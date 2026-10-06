import CoreGraphics
import Foundation
import VPCore

public struct WindowInfo: Equatable, Sendable {
    public var id: UInt32
    public var owner: String
    public var title: String?
    /// Global top-left points.
    public var frame: Rect
    public var layer: Int
    public var onScreen: Bool
    public init(id: UInt32, owner: String, title: String?, frame: Rect, layer: Int, onScreen: Bool) {
        self.id = id; self.owner = owner; self.title = title; self.frame = frame; self.layer = layer; self.onScreen = onScreen
    }
}

/// Windows front to back.
public protocol WindowSource: Sendable { func windows() -> [WindowInfo] }

/// The system window list. Bounds are already top-left points; titles need Screen Recording.
public struct CGWindowListSource: WindowSource {
    public init() {}
    public func windows() -> [WindowInfo] {
        let list = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        return list.compactMap { d in
            guard let id = d[kCGWindowNumber as String] as? UInt32,
                  let b = d[kCGWindowBounds as String] as? [String: Double] else { return nil }
            return WindowInfo(id: id, owner: d[kCGWindowOwnerName as String] as? String ?? "",
                              title: d[kCGWindowName as String] as? String,
                              frame: Rect(x: b["X"] ?? 0, y: b["Y"] ?? 0, w: b["Width"] ?? 0, h: b["Height"] ?? 0),
                              layer: d[kCGWindowLayer as String] as? Int ?? 0,
                              onScreen: d[kCGWindowIsOnscreen as String] as? Bool ?? false)
        }
    }
}

/// The Chrome window the user was last looking at: front-most normal, visible, not tiny.
public func frontmostChromeWindow(_ ws: [WindowInfo]) -> WindowInfo? {
    ws.first { $0.owner == "Google Chrome" && $0.layer == 0 && $0.onScreen && $0.frame.w >= 100 && $0.frame.h >= 100 }
}

/// The front-most normal window under `p` (for "Record another window…").
public func window(at p: Point, in ws: [WindowInfo]) -> WindowInfo? {
    ws.first { w in
        w.layer == 0 && w.onScreen &&
            p.x >= w.frame.x && p.x < w.frame.x + w.frame.w && p.y >= w.frame.y && p.y < w.frame.y + w.frame.h
    }
}

/// Follows one window, reporting its frame whenever it changes, and `visible: false` once when
/// it disappears (minimized, closed, other space).
public final class WindowTracker: @unchecked Sendable {
    private let source: WindowSource
    private let windowID: UInt32
    private let log: (Rect, Bool) -> Void
    private var last: (Rect, Bool)?

    public init(source: WindowSource, windowID: UInt32, log: @escaping (Rect, Bool) -> Void) {
        self.source = source; self.windowID = windowID; self.log = log
    }

    public func sample() {
        let found = source.windows().first { $0.id == windowID && $0.onScreen }
        let next: (Rect, Bool)
        if let f = found { next = (f.frame, true) } else if let l = last { next = (l.0, false) } else { return }
        if let l = last, l.0 == next.0, l.1 == next.1 { return }
        last = next
        log(next.0, next.1)
    }
}
