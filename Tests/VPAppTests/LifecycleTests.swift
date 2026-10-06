import Foundation
import Testing
import VPCore
import VPProcess
import VPTestSupport
@testable import VPApp

private func setup() -> (Lifecycle, Paths, Store, RecordingTrasher, SettingsStore) {
    let p = Paths(root: tempDir()), t = RecordingTrasher(), store = Store(paths: p, trasher: t)
    let settings = SettingsStore(defaults: UserDefaults(suiteName: "vp-\(UUID().uuidString)")!)
    return (Lifecycle(store: store, settings: settings, makeProcessor: { Processor(store: store, paths: p, transcriber: nil) }), p, store, t, settings)
}

private func addMeta(_ p: Paths, _ id: String, status: RecordingStatus, daysAgo: Double = 0, now: Date = .now) throws {
    try FileManager.default.createDirectory(at: p.recording(id), withIntermediateDirectories: true)
    try writeJSON(RecordingMeta(id: id, title: id, createdAt: now.addingTimeInterval(-daysAgo * 86400), duration: 1, mode: .window, status: status),
                  to: p.recording(id).appending(path: "meta.json"))
}

@Test func strandedProcessingMarkedFailed() throws {
    let (l, p, store, _, _) = setup()
    try addMeta(p, "stuck", status: .processing)
    try l.onLaunch(now: .now)
    #expect(try store.meta("stuck").status == .processingFailed)
    #expect(try store.meta("stuck").error == "Video Prompt quit while processing")
}

@Test func launchSweeps() throws {
    let (l, p, _, t, _) = setup()
    try addMeta(p, "old", status: .ready, daysAgo: 5)
    try addMeta(p, "new", status: .ready)
    try l.onLaunch(now: .now)
    #expect(t.trashed == ["old"])
}

@Test func retryProcessesKeptRaw() async throws {
    let (l, p, store, _, _) = setup()
    let rec = try RawRecorder(paths: p, session: RawSession(mode: .screen, display: Rect(x: 0, y: 0, w: 640, h: 400), createdAt: .now), now: .now)
    let seg = rec.beginSegment(hostTime: 0)
    try await makeColorVideo(url: seg, size: (640, 400), blocks: [ColorBlock(2, (200, 200, 200))])
    rec.endSegment(hostTime: 2)
    try rec.close()
    try writeJSON(RecordingMeta(id: rec.id, title: "x", createdAt: .now, duration: 0, mode: .screen, status: .processingFailed),
                  to: p.recording(rec.id).appending(path: "meta.json"))
    let m = try await l.retry(rec.id)
    #expect(m.status == .reviewing)
    #expect(try store.meta(rec.id).status == .reviewing)
}

@Test func interruptedRecordingBecomesFailedAndRetryable() throws {
    let (l, p, store, _, _) = setup()
    let rec = try RawRecorder(paths: p, session: RawSession(mode: .screen, display: Rect(x: 0, y: 0, w: 640, h: 400), createdAt: .now), now: .now)
    let seg = rec.beginSegment(hostTime: 0)
    try Data(repeating: 1, count: 1000).write(to: seg)      // the app quit mid-recording: no meta.json
    try l.onLaunch(now: .now)
    let m = try store.meta(rec.id)
    #expect(m.status == .processingFailed)
    #expect(m.error == "Video Prompt quit while recording")
}

@Test func emptyOrphanFolderIsRemoved() throws {
    let (l, p, _, _, _) = setup()
    try FileManager.default.createDirectory(at: p.raw("20261006-000000"), withIntermediateDirectories: true)
    try l.onLaunch(now: .now)
    #expect(!FileManager.default.fileExists(atPath: p.recording("20261006-000000").path))
}
