import Foundation
import Testing
import VPCore
import VPTestSupport
@testable import VPApp

private let now = ISO8601DateFormatter().date(from: "2026-10-06T14:14:02Z")!

private func meta(_ id: String, daysAgo: Double = 0, status: RecordingStatus = .ready, delivered: String? = nil,
                  fetched: String? = nil, size: Int64 = 0) -> RecordingMeta {
    RecordingMeta(id: id, title: "t \(id)", createdAt: now.addingTimeInterval(-daysAgo * 86400), duration: 12, mode: .window,
                  status: status, sizeBytes: size, deliveredToPID: delivered == nil ? nil : 1, deliveredToCwd: delivered, fetchedByCwd: fetched)
}

@Test func statusTexts() {
    #expect(statusText(meta("a", delivered: "/Users/x/acme-console")) == "Sent to claude — acme-console")
    #expect(statusText(meta("a", fetched: "/Users/x/onboarding")) == "Fetched by claude — onboarding")
    #expect(statusText(meta("a")) == "Saved · not fetched yet")
    #expect(statusText(meta("a", status: .reviewing)) == "In review")
    #expect(statusText(meta("a", status: .processing)) == "Processing…")
    #expect(statusText(meta("a", status: .processingFailed)) == "Processing failed · Retry")
}

@Test func expiryTonightAndDays() {
    #expect(expiryText(meta("a", daysAgo: 0), policy: .days(3), now: now) == "Auto-deletes in 3 days")
    #expect(expiryText(meta("a", daysAgo: 1.5), policy: .days(3), now: now) == "Auto-deletes in 2 days")
    #expect(expiryText(meta("a", daysAgo: 2), policy: .days(3), now: now) == "Auto-deletes tonight")
    #expect(expiryText(meta("a"), policy: .keepLast(20), now: now) == nil)
    #expect(expiryText(meta("a"), policy: .never, now: now) == nil)
}

@MainActor
private func model(_ metas: [RecordingMeta]) throws -> (RecordingsModel, RecordingTrasher, Paths, SettingsStore) {
    let p = Paths(root: tempDir()), t = RecordingTrasher()
    for m in metas {
        try FileManager.default.createDirectory(at: p.recording(m.id), withIntermediateDirectories: true)
        try writeJSON(m, to: p.recording(m.id).appending(path: "meta.json"))
    }
    let settings = SettingsStore(defaults: UserDefaults(suiteName: "vp-\(UUID().uuidString)")!)
    return (RecordingsModel(store: Store(paths: p, trasher: t), settings: settings, now: { now }), t, p, settings)
}

@Test @MainActor func selectAllSentPicksSentOnly() throws {
    let (m, _, _, _) = try model([meta("sent", delivered: "/a"), meta("fetched", fetched: "/b"), meta("saved")])
    m.selectAllSent()
    #expect(m.selected == ["sent", "fetched"])
}

@Test @MainActor func deleteSelectedTrashes() throws {
    let (m, t, _, _) = try model([meta("a"), meta("b", daysAgo: 1)])
    m.selected = ["a"]
    try m.deleteSelected()
    #expect(t.trashed == ["a"])
    #expect(m.rows.map(\.id) == ["b"])
    #expect(m.selected.isEmpty)
}

@Test @MainActor func usageSumsSizes() throws {
    let (m, _, _, _) = try model([meta("a", size: 1_000_000), meta("b", daysAgo: 1, size: 2_000_000)])
    #expect(m.usage == "2 recordings · 3.0 MB")
    #expect(m.rows.first?.size == "1.0 MB")
}

@Test @MainActor func changingRetentionSweepsNow() throws {
    let (m, t, _, settings) = try model([meta("old", daysAgo: 2), meta("new")])
    try m.setRetention(.days(1))
    #expect(t.trashed == ["old"])
    #expect(settings.settings.retention == .days(1))
}
