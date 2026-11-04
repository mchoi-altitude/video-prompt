import AppKit

/// The menu-bar icon: selection corners around a hand-drawn V, on an 18-point grid (origin top-left).
/// Keep it matching the app icon in `scripts/make-app-icon.swift`.
enum MenuIcon {
    private static let size = NSSize(width: 18, height: 18)
    private static let red = NSColor(srgbRed: 0xD0 / 255, green: 0x31 / 255, blue: 0x3A / 255, alpha: 1)
    private static let amber = NSColor(srgbRed: 0xF0 / 255, green: 0xA0 / 255, blue: 0x20 / 255, alpha: 1)

    /// One color, so macOS adapts it to light and dark menu bars.
    static func idle() -> NSImage {
        let image = draw(color: .black) { color in
            strokeCorners(topRight: true, color: color)
            strokeV(color: color)
        }
        image.isTemplate = true
        return image
    }

    /// The V becomes a red dot.
    static func recording() -> NSImage {
        draw(color: .labelColor) { color in
            strokeCorners(topRight: true, color: color)
            red.setFill()
            NSBezierPath(ovalIn: NSRect(x: 5.6, y: 5.6, width: 6.8, height: 6.8)).fill()
        }
    }

    /// An amber dot replaces the top-right corner, which would otherwise run into it.
    static func waiting() -> NSImage {
        draw(color: .labelColor) { color in
            strokeCorners(topRight: false, color: color)
            strokeV(color: color)
            amber.setFill()
            NSBezierPath(ovalIn: NSRect(x: 11.5, y: 0.5, width: 6, height: 6)).fill()
        }
    }

    private static func draw(color: NSColor, _ body: @escaping (NSColor) -> Void) -> NSImage {
        let image = NSImage(size: size, flipped: true) { _ in body(color); return true }
        image.accessibilityDescription = "Video Prompt"
        return image
    }

    private static func strokeCorners(topRight: Bool, color: NSColor) {
        let p = NSBezierPath()
        func corner(_ a: NSPoint, _ bend: NSPoint, _ b: NSPoint) {
            p.move(to: a)
            p.appendArc(from: bend, to: b, radius: 1)
            p.line(to: b)
        }
        corner(NSPoint(x: 2.5, y: 6), NSPoint(x: 2.5, y: 2.5), NSPoint(x: 6, y: 2.5))
        if topRight { corner(NSPoint(x: 12, y: 2.5), NSPoint(x: 15.5, y: 2.5), NSPoint(x: 15.5, y: 6)) }
        corner(NSPoint(x: 15.5, y: 12), NSPoint(x: 15.5, y: 15.5), NSPoint(x: 12, y: 15.5))
        corner(NSPoint(x: 6, y: 15.5), NSPoint(x: 2.5, y: 15.5), NSPoint(x: 2.5, y: 12))
        stroke(p, width: 1.5, color: color)
    }

    private static func strokeV(color: NSColor) {
        let p = NSBezierPath()
        p.move(to: NSPoint(x: 5.3, y: 6.1))
        p.curve(to: NSPoint(x: 8.3, y: 12.2), controlPoint1: NSPoint(x: 5.9, y: 8), controlPoint2: NSPoint(x: 7, y: 10.5))
        p.curve(to: NSPoint(x: 9.4, y: 12.2), controlPoint1: NSPoint(x: 8.6, y: 12.6), controlPoint2: NSPoint(x: 9.1, y: 12.6))
        p.curve(to: NSPoint(x: 13, y: 5), controlPoint1: NSPoint(x: 10.8, y: 10.2), controlPoint2: NSPoint(x: 11.7, y: 7.5))
        stroke(p, width: 1.7, color: color)
    }

    private static func stroke(_ p: NSBezierPath, width: CGFloat, color: NSColor) {
        p.lineWidth = width
        p.lineCapStyle = .round
        p.lineJoinStyle = .round
        color.setStroke()
        p.stroke()
    }
}
