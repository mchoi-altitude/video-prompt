import AppKit
import SwiftUI

/// A short message near the top of the screen, e.g. "Copied — paste into Claude Code".
@MainActor
final class Toast {
    private var panel: NSPanel?
    private var hideTask: Task<Void, Never>?

    func hide() { hideTask?.cancel(); panel?.orderOut(nil); panel = nil }

    func show(_ text: String, seconds: Double = 4) {
        hideTask?.cancel()
        panel?.orderOut(nil)
        let host = NSHostingView(rootView: Text(text).font(.system(size: 14)).foregroundStyle(.white)
            .padding(.horizontal, 18).padding(.vertical, 12)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color(white: 0.11).opacity(0.95))).fixedSize())
        let size = host.fittingSize
        let p = NSPanel(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.level = Levels.controls
        p.isOpaque = false
        p.backgroundColor = .clear
        p.ignoresMouseEvents = true
        p.contentView = host
        if let f = NSScreen.main?.visibleFrame { p.setFrameOrigin(NSPoint(x: f.midX - size.width / 2, y: f.maxY - size.height - 120)) }
        p.orderFrontRegardless()
        panel = p
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            self?.panel?.orderOut(nil)
        }
    }
}
