import Foundation
import VPCore

public enum MenuAction: Equatable, Sendable {
    case header, stop, recordChrome, recordScreen, recordArea, recordOtherWindow, recordings, settings, quit
}

public struct MenuItemModel: Equatable, Sendable {
    public var title: String
    public var subtitle: String?
    /// Shown right-aligned: the shortcut, or the Recordings count.
    public var shortcut: String?
    public var checked = false
    public var enabled = true
    public var action: MenuAction
}

/// What the app is in the middle of, as far as the menu cares.
public enum MenuBusy: Equatable, Sendable {
    /// Countdown, starting or recording: offer Stop, no new recording.
    case recording
    /// Transcribing or the review panel is open: no new recording.
    case processing

    public init?(_ s: RecState) {
        switch s {
        case .countdown, .starting, .recording: self = .recording
        case .processing, .reviewing: self = .processing
        case .idle, .failed: return nil
        }
    }
}

public enum MenuBadge: Equatable, Sendable { case none, waiting, recording }

/// Red while recording; amber while a Claude session waits; plain otherwise.
public func menuBadge(state: RecState, waiting: Bool) -> MenuBadge {
    if MenuBusy(state) == .recording { return .recording }
    return waiting && !isProcessing(state) ? .waiting : .none
}

private func isProcessing(_ s: RecState) -> Bool { if case .processing = s { true } else { false } }

/// The status menu, in spec §3.1 order. ⌃⌥⌘R sits on whichever mode was used last.
public func menuItems(waiting: Waiter?, chrome: WindowInfo?, lastMode: CaptureMode, recordingCount: Int,
                      busy: MenuBusy? = nil) -> [MenuItemModel] {
    var items: [MenuItemModel] = []
    if busy == .recording { items.append(MenuItemModel(title: "Stop recording", shortcut: "⌃⌥⌘R", action: .stop)) }
    if waiting != nil { items.append(MenuItemModel(title: "Claude is waiting for a recording", enabled: false, action: .header)) }
    func short(_ m: CaptureMode) -> String? { m == lastMode && busy == nil ? "⌃⌥⌘R" : nil }
    let canRecord = busy == nil
    let title = chrome.map { t -> String in
        let s = t.title ?? "Chrome"
        return s.count > 40 ? String(s.prefix(39)) + "…" : s
    }
    items.append(MenuItemModel(title: "Record Chrome window", subtitle: title ?? "Chrome isn't open", shortcut: short(.window),
                               checked: lastMode == .window, enabled: chrome != nil && canRecord, action: .recordChrome))
    items.append(MenuItemModel(title: "Record whole screen", shortcut: short(.screen), checked: lastMode == .screen, enabled: canRecord, action: .recordScreen))
    items.append(MenuItemModel(title: "Record selected area…", shortcut: short(.area), checked: lastMode == .area, enabled: canRecord, action: .recordArea))
    items.append(MenuItemModel(title: "Record another window…", enabled: canRecord, action: .recordOtherWindow))
    items.append(MenuItemModel(title: "Recordings…", shortcut: String(recordingCount), action: .recordings))
    items.append(MenuItemModel(title: "Settings…", action: .settings))
    items.append(MenuItemModel(title: "Quit Video Prompt", action: .quit))
    return items
}
