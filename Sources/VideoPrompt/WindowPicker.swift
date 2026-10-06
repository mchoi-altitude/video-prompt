import AppKit
import VPApp
import VPCore

/// Highlights the window under the pointer; click to choose it, Esc cancels.
@MainActor
final class WindowPicker {
    private var panels: [NSPanel] = []
    private var continuation: CheckedContinuation<WindowInfo?, Never>?

    func pick(source: WindowSource) async -> WindowInfo? {
        let windows = source.windows().filter { $0.owner != "Video Prompt" && $0.owner != "Window Server" && $0.owner != "Dock" }
        return await withCheckedContinuation { c in
            continuation = c
            for screen in NSScreen.screens {
                let p = KeyPanel(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
                p.level = Levels.controls
                p.isOpaque = false
                p.backgroundColor = .clear
                p.acceptsMouseMovedEvents = true
                let v = PickView(frame: NSRect(origin: .zero, size: screen.frame.size), windows: windows)
                v.onDone = { [weak self] w in self?.finish(w) }
                p.contentView = v
                p.setFrame(screen.frame, display: true)
                p.makeKeyAndOrderFront(nil)
                panels.append(p)
            }
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private func finish(_ w: WindowInfo?) {
        for p in panels { p.orderOut(nil) }
        panels.removeAll()
        continuation?.resume(returning: w)
        continuation = nil
    }
}

private final class PickView: NSView {
    var onDone: ((WindowInfo?) -> Void)?
    private let windows: [WindowInfo]
    private var hovered: WindowInfo?
    private var tracking: NSTrackingArea?

    init(frame: NSRect, windows: [WindowInfo]) {
        self.windows = windows
        super.init(frame: frame)
    }
    required init?(coder: NSCoder) { fatalError() }

    override var acceptsFirstResponder: Bool { true }
    override func viewDidMoveToWindow() { window?.makeFirstResponder(self) }
    override func updateTrackingAreas() {
        if let t = tracking { removeTrackingArea(t) }
        let t = NSTrackingArea(rect: bounds, options: [.mouseMoved, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(t); tracking = t
    }

    private func globalPoint(_ e: NSEvent) -> Point {
        let p = window?.convertPoint(toScreen: e.locationInWindow) ?? .zero
        return ScreenGeometry.topLeft(p, primaryHeight: Double(NSScreen.screens.first?.frame.height ?? 0))
    }

    override func mouseMoved(with e: NSEvent) {
        let w = VPApp.window(at: globalPoint(e), in: windows)
        if w != hovered { hovered = w; needsDisplay = true }
    }
    override func mouseDown(with e: NSEvent) { onDone?(VPApp.window(at: globalPoint(e), in: windows)) }
    override func keyDown(with e: NSEvent) { if e.keyCode == 53 { onDone?(nil) } }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.15).setFill()
        bounds.fill()
        guard let h = hovered, let w = window else { return }
        let screenRect = ScreenGeometry.appKit(h.frame, primaryHeight: Double(NSScreen.screens.first?.frame.height ?? 0))
        let local = w.convertFromScreen(screenRect)
        let path = NSBezierPath(roundedRect: local, xRadius: 10, yRadius: 10)
        path.lineWidth = 3
        NSColor(srgbRed: 0xE5 / 255, green: 0x48 / 255, blue: 0x4D / 255, alpha: 1).setStroke()
        path.stroke()
    }
}
