import Combine
import Foundation
import VPCore
import VPProcess

public enum RecState: Equatable, Sendable {
    case idle
    case countdown(Int)
    /// Countdown done; waiting for ScreenCaptureKit (may sit behind a permission prompt).
    case starting
    case recording(paused: Bool)
    case processing(id: String)
    case reviewing(id: String)
    case failed(String)
}

/// What to record. `display` is that display's frame in global top-left points.
public enum CaptureTarget: Sendable {
    case window(WindowInfo, displayID: UInt32, display: Rect)
    case screen(displayID: UInt32, display: Rect)
    case area(Rect, displayID: UInt32, display: Rect)

    var displayID: UInt32 {
        switch self { case let .window(_, d, _), let .screen(d, _), let .area(_, d, _): d }
    }
    var display: Rect {
        switch self { case let .window(_, _, r), let .screen(_, r), let .area(_, _, r): r }
    }
}

/// countdown → recording ⇄ paused → processing → reviewing. The app calls `tick()` every second.
@MainActor
public final class RecordingController: ObservableObject {
    @Published public private(set) var state: RecState = .idle
    @Published public private(set) var elapsed: Double = 0
    @Published public var drawOn = false
    public let drawing = DrawingModel()
    public var showsLengthWarning: Bool { elapsed >= 180 }
    /// Windows to keep out of the capture (the control bar).
    public var excludedWindowIDs: () -> [UInt32] = { [] }

    private let paths: Paths
    private let store: Store
    private let capture: CaptureBackend
    private let clock: () -> Double
    private let makeProcessor: () -> Processor
    private let settings: SettingsStore
    private var recorder: RawRecorder?
    private var target: CaptureTarget?
    private var accumulated = 0.0
    private var runningSince: Double?
    /// A start, pause or stop is awaiting the capture; further clicks and ticks are ignored.
    private var busy = false

    public init(paths: Paths, store: Store, capture: CaptureBackend, clock: @escaping () -> Double,
                makeProcessor: @escaping () -> Processor, settings: SettingsStore) {
        self.paths = paths; self.store = store; self.capture = capture; self.clock = clock
        self.makeProcessor = makeProcessor; self.settings = settings
    }

    public var recordingID: String? { recorder?.id }

    public func start(mode: CaptureMode, target: CaptureTarget) async {
        guard state == .idle || isFinished else { return }
        settings.settings.lastMode = mode
        drawing.fades = settings.settings.drawingsFade
        drawing.clear()
        let area: Rect? = if case let .area(r, _, _) = target { r } else { nil }
        let title: String? = if case let .window(w, _, _) = target { w.title } else { nil }
        do {
            recorder = try RawRecorder(paths: paths, session: RawSession(mode: mode, display: target.display, area: area,
                                                                        windowTitle: title, createdAt: .now), now: .now)
        } catch {
            state = .failed("Couldn't create the recording folder: \(error.localizedDescription)")
            return
        }
        self.target = target
        accumulated = 0; runningSince = nil; elapsed = 0
        state = .countdown(3)
    }

    public func tick() async {
        guard !busy else { return }
        switch state {
        case let .countdown(n) where n > 1:
            state = .countdown(n - 1)
        case .countdown:
            busy = true
            defer { busy = false }
            state = .starting
            await beginCapture()
        case .recording(paused: false):
            elapsed = accumulated + (runningSince.map { clock() - $0 } ?? 0)
        default:
            break
        }
    }

    /// Something the user did, in host time; dropped unless recording.
    public func log(_ kind: EventKind, hostTime: Double) { recorder?.log(kind, hostTime: hostTime) }

    /// Undo on the control bar: off the screen, and out of what Claude is told.
    public func undoDrawing(hostTime: Double) {
        drawing.undo()
        log(.undo, hostTime: hostTime)
    }

    public func clearDrawings(hostTime: Double) {
        drawing.clear()
        log(.clear, hostTime: hostTime)
    }

    public func togglePause() async {
        guard !busy, case let .recording(paused) = state, let recorder else { return }
        busy = true
        defer { busy = false }
        let now = clock()
        do {
            if paused {
                let url = recorder.prepareSegment()
                try await capture.newSegment(url)
                let began = clock()
                recorder.startSegment(hostTime: began)
                runningSince = began
                state = .recording(paused: false)
            } else {
                drawOn = false
                try await capture.pause()
                recorder.endSegment(hostTime: now)
                accumulated += runningSince.map { now - $0 } ?? 0
                runningSince = nil
                elapsed = accumulated
                state = .recording(paused: true)
            }
        } catch {
            state = .failed("Recording stopped: \(error.localizedDescription)")
        }
    }

    public func stop() async {
        guard !busy, case .recording = state, let recorder else { return }
        busy = true
        defer { busy = false }
        drawOn = false  // first: never leave the screen swallowing clicks
        let now = clock()
        do {
            try await capture.stop()
        } catch {
            state = .failed("Recording stopped: \(error.localizedDescription)")
            return
        }
        recorder.endSegment(hostTime: now)
        try? recorder.close()
        let id = recorder.id
        state = .processing(id: id)
        do {
            _ = try await makeProcessor().process(id: id)
            state = .reviewing(id: id)
        } catch {
            state = .failed("Processing failed: \(error.localizedDescription)")
        }
    }

    /// Back to idle once the review panel (or an error) is dismissed.
    public func reset() {
        recorder = nil; target = nil; drawOn = false
        state = .idle
    }

    private var isFinished: Bool {
        switch state { case .reviewing, .failed: true; default: false }
    }

    private func beginCapture() async {
        guard let recorder, let target else { return }
        let url = recorder.prepareSegment()
        do {
            try await capture.start(displayID: target.displayID, excludingWindowIDs: excludedWindowIDs(), firstSegment: url)
            // Event times count from when the file actually began, not from the click.
            let began = clock()
            recorder.startSegment(hostTime: began)
            runningSince = began
            state = .recording(paused: false)
        } catch {
            // Nothing usable was recorded: don't leave an invisible folder behind.
            try? recorder.close()
            try? FileManager.default.removeItem(at: paths.recording(recorder.id))
            state = .failed((error as? CaptureError) == .permissionDenied
                ? "Allow Screen Recording for Video Prompt in System Settings › Privacy & Security, then try again."
                : "Couldn't start recording: \(error.localizedDescription)")
        }
    }
}
