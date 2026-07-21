import AppKit
import SwiftUI
import ServiceManagement

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private let store = CaptureStore()
    private lazy var engine = SystemCapture(store: store)
    private lazy var selectionOverlay = SelectionOverlayController(
        store: store, fallback: { [weak self] mode in self?.engine.capture(mode) })
    private lazy var editor = AnnotationEditorController(store: store)
    private let menuModel = ScreenlyMenuModel()
    private let onboarding = OnboardingController()
    private let settings = SettingsController()
    private let updater = UpdateController()
    private lazy var gallery = GalleryController(store: store)
    private let colorPicker = ColorPickerController()

    private var hotKeys: [HotKey] = []
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var lastPopoverClose = Date.distantPast
    private var availableUpdate: UpdateInfo? { didSet { menuModel.availableUpdate = availableUpdate } }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        // Debug: render sample annotations to a PNG and quit (verifies the export path).
        if let out = ProcessInfo.processInfo.environment["SCREENLY_DEBUG_EXPORT"] {
            Self.debugExport(to: out)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { NSApp.terminate(nil) }
            return
        }
        // Debug: render the annotation toolbar to a PNG and quit.
        if let out = ProcessInfo.processInfo.environment["SCREENLY_DEBUG_TOOLBAR"] {
            Self.debugToolbar(to: out)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { NSApp.terminate(nil) }
            return
        }

        store.load()
        setupStatusItem()

        registerHotKeys()
        settings.onShortcutsChanged = { [weak self] in self?.registerHotKeys() }
        settings.onRecordingChange = { [weak self] recording in
            // While the user records a new shortcut, drop the global hotkeys so
            // pressing an existing one doesn't fire a capture underneath.
            if recording { self?.suspendHotKeys() } else { self?.registerHotKeys() }
        }
        settings.onCheckedUpdate = { [weak self] info in self?.availableUpdate = info }
        settings.onStartUpdate = { [weak self] info in self?.updater.start(info) }
        engine.onCaptured = { [weak self] in self?.refreshMenuModel() }

        // Welcome window on first launch (explains the shortcuts + Screen Recording).
        if !UserDefaults.standard.bool(forKey: "didOnboard") {
            UserDefaults.standard.set(true, forKey: "didOnboard")
            onboarding.show()
        }

        if Updater.autoCheckEnabled {
            Updater.check { [weak self] info in self?.availableUpdate = info }
        }

        // Debug hooks for verifying flows without clicking the menu.
        switch ProcessInfo.processInfo.environment["SCREENLY_DEBUG_WINDOW"] {
        case "settings": settings.show()
        case "gallery": gallery.show()
        case "onboarding": onboarding.show()
        case "editor": if let img = Self.debugImage(NSSize(width: 1200, height: 800)) { editor.open(image: img, mode: .screen) }
        case "overlay": selectionOverlay.beginDebug()
        default: break
        }
    }

    /// Render one sample shape per tool over a synthetic image, via the real
    /// `ShapesCanvas` + `ImageRenderer` export path, and write it to `path`.
    static func debugExport(to path: String) {
        let size = CGSize(width: 800, height: 500)
        guard let base = debugImage(size) else { return }
        let shapes: [AnnotationShape] = [
            AnnotationShape(tool: .rectangle, colorHex: "#FF3B30", lineWidth: 6,
                            points: [CGPoint(x: 60, y: 70), CGPoint(x: 300, y: 230)]),
            AnnotationShape(tool: .ellipse, colorHex: "#34C759", lineWidth: 6,
                            points: [CGPoint(x: 340, y: 80), CGPoint(x: 520, y: 220)]),
            AnnotationShape(tool: .arrow, colorHex: "#007AFF", lineWidth: 6,
                            points: [CGPoint(x: 120, y: 410), CGPoint(x: 430, y: 300)]),
            AnnotationShape(tool: .freehand, colorHex: "#FFCC00", lineWidth: 5,
                            points: [CGPoint(x: 560, y: 300), CGPoint(x: 600, y: 350),
                                     CGPoint(x: 645, y: 300), CGPoint(x: 690, y: 360)]),
            AnnotationShape(tool: .highlighter, colorHex: "#AF52DE", lineWidth: 9,
                            points: [CGPoint(x: 80, y: 470), CGPoint(x: 300, y: 470)]),
            AnnotationShape(tool: .text, colorHex: "#FFFFFF", lineWidth: 9,
                            points: [CGPoint(x: 350, y: 420)], text: "Screenly ✎"),
            AnnotationShape(tool: .rectangle, colorHex: "#000000", lineWidth: 6,
                            points: [CGPoint(x: 560, y: 410), CGPoint(x: 740, y: 470)], filled: true),
        ]
        let content = ZStack(alignment: .topLeading) {
            Image(nsImage: base).resizable().frame(width: size.width, height: size.height)
            ShapesCanvas(shapes: shapes).frame(width: size.width, height: size.height)
        }
        .frame(width: size.width, height: size.height)
        let renderer = ImageRenderer(content: content)
        renderer.scale = 2
        guard let cg = renderer.cgImage else { return }
        let rep = NSBitmapImageRep(cgImage: cg)
        if let data = rep.representation(using: .png, properties: [:]) {
            try? data.write(to: URL(fileURLWithPath: path))
        }
    }

    /// Render the annotation toolbar over a neutral backdrop, for layout review.
    static func debugToolbar(to path: String) {
        let model = AnnotationModel()
        let content = AnnotationToolbar(model: model, onCopy: {}, onSave: {}, onCancel: {})
            .padding(40)
            .background(LinearGradient(colors: [.gray, .black], startPoint: .top, endPoint: .bottom))
        let renderer = ImageRenderer(content: content)
        renderer.scale = 2
        guard let cg = renderer.cgImage else { return }
        let rep = NSBitmapImageRep(cgImage: cg)
        if let data = rep.representation(using: .png, properties: [:]) {
            try? data.write(to: URL(fileURLWithPath: path))
        }
    }

    /// A synthetic image for verifying the editor/overlay without a real capture.
    static func debugImage(_ size: NSSize) -> NSImage? {
        let img = NSImage(size: size)
        img.lockFocus()
        NSGradient(colors: [.systemTeal, .systemIndigo])?.draw(in: NSRect(origin: .zero, size: size), angle: -45)
        ("Screenly debug" as NSString).draw(at: NSPoint(x: 40, y: 40),
            withAttributes: [.font: NSFont.systemFont(ofSize: 40), .foregroundColor: NSColor.white])
        img.unlockFocus()
        return img
    }

    // MARK: - Hotkeys

    private func registerHotKeys() {
        hotKeys.forEach { $0.invalidate() }
        hotKeys = CaptureMode.allCases.compactMap { mode in
            let hk = HotKey(keyCode: UInt32(Shortcut.keyCode(mode)),
                            modifiers: Shortcut.carbonModifiers(mode),
                            id: mode.hotKeyID)
            hk?.onFire = { [weak self] in self?.capture(mode) }
            return hk
        }
        // The screen colour picker rides the same global-hotkey machinery.
        let picker = PickerAction.eyedropper
        if let hk = HotKey(keyCode: UInt32(Shortcut.keyCode(picker)),
                           modifiers: Shortcut.carbonModifiers(picker),
                           id: picker.hotKeyID) {
            hk.onFire = { [weak self] in self?.pickColor() }
            hotKeys.append(hk)
        }
    }

    private func suspendHotKeys() {
        hotKeys.forEach { $0.invalidate() }
        hotKeys = []
    }

    private func capture(_ mode: CaptureMode) {
        dismissPopover()
        guard CaptureSettings.annotate else { engine.capture(mode); return }
        switch mode {
        case .region:
            // Freeze the screen → interactive selection + annotation overlay.
            selectionOverlay.begin()
        case .window, .screen:
            // Capture, then open the annotation editor window.
            engine.captureImage(mode) { [weak self] image in
                guard let self, let image else { return }
                self.editor.open(image: image, mode: mode)
            }
        }
    }

    // MARK: - Colour picker

    private func pickColor() {
        dismissPopover()
        colorPicker.pick()
    }

    private func copyRecentColor(_ hex: String) {
        dismissPopover()
        colorPicker.copyRecent(hex)
    }

    // MARK: - Status bar

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let image = NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: "Screenly")
        image?.isTemplate = true
        item.button?.image = image
        item.button?.target = self
        item.button?.action = #selector(togglePopover)
        statusItem = item
        buildPopover()
    }

    /// The menu-bar dropdown is a SwiftUI panel in an `NSPopover`, matching the
    /// other apps in the family.
    private func buildPopover() {
        let panel = MenuPanel(
            store: store,
            model: menuModel,
            onCapture: { [weak self] mode in self?.capture(mode) },
            onPickColor: { [weak self] in self?.pickColor() },
            onPickRecentColor: { [weak self] hex in self?.copyRecentColor(hex) },
            onPickRecent: { [weak self] shot in self?.pickRecent(shot) },
            onRevealRecent: { [weak self] shot in self?.revealRecent(shot) },
            onShowGallery: { [weak self] in self?.dismissPopover(); self?.gallery.show() },
            onSettings: { [weak self] in self?.dismissPopover(); self?.settings.show() },
            onOnboarding: { [weak self] in self?.dismissPopover(); self?.onboarding.show() },
            onUpdate: { [weak self] in
                self?.dismissPopover()
                if let update = self?.availableUpdate { self?.updater.start(update) }
            },
            onGrantAccess: { [weak self] in
                self?.dismissPopover()
                Permissions.shared.request()
                Permissions.shared.openSettings()
            },
            onQuit: { NSApp.terminate(nil) })

        let hosting = NSHostingController(rootView: panel)
        hosting.sizingOptions = .preferredContentSize

        let pop = NSPopover()
        pop.behavior = .transient
        pop.animates = true
        pop.delegate = self
        pop.contentViewController = hosting
        popover = pop
    }

    @objc private func togglePopover() {
        guard let popover, let button = statusItem?.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            // Clicking the icon while the popover is open dismisses it via the
            // transient behaviour first; don't let the same click reopen it.
            if Date().timeIntervalSince(lastPopoverClose) < 0.2 { return }
            refreshMenuModel()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    func popoverDidClose(_ notification: Notification) { lastPopoverClose = Date() }

    private func dismissPopover() { popover?.performClose(nil) }

    /// Mirror live state into the panel's model before it shows.
    private func refreshMenuModel() {
        menuModel.count = store.items.count
        menuModel.shortcuts = Dictionary(
            uniqueKeysWithValues: CaptureMode.allCases.map { ($0.rawValue, Shortcut.display($0)) })
        menuModel.pickerShortcut = Shortcut.display(PickerAction.eyedropper)
        menuModel.recentColors = ColorHistory.colors
        Permissions.shared.refresh()
        menuModel.hasScreenRecording = Permissions.shared.isTrusted
        menuModel.availableUpdate = availableUpdate
    }

    // MARK: - Recent actions

    private func pickRecent(_ shot: Shot) {
        dismissPopover()
        if let img = NSImage(contentsOf: store.imageURL(for: shot)) {
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.writeObjects([img])
        }
    }

    private func revealRecent(_ shot: Shot) {
        dismissPopover()
        let saved = shot.savedPath.flatMap {
            FileManager.default.fileExists(atPath: $0) ? URL(fileURLWithPath: $0) : nil
        }
        NSWorkspace.shared.activateFileViewerSelecting([saved ?? store.imageURL(for: shot)])
    }
}

// MARK: - Launch at login

enum LoginItem {
    static var isEnabled: Bool {
        if #available(macOS 13.0, *) { return SMAppService.mainApp.status == .enabled }
        return false
    }

    static func setEnabled(_ enabled: Bool) {
        guard #available(macOS 13.0, *) else { return }
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSLog("Screenly: login item error: \(error.localizedDescription)")
        }
    }
}
