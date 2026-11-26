import SwiftUI
import AgentMeterCore

// The platform's mascot, drawn and animated like desktop/Pet.cs: Codex is a blue-violet cloud with a ">_"
// prompt for a mouth, Claude an orange blob with a sparkle on a sprout. Moods:
//   working   — hops; Claude's sparkle spins, Codex's cursor blinks
//   idle      — breathes and blinks
//   tired     — under 20% left: half-closed eyes, slow breath, a bead of sweat
//   exhausted — a quota window is used up: melted flat, asleep, "z z Z" drifting up
//   offline   — the local service is down: greyed, eyes closed, still
struct PetView: View {
    let codex: Bool
    let mood: PetMood
    let animating: Bool
    let palette: Palette

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !animating)) { timeline in
            Canvas { context, _ in
                PetDrawing(codex: codex, mood: mood, time: timeline.date.timeIntervalSinceReferenceDate, moving: animating, text: palette.text).draw(&context)
            }
        }
        .frame(width: 30, height: 30)
        .opacity(mood == .offline ? 0.45 : 1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel((codex ? "Codex" : "Claude Code") + " · " + mood.label)
        .accessibilityAddTraits(.isImage)
    }
}

struct PetDrawing {
    let codex: Bool
    let mood: PetMood
    let time: Double
    let moving: Bool
    let text: Color

    static let lidCodex = Color(rgb: 0x141752), lidClaude = Color(rgb: 0x3b2418), pupil = Color(rgb: 0x1d1d1f)

    // WPF's SineEase / QuadraticEase(EaseOut), played forward then back like AutoReverse.
    static func sine(_ t: Double) -> Double { -(cos(Double.pi * t) - 1) / 2 }
    static func quadOut(_ t: Double) -> Double { 1 - (1 - t) * (1 - t) }
    func loop(_ from: Double, _ to: Double, _ seconds: Double, _ ease: (Double) -> Double = PetDrawing.sine) -> Double {
        let cycle = time.truncatingRemainder(dividingBy: 2 * seconds)
        let forward = cycle < seconds ? cycle / seconds : (2 * seconds - cycle) / seconds
        return from + (to - from) * ease(forward)
    }

    func draw(_ context: inout GraphicsContext) {
        let asleep = mood == .offline || mood == .exhausted
        let exhausted = mood == .exhausted
        context.fill(Path(ellipseIn: CGRect(x: exhausted ? 3.5 : 6, y: 26.2, width: exhausted ? 23 : 18, height: 3)), with: .color(Color.black.opacity(34 / 255)))

        // Body: melted flat when exhausted, hopping when working, breathing otherwise.
        var scaleX = exhausted ? 1.16 : 1.0, scaleY = exhausted ? 0.6 : 1.0, hop = 0.0
        if moving {
            switch mood {
            case .working: scaleY = loop(0.95, 1.04, 0.34, PetDrawing.quadOut); hop = loop(0, -2.4, 0.34, PetDrawing.quadOut)
            case .exhausted: scaleY = loop(0.6, 0.63, 3.2)
            case .tired: scaleY = loop(1, 1.03, 3.6)
            case .idle: scaleY = loop(1, 1.035, 2.6); scaleX = loop(1, 0.985, 2.6)
            case .offline: break
            }
        }
        let lean = exhausted ? -6.0 : mood == .tired ? 3.0 : 0.0
        var body = context
        body.translateBy(x: 0, y: hop)
        body.translateBy(x: 15, y: 27)
        body.rotate(by: .degrees(lean))
        body.scaleBy(x: scaleX, y: scaleY)
        body.translateBy(x: -15, y: -27)
        let eyeY: CGFloat = codex ? 16.3 : 17.2
        if codex { drawCloud(&body, eyeY: eyeY) } else { drawBlob(&body, eyeY: eyeY) }
        drawEyes(&body, eyeY: eyeY, asleep: asleep)

        // A bead of sweat when tired.
        if mood == .tired {
            var sweat = context
            sweat.translateBy(x: 25, y: 8.5 + (moving ? loop(0, 2.2, 1.4) : 0))
            var drop = Path()
            drop.move(to: .zero)
            drop.addCurve(to: CGPoint(x: -1.5, y: 3.2), control1: CGPoint(x: -0.2, y: 0.9), control2: CGPoint(x: -1.5, y: 2.2))
            drop.addCurve(to: CGPoint(x: 0, y: 4.7), control1: CGPoint(x: -1.5, y: 4.03), control2: CGPoint(x: -0.83, y: 4.7))
            drop.addCurve(to: CGPoint(x: 1.5, y: 3.2), control1: CGPoint(x: 0.83, y: 4.7), control2: CGPoint(x: 1.5, y: 4.03))
            drop.addCurve(to: .zero, control1: CGPoint(x: 1.5, y: 2.2), control2: CGPoint(x: 0.2, y: 0.9))
            drop.closeSubpath()
            sweat.fill(drop, with: .color(Color(rgb: 0x7cc8ff)))
        }

        // Asleep: three z's drift up and fade, one after another.
        if exhausted {
            for i in 0..<3 {
                var rise = 0.0, drift = 0.0, alpha = 0.55 + Double(i) * 0.15
                if moving {
                    var phase = (time - Double(i) * 0.9).truncatingRemainder(dividingBy: 2.7) / 2.7
                    if phase < 0 { phase += 1 }
                    rise = -7 * phase; drift = 3 * phase
                    alpha = phase < 0.3 ? 0.9 * phase / 0.3 : 0.9 * (1 - (phase - 0.3) / 0.7)
                }
                var z = context
                z.opacity = alpha
                let letter = Text(i == 2 ? "Z" : "z").font(.system(size: 5.5 + Double(i) * 1.2, weight: .bold)).foregroundColor(text)
                z.draw(letter, at: CGPoint(x: 20 + Double(i) * 2.6 + drift, y: 10 - Double(i) * 3.4 + rise), anchor: .topLeading)
            }
        }
    }

    // The Codex cloud: a rounded body with three bumps on top, lit from above like the logo.
    private func drawCloud(_ context: inout GraphicsContext, eyeY: CGFloat) {
        let fill = GraphicsContext.Shading.linearGradient(Gradient(colors: [Brand.codexTop, Brand.codexMid, Brand.codexBottom]), startPoint: CGPoint(x: 15, y: 4.3), endPoint: CGPoint(x: 15, y: 27))
        // Filled part by part with one shared gradient, so the overlaps join seamlessly.
        context.fill(Path(roundedRect: CGRect(x: 5, y: 11.5, width: 20, height: 15.5), cornerRadius: 7.5), with: fill)
        for (x, y, r) in [(10.0, 12.5, 4.6), (15.4, 9.6, 5.3), (20.6, 12.8, 4.3)] {
            context.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)), with: fill)
        }
        // ">_" for a mouth; the underscore is the cursor that blinks while working.
        var prompt = Path()
        prompt.move(to: CGPoint(x: 12.4, y: 20.2)); prompt.addLine(to: CGPoint(x: 14.2, y: 21.4)); prompt.addLine(to: CGPoint(x: 12.4, y: 22.6))
        context.stroke(prompt, with: .color(Color.white.opacity(0.92)), style: StrokeStyle(lineWidth: 1.1, lineCap: .round, lineJoin: .round))
        let cursorOn = !(moving && mood == .working) || time.truncatingRemainder(dividingBy: 1) < 0.5
        if cursorOn { context.fill(Path(roundedRect: CGRect(x: 15, y: 22.1, width: 2.8, height: 0.95), cornerRadius: 0.4), with: .color(Color.white.opacity(0.92))) }
        cheeks(&context, color: Color(rgb: 0xffb3e6, alpha: 90 / 255), y: eyeY + 3.4)
    }

    // The Claude blob, with a sparkle like its mark growing from a little sprout.
    private func drawBlob(_ context: inout GraphicsContext, eyeY: CGFloat) {
        context.fill(Path(roundedRect: CGRect(x: 5, y: 11, width: 20, height: 16), cornerRadius: 7.5), with: .color(Brand.clay))
        var sprout = Path()
        sprout.move(to: CGPoint(x: 15, y: 11.2)); sprout.addQuadCurve(to: CGPoint(x: 15.9, y: 7.4), control: CGPoint(x: 15, y: 8.6))
        context.stroke(sprout, with: .color(Brand.clayDark), style: StrokeStyle(lineWidth: 1.2, lineCap: .round))
        var sparkle = context
        sparkle.translateBy(x: 16, y: 5)
        if moving && mood == .working { sparkle.rotate(by: .degrees(time.truncatingRemainder(dividingBy: 1.4) / 1.4 * 360)) }
        var rays = Path()
        for i in 0..<8 {
            let angle = Double(i) * Double.pi / 4, reach = i % 2 == 0 ? 3.1 : 2.2
            rays.move(to: .zero); rays.addLine(to: CGPoint(x: reach * sin(angle), y: -reach * cos(angle)))
        }
        sparkle.stroke(rays, with: .color(Brand.clay), style: StrokeStyle(lineWidth: 1.25, lineCap: .round))
        var mouth = Path()
        mouth.move(to: CGPoint(x: 13.8, y: 21.1)); mouth.addQuadCurve(to: CGPoint(x: 16.2, y: 21.1), control: CGPoint(x: 15, y: 22.3))
        context.stroke(mouth, with: .color(PetDrawing.lidClaude), style: StrokeStyle(lineWidth: 0.95, lineCap: .round))
        cheeks(&context, color: Color(rgb: 0xffa88c, alpha: 110 / 255), y: eyeY + 3.2)
    }

    private func cheeks(_ context: inout GraphicsContext, color: Color, y: CGFloat) {
        for x in [8.6, 21.4] { context.fill(Path(ellipseIn: CGRect(x: x - 1.5, y: y - 0.95, width: 3, height: 1.9)), with: .color(color)) }
    }

    // Whites with dark pupils that blink by squashing toward the eye line; closed curves when asleep.
    private func drawEyes(_ context: inout GraphicsContext, eyeY: CGFloat, asleep: Bool) {
        let xs: [CGFloat] = codex ? [11.3, 18.7] : [11.6, 18.4]
        let lid = codex ? PetDrawing.lidCodex : PetDrawing.lidClaude
        if asleep {
            for x in xs {
                var closed = Path()
                closed.move(to: CGPoint(x: x - 2, y: eyeY)); closed.addQuadCurve(to: CGPoint(x: x + 2, y: eyeY), control: CGPoint(x: x, y: eyeY + 1.6))
                context.stroke(closed, with: .color(lid), style: StrokeStyle(lineWidth: 1.1, lineCap: .round))
            }
            return
        }
        var blink = mood == .tired ? 0.5 : 1.0
        if moving && (mood == .idle || mood == .working) {
            let cycle = mood == .working ? 3.2 : 4.2, closeAt = mood == .working ? 2.9 : 3.8
            let t = time.truncatingRemainder(dividingBy: cycle)
            if t >= closeAt && t < closeAt + 0.07 { blink = 1 - 0.9 * (t - closeAt) / 0.07 }
            else if t >= closeAt + 0.07 && t < closeAt + 0.16 { blink = 0.1 + 0.9 * (t - closeAt - 0.07) / 0.09 }
        }
        var eyes = context
        eyes.translateBy(x: 0, y: eyeY)
        eyes.scaleBy(x: 1, y: blink)
        eyes.translateBy(x: 0, y: -eyeY)
        for x in xs {
            eyes.fill(Path(ellipseIn: CGRect(x: x - 2.2, y: eyeY - 2.5, width: 4.4, height: 5.0)), with: .color(.white))
            eyes.fill(Path(ellipseIn: CGRect(x: x - 0.9, y: eyeY - 1.1, width: 2.4, height: 2.9)), with: .color(PetDrawing.pupil))
            eyes.fill(Path(ellipseIn: CGRect(x: x - 0.2, y: eyeY - 0.9, width: 0.9, height: 0.9)), with: .color(.white))
        }
    }
}
