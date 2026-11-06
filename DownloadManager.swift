import AppKit
import WebKit
import VeilCore
import UniformTypeIdentifiers

extension Notification.Name {
    static let downloadsChanged = Notification.Name("VeilDownloadsChanged")
    static let downloadStarted = Notification.Name("VeilDownloadStarted")
    static let bookmarksChanged = Notification.Name("VeilBookmarksChanged")
}

final class DownloadManager: NSObject, WKDownloadDelegate {
    var hasActive: Bool { !live.isEmpty }
    private let records = JSONStore<[DownloadRecord]>(name: "downloads", defaultValue: [])
    private var live: [UUID: WKDownload] = [:]
    private var ids: [ObjectIdentifier: UUID] = [:]

    func flush() { records.flush() }

    func attach(_ download: WKDownload) {
        let id = UUID()
        download.delegate = self
        live[id] = download
        ids[ObjectIdentifier(download)] = id
        let source = download.originalRequest?.url?.absoluteString ?? ""
        let name = download.originalRequest?.url?.lastPathComponent ?? "download"
        records.mutate { $0.insert(DownloadRecord(id: id, name: name, source: source, path: "", state: "running"), at: 0) }
        NotificationCenter.default.post(name: .downloadsChanged, object: nil)
        NotificationCenter.default.post(name: .downloadStarted, object: nil)
    }

    /// Rows for the Downloads page, with live progress for running items.
    func list() -> [[String: Any]] {
        records.value.map { r in
            var row: [String: Any] = ["id": r.id.uuidString, "name": r.name, "source": r.source,
                                      "state": r.state, "date": r.date.timeIntervalSince1970, "path": r.path]
            if r.state == "running", let d = live[r.id] { row["progress"] = d.progress.fractionCompleted }
            return row
        }
    }

    func reveal(id: String) {
        guard let r = records.value.first(where: { $0.id.uuidString == id }), !r.path.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: r.path)])
    }
    func open(id: String) {
        guard let r = records.value.first(where: { $0.id.uuidString == id }), r.state == "done" else { return }
        NSWorkspace.shared.open(URL(fileURLWithPath: r.path))
    }
    func remove(id: String) { records.mutate { $0.removeAll { $0.id.uuidString == id && $0.state != "running" } } }
    func clearFinished() { records.mutate { $0.removeAll { $0.state != "running" } } }

    // MARK: WKDownloadDelegate

    /// Saves bytes we already have (for example an image embedded as a data: URL).
    func saveData(_ data: Data, suggestedName: String) {
        let dest = DownloadManager.uniqueURL(in: downloadsDirectory, name: suggestedName)
        do { try data.write(to: dest) } catch { return }
        records.mutate { $0.insert(DownloadRecord(name: dest.lastPathComponent, source: "Embedded in page", path: dest.path, state: "done"), at: 0) }
        NotificationCenter.default.post(name: .downloadsChanged, object: nil)
        NotificationCenter.default.post(name: .downloadStarted, object: nil)
    }

    var downloadsDirectory: URL {
        let custom = Services.shared.settings.downloadFolder
        if !custom.isEmpty, FileManager.default.fileExists(atPath: custom) { return URL(fileURLWithPath: custom, isDirectory: true) }
        return FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
    }

    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse,
                  suggestedFilename: String, completionHandler: @escaping (URL?) -> Void) {
        var name = DownloadManager.sanitize(suggestedFilename)
        // Images and other files often arrive without an extension; derive one from the content type.
        if (name as NSString).pathExtension.isEmpty, let mime = response.mimeType,
           let ext = UTType(mimeType: mime)?.preferredFilenameExtension {
            name += "." + ext
        }
        let complete: (URL?) -> Void = { [weak self] dest in
            guard let self = self else { completionHandler(nil); return }
            guard let dest = dest else {
                // User cancelled the save dialog.
                if let id = self.ids[ObjectIdentifier(download)] { self.records.mutate { $0.removeAll { $0.id == id } }; self.live[id] = nil }
                NotificationCenter.default.post(name: .downloadsChanged, object: nil)
                completionHandler(nil)
                return
            }
            if let id = self.ids[ObjectIdentifier(download)] {
                self.records.mutate { list in
                    if let i = list.firstIndex(where: { $0.id == id }) { list[i].name = dest.lastPathComponent; list[i].path = dest.path }
                }
            }
            if FileManager.default.fileExists(atPath: dest.path) { try? FileManager.default.removeItem(at: dest) }   // user confirmed overwrite
            completionHandler(dest)
        }
        if Services.shared.settings.askDownloadLocation {
            let panel = NSSavePanel()
            panel.nameFieldStringValue = name
            panel.directoryURL = downloadsDirectory
            panel.canCreateDirectories = true
            panel.begin { response in
                complete(response == .OK ? panel.url : nil)
            }
        } else {
            complete(DownloadManager.uniqueURL(in: downloadsDirectory, name: name))
        }
    }

    func downloadDidFinish(_ download: WKDownload) { finish(download, state: "done") }

    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        finish(download, state: "failed")
    }

    private func finish(_ download: WKDownload, state: String) {
        guard let id = ids.removeValue(forKey: ObjectIdentifier(download)) else { return }
        live[id] = nil
        records.mutate { list in
            if let i = list.firstIndex(where: { $0.id == id }) { list[i].state = state }
        }
        NotificationCenter.default.post(name: .downloadsChanged, object: nil)
        if state == "done", Services.shared.settings.downloadSound { NSSound(named: "Glass")?.play() }
    }

    static func sanitize(_ name: String) -> String {
        var n = name.replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: ":", with: "_")
        while n.hasPrefix(".") { n.removeFirst() }
        return n.isEmpty ? "download" : n
    }

    static func uniqueURL(in dir: URL, name: String) -> URL {
        var url = dir.appendingPathComponent(name)
        let base = url.deletingPathExtension().lastPathComponent, ext = url.pathExtension
        var n = 1
        while FileManager.default.fileExists(atPath: url.path) {
            url = dir.appendingPathComponent(ext.isEmpty ? "\(base) \(n)" : "\(base) \(n).\(ext)")
            n += 1
        }
        return url
    }
}
