import Foundation
import VPCore
import VPProcess
import VPTestSupport
@testable import VPApp

final class FakePasteboard: Pasteboard, @unchecked Sendable {
    var value: String?
    func setString(_ s: String) { value = s }
}

final class RecordingTrasher: Trasher, @unchecked Sendable {
    var trashed: [String] = []
    func trash(_ url: URL) throws { trashed.append(url.lastPathComponent); try FileManager.default.removeItem(at: url) }
}

/// A recording in review: two frames, two sentences.
func reviewingRecording(_ p: Paths, id: String = "20261006-141402") throws -> String {
    let dir = p.recording(id)
    try FileManager.default.createDirectory(at: dir.appending(path: "frames"), withIntermediateDirectories: true)
    let frames = [ManifestFrame(index: 1, time: 0.5, reasons: ["start"], file: "frames/f1.jpg", width: 10, height: 10),
                  ManifestFrame(index: 2, time: 4.3, reasons: ["drawing"], file: "frames/f2.jpg", width: 10, height: 10)]
    for f in frames { try Data([0xFF, 0xD8]).write(to: dir.appending(path: f.file)) }
    let transcript = [Sentence(start: 1, end: 2, text: "So, the settings page."), Sentence(start: 3, end: 4, text: "See this.")]
    try writeJSON(Manifest(id: id, duration: 12, mode: .window, transcript: transcript, frames: frames, strokes: [],
                           timeline: buildTimeline(frames: frames, transcript: transcript, strokes: [], clears: [], hidden: [])),
                  to: dir.appending(path: "manifest.json"))
    try writeJSON(RecordingMeta(id: id, title: "So, the settings page", createdAt: .now, duration: 12, mode: .window, status: .reviewing),
                  to: dir.appending(path: "meta.json"))
    return id
}
