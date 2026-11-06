import AppKit

/// One line in a Veil menu.
struct MenuEntry {
    enum Kind { case action, info, separator }
    var kind: Kind
    var title: String = ""
    var hint: String = ""
    var enabled: Bool = true
    var run: (() -> Void)?

    static func item(_ title: String, hint: String = "", enabled: Bool = true, _ run: @escaping () -> Void) -> MenuEntry {
        MenuEntry(kind: .action, title: title, hint: hint, enabled: enabled, run: run)
    }
    static func info(_ title: String) -> MenuEntry { MenuEntry(kind: .info, title: title, enabled: false, run: nil) }
    static var separator: MenuEntry { MenuEntry(kind: .separator, run: nil) }
}

private final class MenuPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private final class MenuRowView: NSView {
    let entry: MenuEntry
    var highlighted = false { didSet { if oldValue != highlighted { needsDisplay = true } } }
    var onHover: ((MenuRowView) -> Void)?
    var onLeave: ((MenuRowView) -> Void)?

    static let titleFont = NSFont.systemFont(ofSize: 13)
    static let hintFont = NSFont.systemFont(ofSize: 12)

    init(entry: MenuEntry, frame: NSRect) {
        self.entry = entry
        super.init(frame: frame)
    }
    required init?(coder: NSCoder) { fatalError() }

    var selectable: Bool { entry.kind == .action && entry.enabled }

    override func updateTrackingAreas() {
        for a in trackingAreas { removeTrackingArea(a) }
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self, userInfo: nil))
        super.updateTrackingAreas()
    }
    override func mouseEntered(with event: NSEvent) { onHover?(self) }
    override func mouseExited(with event: NSEvent) { onLeave?(self) }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        if entry.kind == .separator {
            Theme.tabBorder.setFill()
            NSRect(x: 12, y: bounds.midY, width: bounds.width - 24, height: 1).fill()
            return
        }
        if highlighted && selectable {
            Theme.accent.withAlphaComponent(0.22).setFill()
            NSBezierPath(roundedRect: bounds.insetBy(dx: 5, dy: 1), xRadius: 6, yRadius: 6).fill()
        }
        let color: NSColor = selectable ? .labelColor : .secondaryLabelColor
        let title = entry.title as NSString
        let tAttrs: [NSAttributedString.Key: Any] = [.font: MenuRowView.titleFont, .foregroundColor: color]
        let tSize = title.size(withAttributes: tAttrs)
        title.draw(at: NSPoint(x: 15, y: (bounds.height - tSize.height) / 2), withAttributes: tAttrs)
        if !entry.hint.isEmpty {
            let hint = entry.hint as NSString
            let hAttrs: [NSAttributedString.Key: Any] = [.font: MenuRowView.hintFont, .foregroundColor: NSColor.secondaryLabelColor]
            let hSize = hint.size(withAttributes: hAttrs)
            hint.draw(at: NSPoint(x: bounds.width - 15 - hSize.width, y: (bounds.height - hSize.height) / 2), withAttributes: hAttrs)
        }
    }
}

private final class MenuContentView: NSView {
    private var rows: [MenuRowView] = []
    private var selected: Int?
    override var isFlipped: Bool { true }

    init(entries: [MenuEntry]) {
        var width: CGFloat = 190
        for e in entries where e.kind != .separator {
            let t = (e.title as NSString).size(withAttributes: [.font: MenuRowView.titleFont]).width
            let h = e.hint.isEmpty ? 0 : (e.hint as NSString).size(withAttributes: [.font: MenuRowView.hintFont]).width + 28
            width = max(width, ceil(t + h + 34))
        }
        width = min(width, 360)
        var y: CGFloat = 6
        var built: [MenuRowView] = []
        for e in entries {
            let h: CGFloat = e.kind == .separator ? 9 : 28
            built.append(MenuRowView(entry: e, frame: NSRect(x: 0, y: y, width: width, height: h)))
            y += h
        }
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: y + 6))
        rows = built
        for r in rows {
            r.onHover = { [weak self] row in self?.select(row) }
            r.onLeave = { [weak self] row in self?.deselect(row) }
            addSubview(r)
        }
    }
    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 11, yRadius: 11)
        Theme.field.setFill()
        path.fill()
        Theme.tabBorder.setStroke()
        path.lineWidth = 1
        path.stroke()
    }

    private func select(_ row: MenuRowView) {
        selected = row.selectable ? rows.firstIndex(where: { $0 === row }) : nil
        for r in rows { r.highlighted = (r === row) && r.selectable }
    }
    private func deselect(_ row: MenuRowView) {
        row.highlighted = false
        if let s = selected, rows[s] === row { selected = nil }
    }

    func move(_ delta: Int) {
        let ok = rows.indices.filter { rows[$0].selectable }
        guard !ok.isEmpty else { return }
        let next: Int
        if let s = selected, let c = ok.firstIndex(of: s) { next = (c + delta + ok.count) % ok.count }
        else { next = delta > 0 ? 0 : ok.count - 1 }
        selected = ok[next]
        for (i, r) in rows.enumerated() { r.highlighted = (i == selected) }
    }

    var selectedRun: (() -> Void)? {
        guard let s = selected else { return nil }
        return rows[s].entry.run
    }

    func runnable(at windowPoint: NSPoint) -> (() -> Void)? {
        let p = convert(windowPoint, from: nil)
        guard let row = rows.first(where: { $0.frame.contains(p) }), row.selectable else { return nil }
        return row.entry.run
    }
}

/// Veil's own dropdown menu: a plain solid panel, drawn by Veil, not by macOS.
final class CustomMenu {
    private static var current: CustomMenu?
    private let panel: MenuPanel
    private let content: MenuContentView
    private var local: Any?
    private var global: Any?
    private var observer: NSObjectProtocol?

    private init(entries: [MenuEntry]) {
        content = MenuContentView(entries: entries)
        panel = MenuPanel(contentRect: NSRect(origin: .zero, size: content.frame.size),
                          styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .popUpMenu
        panel.hidesOnDeactivate = false
        panel.contentView = content
    }

    /// Opens the menu just below a button.
    static func show(_ entries: [MenuEntry], below anchor: NSView, rightAlign: Bool = false) {
        guard let win = anchor.window else { return }
        let r = win.convertToScreen(anchor.convert(anchor.bounds, to: nil))
        present(entries, topLeft: NSPoint(x: rightAlign ? r.maxX : r.minX, y: r.minY - 4), rightAligned: rightAlign)
    }

    /// Opens the menu at the mouse pointer (right-click menus).
    static func showAtMouse(_ entries: [MenuEntry]) {
        present(entries, topLeft: NSEvent.mouseLocation, rightAligned: false)
    }

    private static func present(_ entries: [MenuEntry], topLeft: NSPoint, rightAligned: Bool) {
        current?.dismiss()
        let m = CustomMenu(entries: entries)
        let size = m.content.frame.size
        let screen = NSScreen.screens.first(where: { $0.frame.contains(topLeft) }) ?? NSScreen.main
        let vf = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        var x = rightAligned ? topLeft.x - size.width : topLeft.x
        x = max(vf.minX + 6, min(x, vf.maxX - size.width - 6))
        var y = topLeft.y - size.height
        if y < vf.minY + 6 { y = vf.minY + 6 }
        m.panel.setFrame(NSRect(x: x, y: y, width: size.width, height: size.height), display: false)
        m.panel.orderFrontRegardless()
        m.install()
        current = m
    }

    private func install() {
        local = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseUp, .rightMouseDown, .otherMouseDown, .keyDown]) { [weak self] e in
            guard let self = self else { return e }
            return self.handle(e)
        }
        global = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] _ in
            self?.dismiss()
        }
        observer = NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            self?.dismiss()
        }
    }

    private func handle(_ e: NSEvent) -> NSEvent? {
        switch e.type {
        case .keyDown:
            switch e.keyCode {
            case 53: dismiss()                       // Escape
            case 125: content.move(1)                // Down
            case 126: content.move(-1)               // Up
            case 36, 76: if let run = content.selectedRun { finish(run) }   // Return
            default: break
            }
            return nil
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            if e.window === panel { return nil }
            dismiss()
            return nil
        case .leftMouseUp:
            if e.window === panel {
                if let run = content.runnable(at: e.locationInWindow) { finish(run) }
                return nil
            }
            return e
        default:
            return e
        }
    }

    private func finish(_ run: @escaping () -> Void) {
        dismiss()
        DispatchQueue.main.async { run() }
    }

    func dismiss() {
        if let l = local { NSEvent.removeMonitor(l); local = nil }
        if let g = global { NSEvent.removeMonitor(g); global = nil }
        if let o = observer { NotificationCenter.default.removeObserver(o); observer = nil }
        panel.orderOut(nil)
        if CustomMenu.current === self { CustomMenu.current = nil }
    }
}
