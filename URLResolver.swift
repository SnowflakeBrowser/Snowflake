import Foundation

public struct SearchEngine: Equatable {
    public let id: String
    public let name: String
    public let template: String      // %s is replaced by the encoded query
    public init(id: String, name: String, template: String) { self.id = id; self.name = name; self.template = template }
}

public enum SearchEngines {
    public static let all: [SearchEngine] = [
        SearchEngine(id: "duckduckgo", name: "DuckDuckGo", template: "https://duckduckgo.com/?q=%s"),
        SearchEngine(id: "brave", name: "Brave Search", template: "https://search.brave.com/search?q=%s"),
        SearchEngine(id: "startpage", name: "Startpage", template: "https://www.startpage.com/do/search?q=%s"),
        SearchEngine(id: "ecosia", name: "Ecosia", template: "https://www.ecosia.org/search?q=%s"),
        SearchEngine(id: "google", name: "Google", template: "https://www.google.com/search?q=%s"),
    ]
    public static func template(for id: String) -> String {
        (all.first { $0.id == id } ?? all[0]).template
    }
}

public enum URLResolver {
    public static let newTabURL = URL(string: "veil://newtab")!

    /// Turn whatever the user typed into a URL: explicit URL, bare host, or a search.
    public static func resolve(_ raw: String, searchTemplate: String) -> URL {
        let input = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if input.isEmpty { return newTabURL }
        if let u = explicitURL(input) { return u }
        if looksLikeHost(input) {
            let scheme = hostPart(of: input).map(isLocalHost) == true ? "http://" : "https://"
            if let u = URL(string: scheme + input) { return u }
        }
        return searchURL(for: input, template: searchTemplate)
    }

    static func explicitURL(_ s: String) -> URL? {
        let lower = s.lowercased()
        for prefix in ["http://", "https://", "file://", "veil://"] where lower.hasPrefix(prefix) {
            return URL(string: s)
        }
        if lower == "about:blank" { return URL(string: "about:blank") }
        return nil
    }

    public static func searchURL(for query: String, template: String) -> URL {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
        let encoded = query.addingPercentEncoding(withAllowedCharacters: allowed) ?? query
        return URL(string: template.replacingOccurrences(of: "%s", with: encoded)) ?? newTabURL
    }

    /// Host (no port, path, query) of something the user typed without a scheme.
    static func hostPart(of s: String) -> String? {
        var host = s
        if let i = host.firstIndex(where: { "/?#".contains($0) }) { host = String(host[..<i]) }
        if let at = host.lastIndex(of: "@") { host = String(host[host.index(after: at)...]) }
        if let colon = host.lastIndex(of: ":"), !host.hasSuffix("]") {
            let port = host[host.index(after: colon)...]
            if port.allSatisfy({ $0.isNumber }) { host = String(host[..<colon]) } else { return nil }
        }
        return host.isEmpty ? nil : host
    }

    static func looksLikeHost(_ s: String) -> Bool {
        if s.contains(where: { $0.isWhitespace }) { return false }
        guard let host = hostPart(of: s) else { return false }
        if host.lowercased() == "localhost" { return true }
        if isIPv4(host) { return true }
        guard host.contains("."), !host.hasPrefix("."), !host.hasSuffix(".") else { return false }
        let labels = host.split(separator: ".", omittingEmptySubsequences: false)
        guard let tld = labels.last, tld.count >= 2, tld.allSatisfy({ $0.isLetter }) else { return false }
        return host.allSatisfy { $0.isLetter || $0.isNumber || $0 == "." || $0 == "-" }
    }

    public static func isIPv4(_ host: String) -> Bool {
        let parts = host.split(separator: ".", omittingEmptySubsequences: false)
        return parts.count == 4 && parts.allSatisfy { p in
            if let n = Int(p) { return (0...255).contains(n) } else { return false }
        }
    }

    /// Hosts that should never be HTTPS-upgraded or treated as public sites.
    public static func isLocalHost(_ host: String) -> Bool {
        let h = host.lowercased()
        return h == "localhost" || h.hasSuffix(".local") || h.hasSuffix(".localhost")
            || isIPv4(h) || h.hasPrefix("[")
    }

    /// Short, clean text for the address bar when it is not being edited.
    public static func displayString(for url: URL) -> String {
        if url.scheme == "veil" { return url.host == "newtab" ? "" : "veil://" + (url.host ?? "") }
        var s = url.absoluteString
        for p in ["https://", "http://"] where s.hasPrefix(p) { s.removeFirst(p.count); break }
        if s.hasPrefix("www.") { s.removeFirst(4) }
        if s.hasSuffix("/") && s.filter({ $0 == "/" }).count == 1 { s.removeLast() }
        return s
    }
}
