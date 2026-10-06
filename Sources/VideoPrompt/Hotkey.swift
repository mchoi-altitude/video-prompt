import AppKit
import Carbon.HIToolbox
import os

/// Global shortcuts (⌃⌥⌘R record/stop, ⌃⌥⌘D draw). Carbon hot keys need no Accessibility or
/// Input Monitoring permission.
@MainActor
final class Hotkeys {
    private var refs: [EventHotKeyRef?] = []
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

    /// ⌃⌥⌘ + `key` (a kVK_ code).
    func register(_ key: Int, id: UInt32, action: @escaping () -> Void) {
        Self.actions[id] = action
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(UInt32(key), UInt32(controlKey | optionKey | cmdKey),
                                         EventHotKeyID(signature: OSType(0x5650_5254), id: id), GetApplicationEventTarget(), 0, &ref)
        log.notice("hotkey \(id, privacy: .public) register=\(status, privacy: .public)")
        refs.append(ref)
    }
}
