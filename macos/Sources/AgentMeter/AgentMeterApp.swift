import AppKit
import SwiftUI
import AgentMeterCore

// Command line: [--root <project folder>] [--url <local service>] [--preview <folder>]
struct Options {
    var root: URL
    var server: URL
    var preview: URL?

    static func parse(_ args: [String]) -> Options {
        var root: URL? = nil
        var server = URL(string: "http://127.0.0.1:4318")!
        var preview: URL? = nil
        var i = 1
        while i < args.count {
            let value = i + 1 < args.count ? args[i + 1] : nil
            switch args[i] {
            case "--root":
                if let value { root = URL(fileURLWithPath: value); i += 1 }
            case "--url":
                // Only the local service on this Mac, as on Windows.
                if let value {
                    if let url = URL(string: value), url.scheme == "http", ["127.0.0.1", "localhost"].contains(url.host ?? "") { server = url }
                    i += 1
                }
            case "--preview":
                if let value { preview = URL(fileURLWithPath: value); i += 1 }
            default:
                break
            }
            i += 1
        }
        return Options(root: root ?? defaultRoot(), server: server, preview: preview)
    }

    // build.sh puts the app in macos/bin/Agent Meter.app, three levels below the project folder.
    static func defaultRoot() -> URL {
        let bundle = Bundle.main.bundleURL
        if bundle.pathExtension == "app" {
            return bundle.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        }
        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    }
}

@main
enum AgentMeterMain {
    @MainActor static func main() {
        let options = Options.parse(CommandLine.arguments)
        if let folder = options.preview { exit(Preview.export(to: folder, server: options.server)) }
        let app = NSApplication.shared
        let delegate = AppDelegate(options: options)
        app.delegate = delegate
        // A widget, not a regular app: no Dock icon, never takes focus from what you are working in.
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { app.run() }
    }
}

extension Notification.Name {
    static let agentMeterShow = Notification.Name("com.agentmeter.widget.show")
    static let agentMeterQuit = Notification.Name("com.agentmeter.widget.quit")
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let options: Options
    var controller: WidgetController?

    init(options: Options) { self.options = options; super.init() }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let me = ProcessInfo.processInfo.processIdentifier
        if let id = Bundle.main.bundleIdentifier, NSRunningApplication.runningApplications(withBundleIdentifier: id).contains(where: { $0.processIdentifier != me }) {
            // Already running: a second launch asks that copy to show itself, as on Windows.
            DistributedNotificationCenter.default().postNotificationName(.agentMeterShow, object: nil, userInfo: nil, deliverImmediately: true)
            NSApp.terminate(nil)
            return
        }
        let controller = WidgetController(model: WidgetModel(options: options))
        self.controller = controller
        controller.start()
        let center = DistributedNotificationCenter.default()
        center.addObserver(forName: .agentMeterShow, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.controller?.showWidget() }
        }
        center.addObserver(forName: .agentMeterQuit, object: nil, queue: .main) { _ in
            Task { @MainActor in NSApp.terminate(nil) }
        }
    }

    func applicationWillTerminate(_ notification: Notification) { controller?.stop() }
}
