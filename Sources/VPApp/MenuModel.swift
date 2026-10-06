import Foundation
import VPCore

public enum MenuAction: Equatable, Sendable {
    case header, recordChrome, recordScreen, recordArea, recordOtherWindow, recordings, settings, quit
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

/// The status menu, in spec §3.1 order. ⌃⌥⌘R sits on whichever mode was used last.
public func menuItems(waiting: Waiter?, chrome: WindowInfo?, lastMode: CaptureMode, recordingCount: Int) -> [MenuItemModel] {
    var items: [MenuItemModel] = []
    if waiting != nil { items.append(MenuItemModel(title: "Claude is waiting for a recording", enabled: false, action: .header)) }
    func short(_ m: CaptureMode) -> String? { m == lastMode ? "⌃⌥⌘R" : nil }
    let title = chrome.map { t -> String in
        let s = t.title ?? "Chrome"
        return s.count > 40 ? String(s.prefix(39)) + "…" : s
    }
    items.append(MenuItemModel(title: "Record Chrome window", subtitle: title ?? "Chrome isn't open", shortcut: short(.window),
                               checked: lastMode == .window, enabled: chrome != nil, action: .recordChrome))
    items.append(MenuItemModel(title: "Record whole screen", shortcut: short(.screen), checked: lastMode == .screen, action: .recordScreen))
    items.append(MenuItemModel(title: "Record selected area…", shortcut: short(.area), checked: lastMode == .area, action: .recordArea))
    items.append(MenuItemModel(title: "Record another window…", action: .recordOtherWindow))
    items.append(MenuItemModel(title: "Recordings…", shortcut: String(recordingCount), action: .recordings))
    items.append(MenuItemModel(title: "Settings…", action: .settings))
    items.append(MenuItemModel(title: "Quit Video Prompt", action: .quit))
    return items
}
