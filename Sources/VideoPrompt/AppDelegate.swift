import AppKit
import Combine
import VPApp
import VPCapture
import VPCore
import VPProcess

struct SystemPasteboard: VPApp.Pasteboard {
    func setString(_ s: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(s, forType: .string)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let paths = Paths.default()
    private lazy var store = Store(paths: paths)
    private let settings = SettingsStore()
    private lazy var waiters = Waiters(paths: paths)
    private lazy var watcher = WaiterWatcher(waiters: waiters)
    private let windows = CGWindowListSource()
    private lazy var makeProcessor: @Sendable () -> Processor = { [paths, store] in
        Processor(store: store, paths: paths, transcriber: WhisperCLITranscriber.fromEnvironment(paths: paths))
    }
    private let capture = ScreenCaptureBackend()
    private lazy var controller = RecordingController(paths: paths, store: store, capture: capture,
                                                      clock: { ProcessInfo.processInfo.systemUptime },
                                                      makeProcessor: makeProcessor, settings: settings)
    private lazy var lifecycle = Lifecycle(store: store, settings: settings, makeProcessor: makeProcessor)
    private lazy var delivery = Delivery(store: store, paths: paths, waiters: waiters, pasteboard: SystemPasteboard())
    private lazy var recordingsModel = RecordingsModel(store: store, settings: settings)

    private var statusItem: StatusItem?
    private var hotkey: Hotkey?
    private lazy var controlBar = ControlBarPanel(controller: controller) { [weak self] in self?.stop() }
    private lazy var overlay = OverlayController(model: controller.drawing)
    private let countdown = CountdownWindow()
    private let review = ReviewPanel()
    private let recordingsWindow = RecordingsWindow()
    private let toast = Toast()
    private var tracker: WindowTracker?
    private var targetScreen: NSScreen?
    private var timers: [Timer] = []
    private var subs: Set<AnyCancellable> = []
    private var lastCursor: Point?

    func applicationDidFinishLaunching(_ notification: Notification) {
        try? lifecycle.onLaunch(now: .now)
        statusItem = StatusItem(items: { [unowned self] in
            menuItems(waiting: watcher.current, chrome: frontmostChromeWindow(windows.windows()),
                      lastMode: settings.settings.lastMode, recordingCount: store.list().count, busy: MenuBusy(controller.state))
        }, onAction: { [unowned self] in handle($0) })
        hotkey = Hotkey { [weak self] in
            guard let self else { return }
            if MenuBusy(self.controller.state) == .recording { self.stop() } else { self.startLastMode() }
        }
        controller.excludedWindowIDs = { [unowned self] in [controlBar.windowID] }
        // The system ended capture (menu-bar indicator, display unplugged, sleep): keep what was
        // recorded and move on to processing, rather than sitting in "recording".
        capture.onUnexpectedStop = { [weak self] message in
            guard let self else { return }
            toast.show(message, seconds: 6)
            Task { await self.controller.stop() }
        }
        overlay.onStroke = { [unowned self] s in
            controller.log(.stroke(startHost: s.startHost, points: s.points, tool: s.tool), hostTime: s.endHost ?? s.startHost)
        }
        controller.$drawOn.sink { [unowned self] on in overlay.drawOn = on }.store(in: &subs)
        // @Published emits before storing; handle on the next main-queue turn so the stored
        // value is current and a reset() inside the handler isn't overwritten.
        controller.$state.receive(on: DispatchQueue.main).sink { [unowned self] s in stateChanged(s) }.store(in: &subs)
        watcher.$current.receive(on: DispatchQueue.main).sink { [unowned self] _ in refreshBadge() }.store(in: &subs)

        timers.append(Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.watcher.poll()
                Task { await self.controller.tick() }
            }
        })
        timers.append(Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.sampleWhileRecording() }
        })
        timers.append(Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { try? self?.lifecycle.hourly(now: .now) }
        })
    }

    // MARK: Starting

    private func handle(_ action: MenuAction) {
        switch action {
        case .recordChrome: startChrome()
        case .recordScreen: startScreen()
        case .recordArea: Task { await startArea() }
        case .recordOtherWindow: Task { await startOtherWindow() }
        case .recordings, .settings: showRecordings()
        case .quit: NSApp.terminate(nil)
        case .stop: stop()
        case .header: break
        }
    }

    private func showRecordings() {
        recordingsWindow.show(model: recordingsModel, paths: paths, pasteboard: SystemPasteboard(),
                              onRetry: { [weak self] id in self?.retry(id) },
                              onReview: { [weak self] id in self?.showReview(id) })
    }

    private func startLastMode() {
        guard controller.state == .idle || isDone else { return }
        switch settings.settings.lastMode {
        case .window: frontmostChromeWindow(windows.windows()) != nil ? startChrome() : startScreen()
        case .screen: startScreen()
        case .area: Task { await startArea() }
        }
    }

    private var isDone: Bool { if case .failed = controller.state { true } else { false } }

    private func startChrome() {
        guard let w = frontmostChromeWindow(windows.windows()) else { toast.show("Chrome isn't open."); return }
        startWindow(w)
    }

    private func startWindow(_ w: WindowInfo) {
        let screen = Screens.screen(for: w.frame) ?? NSScreen.main!
        begin(mode: .window, target: .window(w, displayID: Screens.displayID(screen), display: Screens.topLeftFrame(screen)), screen: screen)
        tracker = WindowTracker(source: windows, windowID: w.id) { [weak self] r, visible in
            self?.controller.log(.window(r, visible: visible), hostTime: ProcessInfo.processInfo.systemUptime)
        }
    }

    private func startScreen() {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main!
        begin(mode: .screen, target: .screen(displayID: Screens.displayID(screen), display: Screens.topLeftFrame(screen)), screen: screen)
    }

    private func startArea() async {
        guard let (r, id) = await AreaPicker().pick() else { return }
        let screen = NSScreen.screens.first { Screens.displayID($0) == id } ?? NSScreen.main!
        begin(mode: .area, target: .area(r, displayID: id, display: Screens.topLeftFrame(screen)), screen: screen)
    }

    private func startOtherWindow() async {
        guard let w = await WindowPicker().pick(source: windows) else { return }
        startWindow(w)
    }

    private func begin(mode: CaptureMode, target: CaptureTarget, screen: NSScreen) {
        guard controller.state == .idle || isDone else { return }
        if isDone { controller.reset() }
        targetScreen = screen
        tracker = nil
        controlBar.show(on: screen, visible: false)  // exists (so it can be excluded) but hidden until recording
        Task { await controller.start(mode: mode, target: target) }
    }

    // MARK: While recording

    private func sampleWhileRecording() {
        guard case .recording(paused: false) = controller.state else { return }
        tracker?.sample()
        let p = ScreenGeometry.topLeft(NSEvent.mouseLocation, primaryHeight: Screens.primaryHeight)
        if p != lastCursor {
            lastCursor = p
            controller.log(.cursor(p), hostTime: ProcessInfo.processInfo.systemUptime)
        }
    }

    private func stop() { Task { await controller.stop() } }

    private func stateChanged(_ s: RecState) {
        refreshBadge()
        switch s {
        case let .countdown(n):
            countdown.show(n, label: label(settings.settings.lastMode), on: targetScreen)
        case .starting:
            countdown.hide()  // before ScreenCaptureKit's first frame
        case .recording:
            countdown.hide()
            controlBar.show(on: targetScreen, visible: true)
            tracker?.sample()
            if !overlay.isShowing { overlay.show() }
        case .processing:
            controlBar.hide(); overlay.hide(); tracker = nil
            toast.show("Transcribing on this Mac…", seconds: 30)
        case let .reviewing(id):
            toast.hide()
            if settings.settings.reviewStep { showReview(id) } else { finish(id, .primary, edits: ReviewEdits()) }
        case let .failed(message):
            countdown.hide(); controlBar.hide(); overlay.hide(); tracker = nil
            toast.show(message, seconds: 8)
            controller.reset()
        case .idle:
            break
        }
    }

    private func label(_ m: CaptureMode) -> String {
        switch m { case .window: "the Chrome window"; case .screen: "whole screen"; case .area: "selected area" }
    }

    private func refreshBadge() {
        statusItem?.setBadge(menuBadge(state: controller.state, waiting: watcher.current != nil))
    }

    // MARK: Review and delivery

    private func showReview(_ id: String) {
        watcher.poll()
        guard let model = try? ReviewModel(id: id, store: store, waiter: watcher.current) else {
            toast.show("Couldn't open the recording."); controller.reset(); return
        }
        review.show(model) { [weak self] choice in self?.finish(id, choice, edits: model.edits) }
    }

    private func finish(_ id: String, _ choice: ReviewChoice, edits: ReviewEdits) {
        do {
            switch choice {
            case .primary:
                watcher.poll()
                if watcher.current != nil {
                    switch try delivery.send(id, edits: edits) {
                    case let .delivered(w): toast.show("Sent to claude — \(URL(fileURLWithPath: w.cwd).lastPathComponent)")
                    case .fellBackToClipboard: toast.show("That Claude session is gone. Saved, and the reference is on your clipboard.")
                    }
                } else {
                    try delivery.saveAndCopy(id, edits: edits)
                    toast.show("Saved. Paste into Claude Code (⌘V), or ask Claude to “look at my recording”.")
                }
            case .copyReference:
                try delivery.copyReference(id, edits: edits)
                toast.show("Reference copied. Paste it into Claude Code (⌘V).")
            case .discard:
                try delivery.discard(id)
                toast.show("Discarded (moved to the Trash).")
            case .close:
                try delivery.copyReference(id, edits: edits)
                toast.show("Saved to Recordings, and the reference is on your clipboard.")
            }
        } catch {
            toast.show("Couldn't save the recording: \(error.localizedDescription)", seconds: 8)
        }
        controller.reset()
        recordingsModel.reload()
    }

    private func retry(_ id: String) {
        Task {
            do {
                _ = try await lifecycle.retry(id)
                recordingsModel.reload()
                showReview(id)
            } catch {
                toast.show("Retry failed: \(error.localizedDescription)", seconds: 8)
            }
        }
    }
}
