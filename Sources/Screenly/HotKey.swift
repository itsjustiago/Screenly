import AppKit
import Carbon.HIToolbox

/// Registers a system-wide hotkey via the Carbon API (no Accessibility permission
/// required). Screenly registers one per capture mode, each with a distinct `id`.
final class HotKey {
    var onFire: (() -> Void)?

    private var ref: EventHotKeyRef?
    private let id: UInt32
    private static var instances: [UInt32: HotKey] = [:]
    private static var handlerInstalled = false

    init?(keyCode: UInt32, modifiers: UInt32, id: UInt32 = 1) {
        self.id = id
        HotKey.installHandlerIfNeeded()

        let hotKeyID = EventHotKeyID(signature: OSType(0x5343524E), id: id) // 'SCRN'
        let status = RegisterEventHotKey(keyCode, modifiers, hotKeyID,
                                         GetApplicationEventTarget(), 0, &ref)
        if status != noErr { return nil }
        HotKey.instances[id] = self
    }

    /// Unregisters the hotkey. Safe to call more than once.
    func invalidate() {
        if let ref {
            UnregisterEventHotKey(ref)
            self.ref = nil
        }
        // Only clear the slot if it still points at us (a replacement may own it now).
        if HotKey.instances[id] === self {
            HotKey.instances[id] = nil
        }
    }

    deinit { invalidate() }

    private static func installHandlerIfNeeded() {
        guard !handlerInstalled else { return }
        handlerInstalled = true
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ -> OSStatus in
            var hkID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject),
                              EventParamType(typeEventHotKeyID), nil,
                              MemoryLayout<EventHotKeyID>.size, nil, &hkID)
            HotKey.instances[hkID.id]?.onFire?()
            return noErr
        }, 1, &eventType, nil, nil)
    }
}
