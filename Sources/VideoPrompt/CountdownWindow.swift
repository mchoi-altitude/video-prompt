import AppKit
import SwiftUI

/// The 3-2-1 before recording starts, dimming the display being recorded.
@MainActor
final class CountdownWindow {
    private var panel: NSPanel?

    func show(_ n: Int, label: String, on screen: NSScreen?) {
        guard let screen = screen ?? NSScreen.main else { return }
        let view = NSHostingView(rootView: CountdownView(n: n, label: label))
        if let panel { panel.contentView = view; return }
        let p = NSPanel(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.level = Levels.controls
        p.isOpaque = false
        p.backgroundColor = .clear
        p.ignoresMouseEvents = true
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.contentView = view
        p.setFrame(screen.frame, display: true)
        p.orderFrontRegardless()
        panel = p
    }

    func hide() { panel?.orderOut(nil); panel = nil }
}

private struct CountdownView: View {
    let n: Int
    let label: String
    var body: some View {
        ZStack {
            Color.black.opacity(0.35)
            VStack(spacing: 8) {
                Text("\(n)").font(.system(size: 140, weight: .semibold)).foregroundStyle(.white)
                Text("Recording \(label) in…").font(.system(size: 16)).foregroundStyle(.white)
            }
        }
    }
}
