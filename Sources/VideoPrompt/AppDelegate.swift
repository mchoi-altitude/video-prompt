import AppKit
import VPApp

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: StatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = StatusItem(items: { menuItems(waiting: nil, chrome: nil, lastMode: .window, recordingCount: 0) },
                                onAction: { if $0 == .quit { NSApp.terminate(nil) } })
    }
}
