import CoreGraphics
import Foundation

// Where the widget sits, by the rules of desktop/WindowPlacement.cs. These work in a top-left-origin space
// (y grows downward, like Windows); the app converts AppKit's bottom-left screen coordinates before and after.
public enum Placement {
    // The screen area the window overlaps most, or is nearest to.
    public static func nearestArea(_ window: CGRect, _ areas: [CGRect]) -> Int? {
        var selected: Int? = nil
        var bestOverlap: CGFloat = -1, bestDistance = CGFloat.greatestFiniteMagnitude
        for (i, area) in areas.enumerated() {
            let overlap = window.intersection(area)
            let size = overlap.isNull ? 0 : overlap.width * overlap.height
            let cx = window.midX, cy = window.midY
            let dx = max(area.minX - cx, max(0, cx - area.maxX)), dy = max(area.minY - cy, max(0, cy - area.maxY))
            let distance = dx * dx + dy * dy
            if size > bestOverlap || (size == bestOverlap && distance < bestDistance) { selected = i; bestOverlap = size; bestDistance = distance }
        }
        return selected
    }

    // Inside the work area; within `snap` of an edge it sits flush against it.
    public static func fit(_ window: CGRect, in work: CGRect, snap: CGFloat) -> CGRect {
        let right = max(work.minX, work.maxX - window.width), bottom = max(work.minY, work.maxY - window.height)
        var x = max(work.minX, min(right, window.minX)), y = max(work.minY, min(bottom, window.minY))
        if x - work.minX <= snap { x = work.minX } else if right - x <= snap { x = right }
        if y - work.minY <= snap { y = work.minY } else if bottom - y <= snap { y = bottom }
        return CGRect(x: x, y: y, width: window.width, height: window.height)
    }

    // "left" / "right" when the window sits against that side of its work area.
    public static func sideEdge(_ window: CGRect, in work: CGRect, tolerance: CGFloat) -> String? {
        if abs(window.minX - work.minX) <= tolerance { return "left" }
        if abs(window.maxX - work.maxX) <= tolerance { return "right" }
        return nil
    }

    // The new layout's frame: flush with the docked edge, otherwise kept on the same side of the screen; centred
    // on the old frame vertically.
    public static func anchored(_ before: CGRect, size: CGSize, in work: CGRect, edge: String?) -> CGRect {
        let x: CGFloat
        if edge == "left" { x = work.minX }
        else if edge == "right" { x = work.maxX - size.width }
        else { x = before.midX < work.midX ? before.minX : before.maxX - size.width }
        return fit(CGRect(x: x, y: before.midY - size.height / 2, width: size.width, height: size.height), in: work, snap: 0)
    }

    // A frame at fractions of the free space in the work area (0 = left/top edge, 1 = right/bottom edge).
    public static func atOffset(_ work: CGRect, size: CGSize, x: CGFloat, y: CGFloat) -> CGRect {
        CGRect(x: work.minX + max(0, work.width - size.width) * x, y: work.minY + max(0, work.height - size.height) * y, width: size.width, height: size.height)
    }

    public static func offsets(of window: CGRect, in work: CGRect) -> (x: CGFloat, y: CGFloat) {
        (max(0, min(1, (window.minX - work.minX) / max(1, work.width - window.width))),
         max(0, min(1, (window.minY - work.minY) / max(1, work.height - window.height))))
    }
}

// What the widget remembers between launches, in .data/widget-state.json.
public struct WidgetState: Codable, Equatable {
    public var screen: String?
    public var offsetX: Double?
    public var offsetY: Double?
    public var pinned = true
    // "auto" (follow the Mac's language), "zh" or "en".
    public var language = "auto"
    // "left" / "right" when docked to that side of the screen (column layout).
    public var dock: String?
    // What the middle of the rings shows: "outer" (5 hours) or "inner" (7 days).
    public var center = "outer"

    public init() {}

    enum CodingKeys: String, CodingKey { case screen, offsetX, offsetY, pinned, language, dock, center }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        screen = try? c.decodeIfPresent(String.self, forKey: .screen)
        offsetX = try? c.decodeIfPresent(Double.self, forKey: .offsetX)
        offsetY = try? c.decodeIfPresent(Double.self, forKey: .offsetY)
        pinned = (try? c.decodeIfPresent(Bool.self, forKey: .pinned)) ?? true
        language = (try? c.decodeIfPresent(String.self, forKey: .language)) ?? "auto"
        dock = try? c.decodeIfPresent(String.self, forKey: .dock)
        center = (try? c.decodeIfPresent(String.self, forKey: .center)) ?? "outer"
    }
}
