import AppKit
import VPApp
import VPCore

/// Window levels: drawings above apps, the control bar above drawings so it stays clickable.
enum Levels {
    static let overlay = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
    static let controls = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 2)
}

/// One transparent panel per display that paints the drawing model. It swallows clicks only
/// while Draw is on; otherwise clicks pass through to the apps underneath.
@MainActor
final class OverlayController {
    private var panels: [NSPanel] = []
    private var timer: Timer?
    let model: DrawingModel
    /// A finished stroke, for the raw recorder.
    var onStroke: ((Stroke) -> Void)?

    init(model: DrawingModel) { self.model = model }

    var drawOn = false {
        didSet { for p in panels { p.ignoresMouseEvents = !drawOn } }
    }

    func show() {
        hide()
        for screen in NSScreen.screens {
            let panel = NSPanel(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.level = Levels.overlay
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false
            panel.ignoresMouseEvents = !drawOn
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            let view = OverlayView(frame: NSRect(origin: .zero, size: screen.frame.size))
            view.controller = self
            panel.contentView = view
            panel.setFrame(screen.frame, display: false)
            panel.orderFrontRegardless()
            panels.append(panel)
        }
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.redraw() }
        }
    }

    func hide() {
        timer?.invalidate(); timer = nil
        drawOn = false
        model.clear()
        for p in panels { p.orderOut(nil) }
        panels.removeAll()
    }

    private func redraw() {
        model.prune(now: ProcessInfo.processInfo.systemUptime)
        for p in panels { p.contentView?.needsDisplay = true }
    }
}

final class OverlayView: NSView {
    weak var controller: OverlayController?
    private static let red = NSColor(srgbRed: 0xE5 / 255, green: 0x48 / 255, blue: 0x4D / 255, alpha: 1)

    private var primaryHeight: Double { Double(NSScreen.screens.first?.frame.height ?? 0) }

    /// Global top-left point → this view's coordinates.
    private func local(_ p: Point) -> NSPoint {
        let global = NSPoint(x: p.x, y: primaryHeight - p.y)
        let origin = window?.frame.origin ?? .zero
        return NSPoint(x: global.x - origin.x, y: global.y - origin.y)
    }

    private func globalPoint(_ e: NSEvent) -> Point {
        let w = window?.convertPoint(toScreen: e.locationInWindow) ?? e.locationInWindow
        return ScreenGeometry.topLeft(w, primaryHeight: primaryHeight)
    }

    override func mouseDown(with e: NSEvent) { controller?.model.begin(globalPoint(e), host: e.timestamp) }
    override func mouseDragged(with e: NSEvent) { controller?.model.extend(globalPoint(e)); needsDisplay = true }
    override func mouseUp(with e: NSEvent) {
        if let s = controller?.model.end(host: ProcessInfo.processInfo.systemUptime) { controller?.onStroke?(s) }
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let model = controller?.model else { return }
        let now = ProcessInfo.processInfo.systemUptime
        for s in model.visible {
            let path = NSBezierPath()
            path.lineWidth = 5
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            let pts = s.points.map(local)
            switch s.tool {
            case .pen:
                path.move(to: pts[0])
                for p in pts.dropFirst() { path.line(to: p) }
            case .arrow:
                guard let a = pts.first, let b = pts.last else { continue }
                path.move(to: a); path.line(to: b)
                let angle = atan2(b.y - a.y, b.x - a.x), head = 14.0
                for side in [-0.5, 0.5] {
                    path.move(to: b)
                    path.line(to: NSPoint(x: b.x - head * cos(angle + side), y: b.y - head * sin(angle + side)))
                }
            case .box:
                guard let a = pts.first, let b = pts.last else { continue }
                path.appendRect(NSRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(b.x - a.x), height: abs(b.y - a.y)))
            }
            Self.red.withAlphaComponent(model.opacity(of: s, now: now)).setStroke()
            path.stroke()
        }
    }
}
