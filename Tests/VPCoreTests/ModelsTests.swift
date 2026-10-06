import Foundation
import Testing
@testable import VPCore

@Test func rawEventRoundTripsWithTypeDiscriminator() throws {
    let e = RawEvent.window(seg: 1, t: 2.5, frame: Rect(x: 40, y: 64, w: 740, h: 560), visible: true)
    let data = try JSON.encoder.encode(e)
    #expect(String(decoding: data, as: UTF8.self).contains("\"type\" : \"window\""))
    #expect(try JSON.decoder.decode(RawEvent.self, from: data) == e)
}

@Test func strokeEventRoundTrips() throws {
    let e = RawEvent.stroke(seg: 2, t0: 1, t1: 2, points: [Point(x: 1, y: 2)], tool: .arrow)
    #expect(try JSON.decoder.decode(RawEvent.self, from: JSON.encoder.encode(e)) == e)
}

@Test func timelineItemRoundTripsWithKind() throws {
    let items: [TimelineItem] = [.speech(time: 1, end: 2, text: "Hi."), .drawing(time: 2, description: "x"),
                                 .clear(time: 3), .click(time: 4, x: 10, y: 20), .pause(time: 4.5), .windowHidden(time: 5)]
    let data = try JSON.encoder.encode(items)
    #expect(String(decoding: data, as: UTF8.self).contains("\"kind\" : \"windowHidden\""))
    #expect(try JSON.decoder.decode([TimelineItem].self, from: data) == items)
}

@Test func atomicWriteLeavesNoTempFile() throws {
    let dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    try writeJSON(Sentence(start: 0, end: 1, text: "Hi."), to: dir.appending(path: "s.json"))
    #expect(try FileManager.default.contentsOfDirectory(atPath: dir.path) == ["s.json"])
    #expect(try readJSON(Sentence.self, from: dir.appending(path: "s.json")).text == "Hi.")
}

@Test func undoEventRoundTrips() throws {
    let e = RawEvent.undo(seg: 1, t: 3)
    #expect(try JSON.decoder.decode(RawEvent.self, from: JSON.encoder.encode(e)) == e)
}

@Test func clickEventRoundTrips() throws {
    let e = RawEvent.click(seg: 1, t: 2, p: Point(x: 3, y: 4))
    #expect(try JSON.decoder.decode(RawEvent.self, from: JSON.encoder.encode(e)) == e)
}
