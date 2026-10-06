import Foundation

/// Frames per second for capture and the recording video (spec §2 #19). The one place to change it.
public let VideoFPS = 10

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
    /// A left-mouse click (global point).
    case click(seg: Int, t: Double, p: Point)
    /// The user undid their most recent stroke.
    case undo(seg: Int, t: Double)
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
        case "click": self = .click(seg: seg, t: try c.decode(Double.self, forKey: .t), p: try c.decode(Point.self, forKey: .p))
        case "undo": self = .undo(seg: seg, t: try c.decode(Double.self, forKey: .t))
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
        case let .click(seg, t, p):
            try c.encode("click", forKey: .type); try c.encode(seg, forKey: .seg); try c.encode(t, forKey: .t); try c.encode(p, forKey: .p)
        case let .undo(seg, t):
            try c.encode("undo", forKey: .type); try c.encode(seg, forKey: .seg); try c.encode(t, forKey: .t)
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

public struct ManifestStroke: Codable, Sendable, Equatable {
    public var start, end: Double
    public var tool: StrokeTool
    public var bbox: [Int]
    public var description: String
    public init(start: Double, end: Double, tool: StrokeTool, bbox: [Int], description: String) {
        self.start = start; self.end = end; self.tool = tool; self.bbox = bbox; self.description = description
    }
}

/// A click, in pixels of the recording video.
public struct ManifestClick: Codable, Sendable, Equatable {
    public var t: Double
    public var x, y: Int
    public init(t: Double, x: Int, y: Int) { self.t = t; self.x = x; self.y = y }
}

/// What happened to the narration: shown to Claude so silence and "no speech engine" aren't confused.
public enum TranscriptionState: String, Codable, Sendable {
    case ok
    /// There was audio, but no speech in it.
    case noSpeech
    /// No audio track (microphone off or denied).
    case noAudio
    /// Speech-to-text isn't installed on this Mac.
    case unavailable
}

/// The window-only recording video.
public struct VideoInfo: Codable, Sendable, Equatable {
    public var file: String
    public var width, height, fps: Int
    public var hasAudio: Bool
    public init(file: String, width: Int, height: Int, fps: Int, hasAudio: Bool) {
        self.file = file; self.width = width; self.height = height; self.fps = fps; self.hasAudio = hasAudio
    }
}

public enum TimelineItem: Codable, Sendable, Equatable {
    case speech(time: Double, end: Double, text: String)
    case drawing(time: Double, description: String)
    case clear(time: Double)
    case click(time: Double, x: Int, y: Int)
    case pause(time: Double)
    case windowHidden(time: Double)

    public var time: Double {
        switch self {
        case let .speech(t, _, _), let .drawing(t, _), let .clear(t), let .click(t, _, _), let .pause(t), let .windowHidden(t): t
        }
    }

    private enum K: String, CodingKey { case kind, time, end, text, description, x, y }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: K.self)
        let t = try c.decode(Double.self, forKey: .time)
        switch try c.decode(String.self, forKey: .kind) {
        case "speech": self = .speech(time: t, end: try c.decode(Double.self, forKey: .end), text: try c.decode(String.self, forKey: .text))
        case "drawing": self = .drawing(time: t, description: try c.decode(String.self, forKey: .description))
        case "clear": self = .clear(time: t)
        case "click": self = .click(time: t, x: try c.decode(Int.self, forKey: .x), y: try c.decode(Int.self, forKey: .y))
        case "pause": self = .pause(time: t)
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
        case let .click(_, x, y): try c.encode("click", forKey: .kind); try c.encode(x, forKey: .x); try c.encode(y, forKey: .y)
        case .pause: try c.encode("pause", forKey: .kind)
        case .windowHidden: try c.encode("windowHidden", forKey: .kind)
        }
    }
}

public struct Manifest: Codable, Sendable, Equatable {
    public var id: String
    public var duration: Double
    public var mode: CaptureMode
    public var transcript: [Sentence]
    public var transcription: TranscriptionState
    public var video: VideoInfo
    /// Contact sheet file, relative to the recording folder.
    public var overview: String
    public var overviewSecondsPerTile: Int
    public var strokes: [ManifestStroke]
    public var clicks: [ManifestClick]
    public var timeline: [TimelineItem]
    public var note: String?
    public init(id: String, duration: Double, mode: CaptureMode, transcript: [Sentence], transcription: TranscriptionState = .ok,
                video: VideoInfo, overview: String,
                overviewSecondsPerTile: Int, strokes: [ManifestStroke], clicks: [ManifestClick], timeline: [TimelineItem], note: String? = nil) {
        self.id = id; self.duration = duration; self.mode = mode; self.transcript = transcript
        self.transcription = transcript.isEmpty && transcription == .ok ? .noSpeech : transcription; self.video = video
        self.overview = overview; self.overviewSecondsPerTile = overviewSecondsPerTile; self.strokes = strokes
        self.clicks = clicks; self.timeline = timeline; self.note = note
    }
}

/// processing → reviewing (frames and prompt exist; the user hasn't saved or sent yet) → ready.
/// Only `ready` recordings are visible to Claude.
public enum RecordingStatus: String, Codable, Sendable { case processing, reviewing, ready, processingFailed }

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
    public var note: String?
    public init(transcriptText: String? = nil, note: String? = nil) {
        self.transcriptText = transcriptText; self.note = note
    }
}
