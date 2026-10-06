import Foundation
import Testing
@testable import VPCore

@Test func offsetsSumEarlierSegments() {
    #expect(segmentOffsets(durations: [1: 2.5, 2: 4, 3: 1]) == [1: 0, 2: 2.5, 3: 6.5])
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


@Test func openCircleIsNotALine() {
    // A circle that stops 3/4 of the way round (like a quick hand-drawn loop): ends far apart.
    let pts = (0..<30).map { i -> [Int] in
        let a = Double(i) / 30 * 1.5 * .pi
        return [Int(500 + 70 * cos(a)), Int(480 + 70 * sin(a))]
    }
    let d = describeStroke(pts, tool: .pen)
    #expect(!d.text.hasPrefix("drew a line"))
    #expect(d.text.hasPrefix("circled the area (") || d.text.hasPrefix("drew a curved mark around ("))
}

@Test func straightStrokeIsStillALine() {
    let pts = (0..<20).map { [100 + $0 * 10, 200 + $0 * 6] }
    #expect(describeStroke(pts, tool: .pen).text.hasPrefix("drew a line from (100,200)"))
}
