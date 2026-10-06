import AVFoundation
import Foundation
import ScreenCaptureKit
import VPApp

/// ScreenCaptureKit display capture with the microphone, one `SCRecordingOutput` per segment.
/// Our own control bar is excluded; the drawing overlay is captured, so marks are in the video.
///
/// Failure handling: every wait on ScreenCaptureKit has a timeout, a failed output is never
/// waited on, `stop()` always stops the stream (and so the microphone), and an unexpected stop
/// (menu-bar indicator, display unplugged, sleep) is reported through `onUnexpectedStop`.
public final class ScreenCaptureBackend: NSObject, CaptureBackend, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    /// Called on the main queue when the system ends capture on its own.
    public var onUnexpectedStop: (@MainActor (String) -> Void)?

    private let lock = NSLock()
    private var stream: SCStream?
    private var output: SCRecordingOutput?
    private var outputFailed = false
    private var stopping = false
    private var pending: [ObjectIdentifier: CheckedContinuation<Void, Error>] = [:]
    private let frames = DispatchQueue(label: "vp.capture.frames")

    public override init() {}

    public func start(displayID: UInt32, excludingWindowIDs: [UInt32], firstSegment: URL) async throws {
        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        } catch let e as SCStreamError where e.code == .userDeclined {
            throw CaptureError.permissionDenied
        }
        guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
            throw CaptureError.noDisplay(displayID)
        }
        let excluded = content.windows.filter { excludingWindowIDs.contains($0.windowID) }
        let filter = SCContentFilter(display: display, excludingWindows: excluded)
        let config = SCStreamConfiguration()
        let scale = Double(filter.pointPixelScale)
        config.width = Int(Double(display.width) * scale)
        config.height = Int(Double(display.height) * scale)
        config.minimumFrameInterval = CMTime(value: 1, timescale: 30)
        config.showsCursor = true
        config.capturesAudio = false
        config.captureMicrophone = true
        let stream = SCStream(filter: filter, configuration: config, delegate: self)
        // ScreenCaptureKit wants a screen output to run; frames are discarded here.
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: frames)
        lock.withLock { self.stream = stream; stopping = false }
        do {
            try await stream.startCapture()
        } catch let e as SCStreamError where e.code == .userDeclined {
            lock.withLock { self.stream = nil }
            throw CaptureError.permissionDenied
        }
        do {
            try await beginOutput(firstSegment, width: config.width, height: config.height)
        } catch {
            // Don't leave the screen and microphone running behind a failed start.
            try? await stream.stopCapture()
            lock.withLock { self.stream = nil }
            throw error
        }
    }

    public func newSegment(_ url: URL) async throws {
        try await endOutput()
        guard lock.withLock({ stream }) != nil else { throw CaptureError.failed("not recording") }
        try await beginOutput(url, width: lastSize.w, height: lastSize.h)
    }

    public func pause() async throws { try await endOutput() }

    public func stop() async throws {
        lock.withLock { stopping = true }
        // Finish the file if we can, but always stop the stream, and with it the microphone.
        try? await endOutput()
        let s = lock.withLock { () -> SCStream? in defer { stream = nil }; return stream }
        try? await s?.stopCapture()
    }

    public func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {}

    public func stream(_ stream: SCStream, didStopWithError error: Error) {
        let wasStopping = lock.withLock { () -> Bool in
            outputFailed = true
            self.stream = nil
            return stopping
        }
        resumeAll(throwing: error)
        guard !wasStopping else { return }
        let message = "Recording stopped: \(error.localizedDescription)"
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated { self?.onUnexpectedStop?(message) }
        }
    }

    // MARK: Recording outputs

    private var lastSize: (w: Int, h: Int) = (0, 0)

    private func beginOutput(_ url: URL, width: Int, height: Int) async throws {
        guard let stream = lock.withLock({ self.stream }) else { throw CaptureError.failed("not recording") }
        lastSize = (width, height)
        let cfg = SCRecordingOutputConfiguration()
        cfg.outputURL = url
        cfg.outputFileType = .mov
        // H.264 tops out around 4096×2304; 5K/6K displays need HEVC.
        cfg.videoCodecType = width * height > 4096 * 2304 ? .hevc : .h264
        let out = SCRecordingOutput(configuration: cfg, delegate: self)
        lock.withLock { outputFailed = false }
        try await wait(for: out, timeout: 10) {
            try stream.addRecordingOutput(out)
        }
        lock.withLock { output = out }
    }

    /// Removes the current output and waits until its file is complete on disk; a failed output
    /// is just dropped.
    private func endOutput() async throws {
        let (stream, out, failed) = lock.withLock { () -> (SCStream?, SCRecordingOutput?, Bool) in
            defer { output = nil }
            return (self.stream, output, outputFailed)
        }
        guard let stream, let out else { return }
        if failed { try? stream.removeRecordingOutput(out); return }
        try await wait(for: out, timeout: 10) {
            try stream.removeRecordingOutput(out)
        }
    }

    /// Runs `action`, then waits for the output's next delegate callback (started / finished /
    /// failed), giving up after `timeout` seconds.
    private func wait(for out: SCRecordingOutput, timeout: Double, _ action: @escaping () throws -> Void) async throws {
        let key = ObjectIdentifier(out)
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
            lock.withLock { pending[key] = c }
            do { try action() } catch { resume(key, with: .failure(error)); return }
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) { [weak self] in
                self?.resume(key, with: .failure(CaptureError.failed("ScreenCaptureKit didn't respond in \(Int(timeout)) s")))
            }
        }
    }

    private func resume(_ key: ObjectIdentifier, with result: Result<Void, Error>) {
        let c = lock.withLock { pending.removeValue(forKey: key) }
        c?.resume(with: result)
    }

    private func resumeAll(throwing error: Error) {
        let all = lock.withLock { () -> [CheckedContinuation<Void, Error>] in defer { pending.removeAll() }; return Array(pending.values) }
        all.forEach { $0.resume(throwing: error) }
    }
}

extension ScreenCaptureBackend: SCRecordingOutputDelegate {
    public func recordingOutputDidStartRecording(_ recordingOutput: SCRecordingOutput) {
        resume(ObjectIdentifier(recordingOutput), with: .success(()))
    }

    public func recordingOutputDidFinishRecording(_ recordingOutput: SCRecordingOutput) {
        resume(ObjectIdentifier(recordingOutput), with: .success(()))
    }

    public func recordingOutput(_ recordingOutput: SCRecordingOutput, didFailWithError error: Error) {
        lock.withLock { outputFailed = true }
        resume(ObjectIdentifier(recordingOutput), with: .failure(error))
    }
}
