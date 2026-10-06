import Foundation
import Testing
import VPCore
import VPTestSupport
@testable import VPApp

@Test @MainActor func primaryTitleFollowsWaiter() throws {
    let p = Paths(root: tempDir()); let id = try reviewingRecording(p)
    let home = FileManager.default.homeDirectoryForCurrentUser.path
    let waiting = try ReviewModel(id: id, store: Store(paths: p), waiter: Waiter(pid: 1, cwd: home + "/acme-console", startedAt: .now))
    #expect(waiting.primaryTitle == "Send to waiting session")
    #expect(waiting.destination == "Goes to: claude — ~/acme-console (waiting for this)")
    let none = try ReviewModel(id: id, store: Store(paths: p), waiter: nil)
    #expect(none.primaryTitle == "Save & copy reference")
    #expect(none.destination == "No session is waiting. It’s saved as your latest recording.")
}

@Test @MainActor func editsCarryRemovedFramesAndNote() throws {
    let p = Paths(root: tempDir()); let id = try reviewingRecording(p)
    let m = try ReviewModel(id: id, store: Store(paths: p), waiter: nil)
    m.removed.insert(2)
    m.note = "Same on Billing."
    #expect(m.edits == ReviewEdits(transcriptText: nil, removedFrames: [2], note: "Same on Billing."))
}

@Test @MainActor func unchangedTranscriptIsNotAnEdit() throws {
    let p = Paths(root: tempDir()); let id = try reviewingRecording(p)
    let m = try ReviewModel(id: id, store: Store(paths: p), waiter: nil)
    #expect(m.transcript == "So, the settings page. See this.")
    #expect(m.edits.transcriptText == nil)
    m.transcript = "So, the settings page. See this button."
    #expect(m.edits.transcriptText == "So, the settings page. See this button.")
}
