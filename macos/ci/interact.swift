// CI only: drives the running widget with synthetic mouse events and screenshots each step, so the macOS job
// can check hovering, clicking a ring and docking against the screen edge on a real Mac.
// Usage: swift macos/ci/interact.swift <output folder>
import AppKit
import CoreGraphics

let folder = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."

func widgetBounds() -> CGRect? {
    guard let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] else { return nil }
    for window in windows where (window[kCGWindowOwnerName as String] as? String) == "AgentMeter" {
        guard let bounds = window[kCGWindowBounds as String] as? [String: CGFloat], let width = bounds["Width"], let height = bounds["Height"] else { continue }
        // The widget itself, not a hover card or tip.
        if (abs(width - 246) < 2 && abs(height - 52) < 2) || (abs(width - 58) < 2 && abs(height - 260) < 2) {
            return CGRect(x: bounds["X"] ?? 0, y: bounds["Y"] ?? 0, width: width, height: height)
        }
    }
    return nil
}

func windows() -> String {
    guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] else { return "none" }
    return list.filter { ($0[kCGWindowOwnerName as String] as? String) == "AgentMeter" }
        .map { "\($0[kCGWindowBounds as String] ?? "?")" }.joined(separator: " | ")
}

func post(_ type: CGEventType, _ point: CGPoint) {
    CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cghidEventTap)
    usleep(25_000)
}

func capture(_ name: String) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
    process.arguments = ["-x", "\(folder)/\(name)"]
    try? process.run()
    process.waitUntilExit()
}

print("accessibility trusted: \(AXIsProcessTrusted())")
guard let start = widgetBounds() else { print("widget window not found; AgentMeter windows: \(windows())"); exit(1) }
print("widget at \(start)")
capture("real-1-strip.png")

// Hover Claude's ring: its card should open under the strip.
post(.mouseMoved, CGPoint(x: start.minX + 140, y: start.midY))
usleep(100_000)
post(.mouseMoved, CGPoint(x: start.minX + 142, y: start.midY))
sleep(1)
print("after hover: \(windows())")
capture("real-2-hover.png")

// Click Codex's ring: the middles switch to the 7-day window.
let ring = CGPoint(x: start.minX + 63, y: start.midY)
post(.mouseMoved, ring)
post(.leftMouseDown, ring)
post(.leftMouseUp, ring)
sleep(1)
capture("real-3-click.png")

// Drag from empty glass to the left edge of the screen: the strip becomes a column there.
let grab = CGPoint(x: start.minX + 182, y: start.midY)
post(.mouseMoved, grab)
post(.leftMouseDown, grab)
for step in 1...24 { post(.leftMouseDragged, CGPoint(x: grab.x - (grab.x - 4) * CGFloat(step) / 24, y: grab.y)) }
post(.leftMouseUp, CGPoint(x: 4, y: grab.y))
sleep(1)
print("after drag: \(widgetBounds().map { "\($0)" } ?? "not found") — \(windows())")
capture("real-4-docked.png")
