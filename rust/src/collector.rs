use std::borrow::Cow;
use std::collections::{BTreeMap, HashMap, HashSet};
use std::fs::{self, File, Metadata};
use std::hash::{DefaultHasher, Hasher};
use std::io::{self, BufRead, BufReader, Read, Seek, SeekFrom};
use std::path::{Path, PathBuf};
use std::time::{Instant, SystemTime, UNIX_EPOCH};

use chrono::{DateTime, NaiveDate, Utc};
use chrono_tz::America::New_York;
use serde::{Deserialize, Serialize};
use serde_json::{Value, value::RawValue};

use crate::quota::{BridgeReading, Context, History, Limits, bridge_connected, codex_limits};
use crate::{Config, atomic_json, now_ms};

#[derive(Clone, Copy, Deserialize, Eq, Hash, Ord, PartialEq, PartialOrd, Serialize)]
#[serde(rename_all = "lowercase")]
pub enum Provider {
    Codex,
    Claude,
}

impl Provider {
    pub fn id(self) -> &'static str {
        match self {
            Self::Codex => "codex",
            Self::Claude => "claude",
        }
    }
    pub fn name(self) -> &'static str {
        match self {
            Self::Codex => "Codex",
            Self::Claude => "Claude Code",
        }
    }
}

#[derive(Clone, Copy, Default, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
struct Usage {
    input: f64,
    output: f64,
    cached: f64,
    cache_write: f64,
    reasoning: f64,
    total: f64,
}

impl Usage {
    fn zip(self, b: Self, op: impl Fn(f64, f64) -> f64) -> Self {
        Self {
            input: op(self.input, b.input),
            output: op(self.output, b.output),
            cached: op(self.cached, b.cached),
            cache_write: op(self.cache_write, b.cache_write),
            reasoning: op(self.reasoning, b.reasoning),
            total: op(self.total, b.total),
        }
    }
}

#[derive(Default, Deserialize)]
#[serde(default)]
struct RawUsage {
    input_tokens: Option<f64>,
    output_tokens: Option<f64>,
    cached_input_tokens: Option<f64>,
    cache_read_input_tokens: Option<f64>,
    cache_write_input_tokens: Option<f64>,
    cache_creation_input_tokens: Option<f64>,
    reasoning_output_tokens: Option<f64>,
    output_tokens_details: Option<ThinkingTokens>,
}

#[derive(Deserialize)]
struct ThinkingTokens {
    thinking_tokens: Option<f64>,
}

impl RawUsage {
    fn counts(&self, provider: Provider) -> Usage {
        let count = |v: Option<f64>| v.unwrap_or(0.0).max(0.0);
        let cached = count(self.cached_input_tokens.or(self.cache_read_input_tokens));
        let cache_write = count(
            self.cache_write_input_tokens
                .or(self.cache_creation_input_tokens),
        );
        let input = count(self.input_tokens)
            + if provider == Provider::Claude {
                cached + cache_write
            } else {
                0.0
            };
        let output = count(self.output_tokens);
        let reasoning = count(
            self.reasoning_output_tokens
                .or_else(|| self.output_tokens_details.as_ref()?.thinking_tokens),
        );
        Usage {
            input,
            output,
            cached,
            cache_write,
            reasoning,
            total: input + output,
        }
    }
}

#[derive(Deserialize, Serialize)]
struct Record {
    time: i64,
    model: Option<String>,
    effort: Option<String>,
    #[serde(flatten)]
    usage: Usage,
}

#[derive(Default, Deserialize, Serialize)]
struct Session {
    id: Option<String>,
    name: Option<String>,
    project: Option<String>,
    parent_id: Option<String>,
    subagent: bool,
    guardian: bool,
    model: Option<String>,
    effort: Option<String>,
    updated_at: i64,
    started_at: i64,
    context: Option<Context>,
    idle: bool,
    entrypoint: Option<String>,
    history_start: Option<i64>,
    records: BTreeMap<String, Record>,
    fallback: BTreeMap<String, Record>,
    baseline: Usage,
    limits: Option<Limits>,
}

fn time_ms(timestamp: Option<&str>) -> i64 {
    timestamp
        .and_then(|s| DateTime::parse_from_rfc3339(s).ok())
        .map_or(0, |d| d.timestamp_millis())
}

fn day(time: i64) -> NaiveDate {
    DateTime::<Utc>::from_timestamp_millis(time)
        .unwrap_or(DateTime::UNIX_EPOCH)
        .with_timezone(&New_York)
        .date_naive()
}

fn project(path: &str) -> Option<String> {
    path.rsplit(['/', '\\'])
        .find(|s| !s.is_empty())
        .map(str::to_owned)
}

fn effort(value: Option<&str>) -> Option<String> {
    let name = value?.trim();
    let mut bytes = name.bytes();
    (name.len() <= 16
        && bytes.next().is_some_and(|b| b.is_ascii_alphabetic())
        && bytes.all(|b| b.is_ascii_alphanumeric() || b == b'_' || b == b'-'))
    .then(|| name.to_ascii_lowercase())
}

#[derive(Deserialize)]
struct CodexRow<'a> {
    #[serde(rename = "type", borrow)]
    kind: Cow<'a, str>,
    #[serde(borrow)]
    timestamp: Option<Cow<'a, str>>,
    ordinal: Option<i64>,
    #[serde(borrow)]
    payload: Option<&'a RawValue>,
}

#[derive(Default, Deserialize)]
#[serde(default)]
struct CodexMeta {
    id: Option<String>,
    timestamp: Option<String>,
    cwd: Option<String>,
    source: Value,
    parent_thread_id: Option<String>,
    thread_source: Option<String>,
    agent_nickname: Option<String>,
    agent_name: Option<String>,
    agent_path: Option<String>,
    subagent_history_start_ordinal: Option<i64>,
}

#[derive(Deserialize)]
struct CodexTurn {
    model: Option<String>,
    #[serde(default)]
    effort: Value,
    #[serde(default)]
    collaboration_mode: Value,
}

#[derive(Deserialize)]
struct CodexRequest {
    thread_id: Option<String>,
    response_id: Option<String>,
    turn_id: Option<String>,
    usage: Option<RawUsage>,
}

#[derive(Deserialize)]
struct CodexEvent<'a> {
    #[serde(rename = "type", borrow)]
    kind: Cow<'a, str>,
    #[serde(borrow)]
    info: Option<&'a RawValue>,
    #[serde(borrow)]
    rate_limits: Option<&'a RawValue>,
}

#[derive(Deserialize)]
struct CodexCount {
    total_token_usage: Option<RawUsage>,
    last_token_usage: Option<RawUsage>,
    model_context_window: Option<f64>,
}

impl Session {
    fn consume_codex(&mut self, line: &[u8], now: i64, history: &mut History) {
        let Ok(row) = serde_json::from_slice::<CodexRow>(line) else {
            return;
        };
        let Some(payload) = row.payload else { return };
        let time = time_ms(row.timestamp.as_deref());
        match row.kind.as_ref() {
            "session_meta" => {
                let Ok(meta) = serde_json::from_str::<CodexMeta>(payload.get()) else {
                    return;
                };
                self.id = meta.id;
                self.started_at = meta.timestamp.as_deref().map_or(time, |s| {
                    let t = time_ms(Some(s));
                    if t == 0 { time } else { t }
                });
                self.project = meta.cwd.as_deref().and_then(project);
                let subagent = meta
                    .source
                    .get("subagent")
                    .filter(|v| !v.is_null() && v.as_bool() != Some(false));
                self.parent_id = meta.parent_thread_id.or_else(|| {
                    Some(
                        subagent?["thread_spawn"]["parent_thread_id"]
                            .as_str()?
                            .to_owned(),
                    )
                });
                self.subagent = subagent.is_some() || self.parent_id.is_some();
                self.name = nonempty(meta.agent_nickname)
                    .or(nonempty(meta.agent_name))
                    .or(nonempty(meta.agent_path));
                self.history_start = meta.subagent_history_start_ordinal;
                self.guardian = meta.thread_source.as_deref() == Some("guardian_review");
            }
            "turn_context" => {
                let Ok(turn) = serde_json::from_str::<CodexTurn>(payload.get()) else {
                    return;
                };
                if let Some(model) = nonempty(turn.model) {
                    self.model = Some(model);
                }
                let level = if turn.effort.is_null() {
                    turn.collaboration_mode["settings"]["reasoning_effort"].as_str()
                } else {
                    turn.effort.as_str()
                };
                if let Some(level) = effort(level) {
                    self.effort = Some(level);
                }
            }
            "token_usage_record" => {
                let Ok(request) = serde_json::from_str::<CodexRequest>(payload.get()) else {
                    return;
                };
                if request.thread_id.is_some() && request.thread_id != self.id {
                    return;
                }
                let id = nonempty(request.response_id).unwrap_or_else(|| {
                    format!(
                        "{}:{}",
                        request.turn_id.as_deref().unwrap_or("undefined"),
                        row.ordinal.unwrap_or(time)
                    )
                });
                let usage = request.usage.unwrap_or_default().counts(Provider::Codex);
                let record = self.record(time, usage);
                self.records.insert(id, record);
                self.updated_at = self.updated_at.max(time);
            }
            "event_msg" => {
                self.updated_at = self.updated_at.max(time);
                let Ok(event) = serde_json::from_str::<CodexEvent>(payload.get()) else {
                    return;
                };
                match event.kind.as_ref() {
                    "task_started" => self.idle = false,
                    "task_complete" | "task_completed" | "turn_aborted" => self.idle = true,
                    "token_count" => self.codex_count(row.ordinal, time, now, event, history),
                    _ => {}
                }
            }
            _ => {}
        }
    }

    fn codex_count(
        &mut self,
        ordinal: Option<i64>,
        time: i64,
        now: i64,
        event: CodexEvent,
        history: &mut History,
    ) {
        if let Some(info) = event
            .info
            .and_then(|raw| serde_json::from_str::<CodexCount>(raw.get()).ok())
            && let Some(total) = info.total_token_usage
        {
            let total = total.counts(Provider::Codex);
            let delta = total.zip(self.baseline, |a, b| (a - b).max(0.0));
            self.baseline = total;
            let inherited = self
                .history_start
                .zip(ordinal)
                .is_some_and(|(start, ordinal)| ordinal < start)
                || time < self.started_at;
            if !inherited && delta.total > 0.0 {
                let key = format!(
                    "{}:{}",
                    self.id.as_deref().unwrap_or("null"),
                    ordinal.unwrap_or(time)
                );
                self.fallback.insert(key, self.record(time, delta));
            }
            if let (Some(size), Some(last)) = (
                info.model_context_window.filter(|s| *s > 0.0),
                info.last_token_usage,
            ) {
                let used = last.counts(Provider::Codex).input;
                self.context = Some(Context {
                    used: Some(used),
                    size: Some(size),
                    percent: (100.0 * used / size).min(100.0),
                    source: "最近一次模型请求".into(),
                });
            }
        }
        if let Some(limits) = event
            .rate_limits
            .and_then(|raw| codex_limits(raw.get(), time, "Codex 会话快照"))
        {
            if time > now - 8 * 86_400_000
                && self
                    .limits
                    .as_ref()
                    .is_none_or(|last| last.windows != limits.windows)
            {
                history.record("codex", &limits);
            }
            self.limits = Some(limits);
        }
    }

    fn record(&self, time: i64, usage: Usage) -> Record {
        Record {
            time,
            model: self.model.clone(),
            effort: self.effort.clone(),
            usage,
        }
    }
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct ClaudeRow<'a> {
    #[serde(rename = "type", borrow)]
    kind: Cow<'a, str>,
    #[serde(borrow)]
    timestamp: Option<Cow<'a, str>>,
    agent_id: Option<String>,
    session_id: Option<String>,
    cwd: Option<String>,
    entrypoint: Option<String>,
    custom_title: Option<String>,
    agent_name: Option<String>,
    #[serde(borrow)]
    message: Option<&'a RawValue>,
    request_id: Option<String>,
    uuid: Option<String>,
    #[serde(default)]
    effort: Value,
    #[serde(default)]
    per_turn_effort: Value,
}

#[derive(Deserialize)]
struct ClaudeMessage {
    id: Option<String>,
    model: Option<String>,
    stop_reason: Option<String>,
    usage: Option<RawUsage>,
}

impl Session {
    fn consume_claude(&mut self, line: &[u8]) {
        let Ok(row) = serde_json::from_slice::<ClaudeRow>(line) else {
            return;
        };
        if !matches!(
            row.kind.as_ref(),
            "assistant" | "user" | "custom-title" | "agent-name"
        ) {
            return;
        }
        let time = time_ms(row.timestamp.as_deref());
        if self.id.is_none() {
            self.id = nonempty(row.agent_id).or(nonempty(row.session_id));
        }
        if let Some(path) = row.cwd.as_deref().and_then(project) {
            self.project = Some(path);
        }
        if let Some(entrypoint) = nonempty(row.entrypoint) {
            self.entrypoint = Some(entrypoint);
        }
        self.updated_at = self.updated_at.max(time);
        if time != 0 && (self.started_at == 0 || self.started_at > time) {
            self.started_at = time;
        }
        match row.kind.as_ref() {
            "custom-title" => self.name = nonempty(row.custom_title),
            "agent-name" if self.name.is_none() => self.name = nonempty(row.agent_name),
            "user" => self.idle = false,
            "assistant" => {
                let Some(message) = row
                    .message
                    .and_then(|raw| serde_json::from_str::<ClaudeMessage>(raw.get()).ok())
                else {
                    return;
                };
                let Some(usage) = message.usage else { return };
                if let Some(model) = nonempty(message.model.clone()) {
                    self.model = Some(model);
                }
                self.idle = matches!(
                    message.stop_reason.as_deref(),
                    Some("end_turn" | "stop_sequence")
                );
                let Some(id) = nonempty(message.id)
                    .or(nonempty(row.request_id))
                    .or(nonempty(row.uuid))
                else {
                    return;
                };
                if message.model.as_deref() == Some("<synthetic>") {
                    return;
                }
                let mut usage = usage.counts(Provider::Claude);
                let previous = self.records.get(&id);
                if let Some(p) = previous {
                    usage = usage.zip(p.usage, f64::max);
                }
                usage.total = usage.input + usage.output;
                let level = if row.effort.is_null() {
                    row.per_turn_effort.as_str()
                } else {
                    row.effort.as_str()
                };
                let effort = effort(level).or_else(|| previous?.effort.clone());
                let time = previous.map_or(time, |p| if p.time == 0 { time } else { p.time });
                self.records.insert(
                    id,
                    Record {
                        time,
                        model: message.model,
                        effort,
                        usage,
                    },
                );
            }
            _ => {}
        }
    }
}

fn nonempty(s: Option<String>) -> Option<String> {
    s.filter(|s| !s.is_empty())
}

#[derive(Deserialize, Eq, PartialEq, Serialize)]
struct FileStamp {
    len: u64,
    modified: Option<u128>,
    created: Option<u128>,
    #[cfg(unix)]
    identity: (u64, u64),
}

impl FileStamp {
    fn from(meta: &Metadata) -> Self {
        fn nanos(time: io::Result<SystemTime>) -> Option<u128> {
            Some(time.ok()?.duration_since(UNIX_EPOCH).ok()?.as_nanos())
        }
        #[cfg(unix)]
        use std::os::unix::fs::MetadataExt;
        Self {
            len: meta.len(),
            modified: nanos(meta.modified()),
            created: nanos(meta.created()),
            #[cfg(unix)]
            identity: (meta.dev(), meta.ino()),
        }
    }

    fn can_append(&self, old: &Self) -> bool {
        #[cfg(unix)]
        if self.identity != old.identity {
            return false;
        }
        self.len > old.len && self.created == old.created && self.modified >= old.modified
    }
}

#[derive(Deserialize, Serialize)]
struct CachedFile {
    provider: Provider,
    offset: u64,
    stamp: Option<FileStamp>,
    boundary: u64,
    session: Session,
}

impl CachedFile {
    fn new(provider: Provider, path: &Path) -> Self {
        let mut session = Session::default();
        if provider == Provider::Claude {
            let parent = path.parent();
            let in_subagents = path
                .components()
                .any(|component| component.as_os_str() == "subagents");
            if in_subagents
                || path
                    .file_name()
                    .is_some_and(|name| name.to_string_lossy().starts_with("agent-"))
            {
                session.subagent = true;
                session.id = path.file_stem().map(|s| s.to_string_lossy().into_owned());
                if in_subagents {
                    session.parent_id = parent
                        .and_then(Path::parent)
                        .and_then(Path::file_name)
                        .map(|s| s.to_string_lossy().into_owned());
                }
            }
        }
        Self {
            provider,
            offset: 0,
            stamp: None,
            boundary: 0,
            session,
        }
    }
}

fn checkpoint(file: &mut File, end: u64) -> io::Result<u64> {
    // A file can be truncated and regrown between scans without changing its identity.
    let mut sample = [0; 256];
    let len = end.min(sample.len() as u64) as usize;
    file.seek(SeekFrom::Start(end - len as u64))?;
    file.read_exact(&mut sample[..len])?;
    let mut hash = DefaultHasher::new();
    hash.write(&sample[..len]);
    Ok(hash.finish())
}

#[derive(Default, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Activity {
    working: bool,
    active_sessions: usize,
    today_tokens: f64,
    today_requests: usize,
    last_active_at: Option<i64>,
    model: Option<String>,
    effort: Option<String>,
    #[serde(skip)]
    latest_at: i64,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ProviderInfo {
    pub id: Provider,
    pub name: &'static str,
    pub connected: bool,
    pub file_count: usize,
    pub error: Option<&'static str>,
    #[serde(skip)]
    pub limits: Option<Limits>,
    pub bridge_connected: bool,
    pub quota_status: Option<&'static str>,
    pub quota_message: Option<&'static str>,
    pub bridge_received_at: Option<i64>,
}

#[derive(Serialize)]
struct Bucket {
    time: i64,
    model: Option<String>,
    effort: Option<String>,
    count: usize,
    #[serde(flatten)]
    usage: Usage,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct PublicSession {
    provider: Provider,
    id: String,
    parent_id: Option<String>,
    kind: &'static str,
    guardian: bool,
    model: Option<String>,
    updated_at: i64,
    started_at: i64,
    context: Option<Context>,
    name: String,
    project: String,
    activity: &'static str,
    records: Vec<Bucket>,
}

#[derive(Default)]
pub struct Collection {
    pub sessions: Vec<PublicSession>,
    pub providers: Vec<ProviderInfo>,
    pub activity: BTreeMap<Provider, Activity>,
    pub collected_at: Option<i64>,
    pub scan_ms: Option<u128>,
    pub reused_files: usize,
}

const INDEX_VERSION: u32 = 1;

pub struct Collector {
    files: BTreeMap<PathBuf, CachedFile>,
    index_dirty: bool,
    scratch: Vec<u8>,
    pub history: History,
}

impl Collector {
    pub fn load(config: &Config) -> Self {
        #[derive(Deserialize)]
        struct Index {
            version: u32,
            files: BTreeMap<PathBuf, CachedFile>,
        }
        let files = File::open(config.index_file())
            .ok()
            .and_then(|f| serde_json::from_reader::<_, Index>(BufReader::new(f)).ok())
            .filter(|index| index.version == INDEX_VERSION)
            .map_or_else(BTreeMap::new, |index| index.files);
        Self {
            files,
            index_dirty: false,
            scratch: Vec::new(),
            history: History::load(&config.history_file()),
        }
    }

    pub fn save(&mut self, config: &Config) -> io::Result<()> {
        if self.index_dirty {
            #[derive(Serialize)]
            struct Index<'a> {
                version: u32,
                files: &'a BTreeMap<PathBuf, CachedFile>,
            }
            atomic_json(
                &config.index_file(),
                &Index {
                    version: INDEX_VERSION,
                    files: &self.files,
                },
            )?;
            self.index_dirty = false;
        }
        self.history.save(&config.history_file())
    }

    fn read(&mut self, path: &Path, provider: Provider, now: i64) -> io::Result<bool> {
        let stamp = FileStamp::from(&fs::metadata(path)?);
        let cached = self
            .files
            .entry(path.into())
            .or_insert_with(|| CachedFile::new(provider, path));
        if cached.provider == provider && cached.stamp.as_ref() == Some(&stamp) {
            return Ok(false);
        }
        let mut file = File::open(path)?;
        let stamp = FileStamp::from(&file.metadata()?);
        if cached.provider != provider
            || cached
                .stamp
                .as_ref()
                .is_none_or(|old| !stamp.can_append(old))
            || cached.offset > stamp.len
            || (cached.offset > 0 && checkpoint(&mut file, cached.offset)? != cached.boundary)
        {
            *cached = CachedFile::new(provider, path);
        }
        file.seek(SeekFrom::Start(cached.offset))?;
        let mut reader = BufReader::with_capacity(128 * 1024, file.take(stamp.len - cached.offset));
        loop {
            self.scratch.clear();
            let bytes = reader.read_until(b'\n', &mut self.scratch)?;
            if self.scratch.last() != Some(&b'\n') {
                break;
            } // Retry an incomplete line on append.
            cached.offset += bytes as u64;
            match provider {
                Provider::Codex => {
                    cached
                        .session
                        .consume_codex(&self.scratch, now, &mut self.history)
                }
                Provider::Claude => cached.session.consume_claude(&self.scratch),
            }
        }
        if self.scratch.capacity() > 1024 * 1024 {
            self.scratch = Vec::new();
        }
        cached.boundary = checkpoint(&mut reader.into_inner().into_inner(), cached.offset)?;
        cached.stamp = Some(stamp);
        Ok(true)
    }

    pub fn collect(&mut self, config: &Config) -> Collection {
        let started = Instant::now();
        let now = now_ms();
        let mut output = Collection::default();
        let mut visible = HashSet::new();
        let mut incomplete = HashSet::new();
        let names = session_names(&config.codex_home);
        let mut bridges = BTreeMap::new();
        for (provider, dir) in [
            (Provider::Codex, config.codex_home.join("sessions")),
            (Provider::Claude, config.claude_home.join("projects")),
        ] {
            let mut files = Vec::new();
            let mut error = if discover(&dir, &mut files).is_err() {
                incomplete.insert(provider);
                Some("无法读取本机会话目录")
            } else {
                None
            };
            files.sort_unstable();
            let mut limits = None;
            let mut last_entry = None;
            let mut entry_time = i64::MIN;
            for path in &files {
                visible.insert(path.clone());
                match self.read(path, provider, now) {
                    Ok(false) => output.reused_files += 1,
                    Ok(true) => self.index_dirty = true,
                    Err(_) => error = Some("部分记录暂时无法读取，将在下次刷新重试"),
                }
                let Some(session) = self
                    .files
                    .get(path)
                    .map(|file| &file.session)
                    .filter(|s| s.id.is_some())
                else {
                    continue;
                };
                if session.entrypoint.is_some() && session.updated_at >= entry_time {
                    last_entry = session.entrypoint.clone();
                    entry_time = session.updated_at;
                }
                if let Some(current) = &session.limits {
                    take_newer(&mut limits, current);
                }
            }
            let (bridge_connected, bridge_received_at, quota_status, quota_message) = if provider
                == Provider::Claude
            {
                bridges = bridge_readings(&config.data_dir);
                let bridge = bridge_connected(config);
                let received = bridges.values().map(|r| r.collected_at).max();
                for reading in bridges.values() {
                    if let Some(current) = reading.limits() {
                        take_newer(&mut limits, &current);
                    }
                }
                let (status, message) = if limits.is_some() {
                    ("available", None)
                } else if last_entry.as_deref() == Some("claude-desktop") && received.is_none() {
                    (
                        "desktop-not-connected",
                        Some(
                            "检测到 Claude 桌面版会话，未收到终端状态栏数据；当前桥接不能自动显示桌面版额度。",
                        ),
                    )
                } else if received.is_some() {
                    (
                        "fields-unavailable",
                        Some("状态栏已运行，但 Claude 未返回额度字段；字段取决于账户类型和版本。"),
                    )
                } else if bridge {
                    (
                        "waiting-for-cli",
                        Some("已安装终端版状态栏桥接，等待 Claude Code CLI 返回数据。"),
                    )
                } else {
                    ("not-connected", Some("尚未接入 Claude Code CLI 状态栏。"))
                };
                (bridge, received, Some(status), message)
            } else {
                (false, None, None, None)
            };
            if let Some(limits) = &limits {
                self.history.record(provider.id(), limits);
            }
            output.providers.push(ProviderInfo {
                id: provider,
                name: provider.name(),
                connected: !files.is_empty(),
                file_count: files.len(),
                error,
                limits,
                bridge_connected,
                quota_status,
                quota_message,
                bridge_received_at,
            });
            output.activity.insert(provider, Activity::default());
        }
        let count = self.files.len();
        self.files
            .retain(|path, file| visible.contains(path) || incomplete.contains(&file.provider));
        self.index_dirty |= count != self.files.len();
        output.sessions = self.aggregate(&names, &bridges, &mut output.activity, &visible, now);
        output.collected_at = Some(now_ms());
        output.scan_ms = Some(started.elapsed().as_millis());
        output
    }

    fn aggregate(
        &self,
        names: &HashMap<String, String>,
        bridges: &BTreeMap<String, BridgeReading>,
        activity: &mut BTreeMap<Provider, Activity>,
        visible: &HashSet<PathBuf>,
        now: i64,
    ) -> Vec<PublicSession> {
        let mut sessions: Vec<_> = self
            .files
            .iter()
            .filter(|(path, file)| visible.contains(*path) && file.session.id.is_some())
            .collect();
        // Match the legacy tie order before deduplicating IDs reused by resumed transcripts.
        sessions.sort_by(|(a_path, a), (b_path, b)| {
            (a.session.started_at, a.session.subagent)
                .cmp(&(b.session.started_at, b.session.subagent))
                .then_with(|| {
                    if a.session.subagent {
                        a_path.cmp(b_path)
                    } else {
                        b_path.cmp(a_path)
                    }
                })
        });
        let mut seen = HashSet::new();
        let mut days = HashMap::new();
        let today = day(now);
        let mut output = Vec::with_capacity(sessions.len());
        for (_, file) in sessions {
            let s = &file.session;
            let provider = file.provider;
            let Some(id) = &s.id else { continue };
            let active = !s.idle && now - s.updated_at < 120_000;
            let act = activity
                .get_mut(&provider)
                .expect("activity was initialized for each provider");
            if !s.guardian {
                act.active_sessions += usize::from(active);
                act.working |= active;
                if s.updated_at > 0 {
                    act.last_active_at = act.last_active_at.max(Some(s.updated_at));
                }
            }
            let first_real = s.records.values().map(|r| r.time).min().unwrap_or(i64::MAX);
            let legacy = s.fallback.iter().filter(|(_, r)| r.time < first_real);
            // The dashboard works at day/model/effort granularity. Deduplicate before aggregating, not in the browser.
            let mut buckets: BTreeMap<_, Bucket> = BTreeMap::new();
            for (id, r) in legacy.chain(s.records.iter()) {
                if !seen.insert((provider, id.as_str())) {
                    continue;
                }
                let date = *days.entry(r.time).or_insert_with(|| day(r.time));
                let bucket = buckets
                    .entry((date, r.model.as_deref(), r.effort.as_deref()))
                    .or_insert_with(|| Bucket {
                        time: r.time,
                        model: r.model.clone(),
                        effort: r.effort.clone(),
                        count: 0,
                        usage: Usage::default(),
                    });
                bucket.time = bucket.time.min(r.time);
                bucket.count += 1;
                bucket.usage = bucket.usage.zip(r.usage, |a, b| a + b);
                if s.guardian || r.time == 0 {
                    continue;
                }
                if r.time > act.latest_at {
                    act.latest_at = r.time;
                    act.model.clone_from(&r.model);
                    act.effort.clone_from(&r.effort);
                }
                if date == today && r.time <= now + 60_000 {
                    act.today_tokens += r.usage.total;
                    act.today_requests += 1;
                }
            }
            let project = s.project.clone().unwrap_or_else(|| "未命名项目".into());
            let name = nonempty(names.get(id).cloned())
                .or_else(|| s.name.clone())
                .unwrap_or_else(|| {
                    format!("{project} · {}", id.chars().take(8).collect::<String>())
                });
            let context = if provider == Provider::Claude {
                bridges
                    .get(id)
                    .filter(|r| r.collected_at >= s.updated_at - 5_000)
                    .and_then(|r| r.context.clone())
                    .or_else(|| s.context.clone())
            } else {
                s.context.clone()
            };
            output.push(PublicSession {
                provider,
                id: id.clone(),
                parent_id: s.parent_id.clone(),
                kind: if s.subagent { "subagent" } else { "session" },
                model: s.model.clone(),
                updated_at: s.updated_at,
                started_at: s.started_at,
                context,
                guardian: s.guardian,
                name,
                project,
                activity: if active { "recent" } else { "idle" },
                records: buckets.into_values().collect(),
            });
        }
        output.sort_by_key(|s| std::cmp::Reverse(s.updated_at));
        output
    }
}

fn take_newer(best: &mut Option<Limits>, current: &Limits) {
    if best
        .as_ref()
        .is_none_or(|b| current.collected_at > b.collected_at)
    {
        *best = Some(current.clone());
    }
}

fn discover(root: &Path, files: &mut Vec<PathBuf>) -> io::Result<()> {
    let entries = match fs::read_dir(root) {
        Ok(entries) => entries,
        Err(e) if e.kind() == io::ErrorKind::NotFound => return Ok(()),
        Err(e) => return Err(e),
    };
    for entry in entries {
        let entry = entry?;
        let kind = entry.file_type()?;
        let path = entry.path();
        if kind.is_dir() {
            discover(&path, files)?;
        } else if kind.is_file() && path.extension().is_some_and(|ext| ext == "jsonl") {
            files.push(path);
        }
    }
    Ok(())
}

fn session_names(home: &Path) -> HashMap<String, String> {
    #[derive(Deserialize)]
    struct Name {
        id: String,
        thread_name: String,
    }
    File::open(home.join("session_index.jsonl"))
        .into_iter()
        .flat_map(|file| BufReader::new(file).lines().map_while(Result::ok))
        .filter_map(|line| serde_json::from_str::<Name>(&line).ok())
        .map(|row| (row.id, row.thread_name))
        .collect()
}

fn bridge_readings(dir: &Path) -> BTreeMap<String, BridgeReading> {
    fs::read_dir(dir)
        .into_iter()
        .flatten()
        .flatten()
        .filter_map(|entry| {
            let name = entry.file_name();
            let name = name.to_str()?;
            if !name.starts_with("claude-status-")
                || !name.ends_with(".json")
                || !entry.file_type().ok()?.is_file()
            {
                return None;
            }
            let file = File::open(entry.path()).ok()?;
            let reading: BridgeReading =
                serde_json::from_reader(BufReader::new(file.take(1024 * 1024))).ok()?;
            Some((reading.session_id.clone(), reading))
        })
        .collect()
}
