import Foundation
import Testing
import VPCore
import VPProcess
import VPTestSupport
@testable import VPApp

private let display = Rect(x: 0, y: 0, w: 640, h: 400)
private let win = Rect(x: 20, y: 30, w: 400, h: 300)

private func recorder() throws -> (RawRecorder, Paths) {
    let p = Paths(root: tempDir())
    let r = try RawRecorder(paths: p, session: RawSession(mode: .window, display: display, windowTitle: "Settings", createdAt: .now), now: .now)
    return (r, p)
}

private func events(_ p: Paths, _ id: String) throws -> [RawEvent] {
    try String(contentsOf: p.raw(id).appending(path: "events.jsonl"), encoding: .utf8)
        .split(whereSeparator: \.isNewline).map { try JSON.decoder.decode(RawEvent.self, from: Data($0.utf8)) }
}

@Test func firstSegmentIsOne() throws {
    let (r, p) = try recorder()
    #expect(r.beginSegment(hostTime: 100) == p.raw(r.id).appending(path: "seg_001.mov"))
    #expect(FileManager.default.fileExists(atPath: p.raw(r.id).appending(path: "session.json").path))
}

@Test func eventTimesAreSegmentRelative() throws {
    let (r, p) = try recorder()
    _ = r.beginSegment(hostTime: 100)
    r.log(.cursor(Point(x: 5, y: 6)), hostTime: 102.5)
    try r.close()
    #expect(try events(p, r.id) == [.cursor(seg: 1, t: 2.5, p: Point(x: 5, y: 6))])
}

@Test func eventsAfterResumeUseNewSegment() throws {
    let (r, p) = try recorder()
    _ = r.beginSegment(hostTime: 100)
    r.endSegment(hostTime: 105)
    #expect(r.beginSegment(hostTime: 200).lastPathComponent == "seg_002.mov")
    r.log(.window(win, visible: true), hostTime: 201)
    try r.close()
    #expect(try events(p, r.id) == [.window(seg: 2, t: 1, frame: win, visible: true)])
}

@Test func eventsWhilePausedAreDropped() throws {
    let (r, p) = try recorder()
    _ = r.beginSegment(hostTime: 100)
    r.endSegment(hostTime: 105)
    r.log(.clear, hostTime: 150)
    try r.close()
    #expect(try events(p, r.id).isEmpty)
}

@Test func strokeStartClampsToSegment() throws {
    let (r, p) = try recorder()
    _ = r.beginSegment(hostTime: 100)
    r.log(.stroke(startHost: 99, points: [Point(x: 1, y: 1), Point(x: 2, y: 2)], tool: .arrow), hostTime: 101)
    try r.close()
    #expect(try events(p, r.id) == [.stroke(seg: 1, t0: 0, t1: 1, points: [Point(x: 1, y: 1), Point(x: 2, y: 2)], tool: .arrow)])
}

@Test func processorAcceptsRecorderOutput() async throws {
    let (r, p) = try recorder()
    let seg = r.beginSegment(hostTime: 0)
    r.log(.window(win, visible: true), hostTime: 0)
    try await makeColorVideo(url: seg, size: (640, 400), blocks: [ColorBlock(3, (200, 200, 200))])
    r.endSegment(hostTime: 3)
    try r.close()
    let meta = try await Processor(store: Store(paths: p), paths: p, transcriber: nil).process(id: r.id)
    #expect(meta.status == .reviewing)
}

@Test func clickIsLogged() throws {
    let (r, p) = try recorder()
    _ = r.beginSegment(hostTime: 10)
    r.log(.click(Point(x: 812, y: 96)), hostTime: 12.5)
    try r.close()
    #expect(try events(p, r.id) == [.click(seg: 1, t: 2.5, p: Point(x: 812, y: 96))])
}
