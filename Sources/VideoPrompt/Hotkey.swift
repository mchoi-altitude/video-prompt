import AppKit
import Carbon.HIToolbox
import os

/// Global shortcuts. ⌃⌥⌘R (record/stop) is always on; ⌥D (draw) only while recording and Esc
/// (stop drawing) only while drawing, so they never take keys away from other apps otherwise.
/// Carbon hot keys need no Accessibility or Input Monitoring permission.
@MainActor
final class Hotkeys {
    private var refs: [UInt32: EventHotKeyRef] = [:]
    private var handler: EventHandlerRef?
    nonisolated(unsafe) private static var actions: [UInt32: () -> Void] = [:]

    init() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let installed = InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var id = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                              MemoryLayout<EventHotKeyID>.size, nil, &id)
            log.notice("hotkey \(id.id, privacy: .public) pressed")
            DispatchQueue.main.async { Hotkeys.actions[id.id]?() }
            return noErr
        }, 1, &spec, nil, &handler)
        log.notice("hotkey handler=\(installed, privacy: .public)")
    }

    static let controlOptionCommand = UInt32(controlKey | optionKey | cmdKey)
    static let option = UInt32(optionKey)

    /// `key` (a kVK_ code) with `modifiers` (Carbon flags; 0 for none). Registering an id that is
    /// already registered does nothing.
    func register(_ key: Int, modifiers: UInt32, id: UInt32, action: @escaping () -> Void) {
        guard refs[id] == nil else { return }
        Self.actions[id] = action
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(UInt32(key), modifiers, EventHotKeyID(signature: OSType(0x5650_5254), id: id),
                                         GetApplicationEventTarget(), 0, &ref)
        log.notice("hotkey \(id, privacy: .public) register=\(status, privacy: .public)")
        if let ref { refs[id] = ref }
    }

    func unregister(_ id: UInt32) {
        guard let ref = refs.removeValue(forKey: id) else { return }
        UnregisterEventHotKey(ref)
    }
}
