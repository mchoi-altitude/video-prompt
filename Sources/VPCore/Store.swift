import Foundation

public enum RetentionPolicy: Codable, Sendable, Equatable {
    case days(Int), keepLast(Int), never
    public static let `default` = RetentionPolicy.days(3)
}

public protocol Trasher: Sendable { func trash(_ url: URL) throws }

/// Moves to the macOS Trash, so a deletion can be undone from Finder.
public struct SystemTrasher: Trasher {
    public init() {}
    public func trash(_ url: URL) throws { try FileManager.default.trashItem(at: url, resultingItemURL: nil) }
}

public enum StoreError: Error, Equatable { case notFound(String) }

/// Reads and maintains the recordings folder. A recording exists for readers only once its
/// `meta.json` has been written.
public final class Store: Sendable {
    public let paths: Paths
    let trasher: Trasher

    public init(paths: Paths, trasher: Trasher = SystemTrasher()) {
        self.paths = paths
        self.trasher = trasher
    }

    public func list() -> [RecordingMeta] {
        let ids = (try? FileManager.default.contentsOfDirectory(atPath: paths.recordings.path)) ?? []
        return ids.compactMap { try? meta($0) }.sorted { $0.createdAt > $1.createdAt }
    }

    public func latestReady() -> RecordingMeta? { list().first { $0.status == .ready } }

    public func meta(_ id: String) throws -> RecordingMeta {
        let url = paths.recording(id).appending(path: "meta.json")
        guard FileManager.default.fileExists(atPath: url.path) else { throw StoreError.notFound(id) }
        return try readJSON(RecordingMeta.self, from: url)
    }

    public func manifest(_ id: String) throws -> Manifest {
        try readJSON(Manifest.self, from: paths.recording(id).appending(path: "manifest.json"))
    }

    public func update(_ id: String, _ change: (inout RecordingMeta) -> Void) throws {
        var m = try meta(id)
        change(&m)
        try writeJSON(m, to: paths.recording(id).appending(path: "meta.json"))
    }

    public func trash(_ ids: [String]) throws {
        for id in ids { try trasher.trash(paths.recording(id)) }
    }

    /// Trashes recordings the policy has expired; never one still processing. Returns their ids.
    @discardableResult
    public func sweep(policy: RetentionPolicy, now: Date) throws -> [String] {
        let candidates = list().filter { $0.status != .processing }
        let expired: [RecordingMeta]
        switch policy {
        case .never: expired = []
        case let .days(d): expired = candidates.filter { now.timeIntervalSince($0.createdAt) > Double(d) * 86400 }
        case let .keepLast(n): expired = Array(candidates.dropFirst(n))
        }
        let ids = expired.map(\.id)
        try trash(ids)
        return ids
    }
}
