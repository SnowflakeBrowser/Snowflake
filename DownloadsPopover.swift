import AppKit
import ImageIO
import VeilCore

/// One row in the downloads panel. Finished files can be DRAGGED out of the row into a web page
/// (upload boxes, drop zones), onto the desktop, or into Finder or any other app.
final class DownloadRowView: ChromeView, NSDraggingSource {
    var onReveal: (() -> Void)?
    var onRemove: (() -> Void)?
    var onDragStart: (() -> Void)?
    var onDragEnd: (() -> Void)?

    private let fileURL: URL?
    private let isDone: Bool
    private let thumb = NSImageView()
    private let revealButton: NSButton
    private let removeButton: NSButton
    private var downEvent: NSEvent?
    private var tracking: NSTrackingArea?

    init(row: [String: Any]) {
        let state = row["state"] as? String ?? ""
        let path = row["path"] as? String ?? ""
        let url: URL? = path.isEmpty ? nil : URL(fileURLWithPath: path)
        let exists = !path.isEmpty && FileManager.default.fileExists(atPath: path)
        isDone = state == "done" && exists
        fileURL = url
        revealButton = symbolButton("magnifyingglass", tip: "Show in Finder", target: nil, action: #selector(DownloadRowView.revealTapped))
        removeButton = symbolButton("xmark", tip: "Remove from list", target: nil, action: #selector(DownloadRowView.removeTapped))
        super.init(frame: .zero)
        revealButton.target = self
        removeButton.target = self
        translatesAutoresizingMaskIntoConstraints = false
        radius = 10
        heightAnchor.constraint(equalToConstant: 60).isActive = true

        thumb.translatesAutoresizingMaskIntoConstraints = false
        thumb.imageScaling = .scaleProportionallyUpOrDown
        thumb.wantsLayer = true
        thumb.layer?.cornerRadius = 6
        thumb.layer?.masksToBounds = true
        if let u = url, isDone {
            thumb.image = DownloadRowView.thumbnail(for: u, side: 40) ?? NSWorkspace.shared.icon(forFile: u.path)
        } else {
            thumb.image = NSImage(systemSymbolName: state == "failed" ? "exclamationmark.triangle" : "arrow.down.circle",
                                  accessibilityDescription: nil)
            thumb.contentTintColor = .secondaryLabelColor
        }
        addSubview(thumb)

        let name = NSTextField(labelWithString: row["name"] as? String ?? "Download")
        name.font = .systemFont(ofSize: 13, weight: .medium)
        name.lineBreakMode = .byTruncatingMiddle
        name.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let status = NSTextField(labelWithString: "")
        status.font = .systemFont(ofSize: 11.5)
        status.textColor = .secondaryLabelColor
        switch state {
        case "done":
            if exists, let size = (try? FileManager.default.attributesOfItem(atPath: path))?[.size] as? NSNumber {
                status.stringValue = "Done · " + ByteCountFormatter.string(fromByteCount: size.int64Value, countStyle: .file)
            } else {
                status.stringValue = "File was moved or deleted"
            }
        case "failed": status.stringValue = "Failed"
        default: status.stringValue = "Downloading… \(Int(((row["progress"] as? Double) ?? 0) * 100))%"
        }

        let text = NSStackView(views: [name, status])
        text.translatesAutoresizingMaskIntoConstraints = false
        text.orientation = .vertical
        text.alignment = .leading
        text.spacing = 2
        if state == "running" {
            let bar = NSProgressIndicator()
            bar.style = .bar
            bar.isIndeterminate = false
            bar.minValue = 0
            bar.maxValue = 1
            bar.doubleValue = (row["progress"] as? Double) ?? 0
            bar.controlSize = .small
            bar.translatesAutoresizingMaskIntoConstraints = false
            text.addArrangedSubview(bar)
            bar.widthAnchor.constraint(equalToConstant: 170).isActive = true
        }
        addSubview(text)

        revealButton.isHidden = url == nil || !exists
        addSubview(revealButton)
        addSubview(removeButton)
        removeButton.isEnabled = state != "running"
        toolTip = isDone ? "Drag into a page, onto the desktop, or into any app" : nil

        NSLayoutConstraint.activate([
            thumb.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            thumb.centerYAnchor.constraint(equalTo: centerYAnchor),
            thumb.widthAnchor.constraint(equalToConstant: 40),
            thumb.heightAnchor.constraint(equalToConstant: 40),
            text.leadingAnchor.constraint(equalTo: thumb.trailingAnchor, constant: 10),
            text.trailingAnchor.constraint(lessThanOrEqualTo: revealButton.leadingAnchor, constant: -6),
            text.centerYAnchor.constraint(equalTo: centerYAnchor),
            removeButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            removeButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            revealButton.trailingAnchor.constraint(equalTo: removeButton.leadingAnchor, constant: -2),
            revealButton.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }

    @objc private func revealTapped() { onReveal?() }
    @objc private func removeTapped() { onRemove?() }

    /// Fast thumbnail without loading a full-size image into memory.
    static func thumbnail(for url: URL, side: CGFloat) -> NSImage? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: side * 2,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { return nil }
        return NSImage(cgImage: cg, size: .zero)
    }

    // MARK: Mouse + dragging

    override func hitTest(_ point: NSPoint) -> NSView? {
        let v = super.hitTest(point)
        if v === revealButton || v === removeButton { return v }
        return v == nil ? nil : self
    }

    override func mouseDown(with event: NSEvent) {
        downEvent = event
        if event.clickCount == 2, isDone, let u = fileURL { NSWorkspace.shared.open(u) }
    }

    override func mouseDragged(with event: NSEvent) {
        guard isDone, let url = fileURL, let start = downEvent,
              hypot(event.locationInWindow.x - start.locationInWindow.x,
                    event.locationInWindow.y - start.locationInWindow.y) > 4 else { return }
        downEvent = nil
        let item = NSDraggingItem(pasteboardWriter: url as NSURL)
        let image = thumb.image ?? NSWorkspace.shared.icon(forFile: url.path)
        item.setDraggingFrame(thumb.convert(thumb.bounds, to: self), contents: image)
        onDragStart?()
        beginDraggingSession(with: [item], event: start, source: self)
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        [.copy, .generic]
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        onDragEnd?()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = tracking { removeTrackingArea(t) }
        let t = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self, userInfo: nil)
        addTrackingArea(t); tracking = t
    }
    override func mouseEntered(with event: NSEvent) { fill = Theme.tabHover }
    override func mouseExited(with event: NSEvent) { fill = .clear }
}

/// The downloads panel that drops down from the toolbar button.
final class DownloadsPopover: NSObject, NSPopoverDelegate {
    var onShowAll: (() -> Void)?

    private let popover = NSPopover()
    private let container = NSView(frame: NSRect(x: 0, y: 0, width: 372, height: 300))
    private let stack = NSStackView()
    private let scroll = NSScrollView()
    private let emptyLabel = NSTextField(labelWithString: "No downloads yet")
    private let width: CGFloat = 372
    private var timer: Timer?
    private var monitor: Any?
    private var lastSignature = ""
    private var isDragging = false
    private var closedAt = Date.distantPast

    override init() {
        super.init()
        build()
    }

    var isShown: Bool { popover.isShown }

    private func build() {
        let title = NSTextField(labelWithString: "Downloads")
        title.font = .systemFont(ofSize: 14, weight: .semibold)
        title.translatesAutoresizingMaskIntoConstraints = false

        let all = NSButton(title: "All", target: self, action: #selector(allTapped))
        let clear = NSButton(title: "Clear", target: self, action: #selector(clearTapped))
        for b in [all, clear] {
            b.isBordered = false
            b.font = .systemFont(ofSize: 12)
            b.contentTintColor = Theme.accent
            b.translatesAutoresizingMaskIntoConstraints = false
        }
        let folder = symbolButton("folder", tip: "Open Downloads folder", target: self, action: #selector(folderTapped))

        let header = NSView()
        header.translatesAutoresizingMaskIntoConstraints = false
        [title, all, clear, folder].forEach { header.addSubview($0) }

        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 2
        stack.edgeInsets = NSEdgeInsets(top: 4, left: 8, bottom: 10, right: 8)
        stack.translatesAutoresizingMaskIntoConstraints = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.documentView = stack

        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        emptyLabel.textColor = .tertiaryLabelColor
        emptyLabel.font = .systemFont(ofSize: 13)

        container.addSubview(header)
        container.addSubview(scroll)
        container.addSubview(emptyLabel)
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: container.topAnchor),
            header.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            header.heightAnchor.constraint(equalToConstant: 42),
            title.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 16),
            title.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            clear.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -12),
            clear.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            all.trailingAnchor.constraint(equalTo: clear.leadingAnchor, constant: -6),
            all.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            folder.trailingAnchor.constraint(equalTo: all.leadingAnchor, constant: -2),
            folder.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            scroll.topAnchor.constraint(equalTo: header.bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            stack.topAnchor.constraint(equalTo: scroll.contentView.topAnchor),
            stack.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: scroll.contentView.trailingAnchor),
            emptyLabel.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: container.centerYAnchor, constant: -10),
        ])

        let vc = NSViewController()
        vc.view = container
        popover.contentViewController = vc
        popover.behavior = .applicationDefined     // stays open while you drag a file out of it
        popover.animates = true
        popover.delegate = self
    }

    // MARK: Show / hide

    func toggle(relativeTo view: NSView) {
        if popover.isShown { close() }
        else if Date().timeIntervalSince(closedAt) > 0.3 { show(relativeTo: view) }
    }

    func show(relativeTo view: NSView) {
        guard !popover.isShown, view.window != nil else { return }
        rebuild(force: true)
        popover.show(relativeTo: view.bounds, of: view, preferredEdge: .minY)
        timer = Timer.scheduledTimer(withTimeInterval: 0.6, repeats: true) { [weak self] _ in self?.rebuild() }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown]) { [weak self] e in
            guard let self = self, self.popover.isShown else { return e }
            if e.type == .keyDown {
                if e.keyCode == 53 { self.close(); return nil }      // Escape
                return e
            }
            if e.window !== self.popover.contentViewController?.view.window { self.close() }   // click outside
            return e
        }
    }

    func close() {
        closedAt = Date()
        popover.performClose(nil)
    }

    func popoverDidClose(_ notification: Notification) {
        timer?.invalidate(); timer = nil
        if let m = monitor { NSEvent.removeMonitor(m); monitor = nil }
        isDragging = false
    }

    // MARK: Content

    private func rebuild(force: Bool = false) {
        guard !isDragging else { return }
        let rows = Array(Services.shared.downloads.list().prefix(40))
        let sig = rows.map { "\($0["id"] ?? "")\($0["state"] ?? "")\(Int((($0["progress"] as? Double) ?? 0) * 100))\($0["name"] ?? "")" }
            .joined(separator: "|")
        if !force && sig == lastSignature { return }
        lastSignature = sig

        for v in stack.arrangedSubviews { stack.removeArrangedSubview(v); v.removeFromSuperview() }
        for r in rows {
            let id = r["id"] as? String ?? ""
            let row = DownloadRowView(row: r)
            row.onReveal = { Services.shared.downloads.reveal(id: id) }
            row.onRemove = { [weak self] in
                Services.shared.downloads.remove(id: id)
                self?.rebuild(force: true)
                NotificationCenter.default.post(name: .downloadsChanged, object: nil)
            }
            row.onDragStart = { [weak self] in self?.isDragging = true }
            row.onDragEnd = { [weak self] in
                self?.isDragging = false
                self?.close()
            }
            stack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -16).isActive = true
        }
        emptyLabel.isHidden = !rows.isEmpty
        let height = min(max(CGFloat(rows.count) * 62 + 60, 150), 440)
        popover.contentSize = NSSize(width: width, height: height)
    }

    @objc private func allTapped() { close(); onShowAll?() }
    @objc private func clearTapped() {
        Services.shared.downloads.clearFinished()
        rebuild(force: true)
        NotificationCenter.default.post(name: .downloadsChanged, object: nil)
    }
    @objc private func folderTapped() {
        NSWorkspace.shared.open(Services.shared.downloads.downloadsDirectory)
    }
}
