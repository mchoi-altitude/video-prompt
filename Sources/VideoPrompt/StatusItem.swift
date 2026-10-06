import AppKit

/// The menu-bar icon and its menu.
@MainActor
final class StatusItem {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

    init() {
        let image = NSImage(systemSymbolName: "record.circle", accessibilityDescription: "Video Prompt")
        image?.isTemplate = true
        item.button?.image = image
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Quit Video Prompt", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        item.menu = menu
    }
}
