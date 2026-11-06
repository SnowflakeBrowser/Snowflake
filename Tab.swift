import AppKit
import WebKit
import VeilCore
import UniformTypeIdentifiers

protocol TabHost: AnyObject {
    var window: NSWindow? { get }
    func tabDidChange(_ tab: Tab)
    @discardableResult
    func openTab(configuration: WKWebViewConfiguration?, url: URL?, activate: Bool, isPrivate: Bool) -> Tab
    func closeTab(_ tab: Tab)
}

/// Receives "something is playing" reports from pages without keeping the tab alive.
private final class MediaProxy: NSObject, WKScriptMessageHandler {
    weak var tab: Tab?
    init(tab: Tab) { self.tab = tab }
    func userContentController(_ ucc: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], let id = body["id"] as? String,
              let playing = body["playing"] as? Bool else { return }
        tab?.mediaReport(frame: id, playing: playing)
    }
}

/// One browser tab. The WKWebView is created lazily (restored/background tabs cost nothing)
/// and can be discarded when idle to give memory back.
final class Tab: NSObject, WKNavigationDelegate, WKUIDelegate {
    let id = UUID()
    weak var host: TabHost?
    private(set) var webView: WKWebView?
    var title: String
    var url: URL?
    var pendingURL: URL?
    var lastActive = Date()
    let isPrivate: Bool
    var favicon: NSImage?
    var isMuted = false
    var isPlayingMedia = false

    private var observers: [NSKeyValueObservation] = []
    private var blockingKey = ""
    private var upgradedFrom: URL?
    private lazy var mediaProxy = MediaProxy(tab: self)
    private var playingFrames = Set<String>()
    private static var httpFallbackHosts = Set<String>()

    /// A lazy tab: no web view until first selected.
    init(host: TabHost, url: URL?, title: String = "New Tab", isPrivate: Bool = false) {
        self.host = host; self.pendingURL = url; self.url = url; self.title = title
        self.isPrivate = isPrivate
        super.init()
        if !isPrivate { favicon = FaviconCache.shared.image(forHost: url?.host) }
    }

    /// A tab created by `window.open` / target=_blank; must use the configuration WebKit supplies
    /// so OAuth popups keep `window.opener` and sign-in flows work.
    init(host: TabHost, configuration: WKWebViewConfiguration, isPrivate: Bool) {
        self.host = host; self.title = "New Tab"
        self.isPrivate = isPrivate
        super.init()
        // store: nil -> keep the opener's data store (so private popups stay private).
        let w = VeilWebView(frame: .zero, configuration: Services.shared.prepare(configuration, store: nil))
        attach(w)
    }

    var isLoaded: Bool { webView != nil }
    var isLoading: Bool { webView?.isLoading ?? false }

    @discardableResult
    func ensureWebView() -> WKWebView {
        if let w = webView { return w }
        let w = VeilWebView(frame: .zero, configuration: Services.shared.makeConfiguration(isPrivate: isPrivate))
        attach(w)
        if let u = pendingURL { pendingURL = nil; load(u) }
        return w
    }

    private func attach(_ w: WKWebView) {
        webView = w
        (w as? VeilWebView)?.tab = self
        installMediaHandler()
        applyBrowsingSettings(w)
        w.navigationDelegate = self
        w.uiDelegate = self
        w.allowsBackForwardNavigationGestures = true
        w.allowsMagnification = true
        w.underPageBackgroundColor = Theme.pageBackdrop
        let notify: () -> Void = { [weak self] in
            guard let self = self else { return }
            self.host?.tabDidChange(self)
        }
        observers = [
            w.observe(\.title) { [weak self] w, _ in
                if let t = w.title, !t.isEmpty { self?.title = t }
                notify()
            },
            w.observe(\.url) { [weak self] w, _ in
                if let u = w.url { self?.url = u }
                notify()
            },
            w.observe(\.isLoading) { _, _ in notify() },
            w.observe(\.estimatedProgress) { _, _ in notify() },
            w.observe(\.canGoBack) { _, _ in notify() },
            w.observe(\.canGoForward) { _, _ in notify() },
        ]
    }

    func load(_ url: URL) {
        self.url = url
        guard let w = webView else { pendingURL = url; return }
        updateBlocking(for: url.host)
        if url.isFileURL {
            w.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent()); return
        }
        if url.scheme == "veil" || url.scheme == "about" { w.load(URLRequest(url: url)); return }
        Services.shared.blocker.whenReady { [weak self] in
            guard let self = self, let w = self.webView else { return }
            self.updateBlocking(for: url.host)
            w.load(URLRequest(url: url))
        }
    }

    func updateBlocking(for host: String?) {
        guard let ucc = webView?.configuration.userContentController else { return }
        let (key, lists) = Services.shared.blocker.state(forHost: host)
        if key == blockingKey { return }
        blockingKey = key
        ucc.removeAllContentRuleLists()
        lists.forEach { ucc.add($0) }
    }

    /// Called when settings, lists or the allowlist change.
    func refreshConfiguration() {
        blockingKey = ""
        if let ucc = webView?.configuration.userContentController { Services.shared.configure(ucc, muted: isMuted) }
        if let w = webView { applyBrowsingSettings(w) }
        // Update the page that is already open too, so tints and filters switch on AND off right away.
        if let w = webView, let scheme = w.url?.scheme, scheme == "http" || scheme == "https" {
            w.evaluateJavaScript("document.querySelectorAll('[data-veil-fun]').forEach(function(e){e.remove()});document.querySelectorAll('div').forEach(function(d){var c=d.style&&d.style.cssText||'';if(c.indexOf('2147483647')>=0&&c.indexOf('mix-blend-mode')>=0)d.remove()});window.__veilFun=false;", completionHandler: nil)
            if let fun = FunPage.script(for: Services.shared.settings) { w.evaluateJavaScript(fun, completionHandler: nil) }
        }
        updateBlocking(for: webView?.url?.host)
    }

    // MARK: Sound

    /// Mutes or unmutes every <video>/<audio> in the page, and keeps it muted across navigations.
    func setMuted(_ muted: Bool) {
        isMuted = muted
        if let ucc = webView?.configuration.userContentController { Services.shared.configure(ucc, muted: muted) }
        webView?.evaluateJavaScript("window.__veilSetMuted && window.__veilSetMuted(\(muted ? "true" : "false"))",
                                    completionHandler: nil)
        host?.tabDidChange(self)
    }

    /// Settings that apply to a live web view.
    private func applyBrowsingSettings(_ w: WKWebView) {
        let settings = Services.shared.settings
        if #available(macOS 13.3, *) { w.isInspectable = settings.developerTools }
        w.configuration.preferences.setValue(settings.developerTools, forKey: "developerExtrasEnabled")
        if w.pageZoom == 1 { w.pageZoom = CGFloat(settings.defaultZoom) / 100 }
    }

    // MARK: Downloading things the page shows (images, videos, linked files)

    func downloadURL(_ url: URL) {
        if url.scheme == "data" { saveDataURL(url); return }
        guard let w = webView else { return }
        w.startDownload(using: URLRequest(url: url)) { download in
            Services.shared.downloads.attach(download)
        }
    }

    private func saveDataURL(_ url: URL) {
        let s = url.absoluteString
        guard s.count > 5, let comma = s.firstIndex(of: ",") else { return }
        let meta = String(s[s.index(s.startIndex, offsetBy: 5)..<comma])
        let payload = String(s[s.index(after: comma)...])
        let data: Data? = meta.contains(";base64") ? Data(base64Encoded: payload) : payload.removingPercentEncoding?.data(using: .utf8)
        guard let bytes = data else { return }
        let mime = meta.split(separator: ";").first.map(String.init) ?? "application/octet-stream"
        let ext = UTType(mimeType: mime)?.preferredFilenameExtension ?? "bin"
        Services.shared.downloads.saveData(bytes, suggestedName: "image." + ext)
    }

    /// Opens the page's current HTML in a new tab.
    func showSource() {
        webView?.evaluateJavaScript("document.documentElement.outerHTML") { [weak self] result, _ in
            guard let self = self, let html = result as? String else { return }
            let t = self.host?.openTab(configuration: nil, url: URL(string: "about:blank"), activate: true, isPrivate: self.isPrivate)
            t?.webView?.loadHTMLString(Pages.sourceHTML(url: self.url?.absoluteString ?? "", source: html),
                                       baseURL: URL(string: "veil://source"))
        }
    }

    private func installMediaHandler() {
        guard let ucc = webView?.configuration.userContentController else { return }
        ucc.removeScriptMessageHandler(forName: "veilMedia", contentWorld: .page)
        ucc.add(mediaProxy, contentWorld: .page, name: "veilMedia")
    }

    func mediaReport(frame: String, playing: Bool) {
        if playing { playingFrames.insert(frame) } else { playingFrames.remove(frame) }
        let now = !playingFrames.isEmpty
        if now != isPlayingMedia { isPlayingMedia = now; host?.tabDidChange(self) }
    }

    private func refreshFavicon(_ w: WKWebView) {
        FaviconCache.shared.fetch(for: w, isPrivate: isPrivate) { [weak self] image in
            guard let self = self, let image = image else { return }
            self.favicon = image
            self.host?.tabDidChange(self)
        }
    }

    func shutdown() {
        playingFrames.removeAll()
        isPlayingMedia = false
        webView?.stopLoading()
        observers.removeAll()
        webView?.navigationDelegate = nil
        webView?.uiDelegate = nil
        webView?.removeFromSuperview()
        webView = nil
    }

    /// Free the web process memory; the tab reloads when selected again.
    func discard() {
        let keep = webView?.url ?? url
        shutdown()
        pendingURL = keep
        blockingKey = ""
    }

    // MARK: - WKNavigationDelegate

    /// Links to other apps (ssh:, smb:, vnc: ...) ask first; mail and phone links open directly.
    private func confirmOpenExternally(_ url: URL) {
        let scheme = url.scheme?.lowercased() ?? ""
        if ["mailto", "tel", "sms", "facetime"].contains(scheme) { NSWorkspace.shared.open(url); return }
        let alert = NSAlert()
        alert.messageText = "Open this link in another app?"
        alert.informativeText = String(url.absoluteString.prefix(200))
        alert.addButton(withTitle: "Open")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn { NSWorkspace.shared.open(url) }
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 preferences: WKWebpagePreferences,
                 decisionHandler: @escaping (WKNavigationActionPolicy, WKWebpagePreferences) -> Void) {
        if navigationAction.shouldPerformDownload { decisionHandler(.download, preferences); return }
        guard let url = navigationAction.request.url else { decisionHandler(.cancel, preferences); return }
        let scheme = url.scheme?.lowercased() ?? ""

        // "Load over HTTP anyway" button on the upgrade-failed page.
        if scheme == "veil", url.host == "insecure",
           let q = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "u" })?.value,
           let target = URL(string: q), target.scheme == "http", let host = target.host {
            Tab.httpFallbackHosts.insert(host)
            decisionHandler(.cancel, preferences)
            load(target)
            return
        }

        if !["http", "https", "veil", "about", "blob", "data", "file"].contains(scheme) {
            if navigationAction.navigationType == .linkActivated { confirmOpenExternally(url) }
            decisionHandler(.cancel, preferences)
            return
        }

        if navigationAction.navigationType == .linkActivated, ["http", "https"].contains(scheme),
           navigationAction.modifierFlags.contains(.command) || navigationAction.buttonNumber == 4 {
            host?.openTab(configuration: nil, url: url, activate: navigationAction.modifierFlags.contains(.shift), isPrivate: isPrivate)
            decisionHandler(.cancel, preferences)
            return
        }

        // Strip tracking junk (utm_*, fbclid, gclid...) from addresses before anything is loaded.
        if navigationAction.targetFrame?.isMainFrame == true, scheme == "http" || scheme == "https",
           (navigationAction.request.httpMethod ?? "GET") == "GET", Services.shared.settings.stripTracking,
           let cleaned = TrackingParams.cleaned(url) {
            decisionHandler(.cancel, preferences)
            load(cleaned)
            return
        }

        if navigationAction.targetFrame?.isMainFrame == true {
            if scheme == "http", Services.shared.settings.httpsUpgrade, let host = url.host,
               !Tab.httpFallbackHosts.contains(host), !URLResolver.isLocalHost(host),
               var c = URLComponents(url: url, resolvingAgainstBaseURL: false) {
                c.scheme = "https"
                if let https = c.url {
                    upgradedFrom = url
                    decisionHandler(.cancel, preferences)
                    load(https)
                    return
                }
            }
            updateBlocking(for: url.host)
        }
        decisionHandler(.allow, preferences)
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse,
                 decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        let disposition = (navigationResponse.response as? HTTPURLResponse)?
            .value(forHTTPHeaderField: "Content-Disposition")?.lowercased() ?? ""
        decisionHandler(navigationResponse.canShowMIMEType && !disposition.hasPrefix("attachment") ? .allow : .download)
    }

    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
        Services.shared.downloads.attach(download)
    }
    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
        Services.shared.downloads.attach(download)
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        upgradedFrom = nil
        playingFrames.removeAll()
        isPlayingMedia = false
        host?.tabDidChange(self)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        if let u = webView.url, ["http", "https"].contains(u.scheme ?? "") {
            if !isPrivate { Services.shared.history.add(url: u.absoluteString, title: webView.title ?? "") }
            refreshFavicon(webView)
        } else {
            favicon = nil
        }
        if isMuted {
            webView.evaluateJavaScript("window.__veilSetMuted && window.__veilSetMuted(true)", completionHandler: nil)
        }
        host?.tabDidChange(self)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        handleFailure(webView, error)
    }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        handleFailure(webView, error)
    }

    private func handleFailure(_ webView: WKWebView, _ error: Error) {
        let ns = error as NSError
        if ns.code == NSURLErrorCancelled || ns.domain == "WebKitErrorDomain" && ns.code == 102 { return }
        let failing = (ns.userInfo[NSURLErrorFailingURLErrorKey] as? URL)?.absoluteString ?? ""
        if let orig = upgradedFrom {
            upgradedFrom = nil
            webView.loadHTMLString(Pages.errorHTML(heading: "This site doesn’t support a secure connection",
                                                   detail: "Veil tried https:// first and it failed. You can continue over unencrypted http, but anyone on your network could read or change what you send.",
                                                   failingURL: orig.absoluteString, insecureURL: orig.absoluteString),
                                   baseURL: URL(string: "veil://error"))
            return
        }
        webView.loadHTMLString(Pages.errorHTML(heading: "Can’t open this page", detail: ns.localizedDescription,
                                               failingURL: failing, insecureURL: nil),
                               baseURL: URL(string: "veil://error"))
    }

    // MARK: - WKUIDelegate

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        host?.openTab(configuration: configuration, url: nil, activate: true, isPrivate: isPrivate).webView
    }

    func webViewDidClose(_ webView: WKWebView) { host?.closeTab(self) }

    private func present(_ alert: NSAlert, _ done: @escaping (NSApplication.ModalResponse) -> Void) {
        if let w = host?.window { alert.beginSheetModal(for: w, completionHandler: done) }
        else { done(alert.runModal()) }
    }

    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        let a = NSAlert()
        a.messageText = frame.request.url?.host ?? "This page says"
        a.informativeText = message
        a.addButton(withTitle: "OK")
        present(a) { _ in completionHandler() }
    }

    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        let a = NSAlert()
        a.messageText = frame.request.url?.host ?? "This page asks"
        a.informativeText = message
        a.addButton(withTitle: "OK"); a.addButton(withTitle: "Cancel")
        present(a) { completionHandler($0 == .alertFirstButtonReturn) }
    }

    func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String, defaultText: String?,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (String?) -> Void) {
        let a = NSAlert()
        a.messageText = frame.request.url?.host ?? "This page asks"
        a.informativeText = prompt
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.stringValue = defaultText ?? ""
        a.accessoryView = field
        a.addButton(withTitle: "OK"); a.addButton(withTitle: "Cancel")
        present(a) { completionHandler($0 == .alertFirstButtonReturn ? field.stringValue : nil) }
    }

    func webView(_ webView: WKWebView, runOpenPanelWith parameters: WKOpenPanelParameters,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping ([URL]?) -> Void) {
        let p = NSOpenPanel()
        p.allowsMultipleSelection = parameters.allowsMultipleSelection
        p.canChooseDirectories = parameters.allowsDirectories
        if let w = host?.window { p.beginSheetModal(for: w) { completionHandler($0 == .OK ? p.urls : nil) } }
        else { completionHandler(p.runModal() == .OK ? p.urls : nil) }
    }

    func webView(_ webView: WKWebView, requestMediaCapturePermissionFor origin: WKSecurityOrigin,
                 initiatedByFrame frame: WKFrameInfo, type: WKMediaCaptureType,
                 decisionHandler: @escaping (WKPermissionDecision) -> Void) {
        if Services.shared.settings.denyMedia { decisionHandler(.deny); return }
        let hostName = origin.host
        let kinds: [String]
        switch type {
        case .camera: kinds = ["camera"]
        case .microphone: kinds = ["microphone"]
        default: kinds = ["camera", "microphone"]
        }
        let store = Services.shared.permissions
        let saved = kinds.compactMap { store.get(host: hostName, kind: $0) }
        if saved.count == kinds.count { decisionHandler(saved.allSatisfy { $0 } ? .grant : .deny); return }

        let a = NSAlert()
        a.messageText = "\(hostName) wants to use your \(kinds.joined(separator: " and "))"
        a.addButton(withTitle: "Allow"); a.addButton(withTitle: "Don’t Allow")
        a.showsSuppressionButton = true
        a.suppressionButton?.title = "Remember for this site"
        present(a) { response in
            let allowed = response == .alertFirstButtonReturn
            if a.suppressionButton?.state == .on { kinds.forEach { store.set(host: hostName, kind: $0, allowed: allowed) } }
            decisionHandler(allowed ? .grant : .deny)
        }
    }
}
