import AppKit
import AVKit
import SwiftUI
import VPApp
import VPCore

enum ReviewChoice { case primary, copyReference, discard, close }

/// Video preview, transcript, note, destination; Return triggers the primary button.
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
            VideoPreview(url: model.videoURL)
                .frame(height: 300)
                .clipShape(RoundedRectangle(cornerRadius: 8))
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
}

/// Plays the recording video in the review panel (the same file Claude gets).
struct VideoPreview: NSViewRepresentable {
    let url: URL
    func makeNSView(context: Context) -> AVPlayerView {
        let v = AVPlayerView()
        v.controlsStyle = .inline
        let player = AVPlayer(url: url)
        // Plays silently: the user's narration shouldn't blare in a shared room. Unmute in the controls.
        player.isMuted = true
        v.player = player
        player.play()
        return v
    }
    func updateNSView(_ v: AVPlayerView, context: Context) {}
    static func dismantleNSView(_ v: AVPlayerView, coordinator: ()) { v.player?.pause() }
}
