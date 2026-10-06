import Foundation
import Testing
import VPCore
@testable import VPApp

private func p(_ x: Double, _ y: Double) -> Point { Point(x: x, y: y) }

@Test func penKeepsAllPoints() {
    let m = DrawingModel()
    m.begin(p(0, 0), host: 1); m.extend(p(1, 1)); m.extend(p(2, 2))
    #expect(m.end(host: 2)?.points.count == 3)
}

@Test func arrowKeepsEnds() {
    let m = DrawingModel(); m.tool = .arrow
    m.begin(p(0, 0), host: 1); m.extend(p(1, 1)); m.extend(p(9, 9))
    #expect(m.end(host: 2)?.points == [p(0, 0), p(9, 9)])
}

@Test func clickIsNotAStroke() {
    let m = DrawingModel()
    m.begin(p(0, 0), host: 1)
    #expect(m.end(host: 1.1) == nil)
    #expect(m.strokes.isEmpty)
}

@Test func fadesAfterThreeSeconds() {
    let m = DrawingModel()
    m.begin(p(0, 0), host: 0); m.extend(p(5, 5))
    let s = m.end(host: 10)!
    #expect(m.opacity(of: s, now: 12.9) == 1)
    #expect(abs(m.opacity(of: s, now: 13.25) - 0.5) < 0.01)
    #expect(m.opacity(of: s, now: 13.5) == 0)
    m.prune(now: 13.6)
    #expect(m.strokes.isEmpty)
}

@Test func pinnedNeverFades() {
    let m = DrawingModel(); m.fades = false
    m.begin(p(0, 0), host: 0); m.extend(p(5, 5))
    let s = m.end(host: 1)!
    #expect(m.opacity(of: s, now: 1000) == 1)
}

@Test func undoRemovesLast() {
    let m = DrawingModel()
    for i in 0..<2 { m.begin(p(0, 0), host: Double(i)); m.extend(p(1, 1)); _ = m.end(host: Double(i) + 0.5) }
    m.undo()
    #expect(m.strokes.count == 1)
}

@Test func clearRemovesAll() {
    let m = DrawingModel()
    m.begin(p(0, 0), host: 0); m.extend(p(1, 1)); _ = m.end(host: 1)
    m.clear()
    #expect(m.strokes.isEmpty)
}
