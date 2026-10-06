import AppKit
import SwiftUI
import VPApp
import VPCore

@MainActor
final class RecordingsWindow {
    private var window: NSWindow?

    func show(model: RecordingsModel, paths: Paths, pasteboard: VPApp.Pasteboard, onRetry: @escaping (String) -> Void,
              onReview: @escaping (String) -> Void) {
        model.reload()
        if let window { window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); return }
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 520),
                         styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
        w.title = "Recordings"
        w.isReleasedWhenClosed = false
        w.contentView = NSHostingView(rootView: RecordingsView(model: model, paths: paths, pasteboard: pasteboard, onRetry: onRetry, onReview: onReview))
        w.center()
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        window = w
    }
}

private enum RetentionChoice: String, CaseIterable, Identifiable {
    case d1, d3, d7, d30, last20, never
    var id: String { rawValue }
    var label: String {
        switch self {
        case .d1: "after 1 day"; case .d3: "after 3 days"; case .d7: "after 7 days"; case .d30: "after 30 days"
        case .last20: "keep the last 20"; case .never: "never"
        }
    }
    var policy: RetentionPolicy {
        switch self {
        case .d1: .days(1); case .d3: .days(3); case .d7: .days(7); case .d30: .days(30); case .last20: .keepLast(20); case .never: .never
        }
    }
    init(_ p: RetentionPolicy) {
        switch p {
        case .days(1): self = .d1; case .days(7): self = .d7; case .days(30): self = .d30
        case .keepLast: self = .last20; case .never: self = .never; default: self = .d3
        }
    }
}

struct RecordingsView: View {
    @ObservedObject var model: RecordingsModel
    let paths: Paths
    let pasteboard: VPApp.Pasteboard
    let onRetry: (String) -> Void
    let onReview: (String) -> Void
    @State private var retention: RetentionChoice = .d3

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                Text(model.usage + " · frames + transcript only (raw video dropped after processing)").foregroundStyle(.secondary)
                Spacer()
                Picker("Auto-delete", selection: $retention) {
                    ForEach(RetentionChoice.allCases) { Text($0.label).tag($0) }
                }
                .frame(width: 240)
                .onChange(of: retention) { _, c in try? model.setRetention(c.policy) }
            }
            .padding(.horizontal, 22).padding(.vertical, 14)
            Divider()
            if model.rows.isEmpty {
                Text("No recordings. New ones show up here after you press Stop.").foregroundStyle(.secondary).frame(maxHeight: .infinity)
            } else {
                List(model.rows) { row in rowView(row) }.listStyle(.inset)
            }
            Divider()
            HStack(spacing: 12) {
                Button("Select all sent") { model.selectAllSent() }
                Text("Deleted recordings go to the macOS Trash, so a mistake is recoverable.").font(.system(size: 13)).foregroundStyle(.secondary)
                Spacer()
                Button(model.selected.isEmpty ? "Delete selected" : "Delete \(model.selected.count) selected", role: .destructive) {
                    try? model.deleteSelected()
                }
                .disabled(model.selected.isEmpty)
            }
            .padding(.horizontal, 22).padding(.vertical, 12)
        }
        .frame(minWidth: 900, minHeight: 360)
        .onAppear { retention = RetentionChoice(model.retention) }
    }

    @ViewBuilder private func rowView(_ row: RecordingRow) -> some View {
        HStack(spacing: 14) {
            Toggle("", isOn: Binding(get: { model.selected.contains(row.id) },
                                     set: { if $0 { model.selected.insert(row.id) } else { model.selected.remove(row.id) } }))
                .labelsHidden().toggleStyle(.checkbox)
            thumbnail(row.id).frame(width: 92, height: 52).clipShape(RoundedRectangle(cornerRadius: 5))
            VStack(alignment: .leading, spacing: 3) {
                Text(row.title).font(.system(size: 14, weight: .medium)).lineLimit(1)
                Text(row.meta).font(.system(size: 12)).foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .leading, spacing: 3) {
                Text(row.status).font(.system(size: 13)).foregroundStyle(row.sent ? Color.green.opacity(0.8) : Color.secondary)
                if let e = row.expires { Text(e).font(.system(size: 12)).foregroundStyle(Color.orange) }
            }
            .frame(width: 250, alignment: .leading)
            Text(row.size).font(.system(size: 12, design: .monospaced)).foregroundStyle(.secondary).frame(width: 64, alignment: .trailing)
            if row.failed {
                Button("Retry") { onRetry(row.id) }
            } else if row.inReview {
                Button("Review") { onReview(row.id) }
            } else {
                Button("Copy reference") { model.copyReference(row.id, pasteboard: pasteboard) }
            }
            Button { try? model.delete(row.id) } label: { Image(systemName: "trash") }
                .buttonStyle(.borderless).help("Move to Trash").accessibilityLabel("Delete \(row.title)")
        }
        .padding(.vertical, 6)
    }

    @ViewBuilder private func thumbnail(_ id: String) -> some View {
        if let img = NSImage(contentsOf: paths.recording(id).appending(path: "overview.jpg")) {
            Image(nsImage: img).resizable().aspectRatio(contentMode: .fill)
        } else {
            Rectangle().fill(Color.gray.opacity(0.3))
        }
    }
}
