import XCTest
@testable import AgentMeterCore

// The same cases as desktop/test/BehaviorTests.cs and test/pace.test.mjs, so all three read quotas alike.
final class QuotaTests: XCTestCase {
    let hour = 3_600_000.0, day = 86_400_000.0
    var now: Double = 0

    override func setUp() { Lang.apply("zh"); now = Quota.now() }

    func provider(_ windows: [QuotaWindow], id: String = "codex", collectedAgo: Double = 4 * 60000) -> Provider {
        Provider(id: id, limits: Limits(windows: windows, collectedAt: now - collectedAgo, source: "Claude 桌面账户额度", staleAfterMs: 360000))
    }
    func standard() -> Provider {
        provider([QuotaWindow(remainingPercent: 80, windowMinutes: 300, resetsAt: now + 2 * hour), QuotaWindow(remainingPercent: 65, windowMinutes: 10080, resetsAt: now + day)])
    }

    func testOuterIsFiveHoursInnerIsWeekMiddleFollowsTheChoice() {
        let rings = Quota.rings(standard(), now: now, online: true)
        XCTAssertEqual(rings.outer.percent, 80); XCTAssertEqual(rings.inner?.percent, 65)
        XCTAssertFalse(rings.centerInner); XCTAssertEqual(rings.center.percent, 80); XCTAssertEqual(rings.lowest.percent, 65)
        let switched = Quota.rings(standard(), now: now, online: true, showInner: true)
        XCTAssertTrue(switched.centerInner); XCTAssertEqual(switched.center.percent, 65)
        XCTAssertEqual(rings.outer.name, "5 小时"); XCTAssertEqual(rings.inner?.name, "7 天")
        XCTAssertFalse(rings.outer.stale); XCTAssertTrue(Quota.rings(standard(), now: now, online: false).outer.stale)
    }

    func testSingleWindowPlansModelWindowsAndBuckets() {
        let free = provider([QuotaWindow(remainingPercent: 100, windowMinutes: 43200, resetsAt: now + 30 * day)])
        let freeRings = Quota.rings(free, now: now, online: true, showInner: true)
        XCTAssertEqual(freeRings.outer.percent, 100); XCTAssertNil(freeRings.inner); XCTAssertFalse(freeRings.centerInner)
        XCTAssertEqual(freeRings.outer.name, "30 天")
        let scoped = provider([QuotaWindow(remainingPercent: 80, windowMinutes: 300, resetsAt: now + hour), QuotaWindow(id: "seven_day_opus", name: "Opus · 7 天", remainingPercent: 65, windowMinutes: 10080, resetsAt: now + day)])
        XCTAssertNil(Quota.rings(scoped, now: now, online: true).inner, "a model-specific week is not the inner ring")
        var windows = standard().limits!.windows!
        windows.insert(QuotaWindow(name: "Spark · 1 小时", remainingPercent: 5, windowMinutes: 60, resetsAt: now + 1800000), at: 0)
        let bucket = Quota.rings(provider(windows), now: now, online: true)
        XCTAssertEqual(bucket.outer.percent, 80); XCTAssertEqual(bucket.inner?.percent, 65)
    }

    func testStatusesWithoutAWindowAndExpiredSnapshots() {
        XCTAssertEqual(Quota.rings(Provider(id: "claude", quotaStatus: "desktop-connection-disabled"), now: now, online: true).outer.status, .setup)
        XCTAssertEqual(Quota.rings(Provider(id: "claude", quotaStatus: "desktop-not-connected"), now: now, online: true).outer.status, .notLinked)
        XCTAssertEqual(Quota.rings(Provider(id: "claude"), now: now, online: true).outer.status, .unavailable)
        XCTAssertEqual(Quota.rings(nil, now: now, online: true).outer.status, .waiting)
        var windows = standard().limits!.windows!
        windows[0].resetsAt = now - 1
        let lapsed = Quota.rings(provider(windows), now: now, online: true)
        XCTAssertEqual(lapsed.outer.status, .expired); XCTAssertNil(lapsed.outer.percent); XCTAssertEqual(lapsed.lowest.percent, 65)
    }

    func testTheExhaustedWeekRule() {
        var windows = standard().limits!.windows!
        windows[1].remainingPercent = 0
        var shown = Quota.rings(provider(windows), now: now, online: true)
        XCTAssertEqual(shown.outer.percent, 0); XCTAssertEqual(shown.outer.resetsAt, windows[1].resetsAt); XCTAssertEqual(shown.inner?.percent, 0)
        XCTAssertNil(shown.outer.pace, "no pace while the week holds the 5 hours at zero")
        for weekly in [0.1, nil] as [Double?] {
            windows[1].remainingPercent = weekly
            XCTAssertEqual(Quota.rings(provider(windows), now: now, online: true).outer.percent, 80)
        }
        windows[1].remainingPercent = 0; windows[1].resetsAt = now - 1
        XCTAssertEqual(Quota.rings(provider(windows), now: now, online: true).outer.percent, 80, "a passed weekly reset cannot block")
        windows[1].resetsAt = now + day; windows[1].id = "seven_day_opus"; windows[1].name = "Opus · 7 天"
        XCTAssertEqual(Quota.rings(provider(windows), now: now, online: true).outer.percent, 80, "a model week cannot block the account")
        windows[1].id = nil
        XCTAssertEqual(Quota.rings(provider(windows), now: now, online: true).outer.percent, 80)
        windows[1].id = "seven_day"; windows[1].name = "7 天"; windows[0].resetsAt = now - 1
        XCTAssertEqual(Quota.rings(provider(windows), now: now, online: true).outer.percent, 0, "a known block outlives the 5-hour reset")
        windows[0].remainingPercent = 0; windows[0].resetsAt = now + 2 * day
        shown = Quota.rings(provider(windows), now: now, online: true)
        XCTAssertEqual(shown.outer.resetsAt, windows[0].resetsAt, "with both used up the later reset counts")
        windows[1].resetsAt = nil
        XCTAssertNil(Quota.rings(provider(windows), now: now, online: true).outer.resetsAt)
        XCTAssertTrue(Quota.weeklyBlockedText(QuotaWindow(remainingPercent: 80)).contains("原始剩余：80%"))
    }

    func testRingBadgesAndTimes() {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = .current
        func stamp(_ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ mi: Int) -> Double {
            calendar.date(from: DateComponents(year: y, month: mo, day: d, hour: h, minute: mi))!.timeIntervalSince1970 * 1000
        }
        let monday = stamp(2026, 10, 19, 10, 0)
        XCTAssertEqual(Quota.ringBadge(stamp(2026, 10, 19, 14, 30), now: monday), "14:30")
        XCTAssertEqual(Quota.ringBadge(stamp(2026, 10, 20, 3, 5), now: monday), "03:05")
        XCTAssertEqual(Quota.ringBadge(stamp(2026, 10, 22, 9, 0), now: monday), "周四")
        XCTAssertEqual(Quota.ringBadge(stamp(2026, 10, 26, 9, 0), now: monday), "10/26")
        XCTAssertEqual(Quota.ringBadge(stamp(2026, 11, 24, 14, 2), now: monday), "11/24")
        XCTAssertNil(Quota.ringBadge(monday - 1, now: monday))
        Lang.apply("en")
        XCTAssertEqual(Quota.ringBadge(stamp(2026, 10, 22, 9, 0), now: monday), "Thu")
        XCTAssertTrue(Quota.updatedText(monday - 4 * 60000, now: monday).hasPrefix("Quota updated 4 min ago"))
        Lang.apply("zh")
        XCTAssertTrue(Quota.updatedText(monday - 4 * 60000, now: monday).contains("4 分钟前"))
        XCTAssertTrue(Quota.updatedText(nil, now: monday).contains("未知"))
        XCTAssertTrue(Quota.updatedText(monday + 120000, now: monday).contains("异常"))
        XCTAssertEqual(Quota.resetText(2 * hour + 1), "2小时 1分后重置")
        XCTAssertEqual(Quota.span(63 * 60000), "1 小时 3 分钟")
    }

    func testServerTextIsTranslated() {
        Lang.apply("en")
        XCTAssertEqual(Lang.server("5 小时"), "5 hours"); XCTAssertEqual(Lang.server("7 天"), "7 days")
        XCTAssertEqual(Lang.server("Opus · 7 天"), "Opus · 7 days"); XCTAssertEqual(Lang.server("30 天"), "30 days")
        XCTAssertEqual(Lang.server("90 分钟"), "90 min"); XCTAssertEqual(Lang.server("支出额度"), "Spend limit")
        XCTAssertEqual(Lang.server("Claude 桌面账户额度"), "Claude desktop account")
        Lang.apply("zh")
        XCTAssertEqual(Lang.server("5 小时"), "5 小时")
    }
}

final class PaceTests: XCTestCase {
    let hour = 3_600_000.0, day = 86_400_000.0
    let now = 1_795_000_000_000.0
    override func setUp() { Lang.apply("zh") }
    func window(_ remaining: Double?, _ resetIn: Double, _ minutes: Double? = 300) -> QuotaWindow {
        QuotaWindow(remainingPercent: remaining, windowMinutes: minutes, resetsAt: now + resetIn)
    }

    func testTickAndForecast() throws {
        let steady = try XCTUnwrap(Pace.of(window(62, 2.6 * hour), nil, now: now))
        XCTAssertEqual(steady.expected, 52, accuracy: 1e-9); XCTAssertEqual(steady.state, .lasts)
        XCTAssertEqual(steady.leftAtReset!.rounded(), 21); XCTAssertNil(steady.runsOutAt)
        let fast = try XCTUnwrap(Pace.of(window(24, 2 * hour), nil, now: now))
        XCTAssertEqual(fast.state, .runsOut)
        XCTAssertEqual(fast.runsOutAt!, now + 24 / (76 / (3 * hour)), accuracy: 1)
        XCTAssertEqual(fast.describe(resetsAt: now + 2 * hour, now: now)?.hasSuffix("用完，比重置早 1 小时 3 分钟"), true)
        XCTAssertEqual(steady.describe(resetsAt: now + 2.6 * hour, now: now), "按此节奏，重置时约剩 21%")
        Lang.apply("en")
        XCTAssertEqual(steady.describe(resetsAt: now + 2.6 * hour, now: now), "At this pace, about 21% left at the reset")
        XCTAssertEqual(fast.describe(resetsAt: now + 2 * hour, now: now)?.hasSuffix(", 1 h 3 min before the reset"), true)
    }

    func testNoForecastEarlyOrEmptyAndNoPaceWithoutData() {
        XCTAssertEqual(Pace.of(window(97, 5 * hour - 5 * 60000), nil, now: now)?.state, .early)
        XCTAssertEqual(Pace.of(window(80, 5 * hour - 25 * 60000), nil, now: now)?.state, .early)
        XCTAssertEqual(Pace.of(window(80, 5 * hour - 35 * 60000), nil, now: now)?.state, .runsOut)
        XCTAssertEqual(Pace.of(window(70, 7 * day - 13 * hour, 10080), nil, now: now)?.state, .early)
        XCTAssertEqual(Pace.of(window(0, hour), nil, now: now)?.state, .empty)
        XCTAssertEqual(Pace.of(window(100, hour), nil, now: now)?.leftAtReset, 100)
        XCTAssertNil(Pace.of(window(50, -1), nil, now: now))
        XCTAssertNil(Pace.of(window(nil, hour), nil, now: now))
        XCTAssertNil(Pace.of(window(50, hour, nil), nil, now: now))
        let short = window(80, hour), week = window(0, day, 10080)
        XCTAssertNil(Pace.of(short, Limits(windows: [short, week]), now: now))
        XCTAssertEqual(Pace.of(week, Limits(windows: [short, week]), now: now)?.state, .empty)
    }
}

final class CardTests: XCTestCase {
    let hour = 3_600_000.0, day = 86_400_000.0
    var now: Double = 0
    override func setUp() { Lang.apply("zh"); now = Quota.now() }

    func busy() -> Provider {
        Provider(id: "codex", limits: Limits(windows: [QuotaWindow(remainingPercent: 80, windowMinutes: 300, resetsAt: now + 2 * hour), QuotaWindow(remainingPercent: 65, windowMinutes: 10080, resetsAt: now + day)], collectedAt: now - 4 * 60000, source: "Claude 桌面账户额度", staleAfterMs: 360000),
                 activity: Activity(working: true, activeSessions: 2, todayTokens: 1234567, todayRequests: 42, lastActiveAt: now - 30000, model: "gpt-6.1-sol", effort: "xhigh"))
    }

    func testCardListsWindowsWithRingsForecastsAndUsage() {
        let card = CardModel.build(busy(), codex: true, now: now, online: true, mood: .working)
        XCTAssertEqual(card.status, "工作中 · 2 个会话")
        XCTAssertEqual(card.rows.map(\.title), ["5 小时 · 外圈", "7 天 · 内圈"])
        XCTAssertEqual(card.rows.map(\.percentText), ["80%", "65%"])
        XCTAssertEqual(card.rows[0].tick!, 0.4, accuracy: 1e-9)
        XCTAssertTrue(card.rows[0].reset.contains("后重置"))
        XCTAssertEqual(card.rows[0].forecast?.hasPrefix("按此节奏，重置时约剩 "), true)
        XCTAssertEqual(card.hint, "点击圆环可切换中间显示的额度")
        XCTAssertEqual(card.usage, ["今日 1.2M tokens · 42 次请求", "最近模型 gpt-6.1-sol · xhigh"])
        XCTAssertEqual(card.lastActive, "最近活动：刚刚")
        XCTAssertTrue(card.footer!.hasPrefix("Claude 桌面账户额度\n额度更新："))
        XCTAssertTrue(CardModel.build(busy(), codex: true, now: now, online: false, mood: .offline).footer!.contains("本地服务离线"))
    }

    func testRunningOutIsWarnedAndSingleRingsAreMarked() {
        let hurried = Provider(id: "claude", limits: Limits(windows: [QuotaWindow(remainingPercent: 24, windowMinutes: 300, resetsAt: now + 2 * hour), QuotaWindow(remainingPercent: 73, windowMinutes: 10080, resetsAt: now + 2.3 * day)], collectedAt: now))
        let card = CardModel.build(hurried, codex: false, now: now, online: true, mood: .idle)
        XCTAssertTrue(card.rows[0].forecastWarn); XCTAssertEqual(card.rows[0].forecast?.hasSuffix("比重置早 1 小时 3 分钟"), true)
        XCTAssertFalse(card.rows[1].forecastWarn)
        let single = Provider(id: "codex", limits: Limits(windows: [QuotaWindow(remainingPercent: 100, windowMinutes: 43200, resetsAt: now + 30 * day), QuotaWindow(name: "支出额度", remainingPercent: 40)], collectedAt: now))
        let singleCard = CardModel.build(single, codex: true, now: now, online: true, mood: .idle)
        XCTAssertEqual(singleCard.rows[0].title, "30 天 · 圆环显示"); XCTAssertNil(singleCard.hint)
        let empty = CardModel.build(Provider(id: "claude", quotaMessage: "未找到 Claude 桌面版登录连接，请先打开 Claude 并登录。"), codex: false, now: now, online: true, mood: .idle)
        XCTAssertEqual(empty.message, "未找到 Claude 桌面版登录连接，请先打开 Claude 并登录。"); XCTAssertTrue(empty.rows.isEmpty)
    }

    func testEnglishCard() {
        Lang.apply("en")
        var provider = busy(); provider.activity?.todayRequests = 1
        let card = CardModel.build(provider, codex: true, now: now, online: true, mood: .working)
        XCTAssertEqual(card.status, "Working · 2 sessions")
        XCTAssertEqual(card.rows.map(\.title), ["5 hours · outer ring", "7 days · inner ring"])
        XCTAssertEqual(card.usage.first, "Today 1.2M tokens · 1 request")
        XCTAssertEqual(card.hint, "Click a ring to switch the middle number")
    }

    func testPetMoods() {
        var provider = busy()
        XCTAssertEqual(PetMood.of(provider, lowest: Quota.rings(provider, now: now, online: true).lowest, online: true, now: now), .working)
        XCTAssertEqual(PetMood.of(provider, lowest: nil, online: false, now: now), .offline)
        provider.limits?.windows?[1].remainingPercent = 0
        XCTAssertEqual(PetMood.of(provider, lowest: nil, online: true, now: now), .exhausted)
        provider.limits?.windows?[1].remainingPercent = 15; provider.activity?.working = false
        XCTAssertEqual(PetMood.of(provider, lowest: Quota.rings(provider, now: now, online: true).lowest, online: true, now: now), .tired)
        provider.limits?.windows?[1].remainingPercent = 65
        XCTAssertEqual(PetMood.of(provider, lowest: Quota.rings(provider, now: now, online: true).lowest, online: true, now: now), .idle)
    }
}

final class PlacementTests: XCTestCase {
    func testDockingSnappingAndScreens() {
        let work = CGRect(x: 0, y: 0, width: 2560, height: 1400)
        XCTAssertEqual(Placement.sideEdge(CGRect(x: 0, y: 300, width: 58, height: 260), in: work, tolerance: 2), "left")
        XCTAssertEqual(Placement.sideEdge(CGRect(x: 2502, y: 300, width: 58, height: 260), in: work, tolerance: 2), "right")
        XCTAssertNil(Placement.sideEdge(CGRect(x: 40, y: 0, width: 246, height: 52), in: work, tolerance: 2))
        XCTAssertEqual(Placement.fit(CGRect(x: 8, y: 9, width: 260, height: 48), in: work, snap: 10).origin, .zero)
        XCTAssertEqual(Placement.fit(CGRect(x: 80, y: 90, width: 260, height: 48), in: work, snap: 10).origin, CGPoint(x: 80, y: 90))
        let areas = [CGRect(x: -1920, y: 0, width: 1920, height: 1040), work, CGRect(x: 3000, y: 300, width: 1920, height: 1040)]
        let gap = CGRect(x: 2700, y: 100, width: 260, height: 48)
        let selected = Placement.nearestArea(gap, areas)!
        XCTAssertTrue(areas[selected].contains(Placement.fit(gap, in: areas[selected], snap: 0)))
        let column = Placement.anchored(CGRect(x: 2300, y: 500, width: 246, height: 52), size: CGSize(width: 58, height: 260), in: work, edge: "right")
        XCTAssertEqual(column.maxX, work.maxX); XCTAssertEqual(column.midY, 526)
        let offsets = Placement.offsets(of: CGRect(x: 1157, y: 674, width: 246, height: 52), in: work)
        XCTAssertEqual(Placement.atOffset(work, size: CGSize(width: 246, height: 52), x: offsets.x, y: offsets.y).origin.x, 1157, accuracy: 0.5)
    }

    func testStateDecodesWithDefaults() throws {
        let state = try JSONDecoder().decode(WidgetState.self, from: Data(#"{"language":"en","left":5}"#.utf8))
        XCTAssertEqual(state.language, "en"); XCTAssertTrue(state.pinned); XCTAssertEqual(state.center, "outer"); XCTAssertNil(state.dock)
    }
}
