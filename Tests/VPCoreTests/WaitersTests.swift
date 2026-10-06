import Foundation
import Testing
@testable import VPCore

@Test func liveWaitersDropsDeadPIDs() throws {
    let p = tempPaths(); let w = Waiters(paths: p)
    try w.register(Waiter(pid: 999, cwd: "/dead", startedAt: .now))
    try w.register(Waiter(pid: 1000, cwd: "/alive", startedAt: .now))
    let live = w.live(isAlive: { $0 == 1000 })
    #expect(live.map(\.pid) == [1000])
    #expect(!FileManager.default.fileExists(atPath: p.waiters.appending(path: "999.json").path))
}

@Test func mostRecentWaiterWins() throws {
    let p = tempPaths(); let w = Waiters(paths: p)
    try w.register(Waiter(pid: 1, cwd: "/a", startedAt: Date(timeIntervalSince1970: 100)))
    try w.register(Waiter(pid: 2, cwd: "/b", startedAt: Date(timeIntervalSince1970: 200)))
    #expect(w.mostRecent(isAlive: { _ in true })?.cwd == "/b")
}

@Test func unregisterRemovesFile() throws {
    let p = tempPaths(); let w = Waiters(paths: p)
    try w.register(Waiter(pid: 7, cwd: "/a", startedAt: .now))
    w.unregister(pid: 7)
    #expect(w.live(isAlive: { _ in true }).isEmpty)
}

@Test func ownProcessIsAlive() { #expect(Waiters.processIsAlive(getpid())) }

@Test func pluginSeenMarker() throws {
    let p = tempPaths(); let w = Waiters(paths: p)
    #expect(w.pluginSeen() == nil)
    try w.markPluginSeen(now: Date(timeIntervalSince1970: 5))
    #expect(w.pluginSeen() == Date(timeIntervalSince1970: 5))
}
