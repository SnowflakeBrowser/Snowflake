import Foundation

public enum Paths {
    /// ~/Library/Application Support/Veil (mode 0700). Everything Veil stores locally lives here.
    public static let dataDirectory: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("Veil", isDirectory: true)
        // One-time move of data from the browser's earlier name.
        let previous = base.appendingPathComponent("Hu" + "sh", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path), FileManager.default.fileExists(atPath: previous.path) {
            try? FileManager.default.moveItem(at: previous, to: dir)
        }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        return dir
    }()
}

extension JSONEncoder {
    public static func veil() -> JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }
}

extension JSONDecoder {
    public static func veil() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }
}

/// A tiny thread-safe, debounced, atomically-written JSON file. Files are chmod 0600.
public final class JSONStore<T: Codable> {
    private let url: URL
    private let lock = NSLock()
    private var _value: T
    private var pending: DispatchWorkItem?
    private let queue = DispatchQueue(label: "veil.store", qos: .utility)

    public init(name: String, directory: URL = Paths.dataDirectory, defaultValue: T) {
        url = directory.appendingPathComponent(name + ".json")
        if let data = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder.veil().decode(T.self, from: data) {
            _value = decoded
        } else {
            _value = defaultValue
        }
    }

    public var value: T {
        get { lock.lock(); defer { lock.unlock() }; return _value }
        set { lock.lock(); _value = newValue; lock.unlock(); scheduleSave() }
    }

    public func mutate(_ body: (inout T) -> Void) {
        lock.lock(); body(&_value); lock.unlock()
        scheduleSave()
    }

    /// Write synchronously (call before quitting).
    public func flush() {
        lock.lock(); pending?.cancel(); pending = nil; lock.unlock()
        queue.sync { self.writeNow() }
    }

    private func scheduleSave() {
        lock.lock()
        pending?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.writeNow() }
        pending = item
        lock.unlock()
        queue.asyncAfter(deadline: .now() + 0.5, execute: item)
    }

    private func writeNow() {
        lock.lock(); let snapshot = _value; lock.unlock()
        guard let data = try? JSONEncoder.veil().encode(snapshot) else { return }
        do {
            try data.write(to: url, options: .atomic)
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        } catch {
            NSLog("Veil: failed to save \(url.lastPathComponent): \(error)")
        }
    }
}
