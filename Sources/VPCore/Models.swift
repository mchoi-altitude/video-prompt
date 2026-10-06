import Foundation

public struct Rect: Codable, Sendable, Equatable {
    public var x, y, w, h: Double
    public init(x: Double, y: Double, w: Double, h: Double) { self.x = x; self.y = y; self.w = w; self.h = h }
}

public struct Point: Codable, Sendable, Equatable {
    public var x, y: Double
    public init(x: Double, y: Double) { self.x = x; self.y = y }
}

public enum CaptureMode: String, Codable, Sendable { case window, screen, area }

/// Written by the app when recording starts: `raw/session.json`.
public struct RawSession: Codable, Sendable, Equatable {
    public var mode: CaptureMode
    public var display: Rect
    public var area: Rect?
    public var windowTitle: String?
    public var createdAt: Date
    public var note: String?
    public init(mode: CaptureMode, display: Rect, area: Rect? = nil, windowTitle: String? = nil,
                createdAt: Date, note: String? = nil) {
        self.mode = mode; self.display = display; self.area = area
        self.windowTitle = windowTitle; self.createdAt = createdAt; self.note = note
    }
}

public enum StrokeTool: String, Codable, Sendable { case pen, arrow, box }

/// One line of `raw/events.jsonl`. Times are seconds into segment `seg`; points are global
/// screen points, origin top-left.
public enum RawEvent: Codable, Sendable, Equatable {
    case cursor(seg: Int, t: Double, p: Point)
    case stroke(seg: Int, t0: Double, t1: Double, points: [Point], tool: StrokeTool)
    case clear(seg: Int, t: Double)
    case window(seg: Int, t: Double, frame: Rect, visible: Bool)

    private enum K: String, CodingKey { case type, seg, t, p, t0, t1, points, tool, frame, visible }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: K.self)
        let seg = try c.decode(Int.self, forKey: .seg)
        switch try c.decode(String.self, forKey: .type) {
        case "cursor": self = .cursor(seg: seg, t: try c.decode(Double.self, forKey: .t), p: try c.decode(Point.self, forKey: .p))
        case "stroke": self = .stroke(seg: seg, t0: try c.decode(Double.self, forKey: .t0), t1: try c.decode(Double.self, forKey: .t1),
                                      points: try c.decode([Point].self, forKey: .points), tool: try c.decode(StrokeTool.self, forKey: .tool))
        case "clear": self = .clear(seg: seg, t: try c.decode(Double.self, forKey: .t))
        case "window": self = .window(seg: seg, t: try c.decode(Double.self, forKey: .t), frame: try c.decode(Rect.self, forKey: .frame),
                                      visible: try c.decode(Bool.self, forKey: .visible))
        case let other: throw DecodingError.dataCorruptedError(forKey: .type, in: c, debugDescription: "unknown event type \(other)")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: K.self)
        switch self {
        case let .cursor(seg, t, p):
            try c.encode("cursor", forKey: .type); try c.encode(seg, forKey: .seg); try c.encode(t, forKey: .t); try c.encode(p, forKey: .p)
        case let .stroke(seg, t0, t1, points, tool):
            try c.encode("stroke", forKey: .type); try c.encode(seg, forKey: .seg); try c.encode(t0, forKey: .t0)
            try c.encode(t1, forKey: .t1); try c.encode(points, forKey: .points); try c.encode(tool, forKey: .tool)
        case let .clear(seg, t):
            try c.encode("clear", forKey: .type); try c.encode(seg, forKey: .seg); try c.encode(t, forKey: .t)
        case let .window(seg, t, frame, visible):
            try c.encode("window", forKey: .type); try c.encode(seg, forKey: .seg); try c.encode(t, forKey: .t)
            try c.encode(frame, forKey: .frame); try c.encode(visible, forKey: .visible)
        }
    }
}

public struct Sentence: Codable, Sendable, Equatable {
    public var start, end: Double
    public var text: String
    public init(start: Double, end: Double, text: String) { self.start = start; self.end = end; self.text = text }
}

public struct ManifestFrame: Codable, Sendable, Equatable {
    public var index: Int
    public var time: Double
    public var reasons: [String]
    /// Relative to the recording folder, e.g. `frames/frame_01_00m00.5s.jpg`.
    public var file: String
    public var width, height: Int
    public var cursor: [Int]?
    public init(index: Int, time: Double, reasons: [String], file: String, width: Int, height: Int, cursor: [Int]? = nil) {
        self.index = index; self.time = time; self.reasons = reasons; self.file = file
        self.width = width; self.height = height; self.cursor = cursor
    }
}

public struct ManifestStroke: Codable, Sendable, Equatable {
    public var start, end: Double
    public var tool: StrokeTool
    public var bbox: [Int]
    public var description: String
    public var frameIndex: Int?
    public init(start: Double, end: Double, tool: StrokeTool, bbox: [Int], description: String, frameIndex: Int? = nil) {
        self.start = start; self.end = end; self.tool = tool; self.bbox = bbox
        self.description = description; self.frameIndex = frameIndex
    }
}

public enum TimelineItem: Codable, Sendable, Equatable {
    case speech(time: Double, end: Double, text: String)
    case drawing(time: Double, description: String)
    case clear(time: Double)
    case frame(time: Double, index: Int)
    case windowHidden(time: Double)

    public var time: Double {
        switch self {
        case let .speech(t, _, _), let .drawing(t, _), let .clear(t), let .frame(t, _), let .windowHidden(t): t
        }
    }

    private enum K: String, CodingKey { case kind, time, end, text, description, index }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: K.self)
        let t = try c.decode(Double.self, forKey: .time)
        switch try c.decode(String.self, forKey: .kind) {
        case "speech": self = .speech(time: t, end: try c.decode(Double.self, forKey: .end), text: try c.decode(String.self, forKey: .text))
        case "drawing": self = .drawing(time: t, description: try c.decode(String.self, forKey: .description))
        case "clear": self = .clear(time: t)
        case "frame": self = .frame(time: t, index: try c.decode(Int.self, forKey: .index))
        case "windowHidden": self = .windowHidden(time: t)
        case let other: throw DecodingError.dataCorruptedError(forKey: .kind, in: c, debugDescription: "unknown timeline kind \(other)")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: K.self)
        try c.encode(time, forKey: .time)
        switch self {
        case let .speech(_, end, text): try c.encode("speech", forKey: .kind); try c.encode(end, forKey: .end); try c.encode(text, forKey: .text)
        case let .drawing(_, d): try c.encode("drawing", forKey: .kind); try c.encode(d, forKey: .description)
        case .clear: try c.encode("clear", forKey: .kind)
        case let .frame(_, i): try c.encode("frame", forKey: .kind); try c.encode(i, forKey: .index)
        case .windowHidden: try c.encode("windowHidden", forKey: .kind)
        }
    }
}

public struct Manifest: Codable, Sendable, Equatable {
    public var id: String
    public var duration: Double
    public var mode: CaptureMode
    public var transcript: [Sentence]
    public var frames: [ManifestFrame]
    public var strokes: [ManifestStroke]
    public var timeline: [TimelineItem]
    public var note: String?
    public init(id: String, duration: Double, mode: CaptureMode, transcript: [Sentence], frames: [ManifestFrame],
                strokes: [ManifestStroke], timeline: [TimelineItem], note: String? = nil) {
        self.id = id; self.duration = duration; self.mode = mode; self.transcript = transcript
        self.frames = frames; self.strokes = strokes; self.timeline = timeline; self.note = note
    }
}

public enum RecordingStatus: String, Codable, Sendable { case processing, ready, processingFailed }

/// `meta.json`, written last: a recording folder without it doesn't exist yet for readers.
public struct RecordingMeta: Codable, Sendable, Equatable {
    public var id: String
    public var title: String
    public var createdAt: Date
    public var duration: Double
    public var mode: CaptureMode
    public var status: RecordingStatus
    public var sizeBytes: Int64
    public var deliveredToPID: Int32?
    public var deliveredToCwd: String?
    public var fetchedByCwd: String?
    public var error: String?
    public init(id: String, title: String, createdAt: Date, duration: Double, mode: CaptureMode, status: RecordingStatus,
                sizeBytes: Int64 = 0, deliveredToPID: Int32? = nil, deliveredToCwd: String? = nil,
                fetchedByCwd: String? = nil, error: String? = nil) {
        self.id = id; self.title = title; self.createdAt = createdAt; self.duration = duration; self.mode = mode
        self.status = status; self.sizeBytes = sizeBytes; self.deliveredToPID = deliveredToPID
        self.deliveredToCwd = deliveredToCwd; self.fetchedByCwd = fetchedByCwd; self.error = error
    }
}

/// What the user changed in the review panel.
public struct ReviewEdits: Codable, Sendable, Equatable {
    public var transcriptText: String?
    public var removedFrames: Set<Int>
    public var note: String?
    public init(transcriptText: String? = nil, removedFrames: Set<Int> = [], note: String? = nil) {
        self.transcriptText = transcriptText; self.removedFrames = removedFrames; self.note = note
    }
}
