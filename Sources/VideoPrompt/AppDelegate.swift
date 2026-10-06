import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: StatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = StatusItem()
    }
}
