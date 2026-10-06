import Foundation
@testable import VPCore

func tempPaths() -> Paths {
    Paths(root: FileManager.default.temporaryDirectory.appending(path: "vp-\(UUID().uuidString)"))
}

final class FakeTrasher: Trasher, @unchecked Sendable {
    private let lock = NSLock()
    private var _trashed: [URL] = []
    var trashed: [String] { lock.withLock { _trashed.map(\.lastPathComponent) } }
    func trash(_ url: URL) throws {
        lock.withLock { _trashed.append(url) }
        try FileManager.default.removeItem(at: url)
    }
}

/// A recording folder with meta.json; `daysAgo` sets createdAt relative to `now`.
@discardableResult
func addRecording(_ paths: Paths, id: String, daysAgo: Double, now: Date, status: RecordingStatus = .ready,
                  deliveredToPID: Int32? = nil) throws -> RecordingMeta {
    let dir = paths.recording(id)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let meta = RecordingMeta(id: id, title: "t \(id)", createdAt: now.addingTimeInterval(-daysAgo * 86400),
                             duration: 10, mode: .window, status: status, deliveredToPID: deliveredToPID)
    try writeJSON(meta, to: dir.appending(path: "meta.json"))
    return meta
}
