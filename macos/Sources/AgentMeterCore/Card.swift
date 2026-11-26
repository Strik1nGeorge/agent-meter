import Foundation

// One quota window in the hover card: its name and ring, what is left, its bar with the pace tick, when it
// resets, and the forecast.
public struct CardRow: Equatable {
    public var title: String
    public var percentText: String
    public var low: Bool
    public var fill: Double
    public var tick: Double?
    public var reset: String
    public var blocked: String?
    public var forecast: String?
    public var forecastWarn: Bool
}

// The card shown while hovering an agent, as text and numbers (desktop/AgentDetail.cs builds the same):
// every quota window the platform reports with each ring's window marked, what its agents are doing,
// today's usage, and where the quota came from.
public struct CardModel: Equatable {
    public var codex: Bool
    public var title: String
    public var plan: String?
    public var status: String
    public var mood: PetMood
    public var rows: [CardRow] = []
    public var message: String?
    public var hint: String?
    public var usage: [String] = []
    public var lastActive: String?
    public var footer: String?

    public static func build(_ provider: Provider?, codex: Bool, now: Double, online: Bool, mood: PetMood) -> CardModel {
        let limits = provider?.limits
        var status = mood.label
        if mood == .working, let sessions = provider?.activity?.activeSessions, sessions > 1 {
            status += Lang.t(" · \(sessions) 个会话", " · \(sessions) sessions")
        }
        let plan = limits?.plan.flatMap { $0.isEmpty ? nil : $0.lowercased().capitalized }
        var card = CardModel(codex: codex, title: codex ? "Codex" : "Claude Code", plan: plan, status: status, mood: mood)

        // Quota windows, shortest first (in the service's order when equal), each marked with the ring it is drawn as.
        let windows = (limits?.windows ?? []).filter { $0.remainingPercent != nil }.enumerated()
            .sorted { ($0.element.windowMinutes ?? .greatestFiniteMagnitude, $0.offset) < ($1.element.windowMinutes ?? .greatestFiniteMagnitude, $1.offset) }
            .map(\.element)
        if windows.isEmpty {
            card.message = Lang.server(provider?.quotaMessage) ?? Lang.t("这个平台还没有提供额度。", "This platform hasn't reported a quota yet.")
        } else {
            let outer = Quota.outerWindow(limits?.windows), inner = Quota.innerWindow(limits?.windows, outer: outer)
            for window in windows {
                let role: String
                if inner == nil { role = window == outer && windows.count > 1 ? Lang.t(" · 圆环显示", " · in the ring") : "" }
                else { role = window == outer ? Lang.t(" · 外圈", " · outer ring") : window == inner ? Lang.t(" · 内圈", " · inner ring") : "" }
                card.rows.append(row(window, role: role, now: now, weekly: Quota.weeklyBlocker(limits, window, now: now), pace: Pace.of(window, limits, now: now)))
            }
            if inner != nil { card.hint = Lang.t("点击圆环可切换中间显示的额度", "Click a ring to switch the middle number") }
        }

        // Today's usage and the latest model.
        if let activity = provider?.activity {
            let requests = activity.todayRequests ?? 0
            card.usage.append(Lang.t("今日 ", "Today ") + Format.compact(activity.todayTokens ?? 0) + " tokens · " + Format.grouped(requests) + Lang.t(" 次请求", requests == 1 ? " request" : " requests"))
            if let model = activity.model, !model.isEmpty {
                let effort = activity.effort ?? ""
                card.usage.append(Lang.t("最近模型 ", "Latest model ") + model + (effort.isEmpty ? "" : " · " + effort))
            }
            if let last = activity.lastActiveAt { card.lastActive = Lang.t("最近活动：", "Last active ") + Format.age(last, now: now) }
        }

        // Where the quota came from, and how fresh it is.
        if let limits {
            let source = Lang.server(limits.source) ?? Lang.t("平台额度", "Platform quota")
            card.footer = source + "\n" + Quota.updatedText(limits.collectedAt, now: now) + (online ? "" : Lang.t("\n本地服务离线，显示的是最后一次快照", "\nLocal service offline; showing the last snapshot"))
        }
        return card
    }

    static func row(_ window: QuotaWindow, role: String, now: Double, weekly: QuotaWindow?, pace: Pace?) -> CardRow {
        let percent = weekly == nil ? Quota.clamp(window.remainingPercent ?? 0) : 0
        let resetsAt = Quota.effectiveReset(window, weekly, now: now)
        let expired = weekly == nil && (window.resetsAt.map { $0 <= now } ?? false)
        let reset: String
        if expired { reset = Lang.t("已过重置时间，等待更新", "Reset time passed; waiting for an update") }
        else if let at = resetsAt { reset = Quota.resetText(at - now) + Lang.t("（\(Quota.stamp(at))）", " (\(Quota.stamp(at)))") }
        else { reset = Lang.t("重置时间未提供", "Reset time not provided") }
        let shownPace = expired ? nil : pace
        var forecast: String? = nil
        if let shownPace, let windowReset = window.resetsAt { forecast = shownPace.describe(resetsAt: windowReset, now: now) }
        return CardRow(title: Quota.windowName(window) + role,
                       percentText: expired ? "—" : "\(Int(percent.rounded()))%",
                       low: !expired && percent < 20,
                       fill: expired ? 0 : percent / 100,
                       tick: shownPace.map { $0.expected / 100 },
                       reset: reset,
                       blocked: weekly == nil ? nil : Quota.weeklyBlockedText(window),
                       forecast: forecast,
                       forecastWarn: shownPace?.state == .runsOut)
    }
}
