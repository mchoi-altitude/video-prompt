import Foundation
import Testing
import VPCore
@testable import VPProcess
import VPTestSupport

struct StubTranscriber: Transcriber {
    var result: [Word]
    func words(wav: URL) async throws -> [Word] { result }
}

private var utc: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c }
private let createdAt = ISO8601DateFormatter().date(from: "2026-10-06T14:14:02Z")!
private let display = Rect(x: 0, y: 0, w: 640, h: 400)
private let win = Rect(x: 20, y: 30, w: 400, h: 300)

private let stubWords = [
    Word(start: 1, end: 1.5, text: " So,"), Word(start: 1.6, end: 2.5, text: " the settings page."),
    Word(start: 3, end: 3.6, text: " See this"), Word(start: 3.7, end: 5.2, text: " Save button?"),
    Word(start: 8, end: 9.5, text: " Make it blue."),
]

/// Circle of 12 points around the window-relative point (60, 250).
private func circle() -> [Point] {
    (0..<12).map { i in
        let a = Double(i) / 12 * 2 * .pi
        return Point(x: win.x + 60 + 40 * cos(a), y: win.y + 250 + 20 * sin(a))
    }
}

/// Raw folder: one 12 s segment (needs `sayText` for an audio track), session + events.
private func makeRaw(_ paths: Paths, events: [RawEvent], segments: Int = 1, segmentNumbers: [Int]? = nil,
                     corrupt: Bool = false) async throws -> String {
    let id = try paths.newRecordingID(now: createdAt, calendar: utc)
    let raw = paths.raw(id)
    try FileManager.default.createDirectory(at: raw, withIntermediateDirectories: true)
    try writeJSON(RawSession(mode: .window, display: display, windowTitle: "Settings", createdAt: createdAt), to: raw.appending(path: "session.json"))
    let lines = try events.map { String(decoding: try JSONEncoder().encode($0), as: UTF8.self) }.joined(separator: "\n")
    try Data(lines.utf8).write(to: raw.appending(path: "events.jsonl"))
    for s in segmentNumbers ?? Array(1...segments) {
        let url = raw.appending(path: String(format: "seg_%03d.mov", s))
        if corrupt { try Data("not a movie".utf8).write(to: url); continue }
        try await makeColorVideo(url: url, size: (640, 400),
                                 blocks: [ColorBlock(6, (250, 250, 250)), ColorBlock(6, (30, 30, 30))], sayText: "Testing.")
    }
    return id
}

private let resize: [RawEvent] = [
    .window(seg: 1, t: 0, frame: win, visible: true),
    .window(seg: 1, t: 6, frame: Rect(x: 20, y: 30, w: 300, h: 300), visible: true),
]

@Test func processesWindowRecordingEndToEnd() async throws {
    let paths = tempPathsForProcess()
    let id = try await makeRaw(paths, events: resize + [.stroke(seg: 1, t0: 2.8, t1: 4.0, points: circle(), tool: .pen),
                                                        .click(seg: 1, t: 4.1, p: Point(x: 80, y: 280))])
    let store = Store(paths: paths)
    let meta = try await Processor(store: store, paths: paths, transcriber: StubTranscriber(result: stubWords), calendar: utc).process(id: id)
    #expect(meta.status == .reviewing)
    #expect(meta.title == "So, the settings page")
    let m = try store.manifest(id)
    // The video is the largest the window got (400×300); after the resize the rest is padded.
    #expect(m.video.width == 400 && m.video.height == 300 && m.video.fps == 10)
    #expect(abs(m.duration - 12) < 0.3)
    #expect(m.strokes.first?.description.hasPrefix("circled the area (") == true)
    #expect(m.strokes.first?.bbox == [20, 230, 100, 270])
    #expect(m.clicks == [ManifestClick(t: 4.1, x: 60, y: 250)])
    #expect(FileManager.default.fileExists(atPath: paths.recording(id).appending(path: "timeline.md").path))
    #expect(!FileManager.default.fileExists(atPath: paths.raw(id).path))
    for f in ["video.mp4", "overview.jpg", "timeline.md"] {
        #expect(FileManager.default.fileExists(atPath: paths.recording(id).appending(path: f).path))
    }
    let timeline = try String(contentsOf: paths.recording(id).appending(path: "timeline.md"), encoding: .utf8)
    #expect(timeline.contains("🖱 Clicked at (60,250)"))
    #expect(timeline.contains("circled the area"))
    #expect(meta.sizeBytes > 0)
}

@Test func processesSilentRecording() async throws {
    let paths = tempPathsForProcess()
    let id = try await makeRaw(paths, events: resize)
    let meta = try await Processor(store: Store(paths: paths), paths: paths, transcriber: nil, calendar: utc).process(id: id)
    #expect(meta.status == .reviewing)
    #expect(meta.title == "Recording 14:14")
    let prompt = try String(contentsOf: paths.recording(id).appending(path: "timeline.md"), encoding: .utf8)
    #expect(prompt.contains("_(no narration was detected)_"))
}

@Test func hiddenWindowIsMarked() async throws {
    let paths = tempPathsForProcess()
    let id = try await makeRaw(paths, events: [
        .window(seg: 1, t: 0, frame: win, visible: true),
        .window(seg: 1, t: 3, frame: win, visible: false),
        .window(seg: 1, t: 5, frame: win, visible: true)])
    let words = [Word(start: 3.5, end: 4.5, text: " Hidden now.")]
    _ = try await Processor(store: Store(paths: paths), paths: paths, transcriber: StubTranscriber(result: words), calendar: utc).process(id: id)
    let m = try Store(paths: paths).manifest(id)
    #expect(m.timeline.contains { if case .windowHidden = $0 { true } else { false } })
}

@Test func pausedSegmentsMapEventTimes() async throws {
    let paths = tempPathsForProcess()
    // Stroke in segment 2 at t=1 → 13 s into the joined 24 s recording.
    let id = try await makeRaw(paths, events: [.window(seg: 1, t: 0, frame: win, visible: true),
                                               .stroke(seg: 2, t0: 0.5, t1: 1, points: circle(), tool: .pen)], segments: 2)
    _ = try await Processor(store: Store(paths: paths), paths: paths, transcriber: nil, calendar: utc).process(id: id)
    let m = try Store(paths: paths).manifest(id)
    #expect(abs((m.strokes.first?.end ?? 0) - 13) < 0.2)
    #expect(abs(m.duration - 24) < 0.3)
    #expect(m.timeline.contains { if case let .pause(t) = $0 { abs(t - 12) < 0.2 } else { false } })
}

@Test func failureKeepsRaw() async throws {
    let paths = tempPathsForProcess()
    let id = try await makeRaw(paths, events: resize, corrupt: true)
    let store = Store(paths: paths)
    await #expect(throws: (any Error).self) {
        try await Processor(store: store, paths: paths, transcriber: nil, calendar: utc).process(id: id)
    }
    #expect(try store.meta(id).status == .processingFailed)
    #expect(try store.meta(id).error != nil)
    #expect(FileManager.default.fileExists(atPath: paths.raw(id).path))
}

func tempPathsForProcess() -> Paths { Paths(root: tempDir()) }

@Test func windowPartlyOffScreenMapsCoordinates() async throws {
    let paths = tempPathsForProcess()
    // 100 pt of the window hang off the left edge of the 640×400 display.
    let id = try await makeRaw(paths, events: [
        .window(seg: 1, t: 0, frame: Rect(x: -100, y: 30, w: 400, h: 300), visible: true),
        .click(seg: 1, t: 0.4, p: Point(x: 50, y: 280))])
    _ = try await Processor(store: Store(paths: paths), paths: paths, transcriber: nil, calendar: utc).process(id: id)
    let m = try Store(paths: paths).manifest(id)
    #expect(m.video.width == 300)                       // only the on-screen part
    #expect(m.clicks.first.map { [$0.x, $0.y] } == [50, 250])
}

@Test func segmentNumbersComeFromFileNames() async throws {
    let paths = tempPathsForProcess()
    // seg_002 is missing (an empty segment the app dropped): seg 3 starts right after seg 1.
    let id = try await makeRaw(paths, events: [.window(seg: 1, t: 0, frame: win, visible: true),
                                               .stroke(seg: 3, t0: 0.5, t1: 1, points: circle(), tool: .pen)],
                               segmentNumbers: [1, 3])
    _ = try await Processor(store: Store(paths: paths), paths: paths, transcriber: nil, calendar: utc).process(id: id)
    #expect(abs((try Store(paths: paths).manifest(id).strokes.first?.end ?? 0) - 13) < 0.2)
}

@Test func undoneStrokeIsNotDescribed() async throws {
    let paths = tempPathsForProcess()
    let id = try await makeRaw(paths, events: resize + [
        .stroke(seg: 1, t0: 2.8, t1: 4.0, points: circle(), tool: .pen),
        .stroke(seg: 1, t0: 5.0, t1: 5.5, points: circle(), tool: .arrow),
        .undo(seg: 1, t: 5.8)])
    _ = try await Processor(store: Store(paths: paths), paths: paths, transcriber: nil, calendar: utc).process(id: id)
    let m = try Store(paths: paths).manifest(id)
    #expect(m.strokes.map(\.tool) == [.pen])          // the arrow was undone
}

@Test func keepRawWhenAsked() async throws {
    let paths = tempPathsForProcess()
    let id = try await makeRaw(paths, events: resize)
    _ = try await Processor(store: Store(paths: paths), paths: paths, transcriber: nil, calendar: utc, keepRaw: true).process(id: id)
    #expect(FileManager.default.fileExists(atPath: paths.raw(id).appending(path: "seg_001.mov").path))
}
