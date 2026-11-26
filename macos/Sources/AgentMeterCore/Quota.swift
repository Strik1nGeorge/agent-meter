import Foundation

// Language-independent states; the ring picks its words from these.
public enum RingStatus: String { case waiting, setup, notLinked = "not-linked", unavailable, expired, live }

// One ring's value: the remaining share of a quota window, when it resets, and how it is being used.
public struct RingValue: Equatable {
    public var percent: Double?
    public var resetsAt: Double?
    public var stale = false
    public var status: RingStatus = .waiting
    // The window's name ("5 小时" / "5 hours"), when there is one.
    public var name: String?
    // How the window is being used, while it is live and not held at zero by the week.
    public var pace: Pace?

    public init(percent: Double? = nil, resetsAt: Double? = nil, stale: Bool = false, status: RingStatus = .waiting, name: String? = nil, pace: Pace? = nil) {
        self.percent = percent; self.resetsAt = resetsAt; self.stale = stale; self.status = status; self.name = name; self.pace = pace
    }
}

// One platform's rings. The outer ring is its shortest window (5 hours on most plans); the thinner inner
// ring is the account-wide window after it (7 days), when the plan has one. The middle shows the outer
// window, or the inner one once the user switches to it.
public struct RingSet: Equatable {
    public var outer: RingValue
    public var inner: RingValue?
    public var centerInner: Bool

    public init(outer: RingValue = RingValue(), inner: RingValue? = nil, centerInner: Bool = false) {
        self.outer = outer; self.inner = inner; self.centerInner = centerInner
    }

    public var center: RingValue { centerInner ? (inner ?? outer) : outer }
    // The window closer to running out, which sets the pet's mood: a number beats a status word, then the lower number.
    public var lowest: RingValue {
        if let inner = inner, let value = inner.percent, outer.percent == nil || value < outer.percent! { return inner }
        return outer
    }
}

// The quota rules of desktop/Models.cs (RingValue), so both widgets read a platform's quota the same way.
public enum Quota {
    public static func now() -> Double { Date().timeIntervalSince1970 * 1000 }
    public static func clamp(_ value: Double) -> Double { max(0, min(100, value)) }

    public static func rings(_ provider: Provider?, now: Double, online: Bool, showInner: Bool = false) -> RingSet {
        let windows = provider?.limits?.windows
        let outer = outerWindow(windows)
        let inner = innerWindow(windows, outer: outer)
        let innerValue = inner.map { forWindow(provider, $0, now: now, online: online) }
        return RingSet(outer: forWindow(provider, outer, now: now, online: online), inner: innerValue, centerInner: showInner && innerValue != nil)
    }

    static func forWindow(_ provider: Provider?, _ window: QuotaWindow?, now: Double, online: Bool) -> RingValue {
        var result = RingValue()
        guard let provider else { return result }
        let limits = provider.limits
        guard let window else {
            result.status = provider.quotaStatus == "desktop-connection-disabled" ? .setup : provider.quotaStatus == "desktop-not-connected" ? .notLinked : .unavailable
            return result
        }
        result.name = windowName(window)
        let weekly = weeklyBlocker(limits, window, now: now)
        if weekly == nil, let resetsAt = window.resetsAt, resetsAt <= now { result.status = .expired; return result }
        result.status = .live
        result.percent = weekly == nil ? clamp(window.remainingPercent ?? 0) : 0
        result.resetsAt = effectiveReset(window, weekly, now: now)
        result.pace = Pace.of(window, limits, now: now)
        if let collected = limits?.collectedAt {
            result.stale = limits?.stale == true || !online || now - collected > (limits?.staleAfterMs ?? 120000)
        } else { result.stale = true }
        return result
    }

    // Only the account-wide weekly window blocks its 5-hour allowance. Model-specific windows (for example
    // Opus) and snapshots past their reset cannot block the account.
    public static func weeklyBlocker(_ limits: Limits?, _ window: QuotaWindow?, now: Double) -> QuotaWindow? {
        guard let window, window.windowMinutes == 300, let windows = limits?.windows else { return nil }
        return windows.first { w in
            w.windowMinutes == 10080 && accountWide(w)
                && (w.remainingPercent.map { $0.isFinite && $0 <= 0 } ?? false)
                && (w.resetsAt.map { $0 > now } ?? true)
        }
    }

    // Windows for the whole account, not one model's (Claude's "Opus · 7 天", Codex's per-model buckets).
    public static func accountWide(_ w: QuotaWindow) -> Bool {
        let id = w.id ?? ""
        return (id.isEmpty || id == "five_hour" || id == "seven_day") && !(w.name ?? "").contains("·")
    }

    // A window can go in a ring once it has a real percentage and a length.
    static func usable(_ windows: [QuotaWindow]?) -> [QuotaWindow] {
        (windows ?? []).filter { w in
            guard let remaining = w.remainingPercent, remaining.isFinite, let minutes = w.windowMinutes, minutes > 0 else { return false }
            return true
        }
    }

    // The outer ring takes the shortest account-wide window (any window, if the plan only has model-specific
    // ones), the inner ring the next longer account-wide one.
    public static func outerWindow(_ windows: [QuotaWindow]?) -> QuotaWindow? {
        let list = usable(windows)
        let shorter: (QuotaWindow, QuotaWindow) -> Bool = { ($0.windowMinutes ?? 0) < ($1.windowMinutes ?? 0) }
        return list.filter(accountWide).min(by: shorter) ?? list.min(by: shorter)
    }

    public static func innerWindow(_ windows: [QuotaWindow]?, outer: QuotaWindow?) -> QuotaWindow? {
        guard let outer, let length = outer.windowMinutes else { return nil }
        return usable(windows).filter { accountWide($0) && ($0.windowMinutes ?? 0) > length }.min { ($0.windowMinutes ?? 0) < ($1.windowMinutes ?? 0) }
    }

    // The service's name for a window, or one made from its length.
    public static func windowName(_ window: QuotaWindow) -> String {
        if let name = Lang.server(window.name) { return name }
        guard let minutes = window.windowMinutes, minutes > 0 else { return Lang.t("额度", "Quota") }
        let m = Int(minutes)
        if m % 1440 == 0 { let d = m / 1440; return Lang.t("\(d) 天", "\(d) " + (d == 1 ? "day" : "days")) }
        if m % 60 == 0 { let h = m / 60; return Lang.t("\(h) 小时", "\(h) " + (h == 1 ? "hour" : "hours")) }
        return Lang.t("\(m) 分钟", "\(m) min")
    }

    public static func effectiveReset(_ window: QuotaWindow, _ weekly: QuotaWindow?, now: Double) -> Double? {
        guard let weekly else { return window.resetsAt }
        if let remaining = window.remainingPercent, remaining <= 0, window.resetsAt.map({ $0 > now }) ?? true {
            if let a = window.resetsAt, let b = weekly.resetsAt { return max(a, b) }
            return nil
        }
        return weekly.resetsAt
    }

    public static func weeklyBlockedText(_ window: QuotaWindow) -> String {
        var note = Lang.t("周额度已用尽，5 小时可用额度为 0%。", "Weekly quota exhausted; available 5-hour quota is 0%.")
        if let remaining = window.remainingPercent {
            let raw = Format.oneDecimal(clamp(remaining))
            note += Lang.t("平台 5 小时原始剩余：\(raw)%（未计入周限制）。", " Platform-reported 5-hour remaining: \(raw)% (before the weekly limit).")
        }
        return note
    }

    public static func updatedText(_ collectedAt: Double?, now: Double) -> String {
        guard let stamp = collectedAt else { return Lang.t("额度更新时间未知", "Quota update time unknown") }
        if !stamp.isFinite || stamp > now + 60000 { return Lang.t("额度更新时间异常，请检查系统时间", "Quota update time looks wrong; check the system clock") }
        let minutes = (max(0, now - stamp) / 60000).rounded(.down)
        let age: String
        if minutes < 1 { age = Lang.t("刚刚", "just now") }
        else if minutes < 60 { age = Lang.t("\(Int(minutes)) 分钟前", "\(Int(minutes)) min ago") }
        else if minutes < 1440 { let h = Int(minutes / 60); age = Lang.t("\(h) 小时前", "\(h) h ago") }
        else { let d = Int(minutes / 1440); age = Lang.t("\(d) 天前", "\(d) d ago") }
        let date = Format.local(stamp, "MM-dd HH:mm")
        return Lang.t("额度更新：\(age)（\(date)）", "Quota updated \(age) (\(date))")
    }

    // Shortest form, for inside the ring: the clock time within a day, the weekday within the coming week,
    // otherwise the date. The countdown and full date are in the hover card.
    public static func ringBadge(_ resetsAt: Double, now: Double) -> String? {
        guard resetsAt.isFinite, resetsAt > now else { return nil }
        if resetsAt - now < 86_400_000 { return Format.local(resetsAt, "HH:mm") }
        let calendar = Format.calendar
        let reset = Date(timeIntervalSince1970: resetsAt / 1000), today = Date(timeIntervalSince1970: now / 1000)
        // A weekday is only unambiguous within the next six days; a 7-day window's same-weekday reset gets its date.
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: today), to: calendar.startOfDay(for: reset)).day ?? 99
        if days < 7 {
            let day = calendar.component(.weekday, from: reset) - 1
            return Lang.t(["周日", "周一", "周二", "周三", "周四", "周五", "周六"][day], ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"][day])
        }
        return Format.local(resetsAt, "M/d")
    }

    public static func stamp(_ time: Double) -> String { time.isFinite ? Format.local(time, "MM-dd HH:mm") : "" }

    // A time later today as "15:40", on another day as "11-26 15:40".
    public static func shortTime(_ time: Double, now: Double) -> String {
        let calendar = Format.calendar
        let same = calendar.isDate(Date(timeIntervalSince1970: time / 1000), inSameDayAs: Date(timeIntervalSince1970: now / 1000))
        return Format.local(time, same ? "HH:mm" : "MM-dd HH:mm")
    }

    // A stretch of time as "50 分钟" / "2 小时 10 分钟" / "1 天 3 小时".
    public static func span(_ milliseconds: Double) -> String {
        let minutes = Int((max(0, milliseconds) / 60000).rounded())
        if minutes >= 1440 { return Lang.t("\(minutes / 1440) 天 \((minutes % 1440) / 60) 小时", "\(minutes / 1440) d \((minutes % 1440) / 60) h") }
        if minutes >= 60 { return Lang.t("\(minutes / 60) 小时 \(minutes % 60) 分钟", "\(minutes / 60) h \(minutes % 60) min") }
        return Lang.t("\(minutes) 分钟", "\(minutes) min")
    }

    public static func resetText(_ milliseconds: Double) -> String {
        let minutes = Int((max(0, milliseconds) / 60000).rounded(.up))
        if minutes >= 1440 { return Lang.t("\(minutes / 1440)天 \((minutes % 1440) / 60)小时后重置", "Resets in \(minutes / 1440)d \((minutes % 1440) / 60)h") }
        if minutes >= 60 { return Lang.t("\(minutes / 60)小时 \(minutes % 60)分后重置", "Resets in \(minutes / 60)h \(minutes % 60)m") }
        return Lang.t("\(minutes)分钟后重置", "Resets in \(minutes) min")
    }
}

public enum Format {
    static var calendar: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = .current; return c }

    public static func local(_ time: Double, _ pattern: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = pattern
        return formatter.string(from: Date(timeIntervalSince1970: time / 1000))
    }

    // "0.#": at most one decimal, none when it is whole.
    public static func oneDecimal(_ value: Double) -> String {
        let rounded = (value * 10).rounded() / 10
        return rounded == rounded.rounded() ? String(Int(rounded)) : String(format: "%.1f", rounded)
    }

    public static func compact(_ value: Double) -> String {
        if value >= 1e9 { return oneDecimal(value / 1e9) + "B" }
        if value >= 1e6 { return oneDecimal(value / 1e6) + "M" }
        if value >= 1e3 { return oneDecimal(value / 1e3) + "K" }
        return String(Int(value.rounded()))
    }

    public static func grouped(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: value)) ?? String(value)
    }

    public static func age(_ time: Double, now: Double) -> String {
        let minutes = (max(0, now - time) / 60000).rounded(.down)
        if minutes < 1 { return Lang.t("刚刚", "just now") }
        if minutes < 60 { return Lang.t("\(Int(minutes)) 分钟前", "\(Int(minutes)) min ago") }
        if minutes < 1440 { let h = Int(minutes / 60); return Lang.t("\(h) 小时前", "\(h) h ago") }
        let d = Int(minutes / 1440)
        return Lang.t("\(d) 天前", "\(d) d ago")
    }
}
