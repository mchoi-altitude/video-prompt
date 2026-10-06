import Combine
import Foundation
import VPCore

public struct RecordingRow: Identifiable, Equatable, Sendable {
    public var id: String
    public var title: String
    public var meta: String
    public var status: String
    public var expires: String?
    public var size: String
    public var sent: Bool
    public var failed: Bool
    public var inReview: Bool
}

private func lastComponent(_ path: String) -> String { URL(fileURLWithPath: path).lastPathComponent }

public func statusText(_ m: RecordingMeta) -> String {
    switch m.status {
    case .processing: return "Processing…"
    case .reviewing: return "In review"
    case .processingFailed: return "Processing failed · Retry"
    case .ready:
        if let c = m.deliveredToCwd { return "Sent to claude — \(lastComponent(c))" }
        if let c = m.fetchedByCwd { return "Fetched by claude — \(lastComponent(c))" }
        return "Saved · not fetched yet"
    }
}

public func expiryText(_ m: RecordingMeta, policy: RetentionPolicy, now: Date) -> String? {
    guard case let .days(d) = policy else { return nil }
    let remaining = Double(d) * 86400 - now.timeIntervalSince(m.createdAt)
    if remaining <= 86400 { return "Auto-deletes tonight" }
    return "Auto-deletes in \(Int((remaining / 86400).rounded(.up))) days"
}

private func megabytes(_ bytes: Int64) -> String { String(format: "%.1f MB", Double(bytes) / 1_000_000) }

/// The Recordings window: rows, selection, delete to Trash, retention.
@MainActor
public final class RecordingsModel: ObservableObject {
    @Published public private(set) var rows: [RecordingRow] = []
    @Published public var selected: Set<String> = []
    @Published public private(set) var usage = ""
    private let store: Store
    private let settings: SettingsStore
    private let now: () -> Date

    public init(store: Store, settings: SettingsStore, now: @escaping () -> Date = { .now }) {
        self.store = store; self.settings = settings; self.now = now
        reload()
    }

    public var retention: RetentionPolicy { settings.settings.retention }

    public func reload() {
        let metas = store.list()
        let policy = settings.settings.retention, t = now()
        let fmt = DateFormatter()
        fmt.dateStyle = .medium; fmt.timeStyle = .short; fmt.doesRelativeDateFormatting = true
        rows = metas.map { m in
            RecordingRow(id: m.id, title: m.title,
                         meta: "\(fmt.string(from: m.createdAt)) · \(String(format: "%d:%02d", Int(m.duration) / 60, Int(m.duration) % 60))",
                         status: statusText(m), expires: expiryText(m, policy: policy, now: t), size: megabytes(m.sizeBytes),
                         sent: m.deliveredToCwd != nil || m.fetchedByCwd != nil, failed: m.status == .processingFailed,
                         inReview: m.status == .reviewing)
        }
        selected.formIntersection(Set(rows.map(\.id)))
        let total = metas.reduce(Int64(0)) { $0 + $1.sizeBytes }
        usage = "\(metas.count) \(metas.count == 1 ? "recording" : "recordings") · \(megabytes(total))"
    }

    public func selectAllSent() { selected = Set(rows.filter(\.sent).map(\.id)) }

    public func deleteSelected() throws {
        try store.trash(rows.map(\.id).filter(selected.contains))
        selected.removeAll()
        reload()
    }

    public func delete(_ id: String) throws {
        try store.trash([id])
        reload()
    }

    public func copyReference(_ id: String, pasteboard: Pasteboard) {
        pasteboard.setString(reference(for: id, paths: store.paths))
    }

    public func setRetention(_ p: RetentionPolicy) throws {
        settings.settings.retention = p
        try store.sweep(policy: p, now: now())
        reload()
    }
}
