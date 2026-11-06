import Foundation
import WebKit
import VeilCore

/// WebKit keeps cookies that have an expiry date across restarts, but DROPS "session" cookies
/// (no expiry) when the app quits. Some sites sign you in with session cookies, so on quit we save
/// them locally (file mode 0600) and put them back, with a 30-day expiry, on the next launch.
/// Controlled by Settings > "Keep me signed in across restarts". Nothing leaves this Mac.
final class CookieKeeper {
    private struct Stored: Codable {
        var name, value, domain, path: String
        var secure, httpOnly: Bool
        var sameSite: String?
    }

    let fileURL = Paths.dataDirectory.appendingPathComponent("session-cookies.json")
    private var store: WKHTTPCookieStore { WKWebsiteDataStore.default().httpCookieStore }

    func saveSessionCookies(completion: @escaping () -> Void) {
        guard Services.shared.settings.keepSessionCookies else {
            try? FileManager.default.removeItem(at: fileURL)
            completion(); return
        }
        store.getAllCookies { cookies in
            let stored = cookies.filter { $0.isSessionOnly }.map {
                Stored(name: $0.name, value: $0.value, domain: $0.domain, path: $0.path,
                       secure: $0.isSecure, httpOnly: $0.isHTTPOnly, sameSite: $0.sameSitePolicy?.rawValue)
            }
            if let data = try? JSONEncoder().encode(stored) {
                try? data.write(to: self.fileURL, options: .atomic)
                try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: self.fileURL.path)
            }
            completion()
        }
    }

    func restore(completion: @escaping () -> Void) {
        guard Services.shared.settings.keepSessionCookies,
              let data = try? Data(contentsOf: fileURL),
              let stored = try? JSONDecoder().decode([Stored].self, from: data), !stored.isEmpty else {
            completion(); return
        }
        let expiry = Date().addingTimeInterval(30 * 86_400)
        let group = DispatchGroup()
        for s in stored {
            var props: [HTTPCookiePropertyKey: Any] = [
                .name: s.name, .value: s.value, .domain: s.domain, .path: s.path, .expires: expiry,
            ]
            if s.secure { props[.secure] = "TRUE" }
            if s.httpOnly { props[HTTPCookiePropertyKey("HttpOnly")] = "TRUE" }
            if let ss = s.sameSite { props[.sameSitePolicy] = ss }
            guard let cookie = HTTPCookie(properties: props) else { continue }
            group.enter()
            store.setCookie(cookie) { group.leave() }
        }
        group.notify(queue: .main) { completion() }
    }
}
