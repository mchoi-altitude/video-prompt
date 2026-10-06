import AppKit
import Carbon.HIToolbox
import os

/// ⌃⌥⌘R anywhere. Carbon hot keys need no Accessibility permission.
@MainActor
final class Hotkey {
    private var ref: EventHotKeyRef?
    private var handler: EventHandlerRef?
    nonisolated(unsafe) private static var action: (() -> Void)?

    init(action: @escaping () -> Void) {
        Self.action = action
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let installed = InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            log.notice("hotkey pressed")
            DispatchQueue.main.async { Hotkey.action?() }
            return noErr
        }, 1, &spec, nil, &handler)
        let id = EventHotKeyID(signature: OSType(0x5650_5254), id: 1)  // 'VPRT'
        let registered = RegisterEventHotKey(UInt32(kVK_ANSI_R), UInt32(controlKey | optionKey | cmdKey), id, GetApplicationEventTarget(), 0, &ref)
        log.notice("hotkey handler=\(installed, privacy: .public) register=\(registered, privacy: .public)")
    }
}
