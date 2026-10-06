import AppKit
import AVFoundation
import SwiftUI
import VPApp
import VPCore
import VPProcess

/// The real system state behind the first-run window.
struct LiveSetupSystem: SetupSystem {
    let paths: Paths
    var screenGranted: Bool { CGPreflightScreenCaptureAccess() }
    var micAccess: MicAccess {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: .granted
        case .notDetermined: .notDetermined
        default: .denied
        }
    }
    var speechInstalled: Bool { WhisperCLITranscriber.fromEnvironment(paths: paths) != nil }
    var pluginSeen: Bool { Waiters(paths: paths).pluginSeen() != nil }
}

/// First-run setup, as in the prototype: one step at a time, nothing that blocks a dead end.
@MainActor
final class SetupWindow {
    private var window: NSWindow?
    private var timer: Timer?

    func show(paths: Paths, onDone: @escaping () -> Void) {
        let model = SetupModel(system: LiveSetupSystem(paths: paths))
        if let window { window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); return }
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 560), styleMask: [.titled, .closable],
                         backing: .buffered, defer: false)
        w.title = "Welcome to Video Prompt"
        w.isReleasedWhenClosed = false
        w.contentView = NSHostingView(rootView: SetupView(model: model, onDone: { [weak self] in
            self?.close(); onDone()
        }))
        w.center()
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        window = w
        // Permissions change in System Settings, not here: keep re-checking while the window is open.
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in MainActor.assumeIsolated { model.refresh() } }
    }

    func close() {
        timer?.invalidate(); timer = nil
        window?.orderOut(nil); window = nil
    }
}

private let modelCommand = #"brew install whisper-cpp && mkdir -p ~/Library/Application\ Support/VideoPrompt/models && curl -fL -o ~/Library/Application\ Support/VideoPrompt/models/ggml-base.en.bin https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.en.bin"#
private let pluginCommands = "/plugin marketplace add mchoi-altitude/video-prompt\n/plugin install video-prompt@video-prompt"

struct SetupView: View {
    @ObservedObject var model: SetupModel
    let onDone: () -> Void
    @State private var copied: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12).fill(Color.black).frame(width: 48, height: 48)
                    Circle().fill(Color(red: 0.9, green: 0.28, blue: 0.3)).frame(width: 16, height: 16)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text("Welcome to Video Prompt").font(.system(size: 20, weight: .semibold))
                    Text("Show Claude what you mean instead of typing it. Setup takes about a minute.").foregroundStyle(.secondary)
                }
            }
            .padding(.bottom, 16)
            step(1, "Screen Recording", model.screen,
                 model.screen == .done ? "Allowed." : "So it can record your Chrome window. Switch on Video Prompt in System Settings; macOS then asks to quit and reopen it.") {
                if model.screen != .done {
                    Button("Open System Settings") {
                        _ = CGRequestScreenCaptureAccess()
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
                    }
                    Button("Quit & Reopen") { relaunch() }.help("macOS applies Screen Recording after a restart")
                }
            }
            step(2, "Microphone", model.microphone, micNote) {
                if model.microphone == .todo {
                    Button("Allow microphone") { AVCaptureDevice.requestAccess(for: .audio) { _ in } }
                } else if model.microphone == .warning {
                    Button("Open System Settings") {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!)
                    }
                }
            }
            step(3, "Speech-to-text", model.speech,
                 model.speech == .done ? "Installed. Narration is transcribed on this Mac." : "Not installed yet. install.sh does this; or run the command below in Terminal.") {
                if model.speech != .done { copyButton("Copy command", modelCommand) }
            }
            step(4, "Connect Claude Code", model.claude,
                 model.claude == .done ? "Claude Code has used the plugin. It can fetch and wait for recordings." : "Optional: lets Claude fetch your recordings or ask you to record. Paste these into Claude Code; this turns green once it runs.") {
                if model.claude != .done { copyButton("Copy commands", pluginCommands) }
            }
            Divider().padding(.vertical, 12)
            HStack {
                Text("⌃⌥⌘R records the Chrome window.").foregroundStyle(.secondary)
                Spacer()
                Button("Later") { onDone() }
                Button(model.canFinish ? "Done" : "Finish the steps above") { onDone() }
                    .keyboardShortcut(.defaultAction).disabled(!model.canFinish)
            }
        }
        .padding(24)
        .frame(width: 640)
    }

    private var micNote: String {
        switch model.microphone {
        case .done: "Allowed. Audio never leaves this Mac."
        case .warning: "Off. You can still record and draw; Claude just won't hear you."
        case .todo: "So Claude gets your narration as text. Audio never leaves this Mac."
        }
    }

    @ViewBuilder private func step(_ n: Int, _ title: String, _ status: StepStatus, _ note: String,
                                   @ViewBuilder actions: () -> some View) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle().fill(status == .done ? Color.green.opacity(0.8) : status == .warning ? Color.orange : Color.primary.opacity(0.85))
                    .frame(width: 26, height: 26)
                Text(status == .done ? "✓" : status == .warning ? "!" : "\(n)").font(.system(size: 13, weight: .bold)).foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.system(size: 15, weight: .medium))
                Text(note).font(.system(size: 13)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                HStack { actions() }
            }
            Spacer()
        }
        .padding(.vertical, 10)
    }

    private func copyButton(_ label: String, _ text: String) -> some View {
        Button(copied == text ? "Copied ✓" : label) {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            copied = text
        }
    }

    private func relaunch() {
        let path = Bundle.main.bundlePath
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", "sleep 1; /usr/bin/open \"$0\"", path]
        try? p.run()
        NSApp.terminate(nil)
    }
}
