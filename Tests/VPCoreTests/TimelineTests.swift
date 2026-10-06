import Foundation
import Testing
@testable import VPCore

@Test func offsetsSumEarlierSegments() {
    #expect(segmentOffsets(durations: [1: 2.5, 2: 4, 3: 1]) == [1: 0, 2: 2.5, 3: 6.5])
}

@Test func framesKeepGapAndPriority() {
    let f = chooseFrameTimes(duration: 12, scenes: [0.6, 5.0], strokeEnds: [4.0],
                             sentences: [Sentence(start: 2, end: 4, text: "See this.")])
    // scene 1.0 merges into start; scene 5.4 and narration 3.0 merge into drawing 4.3
    #expect(f.map(\.time) == [0.5, 4.3, 11.7])
    #expect(f[0].reasons == ["start", "scene change"])
    #expect(f[1].reasons == ["drawing", "scene change", "narration"])
}

@Test func framesCappedAt24() {
    let s = (0..<60).map { Sentence(start: Double($0) * 2, end: Double($0) * 2 + 1, text: "x.") }
    let f = chooseFrameTimes(duration: 121, scenes: [], strokeEnds: [], sentences: s)
    #expect(f.count == 24)
    #expect(f.first?.reasons.first == "start")
    #expect(f.contains { $0.reasons.contains("end") })
}

@Test func shortRecordingStartsAtZero() {
    #expect(chooseFrameTimes(duration: 0.8, scenes: [], strokeEnds: [], sentences: []).first?.time == 0)
}

private let display = Rect(x: 0, y: 0, w: 1440, h: 900)

@Test func cropFollowsResizedWindow() {
    let c = CropTimeline(mode: .window, display: display, area: nil, windowSamples: [
        WindowSample(t: 0, frame: Rect(x: 40, y: 64, w: 740, h: 560), visible: true),
        WindowSample(t: 6, frame: Rect(x: 40, y: 64, w: 640, h: 560), visible: true)])
    #expect(c.crop(at: 5.9)?.w == 740)
    #expect(c.crop(at: 6.0)?.w == 640)
}

@Test func cropSkipsHiddenWindow() {
    let c = CropTimeline(mode: .window, display: display, area: nil, windowSamples: [
        WindowSample(t: 0, frame: Rect(x: 40, y: 64, w: 740, h: 560), visible: true),
        WindowSample(t: 3, frame: Rect(x: 40, y: 64, w: 740, h: 560), visible: false),
        WindowSample(t: 5, frame: Rect(x: 40, y: 64, w: 740, h: 560), visible: true)])
    #expect(c.crop(at: 3.5) == nil)
    #expect(c.crop(at: 5.5) != nil)
}

@Test func cropBeforeFirstSampleUsesFirst() {
    let c = CropTimeline(mode: .window, display: display, area: nil,
                         windowSamples: [WindowSample(t: 1, frame: Rect(x: 1, y: 2, w: 3, h: 4), visible: true)])
    #expect(c.crop(at: 0) == Rect(x: 1, y: 2, w: 3, h: 4))
}

@Test func screenAndAreaModes() {
    let area = Rect(x: 10, y: 10, w: 100, h: 50)
    #expect(CropTimeline(mode: .screen, display: display, area: nil, windowSamples: []).crop(at: 3) == display)
    #expect(CropTimeline(mode: .area, display: display, area: area, windowSamples: []).crop(at: 3) == area)
}

@Test func pointMapsToWindowRelativePixels() {
    #expect(toFramePixels(Point(x: 80, y: 534), crop: Rect(x: 40, y: 64, w: 740, h: 560), frameW: 740, frameH: 560) == [40, 470])
    #expect(toFramePixels(Point(x: 900, y: 534), crop: Rect(x: 40, y: 64, w: 740, h: 560), frameW: 740, frameH: 560) == nil)
}

@Test func frameSizeNeverUpscales() {
    #expect(frameSize(cropW: 740, cropH: 560) == (740, 560))
    #expect(frameSize(cropW: 3136, cropH: 1800) == (1568, 900))
}

@Test func circleIsDescribedAsCircled() {
    let pts = (0..<12).map { i -> [Int] in
        let a = Double(i) / 12 * 2 * .pi
        return [Int(135 + 88 * cos(a)), Int(554 + 40 * sin(a))]
    }
    let d = describeStroke(pts, tool: .pen)
    #expect(d.text.hasPrefix("circled the area ("))
    #expect(d.bbox == [47, 514, 223, 594])
}

@Test func arrowAndBoxDescriptions() {
    #expect(describeStroke([[10, 20], [300, 22]], tool: .arrow).text == "drew an arrow from (10,20) to (300,22)")
    #expect(describeStroke([[10, 20], [300, 80]], tool: .box).text == "boxed the area (10,20)–(300,80)")
}

@Test func cursorNearTime() {
    let s = [CursorSample(t: 1, p: [5, 5]), CursorSample(t: 2, p: [9, 9])]
    #expect(cursor(at: 2.1, in: s) == [9, 9])
    #expect(cursor(at: 9, in: s) == nil)
}
