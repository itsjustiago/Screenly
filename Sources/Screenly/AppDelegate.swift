import AppKit
import SwiftUI
import ServiceManagement

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private let store = CaptureStore()
    private lazy var engine = SystemCapture(store: store)
    private let menuModel = ScreenlyMenuModel()
    private let onboarding = OnboardingController()
    private let settings = SettingsController()
    private let updater = UpdateController()
    private lazy var gallery = GalleryController(store: store)

    private var hotKeys: [HotKey] = []
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var lastPopoverClose = Date.distantPast
    private var availableUpdate: UpdateInfo? { didSet { menuModel.availableUpdate = availableUpdate } }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
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
        default: break
        }
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
    }

    private func suspendHotKeys() {
        hotKeys.forEach { $0.invalidate() }
        hotKeys = []
    }

    private func capture(_ mode: CaptureMode) {
        dismissPopover()
        engine.capture(mode)
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
