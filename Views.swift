import AppKit
import VeilCore

enum Theme {
    static func dynamic(dark: NSColor, light: NSColor) -> NSColor {
        NSColor(name: nil) { a in a.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light }
    }
    static func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> NSColor {
        NSColor(srgbRed: r / 255, green: g / 255, blue: b / 255, alpha: a)
    }
    /// Browser theme (colours the tab bar, toolbar, address box and page surround), like Chrome themes.
    static var current = "default"
    private static let hues: [String: (CGFloat, CGFloat)] = [
        "midnight": (222, 0.60), "forest": (140, 0.45), "rose": (340, 0.50), "sunset": (18, 0.62), "grape": (272, 0.50),
        "ocean": (190, 0.58), "mocha": (28, 0.35), "mint": (160, 0.48), "graphite": (220, 0.0),
    ]
    private static func hsb(_ h: CGFloat, _ s: CGFloat, _ b: CGFloat) -> NSColor {
        NSColor(hue: h / 360, saturation: s, brightness: b, alpha: 1)
    }
    /// role: 0 chrome, 1 address box, 2 selected tab, 3 page surround
    private static func resolve(_ a: NSAppearance, _ role: Int) -> NSColor {
        let dark = a.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        if let (h, s) = hues[current] {
            switch (dark, role) {
            case (true, 0): return hsb(h, s, 0.16)
            case (true, 1): return hsb(h, s * 0.9, 0.23)
            case (true, 2): return hsb(h, s * 0.8, 0.31)
            case (true, _): return hsb(h, s, 0.14)
            case (false, 0): return hsb(h, s * 0.28, 0.93)
            case (false, 1): return hsb(h, s * 0.10, 0.99)
            case (false, 2): return .white
            case (false, _): return hsb(h, s * 0.20, 0.96)
            }
        }
        switch (dark, role) {
        case (true, 0): return rgb(19, 20, 23)
        case (true, 1): return rgb(32, 34, 39)
        case (true, 2): return rgb(44, 47, 55)
        case (true, _): return rgb(19, 20, 23)
        case (false, 0): return rgb(232, 232, 228)
        case (false, 1): return rgb(250, 250, 248)
        case (false, 2): return rgb(255, 255, 255)
        case (false, _): return rgb(244, 244, 241)
        }
    }
    static let chrome = NSColor(name: nil) { Theme.resolve($0, 0) }
    static let field = NSColor(name: nil) { Theme.resolve($0, 1) }
    static let privateField = dynamic(dark: rgb(40, 30, 58), light: rgb(240, 232, 252))
    static let tabIdle = dynamic(dark: NSColor.white.withAlphaComponent(0.035), light: NSColor.black.withAlphaComponent(0.03))
    static let tabBorder = dynamic(dark: NSColor.white.withAlphaComponent(0.17), light: NSColor.black.withAlphaComponent(0.17))
    static let tabSelected = NSColor(name: nil) { Theme.resolve($0, 2) }
    static let tabHover = dynamic(dark: NSColor.white.withAlphaComponent(0.08), light: NSColor.black.withAlphaComponent(0.06))
    static let inactiveDot = dynamic(dark: NSColor.white.withAlphaComponent(0.18), light: NSColor.black.withAlphaComponent(0.16))
    static let pageBackdrop = NSColor(name: nil) { Theme.resolve($0, 3) }
    static let privateTint = rgb(176, 132, 255)

    static var accent: NSColor { accentColor(named: Services.shared.settings.accent) }

    static func accentColor(named name: String) -> NSColor {
        switch name {
        case "coral": return dynamic(dark: rgb(240, 144, 125), light: rgb(196, 80, 58))
        case "mint": return dynamic(dark: rgb(111, 208, 168), light: rgb(38, 137, 106))
        case "violet": return dynamic(dark: rgb(171, 148, 245), light: rgb(111, 82, 201))
        case "amber": return dynamic(dark: rgb(232, 176, 88), light: rgb(168, 112, 15))
        case "pink": return dynamic(dark: rgb(244, 143, 190), light: rgb(190, 60, 120))
        case "sky": return dynamic(dark: rgb(100, 181, 246), light: rgb(25, 118, 210))
        case "lime": return dynamic(dark: rgb(170, 214, 92), light: rgb(98, 140, 20))
        case "crimson": return dynamic(dark: rgb(232, 100, 110), light: rgb(176, 40, 56))
        default: return dynamic(dark: rgb(143, 179, 201), light: rgb(61, 108, 138))
        }
    }
}

extension NSView {
    /// Redraws every themed view (after the browser theme changed).
    func refreshAllChrome() {
        if self is ChromeView { needsDisplay = true }
        for v in subviews { v.refreshAllChrome() }
    }
}

/// A layer-backed view whose fill and border follow light/dark appearance.
class ChromeView: NSView {
    var fill: NSColor = .clear { didSet { needsDisplay = true } }
    var radius: CGFloat = 0 { didSet { needsDisplay = true } }
    var borderColor: NSColor? { didSet { needsDisplay = true } }
    var borderWidth: CGFloat = 0 { didSet { needsDisplay = true } }
    override init(frame: NSRect) { super.init(frame: frame); wantsLayer = true }
    required init?(coder: NSCoder) { fatalError() }
    override var wantsUpdateLayer: Bool { true }
    override func updateLayer() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = fill.cgColor
            layer?.borderColor = borderColor?.cgColor
        }
        layer?.borderWidth = borderWidth
        layer?.cornerRadius = radius
        layer?.cornerCurve = .continuous
    }
}

/// Draggable like a title bar.
final class DragView: ChromeView {
    override var mouseDownCanMoveWindow: Bool { true }
    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 { window?.zoom(nil) } else { window?.performDrag(with: event) }
    }
}

/// The rounded box around the address field: clicking anywhere in it focuses the field and selects its text.
final class ClickableBox: ChromeView {
    weak var field: NSTextField?
    override var mouseDownCanMoveWindow: Bool { false }
    override func mouseDown(with event: NSEvent) {
        guard let field = field else { return }
        window?.makeFirstResponder(field)
        field.currentEditor()?.selectAll(nil)
    }
}

final class AddressField: NSTextField {
    var onFocus: (() -> Void)?

    /// First click selects everything, so typing or Backspace replaces the whole address.
    override func mouseDown(with event: NSEvent) {
        if currentEditor() == nil {
            window?.makeFirstResponder(self)
            currentEditor()?.selectAll(nil)
        } else {
            super.mouseDown(with: event)
        }
    }

    override func becomeFirstResponder() -> Bool {
        let ok = super.becomeFirstResponder()
        if ok {
            onFocus?()
            DispatchQueue.main.async { [weak self] in self?.currentEditor()?.selectAll(nil) }
        }
        return ok
    }
}

func symbolButton(_ name: String, tip: String, target: AnyObject?, action: Selector) -> NSButton {
    let b = NSButton(frame: .zero)
    b.image = NSImage(systemSymbolName: name, accessibilityDescription: tip)
    b.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 13, weight: .regular)
    b.isBordered = false
    b.bezelStyle = .regularSquare
    b.contentTintColor = .secondaryLabelColor
    b.toolTip = tip
    b.target = target
    b.action = action
    b.translatesAutoresizingMaskIntoConstraints = false
    b.widthAnchor.constraint(equalToConstant: 28).isActive = true
    b.heightAnchor.constraint(equalToConstant: 28).isActive = true
    return b
}

// MARK: - Window buttons (drawn by Veil so they are always visible)

final class TrafficDot: ChromeView {
    var onClick: (() -> Void)?
    private let color: NSColor
    private let glyph = NSImageView()
    var isActive = true {
        didSet { fill = isActive ? color : Theme.inactiveDot; updateGlyph() }
    }
    var showGlyph = false { didSet { updateGlyph() } }

    init(color: NSColor, symbol: String) {
        self.color = color
        super.init(frame: NSRect(x: 0, y: 0, width: 12, height: 12))
        fill = color
        radius = 6
        glyph.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        glyph.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 7, weight: .heavy)
        glyph.contentTintColor = NSColor.black.withAlphaComponent(0.55)
        glyph.frame = bounds
        glyph.alphaValue = 0
        addSubview(glyph)
    }
    required init?(coder: NSCoder) { fatalError() }

    private func updateGlyph() {
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.1
            glyph.animator().alphaValue = (showGlyph && isActive) ? 1 : 0
        }
    }
    override var mouseDownCanMoveWindow: Bool { false }
    override func hitTest(_ point: NSPoint) -> NSView? { frame.contains(point) ? self : nil }
    override func mouseDown(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) {
        if bounds.contains(convert(event.locationInWindow, from: nil)) { onClick?() }
    }
}

final class TrafficLights: NSView {
    var onClose: (() -> Void)?
    var onMinimize: (() -> Void)?
    var onZoom: (() -> Void)?
    private let dots = [
        TrafficDot(color: Theme.rgb(255, 95, 87), symbol: "xmark"),
        TrafficDot(color: Theme.rgb(254, 188, 46), symbol: "minus"),
        TrafficDot(color: Theme.rgb(40, 200, 64), symbol: "plus"),
    ]
    private var tracking: NSTrackingArea?
    var isActive = true { didSet { dots.forEach { $0.isActive = isActive } } }

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: 52, height: 20))
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: 52).isActive = true
        heightAnchor.constraint(equalToConstant: 20).isActive = true
        dots[0].onClick = { [weak self] in self?.onClose?() }
        dots[1].onClick = { [weak self] in self?.onMinimize?() }
        dots[2].onClick = { [weak self] in self?.onZoom?() }
        for (i, d) in dots.enumerated() {
            d.frame = NSRect(x: CGFloat(i) * 20, y: 4, width: 12, height: 12)
            addSubview(d)
        }
    }
    required init?(coder: NSCoder) { fatalError() }

    override var mouseDownCanMoveWindow: Bool { false }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = tracking { removeTrackingArea(t) }
        let t = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self, userInfo: nil)
        addTrackingArea(t); tracking = t
    }
    override func mouseEntered(with event: NSEvent) { dots.forEach { $0.showGlyph = true } }
    override func mouseExited(with event: NSEvent) { dots.forEach { $0.showGlyph = false } }
}

// MARK: - Tabs

final class TabItemView: NSView {
    let tab: Tab
    var onSelect: ((Tab) -> Void)?
    var onClose: ((Tab) -> Void)?
    var onMute: ((Tab) -> Void)?
    var onMenu: ((Tab) -> Void)?
    private let base = ChromeView()
    private let overlay = ChromeView()
    private let icon = NSImageView()
    private let label = NSTextField(labelWithString: "")
    private let audioButton = NSButton()
    private let closeButton = NSButton()
    private var audioWidth: NSLayoutConstraint!
    private var isSelected = false
    private var tracking: NSTrackingArea?

    init(tab: Tab) {
        self.tab = tab
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        for v in [base, overlay] {
            v.translatesAutoresizingMaskIntoConstraints = false
            v.radius = 9
            v.borderWidth = 1
            addSubview(v)
        }
        base.fill = Theme.tabIdle
        base.borderColor = Theme.tabBorder
        overlay.fill = Theme.tabSelected
        overlay.borderColor = Theme.accent
        overlay.borderWidth = 1.5
        overlay.alphaValue = 0

        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.imageScaling = .scaleProportionallyDown
        icon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 11, weight: .regular)
        icon.wantsLayer = true
        icon.layer?.cornerRadius = 3
        icon.layer?.masksToBounds = true
        addSubview(icon)

        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 12)
        label.lineBreakMode = .byTruncatingTail
        label.textColor = .secondaryLabelColor
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        addSubview(label)

        audioButton.translatesAutoresizingMaskIntoConstraints = false
        audioButton.isBordered = false
        audioButton.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 10, weight: .semibold)
        audioButton.target = self
        audioButton.action = #selector(muteTapped)
        audioButton.toolTip = "Mute or unmute this tab"
        audioButton.isHidden = true
        addSubview(audioButton)

        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: "Close tab")
        closeButton.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 9, weight: .semibold)
        closeButton.isBordered = false
        closeButton.contentTintColor = .tertiaryLabelColor
        closeButton.target = self
        closeButton.action = #selector(closeTapped)
        closeButton.alphaValue = 0
        addSubview(closeButton)

        audioWidth = audioButton.widthAnchor.constraint(equalToConstant: 0)
        // Soft (below the window's 500 hold): with very many tabs these simply give way, so tabs can shrink
        // below their comfortable width instead of forcing the window wider than the screen.
        for c in [label.trailingAnchor.constraint(equalTo: audioButton.leadingAnchor, constant: -2),
                  audioButton.trailingAnchor.constraint(equalTo: closeButton.leadingAnchor, constant: -2),
                  closeButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -9),
                  icon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12)] {
            c.priority = NSLayoutConstraint.Priority(450)
            c.isActive = true
        }

        NSLayoutConstraint.activate([
            base.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            base.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -2),
            base.topAnchor.constraint(equalTo: topAnchor, constant: -2),
            base.bottomAnchor.constraint(equalTo: bottomAnchor, constant: 2),
            overlay.leadingAnchor.constraint(equalTo: base.leadingAnchor),
            overlay.trailingAnchor.constraint(equalTo: base.trailingAnchor),
            overlay.topAnchor.constraint(equalTo: base.topAnchor),
            overlay.bottomAnchor.constraint(equalTo: base.bottomAnchor),
            icon.centerYAnchor.constraint(equalTo: centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 15),
            icon.heightAnchor.constraint(equalToConstant: 15),
            label.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 7),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            audioButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            audioWidth,
            audioButton.heightAnchor.constraint(equalToConstant: 16),
            closeButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            closeButton.widthAnchor.constraint(equalToConstant: 16),
            closeButton.heightAnchor.constraint(equalToConstant: 16),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }

    func refresh(selected: Bool) {
        let isNewTab = tab.url?.scheme == "veil" && tab.url?.host == "newtab"
        label.stringValue = isNewTab ? (tab.isPrivate ? "Private Tab" : "New Tab") : tab.title
        label.textColor = selected ? .labelColor : .secondaryLabelColor
        label.alphaValue = tab.isLoaded ? 1 : 0.6            // dimmed = not loaded (saves memory)

        if let f = tab.favicon {
            icon.image = f
            icon.contentTintColor = nil
        } else {
            let sym = tab.isLoading ? "circle.dotted" : (tab.isPrivate ? "eyeglasses" : (isNewTab ? "square.grid.2x2" : "globe"))
            icon.image = NSImage(systemSymbolName: sym, accessibilityDescription: nil)
            icon.contentTintColor = tab.isPrivate ? Theme.privateTint : .tertiaryLabelColor
        }

        let showAudio = tab.isPlayingMedia || tab.isMuted
        audioButton.isHidden = !showAudio
        audioWidth.constant = showAudio ? 16 : 0
        audioButton.image = NSImage(systemSymbolName: tab.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill",
                                    accessibilityDescription: tab.isMuted ? "Muted" : "Playing sound")
        audioButton.contentTintColor = tab.isMuted ? .tertiaryLabelColor : Theme.accent

        base.borderColor = tab.isPrivate ? Theme.privateTint.withAlphaComponent(0.6) : Theme.tabBorder
        overlay.borderColor = tab.isPrivate ? Theme.privateTint : Theme.accent

        if selected != isSelected {
            isSelected = selected
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.18
                ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                overlay.animator().alphaValue = selected ? 1 : 0
            }
        }
        closeButton.alphaValue = selected ? 1 : 0
    }

    @objc private func closeTapped() { onClose?(tab) }
    @objc private func muteTapped() { onMute?(tab) }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let v = super.hitTest(point)
        if v === closeButton || v === audioButton { return v }
        return v == nil ? nil : self
    }
    override func mouseDown(with event: NSEvent) { onSelect?(tab) }
    override func rightMouseDown(with event: NSEvent) { onMenu?(tab) }
    override func otherMouseUp(with event: NSEvent) { if event.buttonNumber == 2 { onClose?(tab) } }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = tracking { removeTrackingArea(t) }
        let t = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInKeyWindow], owner: self, userInfo: nil)
        addTrackingArea(t); tracking = t
    }
    override func mouseEntered(with event: NSEvent) { setHover(true) }
    override func mouseExited(with event: NSEvent) { setHover(false) }
    func setHover(_ on: Bool) {
        base.fill = on ? Theme.tabHover : Theme.tabIdle
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.12
            closeButton.animator().alphaValue = (on || isSelected) ? 1 : 0
        }
    }
}

final class TabStripView: NSView {
    let vertical: Bool
    var onSelect: ((Tab) -> Void)?
    var onClose: ((Tab) -> Void)?
    var onMute: ((Tab) -> Void)?
    var onNew: (() -> Void)?
    var onMenu: ((Tab) -> Void)?
    private let stack = NSStackView()
    private var items: [UUID: TabItemView] = [:]
    private var stackPref: NSLayoutConstraint?
    private let scroll = NSScrollView()
    private var plusButton: NSButton!
    /// After closing a tab with its X, tabs keep their width until the mouse leaves the strip,
    /// so the next tab's X lands under the cursor and you can spam-click to close many tabs.
    private var lockedWidth: CGFloat?
    private var tabCount = 0
    private var stripTracking: NSTrackingArea?

    private var wantedTabWidth: CGFloat {
        switch Services.shared.settings.tabWidth { case "compact": return 150; case "wide": return 280; default: return 210 }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = stripTracking { removeTrackingArea(t) }
        let t = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(t); stripTracking = t
    }

    override func mouseExited(with event: NSEvent) {
        guard lockedWidth != nil else { return }
        lockedWidth = nil
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.18
            ctx.allowsImplicitAnimation = true
            stackPref?.animator().constant = wantedTabWidth * CGFloat(tabCount)
            layoutSubtreeIfNeeded()
        }
    }

    private func lockWidth(for tab: Tab) {
        guard !vertical, lockedWidth == nil, let w = items[tab.id]?.frame.width, w > 0 else { return }
        lockedWidth = w
    }

    private func refreshHover() {
        guard let w = window else { return }
        let q = stack.convert(convert(w.mouseLocationOutsideOfEventStream, from: nil), from: self)
        for v in items.values { v.setHover(v.frame.contains(q)) }
    }

    init(vertical: Bool) {
        self.vertical = vertical
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = vertical ? .vertical : .horizontal
        stack.spacing = vertical ? 2 : 0
        stack.alignment = vertical ? .leading : .centerY
        stack.distribution = vertical ? .fill : .fillEqually     // horizontal tabs are always equal width
        stack.translatesAutoresizingMaskIntoConstraints = false
        plusButton = symbolButton("plus", tip: "New Tab (⌘T)", target: self, action: #selector(newTapped))

        if vertical {
            let newRow = NSButton(title: "  New Tab",
                                  image: NSImage(systemSymbolName: "plus", accessibilityDescription: "New Tab")!,
                                  target: self, action: #selector(newTapped))
            newRow.translatesAutoresizingMaskIntoConstraints = false
            newRow.imagePosition = .imageLeading
            newRow.isBordered = false
            newRow.alignment = .left
            newRow.font = .systemFont(ofSize: 12)
            newRow.contentTintColor = .secondaryLabelColor
            addSubview(newRow)
            scroll.translatesAutoresizingMaskIntoConstraints = false
            scroll.drawsBackground = false
            scroll.hasVerticalScroller = true
            scroll.autohidesScrollers = true
            scroll.documentView = stack
            addSubview(scroll)
            NSLayoutConstraint.activate([
                newRow.topAnchor.constraint(equalTo: topAnchor, constant: -2),
                newRow.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
                newRow.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
                newRow.heightAnchor.constraint(equalToConstant: 28),
                scroll.topAnchor.constraint(equalTo: newRow.bottomAnchor, constant: -4),
                scroll.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
                scroll.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
                scroll.bottomAnchor.constraint(equalTo: bottomAnchor),
                stack.topAnchor.constraint(equalTo: scroll.contentView.topAnchor),
                stack.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor),
                stack.trailingAnchor.constraint(equalTo: scroll.contentView.trailingAnchor),
            ])
        } else {
            addSubview(stack)
            addSubview(plusButton)
            NSLayoutConstraint.activate([
                stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 0),
                stack.topAnchor.constraint(equalTo: topAnchor),
                stack.bottomAnchor.constraint(equalTo: bottomAnchor),
                plusButton.leadingAnchor.constraint(equalTo: stack.trailingAnchor, constant: 4),
                plusButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            ])
            // Wished-for width of all tabs together (set in reload). Below the window's own 500 hold, so it can never stretch the window.
            let pull = stack.widthAnchor.constraint(equalToConstant: 0)
            pull.priority = NSLayoutConstraint.Priority(400)
            pull.isActive = true
            stackPref = pull
            // Not required (999): with dozens of tabs the row overflows and is clipped, instead of forcing the window wider than the screen.
            let tail = stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -44)
            tail.priority = NSLayoutConstraint.Priority(999)
            tail.isActive = true
            setContentCompressionResistancePriority(NSLayoutConstraint.Priority(1), for: .horizontal)
            setContentHuggingPriority(NSLayoutConstraint.Priority(1), for: .horizontal)
        }
    }
    required init?(coder: NSCoder) { fatalError() }

    @objc private func newTapped() { onNew?() }

    /// Double-click empty space in the tab row to open a new tab.
    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 { onNew?() } else { super.mouseDown(with: event) }
    }

    func reload(tabs: [Tab], active: Tab?) {
        var views: [NSView] = []
        var live = Set<UUID>()
        var fresh: [TabItemView] = []
        var added = false
        for t in tabs {
            live.insert(t.id)
            let v: TabItemView
            if let existing = items[t.id] { v = existing } else {
                v = TabItemView(tab: t)
                v.onSelect = { [weak self] in self?.onSelect?($0) }
                v.onClose = { [weak self] t in self?.lockWidth(for: t); self?.onClose?(t) }
                v.onMute = { [weak self] in self?.onMute?($0) }
                v.onMenu = { [weak self] in self?.onMenu?($0) }
                items[t.id] = v
                added = true
                if vertical {
                    v.heightAnchor.constraint(equalToConstant: 32).isActive = true
                    fresh.append(v)
                } else {
                    v.heightAnchor.constraint(equalToConstant: 34).isActive = true
                }
                v.alphaValue = 0
                NSAnimationContext.runAnimationGroup { $0.duration = 0.2; v.animator().alphaValue = 1 }
            }
            v.refresh(selected: t === active)
            views.append(v)
        }
        if added { lockedWidth = nil }
        tabCount = tabs.count
        let wanted = lockedWidth ?? wantedTabWidth
        let wantedTotal = wanted * CGFloat(tabs.count)
        if stackPref?.constant != wantedTotal { stackPref?.constant = wantedTotal }
        var removed = false
        for (id, v) in items where !live.contains(id) { v.removeFromSuperview(); items[id] = nil; removed = true }
        // The "+" is a separate view that sits right after the last tab (like Chrome).
        let changed = stack.arrangedSubviews != views
        if !changed {
            // nothing to rearrange: skip the layout work entirely
        } else if removed && !added && lockedWidth == nil {
            // Closing a tab: neighbours slide into place instead of jumping.
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.22
                ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                ctx.allowsImplicitAnimation = true
                stack.setViews(views, in: .leading)
                stack.layoutSubtreeIfNeeded()
            }
        } else {
            stack.setViews(views, in: .leading)
            if lockedWidth != nil {
                // Spam-closing: jump straight into place and show the next tab's X under the pointer.
                stack.layoutSubtreeIfNeeded()
                DispatchQueue.main.async { [weak self] in self?.refreshHover() }
            }
        }
        fresh.forEach { $0.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true }
    }
}

// MARK: - Bookmarks bar

final class BookmarkChip: ChromeView {
    let bookmark: Bookmark
    var onOpen: ((Bookmark, Bool) -> Void)?       // Bool = open in a new tab
    var onRemove: ((Bookmark) -> Void)?
    private let icon = NSImageView()
    private let label = NSTextField(labelWithString: "")
    private var tracking: NSTrackingArea?

    init(bookmark: Bookmark) {
        self.bookmark = bookmark
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        radius = 7

        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.imageScaling = .scaleProportionallyDown
        if let f = FaviconCache.shared.image(forHost: URL(string: bookmark.url)?.host) {
            icon.image = f
        } else {
            icon.image = NSImage(systemSymbolName: "star.fill", accessibilityDescription: nil)
            icon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 9, weight: .regular)
            icon.contentTintColor = Theme.accent
        }
        icon.wantsLayer = true
        icon.layer?.cornerRadius = 3
        icon.layer?.masksToBounds = true
        addSubview(icon)

        label.translatesAutoresizingMaskIntoConstraints = false
        label.stringValue = bookmark.title
        label.font = .systemFont(ofSize: 12)
        label.textColor = .secondaryLabelColor
        label.lineBreakMode = .byTruncatingTail
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        addSubview(label)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 24),
            widthAnchor.constraint(lessThanOrEqualToConstant: 190),
            icon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            icon.centerYAnchor.constraint(equalTo: centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 14),
            icon.heightAnchor.constraint(equalToConstant: 14),
            label.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 6),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])

    }
    required init?(coder: NSCoder) { fatalError() }

    @objc private func openInNewTab() { onOpen?(bookmark, true) }
    @objc private func removeTapped() { onRemove?(bookmark) }

    override func hitTest(_ point: NSPoint) -> NSView? { frame.contains(point) ? self : nil }
    override func mouseDown(with event: NSEvent) { onOpen?(bookmark, event.modifierFlags.contains(.command)) }
    override func rightMouseDown(with event: NSEvent) {
        CustomMenu.showAtMouse([
            .item("Open in New Tab") { [weak self] in self?.openInNewTab() },
            .item("Remove Bookmark") { [weak self] in self?.removeTapped() },
        ])
    }
    override func otherMouseUp(with event: NSEvent) { if event.buttonNumber == 2 { onOpen?(bookmark, true) } }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = tracking { removeTrackingArea(t) }
        let t = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInKeyWindow], owner: self, userInfo: nil)
        addTrackingArea(t); tracking = t
    }
    override func mouseEntered(with event: NSEvent) { fill = Theme.tabHover }
    override func mouseExited(with event: NSEvent) { fill = .clear }
}

/// Bookmarks the user saves live here, at the top of every window.
final class BookmarksBar: NSView {
    var onOpen: ((Bookmark, Bool) -> Void)?
    var onRemove: ((Bookmark) -> Void)?
    private let scroll = NSScrollView()
    private let stack = NSStackView()
    private let hint = NSTextField(labelWithString: "Press ⌘D on any page and it will be kept here")
    private(set) var key = ""

    init() {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.masksToBounds = true
        stack.orientation = .horizontal
        stack.spacing = 4
        stack.alignment = .centerY
        stack.translatesAutoresizingMaskIntoConstraints = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.drawsBackground = false
        scroll.hasHorizontalScroller = true
        scroll.hasVerticalScroller = false
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        scroll.documentView = stack
        hint.translatesAutoresizingMaskIntoConstraints = false
        hint.font = .systemFont(ofSize: 11.5)
        hint.textColor = .tertiaryLabelColor
        addSubview(scroll)
        addSubview(hint)
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            scroll.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            scroll.topAnchor.constraint(equalTo: topAnchor),
            scroll.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor),
            stack.topAnchor.constraint(equalTo: scroll.contentView.topAnchor),
            stack.bottomAnchor.constraint(equalTo: scroll.contentView.bottomAnchor),
            hint.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            hint.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }

    /// Rebuilds only when the bookmarks (or which icons are available) actually changed.
    func reload(_ marks: [Bookmark]) {
        let newKey = marks.map { m in
            m.url + (FaviconCache.shared.image(forHost: URL(string: m.url)?.host) != nil ? "•" : "")
        }.joined(separator: "|")
        guard newKey != key else { return }
        key = newKey
        for v in stack.arrangedSubviews { stack.removeArrangedSubview(v); v.removeFromSuperview() }
        for b in marks {
            let chip = BookmarkChip(bookmark: b)
            chip.onOpen = { [weak self] in self?.onOpen?($0, $1) }
            chip.onRemove = { [weak self] in self?.onRemove?($0) }
            stack.addArrangedSubview(chip)
        }
        hint.isHidden = !marks.isEmpty
    }
}
