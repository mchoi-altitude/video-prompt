import AppKit
import VPApp
import VPCore

/// Dims every display; drag a rectangle to choose the area. Esc cancels.
@MainActor
final class AreaPicker {
    private var panels: [NSPanel] = []
    private var continuation: CheckedContinuation<(Rect, UInt32)?, Never>?

    func pick() async -> (Rect, displayID: UInt32)? {
        let result = await withCheckedContinuation { c in
            continuation = c
            for screen in NSScreen.screens {
                let p = KeyPanel(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
                p.level = Levels.controls
                p.isOpaque = false
                p.backgroundColor = .clear
                let v = AreaView(frame: NSRect(origin: .zero, size: screen.frame.size))
                v.onDone = { [weak self] r in self?.finish(r.map { ($0, Screens.displayID(screen)) }) }
                p.contentView = v
                p.setFrame(screen.frame, display: true)
                p.makeKeyAndOrderFront(nil)
                panels.append(p)
            }
            NSApp.activate(ignoringOtherApps: true)
            NSCursor.crosshair.push()
        }
        return result.map { ($0.0, displayID: $0.1) }
    }

    private func finish(_ r: (Rect, UInt32)?) {
        NSCursor.pop()
        for p in panels { p.orderOut(nil) }
        panels.removeAll()
        continuation?.resume(returning: r)
        continuation = nil
    }
}

private final class AreaView: NSView {
    var onDone: ((Rect?) -> Void)?
    private var start: NSPoint?
    private var current: NSPoint?
    override var acceptsFirstResponder: Bool { true }
    override func viewDidMoveToWindow() { window?.makeFirstResponder(self) }

    override func keyDown(with e: NSEvent) { if e.keyCode == 53 { onDone?(nil) } }
    override func mouseDown(with e: NSEvent) { start = convert(e.locationInWindow, from: nil); current = start }
    override func mouseDragged(with e: NSEvent) { current = convert(e.locationInWindow, from: nil); needsDisplay = true }
    override func mouseUp(with e: NSEvent) {
        guard let r = selection, r.width >= 80, r.height >= 80, let w = window else { start = nil; needsDisplay = true; return }
        let screenRect = w.convertToScreen(r)
        onDone?(ScreenGeometry.topLeft(screenRect, primaryHeight: Double(NSScreen.screens.first?.frame.height ?? 0)))
    }

    private var selection: NSRect? {
        guard let a = start, let b = current else { return nil }
        return NSRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.35).setFill()
        bounds.fill()
        if let r = selection {
            NSColor.clear.setFill()
            r.fill(using: .copy)
            let border = NSBezierPath(rect: r)
            border.lineWidth = 2
            border.setLineDash([6, 4], count: 2, phase: 0)
            NSColor.white.setStroke()
            border.stroke()
        }
        let hint = "Drag to choose an area · Esc cancels" as NSString
        hint.draw(at: NSPoint(x: bounds.midX - 120, y: bounds.maxY - 80),
                  withAttributes: [.foregroundColor: NSColor.white, .font: NSFont.systemFont(ofSize: 16, weight: .medium)])
    }
}
