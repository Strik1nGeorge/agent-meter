import AppKit
import SwiftUI
import AgentMeterCore

// --preview <folder> [--url <service>]: draws the widget and its hover cards from the service's current data
// into PNG files, at 2×, in light and dark and both languages. The macOS CI job uses it to check how they
// look without a Mac at hand. The window server's blur doesn't appear in these renders; everything drawn
// over it does.
@MainActor
enum Preview {
    static func export(to folder: URL, server: URL) -> Int32 {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        guard let data = try? Data(contentsOf: server.appendingPathComponent("api/quotas")),
              let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data) else {
            print("Preview: no data from \(server.absoluteString)")
            return 1
        }
        var written = 0, failed = 0
        func model(dock: String? = nil, center: String = "outer") -> WidgetModel {
            let model = WidgetModel(options: Options(root: folder, server: server, preview: folder))
            model.snapshot = snapshot
            model.online = true
            model.visible = false
            model.state.dock = dock
            model.state.center = center
            return model
        }
        for language in ["zh", "en"] {
            Lang.apply(language)
            for scheme in [ColorScheme.light, ColorScheme.dark] {
                let suffix = "\(scheme == .dark ? "dark" : "light")-\(language)"
                let layouts: [(String, String?, String)] = [("strip", nil, "outer"), ("strip-week", nil, "inner"), ("column", "left", "outer")]
                for (name, dock, center) in layouts {
                    let view = WidgetView(model: model(dock: dock, center: center)).environment(\.colorScheme, scheme)
                    if write(view, folder.appendingPathComponent("\(name)-\(suffix).png")) { written += 1 } else { failed += 1 }
                }
                for id in ["codex", "claude"] {
                    let view = CardView(card: model().card(id), palette: Palette.of(scheme)).environment(\.colorScheme, scheme)
                    if write(view, folder.appendingPathComponent("card-\(id)-\(suffix).png")) { written += 1 } else { failed += 1 }
                }
            }
        }
        print("Preview: wrote \(written) images, \(failed) failed")
        return failed == 0 ? 0 : 1
    }

    static func write<V: View>(_ view: V, _ url: URL) -> Bool {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        guard let image = renderer.cgImage else { return false }
        guard let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else { return false }
        return (try? png.write(to: url)) != nil
    }
}
