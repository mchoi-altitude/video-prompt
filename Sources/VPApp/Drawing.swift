import Foundation
import VPCore

public struct Stroke: Equatable, Sendable {
    public var tool: StrokeTool
    /// Global top-left points. Arrow and box keep only [start, end].
    public var points: [Point]
    public var startHost: Double
    public var endHost: Double?
}

/// The marks on screen while recording: tools, fading, undo and clear.
public final class DrawingModel: @unchecked Sendable {
    public var tool: StrokeTool = .pen
    public var fades = true
    public private(set) var strokes: [Stroke] = []
    private var current: Stroke?

    /// A mark stays fully visible this long after it's finished, then fades over `fadeOut`.
    public static let hold = 3.0, fadeOut = 0.5

    public init() {}

    /// The stroke being drawn plus the finished ones, for the overlay to paint.
    public var visible: [Stroke] { strokes + (current.map { [$0] } ?? []) }

    public func begin(_ p: Point, host: Double) { current = Stroke(tool: tool, points: [p], startHost: host) }

    public func extend(_ p: Point) {
        guard var s = current else { return }
        if s.tool == .pen { s.points.append(p) } else { s.points = [s.points[0], p] }
        current = s
    }

    /// Finishes the stroke being drawn; nil for a click that never moved.
    public func end(host: Double) -> Stroke? {
        defer { current = nil }
        guard var s = current, s.points.count >= 2 else { return nil }
        s.endHost = host
        strokes.append(s)
        return s
    }

    public func opacity(of s: Stroke, now: Double) -> Double {
        guard fades, let end = s.endHost else { return 1 }
        let age = now - end
        if age <= Self.hold { return 1 }
        return max(0, 1 - (age - Self.hold) / Self.fadeOut)
    }

    public func prune(now: Double) { strokes.removeAll { opacity(of: $0, now: now) == 0 } }
    public func undo() { if !strokes.isEmpty { strokes.removeLast() } }
    public func clear() { strokes.removeAll(); current = nil }
}
