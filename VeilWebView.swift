import AppKit
import WebKit
import VeilCore

/// Keeps a menu action alive (NSMenuItem only holds its target weakly).
final class MenuAction: NSObject {
    private let run: () -> Void
    init(_ run: @escaping () -> Void) { self.run = run }
    @objc func fire() { run() }
}

/// A WKWebView with Veil's right-click menu: open in a new or private tab, save images, search the
/// selection, view source, and Inspect Element.
final class VeilWebView: WKWebView {
    weak var tab: Tab?

    private struct Hit {
        var link: URL?
        var image: URL?
        var video: URL?
        var selection: String?
        init() {}
        init(_ raw: Any?) {
            guard let d = raw as? [String: Any] else { return }
            link = (d["link"] as? String).flatMap(URL.init(string:))
            image = (d["image"] as? String).flatMap(URL.init(string:))
            video = (d["video"] as? String).flatMap(URL.init(string:))
            selection = d["selection"] as? String
        }
    }
    private var hit = Hit()
    private var actions: [MenuAction] = []

    private static let hitScript = """
    (function (x, y) {
      var el = document.elementFromPoint(x, y), out = {};
      while (el) {
        if (!out.link && el.tagName === 'A' && el.href) out.link = el.href;
        if (!out.image && el.tagName === 'IMG') out.image = el.currentSrc || el.src;
        if (!out.video && el.tagName === 'VIDEO') out.video = el.currentSrc || el.src;
        el = el.parentElement;
      }
      var sel = String(window.getSelection() || '');
      if (sel) out.selection = sel.slice(0, 300);
      return out;
    })
    """

    // MARK: Find out what was clicked, then let WebKit open its menu

    override func rightMouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        let x = Int(p.x)
        let y = Int(isFlipped ? p.y : bounds.height - p.y)
        var proceeded = false
        let proceed = { [weak self] in
            guard let self = self, !proceeded else { return }
            proceeded = true
            self.continueRightMouseDown(event)
        }
        evaluateJavaScript("\(VeilWebView.hitScript)(\(x), \(y))") { [weak self] result, _ in
            self?.hit = Hit(result)
            proceed()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { proceed() }   // never leave the user without a menu
    }

    private func continueRightMouseDown(_ event: NSEvent) { super.rightMouseDown(with: event) }

    // MARK: Menu

    override func willOpenMenu(_ menu: NSMenu, with event: NSEvent) {
        super.willOpenMenu(menu, with: event)
        customize(menu)
        // "Inspect Element": always open the inspector in its own window (docked inside the page it fights Veil's layout).
        if Services.shared.settings.developerTools {
            if let idx = menu.items.firstIndex(where: { $0.title.localizedCaseInsensitiveContains("inspect") }) {
                let original = menu.items[idx]
                menu.removeItem(at: idx)
                menu.insertItem(item("Inspect Element") { [weak self] in
                    // WebKit's own item selects the element under the pointer (e.g. the text you highlighted and
                    // right-clicked); then Veil pops the inspector out into its own window.
                    if let target = original.target, let action = original.action {
                        NSApp.sendAction(action, to: target, from: original)
                    }
                    _ = self?.showInspector()
                }, at: idx)
            } else {
                if !menu.items.isEmpty { menu.addItem(.separator()) }
                menu.addItem(item("Inspect Element") { [weak self] in _ = self?.showInspector() })
            }
        }
        hit = Hit()
    }

    /// Opens WebKit's Web Inspector for this page. Returns false if this macOS version doesn't offer it.
    @discardableResult
    func showInspector() -> Bool {
        let getter = NSSelectorFromString("_inspector")
        guard responds(to: getter), let inspector = value(forKey: "_inspector") as? NSObject else { return false }
        let show = NSSelectorFromString("show")
        guard inspector.responds(to: show) else { return false }
        _ = inspector.perform(show)
        // Pop it out into a separate window right away.
        let detach = NSSelectorFromString("detach")
        if inspector.responds(to: detach) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { _ = inspector.perform(detach) }
        }
        return true
    }

    private func item(_ title: String, _ run: @escaping () -> Void) -> NSMenuItem {
        let a = MenuAction(run)
        actions.append(a)
        let i = NSMenuItem(title: title, action: #selector(MenuAction.fire), keyEquivalent: "")
        i.target = a
        return i
    }

    private func customize(_ menu: NSMenu) {
        actions.removeAll()
        let replaced = ["OpenLinkInNewWindow", "DownloadLinkedFile", "OpenImageInNewWindow", "DownloadImage",
                        "OpenMediaInNewWindow", "DownloadMedia"]
        let replacedTitles = ["Open Link in New Window", "Download Linked File", "Open Image in New Window",
                              "Download Image", "Open Video in New Window", "Download Video", "Save Image As…"]
        var firstRemoved: Int?
        for (i, it) in menu.items.enumerated().reversed() {
            let ident = it.identifier?.rawValue ?? ""
            if replaced.contains(where: { ident.contains($0) }) || replacedTitles.contains(it.title) {
                menu.removeItem(at: i)
                firstRemoved = i
            }
        }

        var ours: [NSMenuItem] = []
        let priv = tab?.isPrivate ?? false
        if let link = hit.link {
            ours.append(item("Open Link in New Tab") { [weak self] in self?.openTab(link, privateTab: priv) })
            ours.append(item("Open Link in Private Tab") { [weak self] in self?.openTab(link, privateTab: true) })
            ours.append(item("Copy Link Address") { VeilWebView.copy(link.absoluteString) })
            ours.append(item("Download Linked File") { [weak self] in self?.tab?.downloadURL(link) })
        }
        if let image = hit.image {
            if !ours.isEmpty { ours.append(.separator()) }
            ours.append(item("Save Image") { [weak self] in self?.tab?.downloadURL(image) })
            ours.append(item("Open Image in New Tab") { [weak self] in self?.openTab(image, privateTab: priv) })
            ours.append(item("Copy Image Address") { VeilWebView.copy(image.absoluteString) })
        }
        if let video = hit.video {
            if !ours.isEmpty { ours.append(.separator()) }
            ours.append(item("Save Video") { [weak self] in self?.tab?.downloadURL(video) })
            ours.append(item("Open Video in New Tab") { [weak self] in self?.openTab(video, privateTab: priv) })
        }
        if let sel = hit.selection?.trimmingCharacters(in: .whitespacesAndNewlines), !sel.isEmpty {
            if !ours.isEmpty { ours.append(.separator()) }
            let short = sel.count > 28 ? String(sel.prefix(28)) + "…" : sel
            ours.append(item("Search Web for “\(short)”") { [weak self] in
                let template = SearchEngines.template(for: Services.shared.settings.searchEngine)
                self?.openTab(URLResolver.searchURL(for: sel, template: template), privateTab: priv)
            })
        }
        var at = firstRemoved ?? 0
        for it in ours { menu.insertItem(it, at: at); at += 1 }
        if !ours.isEmpty && at < menu.items.count && !menu.items[at].isSeparatorItem { menu.insertItem(.separator(), at: at) }

        // Page tools, placed just above Inspect Element.
        var page: [NSMenuItem] = [
            .separator(),
            item("Copy Page Address") { [weak self] in
                if let u = self?.url { VeilWebView.copy(u.absoluteString) }
            },
            item("Bookmark This Page") { [weak self] in
                guard let self = self, let u = self.url, u.scheme != "veil" else { return }
                Services.shared.bookmarks.add(url: u.absoluteString, title: self.title ?? u.absoluteString)
                NotificationCenter.default.post(name: .bookmarksChanged, object: nil)
            },
            item("View Source") { [weak self] in self?.tab?.showSource() },
            item("Print…") { [weak self] in
                guard let self = self, let w = self.window else { return }
                self.printOperation(with: NSPrintInfo.shared).runModal(for: w, delegate: nil, didRun: nil, contextInfo: nil)
            },
        ]
        var insertAt = menu.items.count
        if let i = menu.items.firstIndex(where: {
            ($0.identifier?.rawValue ?? "").contains("InspectElement") || $0.title == "Inspect Element"
        }) { insertAt = i }
        if insertAt > 0, menu.items[insertAt - 1].isSeparatorItem { page.removeFirst() }
        for it in page { menu.insertItem(it, at: insertAt); insertAt += 1 }
    }

    private func openTab(_ url: URL, privateTab: Bool) {
        tab?.host?.openTab(configuration: nil, url: url, activate: true, isPrivate: privateTab)
    }

    private static func copy(_ s: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(s, forType: .string)
    }
}
