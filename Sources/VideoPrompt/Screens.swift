import AppKit
import VPApp
import VPCore

/// Display ids and top-left frames for NSScreens.
@MainActor
enum Screens {
    static var primaryHeight: Double { Double(NSScreen.screens.first?.frame.height ?? 0) }

    static func displayID(_ s: NSScreen) -> UInt32 {
        (s.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? CGMainDisplayID()
    }

    static func topLeftFrame(_ s: NSScreen) -> Rect { ScreenGeometry.topLeft(s.frame, primaryHeight: primaryHeight) }

    /// The screen containing most of `r` (top-left points).
    static func screen(for r: Rect) -> NSScreen? {
        let target = ScreenGeometry.appKit(r, primaryHeight: primaryHeight)
        return NSScreen.screens.max { a, b in
            a.frame.intersection(target).width * a.frame.intersection(target).height <
                b.frame.intersection(target).width * b.frame.intersection(target).height
        }
    }
}

/// A borderless panel that can take key events (for Esc).
final class KeyPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}
