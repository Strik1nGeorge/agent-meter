import SwiftUI
import AgentMeterCore

// Frames of the parts the pointer can land on, in the widget's own top-left coordinates, for the AppKit
// layer that handles the mouse (SwiftUI's own hover tracking stays quiet while the app isn't active).
struct HitFrames: PreferenceKey {
    static var defaultValue: [Hit: CGRect] = [:]
    static func reduce(value: inout [Hit: CGRect], nextValue: () -> [Hit: CGRect]) { value.merge(nextValue()) { $1 } }
}

extension View {
    func reportFrame(_ hit: Hit) -> some View {
        background(GeometryReader { proxy in Color.clear.preference(key: HitFrames.self, value: [hit: proxy.frame(in: .named("widget"))]) })
    }
}

// The strip (or, against the left or right edge of the screen, the column), with the same parts and
// spacing as the Windows widget: Codex's pet and rings, Claude's, then the language, pin and ⋯ buttons.
struct WidgetView: View {
    @ObservedObject var model: WidgetModel
    @Environment(\.colorScheme) private var scheme

    static let strip = CGSize(width: 246, height: 52)
    static let column = CGSize(width: 58, height: 260)

    var body: some View {
        let palette = Palette.current(scheme)
        let size = model.vertical ? WidgetView.column : WidgetView.strip
        ZStack(alignment: .topLeading) {
            GlassLayers(palette: palette, size: size, offline: !model.online)
            if model.vertical {
                VStack(spacing: 0) {
                    gap(8); tile("codex", palette); gap(10); tile("claude", palette); Spacer(minLength: 0)
                    button(.language, palette, length: 28); button(.pin, palette, length: 28); button(.more, palette, length: 24); gap(6)
                }
                .frame(width: size.width, height: size.height)
            } else {
                HStack(spacing: 0) {
                    gap(8); tile("codex", palette); gap(10); tile("claude", palette); Spacer(minLength: 0)
                    button(.language, palette, length: 24); button(.pin, palette, length: 22); button(.more, palette, length: 18); gap(6)
                }
                .frame(width: size.width, height: size.height)
            }
        }
        .frame(width: size.width, height: size.height)
        .coordinateSpace(name: "widget")
        .onPreferenceChange(HitFrames.self) { frames in model.frames = frames }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func gap(_ length: CGFloat) -> some View {
        Color.clear.frame(width: model.vertical ? nil : length, height: model.vertical ? length : nil)
    }

    @ViewBuilder private func tile(_ id: String, _ palette: Palette) -> some View {
        let codex = id == "codex"
        let pet = PetView(codex: codex, mood: model.mood(id), animating: model.animating, palette: palette)
        let ring = RingView(set: model.rings(id), offline: !model.online, codex: codex, palette: palette).reportFrame(codex ? .codexRing : .claudeRing)
        if model.vertical {
            VStack(spacing: 2) { pet; ring }.reportFrame(codex ? .codexTile : .claudeTile)
        } else {
            HStack(spacing: 3) { pet; ring }.reportFrame(codex ? .codexTile : .claudeTile)
        }
    }

    // Each button keeps the whole strip's height (or the column's width) as its hit area; the chip stays small.
    private func button(_ hit: Hit, _ palette: Palette, length: CGFloat) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10).fill(model.hover == hit ? palette.iconHover : Color.clear).frame(height: 30).padding(.horizontal, 1)
            icon(hit, palette)
        }
        .frame(width: model.vertical ? 36 : length, height: model.vertical ? length : 50)
        .scaleEffect(model.pressed == hit ? 0.9 : 1)
        .animation(.easeOut(duration: model.pressed == hit ? 0.1 : 0.22), value: model.pressed == hit)
        .frame(width: model.vertical ? WidgetView.column.width : length, height: model.vertical ? length : WidgetView.strip.height)
        .reportFrame(hit)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityName(hit))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { model.perform?(hit) }
    }

    private func accessibilityName(_ hit: Hit) -> String {
        switch hit {
        case .language: return Lang.english ? "切换到中文" : "Switch to English"
        case .pin: return model.state.pinned ? Lang.t("已置顶，点击取消置顶", "Pinned, click to unpin") : Lang.t("未置顶，点击置顶", "Not pinned, click to pin")
        default: return Lang.t("更多选项", "More options")
        }
    }

    @ViewBuilder private func icon(_ hit: Hit, _ palette: Palette) -> some View {
        switch hit {
        case .language:
            // The language it switches to, in a rounded outline, like the dashboard's button.
            Text(Lang.english ? "中" : "EN")
                .font(.system(size: 8.5, weight: .semibold))
                .foregroundColor(palette.text)
                .padding(.horizontal, 2)
                .frame(minWidth: 17, minHeight: 13)
                .overlay(RoundedRectangle(cornerRadius: 3.5).stroke(palette.text, lineWidth: 1.1))
        case .pin:
            PinIcon(pinned: model.state.pinned, color: model.state.pinned ? palette.accent : palette.textMuted).frame(width: 16, height: 16)
        default:
            HStack(spacing: 1.8) { ForEach(0..<3, id: \.self) { _ in Circle().fill(palette.text).frame(width: 2.7, height: 2.7) } }
        }
    }
}

// A solid pin when pinned on top; a hollow pin with a slash when not.
struct PinIcon: View {
    let pinned: Bool
    let color: Color

    var body: some View {
        Canvas { context, _ in
            var pin = Path()
            pin.move(to: CGPoint(x: 5, y: 2)); pin.addLine(to: CGPoint(x: 11, y: 2)); pin.addLine(to: CGPoint(x: 10.3, y: 7.3))
            pin.addLine(to: CGPoint(x: 12.5, y: 10)); pin.addLine(to: CGPoint(x: 3.5, y: 10)); pin.addLine(to: CGPoint(x: 5.7, y: 7.3)); pin.closeSubpath()
            var stem = Path()
            stem.move(to: CGPoint(x: 8, y: 10)); stem.addLine(to: CGPoint(x: 8, y: 14.5))
            let style = StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round)
            if pinned { context.fill(pin, with: .color(color)) }
            context.stroke(pin, with: .color(color), style: style)
            context.stroke(stem, with: .color(color), style: style)
            if !pinned {
                var slash = Path()
                slash.move(to: CGPoint(x: 2, y: 2)); slash.addLine(to: CGPoint(x: 14, y: 14))
                context.stroke(slash, with: .color(color), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
            }
        }
    }
}

// The small text panel for buttons and the empty glass, styled like the Windows tooltips.
struct TipView: View {
    let text: String
    let palette: Palette

    var body: some View {
        WrapWidth(limit: 296) {
            Text(text)
                .font(.system(size: 12))
                .foregroundColor(palette.text)
        }
        .padding(EdgeInsets(top: 8, leading: 12, bottom: 9, trailing: 12))
        .background(RoundedRectangle(cornerRadius: 12).fill(palette.menuBg))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(palette.menuRim, lineWidth: 1))
    }
}

// Lays text out at its natural width up to a limit and wraps it beyond that, reporting the wrapped height
// whatever size it's offered, so the panel measured from it fits every line.
struct WrapWidth: Layout {
    let limit: CGFloat

    private func width(_ child: LayoutSubview) -> CGFloat { min(child.sizeThatFits(.unspecified).width, limit) }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let child = subviews.first else { return .zero }
        return child.sizeThatFits(ProposedViewSize(width: width(child), height: nil))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard let child = subviews.first else { return }
        child.place(at: bounds.origin, anchor: .topLeading, proposal: ProposedViewSize(width: width(child), height: nil))
    }
}
