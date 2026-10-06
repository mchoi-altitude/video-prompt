import Foundation
import Testing
import VPCore
import VPTestSupport
@testable import VPApp

private func setup(alive: Bool = true) throws -> (Delivery, Paths, Store, FakePasteboard, RecordingTrasher, String) {
    let p = Paths(root: tempDir()), t = RecordingTrasher(), store = Store(paths: p, trasher: t), pb = FakePasteboard()
    let id = try reviewingRecording(p)
    let d = Delivery(store: store, paths: p, waiters: Waiters(paths: p), pasteboard: pb, isAlive: { _ in alive })
    return (d, p, store, pb, t, id)
}

@Test func referenceIsQuotedAtPrompt() {
    let p = Paths(root: URL(fileURLWithPath: "/Users/x/Library/Application Support/VideoPrompt"))
    #expect(reference(for: "abc", paths: p) == #"@"/Users/x/Library/Application Support/VideoPrompt/recordings/abc/prompt.md""#)
}

@Test func sendDeliversToMostRecentWaiter() throws {
    let (d, p, store, _, _, id) = try setup()
    try Waiters(paths: p).register(Waiter(pid: 42, cwd: "/proj", startedAt: .now))
    #expect(try d.send(id, edits: ReviewEdits()) == .delivered(Waiter(pid: 42, cwd: "/proj", startedAt: try Waiters(paths: p).live(isAlive: { _ in true })[0].startedAt)))
    let m = try store.meta(id)
    #expect(m.status == .ready && m.deliveredToPID == 42)
}

@Test func sendFallsBackWhenWaiterLeft() throws {
    let (d, p, store, pb, _, id) = try setup(alive: false)
    try Waiters(paths: p).register(Waiter(pid: 42, cwd: "/proj", startedAt: .now))
    #expect(try d.send(id, edits: ReviewEdits()) == .fellBackToClipboard)
    #expect(pb.value == reference(for: id, paths: p))
    #expect(try store.meta(id).deliveredToPID == nil)
    #expect(try store.meta(id).status == .ready)
}

@Test func saveAndCopyMakesReadyAndCopies() throws {
    let (d, p, store, pb, _, id) = try setup()
    try d.saveAndCopy(id, edits: ReviewEdits())
    #expect(try store.meta(id).status == .ready)
    #expect(pb.value == reference(for: id, paths: p))
}

@Test func copyReferenceDoesNotDeliver() throws {
    let (d, p, store, pb, _, id) = try setup()
    try Waiters(paths: p).register(Waiter(pid: 42, cwd: "/proj", startedAt: .now))
    try d.copyReference(id, edits: ReviewEdits())
    #expect(try store.meta(id).deliveredToPID == nil)
    #expect(pb.value != nil)
}

@Test func discardTrashes() throws {
    let (d, _, store, _, t, id) = try setup()
    try d.discard(id)
    #expect(t.trashed == [id])
    #expect(store.list().isEmpty)
}

@Test func quietSaveMakesReadyWithoutTouchingClipboard() throws {
    let (d, _, store, pb, _, id) = try setup()
    try d.save(id, edits: ReviewEdits())
    #expect(try store.meta(id).status == .ready)
    #expect(pb.value == nil)
}
