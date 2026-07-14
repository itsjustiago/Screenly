import AppKit

// Entry point. Screenly runs as a menu-bar (accessory) app with no Dock icon.
// Top-level code runs on the main thread, so it's safe to assume main-actor
// isolation to build the (main-actor-isolated) delegate.
MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.run()
}
