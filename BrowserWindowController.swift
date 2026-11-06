import AppKit
import WebKit
import VeilCore

/// A window that turns the mouse's side buttons into Back and Forward.
final class BrowserWindow: NSWindow {
    var onBack: (() -> Void)?
    var onForward: (() -> Void)?

    override func sendEvent(_ event: NSEvent) {
        if (event.type == .otherMouseDown || event.type == .otherMouseUp), Services.shared.settings.mouseNavButtons {
            switch event.buttonNumber {
            case 3:
                if event.type == .otherMouseDown { onBack?() }
                return
            case 4:
                if event.type == .otherMouseDown { onForward?() }
                return
            default: break
            }
        }
        super.sendEvent(event)
    }
}

/// Layout (top to bottom): tab row, toolbar (address bar), bookmarks bar, page.
/// In vertical-tab mode the tabs move to a sidebar that runs the full height of the window.
final class BrowserWindowController: NSWindowController, NSWindowDelegate, NSTextFieldDelegate, TabHost {
    private(set) var tabs: [Tab] = []
    private(set) var active: Tab?
    private var recentlyClosed: [URL] = []

    private let content = ChromeView()
    private let tabRow = DragView()
    private let sidebar = DragView()
    private let toolbar = DragView()
    private let bookmarksBar = BookmarksBar()
    private let addressBox = ClickableBox()
    private let addressField = AddressField()
    private let hStrip = TabStripView(vertical: false)
    private let vStrip = TabStripView(vertical: true)
    private let webContainer = ChromeView()
    private let progress = ChromeView()
    private let downloadsPopover = DownloadsPopover()

    private lazy var backButton = symbolButton("chevron.left", tip: "Back (⌘[)", target: self, action: #selector(goBack))
    private lazy var forwardButton = symbolButton("chevron.right", tip: "Forward (⌘])", target: self, action: #selector(goForward))
    private lazy var reloadButton = symbolButton("arrow.clockwise", tip: "Reload (⌘R)", target: self, action: #selector(reloadOrStop))
    private lazy var shieldButton = symbolButton("shield.lefthalf.filled", tip: "Blocking", target: self, action: #selector(showShieldMenu(_:)))
    private lazy var downloadsButton = symbolButton("arrow.down.circle", tip: "Downloads", target: self, action: #selector(showDownloadsMenu(_:)))
    private lazy var starButton = symbolButton("star", tip: "Bookmark (⌘D)", target: self, action: #selector(toggleBookmark))
    private lazy var menuButton = symbolButton("ellipsis", tip: "Menu", target: self, action: #selector(showMainMenu(_:)))

    private let tabRowHeight: CGFloat = 40
    private let sidebarWidthOpen: CGFloat = 214
    private var tabRowHeightConstraint: NSLayoutConstraint!
    private var sidebarWidthConstraint: NSLayoutConstraint!
    private var tabsLeading: NSLayoutConstraint!
    private var progressWidth: NSLayoutConstraint!
    private var bookmarksHeight: NSLayoutConstraint!

    init() {
        let w = BrowserWindow(contentRect: NSRect(x: 0, y: 0, width: 1280, height: 820),
                         styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                         backing: .buffered, defer: false)
        w.titlebarAppearsTransparent = true
        w.titleVisibility = .hidden
        w.tabbingMode = .disallowed
        w.collectionBehavior.insert(.fullScreenPrimary)     // without this macOS refuses full screen (just beeps)
        w.minSize = NSSize(width: 560, height: 420)
        w.isRestorable = false
        w.isReleasedWhenClosed = false
        super.init(window: w)
        w.delegate = self
        // The green button goes full screen (hold Option for the normal zoom).
        if let z = w.standardWindowButton(.zoomButton) {
            z.target = self
            z.action = #selector(zoomButtonClicked(_:))
        }
        w.onBack = { [weak self] in self?.active?.webView?.goBack() }
        w.onForward = { [weak self] in self?.active?.webView?.goForward() }
        buildUI()
        placeOnScreen()
        restoreWindowFrame()
        applyLayoutMode(animated: false)
        let nc = NotificationCenter.default
        nc.addObserver(self, selector: #selector(settingsChanged), name: .veilSettingsChanged, object: nil)
        nc.addObserver(self, selector: #selector(keyStateChanged), name: NSWindow.didBecomeKeyNotification, object: w)
        nc.addObserver(self, selector: #selector(keyStateChanged), name: NSWindow.didResignKeyNotification, object: w)
        nc.addObserver(self, selector: #selector(refreshBookmarks), name: .bookmarksChanged, object: nil)
        nc.addObserver(self, selector: #selector(refreshDownloadsButton), name: .downloadsChanged, object: nil)
        nc.addObserver(self, selector: #selector(keepOnScreen), name: NSApplication.didChangeScreenParametersNotification, object: nil)
        nc.addObserver(self, selector: #selector(downloadStarted), name: .downloadStarted, object: nil)
        downloadsPopover.onShowAll = { [weak self] in self?.showDownloads(nil) }
        refreshBookmarks()
    }
    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Window placement (always fully on screen)

    private func placeOnScreen() {
        guard let w = window else { return }
        let vf = (w.screen ?? NSScreen.main)?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
        let size = NSSize(width: min(900, vf.width * 0.7), height: min(700, vf.height * 0.85))
        let origin = NSPoint(x: vf.midX - size.width / 2, y: vf.midY - size.height / 2)
        w.setFrame(NSRect(origin: origin, size: size), display: false)
    }

    /// If any part of the window ended up off the visible screen, nudge it back.
    private var clamping = false
    // Window buttons for full screen (macOS hides its own there)
    private let fsLights = TrafficLights()
    private var minimizeAfterExit = false

    private func showFullScreenButtons(_ show: Bool) {
        if show {
            fsLights.onClose = { [weak self] in self?.window?.performClose(nil) }
            fsLights.onMinimize = { [weak self] in
                // macOS can't minimise a full-screen window, so leave full screen first, then minimise.
                self?.minimizeAfterExit = true
                self?.window?.toggleFullScreen(nil)
            }
            fsLights.onZoom = { [weak self] in self?.window?.toggleFullScreen(nil) }
            // Placed with a plain frame (not Auto Layout): 16 from the left, centred 20 from the top edge,
            // and kept that distance from the top while the window changes size.
            fsLights.translatesAutoresizingMaskIntoConstraints = true
            fsLights.frame = NSRect(x: 16, y: content.bounds.height - 30, width: 52, height: 20)
            fsLights.autoresizingMask = [.minYMargin]
            content.addSubview(fsLights, positioned: .above, relativeTo: nil)
        } else {
            fsLights.removeFromSuperview()
        }
    }

    private var fullScreenActive = false   // true from the start of entering full screen until it has been left
    @objc func keepOnScreen() {
        guard !clamping else { return }
        clamping = true
        defer { clamping = false }
        guard let w = window, !fullScreenActive, !w.styleMask.contains(.fullScreen), let screen = w.screen ?? NSScreen.main else { return }
        let vf = screen.visibleFrame
        w.minSize = NSSize(width: min(560, vf.width), height: min(420, vf.height))
        var f = w.frame
        f.size.width = min(f.width, vf.width)
        f.size.height = min(f.height, vf.height)
        if f.maxX > vf.maxX { f.origin.x = vf.maxX - f.width }
        if f.minX < vf.minX { f.origin.x = vf.minX }
        if f.maxY > vf.maxY { f.origin.y = vf.maxY - f.height }
        if f.minY < vf.minY { f.origin.y = vf.minY }
        if f != w.frame { w.setFrame(f, display: true, animate: false) }
    }

    /// Re-check once the window is on screen and layout has settled (Auto Layout can grow the window upward).
    func ensureOnScreenSoon() {
        for delay in [0.0, 0.4] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in self?.keepOnScreen() }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in self?.writeLayoutLog() }
    }

    /// Writes ~/veil-layout.log with the window and view sizes (for diagnosing layout problems).
    private func writeLayoutLog() {
        guard let w = window else { return }
        let vf = (w.screen ?? NSScreen.main)?.visibleFrame ?? .zero
        func d(_ n: String, _ v: NSView) -> String {
            "\(n): frame=\(NSStringFromRect(v.frame)) fitting=\(NSStringFromSize(v.fittingSize))\n"
        }
        var out = "window=\(NSStringFromRect(w.frame)) screenVisible=\(NSStringFromRect(vf))\n"
        out += "min=\(NSStringFromSize(w.minSize)) max=\(NSStringFromSize(w.maxSize)) tabs=\(tabs.count)\n"
        out += d("content", content) + d("tabRow", tabRow) + d("hStrip", hStrip) + d("sidebar", sidebar)
        let st = Services.shared.settings
        out += "settings: pageFilter=\(st.pageFilter) dimPages=\(st.dimPages) windowOpacity=\(st.windowOpacity) accent=\(st.accent) theme=\(st.theme) startPage=\(st.newTab.background)\n"
        out += d("toolbar", toolbar) + d("bookmarksBar", bookmarksBar) + d("webContainer", webContainer)
        let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("veil-layout.log")
        try? out.write(to: url, atomically: true, encoding: .utf8)
    }

    // MARK: - UI

    private func buildUI() {
        guard let window = window else { return }
        content.fill = Theme.chrome
        window.contentView = content
        // Use the real macOS close / minimize / zoom buttons (top-left), so they always sit where they should.
        for b in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            window.standardWindowButton(b)?.isHidden = false
        }

        for v in [tabRow, sidebar, toolbar, bookmarksBar, webContainer, progress] as [NSView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview(v)
        }
        tabRow.layer?.masksToBounds = true
        sidebar.layer?.masksToBounds = true
        webContainer.fill = Theme.pageBackdrop
        webContainer.radius = 10
        webContainer.layer?.masksToBounds = true
        progress.fill = Theme.accent
        progress.alphaValue = 0

        tabRow.addSubview(hStrip)
        sidebar.addSubview(vStrip)

        // Address bar
        addressBox.fill = Theme.field
        addressBox.radius = 9
        addressBox.translatesAutoresizingMaskIntoConstraints = false
        addressField.translatesAutoresizingMaskIntoConstraints = false
        addressField.isBordered = false
        addressField.isBezeled = false
        addressField.drawsBackground = false
        addressField.focusRingType = .none
        addressField.font = .systemFont(ofSize: 13)
        addressField.placeholderString = "Search or enter address"
        addressField.lineBreakMode = .byTruncatingTail
        addressField.usesSingleLineMode = true
        addressField.target = self
        addressField.action = #selector(addressEntered(_:))
        addressField.delegate = self
        addressField.onFocus = { [weak self] in
            if let u = self?.active?.url, u.scheme != "veil" { self?.addressField.stringValue = u.absoluteString }
        }
        addressBox.field = addressField
        addressBox.addSubview(addressField)

        let bar = NSStackView(views: [backButton, forwardButton, reloadButton, addressBox,
                                      shieldButton, downloadsButton, starButton, menuButton])
        bar.translatesAutoresizingMaskIntoConstraints = false
        bar.spacing = 4
        bar.alignment = .centerY
        toolbar.addSubview(bar)
        addressBox.setContentHuggingPriority(.defaultLow, for: .horizontal)
        addressBox.setContentCompressionResistancePriority(NSLayoutConstraint.Priority(1), for: .horizontal)
        addressField.setContentCompressionResistancePriority(NSLayoutConstraint.Priority(1), for: .horizontal)
        addressField.setContentHuggingPriority(NSLayoutConstraint.Priority(1), for: .horizontal)

        bookmarksBar.onOpen = { [weak self] bookmark, newTab in
            guard let self = self, let url = URL(string: bookmark.url) else { return }
            if newTab { self.openTab(configuration: nil, url: url, activate: true) } else { self.active?.load(url) }
        }
        bookmarksBar.onRemove = { bookmark in
            Services.shared.bookmarks.remove(url: bookmark.url)
            NotificationCenter.default.post(name: .bookmarksChanged, object: nil)
        }

        for strip in [hStrip, vStrip] {
            strip.onSelect = { [weak self] in self?.select($0) }
            strip.onClose = { [weak self] in self?.closeTab($0) }
            strip.onMute = { [weak self] in self?.toggleMute($0) }
            strip.onNew = { [weak self] in self?.newTab(nil) }
            strip.onMenu = { [weak self] in self?.showTabMenu(for: $0) }
        }

        tabRowHeightConstraint = tabRow.heightAnchor.constraint(equalToConstant: tabRowHeight)
        sidebarWidthConstraint = sidebar.widthAnchor.constraint(equalToConstant: 0)
        tabsLeading = hStrip.leadingAnchor.constraint(equalTo: tabRow.leadingAnchor, constant: 84)
        progressWidth = progress.widthAnchor.constraint(equalToConstant: 0)
        bookmarksHeight = bookmarksBar.heightAnchor.constraint(equalToConstant: Services.shared.settings.showBookmarksBar ? 30 : 0)

        NSLayoutConstraint.activate([
            tabRow.topAnchor.constraint(equalTo: content.topAnchor),
            tabRow.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            tabRow.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            tabRowHeightConstraint,
            tabsLeading,
            hStrip.centerYAnchor.constraint(equalTo: tabRow.centerYAnchor),
            hStrip.heightAnchor.constraint(equalToConstant: tabRowHeight - 4),
            hStrip.trailingAnchor.constraint(equalTo: tabRow.trailingAnchor),

            sidebar.topAnchor.constraint(equalTo: content.topAnchor),
            sidebar.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            sidebar.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            sidebarWidthConstraint,
            vStrip.topAnchor.constraint(equalTo: sidebar.topAnchor, constant: -(tabRowHeight + 4)),
            vStrip.bottomAnchor.constraint(equalTo: sidebar.bottomAnchor),
            vStrip.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor),
            vStrip.widthAnchor.constraint(equalToConstant: sidebarWidthOpen),

            toolbar.topAnchor.constraint(equalTo: tabRow.bottomAnchor),
            toolbar.leadingAnchor.constraint(equalTo: sidebar.trailingAnchor),
            toolbar.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            toolbar.heightAnchor.constraint(equalToConstant: 44),
            bar.leadingAnchor.constraint(equalTo: toolbar.leadingAnchor, constant: 12),
            bar.trailingAnchor.constraint(equalTo: toolbar.trailingAnchor, constant: -12),
            bar.centerYAnchor.constraint(equalTo: toolbar.centerYAnchor),
            addressBox.heightAnchor.constraint(equalToConstant: 30),
            addressField.leadingAnchor.constraint(equalTo: addressBox.leadingAnchor, constant: 12),
            addressField.trailingAnchor.constraint(equalTo: addressBox.trailingAnchor, constant: -12),
            addressField.centerYAnchor.constraint(equalTo: addressBox.centerYAnchor),

            bookmarksBar.topAnchor.constraint(equalTo: toolbar.bottomAnchor),
            bookmarksBar.leadingAnchor.constraint(equalTo: sidebar.trailingAnchor),
            bookmarksBar.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            bookmarksHeight,

            webContainer.topAnchor.constraint(equalTo: bookmarksBar.bottomAnchor),
            webContainer.leadingAnchor.constraint(equalTo: sidebar.trailingAnchor, constant: 6),
            webContainer.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -6),
            webContainer.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -6),

            progress.topAnchor.constraint(equalTo: webContainer.topAnchor),
            progress.leadingAnchor.constraint(equalTo: webContainer.leadingAnchor),
            progress.heightAnchor.constraint(equalToConstant: 2),
            progressWidth,
        ])
        content.addSubview(progress, positioned: .above, relativeTo: webContainer)
    }

    private func applyLayoutMode(animated: Bool) {
        let vertical = Services.shared.settings.verticalTabs
        let rowHeight: CGFloat = vertical ? 0 : tabRowHeight
        let width: CGFloat = vertical ? sidebarWidthOpen : 0
        guard animated else {
            tabRowHeightConstraint.constant = rowHeight
            sidebarWidthConstraint.constant = width
            return
        }
        if tabRowHeightConstraint.constant == rowHeight && sidebarWidthConstraint.constant == width { return }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.3
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            ctx.allowsImplicitAnimation = true
            tabRowHeightConstraint.animator().constant = rowHeight
            sidebarWidthConstraint.animator().constant = width
        }
    }

    private func applyBookmarksBarVisibility() {
        let target: CGFloat = Services.shared.settings.showBookmarksBar ? 30 : 0
        guard bookmarksHeight.constant != target else { return }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.22
            ctx.allowsImplicitAnimation = true
            bookmarksHeight.animator().constant = target
        }
    }

    @objc private func keyStateChanged() {
        // Native window buttons dim themselves when the window is inactive.
    }

    /// Window-level fun settings (see-through window, stay on top).
    func applyWindowFun(animated: Bool = false) {
        guard let w = window else { return }
        let st = Services.shared.settings
        w.level = st.alwaysOnTop ? .floating : .normal
        w.sharingType = st.hideFromCapture ? .none : .readOnly      // .none: invisible to screenshots and screen recording
        let a = CGFloat(max(60, min(100, st.windowOpacity))) / 100
        if animated { w.animator().alphaValue = a } else { w.alphaValue = a }
    }

    @objc private func settingsChanged() {
        applyWindowFun(animated: true)
        applyLayoutMode(animated: true)
        applyBookmarksBarVisibility()
        progress.fill = Theme.accent
        tabs.forEach { $0.refreshConfiguration() }
        refreshChrome()
    }

    @objc private func refreshBookmarks() {
        bookmarksBar.reload(Services.shared.bookmarks.all)
    }

    @objc private func refreshDownloadsButton() {
        let busy = Services.shared.downloads.hasActive
        downloadsButton.image = NSImage(systemSymbolName: busy ? "arrow.down.circle.fill" : "arrow.down.circle",
                                        accessibilityDescription: "Downloads")
        downloadsButton.contentTintColor = busy ? Theme.accent : .secondaryLabelColor
    }

    // MARK: - Tab management

    @discardableResult
    func openTab(configuration: WKWebViewConfiguration?, url: URL?, activate: Bool, isPrivate: Bool) -> Tab {
        let tab: Tab
        if let c = configuration {
            tab = Tab(host: self, configuration: c, isPrivate: isPrivate)
        } else {
            let start = isPrivate ? URL(string: "veil://newtab?private=1")! : URLResolver.newTabURL
            tab = Tab(host: self, url: url ?? start, isPrivate: isPrivate)
        }
        if Services.shared.settings.newTabNextToCurrent, let a = active, let i = tabs.firstIndex(where: { $0 === a }) { tabs.insert(tab, at: i + 1) }
        else { tabs.append(tab) }          // by default new tabs go to the far end
        if activate { select(tab) } else { reloadStrips() }
        AppDelegate.shared.snapshotSession()
        return tab
    }

    @discardableResult
    func openTab(configuration: WKWebViewConfiguration?, url: URL?, activate: Bool) -> Tab {
        openTab(configuration: configuration, url: url, activate: activate, isPrivate: false)
    }

    func restore(_ state: SessionState) {
        for saved in state.tabs {
            guard let u = URL(string: saved.url) else { continue }
            tabs.append(Tab(host: self, url: u, title: saved.title))
        }
        if tabs.isEmpty { openTab(configuration: nil, url: nil, activate: true); return }
        select(tabs[min(max(state.active, 0), tabs.count - 1)])
    }

    func select(_ tab: Tab) {
        active?.webView?.removeFromSuperview()
        active = tab
        tab.lastActive = Date()
        let wv = tab.ensureWebView()
        wv.translatesAutoresizingMaskIntoConstraints = false
        wv.alphaValue = 0
        webContainer.addSubview(wv)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.18
            wv.animator().alphaValue = 1
        }
        NSLayoutConstraint.activate([
            wv.topAnchor.constraint(equalTo: webContainer.topAnchor),
            wv.bottomAnchor.constraint(equalTo: webContainer.bottomAnchor),
            wv.leadingAnchor.constraint(equalTo: webContainer.leadingAnchor),
            wv.trailingAnchor.constraint(equalTo: webContainer.trailingAnchor),
        ])
        refreshChrome()
        let isBlankPage = tab.url == nil || tab.url?.host == "newtab"
        window?.makeFirstResponder(isBlankPage ? addressField : wv)
        AppDelegate.shared.snapshotSession()
    }

    func closeTab(_ tab: Tab) {
        guard let i = tabs.firstIndex(where: { $0 === tab }) else { return }
        if !tab.isPrivate, let u = tab.url, u.scheme != "veil" {
            recentlyClosed.append(u)
            if recentlyClosed.count > 20 { recentlyClosed.removeFirst() }
        }
        let wasActive = tab === active
        tabs.remove(at: i)
        tab.shutdown()
        AppDelegate.shared.cleanupPrivateStore()
        if tabs.isEmpty { active = nil; window?.close(); return }
        if wasActive { select(tabs[min(i, tabs.count - 1)]) } else { reloadStrips() }
        AppDelegate.shared.snapshotSession()
    }

    func toggleMute(_ tab: Tab) { tab.setMuted(!tab.isMuted) }

    func discardIdleTabs(minutes: Int) {
        guard minutes > 0 else { return }
        for tab in tabs where tab !== active && tab.isLoaded && !tab.isLoading && !tab.isPrivate {
            guard Date().timeIntervalSince(tab.lastActive) > Double(minutes) * 60, let wv = tab.webView else { continue }
            if wv.cameraCaptureState != .none || wv.microphoneCaptureState != .none || tab.isPlayingMedia { continue }
            wv.requestMediaPlaybackState { [weak self, weak tab] state in
                guard let tab = tab, tab !== self?.active, state != .playing else { return }
                tab.discard()
                self?.reloadStrips()
            }
        }
    }

    private func reloadStrips() {
        hStrip.reload(tabs: tabs, active: active)
        vStrip.reload(tabs: tabs, active: active)
    }

    func tabDidChange(_ tab: Tab) {
        if tab === active { refreshChrome() } else { reloadStrips() }
    }

    /// Small toolbar tidy-ups from Settings.
    private func applyToolbarButtons() {
        let st = Services.shared.settings
        shieldButton.isHidden = st.hideShieldButton
        downloadsButton.isHidden = st.hideDownloadsButton
        starButton.isHidden = st.hideBookmarkButton
    }

    private func saveWindowFrame() {
        guard Services.shared.settings.rememberWindow, !fullScreenActive, let w = window, !w.styleMask.contains(.fullScreen) else { return }
        UserDefaults.standard.set(NSStringFromRect(w.frame), forKey: "VeilWindowFrame")
    }

    private func restoreWindowFrame() {
        guard Services.shared.settings.rememberWindow, let w = window,
              let str = UserDefaults.standard.string(forKey: "VeilWindowFrame") else { return }
        let r = NSRectFromString(str)
        if r.width >= 560, r.height >= 420 { w.setFrame(r, display: false) }
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard Services.shared.settings.confirmCloseWindow, tabs.count > 1 else { return true }
        let alert = NSAlert()
        alert.messageText = "Close this window?"
        alert.informativeText = "It has \(tabs.count) tabs open."
        alert.addButton(withTitle: "Close")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }

    func windowDidMove(_ notification: Notification) { saveWindowFrame() }

    private func refreshChrome() {
        applyToolbarButtons()
        BrowserWindowController.updateDockBadge()
        reloadStrips()
        refreshBookmarks()
        refreshDownloadsButton()
        guard let tab = active else { return }
        let wv = tab.webView
        backButton.isEnabled = wv?.canGoBack ?? false
        forwardButton.isEnabled = wv?.canGoForward ?? false
        let loading = tab.isLoading
        reloadButton.image = NSImage(systemSymbolName: loading ? "xmark" : "arrow.clockwise", accessibilityDescription: nil)
        if !(window?.firstResponder === addressField.currentEditor()) {
            addressField.stringValue = tab.url.map { URLResolver.displayString(for: $0) } ?? ""
        }
        addressField.placeholderString = tab.isPrivate ? "Search privately or enter address" : "Search or enter address"
        addressBox.fill = tab.isPrivate ? Theme.privateField : Theme.field

        let isInternal = tab.url?.scheme == "veil"
        let s = Services.shared
        let host = tab.url?.host
        let allowed = host.map { s.allowlist.contains($0) } ?? false
        let blocking = s.settings.adBlocking && !allowed && !isInternal
        shieldButton.image = NSImage(systemSymbolName: blocking ? "shield.lefthalf.filled" : "shield.slash", accessibilityDescription: "Blocking")
        shieldButton.contentTintColor = blocking ? Theme.accent : .tertiaryLabelColor
        let marked = tab.url.map { s.bookmarks.contains(url: $0.absoluteString) } ?? false
        starButton.image = NSImage(systemSymbolName: marked ? "star.fill" : "star", accessibilityDescription: "Bookmark")
        starButton.contentTintColor = marked ? Theme.accent : .secondaryLabelColor
        window?.title = tab.title
        updateProgress(loading ? (wv?.estimatedProgress ?? 0) : 1, loading: loading)
    }

    private func updateProgress(_ p: Double, loading: Bool) {
        let width = webContainer.bounds.width * CGFloat(p)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.25
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            progressWidth.animator().constant = width
            progress.animator().alphaValue = loading ? 1 : 0
        }
        if !loading { DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in self?.progressWidth.constant = 0 } }
    }

    // MARK: - Address bar

    @objc private func addressEntered(_ sender: NSTextField) {
        let s = Services.shared.settings
        let url = URLResolver.resolve(sender.stringValue, searchTemplate: SearchEngines.template(for: s.searchEngine))
        active?.load(url)
        sender.stringValue = URLResolver.displayString(for: url)
        window?.makeFirstResponder(active?.webView)
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        if selector == #selector(NSResponder.cancelOperation(_:)) {
            window?.makeFirstResponder(active?.webView)
            refreshChrome()
            return true
        }
        return false
    }

    /// Don't reset the text when the user pressed Return: the action needs to read what they typed.
    func controlTextDidEndEditing(_ obj: Notification) {
        let movement = obj.userInfo?["NSTextMovement"] as? Int
        if movement != NSTextMovement.return.rawValue { refreshChrome() }
    }

    // MARK: - Actions (menu items reach these through the responder chain)

    @objc func newTab(_ sender: Any?) { openTab(configuration: nil, url: nil, activate: true) }
    @objc func newPrivateTab(_ sender: Any?) { openTab(configuration: nil, url: nil, activate: true, isPrivate: true) }
    @objc func closeCurrentTab(_ sender: Any?) { if let t = active { closeTab(t) } }
    @objc func reopenClosedTab(_ sender: Any?) {
        if let u = recentlyClosed.popLast() { openTab(configuration: nil, url: u, activate: true) }
    }
    // MARK: - Small extras

    /// Shows the number of open tabs on the Dock icon (when turned on in Settings).
    static func updateDockBadge() {
        guard Services.shared.settings.dockTabCount else { NSApp.dockTile.badgeLabel = nil; return }
        let total = NSApp.windows.compactMap { ($0.windowController as? BrowserWindowController)?.tabs.count }.reduce(0, +)
        NSApp.dockTile.badgeLabel = total > 0 ? String(total) : nil
    }

    /// Right-click menu on a tab.
    private func showTabMenu(for tab: Tab) {
        let idx = tabs.firstIndex(where: { $0 === tab }) ?? 0
        CustomMenu.showAtMouse([
            .item("Reload Tab") { _ = tab.webView?.reload() },
            .item("Duplicate Tab", enabled: tab.url != nil) { [weak self] in
                if let u = tab.url { self?.openTab(configuration: nil, url: u, activate: true, isPrivate: tab.isPrivate) }
            },
            .item(tab.isMuted ? "Unmute Tab" : "Mute Tab") { [weak self] in self?.toggleMute(tab) },
            .item("Copy Address", enabled: tab.url != nil) {
                if let u = tab.url {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(u.absoluteString, forType: .string)
                }
            },
            .separator,
            .item("Close Tab") { [weak self] in self?.closeTab(tab) },
            .item("Close Other Tabs", enabled: tabs.count > 1) { [weak self] in self?.closeOtherTabs(keeping: tab) },
            .item("Close Tabs to the Right", enabled: idx < tabs.count - 1) { [weak self] in self?.closeTabs(after: tab) },
        ])
    }

    func closeOtherTabs(keeping tab: Tab) {
        for t in Array(tabs) where t !== tab { closeTab(t) }
        select(tab)
    }

    func closeTabs(after tab: Tab) {
        guard let i = tabs.firstIndex(where: { $0 === tab }) else { return }
        for t in Array(tabs.suffix(from: i + 1)) { closeTab(t) }
    }

    private func moveActiveTab(_ d: Int) {
        guard let a = active, let i = tabs.firstIndex(where: { $0 === a }) else { return }
        let j = i + d
        guard j >= 0, j < tabs.count else { return }
        tabs.swapAt(i, j)
        reloadStrips()
        AppDelegate.shared.snapshotSession()
    }

    @objc private func zoomButtonClicked(_ sender: Any?) {
        if NSEvent.modifierFlags.contains(.option) { window?.zoom(nil) } else { window?.toggleFullScreen(nil) }
    }

    func muteAllTabs() { for t in tabs { t.setMuted(true) } }

    // MARK: - Productivity

    /// Search / jump to any open tab (⇧⌘A).
    @objc func searchTabs(_ sender: Any?) {
        var entries: [MenuEntry] = []
        for t in tabs.prefix(18) {
            let name = t.title.isEmpty ? (t.url?.host ?? "New Tab") : t.title
            let short = name.count > 46 ? String(name.prefix(45)) + "…" : name
            entries.append(.item((t === active ? "● " : "") + short) { [weak self] in self?.select(t) })
        }
        if tabs.count > 18 { entries.append(.info("…and \(tabs.count - 18) more")) }
        CustomMenu.show(entries, below: toolbar)
    }

    @objc func closeDuplicateTabs(_ sender: Any?) {
        var seen = Set<String>()
        for t in Array(tabs) {
            guard let u = t.url?.absoluteString, !u.hasPrefix("veil://") else { continue }
            if seen.contains(u) { closeTab(t) } else { seen.insert(u) }
        }
    }

    @objc func sortTabsBySite(_ sender: Any?) {
        let current = active
        tabs.sort { ($0.url?.host ?? "") < ($1.url?.host ?? "") }
        reloadStrips()
        if let c = current { select(c) }
        AppDelegate.shared.snapshotSession()
    }

    @objc func copyAllTabAddresses(_ sender: Any?) {
        let list = tabs.compactMap { $0.url?.absoluteString }.joined(separator: "\n")
        guard !list.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(list, forType: .string)
    }

    @objc func openLinksFromClipboard(_ sender: Any?) {
        guard let text = NSPasteboard.general.string(forType: .string) else { return }
        let parts = text.components(separatedBy: .whitespacesAndNewlines)
        var opened = 0
        for p in parts where opened < 30 {
            if let u = URL(string: p), let sc = u.scheme?.lowercased(), sc == "http" || sc == "https" {
                openTab(configuration: nil, url: u, activate: opened == 0, isPrivate: active?.isPrivate ?? false)
                opened += 1
            }
        }
    }

    @objc func copyPageScreenshot(_ sender: Any?) {
        active?.webView?.takeSnapshot(with: nil) { image, _ in
            guard let image = image else { return }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.writeObjects([image])
        }
    }

    @objc func savePageAsPDF(_ sender: Any?) {
        guard let tab = active, let wv = tab.webView, let win = window else { return }
        wv.createPDF { result in
            guard case .success(let data) = result else { return }
            DispatchQueue.main.async {
                let panel = NSSavePanel()
                panel.allowedFileTypes = ["pdf"]
                panel.nameFieldStringValue = (tab.title.isEmpty ? "Page" : tab.title) + ".pdf"
                panel.beginSheetModal(for: win) { resp in
                    if resp == .OK, let url = panel.url { try? data.write(to: url) }
                }
            }
        }
    }

    @objc func showWebInspector(_ sender: Any?) {
        if let wv = active?.webView as? VeilWebView { wv.showInspector() }
    }

    @objc func duplicateTab(_ sender: Any?) {
        if let t = active, let u = t.url { openTab(configuration: nil, url: u, activate: true, isPrivate: t.isPrivate) }
    }
    @objc func closeOtherTabsAction(_ sender: Any?) { if let a = active { closeOtherTabs(keeping: a) } }
    @objc func reloadAllTabs(_ sender: Any?) { for t in tabs { _ = t.webView?.reload() } }
    @objc func moveTabLeft(_ sender: Any?) { moveActiveTab(-1) }
    @objc func moveTabRight(_ sender: Any?) { moveActiveTab(1) }
    @objc func toggleBookmarksBar(_ sender: Any?) { Services.shared.updateSettings { $0.showBookmarksBar.toggle() } }
    @objc func toggleAlwaysOnTop(_ sender: Any?) { Services.shared.updateSettings { $0.alwaysOnTop.toggle() } }
    @objc func copyPageAddress(_ sender: Any?) {
        guard let u = active?.url else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(u.absoluteString, forType: .string)
    }

    @objc func focusAddressBar(_ sender: Any?) { window?.makeFirstResponder(addressField) }
    @objc func goBack(_ sender: Any?) { active?.webView?.goBack() }
    @objc func goForward(_ sender: Any?) { active?.webView?.goForward() }
    @objc func reloadOrStop(_ sender: Any?) {
        guard let t = active else { return }
        if t.isLoading { t.webView?.stopLoading() } else if let wv = t.webView { wv.reload() }
    }
    @objc func hardReload(_ sender: Any?) { active?.webView?.reloadFromOrigin() }
    @objc func stopLoading(_ sender: Any?) { active?.webView?.stopLoading() }
    @objc func nextTab(_ sender: Any?) { cycle(1) }
    @objc func previousTab(_ sender: Any?) { cycle(-1) }
    private func cycle(_ d: Int) {
        guard let a = active, let i = tabs.firstIndex(where: { $0 === a }), tabs.count > 1 else { return }
        select(tabs[(i + d + tabs.count) % tabs.count])
    }
    @objc func selectTabNumber(_ sender: NSMenuItem) {
        guard !tabs.isEmpty else { return }
        select(sender.tag == 9 ? tabs[tabs.count - 1] : tabs[min(sender.tag - 1, tabs.count - 1)])
    }
    @objc func muteCurrentTab(_ sender: Any?) { if let t = active { toggleMute(t) } }
    @objc func zoomIn(_ sender: Any?) { active?.webView?.pageZoom *= 1.1 }
    @objc func zoomOut(_ sender: Any?) { active?.webView?.pageZoom /= 1.1 }
    @objc func zoomReset(_ sender: Any?) { active?.webView?.pageZoom = 1 }
    @objc func printPage(_ sender: Any?) {
        guard let wv = active?.webView, let w = window else { return }
        wv.printOperation(with: NSPrintInfo.shared).runModal(for: w, delegate: nil, didRun: nil, contextInfo: nil)
    }
    @objc func toggleVerticalTabs(_ sender: Any?) {
        Services.shared.updateSettings { $0.verticalTabs.toggle() }
    }

    @objc func toggleBookmark(_ sender: Any?) {
        guard let t = active, let u = t.url, u.scheme != "veil" else { return }
        let b = Services.shared.bookmarks
        if b.contains(url: u.absoluteString) { b.remove(url: u.absoluteString) } else { b.add(url: u.absoluteString, title: t.title) }
        NotificationCenter.default.post(name: .bookmarksChanged, object: nil)
        refreshChrome()
    }

    @objc func toggleSiteBlocking(_ sender: Any?) {
        guard let host = active?.url?.host else { return }
        let s = Services.shared
        if s.allowlist.contains(host) { s.allowlist.remove(host) } else { s.allowlist.add(host) }
        s.notifyChanged()
        active?.webView?.reload()
    }

    private func infoItem(_ title: String) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        i.isEnabled = false
        return i
    }

    @objc private func showShieldMenu(_ sender: NSButton) {
        let s = Services.shared
        let host = active?.url?.host
        let isInternal = active?.url?.scheme == "veil"
        let allowed = host.map { s.allowlist.contains($0) } ?? false
        let cookieText: String
        switch s.settings.cookieMode {
        case "off": cookieText = "allowed"
        case "all": cookieText = "all blocked (your exceptions kept)"
        default: cookieText = "third-party blocked"
        }
        var entries: [MenuEntry] = [
            .info("Ads & trackers: " + (s.settings.adBlocking && !allowed ? "blocked" : "allowed")),
            .info("Cookies: " + (allowed ? "allowed on this site" : cookieText)),
            .separator,
        ]
        if let host = host, !isInternal {
            entries.append(.item(allowed ? "Turn blocking on for \(host)" : "Turn blocking off for \(host)") { [weak self] in
                self?.toggleSiteBlocking(nil)
            })
        }
        entries.append(.item("Privacy dashboard") { [weak self] in self?.showPrivacy(nil) })
        CustomMenu.show(entries, below: sender)
    }

    @objc private func showDownloadsMenu(_ sender: NSButton) {
        downloadsPopover.toggle(relativeTo: sender)
    }

    /// A new download pops the panel open so it is easy to find.
    @objc private func downloadStarted() {
        if Services.shared.settings.openDownloadsOnStart, window?.isKeyWindow == true {
            downloadsPopover.show(relativeTo: downloadsButton)
        }
    }

    @objc private func showMainMenu(_ sender: NSButton) {
        CustomMenu.show([
            .item("New Tab", hint: "⌘T") { [weak self] in self?.newTab(nil) },
            .item("New Private Tab") { [weak self] in self?.newPrivateTab(nil) },
            .separator,
            .item("History") { [weak self] in self?.showHistory(nil) },
            .item("Bookmarks") { [weak self] in self?.showBookmarks(nil) },
            .item("Downloads") { [weak self] in self?.showDownloads(nil) },
            .separator,
            .item("Privacy") { [weak self] in self?.showPrivacy(nil) },
            .item("Settings", hint: "⌘,") { [weak self] in self?.showSettings(nil) },
        ], below: sender, rightAlign: true)
    }

    func openInternal(_ name: String) {
        let url = URL(string: "veil://\(name)")!
        if let a = active, a.url?.host == "newtab", !a.isPrivate { a.load(url) } else { openTab(configuration: nil, url: url, activate: true) }
    }
    @objc func showSettings(_ sender: Any?) { openInternal("settings") }
    @objc func showPrivacy(_ sender: Any?) { openInternal("privacy") }
    @objc func showHistory(_ sender: Any?) { openInternal("history") }
    @objc func showBookmarks(_ sender: Any?) { openInternal("bookmarks") }
    @objc func showDownloads(_ sender: Any?) { openInternal("downloads") }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        AppDelegate.shared.windowClosing(self)
        tabs.forEach { $0.shutdown() }
        tabs.removeAll()
        AppDelegate.shared.cleanupPrivateStore()
        DispatchQueue.main.async { BrowserWindowController.updateDockBadge() }
    }

    // No resize hook: changing the frame or tab strip during a layout pass crashes AppKit.
    func windowDidResize(_ notification: Notification) {
        saveWindowFrame()
        // Deferred: the frame must not change in the middle of a layout pass.
        DispatchQueue.main.async { [weak self] in self?.keepOnScreen() }
    }
    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        // Full screen must be allowed to use the whole display (no cap there).
        if fullScreenActive || sender.styleMask.contains(.fullScreen) { return frameSize }
        guard let vf = (sender.screen ?? NSScreen.main)?.visibleFrame else { return frameSize }
        return NSSize(width: min(frameSize.width, vf.width), height: min(frameSize.height, vf.height))
    }
    func windowDidChangeScreen(_ notification: Notification) { keepOnScreen() }
    func windowDidEndLiveResize(_ notification: Notification) { keepOnScreen() }

    func windowWillEnterFullScreen(_ notification: Notification) {
        fullScreenActive = true
        window?.maxSize = NSSize(width: 100_000, height: 100_000)
        tabsLeading.constant = 84                 // leave room for the window buttons on the left
        showFullScreenButtons(true)
    }
    func windowWillExitFullScreen(_ notification: Notification) {
        showFullScreenButtons(false)
    }
    func windowDidExitFullScreen(_ notification: Notification) {
        fullScreenActive = false
        tabsLeading.constant = 84
        showFullScreenButtons(false)
        keepOnScreen()
        if minimizeAfterExit {
            minimizeAfterExit = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in self?.window?.miniaturize(nil) }
        }
    }
    func windowDidFailToEnterFullScreen(_ window: NSWindow) {
        fullScreenActive = false
        showFullScreenButtons(false)
        tabsLeading.constant = 84
        keepOnScreen()
    }
}
