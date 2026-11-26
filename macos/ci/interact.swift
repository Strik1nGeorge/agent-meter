// CI only: drives the running widget with synthetic mouse events and screenshots each step, so the macOS job
// can check hovering, clicking a ring, docking against the screen edge and the ⋯ menu on a real Mac.
// Usage: swift macos/ci/interact.swift <output folder> <widget process id>
import AppKit
import CoreGraphics

let folder = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."
let pid = CommandLine.arguments.count > 2 ? Int(CommandLine.arguments[2]) ?? -1 : -1

// The widget's windows, by process (a bundled app's windows are listed under its display name).
func ownWindows() -> [(CGRect, Int)] {
    guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] else { return [] }
    return list.compactMap { window -> (CGRect, Int)? in
        let owner = window[kCGWindowOwnerPID as String] as? Int ?? -2
        let name = window[kCGWindowOwnerName as String] as? String ?? ""
        guard owner == pid || name == "Agent Meter" || name == "AgentMeter",
              let dictionary = window[kCGWindowBounds as String] as? NSDictionary,
              let bounds = CGRect(dictionaryRepresentation: dictionary as CFDictionary) else { return nil }
        return (bounds, window[kCGWindowLayer as String] as? Int ?? 0)
    }
}

// The widget itself, not a hover card or tip.
func widgetBounds() -> CGRect? {
    ownWindows().map(\.0).first { (abs($0.width - 246) < 2 && abs($0.height - 52) < 2) || (abs($0.width - 58) < 2 && abs($0.height - 260) < 2) }
}

func windows() -> String {
    let own = ownWindows()
    return own.isEmpty ? "none" : own.map { "\($0.0) layer \($0.1)" }.joined(separator: " | ")
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

// Drag from empty glass (the gap between the two tiles, x 85–95) to the left edge of the screen: the strip
// becomes a column there.
let grab = CGPoint(x: start.minX + 90, y: start.midY)
post(.mouseMoved, grab)
post(.leftMouseDown, grab)
for step in 1...24 { post(.leftMouseDragged, CGPoint(x: grab.x - (grab.x - 4) * CGFloat(step) / 24, y: grab.y)) }
post(.leftMouseUp, CGPoint(x: 4, y: grab.y))
sleep(1)
print("after drag: \(widgetBounds().map { "\($0)" } ?? "not found") — \(windows())")
capture("real-4-docked.png")

guard let column = widgetBounds(), column.width < 100 else { print("not docked as a column"); exit(1) }

// In the column, hover Claude's ring (its centre is 148 pt down): the card opens beside the column.
post(.mouseMoved, CGPoint(x: column.midX, y: column.minY + 140))
usleep(100_000)
post(.mouseMoved, CGPoint(x: column.midX, y: column.minY + 148))
sleep(1)
print("column hover: \(windows())")
capture("real-5-column-card.png")

// The ⋯ button at the foot of the column opens the menu.
let more = CGPoint(x: column.midX, y: column.maxY - 18)
post(.mouseMoved, more)
post(.leftMouseDown, more)
post(.leftMouseUp, more)
sleep(1)
print("menu: \(windows())")
capture("real-6-menu.png")
for down in [true, false] { CGEvent(keyboardEventSource: nil, virtualKey: 53, keyDown: down)?.post(tap: .cghidEventTap) }
usleep(500_000)
if ownWindows().contains(where: { $0.1 >= 100 }) {
    // Escape didn't reach the menu: a click elsewhere closes it.
    let away = CGPoint(x: 500, y: 400)
    post(.mouseMoved, away); post(.leftMouseDown, away); post(.leftMouseUp, away)
    usleep(500_000)
}
print("after menu: \(windows())")
