import AppKit
import SwiftUI

// The widget's window: borderless and never takes focus from what you are working in.
final class WidgetPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    // Rounded corners for the window server's blur, stretched to any size.
    static func mask(radius: CGFloat) -> NSImage {
        let edge = radius * 2 + 1
        let image = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }
}

// Handles the mouse for the whole strip. macOS doesn't send SwiftUI's hover events to an app that isn't
// active, and the widget never is, so tracking runs here with .activeAlways.
final class InteractionView: NSView {
    weak var controller: WidgetController?
    private var tracking: NSTrackingArea?

    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func isAccessibilityElement() -> Bool { false }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking = tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(area)
        tracking = area
    }

    private func point(_ event: NSEvent) -> CGPoint { convert(event.locationInWindow, from: nil) }
    override func mouseEntered(with event: NSEvent) { MainActor.assumeIsolated { controller?.pointerMoved(point(event)) } }
    override func mouseMoved(with event: NSEvent) { MainActor.assumeIsolated { controller?.pointerMoved(point(event)) } }
    override func mouseExited(with event: NSEvent) { MainActor.assumeIsolated { controller?.pointerLeft() } }
    override func mouseDown(with event: NSEvent) { MainActor.assumeIsolated { controller?.mouseDown(point(event)) } }
    override func mouseDragged(with event: NSEvent) { MainActor.assumeIsolated { controller?.mouseDragged() } }
    override func mouseUp(with event: NSEvent) { MainActor.assumeIsolated { controller?.mouseUp(point(event)) } }
}

// A borderless panel for the hover card and tips. It never takes focus or catches the mouse.
@MainActor
final class FloatingPanel {
    let panel: NSPanel
    private let host: NSHostingView<AnyView>

    init() {
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 10, height: 10), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        host = NSHostingView(rootView: AnyView(EmptyView()))
        panel.contentView = host
    }

    var isVisible: Bool { panel.isVisible }

    func show<Content: View>(_ content: Content, above level: NSWindow.Level, place: (CGSize) -> NSPoint) {
        host.rootView = AnyView(content)
        let size = host.fittingSize
        panel.level = NSWindow.Level(rawValue: level.rawValue + 1)
        panel.setFrame(NSRect(origin: place(size), size: size), display: true)
        panel.invalidateShadow()
        panel.orderFrontRegardless()
    }

    func hide() { if panel.isVisible { panel.orderOut(nil) } }
}

// A menu item that runs a closure.
final class MenuItem: NSMenuItem {
    private let run: () -> Void

    init(_ title: String, _ run: @escaping () -> Void) {
        self.run = run
        super.init(title: title, action: #selector(fire), keyEquivalent: "")
        target = self
    }

    required init(coder: NSCoder) { fatalError("not used") }

    @objc private func fire() { run() }
}

// The menu-bar mark: the same ring gauge as the Windows tray icon, as a template image.
enum StatusIcon {
    static func make() -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { rect in
            let track = NSBezierPath(ovalIn: rect.insetBy(dx: 3, dy: 3))
            track.lineWidth = 2.2
            NSColor.black.withAlphaComponent(0.35).setStroke()
            track.stroke()
            let arc = NSBezierPath()
            arc.appendArc(withCenter: NSPoint(x: 9, y: 9), radius: 6, startAngle: -90, endAngle: 162, clockwise: false)
            arc.lineWidth = 2.2
            arc.lineCapStyle = .round
            NSColor.black.setStroke()
            arc.stroke()
            return true
        }
        image.isTemplate = true
        return image
    }
}
