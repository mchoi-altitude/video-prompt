import Foundation
import VPCore

/// What the app observes while recording, in host time (seconds on any monotonic clock).
public enum EventKind: Sendable {
    case cursor(Point)
    /// A finished stroke; the `hostTime` passed to `log` is its end.
    case stroke(startHost: Double, points: [Point], tool: StrokeTool)
    case clear
    case undo
    case window(Rect, visible: Bool)
}

/// Writes `recordings/<id>/raw/`: `session.json`, `events.jsonl` and `seg_NNN.mov` names, turning
/// host times into (segment, seconds-into-segment) as the processor expects.
public final class RawRecorder: @unchecked Sendable {
    public let id: String
    private let raw: URL
    private let events: FileHandle
    private let lock = NSLock()
    private var segment = 0
    private var segmentStart: Double?

    public init(paths: Paths, session: RawSession, now: Date) throws {
        id = try paths.newRecordingID(now: now)
        raw = paths.raw(id)
        try FileManager.default.createDirectory(at: raw, withIntermediateDirectories: true)
        try writeJSON(session, to: raw.appending(path: "session.json"))
        let url = raw.appending(path: "events.jsonl")
        FileManager.default.createFile(atPath: url.path, contents: nil)
        events = try FileHandle(forWritingTo: url)
    }

    /// The next segment's file, for the capture to write. Events wait for `startSegment`.
    public func prepareSegment() -> URL {
        lock.withLock {
            segment += 1
            segmentStart = nil
            return raw.appending(path: String(format: "seg_%03d.mov", segment))
        }
    }

    /// The prepared segment's file really began at `hostTime` (capture started late).
    public func startSegment(hostTime: Double) { lock.withLock { segmentStart = hostTime } }

    /// `prepareSegment` + `startSegment` at once.
    public func beginSegment(hostTime: Double) -> URL {
        let url = prepareSegment()
        startSegment(hostTime: hostTime)
        return url
    }

    public func endSegment(hostTime: Double) { lock.withLock { segmentStart = nil } }

    /// Records an event in the open segment; dropped while paused.
    public func log(_ kind: EventKind, hostTime: Double) {
        lock.withLock {
            guard let start = segmentStart else { return }
            let t = max(0, hostTime - start)
            let e: RawEvent
            switch kind {
            case let .cursor(p): e = .cursor(seg: segment, t: t, p: p)
            case let .stroke(s, pts, tool): e = .stroke(seg: segment, t0: max(0, s - start), t1: t, points: pts, tool: tool)
            case .clear: e = .clear(seg: segment, t: t)
            case .undo: e = .undo(seg: segment, t: t)
            case let .window(r, visible): e = .window(seg: segment, t: t, frame: r, visible: visible)
            }
            let enc = JSONEncoder()
            enc.outputFormatting = [.sortedKeys]
            guard let data = try? enc.encode(e) else { return }
            events.write(data + Data("\n".utf8))
        }
    }

    public func close() throws {
        try lock.withLock {
            try events.synchronize()
            try events.close()
        }
    }
}
