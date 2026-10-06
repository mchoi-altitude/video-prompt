import Foundation
import Testing
@testable import VPCore

private let now = ISO8601DateFormatter().date(from: "2026-10-06T14:14:02Z")!

@Test func newIDsAreUniqueWithinOneSecond() throws {
    let p = tempPaths()
    var utc = Calendar(identifier: .gregorian); utc.timeZone = TimeZone(identifier: "UTC")!
    #expect(try p.newRecordingID(now: now, calendar: utc) == "20261006-141402")
    #expect(try p.newRecordingID(now: now, calendar: utc) == "20261006-141402-2")
}

@Test func rootIsPrivate() throws {
    let p = tempPaths()
    try p.ensureRoot()
    let perms = try FileManager.default.attributesOfItem(atPath: p.root.path)[.posixPermissions] as? Int
    #expect(perms == 0o700)
}

@Test func listIgnoresFolderWithoutMeta() throws {
    let p = tempPaths()
    try addRecording(p, id: "a", daysAgo: 0, now: now)
    try FileManager.default.createDirectory(at: p.recording("half-written"), withIntermediateDirectories: true)
    #expect(Store(paths: p).list().map(\.id) == ["a"])
}

@Test func listIsNewestFirst() throws {
    let p = tempPaths()
    try addRecording(p, id: "old", daysAgo: 2, now: now)
    try addRecording(p, id: "new", daysAgo: 0, now: now)
    try addRecording(p, id: "mid", daysAgo: 1, now: now)
    #expect(Store(paths: p).list().map(\.id) == ["new", "mid", "old"])
}

@Test func latestReadySkipsProcessing() throws {
    let p = tempPaths()
    try addRecording(p, id: "done", daysAgo: 1, now: now)
    try addRecording(p, id: "busy", daysAgo: 0, now: now, status: .processing)
    #expect(Store(paths: p).latestReady()?.id == "done")
}

@Test func sweepDaysTrashesOnlyExpired() throws {
    let p = tempPaths(); let t = FakeTrasher()
    try addRecording(p, id: "four", daysAgo: 4, now: now)
    try addRecording(p, id: "two", daysAgo: 2, now: now)
    let gone = try Store(paths: p, trasher: t).sweep(policy: .days(3), now: now)
    #expect(gone == ["four"])
    #expect(t.trashed == ["four"])
    #expect(Store(paths: p).list().map(\.id) == ["two"])
}

@Test func sweepKeepLast20KeepsNewest() throws {
    let p = tempPaths(); let t = FakeTrasher()
    for i in 0..<22 { try addRecording(p, id: String(format: "r%02d", i), daysAgo: Double(i), now: now) }
    let gone = try Store(paths: p, trasher: t).sweep(policy: .keepLast(20), now: now)
    #expect(Set(gone) == ["r20", "r21"])
}

@Test func sweepNeverTrashesNothing() throws {
    let p = tempPaths(); let t = FakeTrasher()
    try addRecording(p, id: "ancient", daysAgo: 400, now: now)
    #expect(try Store(paths: p, trasher: t).sweep(policy: .never, now: now).isEmpty)
}

@Test func sweepSkipsProcessing() throws {
    let p = tempPaths(); let t = FakeTrasher()
    try addRecording(p, id: "busy", daysAgo: 10, now: now, status: .processing)
    #expect(try Store(paths: p, trasher: t).sweep(policy: .days(3), now: now).isEmpty)
}

@Test func updateRewritesMeta() throws {
    let p = tempPaths()
    try addRecording(p, id: "a", daysAgo: 0, now: now)
    let s = Store(paths: p)
    try s.update("a") { $0.fetchedByCwd = "/proj" }
    #expect(try s.meta("a").fetchedByCwd == "/proj")
}

@Test func defaultRetentionIsThreeDays() { #expect(RetentionPolicy.default == .days(3)) }
