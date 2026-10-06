import Combine
import Foundation
import Testing
import VPCore
import VPProcess
import VPTestSupport
@testable import VPApp

/// Records calls; copies a fixture movie (or junk) to each segment URL so processing has input.
final class FakeCapture: CaptureBackend, @unchecked Sendable {
    var calls: [String] = []
    let fixture: URL?
    init(fixture: URL?) { self.fixture = fixture }
    private func write(_ url: URL) throws {
        if let fixture { try FileManager.default.copyItem(at: fixture, to: url) } else { try Data("junk".utf8).write(to: url) }
    }
    func start(displayID: UInt32, excludingWindowIDs: [UInt32], firstSegment: URL) async throws {
        calls.append("start \(firstSegment.lastPathComponent)"); try write(firstSegment)
    }
    func newSegment(_ url: URL) async throws { calls.append("newSegment \(url.lastPathComponent)"); try write(url) }
    func pause() async throws { calls.append("pause") }
    func stop() async throws { calls.append("stop") }
}

/// A test clock. With `autoStep`, every read moves time forward (so countdowns advance).
final class ManualClock: @unchecked Sendable {
    var now = 0.0
    var autoStep = 0.0
    init(autoStep: Double = 0) { self.autoStep = autoStep }
    func read() -> Double { defer { now += autoStep }; return now }
}

private let display = Rect(x: 0, y: 0, w: 640, h: 400)
private let chrome = WindowInfo(id: 9, owner: "Google Chrome", title: "Settings", frame: Rect(x: 20, y: 30, w: 400, h: 300), layer: 0, onScreen: true)

private func fixtureMovie() async throws -> URL {
    let u = tempDir().appending(path: "fixture.mov")
    try await makeColorVideo(url: u, size: (640, 400), blocks: [ColorBlock(2, (220, 220, 220))])
    return u
}

@MainActor
private func controller(_ capture: FakeCapture, clock: ManualClock = ManualClock(autoStep: 1)) -> (RecordingController, SettingsStore) {
    let paths = Paths(root: tempDir())
    let settings = SettingsStore(defaults: UserDefaults(suiteName: "vp-\(UUID().uuidString)")!)
    let c = RecordingController(paths: paths, store: Store(paths: paths), capture: capture, clock: { clock.read() },
                                makeProcessor: { Processor(store: Store(paths: paths), paths: paths, transcriber: nil) },
                                settings: settings)
    return (c, settings)
}

@MainActor
private func startRecording(_ c: RecordingController, clock: ManualClock? = nil) async {
    await c.start(mode: .window, target: .window(chrome, displayID: 1, display: display))
    for _ in 0..<3 { clock?.now += 1; await c.tick() }
}

@Test @MainActor func countdownThenRecording() async throws {
    let cap = FakeCapture(fixture: nil)
    let (c, _) = controller(cap)
    await c.start(mode: .window, target: .window(chrome, displayID: 1, display: display))
    #expect(c.state == .countdown(3))
    await c.tick(); #expect(c.state == .countdown(2))
    await c.tick(); #expect(c.state == .countdown(1))
    await c.tick(); #expect(c.state == .recording(paused: false))
    #expect(cap.calls == ["start seg_001.mov"])
}

@Test @MainActor func startRemembersMode() async throws {
    let (c, settings) = controller(FakeCapture(fixture: nil))
    await c.start(mode: .area, target: .area(Rect(x: 0, y: 0, w: 100, h: 100), displayID: 1, display: display))
    #expect(settings.settings.lastMode == .area)
}

@Test @MainActor func pauseEndsSegmentResumeStartsNext() async throws {
    let cap = FakeCapture(fixture: nil)
    let (c, _) = controller(cap)
    await startRecording(c)
    await c.togglePause()
    #expect(c.state == .recording(paused: true))
    await c.togglePause()
    #expect(c.state == .recording(paused: false))
    #expect(cap.calls == ["start seg_001.mov", "pause", "newSegment seg_002.mov"])
}

@Test @MainActor func elapsedExcludesPausedTime() async throws {
    let clock = ManualClock()
    let (c, _) = controller(FakeCapture(fixture: nil), clock: clock)
    await startRecording(c, clock: clock)     // recording from t = 3
    clock.now = 8; await c.togglePause()      // 5 s recorded
    clock.now = 18; await c.togglePause()     // 10 s paused
    clock.now = 20; await c.tick()            // 2 s more
    #expect(c.elapsed == 7)
}

@Test @MainActor func warningAtThreeMinutes() async throws {
    let clock = ManualClock()
    let (c, _) = controller(FakeCapture(fixture: nil), clock: clock)
    await startRecording(c, clock: clock)     // recording from t = 3
    clock.now = 182; await c.tick(); #expect(!c.showsLengthWarning)
    clock.now = 183; await c.tick(); #expect(c.showsLengthWarning)
}

@Test @MainActor func stopTurnsDrawingOff() async throws {
    let cap = FakeCapture(fixture: try await fixtureMovie())
    let (c, _) = controller(cap)
    await startRecording(c)
    c.drawOn = true
    let watch = c.$drawOn.dropFirst().sink { cap.calls.append("drawOn \($0)") }
    await c.stop()
    watch.cancel()
    // Off before capture stops, not after processing.
    #expect(cap.calls.suffix(2) == ["drawOn false", "stop"])
    #expect(!c.drawOn)
}

@Test @MainActor func stopProcessesToReviewing() async throws {
    let (c, _) = controller(FakeCapture(fixture: try await fixtureMovie()))
    await startRecording(c)
    await c.stop()
    guard case let .reviewing(id) = c.state else { Issue.record("state \(c.state)"); return }
    #expect(id.hasPrefix("20"))
}

@Test @MainActor func processorFailureShowsFailed() async throws {
    let (c, _) = controller(FakeCapture(fixture: nil))
    await startRecording(c)
    await c.stop()
    guard case .failed = c.state else { Issue.record("state \(c.state)"); return }
}

/// A capture whose start/stop wait until the test opens the gate (like a permission prompt).
final class GatedCapture: CaptureBackend, @unchecked Sendable {
    var calls: [String] = []
    var startDelayClock: ManualClock?
    var fail: Error?
    private var waiting: [CheckedContinuation<Void, Never>] = []
    func open() { let w = waiting; waiting = []; w.forEach { $0.resume() } }
    /// Waits until a call is parked at the gate, then lets it through.
    func openWhenWaiting() async {
        for _ in 0..<500 where waiting.isEmpty { try? await Task.sleep(for: .milliseconds(10)) }
        open()
    }
    private func gate() async { await withCheckedContinuation { waiting.append($0) } }
    func start(displayID: UInt32, excludingWindowIDs: [UInt32], firstSegment: URL) async throws {
        calls.append("start"); await gate()
        if let fail { throw fail }
        startDelayClock?.now += 0.7
    }
    func newSegment(_ url: URL) async throws { calls.append("newSegment") }
    func pause() async throws { calls.append("pause") }
    func stop() async throws { calls.append("stop"); await gate() }
}

@MainActor
private func gated(_ cap: GatedCapture, clock: ManualClock = ManualClock(autoStep: 1)) -> (RecordingController, Paths) {
    let paths = Paths(root: tempDir())
    let settings = SettingsStore(defaults: UserDefaults(suiteName: "vp-\(UUID().uuidString)")!)
    let c = RecordingController(paths: paths, store: Store(paths: paths), capture: cap, clock: { clock.read() },
                                makeProcessor: { Processor(store: Store(paths: paths), paths: paths, transcriber: nil) }, settings: settings)
    return (c, paths)
}

@Test @MainActor func slowStartIsNotStartedTwice() async throws {
    let cap = GatedCapture()
    let (c, _) = gated(cap)
    await c.start(mode: .window, target: .window(chrome, displayID: 1, display: display))
    await c.tick(); await c.tick()
    let first = Task { await c.tick() }          // countdown(1) → starting, blocks in capture.start
    try await Task.sleep(for: .milliseconds(50))
    #expect(c.state == .starting)
    await c.tick(); await c.tick()               // ticks while the start is in flight
    cap.open()
    await first.value
    #expect(cap.calls == ["start"])
    #expect(c.state == .recording(paused: false))
}

@Test @MainActor func doubleStopRunsOnce() async throws {
    let cap = GatedCapture()
    let (c, _) = gated(cap)
    await c.start(mode: .window, target: .window(chrome, displayID: 1, display: display))
    await c.tick(); await c.tick()
    let s = Task { await c.tick() }; await cap.openWhenWaiting(); await s.value
    let stop1 = Task { await c.stop() }
    for _ in 0..<500 where !cap.calls.contains("stop") { try await Task.sleep(for: .milliseconds(10)) }
    await c.stop()                               // second click while the first is finishing
    await cap.openWhenWaiting()
    await stop1.value
    #expect(cap.calls.filter { $0 == "stop" }.count == 1)
}

@Test @MainActor func eventTimesStartWhenCaptureStarts() async throws {
    let clock = ManualClock()
    let cap = GatedCapture(); cap.startDelayClock = clock
    let (c, paths) = gated(cap, clock: clock)
    clock.now = 10
    await c.start(mode: .window, target: .window(chrome, displayID: 1, display: display))
    clock.now = 11; await c.tick(); clock.now = 12; await c.tick()
    clock.now = 13
    let s = Task { await c.tick() }; await cap.openWhenWaiting(); await s.value
    // The file began 0.7 s after the start call, at 13.7.
    c.log(.cursor(Point(x: 1, y: 1)), hostTime: 15.7)
    let id = try #require(c.recordingID)
    let line = try String(contentsOf: paths.raw(id).appending(path: "events.jsonl"), encoding: .utf8)
    #expect(try JSON.decoder.decode(RawEvent.self, from: Data(line.utf8)) == .cursor(seg: 1, t: 2.0, p: Point(x: 1, y: 1)))
}

@Test @MainActor func failedStartRemovesRecordingFolder() async throws {
    let cap = GatedCapture(); cap.fail = CaptureError.permissionDenied
    let (c, paths) = gated(cap)
    await c.start(mode: .window, target: .window(chrome, displayID: 1, display: display))
    let id = try #require(c.recordingID)
    await c.tick(); await c.tick()
    let s = Task { await c.tick() }; await cap.openWhenWaiting(); await s.value
    guard case .failed = c.state else { Issue.record("state \(c.state)"); return }
    #expect(!FileManager.default.fileExists(atPath: paths.recording(id).path))
}

@Test @MainActor func clearAndUndoAreLogged() async throws {
    let clock = ManualClock()
    let cap = FakeCapture(fixture: nil)
    let paths = Paths(root: tempDir())
    let c = RecordingController(paths: paths, store: Store(paths: paths), capture: cap, clock: { clock.read() },
                                makeProcessor: { Processor(store: Store(paths: paths), paths: paths, transcriber: nil) },
                                settings: SettingsStore(defaults: UserDefaults(suiteName: "vp-\(UUID().uuidString)")!))
    await startRecording(c, clock: clock)
    c.undoDrawing(hostTime: 4)
    c.clearDrawings(hostTime: 5)
    let id = try #require(c.recordingID)
    let events = try String(contentsOf: paths.raw(id).appending(path: "events.jsonl"), encoding: .utf8)
        .split(whereSeparator: \.isNewline).map { try JSON.decoder.decode(RawEvent.self, from: Data($0.utf8)) }
    #expect(events == [.undo(seg: 1, t: 1), .clear(seg: 1, t: 2)])
}

@Test @MainActor func eachCountdownNumberLastsASecond() async throws {
    let clock = ManualClock()
    let (c, _) = controller(FakeCapture(fixture: nil), clock: clock)
    clock.now = 100
    await c.start(mode: .window, target: .window(chrome, displayID: 1, display: display))
    clock.now = 100.05; await c.tick()          // the app's timer fired right after the press
    #expect(c.state == .countdown(3))
    clock.now = 101.0; await c.tick()
    #expect(c.state == .countdown(2))
    clock.now = 101.5; await c.tick()
    #expect(c.state == .countdown(2))
    clock.now = 102.0; await c.tick()
    #expect(c.state == .countdown(1))
}
