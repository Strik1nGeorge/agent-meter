import SwiftUI

// The platform marks on a 24×24 grid, from LobeHub icons (MIT); the marks are trademarks of OpenAI and
// Anthropic. Same paths as public/app.js and desktop/Logos.cs, parsed from SVG path data.
enum Logos {
    static let codex = SVGPath.parse("M8.086 0.457a6.105 6.105 0 0 1 3.046-0.415c1.333 0.153 2.521 0.72 3.564 1.7a0.117 0.117 0 0 0 0.107 0.029c1.408-0.346 2.762-0.224 4.061 0.366l0.063 0.03l0.154 0.076c1.357 0.703 2.33 1.77 2.918 3.198c0.278 0.679 0.418 1.388 0.421 2.126a5.655 5.655 0 0 1-0.18 1.631a0.167 0.167 0 0 0 0.04 0.155a5.982 5.982 0 0 1 1.578 2.891c0.385 1.901-0.01 3.615-1.183 5.14l-0.182 0.22a6.063 6.063 0 0 1-2.934 1.851a0.162 0.162 0 0 0-0.108 0.102c-0.255 0.736-0.511 1.364-0.987 1.992c-1.199 1.582-2.962 2.462-4.948 2.451c-1.583-0.008-2.986-0.587-4.21-1.736a0.145 0.145 0 0 0-0.14-0.032c-0.518 0.167-1.04 0.191-1.604 0.185a5.924 5.924 0 0 1-2.595-0.622a6.058 6.058 0 0 1-2.146-1.781c-0.203-0.269-0.404-0.522-0.551-0.821a7.74 7.74 0 0 1-0.495-1.283a6.11 6.11 0 0 1-0.017-3.064a0.166 0.166 0 0 0 0.008-0.074a0.115 0.115 0 0 0-0.037-0.064a5.958 5.958 0 0 1-1.38-2.202a5.196 5.196 0 0 1-0.333-1.589a6.915 6.915 0 0 1 0.188-2.132c0.45-1.484 1.309-2.648 2.577-3.493c0.282-0.188 0.55-0.334 0.802-0.438c0.286-0.12 0.573-0.22 0.861-0.304a0.129 0.129 0 0 0 0.087-0.087A6.016 6.016 0 0 1 5.635 2.31C6.315 1.464 7.132 0.846 8.086 0.457z m-0.804 7.85a0.848 0.848 0 0 0-1.473 0.842l1.694 2.965l-1.688 2.848a0.849 0.849 0 0 0 1.46 0.864l1.94-3.272a0.849 0.849 0 0 0 0.007-0.854l-1.94-3.393z m5.446 6.24a0.849 0.849 0 0 0 0 1.695h4.848a0.849 0.849 0 0 0 0-1.696h-4.848z")
    static let claude = SVGPath.parse("M4.709 15.955l4.72-2.647l0.08-0.23l-0.08-0.128H9.2l-0.79-0.048l-2.698-0.073l-2.339-0.097l-2.266-0.122l-0.571-0.121L0 11.784l0.055-0.352l0.48-0.321l0.686 0.06l1.52 0.103l2.278 0.158l1.652 0.097l2.449 0.255h0.389l0.055-0.157l-0.134-0.098l-0.103-0.097l-2.358-1.596l-2.552-1.688l-1.336-0.972l-0.724-0.491l-0.364-0.462l-0.158-1.008l0.656-0.722l0.881 0.06l0.225 0.061l0.893 0.686l1.908 1.476l2.491 1.833l0.365 0.304l0.145-0.103l0.019-0.073l-0.164-0.274l-1.355-2.446l-1.446-2.49l-0.644-1.032l-0.17-0.619a2.97 2.97 0 0 1-0.104-0.729L6.283 0.134L6.696 0l0.996 0.134l0.42 0.364l0.62 1.414l1.002 2.229l1.555 3.03l0.456 0.898l0.243 0.832l0.091 0.255h0.158V9.01l0.128-1.706l0.237-2.095l0.23-2.695l0.08-0.76l0.376-0.91l0.747-0.492l0.584 0.28l0.48 0.685l-0.067 0.444l-0.286 1.851l-0.559 2.903l-0.364 1.942h0.212l0.243-0.242l0.985-1.306l1.652-2.064l0.73-0.82l0.85-0.904l0.547-0.431h1.033l0.76 1.129l-0.34 1.166l-1.064 1.347l-0.881 1.142l-1.264 1.7l-0.79 1.36l0.073 0.11l0.188-0.02l2.856-0.606l1.543-0.28l1.841-0.315l0.833 0.388l0.091 0.395l-0.328 0.807l-1.969 0.486l-2.309 0.462l-3.439 0.813l-0.042 0.03l0.049 0.061l1.549 0.146l0.662 0.036h1.622l3.02 0.225l0.79 0.522l0.474 0.638l-0.079 0.485l-1.215 0.62l-1.64-0.389l-3.829-0.91l-1.312-0.329h-0.182v0.11l1.093 1.068l2.006 1.81l2.509 2.33l0.127 0.578l-0.322 0.455l-0.34-0.049l-2.205-1.657l-0.851-0.747l-1.926-1.62h-0.128v0.17l0.444 0.649l2.345 3.521l0.122 1.08l-0.17 0.353l-0.608 0.213l-0.668-0.122l-1.374-1.925l-1.415-2.167l-1.143-1.943l-0.14 0.08l-0.674 7.254l-0.316 0.37l-0.729 0.28l-0.607-0.461l-0.322-0.747l0.322-1.476l0.389-1.924l0.315-1.53l0.286-1.9l0.17-0.632l-0.012-0.042l-0.14 0.018l-1.434 1.967l-2.18 2.945l-1.726 1.845l-0.414 0.164l-0.717-0.37l0.067-0.662l0.401-0.589l2.388-3.036l1.44-1.882l0.93-1.086l-0.006-0.158h-0.055L4.132 18.56l-1.13 0.146l-0.487-0.456l0.061-0.746l0.231-0.243l1.908-1.312l-0.006 0.006z")
}

// Enough of SVG path syntax for the marks: M L H V C A Z, absolute and relative, with implicit repeats.
enum SVGPath {
    static func parse(_ data: String) -> Path {
        var path = Path()
        var scanner = Scanner(Array(data.utf8))
        var current = CGPoint.zero, start = CGPoint.zero
        var command: UInt8 = UInt8(ascii: "M")
        while let next = scanner.command(default: command) {
            command = next
            let relative = command >= UInt8(ascii: "a")
            let origin = relative ? current : .zero
            switch command | 0x20 {
            case UInt8(ascii: "m"):
                guard let x = scanner.number(), let y = scanner.number() else { return path }
                current = CGPoint(x: origin.x + x, y: origin.y + y); start = current
                path.move(to: current)
                command = relative ? UInt8(ascii: "l") : UInt8(ascii: "L")
            case UInt8(ascii: "l"):
                guard let x = scanner.number(), let y = scanner.number() else { return path }
                current = CGPoint(x: origin.x + x, y: origin.y + y); path.addLine(to: current)
            case UInt8(ascii: "h"):
                guard let x = scanner.number() else { return path }
                current = CGPoint(x: (relative ? current.x : 0) + x, y: current.y); path.addLine(to: current)
            case UInt8(ascii: "v"):
                guard let y = scanner.number() else { return path }
                current = CGPoint(x: current.x, y: (relative ? current.y : 0) + y); path.addLine(to: current)
            case UInt8(ascii: "c"):
                guard let x1 = scanner.number(), let y1 = scanner.number(), let x2 = scanner.number(), let y2 = scanner.number(), let x = scanner.number(), let y = scanner.number() else { return path }
                let end = CGPoint(x: origin.x + x, y: origin.y + y)
                path.addCurve(to: end, control1: CGPoint(x: origin.x + x1, y: origin.y + y1), control2: CGPoint(x: origin.x + x2, y: origin.y + y2))
                current = end
            case UInt8(ascii: "a"):
                guard let rx = scanner.number(), let ry = scanner.number(), scanner.number() != nil, let large = scanner.flag(), let sweep = scanner.flag(), let x = scanner.number(), let y = scanner.number() else { return path }
                let end = CGPoint(x: origin.x + x, y: origin.y + y)
                arc(&path, from: current, to: end, radius: max(abs(rx), abs(ry)), large: large, sweep: sweep)
                current = end
            case UInt8(ascii: "z"):
                path.closeSubpath(); current = start
            default:
                return path
            }
        }
        return path
    }

    // A circular arc (the marks use equal radii), from SVG's endpoint form to a centre and two angles.
    static func arc(_ path: inout Path, from p1: CGPoint, to p2: CGPoint, radius: CGFloat, large: Bool, sweep: Bool) {
        if radius == 0 || p1 == p2 { path.addLine(to: p2); return }
        let hx = (p1.x - p2.x) / 2, hy = (p1.y - p2.y) / 2
        let r = max(radius, (hx * hx + hy * hy).squareRoot())
        let numerator = max(0, r * r - hx * hx - hy * hy), denominator = hx * hx + hy * hy
        let coefficient = (large != sweep ? 1 : -1) * (numerator / denominator).squareRoot()
        let center = CGPoint(x: coefficient * hy + (p1.x + p2.x) / 2, y: -coefficient * hx + (p1.y + p2.y) / 2)
        let a1 = atan2(p1.y - center.y, p1.x - center.x), a2 = atan2(p2.y - center.y, p2.x - center.x)
        // SVG's sweep flag 1 runs toward increasing angles, which is SwiftUI's clockwise: false.
        path.addArc(center: center, radius: r, startAngle: .radians(Double(a1)), endAngle: .radians(Double(a2)), clockwise: !sweep)
    }

    struct Scanner {
        let bytes: [UInt8]
        var index = 0
        init(_ bytes: [UInt8]) { self.bytes = bytes }

        mutating func skip() { while index < bytes.count, bytes[index] == 32 || bytes[index] == 44 || bytes[index] == 9 || bytes[index] == 10 || bytes[index] == 13 { index += 1 } }

        // The next command letter, or the previous command again when numbers follow it.
        mutating func command(default previous: UInt8) -> UInt8? {
            skip()
            guard index < bytes.count else { return nil }
            let byte = bytes[index]
            if (byte >= 65 && byte <= 90) || (byte >= 97 && byte <= 122) { index += 1; return byte }
            return previous
        }

        mutating func flag() -> Bool? {
            skip()
            guard index < bytes.count, bytes[index] == 48 || bytes[index] == 49 else { return nil }
            index += 1
            return bytes[index - 1] == 49
        }

        mutating func number() -> CGFloat? {
            skip()
            let begin = index
            if index < bytes.count, bytes[index] == 43 || bytes[index] == 45 { index += 1 }
            var dot = false, digits = false
            while index < bytes.count {
                let byte = bytes[index]
                if byte >= 48 && byte <= 57 { digits = true; index += 1 }
                else if byte == 46 && !dot { dot = true; index += 1 }
                else if (byte == 101 || byte == 69) && digits {
                    index += 1
                    if index < bytes.count, bytes[index] == 43 || bytes[index] == 45 { index += 1 }
                } else { break }
            }
            guard digits, let text = String(bytes: bytes[begin..<index], encoding: .ascii), let value = Double(text) else { index = begin; return nil }
            return CGFloat(value)
        }
    }
}
