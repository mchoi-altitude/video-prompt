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

public struct FrameCandidate: Sendable, Equatable {
    public var time: Double
    public var reasons: [String]
}

private func round2(_ x: Double) -> Double { (x * 100).rounded() / 100 }

/// Picks keyframes by priority, keeping them `minGap` apart (port of `choose_frame_times`).
public func chooseFrameTimes(duration: Double, scenes: [Double], strokeEnds: [Double], sentences: [Sentence],
                             maxFrames: Int = 24, minGap: Double = 1.5) -> [FrameCandidate] {
    let end = max(0, duration - 0.3)
    var candidates: [(prio: Int, t: Double, reason: String)] = [(9, duration > 1 ? 0.5 : 0, "start"), (8, end, "end")]
    candidates += strokeEnds.map { (5, min($0 + 0.3, end), "drawing") }
    candidates += scenes.map { (3, min($0 + 0.4, end), "scene change") }
    candidates += sentences.map { (2, min(($0.start + $0.end) / 2, end), "narration") }

    var chosen: [FrameCandidate] = []
    // Stable sort by priority, highest first, like Python's sorted().
    for c in candidates.enumerated().sorted(by: { ($0.element.prio, -$0.offset) > ($1.element.prio, -$1.offset) }).map(\.element) {
        if let i = chosen.firstIndex(where: { abs($0.time - c.t) < minGap }) {
            if !chosen[i].reasons.contains(c.reason) { chosen[i].reasons.append(c.reason) }
            continue
        }
        if chosen.count >= maxFrames { continue }
        chosen.append(FrameCandidate(time: round2(c.t), reasons: [c.reason]))
    }
    return chosen.sorted { $0.time < $1.time }
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
        if bh < 0.2 * max(bw, 1) {
            return (bbox, "underlined/marked horizontally from (\(bbox[0]),\(bbox[1])) to (\(bbox[2]),\(bbox[3]))")
        }
        return (bbox, "drew a line from (\(start[0]),\(start[1])) to (\(end[0]),\(end[1]))")
    }
}

public struct CursorSample: Sendable, Equatable {
    public var t: Double
    public var p: [Int]
    public init(t: Double, p: [Int]) { self.t = t; self.p = p }
}

/// Cursor position shown in a frame at `t` (port of `_cursor_at`): the latest sample no more
/// than 0.2 s after and 1.5 s before `t`.
public func cursor(at t: Double, in samples: [CursorSample]) -> [Int]? {
    var best: [Int]?
    for s in samples.sorted(by: { $0.t < $1.t }) {
        if s.t > t + 0.2 { break }
        if t - s.t <= 1.5 { best = s.p }
    }
    return best
}
