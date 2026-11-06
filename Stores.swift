import Foundation

public final class HistoryStore {
    private let store: JSONStore<[HistoryEntry]>
    public init(directory: URL = Paths.dataDirectory) {
        store = JSONStore(name: "history", directory: directory, defaultValue: [])
    }
    public var count: Int { store.value.count }

    public func add(url: String, title: String, date: Date = Date()) {
        store.mutate { list in
            if let last = list.last, last.url == url {
                if !title.isEmpty { list[list.count - 1].title = title }
                list[list.count - 1].date = date
                return
            }
            list.append(HistoryEntry(url: url, title: title.isEmpty ? url : title, date: date))
            if list.count > 20_000 { list.removeFirst(list.count - 20_000) }
        }
    }
    public func search(_ query: String, limit: Int = 500) -> [HistoryEntry] {
        let q = query.lowercased()
        var out: [HistoryEntry] = []
        for e in store.value.reversed() {
            if q.isEmpty || e.title.lowercased().contains(q) || e.url.lowercased().contains(q) {
                out.append(e)
                if out.count >= limit { break }
            }
        }
        return out
    }
    public func remove(id: UUID) { store.mutate { $0.removeAll { $0.id == id } } }
    public func clear() { store.value = [] }
    public func flush() { store.flush() }
}

public final class BookmarkStore {
    private let store: JSONStore<[Bookmark]>
    public init(directory: URL = Paths.dataDirectory) {
        store = JSONStore(name: "bookmarks", directory: directory, defaultValue: [])
    }
    public var all: [Bookmark] { store.value }
    public func contains(url: String) -> Bool { store.value.contains { $0.url == url } }
    public func add(url: String, title: String) {
        guard !contains(url: url) else { return }
        store.mutate { $0.insert(Bookmark(url: url, title: title.isEmpty ? url : title), at: 0) }
    }
    public func remove(url: String) { store.mutate { $0.removeAll { $0.url == url } } }
    public func flush() { store.flush() }
}

/// Sites for which blocking is turned off. Matches the host and all of its subdomains.
public final class AllowlistStore {
    private let store: JSONStore<[String]>
    public init(directory: URL = Paths.dataDirectory) {
        store = JSONStore(name: "allowlist", directory: directory, defaultValue: [])
    }
    public var all: [String] { store.value.sorted() }
    public static func normalize(_ host: String) -> String {
        var h = host.lowercased().trimmingCharacters(in: .whitespaces)
        if h.hasPrefix("www.") { h.removeFirst(4) }
        return h
    }
    public func contains(_ host: String) -> Bool {
        let h = AllowlistStore.normalize(host)
        return store.value.contains { h == $0 || h.hasSuffix("." + $0) }
    }
    public func add(_ host: String) {
        let h = AllowlistStore.normalize(host)
        guard !h.isEmpty else { return }
        store.mutate { if !$0.contains(h) { $0.append(h) } }
    }
    public func remove(_ host: String) {
        let h = AllowlistStore.normalize(host)
        store.mutate { $0.removeAll { $0 == h } }
    }
    public func flush() { store.flush() }
}

/// Remembered per-site permission decisions (camera, microphone).
public final class PermissionStore {
    private let store: JSONStore<[String: [String: Bool]]>
    public init(directory: URL = Paths.dataDirectory) {
        store = JSONStore(name: "permissions", directory: directory, defaultValue: [:])
    }
    public var all: [String: [String: Bool]] { store.value }
    public func get(host: String, kind: String) -> Bool? { store.value[host]?[kind] }
    public func set(host: String, kind: String, allowed: Bool) {
        store.mutate { $0[host, default: [:]][kind] = allowed }
    }
    public func remove(host: String, kind: String) {
        store.mutate {
            $0[host]?[kind] = nil
            if $0[host]?.isEmpty == true { $0[host] = nil }
        }
    }
    public func flush() { store.flush() }
}
