import Foundation
import Testing
import VPCore
import VPTestSupport
@testable import VPApp

private let chrome = WindowInfo(id: 9, owner: "Google Chrome", title: "Settings · localhost:5173",
                                frame: Rect(x: 0, y: 0, w: 800, h: 600), layer: 0, onScreen: true)
private let waiter = Waiter(pid: 5, cwd: "/Users/x/acme-console", startedAt: .now)

@Test func headerOnlyWhenWaiting() {
    #expect(menuItems(waiting: waiter, chrome: chrome, lastMode: .window, recordingCount: 0).first?.action == .header)
    #expect(menuItems(waiting: nil, chrome: chrome, lastMode: .window, recordingCount: 0).first?.action == .recordChrome)
    #expect(menuItems(waiting: waiter, chrome: chrome, lastMode: .window, recordingCount: 0).first?.title == "Claude is waiting for a recording")
}

@Test func chromeItemShowsTitle() {
    let item = menuItems(waiting: nil, chrome: chrome, lastMode: .window, recordingCount: 0).first { $0.action == .recordChrome }!
    #expect(item.title == "Record Chrome window")
    #expect(item.subtitle == "Settings · localhost:5173")
    #expect(item.enabled)
}

@Test func longChromeTitleIsTruncated() {
    var c = chrome; c.title = String(repeating: "x", count: 60)
    let item = menuItems(waiting: nil, chrome: c, lastMode: .window, recordingCount: 0).first { $0.action == .recordChrome }!
    #expect(item.subtitle == String(repeating: "x", count: 39) + "…")
}

@Test func noChromeDisablesItem() {
    let item = menuItems(waiting: nil, chrome: nil, lastMode: .window, recordingCount: 0).first { $0.action == .recordChrome }!
    #expect(!item.enabled)
    #expect(item.subtitle == "Chrome isn't open")
}

@Test func shortcutFollowsLastMode() {
    let items = menuItems(waiting: nil, chrome: chrome, lastMode: .screen, recordingCount: 0)
    #expect(items.first { $0.action == .recordScreen }?.shortcut == "⌃⌥⌘R")
    #expect(items.first { $0.action == .recordScreen }?.checked == true)
    #expect(items.first { $0.action == .recordChrome }?.shortcut == nil)
}

@Test func recordingsShowsCount() {
    let items = menuItems(waiting: nil, chrome: chrome, lastMode: .window, recordingCount: 5)
    #expect(items.first { $0.action == .recordings }?.shortcut == "5")
    #expect(items.map(\.action).suffix(3) == [.recordings, .settings, .quit])
}

@Test @MainActor func watcherSeesLiveWaiter() throws {
    let p = Paths(root: tempDir())
    let w = Waiters(paths: p)
    let watcher = WaiterWatcher(waiters: w)
    watcher.poll()
    #expect(watcher.current == nil)
    try w.register(Waiter(pid: getpid(), cwd: "/proj", startedAt: .now))
    watcher.poll()
    #expect(watcher.current?.cwd == "/proj")
}
