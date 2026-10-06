import Combine
import Foundation
import VPCore

/// The review panel: transcript, frames to keep, note, and where the recording will go.
@MainActor
public final class ReviewModel: ObservableObject {
    public let id: String
    public let frames: [ManifestFrame]
    public let duration: Double
    public let mode: CaptureMode
    public let recordingDir: URL
    @Published public var transcript: String
    @Published public var removed: Set<Int> = []
    @Published public var note = ""
    public let waiter: Waiter?
    private let original: String

    public init(id: String, store: Store, waiter: Waiter?) throws {
        let m = try store.manifest(id)
        self.id = id
        frames = m.frames
        duration = m.duration
        mode = m.mode
        recordingDir = store.paths.recording(id)
        original = m.transcript.map(\.text).joined(separator: " ")
        transcript = original
        self.waiter = waiter
    }

    public var primaryTitle: String { waiter == nil ? "Save & copy reference" : "Send to waiting session" }

    public var destination: String {
        guard let w = waiter else { return "No session is waiting. It’s saved as your latest recording." }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let cwd = w.cwd.hasPrefix(home) ? "~" + w.cwd.dropFirst(home.count) : w.cwd
        return "Goes to: claude — \(cwd) (waiting for this)"
    }

    public var keptCount: Int { frames.count - removed.count }

    public var edits: ReviewEdits {
        let t = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        let n = note.trimmingCharacters(in: .whitespacesAndNewlines)
        return ReviewEdits(transcriptText: t == original ? nil : t, removedFrames: removed, note: n.isEmpty ? nil : n)
    }
}
