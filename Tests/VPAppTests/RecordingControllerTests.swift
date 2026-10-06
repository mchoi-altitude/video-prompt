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

final class ManualClock: @unchecked Sendable { var now = 0.0 }

private let display = Rect(x: 0, y: 0, w: 640, h: 400)
private let chrome = WindowInfo(id: 9, owner: "Google Chrome", title: "Settings", frame: Rect(x: 20, y: 30, w: 400, h: 300), layer: 0, onScreen: true)

private func fixtureMovie() async throws -> URL {
    let u = tempDir().appending(path: "fixture.mov")
    try await makeColorVideo(url: u, size: (640, 400), blocks: [ColorBlock(2, (220, 220, 220))])
    return u
}

@MainActor
private func controller(_ capture: FakeCapture, clock: ManualClock = ManualClock()) -> (RecordingController, SettingsStore) {
    let paths = Paths(root: tempDir())
    let settings = SettingsStore(defaults: UserDefaults(suiteName: "vp-\(UUID().uuidString)")!)
    let c = RecordingController(paths: paths, store: Store(paths: paths), capture: capture, clock: { clock.now },
                                makeProcessor: { Processor(store: Store(paths: paths), paths: paths, transcriber: nil) },
                                settings: settings)
    return (c, settings)
}

@MainActor
private func startRecording(_ c: RecordingController, mode: CaptureMode = .window) async {
    await c.start(mode: mode, target: .window(chrome, displayID: 1, display: display))
    for _ in 0..<3 { await c.tick() }
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
    await startRecording(c)
    clock.now = 5; await c.togglePause()      // 5 s recorded
    clock.now = 15; await c.togglePause()     // 10 s paused
    clock.now = 17; await c.tick()            // 2 s more
    #expect(c.elapsed == 7)
}

@Test @MainActor func warningAtThreeMinutes() async throws {
    let clock = ManualClock()
    let (c, _) = controller(FakeCapture(fixture: nil), clock: clock)
    await startRecording(c)
    clock.now = 179; await c.tick(); #expect(!c.showsLengthWarning)
    clock.now = 180; await c.tick(); #expect(c.showsLengthWarning)
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
