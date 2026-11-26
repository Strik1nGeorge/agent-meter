import AppKit
import SwiftUI

extension Color {
    init(rgb: UInt32, alpha: Double = 1) {
        self.init(.sRGB, red: Double((rgb >> 16) & 0xff) / 255, green: Double((rgb >> 8) & 0xff) / 255, blue: Double(rgb & 0xff) / 255, opacity: alpha)
    }
}

enum Brand {
    static let codexTop = Color(rgb: 0xb1a7ff), codexMid = Color(rgb: 0x7a9dff), codexBottom = Color(rgb: 0x3941ff)
    static let clay = Color(rgb: 0xd97757), clayDark = Color(rgb: 0xb35c40)
}

// The colours of desktop/Theme.cs: grey-white or graphite glass, grayscale text, one blue accent, system red
// for a nearly used-up quota, and the platforms' own colours. Follows the Mac's light/dark appearance;
// Reduce Transparency and Increase Contrast make the glass solid, as Windows' settings do.
struct Palette {
    var light: Bool
    var text: Color, textMuted: Color, accent: Color, low: Color
    var tint: Color, grain: UInt8, sheen: Double, highlight: [Double]?, edge: Color, rimOffline: Color
    var iconHover: Color, menuBg: Color, menuRim: Color
    var codexTrack: Color, claudeTrack: Color

    static func current(_ scheme: ColorScheme) -> Palette {
        let workspace = NSWorkspace.shared
        return of(scheme, solid: workspace.accessibilityDisplayShouldReduceTransparency, contrast: workspace.accessibilityDisplayShouldIncreaseContrast)
    }

    static func of(_ scheme: ColorScheme, solid: Bool = false, contrast: Bool = false) -> Palette {
        let light = scheme != .dark
        var palette: Palette
        if light {
            palette = Palette(light: true, text: Color(rgb: 0x1d1d1f), textMuted: Color(rgb: 0x86868b), accent: Color(rgb: 0x0071e3), low: Color(rgb: 0xff3b30),
                              tint: Color(rgb: 0xf5f5f7, alpha: solid ? 1 : 184 / 255), grain: solid ? 0 : 9, sheen: 64 / 255,
                              highlight: [235.0, 110, 30, 22].map { $0 / 255 }, edge: Color.black.opacity(30 / 255), rimOffline: Color(rgb: 0xff6b00, alpha: 220 / 255),
                              iconHover: Color.black.opacity(13 / 255), menuBg: Color(rgb: 0xfbfbfd, alpha: 250 / 255), menuRim: Color.black.opacity(18 / 255),
                              codexTrack: Color(rgb: 0x7a9dff, alpha: 48 / 255), claudeTrack: Color(rgb: 0xd97757, alpha: 48 / 255))
        } else {
            palette = Palette(light: false, text: Color(rgb: 0xf5f5f7), textMuted: Color(rgb: 0x98989d), accent: Color(rgb: 0x0a84ff), low: Color(rgb: 0xff453a),
                              tint: Color(rgb: 0x1c1c1e, alpha: solid ? 1 : 184 / 255), grain: solid ? 0 : 10, sheen: 18 / 255,
                              highlight: [80.0, 40, 14, 10].map { $0 / 255 }, edge: Color.black.opacity(96 / 255), rimOffline: Color(rgb: 0xff9f0a, alpha: 220 / 255),
                              iconHover: Color.white.opacity(20 / 255), menuBg: Color(rgb: 0x2c2c2e, alpha: 250 / 255), menuRim: Color.white.opacity(26 / 255),
                              codexTrack: Color(rgb: 0x7a9dff, alpha: 72 / 255), claudeTrack: Color(rgb: 0xd97757, alpha: 72 / 255))
        }
        if contrast {
            palette.tint = light ? .white : .black
            palette.edge = palette.text
            palette.grain = 0; palette.sheen = 0; palette.highlight = nil
        }
        return palette
    }
}

// The acrylic look over the window's blur, back to front: tint, grain, a soft gloss across the top, the
// darker outer edge, the bright highlight just inside it, and the rim that turns orange while the local
// service is offline. Same recipe as the Windows widget.
struct GlassLayers: View {
    let palette: Palette
    let size: CGSize
    let offline: Bool
    static let radius: CGFloat = 8

    var body: some View {
        let r = GlassLayers.radius
        ZStack {
            RoundedRectangle(cornerRadius: r).fill(palette.tint)
            if palette.grain > 0 { RoundedRectangle(cornerRadius: r).fill(ImagePaint(image: Noise.image(alpha: palette.grain), scale: 0.5)) }
            if palette.sheen > 0 {
                RoundedRectangle(cornerRadius: r).fill(LinearGradient(colors: [Color.white.opacity(palette.sheen), Color.white.opacity(0)], startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 30 / max(size.height, 1))))
            }
            RoundedRectangle(cornerRadius: r).strokeBorder(palette.edge, lineWidth: 1)
            if let alphas = palette.highlight {
                // Bright across the top, fading within the first few points so the sides stay faint.
                let light = LinearGradient(stops: [
                    .init(color: Color.white.opacity(alphas[0]), location: 0),
                    .init(color: Color.white.opacity(alphas[1]), location: 8 / 60),
                    .init(color: Color.white.opacity(alphas[2]), location: 26 / 60),
                    .init(color: Color.white.opacity(alphas[3]), location: 1),
                ], startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 60 / max(size.height, 1)))
                RoundedRectangle(cornerRadius: r - 1).strokeBorder(light, lineWidth: 1).padding(1)
            }
            if offline { RoundedRectangle(cornerRadius: r - 1).strokeBorder(palette.rimOffline, lineWidth: 1).padding(1) }
        }
        .frame(width: size.width, height: size.height)
    }
}

// Acrylic's noise: a fixed tile of grey specks at a few percent opacity. Seeded, so it never shimmers.
enum Noise {
    private static var cache: [UInt8: Image] = [:]

    static func image(alpha: UInt8) -> Image {
        if let cached = cache[alpha] { return cached }
        let size = 128
        var pixels = [UInt8](repeating: 0, count: size * size * 4)
        var seed: UInt32 = 7
        for i in stride(from: 0, to: pixels.count, by: 4) {
            seed = seed &* 1_664_525 &+ 1_013_904_223
            let grey = UInt32(seed >> 24)
            let value = UInt8(grey * UInt32(alpha) / 255)   // premultiplied
            pixels[i] = value; pixels[i + 1] = value; pixels[i + 2] = value; pixels[i + 3] = alpha
        }
        let provider = CGDataProvider(data: Data(pixels) as CFData)!
        let cgImage = CGImage(width: size, height: size, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: size * 4,
                              space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                              provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
        let image = Image(decorative: cgImage, scale: 1)
        cache[alpha] = image
        return image
    }
}
