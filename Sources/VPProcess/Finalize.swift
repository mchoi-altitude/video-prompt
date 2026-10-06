import Foundation
import VPCore

/// Applies the review panel's edits (transcript, note) and rewrites `manifest.json` and
/// `timeline.md`. Marks the recording `ready`. With `deliverTo` (Send), it is addressed to that
/// waiting session, and any earlier fetch is cleared so the waiter picks it up. Returns the
/// `timeline.md` URL.
@discardableResult
public func finalize(id: String, edits: ReviewEdits, store: Store, paths: Paths, deliverTo: Waiter? = nil,
                     vpFrames: String = Processor.defaultVPFramesPath) throws -> URL {
    let dir = paths.recording(id)
    var m = try store.manifest(id)
    if let text = edits.transcriptText?.trimmingCharacters(in: .whitespacesAndNewlines),
       text != m.transcript.map(\.text).joined(separator: " ") {
        m.transcript = text.isEmpty ? [] : [Sentence(start: 0, end: m.duration, text: text)]
        m.timeline.removeAll { if case .speech = $0 { true } else { false } }
        m.timeline = (m.timeline + m.transcript.map { .speech(time: $0.start, end: $0.end, text: $0.text) })
            .sorted { $0.time < $1.time }
    }
    if let note = edits.note { m.note = note.isEmpty ? nil : note }
    try writeJSON(m, to: dir.appending(path: "manifest.json"))
    let prompt = dir.appending(path: "timeline.md")
    try writeAtomically(Data(renderTimeline(m, recordingDir: dir, vpFrames: vpFrames).utf8), to: prompt)
    try store.update(id) {
        $0.sizeBytes = folderSize(dir)
        $0.status = .ready
        if let w = deliverTo {
            $0.deliveredToPID = w.pid
            $0.deliveredToCwd = w.cwd
            $0.fetchedByCwd = nil
        }
    }
    return prompt
}
