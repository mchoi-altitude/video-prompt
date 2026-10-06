import CoreGraphics
import VPCore

/// The one place AppKit's bottom-left points meet the recording contract's top-left points
/// (origin = top-left of the primary display).
public enum ScreenGeometry {
    public static func topLeft(_ p: CGPoint, primaryHeight: Double) -> Point {
        Point(x: p.x, y: primaryHeight - p.y)
    }

    public static func topLeft(_ r: CGRect, primaryHeight: Double) -> Rect {
        Rect(x: r.minX, y: primaryHeight - r.maxY, w: r.width, h: r.height)
    }

    public static func appKit(_ r: Rect, primaryHeight: Double) -> CGRect {
        CGRect(x: r.x, y: primaryHeight - r.y - r.h, width: r.w, height: r.h)
    }
}
