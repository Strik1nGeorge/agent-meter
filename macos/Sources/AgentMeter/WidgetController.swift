import AppKit
import Combine
import QuartzCore
import SwiftUI
import AgentMeterCore

// Runs the widget: its glass window, hover cards and tips, dragging with edge snapping, turning into a column
// against the left or right edge of the screen, the ⋯ menu and the menu-bar icon (the Windows tray menu).
@MainActor
final class WidgetController: NSObject {
    let model: WidgetModel
    let panel: WidgetPanel
    let interaction = InteractionView()
    let card = FloatingPanel()
    let tip = FloatingPanel()
    private var statusItem: NSStatusItem?
    private var cardFor: String?
    private var hoveredTile: String?
    private var hoveredTip: String?
    private var hoverTimer: Timer?
    private var tipTimer: Timer?
    private var drag: (mouse: NSPoint, origin: NSPoint, hit: Hit?, moved: Bool)?
    private var refresh: AnyCancellable?
    private var observers: [NSObjectProtocol] = []

    init(model: WidgetModel) {
        self.model = model
        panel = WidgetPanel(contentRect: NSRect(origin: .zero, size: WidgetView.strip), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        super.init()
        panel.isFloatingPanel = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        panel.isReleasedWhenClosed = false
        panel.title = "Agent Meter Widget"

        // The window server's own blur of whatever is behind the widget; the glass layers are drawn on top.
        let effect = NSVisualEffectView()
        effect.material = .popover
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.maskImage = WidgetPanel.mask(radius: GlassLayers.radius)
        let host = NSHostingView(rootView: WidgetView(model: model))
        host.sizingOptions = []
        for view in [host, interaction] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            effect.addSubview(view)
            NSLayoutConstraint.activate([
                view.leadingAnchor.constraint(equalTo: effect.leadingAnchor), view.trailingAnchor.constraint(equalTo: effect.trailingAnchor),
                view.topAnchor.constraint(equalTo: effect.topAnchor), view.bottomAnchor.constraint(equalTo: effect.bottomAnchor),
            ])
        }
        panel.contentView = effect
        interaction.controller = self
        model.perform = { [weak self] hit in self?.perform(hit) }
    }

    func start() {
        Lang.apply(model.state.language)
        panel.setContentSize(model.vertical ? WidgetView.column : WidgetView.strip)
        restorePosition()
        applyPin()
        panel.orderFrontRegardless()
        model.start()
        buildStatusItem()
        // The open card follows the 5-second refresh.
        refresh = model.objectWillChange.sink { [weak self] _ in
            Task { @MainActor in self?.refreshCard() }
        }
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.ensureVisible(snap: false) }
        })
    }

    func stop() { capture(); model.stop() }

    // MARK: Pointer

    private func isButton(_ hit: Hit?) -> Bool { hit == .language || hit == .pin || hit == .more }
    private func tileID(_ hit: Hit) -> String? {
        switch hit {
        case .codexTile, .codexRing: return "codex"
        case .claudeTile, .claudeRing: return "claude"
        default: return nil
        }
    }

    func hit(at point: CGPoint) -> Hit? {
        for candidate in [Hit.language, .pin, .more] where model.frames[candidate]?.contains(point) == true { return candidate }
        for (ring, tile) in [(Hit.codexRing, Hit.codexTile), (Hit.claudeRing, Hit.claudeTile)] {
            if let frame = model.frames[ring], hypot(point.x - frame.midX, point.y - frame.midY) <= RingView.diameter / 2 { return ring }
            if model.frames[tile]?.contains(point) == true { return tile }
        }
        return nil
    }

    func pointerMoved(_ point: CGPoint) {
        if drag != nil { return }
        let hit = self.hit(at: point)
        let button: Hit? = isButton(hit) ? hit : nil
        if model.hover != button { model.hover = button }
        // Hovering a pet or ring opens that platform's card after a moment, as on Windows.
        let tile = hit.flatMap(tileID)
        if tile != hoveredTile {
            hoveredTile = tile
            hoverTimer?.invalidate()
            if let tile {
                if card.isVisible { showCard(tile) }
                else {
                    hoverTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: false) { [weak self] _ in
                        Task { @MainActor in self?.showCard(tile) }
                    }
                }
            } else { hideCard() }
        }
        // Tips: each button's, or the strip's own over empty glass.
        let tipKey: String? = tile != nil ? nil : button.map { "\($0)" } ?? "glass"
        if tipKey != hoveredTip {
            hoveredTip = tipKey
            tipTimer?.invalidate()
            tip.hide()
            if let tipKey {
                tipTimer = Timer.scheduledTimer(withTimeInterval: tipKey == "glass" ? 1.0 : 0.6, repeats: false) { [weak self] _ in
                    Task { @MainActor in self?.showTip(button) }
                }
            }
        }
    }

    func pointerLeft() {
        model.hover = nil
        hoveredTile = nil; hoveredTip = nil
        hoverTimer?.invalidate(); tipTimer?.invalidate()
        hideCard(); tip.hide()
    }

    // A press on a button acts on release; anywhere else it drags the widget, and a press on a ring that
    // doesn't move switches what the middles show.
    func mouseDown(_ point: CGPoint) {
        hoverTimer?.invalidate(); tipTimer?.invalidate()
        hideCard(); tip.hide()
        let hit = self.hit(at: point)
        drag = (NSEvent.mouseLocation, panel.frame.origin, hit, false)
        if isButton(hit) { model.pressed = hit }
    }

    func mouseDragged() {
        guard var current = drag, !isButton(current.hit) else { return }
        let mouse = NSEvent.mouseLocation
        let dx = mouse.x - current.mouse.x, dy = mouse.y - current.mouse.y
        if !current.moved && hypot(dx, dy) < 3 { return }
        current.moved = true
        drag = current
        panel.setFrameOrigin(NSPoint(x: current.origin.x + dx, y: current.origin.y + dy))
    }

    func mouseUp(_ point: CGPoint) {
        guard let current = drag else { return }
        drag = nil
        model.pressed = nil
        if let hit = current.hit, isButton(hit) {
            if self.hit(at: point) == hit { perform(hit) }
            return
        }
        if current.moved { finishDrag(); return }
        if current.hit == .codexRing || current.hit == .claudeRing { model.toggleCenter() }
    }

    func perform(_ hit: Hit) {
        switch hit {
        case .language: setLanguage(Lang.english ? "zh" : "en")
        case .pin: setPinned(!model.state.pinned)
        case .more: openMenu()
        case .codexRing, .claudeRing: model.toggleCenter()
        case .codexTile, .claudeTile: break
        }
    }

    // MARK: Cards and tips

    private func showCard(_ id: String) {
        guard model.visible, let tile = model.frames[id == "codex" ? .codexTile : .claudeTile] else { return }
        cardFor = id
        tip.hide()
        card.show(CardHost(card: model.card(id)), above: panel.level) { [unowned self] size in self.cardOrigin(size, tile: tile) }
    }

    private func refreshCard() {
        guard card.isVisible, let id = cardFor else { return }
        showCard(id)
    }

    private func hideCard() { cardFor = nil; card.hide() }

    private func showTip(_ button: Hit?) {
        guard model.visible, drag == nil else { return }
        let text = button.flatMap { model.tooltip(for: $0) } ?? model.tooltip
        let anchor = button.flatMap { model.frames[$0] } ?? CGRect(origin: .zero, size: panel.frame.size)
        tip.show(TipHost(text: text), above: panel.level) { [unowned self] size in self.popupOrigin(size, beside: anchor, gap: 6) }
    }

    // Cards open under the strip (above it when there's no room), and beside the column toward the screen.
    private func cardOrigin(_ size: CGSize, tile: CGRect) -> NSPoint {
        let frame = panel.frame
        let tileTop = frame.maxY - tile.minY
        var origin: NSPoint
        switch model.state.dock {
        case "left": origin = NSPoint(x: frame.maxX + 8, y: tileTop - size.height + 6)
        case "right": origin = NSPoint(x: frame.minX - 8 - size.width, y: tileTop - size.height + 6)
        default: origin = NSPoint(x: frame.minX + tile.minX - 4, y: frame.minY - 6 - size.height)
        }
        return clamp(origin, size: size, flipAbove: model.state.dock == nil)
    }

    private func popupOrigin(_ size: CGSize, beside anchor: CGRect, gap: CGFloat) -> NSPoint {
        let frame = panel.frame
        var origin: NSPoint
        switch model.state.dock {
        case "left": origin = NSPoint(x: frame.maxX + gap, y: frame.maxY - anchor.midY - size.height / 2)
        case "right": origin = NSPoint(x: frame.minX - gap - size.width, y: frame.maxY - anchor.midY - size.height / 2)
        default: origin = NSPoint(x: frame.minX + anchor.midX - size.width / 2, y: frame.minY - gap - size.height)
        }
        return clamp(origin, size: size, flipAbove: model.state.dock == nil)
    }

    private func clamp(_ point: NSPoint, size: CGSize, flipAbove: Bool) -> NSPoint {
        var origin = point
        let visible = (panel.screen ?? NSScreen.main)?.visibleFrame ?? panel.frame
        if flipAbove && origin.y < visible.minY { origin.y = panel.frame.maxY + 6 }
        origin.x = min(max(origin.x, visible.minX + 4), visible.maxX - size.width - 4)
        origin.y = min(max(origin.y, visible.minY + 4), visible.maxY - size.height - 4)
        return origin
    }

    // MARK: Actions

    func setPinned(_ pinned: Bool) { model.state.pinned = pinned; model.save(); applyPin() }
    private func applyPin() { panel.level = model.state.pinned ? .floating : .normal }

    func setLanguage(_ value: String) { model.setLanguage(value); buildStatusItem() }

    func showWidget() {
        model.visible = true
        panel.orderFrontRegardless()
        ensureVisible(snap: false)
        model.fetch()
    }

    func hideWidget() { pointerLeft(); panel.orderOut(nil); model.visible = false }

    private func openMenu() {
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.addItem(MenuItem(Lang.t("打开完整面板", "Open dashboard")) { [weak self] in self?.model.openDashboard() })
        menu.addItem(MenuItem(Lang.t("Codex 官方用量 ↗", "Codex usage ↗")) { [weak self] in self?.model.open("https://chatgpt.com/codex/settings/usage") })
        menu.addItem(MenuItem(Lang.t("Claude 官方用量 ↗", "Claude usage ↗")) { [weak self] in self?.model.open("https://claude.ai/settings/usage") })
        menu.addItem(.separator())
        let top = MenuItem(Lang.t("始终置顶", "Always on top")) { [weak self] in
            guard let self else { return }
            self.setPinned(!self.model.state.pinned)
        }
        top.state = model.state.pinned ? .on : .off
        menu.addItem(top)
        menu.addItem(MenuItem(Lang.t("收起到菜单栏", "Hide to menu bar")) { [weak self] in self?.hideWidget() })
        menu.addItem(MenuItem(Lang.t("重置小组件位置", "Reset widget position")) { [weak self] in self?.resetPosition() })
        menu.addItem(.separator())
        menu.addItem(MenuItem(Lang.t("退出小组件", "Quit widget")) { NSApp.terminate(nil) })
        let anchor = model.frames[.more] ?? CGRect(origin: .zero, size: panel.frame.size)
        _ = menu.popUp(positioning: nil, at: NSPoint(x: anchor.minX, y: anchor.maxY + 2), in: interaction)
    }

    private func buildStatusItem() {
        let item = statusItem ?? NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = StatusIcon.make()
        item.button?.toolTip = Lang.t("Agent Meter · 额度小组件", "Agent Meter · quota widget")
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.addItem(MenuItem(Lang.t("显示小组件", "Show widget")) { [weak self] in self?.showWidget() })
        menu.addItem(MenuItem(Lang.t("重置小组件位置", "Reset widget position")) { [weak self] in self?.showWidget(); self?.resetPosition() })
        menu.addItem(MenuItem(Lang.t("打开完整面板", "Open dashboard")) { [weak self] in self?.model.openDashboard() })
        menu.addItem(MenuItem(Lang.t("Codex 官方用量", "Codex usage")) { [weak self] in self?.model.open("https://chatgpt.com/codex/settings/usage") })
        menu.addItem(MenuItem(Lang.t("Claude 官方用量", "Claude usage")) { [weak self] in self?.model.open("https://claude.ai/settings/usage") })
        menu.addItem(MenuItem(Lang.t("收起小组件", "Hide widget")) { [weak self] in self?.hideWidget() })
        // Written in the language it switches to, so it can be found by someone who can't read the current one.
        menu.addItem(MenuItem(Lang.english ? "切换到中文" : "Switch to English") { [weak self] in self?.setLanguage(Lang.english ? "zh" : "en") })
        menu.addItem(.separator())
        menu.addItem(MenuItem(Lang.t("退出小组件", "Quit widget")) { NSApp.terminate(nil) })
        item.menu = menu
        statusItem = item
    }

    // MARK: Placement (Placement's rules work top-left-origin; AppKit screens are bottom-left-origin)

    private func flip(_ rect: CGRect) -> CGRect {
        let top = NSScreen.screens.first?.frame.maxY ?? 0
        return CGRect(x: rect.minX, y: top - rect.maxY, width: rect.width, height: rect.height)
    }

    private func nearestScreen(_ frame: CGRect) -> NSScreen? {
        let screens = NSScreen.screens
        guard let index = Placement.nearestArea(flip(frame), screens.map { flip($0.visibleFrame) }) else { return nil }
        return screens[index]
    }

    private func restorePosition() {
        let screens = NSScreen.screens
        guard let screen = screens.first(where: { $0.localizedName == model.state.screen }) ?? NSScreen.main ?? screens.first else { return }
        let x = model.state.offsetX.map { CGFloat($0) } ?? 0.98, y = model.state.offsetY.map { CGFloat($0) } ?? 0.06
        let target = Placement.atOffset(flip(screen.visibleFrame), size: panel.frame.size, x: max(0, min(1, x)), y: max(0, min(1, y)))
        panel.setFrame(flip(target), display: false)
        checkDock(animated: false)
    }

    private func capture() {
        guard let screen = nearestScreen(panel.frame) else { return }
        let offsets = Placement.offsets(of: flip(panel.frame), in: flip(screen.visibleFrame))
        model.state.screen = screen.localizedName
        model.state.offsetX = Double(offsets.x)
        model.state.offsetY = Double(offsets.y)
        model.save()
    }

    private func ensureVisible(snap: Bool) {
        guard drag == nil, let screen = nearestScreen(panel.frame) else { return }
        let target = flip(Placement.fit(flip(panel.frame), in: flip(screen.visibleFrame), snap: snap ? 10 : 0))
        if abs(target.minX - panel.frame.minX) >= 0.5 || abs(target.minY - panel.frame.minY) >= 0.5 { panel.setFrameOrigin(target.origin) }
    }

    private func finishDrag() {
        ensureVisible(snap: true)
        checkDock(animated: true)
        capture()
    }

    // Against the left or right edge of the screen the strip becomes a column; anywhere else, a strip.
    private func checkDock(animated: Bool) {
        guard let screen = nearestScreen(panel.frame) else { return }
        let work = flip(screen.visibleFrame)
        let edge = Placement.sideEdge(flip(panel.frame), in: work, tolerance: 2)
        let column = edge != nil
        let size = column ? WidgetView.column : WidgetView.strip
        if column == model.vertical && panel.frame.size == size {
            if edge != model.state.dock { model.state.dock = edge; model.save() }
            return
        }
        let target = flip(Placement.anchored(flip(panel.frame), size: size, in: work, edge: edge))
        model.state.dock = edge
        model.save()
        if animated && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.22
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                panel.animator().setFrame(target, display: true)
            }
        } else {
            panel.setFrame(target, display: true)
        }
    }

    private func resetPosition() {
        guard let screen = NSScreen.screens.first else { return }
        model.state.dock = nil
        let target = Placement.atOffset(flip(screen.visibleFrame), size: WidgetView.strip, x: 0.98, y: 0.06)
        panel.setFrame(flip(target), display: true)
        capture()
    }
}

// The card and tips follow the appearance of the panel they're shown in.
struct CardHost: View {
    let card: CardModel
    @Environment(\.colorScheme) private var scheme
    var body: some View { CardView(card: card, palette: Palette.current(scheme)) }
}

struct TipHost: View {
    let text: String
    @Environment(\.colorScheme) private var scheme
    var body: some View { TipView(text: text, palette: Palette.current(scheme)) }
}
