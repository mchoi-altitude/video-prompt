import Foundation
import Testing
import VPCore
@testable import VPProcess
import VPTestSupport

/// A processed recording with two frames and two sentences, built without the processor.
private func processed() throws -> (Paths, Store, String) {
    let paths = Paths(root: tempDir()), store = Store(paths: paths)
    let id = "20261006-141402", dir = paths.recording(id)
    try FileManager.default.createDirectory(at: dir.appending(path: "frames"), withIntermediateDirectories: true)
    let frames = [ManifestFrame(index: 1, time: 0.5, reasons: ["start"], file: "frames/f1.jpg", width: 10, height: 10),
                  ManifestFrame(index: 2, time: 4.3, reasons: ["drawing"], file: "frames/f2.jpg", width: 10, height: 10)]
    for f in frames { try Data([0xFF, 0xD8]).write(to: dir.appending(path: f.file)) }
    let transcript = [Sentence(start: 1, end: 2, text: "So, the settigns page."), Sentence(start: 3, end: 4, text: "See this.")]
    let m = Manifest(id: id, duration: 12, mode: .window, transcript: transcript, frames: frames, strokes: [],
                     timeline: buildTimeline(frames: frames, transcript: transcript, strokes: [], clears: [], hidden: []))
    try writeJSON(m, to: dir.appending(path: "manifest.json"))
    try writeJSON(RecordingMeta(id: id, title: "x", createdAt: .now, duration: 12, mode: .window, status: .ready),
                  to: dir.appending(path: "meta.json"))
    return (paths, store, id)
}

@Test func removedFrameDisappearsFromPromptAndDisk() throws {
    let (paths, store, id) = try processed()
    let url = try finalize(id: id, edits: ReviewEdits(removedFrames: [2]), store: store, paths: paths)
    let prompt = try String(contentsOf: url, encoding: .utf8)
    #expect(!prompt.contains("f2.jpg"))
    #expect(prompt.contains("Frame 1 (start)"))
    #expect(!FileManager.default.fileExists(atPath: paths.recording(id).appending(path: "frames/f2.jpg").path))
    #expect(try store.manifest(id).frames.map(\.index) == [1])
}

@Test func editedTranscriptReplacesNarration() throws {
    let (paths, store, id) = try processed()
    let url = try finalize(id: id, edits: ReviewEdits(transcriptText: "So, the settings page. See this."), store: store, paths: paths)
    let prompt = try String(contentsOf: url, encoding: .utf8)
    #expect(prompt.contains("So, the settings page. See this."))
    #expect(!prompt.contains("settigns"))
    #expect(try store.manifest(id).transcript == [Sentence(start: 0, end: 12, text: "So, the settings page. See this.")])
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
