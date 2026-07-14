import AppKit
import Carbon.HIToolbox

/// The three capture modes Screenly offers, each with its own global shortcut.
enum CaptureMode: String, CaseIterable, Identifiable {
    case region, window, screen
    var id: String { rawValue }

    var title: String {
        switch self {
        case .region: return "Capturar região"
        case .window: return "Capturar janela"
        case .screen: return "Capturar ecrã inteiro"
        }
    }

    var shortTitle: String {
        switch self {
        case .region: return "Região"
        case .window: return "Janela"
        case .screen: return "Ecrã inteiro"
        }
    }

    var systemImage: String {
        switch self {
        case .region: return "rectangle.dashed"
        case .window: return "macwindow"
        case .screen: return "display"
        }
    }

    /// Distinct Carbon hotkey id per mode (1…3).
    var hotKeyID: UInt32 {
        switch self {
        case .region: return 1
        case .window: return 2
        case .screen: return 3
        }
    }

    /// Default shortcut. Uses ⌃⇧ + digit to steer clear of the system
    /// screenshot shortcuts (⌘⇧3 / ⌘⇧4 / ⌘⇧5).
    var defaultKeyCode: Int {
        switch self {
        case .region: return kVK_ANSI_2
        case .window: return kVK_ANSI_3
        case .screen: return kVK_ANSI_4
        }
    }
    var defaultModifiers: NSEvent.ModifierFlags { [.control, .shift] }
    var defaultDisplay: String {
        switch self {
        case .region: return "⌃⇧2"
        case .window: return "⌃⇧3"
        case .screen: return "⌃⇧4"
        }
    }
}

/// The user-configurable global shortcut for each capture mode, persisted in
/// UserDefaults. Generalises Clippy's single-shortcut store to one per mode.
enum Shortcut {
    private static var d: UserDefaults { .standard }
    private static func codeKey(_ m: CaptureMode) -> String { "hotKeyCode.\(m.rawValue)" }
    private static func modsKey(_ m: CaptureMode) -> String { "hotKeyMods.\(m.rawValue)" }
    private static func displayKey(_ m: CaptureMode) -> String { "hotKeyDisplay.\(m.rawValue)" }

    static func keyCode(_ m: CaptureMode) -> Int {
        d.object(forKey: codeKey(m)) as? Int ?? m.defaultKeyCode
    }

    static func modifiers(_ m: CaptureMode) -> NSEvent.ModifierFlags {
        if let raw = d.object(forKey: modsKey(m)) as? Int {
            return NSEvent.ModifierFlags(rawValue: UInt(raw))
        }
        return m.defaultModifiers
    }

    static func display(_ m: CaptureMode) -> String {
        d.string(forKey: displayKey(m)) ?? m.defaultDisplay
    }

    static func save(_ m: CaptureMode, keyCode: Int, modifiers: NSEvent.ModifierFlags, display: String) {
        d.set(keyCode, forKey: codeKey(m))
        d.set(Int(modifiers.rawValue), forKey: modsKey(m))
        d.set(display, forKey: displayKey(m))
    }

    static func resetToDefault(_ m: CaptureMode) {
        d.removeObject(forKey: codeKey(m))
        d.removeObject(forKey: modsKey(m))
        d.removeObject(forKey: displayKey(m))
    }

    /// Carbon modifier mask for RegisterEventHotKey.
    static func carbonModifiers(_ m: CaptureMode) -> UInt32 {
        var c: UInt32 = 0
        let mods = modifiers(m)
        if mods.contains(.command) { c |= UInt32(cmdKey) }
        if mods.contains(.option) { c |= UInt32(optionKey) }
        if mods.contains(.control) { c |= UInt32(controlKey) }
        if mods.contains(.shift) { c |= UInt32(shiftKey) }
        return c
    }

    /// Human-readable label like "⌃⇧2" or "⌥⌘Space".
    static func displayString(keyCode: Int, modifiers: NSEvent.ModifierFlags, chars: String?) -> String {
        var s = ""
        if modifiers.contains(.control) { s += "⌃" }
        if modifiers.contains(.option) { s += "⌥" }
        if modifiers.contains(.shift) { s += "⇧" }
        if modifiers.contains(.command) { s += "⌘" }
        return s + keyLabel(keyCode: keyCode, chars: chars)
    }

    private static func keyLabel(keyCode: Int, chars: String?) -> String {
        let specials: [Int: String] = [
            kVK_Space: "Space", kVK_Return: "↩", kVK_ANSI_KeypadEnter: "⌤",
            kVK_Tab: "⇥", kVK_Delete: "⌫", kVK_ForwardDelete: "⌦", kVK_Escape: "⎋",
            kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
            kVK_Home: "↖", kVK_End: "↘", kVK_PageUp: "⇞", kVK_PageDown: "⇟",
        ]
        if let s = specials[keyCode] { return s }
        if let c = chars, let scalar = c.unicodeScalars.first, scalar.value >= 32 {
            return c.uppercased()
        }
        return "#\(keyCode)"
    }
}
