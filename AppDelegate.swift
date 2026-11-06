import AppKit
import VeilCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    static var shared: AppDelegate { NSApp.delegate as! AppDelegate }

    private(set) var controllers: [BrowserWindowController] = []
    private var pendingURLs: [URL] = []
    private var started = false
    private var sweepTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let s = Services.shared
        s.applyAppearance()
        AppIcon.apply()
        buildMenu()

        // Restore session cookies and load compiled blocking rules BEFORE any page loads,
        // so the first request is already protected and logins are already in place.
        var finished = false
        let go = { [weak self] in
            guard !finished else { return }
            finished = true
            self?.startBrowsing()
        }
        let group = DispatchGroup()
        group.enter(); s.cookies.restore { group.leave() }
        group.enter(); s.blocker.whenReady { group.leave() }
        s.blocker.loadCached()
        group.notify(queue: .main, execute: go)
        DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: go)   // never hang on startup
    }

    private func startBrowsing() {
        let s = Services.shared
        let wc = BrowserWindowController()
        controllers.append(wc)
        let saved = s.sessionStore.value
        if s.settings.restoreSession, !saved.tabs.isEmpty { wc.restore(saved) }
        else { wc.openTab(configuration: nil, url: nil, activate: true) }
        wc.window?.alphaValue = 0
        wc.showWindow(nil)
        wc.ensureOnScreenSoon()
        NSApp.activate(ignoringOtherApps: true)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.3
            wc.window?.animator().alphaValue = CGFloat(max(60, min(100, s.settings.windowOpacity))) / 100
        }
        wc.window?.level = s.settings.alwaysOnTop ? .floating : .normal

        started = true
        for u in pendingURLs { openURL(u) }
        pendingURLs = []

        sweepTimer = Timer.scheduledTimer(withTimeInterval: 120, repeats: true) { [weak self] _ in
            let minutes = Services.shared.settings.discardIdleTabsMinutes
            self?.controllers.forEach { $0.discardIdleTabs(minutes: minutes) }
        }
        sweepTimer?.tolerance = 30
        s.blocker.updateIfStale()
        offerListsOnFirstRun()
    }

    private func offerListsOnFirstRun() {
        let s = Services.shared
        guard !s.settings.didOfferLists else { return }
        s.updateSettings { $0.didOfferLists = true }
        let a = NSAlert()
        a.messageText = "Download ad-blocking lists?"
        a.informativeText = "Veil blocks the most common ad and tracker domains out of the box. Downloading EasyList, EasyPrivacy and uBlock Origin’s lists makes blocking much more thorough.\n\nThis connects directly to easylist.to and ublockorigin.github.io, with no cookies or identifiers. It’s the only time Veil contacts a third party."
        a.addButton(withTitle: "Download and keep updated")
        a.addButton(withTitle: "Download once")
        a.addButton(withTitle: "Not now")
        let r = a.runModal()
        if r == .alertThirdButtonReturn { return }
        if r == .alertFirstButtonReturn { s.updateSettings { $0.autoUpdateLists = true } }
        s.blocker.downloadLists { _, _ in }
    }

    // MARK: - Session + windows

    func snapshotSession() {
        guard started else { return }
        var state = SessionState()
        for (ci, c) in controllers.enumerated() {
            for t in c.tabs where !t.isPrivate {
                guard let u = t.url ?? t.webView?.url,
                      ["http", "https"].contains(u.scheme ?? "") || u.host == "newtab" else { continue }
                if ci == 0, t === c.active { state.active = state.tabs.count }
                state.tabs.append(SavedTab(url: u.absoluteString, title: t.title))
            }
        }
        Services.shared.sessionStore.value = state
    }

    /// Private tabs share one in-memory store; once the last private tab is gone, throw it away.
    func cleanupPrivateStore() {
        if !controllers.contains(where: { $0.tabs.contains(where: { $0.isPrivate }) }) {
            Services.shared.dropPrivateStore()
        }
    }

    func windowClosing(_ c: BrowserWindowController) {
        snapshotSession()
        controllers.removeAll { $0 === c }
    }

    /// Puts every setting back to its default (bookmarks, history and downloads are kept).
    @objc func resetAllSettings(_ sender: Any?) {
        let alert = NSAlert()
        alert.messageText = "Reset all Veil settings?"
        alert.informativeText = "Everything in Settings goes back to its default. Bookmarks, history and downloads are not touched."
        alert.addButton(withTitle: "Reset")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        Services.shared.updateSettings { $0 = Settings() }
        for c in controllers { c.applyWindowFun() }
    }

    /// Panic button (⌃⌘H): silences every tab and hides Veil at once.
    @objc func panic(_ sender: Any?) {
        for c in controllers { c.muteAllTabs() }
        NSApp.hide(nil)
    }

    @objc func newWindow(_ sender: Any?) {
        let wc = BrowserWindowController()
        if let f = NSApp.keyWindow?.frame, let w = wc.window {
            w.setFrameOrigin(NSPoint(x: f.origin.x + 28, y: f.origin.y - 28))     // cascade
            let constrained = w.constrainFrameRect(w.frame, to: NSApp.keyWindow?.screen ?? NSScreen.main)
            w.setFrame(constrained, display: false)
        }
        controllers.append(wc)
        wc.applyWindowFun()
        wc.openTab(configuration: nil, url: nil, activate: true)
        wc.showWindow(nil)
        wc.ensureOnScreenSoon()
    }

    private var frontController: BrowserWindowController? {
        (NSApp.keyWindow?.windowController as? BrowserWindowController) ?? controllers.last
    }

    func openURL(_ url: URL) {
        if let c = frontController { c.openTab(configuration: nil, url: url, activate: true); c.window?.makeKeyAndOrderFront(nil) }
        else { newWindow(nil); frontController?.active?.load(url) }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        if started { urls.forEach(openURL) } else { pendingURLs += urls }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { newWindow(nil) }
        return true
    }

    /// On quit: persist session cookies, flush every store, then exit. Cookies are never cleared.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let s = Services.shared
        if s.settings.confirmQuit {
            let total = controllers.reduce(0) { $0 + $1.tabs.count }
            if total > 1 {
                let alert = NSAlert()
                alert.messageText = "Quit Veil?"
                alert.informativeText = "You have \(total) tabs open."
                alert.addButton(withTitle: "Quit")
                alert.addButton(withTitle: "Cancel")
                if alert.runModal() != .alertFirstButtonReturn { return .terminateCancel }
            }
        }
        if s.settings.clearHistoryOnQuit { s.history.clear() }
        s.flushAll()
        var replied = false
        let reply = {
            guard !replied else { return }
            replied = true
            NSApp.reply(toApplicationShouldTerminate: true)
        }
        s.cookies.saveSessionCookies(completion: reply)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: reply)
        return .terminateLater
    }

    // MARK: - Menu

    @objc func openAbout(_ sender: Any?) { NSApp.orderFrontStandardAboutPanel(nil) }
    private func ensureController() -> BrowserWindowController? {
        if frontController == nil { newWindow(nil) }
        return frontController
    }
    @objc func openPrivacy(_ sender: Any?) { ensureController()?.openInternal("privacy") }
    @objc func openSettings(_ sender: Any?) { ensureController()?.openInternal("settings") }

    private func buildMenu() {
        let main = NSMenu()
        func add(_ menu: NSMenu, _ title: String, _ sel: Selector?, _ key: String = "",
                 _ mods: NSEvent.ModifierFlags = [.command], tag: Int = 0, target: AnyObject? = nil) {
            let item = NSMenuItem(title: title, action: sel, keyEquivalent: key)
            item.keyEquivalentModifierMask = mods
            item.tag = tag
            item.target = target
            menu.addItem(item)
        }
        func submenu(_ title: String, _ build: (NSMenu) -> Void) {
            let item = NSMenuItem(); let m = NSMenu(title: title)
            build(m); item.submenu = m; main.addItem(item)
        }
        typealias W = BrowserWindowController

        submenu("Veil") { m in
            add(m, "About Veil", #selector(openAbout(_:)), target: self)
            m.addItem(.separator())
            add(m, "Settings…", #selector(openSettings(_:)), ",", target: self)
            add(m, "Privacy Dashboard…", #selector(openPrivacy(_:)), "", target: self)
            m.addItem(.separator())
            add(m, "Panic: Mute and Hide", #selector(panic(_:)), "h", [.command, .control], target: self)
            add(m, "Reset All Settings…", #selector(resetAllSettings(_:)), "", target: self)
            add(m, "Hide Veil", #selector(NSApplication.hide(_:)), "h")
            add(m, "Hide Others", #selector(NSApplication.hideOtherApplications(_:)), "h", [.command, .option])
            m.addItem(.separator())
            add(m, "Quit Veil", #selector(NSApplication.terminate(_:)), "q")
        }
        submenu("File") { m in
            add(m, "New Tab", #selector(W.newTab(_:)), "t")
            add(m, "New Private Tab", #selector(W.newPrivateTab(_:)), "n", [.command, .shift])
            add(m, "New Window", #selector(newWindow(_:)), "n", target: self)
            add(m, "Reopen Closed Tab", #selector(W.reopenClosedTab(_:)), "t", [.command, .shift])
            add(m, "Duplicate Tab", #selector(W.duplicateTab(_:)), "d", [.command, .option])
            add(m, "Open Location", #selector(W.focusAddressBar(_:)), "l")
            m.addItem(.separator())
            add(m, "Close Tab", #selector(W.closeCurrentTab(_:)), "w")
            add(m, "Close Other Tabs", #selector(W.closeOtherTabsAction(_:)), "w", [.command, .option])
            add(m, "Copy Page Address", #selector(W.copyPageAddress(_:)), "c", [.command, .shift])
            add(m, "Copy All Tab Addresses", #selector(W.copyAllTabAddresses(_:)), "c", [.command, .option])
            add(m, "Open Links from Clipboard", #selector(W.openLinksFromClipboard(_:)), "v", [.command, .option])
            add(m, "Copy Page Screenshot", #selector(W.copyPageScreenshot(_:)), "s", [.command, .option])
            add(m, "Save Page as PDF…", #selector(W.savePageAsPDF(_:)), "p", [.command, .option])
            add(m, "Print…", #selector(W.printPage(_:)), "p")
        }
        submenu("Edit") { m in
            add(m, "Undo", Selector(("undo:")), "z")
            add(m, "Redo", Selector(("redo:")), "z", [.command, .shift])
            m.addItem(.separator())
            add(m, "Cut", #selector(NSText.cut(_:)), "x")
            add(m, "Copy", #selector(NSText.copy(_:)), "c")
            add(m, "Paste", #selector(NSText.paste(_:)), "v")
            add(m, "Select All", #selector(NSText.selectAll(_:)), "a")
            m.addItem(.separator())
            add(m, "Find…", #selector(NSResponder.performTextFinderAction(_:)), "f", tag: 1)
            add(m, "Find Next", #selector(NSResponder.performTextFinderAction(_:)), "g", tag: 2)
            add(m, "Find Previous", #selector(NSResponder.performTextFinderAction(_:)), "g", [.command, .shift], tag: 3)
        }
        submenu("View") { m in
            add(m, "Reload Page", #selector(W.reloadOrStop(_:)), "r")
            add(m, "Reload Without Cache", #selector(W.hardReload(_:)), "r", [.command, .shift])
            add(m, "Stop", #selector(W.stopLoading(_:)), ".")
            add(m, "Reload All Tabs", #selector(W.reloadAllTabs(_:)), "r", [.command, .option])
            add(m, "Web Inspector", #selector(W.showWebInspector(_:)), "i", [.command, .option])
            add(m, "Mute or Unmute This Tab", #selector(W.muteCurrentTab(_:)), "m", [.command, .option])
            m.addItem(.separator())
            add(m, "Zoom In", #selector(W.zoomIn(_:)), "=")
            add(m, "Zoom Out", #selector(W.zoomOut(_:)), "-")
            add(m, "Actual Size", #selector(W.zoomReset(_:)), "0")
            m.addItem(.separator())
            add(m, "Toggle Vertical Tabs", #selector(W.toggleVerticalTabs(_:)), "\\", [.command, .shift])
            add(m, "Toggle Bookmarks Bar", #selector(W.toggleBookmarksBar(_:)), "b", [.command, .option])
            add(m, "Keep Window on Top", #selector(W.toggleAlwaysOnTop(_:)), "t", [.command, .option])
            add(m, "Enter Full Screen", #selector(NSWindow.toggleFullScreen(_:)), "f", [.command, .control])
        }
        submenu("History") { m in
            add(m, "Back", #selector(W.goBack(_:)), "[")
            add(m, "Forward", #selector(W.goForward(_:)), "]")
            m.addItem(.separator())
            add(m, "Show All History", #selector(W.showHistory(_:)), "y")
            add(m, "Show Downloads", #selector(W.showDownloads(_:)), "l", [.command, .option])
        }
        submenu("Bookmarks") { m in
            add(m, "Bookmark This Page", #selector(W.toggleBookmark(_:)), "d")
            add(m, "Show Bookmarks", #selector(W.showBookmarks(_:)), "b", [.command, .shift])
        }
        submenu("Window") { m in
            add(m, "Minimize", #selector(NSWindow.performMiniaturize(_:)), "m")
            add(m, "Zoom", #selector(NSWindow.performZoom(_:)))
            m.addItem(.separator())
            add(m, "Next Tab", #selector(W.nextTab(_:)), "\t", [.control])
            add(m, "Previous Tab", #selector(W.previousTab(_:)), "\t", [.control, .shift])
            add(m, "Next Tab", #selector(W.nextTab(_:)), "]", [.command, .shift])
            add(m, "Previous Tab", #selector(W.previousTab(_:)), "[", [.command, .shift])
            add(m, "Move Tab Left", #selector(W.moveTabLeft(_:)), "[", [.command, .option])
            add(m, "Move Tab Right", #selector(W.moveTabRight(_:)), "]", [.command, .option])
            add(m, "Search Tabs…", #selector(W.searchTabs(_:)), "a", [.command, .shift])
            add(m, "Sort Tabs by Site", #selector(W.sortTabsBySite(_:)), "")
            add(m, "Close Duplicate Tabs", #selector(W.closeDuplicateTabs(_:)), "")
            m.addItem(.separator())
            for n in 1...9 { add(m, n == 9 ? "Last Tab" : "Tab \(n)", #selector(W.selectTabNumber(_:)), "\(n)", tag: n) }
            NSApp.windowsMenu = m
        }
        NSApp.mainMenu = main
    }
}
