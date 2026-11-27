mod collector;
mod quota;

use std::env;
use std::fs::{self, OpenOptions};
use std::io::{self, BufWriter, Write};
use std::net::Ipv4Addr;
use std::path::{Path, PathBuf};
use std::sync::{Arc, RwLock, mpsc};
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

use axum::extract::{Request, State};
use axum::http::{Method, StatusCode, header};
use axum::middleware::{self, Next};
use axum::response::{IntoResponse, Response};
use axum::{Json, Router, routing::get};
use collector::{Activity, Collection, Collector, Provider, ProviderInfo, SessionView};
use quota::{History, Limits, Rpc, codex_binary};
use serde::Serialize;
use serde_json::json;

const TIME_ZONE: &str = "America/New_York";
const REFRESH: Duration = Duration::from_secs(5);

pub struct Config {
    home: PathBuf,
    pub codex_home: PathBuf,
    pub claude_home: PathBuf,
    pub data_dir: PathBuf,
    pub exe: PathBuf,
}

impl Config {
    fn load(data_dir: Option<PathBuf>) -> io::Result<Self> {
        let home = env::home_dir().ok_or_else(|| io::Error::other("home directory not found"))?;
        let data_dir = data_dir
            .or_else(|| env_path("AGENT_HUD_DATA_DIR"))
            .unwrap_or_else(|| PathBuf::from(".data/rust"));
        let data_dir = if data_dir.is_absolute() {
            data_dir
        } else {
            env::current_dir()?.join(data_dir)
        };
        Ok(Self {
            codex_home: env_path("CODEX_HOME").unwrap_or_else(|| home.join(".codex")),
            claude_home: env_path("CLAUDE_CONFIG_DIR").unwrap_or_else(|| home.join(".claude")),
            home,
            data_dir,
            exe: env::current_exe()?,
        })
    }

    fn index_file(&self) -> PathBuf {
        self.data_dir.join("rust-index.json")
    }
    fn history_file(&self) -> PathBuf {
        self.data_dir.join("quota-history.json")
    }
}

fn env_path(key: &str) -> Option<PathBuf> {
    env::var_os(key)
        .filter(|s| !s.is_empty())
        .map(PathBuf::from)
}

pub fn now_ms() -> i64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_millis() as i64
}

pub fn atomic_json(path: &Path, value: &impl Serialize) -> io::Result<()> {
    let parent = path
        .parent()
        .ok_or_else(|| io::Error::other("missing data directory"))?;
    fs::create_dir_all(parent)?;
    let mut name = path.as_os_str().to_owned();
    name.push(format!(".{}.tmp", std::process::id()));
    let temporary = PathBuf::from(name);
    let mut options = OpenOptions::new();
    options.write(true).create_new(true);
    #[cfg(unix)]
    {
        use std::os::unix::fs::OpenOptionsExt;
        options.mode(0o600);
    }
    let mut output = BufWriter::new(options.open(&temporary)?);
    let result = serde_json::to_writer(&mut output, value)
        .map_err(io::Error::from)
        .and_then(|()| output.flush());
    drop(output);
    let result = result.and_then(|()| fs::rename(&temporary, path));
    if result.is_err() {
        let _ = fs::remove_file(&temporary);
    }
    result
}

#[derive(Default)]
struct Data {
    collection: Collection,
    history: History,
    codex: Option<Limits>,
    quota_error: bool,
}

#[derive(Clone)]
struct App {
    data: Arc<RwLock<Data>>,
    host: String,
    local_host: String,
    origin: String,
    local_origin: String,
    setup_command: String,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct ProviderView<'a> {
    #[serde(flatten)]
    info: &'a ProviderInfo,
    limits: Option<Limits>,
    quota_error: Option<&'static str>,
    #[serde(skip_serializing_if = "Option::is_none")]
    desktop_connection: Option<DesktopConnection>,
    #[serde(skip_serializing_if = "Option::is_none")]
    activity: Option<&'a Activity>,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct DesktopConnection {
    enabled: bool,
    status: &'static str,
    next_attempt_at: Option<i64>,
}

impl Data {
    fn providers(&self, widget: bool) -> Vec<ProviderView<'_>> {
        self.collection
            .providers
            .iter()
            .map(|info| {
                let mut limits = info.limits.clone();
                if info.id == Provider::Codex
                    && let Some(live) = &self.codex
                    && limits
                        .as_ref()
                        .is_none_or(|l| l.collected_at < live.collected_at)
                {
                    limits = Some(live.clone());
                }
                if !widget && let Some(limits) = &mut limits {
                    self.history.attach(info.id.id(), limits);
                }
                ProviderView {
                    info,
                    limits,
                    quota_error: (info.id == Provider::Codex && self.quota_error)
                        .then_some("官方额度接口暂不可用，显示最近会话快照"),
                    desktop_connection: (info.id == Provider::Claude).then_some(
                        DesktopConnection {
                            enabled: false,
                            status: "unsupported",
                            next_attempt_at: None,
                        },
                    ),
                    activity: widget
                        .then(|| self.collection.activity.get(&info.id))
                        .flatten(),
                }
            })
            .collect()
    }
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct Snapshot<'a> {
    providers: Vec<ProviderView<'a>>,
    #[serde(skip_serializing_if = "Option::is_none")]
    sessions: Option<Vec<SessionView<'a>>>,
    collected_at: Option<i64>,
    loading: bool,
    time_zone: &'static str,
    #[serde(skip_serializing_if = "Option::is_none")]
    refresh_seconds: Option<u64>,
}

#[derive(PartialEq)]
enum SnapshotView {
    Legacy,
    Summary,
    Widget,
}

fn snapshot(app: App, view: SnapshotView) -> Response {
    let data = app.data.read().expect("data lock poisoned");
    let widget = view == SnapshotView::Widget;
    Json(Snapshot {
        providers: data.providers(widget),
        sessions: (!widget).then(|| {
            data.collection
                .sessions
                .iter()
                .map(|s| s.view(view == SnapshotView::Summary))
                .collect()
        }),
        collected_at: data.collection.collected_at,
        loading: data.collection.collected_at.is_none(),
        time_zone: TIME_ZONE,
        refresh_seconds: (!widget).then_some(REFRESH.as_secs()),
    })
    .into_response()
}

async fn health(State(app): State<App>) -> impl IntoResponse {
    let data = app.data.read().expect("data lock poisoned");
    Json(
        json!({"ok": true, "backend": "rust", "loading": data.collection.collected_at.is_none(),
        "scanMs": data.collection.scan_ms, "reusedFiles": data.collection.reused_files}),
    )
}

async fn local_only(State(app): State<App>, req: Request, next: Next) -> Response {
    let headers = req.headers();
    let host = headers.get(header::HOST).and_then(|v| v.to_str().ok());
    let origin = headers.get(header::ORIGIN);
    let origin_ok =
        origin.is_none_or(|v| v == app.origin.as_str() || v == app.local_origin.as_str());
    let mut res =
        if host != Some(app.host.as_str()) && host != Some(app.local_host.as_str()) || !origin_ok {
            (StatusCode::FORBIDDEN, "Local access only").into_response()
        } else if req.method() != Method::GET {
            (StatusCode::METHOD_NOT_ALLOWED, [(header::ALLOW, "GET")]).into_response()
        } else {
            next.run(req).await
        };
    for (name, value) in [
        ("cache-control", "no-store"),
        ("x-content-type-options", "nosniff"),
        ("x-frame-options", "DENY"),
        ("referrer-policy", "no-referrer"),
        (
            "content-security-policy",
            "default-src 'self'; script-src 'self'; style-src 'self' 'unsafe-inline'; connect-src 'self'; img-src 'self' data:; frame-ancestors 'none'; base-uri 'none'; object-src 'none'",
        ),
    ] {
        res.headers_mut()
            .insert(name, header::HeaderValue::from_static(value));
    }
    res
}

async fn asset(req: Request) -> Response {
    macro_rules! file {
        ($name:literal, $mime:literal) => {
            (
                [(header::CONTENT_TYPE, $mime)],
                &include_bytes!(concat!("../../public/", $name))[..],
            )
                .into_response()
        };
    }
    match req.uri().path() {
        "/" => file!("index.html", "text/html; charset=utf-8"),
        "/app.js" => file!("app.js", "text/javascript; charset=utf-8"),
        "/i18n.js" => file!("i18n.js", "text/javascript; charset=utf-8"),
        "/quota-display.js" => file!("quota-display.js", "text/javascript; charset=utf-8"),
        "/pace.js" => file!("pace.js", "text/javascript; charset=utf-8"),
        "/styles.css" => file!("styles.css", "text/css; charset=utf-8"),
        "/icon.svg" => file!("icon.svg", "image/svg+xml"),
        _ => (StatusCode::NOT_FOUND, "Not found").into_response(),
    }
}

fn scan_loop(config: Config, data: Arc<RwLock<Data>>, stop: mpsc::Receiver<()>) {
    let mut collector = Collector::load(&config);
    let mut last_save = None::<Instant>;
    loop {
        let collection = collector.collect(&config);
        {
            let mut state = data.write().expect("data lock poisoned");
            if let Some(limits) = &state.codex {
                collector.history.record("codex", limits);
            }
            collector.history.prune(now_ms());
            state.collection = collection;
            state.history = collector.history.clone();
        }
        if last_save.is_none_or(|t| t.elapsed() >= Duration::from_secs(60)) {
            if let Err(e) = collector.save(&config) {
                eprintln!("Agent Meter could not save its index: {e}");
            }
            last_save = Some(Instant::now());
        }
        if !matches!(
            stop.recv_timeout(REFRESH),
            Err(mpsc::RecvTimeoutError::Timeout)
        ) {
            break;
        }
    }
    if let Err(e) = collector.save(&config) {
        eprintln!("Agent Meter could not save its index: {e}");
    }
}

async fn poll_codex(home: PathBuf, data: Arc<RwLock<Data>>) {
    if env::var_os("AGENT_HUD_DISABLE_RPC").is_some_and(|v| !v.is_empty()) {
        return;
    }
    let mut rpc = None;
    loop {
        let result = async {
            if rpc.is_none() {
                rpc = Some(Rpc::connect(&codex_binary(&home)).await?);
            }
            rpc.as_mut().expect("connected RPC").read_limits().await
        }
        .await;
        {
            let mut state = data.write().expect("data lock poisoned");
            match result {
                Ok(limits) => {
                    state.codex = Some(limits);
                    state.quota_error = false;
                }
                Err(_) => {
                    rpc = None;
                    state.quota_error = true;
                }
            }
        }
        tokio::time::sleep(Duration::from_secs(60)).await;
    }
}

async fn shutdown() {
    #[cfg(unix)]
    if let Ok(mut terminate) =
        tokio::signal::unix::signal(tokio::signal::unix::SignalKind::terminate())
    {
        tokio::select! { _ = tokio::signal::ctrl_c() => {}, _ = terminate.recv() => {} }
        return;
    }
    let _ = tokio::signal::ctrl_c().await;
}

async fn serve(config: Config) -> Result<(), Box<dyn std::error::Error>> {
    let port: u16 = match env::var("PORT") {
        Ok(port) if !port.is_empty() => port.parse()?,
        _ => 4318,
    };
    if port == 0 {
        return Err("PORT must be between 1 and 65535".into());
    }
    let listener = tokio::net::TcpListener::bind((Ipv4Addr::LOCALHOST, port)).await?;
    let host = format!("127.0.0.1:{port}");
    let local_host = format!("localhost:{port}");
    let data = Arc::new(RwLock::new(Data::default()));
    let app = App {
        data: data.clone(),
        origin: format!("http://{host}"),
        local_origin: format!("http://{local_host}"),
        host,
        local_host,
        setup_command: quota::setup_command(&config.exe, &config.data_dir),
    };
    let router = Router::new()
        .route(
            "/api/snapshot",
            get(|State(app): State<App>, req: Request| async move {
                let view = if req.uri().query() == Some("view=summary") {
                    SnapshotView::Summary
                } else {
                    SnapshotView::Legacy
                };
                snapshot(app, view)
            }),
        )
        .route(
            "/api/quotas",
            get(|State(app): State<App>| async { snapshot(app, SnapshotView::Widget) }),
        )
        .route("/api/health", get(health))
        .route(
            "/api/setup",
            get(|State(app): State<App>| async move {
                Json(json!({"claudeCommand": app.setup_command}))
            }),
        )
        .fallback(asset)
        .layer(middleware::from_fn_with_state(app.clone(), local_only))
        .with_state(app);
    println!("Agent Meter (Rust): http://127.0.0.1:{port}");
    let quotas = tokio::spawn(poll_codex(config.home.clone(), data.clone()));
    let (send, receive) = mpsc::channel();
    let scan = tokio::task::spawn_blocking(move || scan_loop(config, data, receive));
    let result = axum::serve(listener, router)
        .with_graceful_shutdown(shutdown())
        .await;
    quotas.abort();
    let _ = quotas.await;
    let _ = send.send(());
    scan.await?;
    result?;
    Ok(())
}

fn run() -> Result<(), Box<dyn std::error::Error>> {
    let mut args = env::args_os().skip(1);
    let command = args.next().unwrap_or_else(|| "serve".into());
    let data_dir = args.next().map(PathBuf::from);
    if args.next().is_some() {
        return Err("too many arguments (see --help)".into());
    }
    match command.to_str() {
        Some("--version" | "-V") => println!("agent-meter {} (Rust)", env!("CARGO_PKG_VERSION")),
        Some("--help" | "-h") => println!(
            "agent-meter [serve|claude-connect|claude-disconnect|claude-statusline] [data-directory]\nPORT sets the loopback port (default 4318)."
        ),
        Some("serve") => tokio::runtime::Builder::new_multi_thread()
            .worker_threads(2)
            .enable_all()
            .build()?
            .block_on(serve(Config::load(data_dir)?))?,
        Some("claude-statusline") => {
            let output = Config::load(data_dir)
                .ok()
                .and_then(|config| quota::statusline(&config.data_dir).ok());
            println!(
                "{}",
                output
                    .as_deref()
                    .unwrap_or("Agent Meter | waiting for usage")
            );
        }
        Some("claude-connect" | "claude-disconnect") => {
            quota::connect_bridge(&Config::load(data_dir)?, command == "claude-disconnect")?
        }
        _ => return Err("unknown command (see --help)".into()),
    }
    Ok(())
}

fn main() -> std::process::ExitCode {
    match run() {
        Ok(()) => std::process::ExitCode::SUCCESS,
        Err(e) => {
            eprintln!("Agent Meter: {e}");
            std::process::ExitCode::FAILURE
        }
    }
}
