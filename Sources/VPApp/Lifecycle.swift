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
        for m in store.list() where m.status == .processing {
            try store.update(m.id) {
                $0.status = .processingFailed
                $0.error = "Video Prompt quit while processing"
            }
        }
        try store.sweep(policy: settings.settings.retention, now: now)
    }

    public func hourly(now: Date) throws { try store.sweep(policy: settings.settings.retention, now: now) }

    /// Re-runs the processor on the raw folder a failed recording kept.
    public func retry(_ id: String) async throws -> RecordingMeta { try await makeProcessor().process(id: id) }
}
