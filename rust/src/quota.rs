use std::collections::BTreeMap;
use std::ffi::OsString;
use std::fs::{self, File};
use std::io::{self, BufReader, Read};
use std::path::{Path, PathBuf};
use std::process::Stdio;
use std::time::Duration;

use serde::{Deserialize, Serialize};
use serde_json::{Value, json};
use tokio::io::{AsyncBufReadExt, AsyncWriteExt, Lines};
use tokio::process::{Child, ChildStdin, ChildStdout, Command};

use crate::{Config, atomic_json, now_ms};

#[derive(Clone, Debug, Deserialize, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Window {
    pub name: String,
    pub used_percent: f64,
    pub remaining_percent: f64,
    pub window_minutes: Option<i64>,
    pub resets_at: Option<i64>,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub history: Vec<(i64, f64)>,
}

#[derive(Clone, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Limits {
    pub windows: Vec<Window>,
    plan: Option<String>,
    pub collected_at: i64,
    source: String,
}

#[derive(Default, Deserialize)]
#[serde(default)]
struct RawWindow {
    #[serde(
        rename = "usedPercent",
        alias = "used_percent",
        alias = "used_percentage"
    )]
    used: Option<f64>,
    #[serde(rename = "windowDurationMins", alias = "window_minutes")]
    minutes: Option<i64>,
    #[serde(rename = "resetsAt", alias = "resets_at")]
    resets: Option<f64>,
}

impl RawWindow {
    fn normalize(&self, name: String, fallback_minutes: Option<i64>) -> Option<Window> {
        let used = self.used?.clamp(0.0, 100.0);
        Some(Window {
            name,
            used_percent: used,
            remaining_percent: 100.0 - used,
            window_minutes: self.minutes.or(fallback_minutes),
            resets_at: self.resets.map(|s| (s * 1000.0).round() as i64),
            history: Vec::new(),
        })
    }
}

#[derive(Default, Deserialize)]
#[serde(default, rename_all = "camelCase")]
struct CodexBucket {
    #[serde(alias = "plan_type")]
    plan_type: Option<String>,
    #[serde(alias = "limit_name")]
    limit_name: Option<String>,
    primary: Option<RawWindow>,
    secondary: Option<RawWindow>,
}

#[derive(Default, Deserialize)]
#[serde(default, rename_all = "camelCase")]
struct CodexQuota {
    rate_limits_by_limit_id: Option<BTreeMap<String, Option<CodexBucket>>>,
    rate_limits: Option<CodexBucket>,
    #[serde(flatten)]
    bucket: CodexBucket,
}

pub fn codex_limits(raw: &str, time: i64, source: &str) -> Option<Limits> {
    let raw: CodexQuota = serde_json::from_str(raw).ok()?;
    let buckets = raw.rate_limits_by_limit_id.unwrap_or_else(|| {
        BTreeMap::from([("codex".into(), Some(raw.rate_limits.unwrap_or(raw.bucket)))])
    });
    let mut windows = Vec::new();
    let mut plan = None;
    for (id, bucket) in buckets {
        let Some(bucket) = bucket else { continue };
        if plan.is_none() {
            plan = bucket.plan_type;
        }
        let prefix = if id == "codex" {
            String::new()
        } else {
            format!(
                "{} · ",
                bucket.limit_name.filter(|s| !s.is_empty()).unwrap_or(id)
            )
        };
        for (raw, short, minutes) in [
            (bucket.primary, "短周期", 300),
            (bucket.secondary, "长周期", 10080),
        ] {
            let Some(raw) = raw else { continue };
            let label = match raw.minutes {
                Some(n) if n > 0 && n % 1440 == 0 => format!("{} 天", n / 1440),
                Some(n) if n > 0 && n % 60 == 0 => format!("{} 小时", n / 60),
                Some(n) if n > 0 => format!("{n} 分钟"),
                _ => short.into(),
            };
            windows.extend(raw.normalize(format!("{prefix}{label}"), Some(minutes)));
        }
    }
    (!windows.is_empty()).then(|| Limits {
        windows,
        plan,
        collected_at: time,
        source: source.into(),
    })
}

#[derive(Clone, Deserialize, Serialize)]
pub struct Context {
    pub percent: f64,
    pub size: Option<f64>,
    pub used: Option<f64>,
    pub source: String,
}

const CLAUDE_WINDOWS: [(&str, &str, Option<i64>); 3] = [
    ("five_hour", "5 小时", Some(300)),
    ("seven_day", "7 天", Some(10080)),
    ("spend_limit", "支出额度", None),
];
const CLAUDE_SOURCE: &str = "Claude Code 状态栏";

#[derive(Deserialize, Serialize)]
struct BridgeWindow {
    used_percentage: f64,
    resets_at: Option<f64>,
}

#[derive(Deserialize, Serialize)]
pub struct BridgeReading {
    pub session_id: String,
    #[serde(rename = "collectedAt")]
    pub collected_at: i64,
    rate_limits: BTreeMap<String, BridgeWindow>,
    pub context: Option<Context>,
}

impl BridgeReading {
    pub fn limits(&self) -> Option<Limits> {
        let windows: Vec<_> = CLAUDE_WINDOWS
            .iter()
            .filter_map(|&(key, label, minutes)| {
                let raw = self.rate_limits.get(key)?;
                RawWindow {
                    used: Some(raw.used_percentage),
                    minutes,
                    resets: raw.resets_at,
                }
                .normalize(label.into(), minutes)
            })
            .collect();
        (!windows.is_empty()).then(|| Limits {
            windows,
            plan: None,
            collected_at: self.collected_at,
            source: CLAUDE_SOURCE.into(),
        })
    }
}

#[derive(Deserialize)]
struct StatusLine {
    session_id: Option<String>,
    rate_limits: Option<StatusLimits>,
    context_window: Option<StatusContext>,
}

#[derive(Default, Deserialize)]
struct StatusLimits {
    five_hour: Option<RawWindow>,
    seven_day: Option<RawWindow>,
    spend_limit: Option<RawWindow>,
}

#[derive(Deserialize)]
struct StatusContext {
    used_percentage: Option<f64>,
    context_window_size: Option<f64>,
    total_input_tokens: Option<f64>,
}

pub fn statusline(data_dir: &Path) -> Result<String, Box<dyn std::error::Error>> {
    const MAX_INPUT: u64 = 1024 * 1024;
    let mut input = Vec::new();
    io::stdin()
        .lock()
        .take(MAX_INPUT + 1)
        .read_to_end(&mut input)?;
    if input.len() as u64 > MAX_INPUT {
        return Err("status line input too large".into());
    }
    let input: StatusLine = serde_json::from_slice(&input)?;
    let id = input.session_id.unwrap_or_default();
    let id: String = id
        .chars()
        .filter(|c| c.is_ascii_alphanumeric() || *c == '_' || *c == '-')
        .take(100)
        .collect();
    let session_id = if id.is_empty() { "current".into() } else { id };
    let mut limits = BTreeMap::new();
    let mut output = vec!["Agent Meter".to_string()];
    let raw = input.rate_limits.unwrap_or_default();
    for ((key, label, minutes), raw) in
        CLAUDE_WINDOWS
            .into_iter()
            .zip([raw.five_hour, raw.seven_day, raw.spend_limit])
    {
        let Some(window) = raw.and_then(|x| x.normalize(label.into(), minutes)) else {
            continue;
        };
        limits.insert(
            key.into(),
            BridgeWindow {
                used_percentage: window.used_percent,
                resets_at: window.resets_at.map(|m| m as f64 / 1000.0),
            },
        );
        if let Some(short) = match key {
            "five_hour" => Some("5h"),
            "seven_day" => Some("7d"),
            _ => None,
        } {
            output.push(format!(
                "{short} left {:.0}%",
                window.remaining_percent.round()
            ));
        }
    }
    let context = input.context_window.and_then(|cw| {
        let percent = cw.used_percentage?.clamp(0.0, 100.0);
        output.push(format!("ctx {:.0}%", percent.round()));
        Some(Context {
            percent,
            size: cw.context_window_size,
            used: cw.total_input_tokens,
            source: CLAUDE_SOURCE.into(),
        })
    });
    let file = data_dir.join(format!("claude-status-{session_id}.json"));
    atomic_json(
        &file,
        &BridgeReading {
            session_id,
            collected_at: now_ms(),
            rate_limits: limits,
            context,
        },
    )?;
    Ok(output.join(" | "))
}

fn shell_quote(value: &str) -> String {
    if cfg!(windows) {
        format!("'{}'", value.replace('\'', "''"))
    } else {
        format!("'{}'", value.replace('\'', "'\\''"))
    }
}

pub fn setup_command(exe: &Path, data_dir: &Path) -> String {
    let bin = shell_quote(&exe.to_string_lossy());
    let dir = shell_quote(&data_dir.to_string_lossy());
    format!(
        "{}{bin} claude-connect {dir}",
        if cfg!(windows) { "& " } else { "" }
    )
}

fn bridge_command(exe: &Path, data_dir: &Path) -> Result<String, &'static str> {
    let bin = shell_quote(&exe.to_string_lossy());
    let dir = shell_quote(&data_dir.to_string_lossy());
    let command = format!("{bin} claude-statusline {dir}");
    if cfg!(windows) {
        // Claude Code uses Git Bash or PowerShell on Windows. Forward only the status JSON on stdin.
        let command = command.replace('\\', "/");
        if command.contains(['$', '`', '\n', '\r', '"']) {
            return Err("unsupported characters in status line path");
        }
        return Ok(format!(
            "powershell.exe -NoProfile -NonInteractive -Command \"[Console]::In.ReadToEnd() | & {command}\""
        ));
    }
    Ok(command)
}

pub fn connect_bridge(config: &Config, remove: bool) -> Result<(), Box<dyn std::error::Error>> {
    let path = config.claude_home.join("settings.json");
    if fs::symlink_metadata(&path).is_ok_and(|m| m.file_type().is_symlink()) {
        return Err("settings.json is a symlink; configure the status line manually".into());
    }
    let existing = match File::open(&path) {
        Ok(file) => Some(serde_json::from_reader::<_, Value>(BufReader::new(file))?),
        Err(e) if e.kind() == io::ErrorKind::NotFound => None,
        Err(e) => return Err(e.into()),
    };
    let mut settings = existing.clone().unwrap_or_else(|| json!({}));
    let object = settings
        .as_object_mut()
        .ok_or("settings.json is not a JSON object")?;
    let command = bridge_command(&config.exe, &config.data_dir)?;
    let previous = object.get("statusLine").filter(|v| !v.is_null());
    let ours = previous.and_then(|v| v["command"].as_str()) == Some(command.as_str());
    if remove {
        if !ours {
            println!("No matching Agent Meter status line; settings untouched.");
            return Ok(());
        }
        object.remove("statusLine");
    } else {
        if ours {
            println!("Claude Code is already connected.");
            return Ok(());
        }
        if previous.is_some() {
            return Err("an existing status line was not changed".into());
        }
        object.insert(
            "statusLine".into(),
            json!({"type": "command", "command": command}),
        );
    }
    if let Some(existing) = existing {
        let backup = path.with_extension(format!("json.agent-meter-{}.bak", now_ms()));
        atomic_json(&backup, &existing)?;
        println!("Settings backup: {}", backup.display());
    }
    atomic_json(&path, &settings)?;
    println!(
        "{}",
        if remove {
            "Agent Meter status line removed."
        } else {
            "Claude Code status line connected; reopen the CLI."
        }
    );
    Ok(())
}

pub fn bridge_connected(config: &Config) -> bool {
    File::open(config.claude_home.join("settings.json"))
        .ok()
        .and_then(|f| serde_json::from_reader::<_, Value>(BufReader::new(f)).ok())
        .and_then(|settings| {
            let command = settings["statusLine"]["command"].as_str()?;
            Some(
                bridge_command(&config.exe, &config.data_dir)
                    .is_ok_and(|expected| command == expected),
            )
        })
        .unwrap_or(false)
}

pub struct Rpc {
    _child: Child,
    input: ChildStdin,
    output: Lines<tokio::io::BufReader<ChildStdout>>,
    id: u32,
}

impl Rpc {
    pub async fn connect(executable: &OsString) -> io::Result<Self> {
        let mut command = Command::new(executable);
        #[cfg(windows)]
        command.creation_flags(0x0800_0000); // CREATE_NO_WINDOW
        let mut child = command
            .args(["app-server", "--listen", "stdio://"])
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::null())
            .kill_on_drop(true)
            .spawn()?;
        let mut rpc = Self {
            input: child
                .stdin
                .take()
                .ok_or_else(|| io::Error::other("no App Server stdin"))?,
            output: tokio::io::BufReader::new(
                child
                    .stdout
                    .take()
                    .ok_or_else(|| io::Error::other("no App Server stdout"))?,
            )
            .lines(),
            _child: child,
            id: 0,
        };
        rpc.request("initialize", json!({"clientInfo": {"name": "agent_meter", "title": "Agent Meter", "version": env!("CARGO_PKG_VERSION")}})).await?;
        rpc.send(json!({"method": "initialized", "params": {}}))
            .await?;
        Ok(rpc)
    }

    async fn send(&mut self, request: Value) -> io::Result<()> {
        let mut bytes = serde_json::to_vec(&request)?;
        bytes.push(b'\n');
        self.input.write_all(&bytes).await
    }

    async fn request(&mut self, method: &str, params: Value) -> io::Result<Value> {
        self.id = self.id.wrapping_add(1);
        let id = self.id;
        tokio::time::timeout(Duration::from_secs(12), async {
            self.send(json!({"id": id, "method": method, "params": params}))
                .await?;
            while let Some(line) = self.output.next_line().await? {
                let Ok(mut response) = serde_json::from_str::<Value>(&line) else {
                    continue;
                };
                if response["id"].as_u64() != Some(u64::from(id)) {
                    continue;
                }
                if let Some(result) = response.get_mut("result") {
                    return Ok(result.take());
                }
                return Err(io::Error::other("App Server rejected the request"));
            }
            Err(io::Error::other("App Server ended"))
        })
        .await
        .map_err(|_| io::Error::new(io::ErrorKind::TimedOut, "App Server timed out"))?
    }

    pub async fn read_limits(&mut self) -> io::Result<Limits> {
        let result = self.request("account/rateLimits/read", json!({})).await?;
        codex_limits(&result.to_string(), now_ms(), "Codex 官方额度接口")
            .ok_or_else(|| io::Error::other("no quota windows"))
    }
}

pub fn codex_binary(home: &Path) -> OsString {
    if let Some(value) = std::env::var_os("CODEX_BINARY").filter(|s| !s.is_empty()) {
        return value;
    }
    if cfg!(target_os = "macos") {
        let apps = [PathBuf::from("/Applications"), home.join("Applications")];
        let candidates = apps
            .iter()
            .flat_map(|root| {
                ["Codex.app", "ChatGPT.app"]
                    .map(|app| root.join(app).join("Contents/Resources/codex"))
            })
            .chain([
                PathBuf::from("/opt/homebrew/bin/codex"),
                PathBuf::from("/usr/local/bin/codex"),
                home.join(".local/bin/codex"),
            ]);
        if let Some(found) = candidates.into_iter().find(|p| p.is_file()) {
            return found.into_os_string();
        }
    }
    if cfg!(windows) {
        let local = std::env::var_os("LOCALAPPDATA")
            .map(PathBuf::from)
            .unwrap_or_else(|| home.join("AppData/Local"));
        let found = fs::read_dir(local.join("OpenAI/Codex/bin"))
            .into_iter()
            .flatten()
            .flatten()
            .map(|entry| entry.path().join("codex.exe"))
            .filter_map(|p| Some((p.metadata().ok()?.modified().ok()?, p)))
            .max();
        return found
            .map(|(_, p)| p.into_os_string())
            .unwrap_or_else(|| "codex.exe".into());
    }
    "codex".into()
}

const SAME_RESET_MS: i64 = 3 * 60_000;

#[derive(Clone, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
struct Series {
    key: String,
    resets_at: i64,
    points: Vec<(i64, f64)>,
}

#[derive(Clone, Default)]
pub struct History {
    series: BTreeMap<String, Series>,
    dirty: bool,
}

impl History {
    pub fn load(file: &Path) -> Self {
        #[derive(Deserialize)]
        struct Saved {
            series: Vec<Series>,
        }
        let saved = File::open(file)
            .ok()
            .and_then(|f| serde_json::from_reader::<_, Saved>(BufReader::new(f)).ok());
        let mut history = Self::default();
        if let Some(saved) = saved {
            history.series = saved
                .series
                .into_iter()
                .filter(|s| s.points.len() <= 2000 && s.points.windows(2).all(|w| w[0].0 < w[1].0))
                .map(|s| (s.key.clone(), s))
                .collect();
        }
        history
    }

    fn key(provider: &str, window: &Window, minutes: i64) -> String {
        format!("{provider}|{}|{minutes}", window.name)
    }

    pub fn record(&mut self, provider: &str, limits: &Limits) {
        let time = limits.collected_at;
        for window in &limits.windows {
            let (Some(reset), Some(minutes)) = (window.resets_at, window.window_minutes) else {
                continue;
            };
            if minutes <= 0
                || time < reset.saturating_sub(minutes.saturating_mul(60_000))
                || time > reset
            {
                continue;
            }
            let key = Self::key(provider, window, minutes);
            let series = self.series.entry(key.clone()).or_insert_with(|| Series {
                key,
                resets_at: reset,
                points: Vec::new(),
            });
            if series.resets_at.abs_diff(reset) > SAME_RESET_MS as u64 {
                if reset < series.resets_at {
                    continue;
                }
                series.resets_at = reset;
                series.points.clear();
            }
            let points = &mut series.points;
            let value = (window.remaining_percent * 10.0).round() / 10.0;
            match points.binary_search_by_key(&time, |p| p.0) {
                Ok(i) if points[i].1 == value => continue,
                Ok(i) => points[i].1 = value,
                Err(i) if i > 0 && points[i - 1].1 == value => continue,
                Err(i) => points.insert(i, (time, value)),
            }
            points.dedup_by(|a, b| a.1 == b.1);
            if points.len() > 2000 {
                points.drain(..points.len() - 2000);
            }
            self.dirty = true;
        }
    }

    pub fn attach(&self, provider: &str, limits: &mut Limits) {
        for window in &mut limits.windows {
            let (Some(reset), Some(minutes)) = (window.resets_at, window.window_minutes) else {
                continue;
            };
            if let Some(series) = self
                .series
                .get(&Self::key(provider, window, minutes))
                .filter(|s| s.resets_at.abs_diff(reset) <= SAME_RESET_MS as u64)
            {
                window.history.clone_from(&series.points);
            }
        }
    }

    pub fn prune(&mut self, now: i64) {
        let count = self.series.len();
        self.series
            .retain(|_, series| series.resets_at >= now - 3_600_000);
        self.dirty |= self.series.len() != count;
    }

    pub fn save(&mut self, file: &Path) -> io::Result<()> {
        if !self.dirty {
            return Ok(());
        }
        #[derive(Serialize)]
        struct Saved<'a> {
            version: u8,
            series: Vec<&'a Series>,
        }
        atomic_json(
            file,
            &Saved {
                version: 1,
                series: self.series.values().collect(),
            },
        )?;
        self.dirty = false;
        Ok(())
    }
}
