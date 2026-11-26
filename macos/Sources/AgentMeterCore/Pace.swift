import Foundation

// How a quota window is being used, by the same rule as public/pace.js and desktop/Models.cs (Pace).
// `expected` is the share that even use across the window would leave right now (the tick on rings and
// bars). The forecast extends the window's average rate so far: it either runs out before the reset
// (`runsOutAt`) or lasts, with `leftAtReset` still there when the window resets. In the first tenth of a
// window, or once it is used up, there is no forecast.
public struct Pace: Equatable {
    public static let minElapsedMs = 10.0 * 60000, minElapsedShare = 0.1
    public enum State: String { case runsOut = "runs-out", lasts, early, empty }

    public var start: Double
    public var expected: Double
    public var state: State = .early
    public var runsOutAt: Double?
    public var leftAtReset: Double?

    public static func of(_ window: QuotaWindow?, _ limits: Limits?, now: Double) -> Pace? {
        guard let window, let reset = window.resetsAt, let minutes = window.windowMinutes, minutes > 0, reset > now,
              let reading = window.remainingPercent, reading.isFinite else { return nil }
        if Quota.weeklyBlocker(limits, window, now: now) != nil { return nil }
        let length = minutes * 60000
        var pace = Pace(start: reset - length, expected: max(0, min(100, (reset - now) / length * 100)))
        let remaining = Quota.clamp(reading), used = 100 - remaining, elapsed = max(0, now - pace.start)
        if remaining <= 0 { pace.state = .empty }
        else if used <= 0 { pace.state = .lasts; pace.leftAtReset = remaining }
        else if elapsed >= max(minElapsedMs, length * minElapsedShare) {
            let rate = used / elapsed, runsOutAt = now + remaining / rate
            if runsOutAt < reset { pace.state = .runsOut; pace.runsOutAt = runsOutAt.rounded() }
            else { pace.state = .lasts; pace.leftAtReset = max(0, remaining - rate * (reset - now)) }
        }
        return pace
    }

    // The forecast in words, or nil when there is none to give.
    public func describe(resetsAt: Double, now: Double) -> String? {
        switch state {
        case .runsOut:
            guard let at = runsOutAt else { return nil }
            let time = Quota.shortTime(at, now: now), gap = Quota.span(resetsAt - at)
            return Lang.t("按此节奏约 \(time) 用完，比重置早 \(gap)", "At this pace it runs out around \(time), \(gap) before the reset")
        case .lasts:
            guard let left = leftAtReset else { return nil }
            let n = Int(left.rounded())
            return Lang.t("按此节奏，重置时约剩 \(n)%", "At this pace, about \(n)% left at the reset")
        case .early, .empty:
            return nil
        }
    }
}

// A small original mascot per platform; its pose says what the platform's agents are doing.
public enum PetMood: Equatable {
    case offline, idle, working, tired, exhausted

    // An empty quota window beats everything (the agent can't work), then work, then a low quota.
    public static func of(_ provider: Provider?, lowest: RingValue?, online: Bool, now: Double) -> PetMood {
        guard online, let provider else { return .offline }
        if let limits = provider.limits, limits.stale != true, let windows = limits.windows,
           windows.contains(where: { w in (w.remainingPercent.map { $0 <= 0.5 } ?? false) && (w.resetsAt.map { $0 > now } ?? true) }) {
            return .exhausted
        }
        if provider.activity?.working == true { return .working }
        if let percent = lowest?.percent, percent < 20 { return .tired }
        return .idle
    }

    public var label: String {
        switch self {
        case .working: return Lang.t("工作中", "Working")
        case .tired: return Lang.t("额度偏低", "Running low")
        case .exhausted: return Lang.t("额度已用尽", "Out of quota")
        case .offline: return Lang.t("服务离线", "Service offline")
        case .idle: return Lang.t("空闲", "Idle")
        }
    }
}
