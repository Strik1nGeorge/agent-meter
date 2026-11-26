import SwiftUI
import AgentMeterCore

// The hover card, laid out like the Windows one (desktop/AgentDetail.cs): header with the mark, name, plan and
// what the agents are doing; each quota window with its bar, pace tick, reset and forecast; today's usage;
// and where the quota came from.
struct CardView: View {
    let card: CardModel
    let palette: Palette

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header.padding(.bottom, 8)
            if let message = card.message { text(message, 11.5, muted: true).padding(.bottom, 4) }
            ForEach(Array(card.rows.enumerated()), id: \.offset) { _, row in rowView(row).padding(.bottom, 7) }
            if let hint = card.hint { text(hint, 10.5, muted: true).padding(.top, -2).padding(.bottom, 2) }
            if !card.usage.isEmpty || card.lastActive != nil {
                VStack(alignment: .leading, spacing: 1) {
                    ForEach(card.usage, id: \.self) { line in text(line, 11.5) }
                    if let last = card.lastActive { text(last, 11.5, muted: true) }
                }
                .padding(.top, 4)
            }
            if let footer = card.footer { text(footer, 10.5, muted: true).padding(.top, 8) }
        }
        .frame(width: 236, alignment: .leading)
        .padding(EdgeInsets(top: 8, leading: 12, bottom: 9, trailing: 12))
        .background(RoundedRectangle(cornerRadius: 12).fill(palette.menuBg))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(palette.menuRim, lineWidth: 1))
    }

    private func text(_ value: String, _ size: CGFloat, weight: Font.Weight = .regular, muted: Bool = false, color: Color? = nil) -> some View {
        Text(value)
            .font(.system(size: size, weight: weight))
            .foregroundColor(color ?? (muted ? palette.textMuted : palette.text))
            .fixedSize(horizontal: false, vertical: true)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 0) {
            logo.frame(width: 14, height: 14).padding(.trailing, 6)
            Text(card.title).font(.system(size: 13, weight: .semibold)).foregroundColor(palette.text).lineLimit(1)
            if let plan = card.plan {
                Text(plan).font(.system(size: 9.5, weight: .semibold)).foregroundColor(palette.textMuted)
                    .padding(EdgeInsets(top: 0, leading: 5, bottom: 1, trailing: 5))
                    .background(RoundedRectangle(cornerRadius: 6).fill(palette.iconHover))
                    .padding(.leading, 6)
            }
            Spacer(minLength: 6)
            // The dot carries the state's colour: green at work, red out of quota, otherwise the text's grey.
            (Text("● ").foregroundColor(card.mood == .working ? Color(rgb: 0x34c759) : card.mood == .exhausted ? palette.low : palette.textMuted)
                + Text(card.status).foregroundColor(palette.textMuted))
                .font(.system(size: 11.5))
                .lineLimit(1)
        }
    }

    private var logo: some View {
        Canvas { context, size in
            let scale = size.width / 24
            let path = (card.codex ? Logos.codex : Logos.claude).applying(CGAffineTransform(scaleX: scale, y: scale))
            if card.codex {
                context.fill(path, with: .linearGradient(Gradient(colors: [Brand.codexTop, Brand.codexBottom]), startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)), style: FillStyle(eoFill: true))
            } else {
                context.fill(path, with: .color(Brand.clay))
            }
        }
    }

    private func rowView(_ row: CardRow) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                text(row.title, 12)
                Spacer(minLength: 0)
                Text(row.percentText).font(.system(size: 12.5, weight: .semibold)).foregroundColor(row.low ? palette.low : palette.text)
            }
            bar(row).frame(height: 4).padding(.vertical, 3)
            text(row.reset, 10.5, muted: true)
            if let blocked = row.blocked { text(blocked, 10.5, muted: true) }
            if let forecast = row.forecast { text(forecast, 10.5, color: row.forecastWarn ? palette.low : palette.textMuted) }
        }
    }

    // The bar in the platform's colour over its track, with the pace tick where even use would leave it now.
    private func bar(_ row: CardRow) -> some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2).fill(card.codex ? Color(rgb: 0x7a9dff, alpha: 56 / 255) : Color(rgb: 0xd97757, alpha: 56 / 255))
                RoundedRectangle(cornerRadius: 2)
                    .fill(card.codex ? AnyShapeStyle(LinearGradient(colors: [Brand.codexTop, Brand.codexBottom], startPoint: .leading, endPoint: .trailing)) : AnyShapeStyle(Brand.clay))
                    .frame(width: width * max(0, min(1, row.fill)))
                if let tick = row.tick {
                    RoundedRectangle(cornerRadius: 0.75).fill(palette.text.opacity(0.6))
                        .frame(width: 1.5, height: 8)
                        .offset(x: width * max(0, min(1, tick)) - 0.75)
                }
            }
        }
    }
}
