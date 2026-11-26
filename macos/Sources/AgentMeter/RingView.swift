import AppKit
import SwiftUI
import AgentMeterCore

// Remaining quota in the platform's colours, drawn like desktop/QuotaRing.cs: the outer ring is the
// shortest window, a longer account-wide window is a thinner ring inside it, pace ticks cross both, and the
// middle shows one window's number with its reset time under it.
struct RingView: View {
    let set: RingSet
    let offline: Bool
    let codex: Bool
    let palette: Palette

    static let diameter: CGFloat = 44
    static let outerThickness: CGFloat = 3, gap: CGFloat = 1.2, innerThickness: CGFloat = 2
    static let outerRadius: CGFloat = diameter / 2 - outerThickness / 2 - 0.4
    static let innerRadius: CGFloat = outerRadius - outerThickness / 2 - gap - innerThickness / 2

    var body: some View {
        ZStack {
            ring(set.outer, radius: RingView.outerRadius, thickness: RingView.outerThickness, emphasis: set.centerInner ? 0.7 : 1)
            if let inner = set.inner {
                ring(inner, radius: RingView.innerRadius, thickness: RingView.innerThickness, emphasis: set.centerInner ? 1 : 0.7)
            }
            tick(set.outer.pace?.expected, radius: RingView.outerRadius, thickness: RingView.outerThickness, inward: 0.9)
            if let inner = set.inner {
                // The inner tick reaches only a little inward, clear of the number.
                tick(inner.pace?.expected, radius: RingView.innerRadius, thickness: RingView.innerThickness, inward: 0.5)
            }
            label
        }
        .frame(width: RingView.diameter, height: RingView.diameter)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spokenName)
    }

    // Codex's gradient runs down the ring like its mark; Claude is its clay colour.
    private var arcStyle: AnyShapeStyle {
        if codex {
            return AnyShapeStyle(LinearGradient(stops: [
                .init(color: Brand.codexTop, location: 2 / 44), .init(color: Brand.codexMid, location: 17 / 44), .init(color: Brand.codexBottom, location: 32 / 44),
            ], startPoint: .top, endPoint: .bottom))
        }
        return AnyShapeStyle(Brand.clay)
    }

    @ViewBuilder private func ring(_ value: RingValue, radius: CGFloat, thickness: CGFloat, emphasis: Double) -> some View {
        let unknown = value.percent == nil
        // The track all the way round, dotted while the value is unknown.
        RingTrack(radius: radius)
            .stroke(codex ? palette.codexTrack : palette.claudeTrack, style: StrokeStyle(lineWidth: thickness, lineCap: .round, dash: unknown ? [0, 1.8 * thickness] : []))
        if let percent = value.percent, percent > 0.05 {
            RingArc(fraction: percent / 100, radius: radius)
                .stroke(arcStyle, style: StrokeStyle(lineWidth: thickness, lineCap: .round))
                .opacity((value.stale ? 0.5 : 1) * emphasis)
                .animation(NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? nil : .easeOut(duration: 0.6), value: percent)
        }
    }

    // A short radial mark across the stroke where even use would leave the ring now. An arc that stops
    // short of it is running ahead of pace; one that reaches past it has quota to spare.
    @ViewBuilder private func tick(_ expected: Double?, radius: CGFloat, thickness: CGFloat, inward: CGFloat) -> some View {
        if let expected {
            RingTick(percent: (expected * 2).rounded() / 2, from: radius - thickness / 2 - inward, to: radius + thickness / 2 + 0.9)
                .stroke(palette.text, style: StrokeStyle(lineWidth: 1.3, lineCap: .round))
                .opacity(0.62)
        }
    }

    @ViewBuilder private var label: some View {
        let center = set.center
        let nested = set.inner != nil
        if let percent = center.percent {
            VStack(spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    Text("\(Int(percent.rounded()))")
                        .font(.system(size: nested ? 11 : 13, weight: center.stale ? .regular : .semibold))
                        .foregroundColor(percent < 20 ? palette.low : palette.text)
                    Text("%").font(.system(size: nested ? 6.5 : 7.5)).foregroundColor(palette.text)
                }
                if let secondary = secondary {
                    Text(secondary)
                        .font(.system(size: nested ? 6.6 : 7.2))
                        .foregroundColor(palette.text)
                        .opacity(0.86)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                        .frame(maxWidth: nested ? 20 : 34)
                }
            }
            .offset(y: nested ? -0.4 : -0.6)
        } else {
            Text(statusWord)
                .font(.system(size: nested ? 7.5 : 8.5))
                .foregroundColor(palette.text)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: nested ? 28 : 36)
        }
    }

    // Under the number: the reset time; "离线" while offline; what the number is when there is no reset time.
    private var secondary: String? {
        let center = set.center
        if offline { return Lang.t("离线", "Offline") }
        if let resetsAt = center.resetsAt, let badge = Quota.ringBadge(resetsAt, now: Quota.now()) { return badge }
        return center.stale ? Lang.t("快照", "Snapshot") : Lang.t("剩余", "left")
    }

    private var statusWord: String {
        if offline { return Lang.t("离线", "Offline") }
        switch set.center.status {
        case .setup: return Lang.t("待连接", "Setup")
        case .notLinked: return Lang.t("未接入", "No link")
        case .expired: return Lang.t("待更新", "Pending")
        case .waiting: return Lang.t("等待", "Waiting")
        default: return Lang.t("未提供", "N/A")
        }
    }

    // What the middle says, then each ring by name, then a warning for a window about to run out.
    private var spokenName: String {
        let platform = codex ? "Codex" : "Claude Code"
        let primary = set.center.percent.map { "\(Int($0.rounded()))%" } ?? statusWord
        let second = set.center.percent == nil ? nil : secondary
        var name = platform + Lang.t(" 剩余额度 " + primary + (second.map { "，" + $0 } ?? ""), " quota remaining " + primary + (second.map { ", " + $0 } ?? ""))
        func describe(_ value: RingValue) -> String {
            let amount = value.percent.map { "\(Int($0.rounded()))%" } ?? Lang.t("未知", "unknown")
            return (value.name.map { $0 + " " } ?? "") + amount
        }
        if let inner = set.inner {
            name += Lang.t("；外圈 " + describe(set.outer) + "，内圈 " + describe(inner), "; outer ring " + describe(set.outer) + ", inner ring " + describe(inner))
        }
        for value in [set.outer] + (set.inner.map { [$0] } ?? []) {
            if let pace = value.pace, pace.state == .runsOut, let resetsAt = value.resetsAt, let forecast = pace.describe(resetsAt: resetsAt, now: Quota.now()) {
                name += Lang.t("；", "; ") + (value.name ?? "") + Lang.t("：", ": ") + forecast
            }
        }
        return name
    }
}

struct RingTrack: Shape {
    let radius: CGFloat
    func path(in rect: CGRect) -> Path {
        Path(ellipseIn: CGRect(x: rect.midX - radius, y: rect.midY - radius, width: radius * 2, height: radius * 2))
    }
}

// Clockwise from 12 o'clock; animatable, so a new value sweeps there instead of jumping.
struct RingArc: Shape {
    var fraction: Double
    let radius: CGFloat
    var animatableData: Double {
        get { fraction }
        set { fraction = newValue }
    }
    func path(in rect: CGRect) -> Path {
        let value = max(0, min(1, fraction))
        var path = Path()
        if value >= 0.9995 { path.addEllipse(in: CGRect(x: rect.midX - radius, y: rect.midY - radius, width: radius * 2, height: radius * 2)); return path }
        path.addArc(center: CGPoint(x: rect.midX, y: rect.midY), radius: radius, startAngle: .degrees(-90), endAngle: .degrees(-90 + 360 * value), clockwise: false)
        return path
    }
}

struct RingTick: Shape {
    let percent: Double
    let from: CGFloat
    let to: CGFloat
    func path(in rect: CGRect) -> Path {
        let angle = percent / 100 * 2 * Double.pi
        let s = CGFloat(sin(angle)), c = CGFloat(cos(angle))
        var path = Path()
        path.move(to: CGPoint(x: rect.midX + from * s, y: rect.midY - from * c))
        path.addLine(to: CGPoint(x: rect.midX + to * s, y: rect.midY - to * c))
        return path
    }
}
