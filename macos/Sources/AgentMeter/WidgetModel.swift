import AppKit
import SwiftUI
import AgentMeterCore

// The parts of the widget the pointer can land on.
enum Hit: Hashable { case codexTile, claudeTile, codexRing, claudeRing, language, pin, more }

// Everything the widget shows, read from the local service every 5 seconds.
@MainActor
final class WidgetModel: ObservableObject {
    let options: Options
    @Published var snapshot: Snapshot?
    @Published var online = false
    @Published var state: WidgetState
    @Published var now = Quota.now()
    @Published var visible = true
    @Published var hover: Hit?
    @Published var pressed: Hit?
    @Published var frames: [Hit: CGRect] = [:]
    // Runs a button's action; set by the controller, used by VoiceOver's press as well.
    var perform: ((Hit) -> Void)?
    private var timer: Timer?
    private var busy = false, failedFetches = 0, lastServiceStart = 0.0
    private let session: URLSession

    init(options: Options) {
        self.options = options
        self.state = WidgetModel.load(options.root)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 4
        configuration.connectionProxyDictionary = [:]
        self.session = URLSession(configuration: configuration)
    }

    var vertical: Bool { state.dock == "left" || state.dock == "right" }
    // Hidden widgets don't animate, and neither does anything when Reduce Motion is on.
    var animating: Bool { visible && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
    func provider(_ id: String) -> Provider? { snapshot?.provider(id) }
    func rings(_ id: String) -> RingSet { Quota.rings(provider(id), now: now, online: online, showInner: state.center == "inner") }
    func mood(_ id: String) -> PetMood { PetMood.of(provider(id), lowest: rings(id).lowest, online: online, now: now) }
    func card(_ id: String) -> CardModel { CardModel.build(provider(id), codex: id == "codex", now: now, online: online, mood: mood(id)) }
    var switchable: Bool { rings("codex").inner != nil || rings("claude").inner != nil }
    var hasTicks: Bool { rings("codex").outer.pace != nil || rings("claude").outer.pace != nil }

    // What hovering the empty glass explains, as on Windows.
    var tooltip: String {
        let scanStale = snapshot != nil && (snapshot?.collectedAt.map { now - $0 > 30000 } ?? true)
        var text = Lang.t("拖动可移动 · 拖到屏幕左右边缘变为竖排 · ⋯ 打开菜单\n", "Drag to move · drop against the left or right edge for a column · ⋯ opens the menu\n")
        if !online { text += Lang.t("本地服务离线，正在自动重启；显示的是最后一次快照", "Local service offline, restarting automatically; showing the last snapshot") }
        else if snapshot?.loading == true { text += Lang.t("正在读取额度", "Reading quotas") }
        else if scanStale { text += Lang.t("会话扫描延迟，额度不受影响", "Session scan delayed; quotas are unaffected") }
        else { text += Lang.t("每 5 秒读取本地快照；平台额度按各自频率更新", "Reads the local snapshot every 5 s; each platform's quota updates on its own schedule") }
        if switchable { text += Lang.t("\n外圈 5 小时、内圈 7 天；点击圆环切换中间显示哪一个", "\nOuter ring 5-hour, inner ring 7-day; click a ring to switch which one the middle shows") }
        if hasTicks { text += Lang.t("\n圆环上的刻度：均匀使用时此刻应剩的位置", "\nThe tick on a ring: where even use would leave it now") }
        return text + Lang.t("\n悬停宠物或圆环查看该 agent 的详情", "\nHover a pet or ring for that agent's details")
    }

    func tooltip(for hit: Hit) -> String? {
        switch hit {
        case .language: return Lang.english ? "切换到中文" : "Switch to English"
        case .pin: return state.pinned ? Lang.t("已置顶 · 点击取消置顶", "Pinned · click to unpin") : Lang.t("未置顶 · 点击置顶", "Not pinned · click to pin")
        case .more: return Lang.t("更多选项", "More options")
        default: return nil
        }
    }

    func start() {
        fetch()
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.fetch() }
        }
    }
    func stop() { timer?.invalidate(); save() }

    func fetch() {
        if busy { return }
        busy = true
        let url = options.server.appendingPathComponent("api/quotas")
        session.dataTask(with: url) { data, _, _ in
            let next = data.flatMap { try? JSONDecoder().decode(Snapshot.self, from: $0) }
            Task { @MainActor in self.finish(next) }
        }.resume()
    }

    private func finish(_ next: Snapshot?) {
        busy = false
        now = Quota.now()
        if let next, next.providers != nil { snapshot = next; online = true; failedFetches = 0 }
        else {
            online = false
            failedFetches += 1
            if failedFetches >= 2 { startService() }
        }
    }

    // The service can die with whatever launched it (a closed terminal). The widget runs on its own, so it
    // brings the service back through start.sh, at most once a minute.
    func startService() {
        let time = Quota.now()
        if time - lastServiceStart < 60000 { return }
        lastServiceStart = time
        let script = options.root.appendingPathComponent("start.sh")
        guard FileManager.default.fileExists(atPath: script.path) else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [script.path, "--no-browser"]
        process.currentDirectoryURL = options.root
        var environment = ProcessInfo.processInfo.environment
        environment["PORT"] = String(options.server.port ?? 4318)
        process.environment = environment
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
    }

    // Clicking a ring switches what the middle of every ring shows, 5 hours or 7 days.
    func toggleCenter() { state.center = state.center == "inner" ? "outer" : "inner"; save() }

    func setLanguage(_ value: String) { state.language = value; Lang.apply(value); save(); objectWillChange.send() }

    static func stateURL(_ root: URL) -> URL { root.appendingPathComponent(".data").appendingPathComponent("widget-state.json") }
    static func load(_ root: URL) -> WidgetState {
        guard let data = try? Data(contentsOf: stateURL(root)), let state = try? JSONDecoder().decode(WidgetState.self, from: data) else { return WidgetState() }
        return state
    }
    func save() {
        if options.preview != nil { return }
        let url = WidgetModel.stateURL(options.root)
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(state) { try? data.write(to: url, options: .atomic) }
    }

    func open(_ address: String) { if let url = URL(string: address) { NSWorkspace.shared.open(url) } }
    func openDashboard() { NSWorkspace.shared.open(options.server) }
}
