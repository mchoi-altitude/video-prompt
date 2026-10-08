import AppKit
import SwiftUI
import VPApp
import VPCore

/// The floating ● 0:07  ❚❚  ✎  ■ bar. It's excluded from the capture.
@MainActor
final class ControlBarPanel {
    let panel: NSPanel
    var windowID: UInt32 { UInt32(panel.windowNumber) }

    init(controller: RecordingController, onStop: @escaping () -> Void) {
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 420, height: 92),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = Levels.controls
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        // The bar is always dark; in Light mode the tool picker drew black glyphs on it.
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = FirstMouseHostingView(rootView: ControlBarView(controller: controller, onStop: onStop))
    }

    /// `visible: false` orders it in at alpha 0 so its window id exists for capture exclusion.
    func show(on screen: NSScreen?, visible: Bool) {
        if !visible || !panel.isVisible, let f = (screen ?? NSScreen.main)?.visibleFrame {
            panel.setFrameOrigin(NSPoint(x: f.midX - panel.frame.width / 2, y: f.maxY - panel.frame.height - 12))
        }
        panel.alphaValue = visible ? 1 : 0
        panel.ignoresMouseEvents = !visible
        panel.orderFrontRegardless()
    }

    func hide() { panel.orderOut(nil) }
}

struct ControlBarView: View {
    @ObservedObject var controller: RecordingController
    let onStop: () -> Void
    @State private var tool: StrokeTool = .pen

    private var paused: Bool { controller.state == .recording(paused: true) }
    private let red = Color(red: 0xE5 / 255, green: 0x48 / 255, blue: 0x4D / 255)

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                Circle().fill(paused ? Color.gray : red).frame(width: 10, height: 10)
                Text(timeLabel).font(.system(size: 14, design: .monospaced)).foregroundStyle(.white).frame(minWidth: 44, alignment: .leading)
                bar(paused ? "play.fill" : "pause.fill", paused ? "Resume" : "Pause") { Task { await controller.togglePause() } }
                Divider().frame(height: 22).overlay(Color.white.opacity(0.25))
                bar("pencil.tip", "Draw (⌥D)", on: controller.drawOn) { controller.drawOn.toggle() }
                    .disabled(paused)
                if controller.drawOn {
                    Picker("Tool", selection: $tool) {
                        Image(systemName: "scribble").tag(StrokeTool.pen)
                        Image(systemName: "arrow.up.right").tag(StrokeTool.arrow)
                        Image(systemName: "rectangle").tag(StrokeTool.box)
                    }
                    .pickerStyle(.segmented).labelsHidden().frame(width: 110)
                    .onChange(of: tool) { _, t in controller.drawing.tool = t }
                    bar("arrow.uturn.backward", "Undo") { controller.undoDrawing(hostTime: ProcessInfo.processInfo.systemUptime) }
                    bar("trash", "Clear drawings") { controller.clearDrawings(hostTime: ProcessInfo.processInfo.systemUptime) }
                }
                Button(action: onStop) {
                    RoundedRectangle(cornerRadius: 2).fill(Color.black).frame(width: 12, height: 12)
                        .frame(width: 36, height: 36).background(Circle().fill(Color.white))
                }
                .buttonStyle(.plain).help("Stop").accessibilityLabel("Stop")
            }
            .padding(.horizontal, 12).frame(height: 52)
            .background(Capsule().fill(Color(white: 0.11).opacity(0.94)))
            Text(caption).font(.system(size: 11)).foregroundStyle(.white)
                .shadow(color: .black.opacity(0.6), radius: 2)
        }
        .fixedSize()
        .padding(4)
    }

    private var caption: String {
        if controller.showsLengthWarning { return "Long recordings give Claude many frames. Wrap up soon?" }
        if controller.drawOn { return "Drawing · clicks don’t reach apps · Esc to stop" }
        return "⌥D to draw · hidden from the recording"
    }

    private var timeLabel: String {
        let s = Int(controller.elapsed)
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    private func bar(_ symbol: String, _ label: String, on: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(Circle().fill(on ? red : Color.clear))
        }
        .buttonStyle(.plain).help(label).accessibilityLabel(label)
    }
}

/// Buttons respond to the first click even though the panel never becomes key.
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
