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
private func makeRaw(_ paths: Paths, events: [RawEvent], segments: Int = 1, corrupt: Bool = false) async throws -> String {
    let id = try paths.newRecordingID(now: createdAt, calendar: utc)
    let raw = paths.raw(id)
    try FileManager.default.createDirectory(at: raw, withIntermediateDirectories: true)
    try writeJSON(RawSession(mode: .window, display: display, windowTitle: "Settings", createdAt: createdAt), to: raw.appending(path: "session.json"))
    let lines = try events.map { String(decoding: try JSONEncoder().encode($0), as: UTF8.self) }.joined(separator: "\n")
    try Data(lines.utf8).write(to: raw.appending(path: "events.jsonl"))
    for s in 1...segments {
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
                                                        .cursor(seg: 1, t: 4.1, p: Point(x: 80, y: 280))])
    let store = Store(paths: paths)
    let meta = try await Processor(store: store, paths: paths, transcriber: StubTranscriber(result: stubWords), calendar: utc).process(id: id)
    #expect(meta.status == .ready)
    #expect(meta.title == "So, the settings page")
    let m = try store.manifest(id)
    #expect(m.frames.filter { $0.time < 6 }.allSatisfy { $0.width == 400 })
    #expect(m.frames.filter { $0.time >= 6 }.allSatisfy { $0.width == 300 })
    #expect(m.frames.contains { $0.time >= 6 })
    #expect(m.strokes.first?.description.hasPrefix("circled the area (") == true)
    #expect(m.strokes.first?.bbox == [20, 230, 100, 270])
    #expect(m.frames.first { $0.reasons.contains("drawing") }?.cursor == [60, 250])
    #expect(FileManager.default.fileExists(atPath: paths.recording(id).appending(path: "prompt.md").path))
    #expect(!FileManager.default.fileExists(atPath: paths.raw(id).path))
    #expect(m.frames.allSatisfy { FileManager.default.fileExists(atPath: paths.recording(id).appending(path: $0.file).path) })
    #expect(meta.sizeBytes > 0)
}

@Test func processesSilentRecording() async throws {
    let paths = tempPathsForProcess()
    let id = try await makeRaw(paths, events: resize)
    let meta = try await Processor(store: Store(paths: paths), paths: paths, transcriber: nil, calendar: utc).process(id: id)
    #expect(meta.status == .ready)
    #expect(meta.title == "Recording 14:14")
    let prompt = try String(contentsOf: paths.recording(id).appending(path: "prompt.md"), encoding: .utf8)
    #expect(prompt.contains("_(no narration was detected)_"))
}

@Test func hiddenWindowFrameIsSkipped() async throws {
    let paths = tempPathsForProcess()
    let id = try await makeRaw(paths, events: [
        .window(seg: 1, t: 0, frame: win, visible: true),
        .window(seg: 1, t: 3, frame: win, visible: false),
        .window(seg: 1, t: 5, frame: win, visible: true)])
    // Sentence midpoint at 4.0 asks for a frame while the window is hidden.
    let words = [Word(start: 3.5, end: 4.5, text: " Hidden now.")]
    _ = try await Processor(store: Store(paths: paths), paths: paths, transcriber: StubTranscriber(result: words), calendar: utc).process(id: id)
    let m = try Store(paths: paths).manifest(id)
    #expect(!m.frames.contains { $0.time >= 3 && $0.time < 5 })
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
