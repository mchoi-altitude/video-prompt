import AppKit
import SwiftUI
import VPApp
import VPCore

enum ReviewChoice { case primary, copyReference, discard, close }

/// Transcript, keyframes, note, destination; Return triggers the primary button.
@MainActor
final class ReviewPanel: NSObject, NSWindowDelegate {
    private var panel: NSPanel?
    private var onClose: (() -> Void)?

    func show(_ model: ReviewModel, onChoice: @escaping (ReviewChoice) -> Void) {
        close()
        let p = KeyPanel(contentRect: NSRect(x: 0, y: 0, width: 680, height: 640),
                         styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
        p.title = "Review recording"
        p.titlebarAppearsTransparent = true
        p.level = Levels.controls
        p.isReleasedWhenClosed = false
        p.hidesOnDeactivate = false  // stays put when the user clicks into Chrome or the terminal
        p.delegate = self
        p.contentView = NSHostingView(rootView: ReviewView(model: model, onChoice: { [weak self] c in
            self?.close(); onChoice(c)
        }))
        onClose = { onChoice(.close) }  // the close button still saves the recording
        p.center()
        p.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        panel = p
        // No text field focused, so Return goes to the default (primary) button.
        DispatchQueue.main.async { p.makeFirstResponder(nil) }
    }

    func close() {
        onClose = nil
        panel?.delegate = nil
        panel?.orderOut(nil)
        panel = nil
    }

    func windowWillClose(_ notification: Notification) {
        let f = onClose
        onClose = nil
        panel = nil
        f?()
    }
}

struct ReviewView: View {
    @ObservedObject var model: ReviewModel
    let onChoice: (ReviewChoice) -> Void
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 3)

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("Review recording").font(.system(size: 18, weight: .semibold))
                Spacer()
                Text("\(length) · \(modeLabel)").foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Transcript").font(.system(size: 13, weight: .medium)) + Text(" · click to fix mistakes").font(.system(size: 13)).foregroundColor(.secondary)
                TextEditor(text: $model.transcript)
                    .font(.system(size: 14)).frame(height: 76)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.3)))
            }
            Text("Keyframes").font(.system(size: 13, weight: .medium))
                + Text(" · \(model.keptCount) of \(model.frames.count) will be sent").font(.system(size: 13)).foregroundColor(.secondary)
            ScrollView {
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(model.frames, id: \.index) { f in frameCard(f) }
                }
            }
            .frame(maxHeight: 260)
            VStack(alignment: .leading, spacing: 6) {
                Text("Typed note").font(.system(size: 13, weight: .medium)) + Text(" · optional").font(.system(size: 13)).foregroundColor(.secondary)
                TextField("e.g. same fix on the Billing tab", text: $model.note).textFieldStyle(.roundedBorder)
            }
            Text(model.destination).font(.system(size: 13))
                .foregroundStyle(model.waiter == nil ? Color.secondary : Color(red: 0.48, green: 0.29, blue: 0.02))
            HStack(spacing: 10) {
                Button("Discard", role: .destructive) { onChoice(.discard) }
                Spacer()
                Button("Copy reference") { onChoice(.copyReference) }
                Button(model.primaryTitle) { onChoice(.primary) }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
            .controlSize(.large)
        }
        .padding(22)
        .padding(.top, 10)
        .frame(width: 680)
    }

    private var length: String { String(format: "%d:%02d", Int(model.duration) / 60, Int(model.duration) % 60) }
    private var modeLabel: String {
        switch model.mode { case .window: "Chrome window"; case .screen: "whole screen"; case .area: "selected area" }
    }

    @ViewBuilder private func frameCard(_ f: ManifestFrame) -> some View {
        let off = model.removed.contains(f.index)
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .topTrailing) {
                if let img = NSImage(contentsOf: model.recordingDir.appending(path: f.file)) {
                    Image(nsImage: img).resizable().aspectRatio(contentMode: .fill)
                        .frame(height: 104).clipped().clipShape(RoundedRectangle(cornerRadius: 6))
                } else {
                    RoundedRectangle(cornerRadius: 6).fill(Color.gray.opacity(0.3)).frame(height: 104)
                }
                Button(off ? "Undo" : "×") {
                    if off { model.removed.remove(f.index) } else { model.removed.insert(f.index) }
                }
                .buttonStyle(.borderless)
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(Capsule().fill(Color.white.opacity(0.92)))
                .foregroundStyle(.black)
                .padding(6)
                .accessibilityLabel(off ? "Keep this frame" : "Remove this frame")
            }
            HStack(spacing: 6) {
                Text(String(format: "%d:%02d", Int(f.time) / 60, Int(f.time) % 60)).font(.system(size: 12, design: .monospaced)).foregroundStyle(.secondary)
                Text(f.reasons.joined(separator: ", ")).font(.system(size: 12)).strikethrough(off)
            }
        }
        .opacity(off ? 0.4 : 1)
    }
}
