import Foundation
import VPCore
import VPProcess

/// Housekeeping: recover from a quit mid-processing, expire old recordings, retry failures.
public struct Lifecycle: Sendable {
    let store: Store
    let settings: SettingsStore
    let makeProcessor: @Sendable () -> Processor

    public init(store: Store, settings: SettingsStore, makeProcessor: @escaping @Sendable () -> Processor) {
        self.store = store; self.settings = settings; self.makeProcessor = makeProcessor
    }

    public func onLaunch(now: Date) throws {
        recoverInterruptedRecordings()
        for m in store.list() where m.status == .processing {
            try store.update(m.id) {
                $0.status = .processingFailed
                $0.error = "Video Prompt quit while processing"
            }
        }
        try store.sweep(policy: settings.settings.retention, now: now)
    }

    /// Folders without meta.json were never finished (quit or crash while recording). Ones with
    /// video become `processingFailed`, so they show in Recordings with Retry and expire like any
    /// other; empty ones are removed.
    private func recoverInterruptedRecordings() {
        let fm = FileManager.default
        let paths = store.paths
        let ids = (try? fm.contentsOfDirectory(atPath: paths.recordings.path)) ?? []
        for id in ids where !id.hasPrefix(".") && !fm.fileExists(atPath: paths.recording(id).appending(path: "meta.json").path) {
            let raw = paths.raw(id)
            let segments = ((try? fm.contentsOfDirectory(atPath: raw.path)) ?? []).filter { $0.hasPrefix("seg_") }
            let hasVideo = segments.contains { ((try? fm.attributesOfItem(atPath: raw.appending(path: $0).path)[.size]) as? Int ?? 0) > 0 }
            guard hasVideo else { try? fm.removeItem(at: paths.recording(id)); continue }
            let session = try? readJSON(RawSession.self, from: raw.appending(path: "session.json"))
            let meta = RecordingMeta(id: id, title: "Unfinished recording", createdAt: session?.createdAt ?? .now, duration: 0,
                                     mode: session?.mode ?? .screen, status: .processingFailed,
                                     error: "Video Prompt quit while recording")
            try? writeJSON(meta, to: paths.recording(id).appending(path: "meta.json"))
        }
    }

    public func hourly(now: Date) throws { try store.sweep(policy: settings.settings.retention, now: now) }

    /// Re-runs the processor on the raw folder a failed recording kept.
    public func retry(_ id: String) async throws -> RecordingMeta { try await makeProcessor().process(id: id) }
}
