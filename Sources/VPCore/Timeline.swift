import Foundation

/// Segment number → start time in the joined recording.
public func segmentOffsets(durations: [Int: Double]) -> [Int: Double] {
    var out: [Int: Double] = [:], acc = 0.0
    for seg in durations.keys.sorted() {
        out[seg] = acc
        acc += durations[seg]!
    }
    return out
}

public struct WindowSample: Sendable, Equatable, Codable {
    public var t: Double
    public var frame: Rect
    public var visible: Bool
    public init(t: Double, frame: Rect, visible: Bool) { self.t = t; self.frame = frame; self.visible = visible }
}

/// Where to crop the display at a given recording time.
public struct CropTimeline: Sendable {
    let mode: CaptureMode
    let display: Rect
    let area: Rect?
    let samples: [WindowSample]

    public init(mode: CaptureMode, display: Rect, area: Rect?, windowSamples: [WindowSample]) {
        self.mode = mode; self.display = display; self.area = area
        self.samples = windowSamples.sorted { $0.t < $1.t }
    }

    /// nil when the target window was hidden at `t`.
    public func crop(at t: Double) -> Rect? {
        switch mode {
        case .screen: return display
        case .area: return area ?? display
        case .window:
            guard let s = samples.last(where: { $0.t <= t }) ?? samples.first else { return display }
            return s.visible ? s.frame : nil
        }
    }
}

/// Screen point → pixel in a frame image of size `frameW`×`frameH` showing `crop`; nil if outside.
public func toFramePixels(_ p: Point, crop: Rect, frameW: Int, frameH: Int) -> [Int]? {
    let x = (p.x - crop.x) / crop.w, y = (p.y - crop.y) / crop.h
    guard (0...1).contains(x), (0...1).contains(y) else { return nil }
    return [Int((x * Double(frameW)).rounded()), Int((y * Double(frameH)).rounded())]
}

/// Frame image size for a crop: long edge at most `longEdge`, even numbers, never upscaled.
public func frameSize(cropW: Double, cropH: Double, longEdge: Int = 1568) -> (w: Int, h: Int) {
    let scale = min(1, Double(longEdge) / max(cropW, cropH))
    func even(_ v: Double) -> Int { max(2, Int((v / 2).rounded()) * 2) }
    return (even(cropW * scale), even(cropH * scale))
}

/// Text anchor for a stroke (port of `describe_stroke` for the pen).
public func describeStroke(_ pts: [[Int]], tool: StrokeTool) -> (bbox: [Int], text: String) {
    let xs = pts.map { $0[0] }, ys = pts.map { $0[1] }
    let bbox = [xs.min()!, ys.min()!, xs.max()!, ys.max()!]
    let (start, end) = (pts.first!, pts.last!)
    switch tool {
    case .arrow: return (bbox, "drew an arrow from (\(start[0]),\(start[1])) to (\(end[0]),\(end[1]))")
    case .box: return (bbox, "boxed the area (\(bbox[0]),\(bbox[1]))–(\(bbox[2]),\(bbox[3]))")
    case .pen:
        let bw = Double(bbox[2] - bbox[0]), bh = Double(bbox[3] - bbox[1])
        let gap = hypot(Double(start[0] - end[0]), Double(start[1] - end[1]))
        if pts.count > 8 && gap < 0.3 * max(bw, bh, 1) && min(bw, bh) > 15 {
            return (bbox, "circled the area (\(bbox[0]),\(bbox[1]))–(\(bbox[2]),\(bbox[3]))")
        }
        // A hand-drawn loop that doesn't close: the path is far longer than the gap between its ends.
        let path = zip(pts, pts.dropFirst()).reduce(0.0) { $0 + hypot(Double($1.1[0] - $1.0[0]), Double($1.1[1] - $1.0[1])) }
        if pts.count > 8 && path > 1.8 * max(gap, 1) && min(bw, bh) > 15 {
            return (bbox, "drew a curved mark around (\(bbox[0]),\(bbox[1]))–(\(bbox[2]),\(bbox[3]))")
        }
        if bh < 0.2 * max(bw, 1) {
            return (bbox, "underlined/marked horizontally from (\(bbox[0]),\(bbox[1])) to (\(bbox[2]),\(bbox[3]))")
        }
        return (bbox, "drew a line from (\(start[0]),\(start[1])) to (\(end[0]),\(end[1]))")
    }
}
