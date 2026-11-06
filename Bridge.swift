import AppKit
import WebKit
import VeilCore

/// Receives calls from veil:// pages only. Web pages can see the handler exist,
/// but every message from a non-veil main frame is rejected.
final class Bridge: NSObject, WKScriptMessageHandlerWithReply {
    static let shared = Bridge()

    func userContentController(_ ucc: WKUserContentController, didReceive message: WKScriptMessage,
                               replyHandler: @escaping (Any?, String?) -> Void) {
        let frame = message.frameInfo
        let fromVeil = frame.securityOrigin.protocol == "veil" || frame.request.url?.scheme == "veil"
        guard fromVeil, frame.isMainFrame,
              let body = message.body as? [String: Any], let cmd = body["cmd"] as? String else {
            replyHandler(nil, "denied"); return
        }
        let args = body["args"] as? [String: Any] ?? [:]
        handle(cmd, args, webView: message.webView) { result in
            let data = (try? JSONSerialization.data(withJSONObject: result, options: [.fragmentsAllowed])) ?? Data("null".utf8)
            replyHandler(String(data: data, encoding: .utf8), nil)
        }
    }

    private func object<T: Encodable>(_ v: T) -> Any {
        (try? JSONSerialization.jsonObject(with: JSONEncoder.veil().encode(v), options: [.fragmentsAllowed])) ?? [:]
    }

    private func cookieDomains(_ done: @escaping ([String: Int]) -> Void) {
        WKWebsiteDataStore.default().httpCookieStore.getAllCookies { cookies in
            var counts: [String: Int] = [:]
            for c in cookies {
                let d = c.domain.hasPrefix(".") ? String(c.domain.dropFirst()) : c.domain
                counts[d, default: 0] += 1
            }
            done(counts)
        }
    }

    private func handle(_ cmd: String, _ a: [String: Any], webView: WKWebView?, done: @escaping (Any) -> Void) {
        let S = Services.shared
        switch cmd {

        case "settings.get":
            let meta = S.blocker.meta.value
            done([
                "settings": object(S.settings),
                "engines": SearchEngines.all.map { ["id": $0.id, "name": $0.name] },
                "meta": object(meta),
                "sources": BlockerManager.sources.map { src -> [String: Any] in
                    ["id": src.id, "name": src.name, "blurb": src.blurb, "url": src.url?.absoluteString ?? "",
                     "enabled": S.blocker.isEnabled(src),
                     "updated": meta.updated[src.id]?.timeIntervalSince1970 ?? 0]
                },
            ])

        case "settings.set":
            guard let key = a["key"] as? String, let value = a["value"] else { done(false); return }
            var ok = false
            S.updateSettings { ok = $0.set(key: key, value: value) }
            if ok, key == "enabledLists" || key == "customRules" { S.blocker.rebuild() }
            if ok, key == "cookieMode" || key == "cookieExceptions" { S.blocker.recompileCookies() }
            done(ok)

        case "lists.update":
            S.blocker.downloadLists { updated, failed in done(["updated": updated, "failed": failed]) }

        case "navigate":
            if let text = a["text"] as? String, let w = webView {
                w.load(URLRequest(url: URLResolver.resolve(text, searchTemplate: SearchEngines.template(for: S.settings.searchEngine))))
            }
            done(true)

        case "history.list":
            done(S.history.search(a["q"] as? String ?? "").map {
                ["id": $0.id.uuidString, "url": $0.url, "title": $0.title, "date": $0.date.timeIntervalSince1970]
            })
        case "history.remove":
            if let s = a["id"] as? String, let id = UUID(uuidString: s) { S.history.remove(id: id) }
            done(true)
        case "history.clear":
            S.history.clear(); done(true)

        case "bookmarks.list":
            done(S.bookmarks.all.map { ["url": $0.url, "title": $0.title] })
        case "bookmarks.remove":
            if let u = a["url"] as? String { S.bookmarks.remove(url: u) }
            NotificationCenter.default.post(name: .bookmarksChanged, object: nil)
            done(true)

        case "background.get": done(S.startBackground.value)
        case "background.set":
            if let d = a["data"] as? String, d.hasPrefix("data:image/"), d.count < 6_000_000 { S.startBackground.value = d; done(true) } else { done(false) }
        case "background.clear": S.startBackground.value = ""; done(true)

        case "newtab.icons":
            var out: [String: String] = [:]
            for sc in S.settings.newTab.shortcuts {
                guard let host = URL(string: sc.url)?.host, let img = FaviconCache.shared.image(forHost: host),
                      let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
                      let png = rep.representation(using: .png, properties: [:]) else { continue }
                out[sc.url] = "data:image/png;base64," + png.base64EncodedString()
            }
            done(out)

        case "downloads.chooseFolder":
            let panel = NSOpenPanel()
            panel.canChooseDirectories = true
            panel.canChooseFiles = false
            panel.canCreateDirectories = true
            panel.prompt = "Choose"
            panel.begin { response in
                if response == .OK, let url = panel.url {
                    S.updateSettings { $0.downloadFolder = url.path }
                    done(url.path)
                } else {
                    done(S.settings.downloadFolder)
                }
            }

        case "downloads.list": done(S.downloads.list())
        case "downloads.reveal": S.downloads.reveal(id: a["id"] as? String ?? ""); done(true)
        case "downloads.open": S.downloads.open(id: a["id"] as? String ?? ""); done(true)
        case "downloads.clear": S.downloads.clearFinished(); done(true)

        case "allowlist.list": done(S.allowlist.all)
        case "allowlist.add":
            if let h = a["host"] as? String { S.allowlist.add(h) }
            S.notifyChanged(); done(true)
        case "allowlist.remove":
            if let h = a["host"] as? String { S.allowlist.remove(h) }
            S.notifyChanged(); done(true)

        case "permissions.list":
            var rows: [[String: Any]] = []
            for (host, kinds) in S.permissions.all.sorted(by: { $0.key < $1.key }) {
                for (kind, allowed) in kinds.sorted(by: { $0.key < $1.key }) {
                    rows.append(["host": host, "kind": kind, "allowed": allowed])
                }
            }
            done(rows)
        case "permissions.remove":
            if let h = a["host"] as? String, let k = a["kind"] as? String { S.permissions.remove(host: h, kind: k) }
            done(true)

        case "privacy.overview":
            let meta = S.blocker.meta.value
            cookieDomains { counts in
                done(["rules": meta.networkRules + meta.cosmeticRules, "cookieDomains": counts.count,
                      "history": S.history.count, "bookmarks": S.bookmarks.all.count])
            }

        case "cookies.list":
            cookieDomains { counts in
                done(counts.sorted { $0.key < $1.key }.map { ["domain": $0.key, "count": $0.value] })
            }
        case "cookies.clearDomain":
            let d = a["domain"] as? String ?? ""
            let store = WKWebsiteDataStore.default().httpCookieStore
            store.getAllCookies { cookies in
                let group = DispatchGroup()
                for c in cookies where c.domain == d || c.domain == "." + d {
                    group.enter(); store.delete(c) { group.leave() }
                }
                group.notify(queue: .main) { done(true) }
            }
        case "cookies.clearAll":
            WKWebsiteDataStore.default().removeData(ofTypes: [WKWebsiteDataTypeCookies],
                                                    modifiedSince: Date(timeIntervalSince1970: 0)) {
                try? FileManager.default.removeItem(at: S.cookies.fileURL)
                done(true)
            }
        case "siteData.clearAll":
            WKWebsiteDataStore.default().removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(),
                                                    modifiedSince: Date(timeIntervalSince1970: 0)) {
                try? FileManager.default.removeItem(at: S.cookies.fileURL)
                done(true)
            }

        default:
            done(NSNull())
        }
    }
}
