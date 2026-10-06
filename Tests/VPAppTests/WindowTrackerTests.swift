import Foundation
import Testing
import VPCore
@testable import VPApp

private func w(_ id: UInt32, _ owner: String, _ frame: Rect, title: String? = nil, layer: Int = 0, onScreen: Bool = true) -> WindowInfo {
    WindowInfo(id: id, owner: owner, title: title, frame: frame, layer: layer, onScreen: onScreen)
}
private let big = Rect(x: 0, y: 0, w: 800, h: 600)

@Test func picksFrontmostChrome() {
    let ws = [w(1, "Safari", big), w(2, "Google Chrome", big, title: "Settings"), w(3, "Google Chrome", big, title: "Other")]
    #expect(frontmostChromeWindow(ws)?.id == 2)
}

@Test func noChromeMeansNoWindowItem() {
    #expect(frontmostChromeWindow([w(1, "Safari", big)]) == nil)
}

@Test func skipsTinyChromePopupsAndOffscreen() {
    let ws = [w(1, "Google Chrome", Rect(x: 0, y: 0, w: 300, h: 40)), w(2, "Google Chrome", big, onScreen: false),
              w(3, "Google Chrome", big, layer: 25), w(4, "Google Chrome", big)]
    #expect(frontmostChromeWindow(ws)?.id == 4)
}

@Test func windowAtPoint() {
    let ws = [w(1, "Dock", big, layer: 20), w(2, "Notes", Rect(x: 100, y: 100, w: 200, h: 200)), w(3, "Finder", big)]
    #expect(window(at: Point(x: 150, y: 150), in: ws)?.id == 2)
    #expect(window(at: Point(x: 10, y: 10), in: ws)?.id == 3)
}

final class FakeSource: WindowSource, @unchecked Sendable {
    var list: [WindowInfo] = []
    func windows() -> [WindowInfo] { list }
}

@Test func logsFirstAndChangesOnly() {
    let src = FakeSource()
    var logs: [(Rect, Bool)] = []
    let t = WindowTracker(source: src, windowID: 7) { logs.append(($0, $1)) }
    src.list = [w(7, "Google Chrome", big)]
    t.sample(); t.sample(); t.sample()
    src.list = [w(7, "Google Chrome", Rect(x: 0, y: 0, w: 640, h: 600))]
    t.sample()
    #expect(logs.count == 2)
    #expect(logs[1].0.w == 640)
}

@Test func minimizedLogsHidden() {
    let src = FakeSource()
    var logs: [(Rect, Bool)] = []
    let t = WindowTracker(source: src, windowID: 7) { logs.append(($0, $1)) }
    src.list = [w(7, "Google Chrome", big)]
    t.sample()
    src.list = []
    t.sample(); t.sample()
    #expect(logs.count == 2)
    #expect(logs[1] == (big, false))
    src.list = [w(7, "Google Chrome", big)]
    t.sample()
    #expect(logs.count == 3 && logs[2].1)
}
