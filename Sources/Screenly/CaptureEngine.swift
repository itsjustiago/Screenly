import AppKit

/// User-facing capture preferences, persisted in UserDefaults. Screenly is not
/// sandboxed (self-signed, like its siblings), so a plain folder path is enough —
/// no security-scoped bookmarks needed.
enum CaptureSettings {
    private static var d: UserDefaults { .standard }

    /// Folder where a user-facing copy of each capture is written.
    static var saveFolder: URL {
        get {
            if let p = d.string(forKey: "saveFolder"), !p.isEmpty {
                return URL(fileURLWithPath: p)
            }
            let pics = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first
                ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Pictures")
            return pics.appendingPathComponent("Screenly", isDirectory: true)
        }
        set { d.set(newValue.path, forKey: "saveFolder") }
    }

    /// "png" or "jpg".
    static var format: String {
        get { d.string(forKey: "captureFormat") ?? "png" }
        set { d.set(newValue, forKey: "captureFormat") }
    }

    static var copyToClipboard: Bool {
        get { d.object(forKey: "copyToClipboard") as? Bool ?? true }
        set { d.set(newValue, forKey: "copyToClipboard") }
    }

    static var saveToFolder: Bool {
        get { d.object(forKey: "saveToFolder") as? Bool ?? true }
        set { d.set(newValue, forKey: "saveToFolder") }
    }

    /// Countdown (seconds) before a full-screen capture. 0 = off.
    static var delaySeconds: Int {
        get { d.integer(forKey: "captureDelay") }
        set { d.set(newValue, forKey: "captureDelay") }
    }

    static var playSound: Bool {
        get { d.object(forKey: "playSound") as? Bool ?? true }
        set { d.set(newValue, forKey: "playSound") }
    }

    static var showPreview: Bool {
        get { d.object(forKey: "showPreview") as? Bool ?? true }
        set { d.set(newValue, forKey: "showPreview") }
    }
}

/// A capture backend. `screencapture` is the v1 implementation; the protocol
/// keeps room to swap in ScreenCaptureKit later (annotation, programmatic grabs)
/// without touching callers.
protocol CaptureEngine {
    func capture(_ mode: CaptureMode)
}

/// Wraps the system `/usr/sbin/screencapture` binary — native selection UI for
/// free, robust across displays. Runs async, then saves + stores + previews.
final class SystemCapture: CaptureEngine {
    private let store: CaptureStore
    private let preview = CapturePreview()

    /// Fired on the main thread after a capture is stored, so the UI can refresh.
    var onCaptured: (() -> Void)?

    init(store: CaptureStore) { self.store = store }

    func capture(_ mode: CaptureMode) {
        let fmt = CaptureSettings.format
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("screenly-\(UUID().uuidString).\(fmt)")

        var args: [String] = []
        switch mode {
        case .region: args += ["-i"]        // interactive region (space toggles window mode)
        case .window: args += ["-w", "-o"]  // window picker, no drop shadow
        case .screen: break                 // whole screen, immediately
        }
        args += ["-t", fmt]
        // Note: we deliberately don't pass `-c` — it would send the capture to the
        // clipboard *instead* of writing the file. We copy from the file ourselves.
        if !CaptureSettings.playSound { args += ["-x"] }
        if mode == .screen, CaptureSettings.delaySeconds > 0 {
            args += ["-T", "\(CaptureSettings.delaySeconds)"]
        }
        args.append(tmp.path)

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        proc.arguments = args
        proc.terminationHandler = { [weak self] p in
            let status = p.terminationStatus
            DispatchQueue.main.async { self?.finish(mode: mode, tmp: tmp, fmt: fmt, status: status) }
        }
        do {
            try proc.run()
        } catch {
            NSLog("Screenly: screencapture failed to launch: \(error.localizedDescription)")
        }
    }

    private func finish(mode: CaptureMode, tmp: URL, fmt: String, status: Int32) {
        let fm = FileManager.default
        // Interactive capture cancelled (Esc) → no file written. Silently ignore.
        guard fm.fileExists(atPath: tmp.path),
              let data = try? Data(contentsOf: tmp), !data.isEmpty else { return }

        // Optional user-facing copy in their chosen folder.
        var savedURL: URL?
        if CaptureSettings.saveToFolder {
            savedURL = saveToUserFolder(data: data, fmt: fmt)
        }

        // Keep a copy in our recent-history store.
        let internalURL = store.add(data: data, ext: fmt, mode: mode, savedPath: savedURL?.path)
        try? fm.removeItem(at: tmp)

        // Place the image on the clipboard, ready to paste.
        if CaptureSettings.copyToClipboard, let image = NSImage(data: data) {
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.writeObjects([image])
        }

        // Floating confirmation thumbnail (click to reveal).
        if CaptureSettings.showPreview,
           let url = savedURL ?? internalURL,
           let image = NSImage(contentsOf: url) {
            preview.show(image: image, reveal: savedURL ?? internalURL)
        }

        onCaptured?()
    }

    private func saveToUserFolder(data: Data, fmt: String) -> URL? {
        let folder = CaptureSettings.saveFolder
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = uniqueURL(in: folder, base: "Captura \(Self.stamp())", ext: fmt)
        do {
            try data.write(to: url)
            return url
        } catch {
            NSLog("Screenly: could not write to save folder: \(error.localizedDescription)")
            return nil
        }
    }

    /// Avoid clobbering if two captures land in the same second.
    private func uniqueURL(in folder: URL, base: String, ext: String) -> URL {
        var url = folder.appendingPathComponent("\(base).\(ext)")
        var n = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = folder.appendingPathComponent("\(base) (\(n)).\(ext)")
            n += 1
        }
        return url
    }

    private static func stamp() -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "pt_PT")
        f.dateFormat = "yyyy-MM-dd 'às' HH.mm.ss"
        return f.string(from: Date())
    }
}
