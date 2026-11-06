import AppKit
import WebKit
import VeilCore

/// Site icons for tabs and bookmarks. The page is asked which icon it uses, the icon is downloaded
/// directly from that same site (ephemeral session: no cookies), shrunk, and kept on this Mac.
/// Private tabs never write icons to disk.
final class FaviconCache {
    static let shared = FaviconCache()

    private var memory: [String: NSImage] = [:]
    private var missing = Set<String>()
    private let session = URLSession(configuration: .ephemeral)
    private let dir: URL = {
        let d = Paths.dataDirectory.appendingPathComponent("favicons", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }()

    private static let iconScript = #"""
    (() => {
      const links = [...document.querySelectorAll('link[rel~="icon"], link[rel="shortcut icon"], link[rel="apple-touch-icon"]')];
      const ok = links.map(l => l.href).filter(h => h && !/\.svg(\?|$)/i.test(h) && !h.startsWith('data:'));
      return ok[0] || (location.origin + '/favicon.ico');
    })()
    """#

    private func fileURL(_ host: String) -> URL {
        let safe = host.lowercased().filter { $0.isLetter || $0.isNumber || $0 == "." || $0 == "-" }
        return dir.appendingPathComponent(safe + ".png")
    }

    func image(forHost host: String?) -> NSImage? {
        guard let host = host, !host.isEmpty else { return nil }
        if let m = memory[host] { return m }
        if missing.contains(host) { return nil }
        if let img = NSImage(contentsOf: fileURL(host)) { memory[host] = img; return img }
        missing.insert(host)
        return nil
    }

    func fetch(for webView: WKWebView, isPrivate: Bool, completion: @escaping (NSImage?) -> Void) {
        guard let pageURL = webView.url, let host = pageURL.host,
              ["http", "https"].contains(pageURL.scheme ?? "") else { completion(nil); return }
        webView.evaluateJavaScript(FaviconCache.iconScript) { [weak self] result, _ in
            guard let self = self, let s = result as? String, let iconURL = URL(string: s),
                  self.isAllowed(iconURL, pageHost: host) else { completion(nil); return }
            var req = URLRequest(url: iconURL)
            req.timeoutInterval = 8
            self.session.dataTask(with: req) { data, resp, _ in
                guard let data = data, data.count < 600_000,
                      (resp as? HTTPURLResponse)?.statusCode == 200,
                      let img = NSImage(data: data), img.isValid else {
                    DispatchQueue.main.async { completion(nil) }
                    return
                }
                DispatchQueue.main.async {
                    let small = FaviconCache.resized(img, to: 32)
                    if !isPrivate {
                        self.memory[host] = small
                        self.missing.remove(host)
                        self.save(small, host: host)
                    }
                    completion(small)
                }
            }.resume()
        }
    }

    /// Only https icons (or http from the same site), and never from local-network addresses.
    private func isAllowed(_ url: URL, pageHost: String) -> Bool {
        guard let scheme = url.scheme, ["http", "https"].contains(scheme), let h = url.host else { return false }
        if h == pageHost { return true }
        return scheme == "https" && !URLResolver.isLocalHost(h)
    }

    private func save(_ img: NSImage, host: String) {
        guard let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: fileURL(host), options: .atomic)
    }

    static func resized(_ img: NSImage, to side: CGFloat) -> NSImage {
        let out = NSImage(size: NSSize(width: side, height: side))
        out.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        img.draw(in: NSRect(x: 0, y: 0, width: side, height: side), from: .zero, operation: .copy, fraction: 1)
        out.unlockFocus()
        return out
    }
}
