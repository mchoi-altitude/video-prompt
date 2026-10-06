import Foundation
import Testing
import VPCore
@testable import VPProcess
import VPTestSupport

/// A processed recording in review, with a typo in its transcript.
private func processed() throws -> (Paths, Store, String) {
    let paths = Paths(root: tempDir()), store = Store(paths: paths)
    let id = try makeProcessedRecording(paths, status: .reviewing,
                                        transcript: [Sentence(start: 1, end: 2, text: "So, the settigns page."), Sentence(start: 3, end: 4, text: "See this.")])
    return (paths, store, id)
}

@Test func editedTranscriptReplacesNarration() throws {
    let (paths, store, id) = try processed()
    let url = try finalize(id: id, edits: ReviewEdits(transcriptText: "So, the settings page. See this."), store: store, paths: paths)
    let prompt = try String(contentsOf: url, encoding: .utf8)
    #expect(prompt.contains("So, the settings page. See this."))
    #expect(!prompt.contains("settigns"))
    #expect(try store.manifest(id).transcript == [Sentence(start: 0, end: 12, text: "So, the settings page. See this.")])
    #expect(url.lastPathComponent == "timeline.md")
}

@Test func unchangedTranscriptKeepsSentences() throws {
    let (paths, store, id) = try processed()
    _ = try finalize(id: id, edits: ReviewEdits(transcriptText: "So, the settigns page. See this."), store: store, paths: paths)
    #expect(try store.manifest(id).transcript.count == 2)
}

@Test func noteRendersUnderTypedNote() throws {
    let (paths, store, id) = try processed()
    let url = try finalize(id: id, edits: ReviewEdits(note: "Same on Billing."), store: store, paths: paths)
    #expect(try String(contentsOf: url, encoding: .utf8).contains("## Typed note\n\nSame on Billing."))
}

@Test func finalizeMarksReady() throws {
    let (paths, store, id) = try processed()
    #expect(store.latestReady() == nil)
    try finalize(id: id, edits: ReviewEdits(), store: store, paths: paths)
    #expect(try store.meta(id).status == .ready)
    #expect(store.latestReady()?.id == id)
}

@Test func finalizeDeliversToWaiterAndRearmsFetch() throws {
    let (paths, store, id) = try processed()
    try store.update(id) { $0.fetchedByCwd = "/other" }  // fetched earlier by another session
    try finalize(id: id, edits: ReviewEdits(), store: store, paths: paths, deliverTo: Waiter(pid: 77, cwd: "/proj", startedAt: .now))
    let m = try store.meta(id)
    #expect(m.deliveredToPID == 77)
    #expect(m.deliveredToCwd == "/proj")
    #expect(m.fetchedByCwd == nil)
}
