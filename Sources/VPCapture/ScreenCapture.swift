import AVFoundation
import Foundation
import ScreenCaptureKit
import VPApp

/// ScreenCaptureKit display capture with the microphone, one `SCRecordingOutput` per segment.
/// Our own control bar is excluded; the drawing overlay is captured, so marks are in the video.
public final class ScreenCaptureBackend: NSObject, CaptureBackend, SCStreamOutput, @unchecked Sendable {
    private var stream: SCStream?
    private var output: SCRecordingOutput?
    private var finished: CheckedContinuation<Void, Error>?
    private var started: CheckedContinuation<Void, Error>?
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
        let stream = SCStream(filter: filter, configuration: config, delegate: nil)
        // ScreenCaptureKit wants a screen output to run; frames are discarded here.
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: frames)
        self.stream = stream
        do {
            try await stream.startCapture()
        } catch let e as SCStreamError where e.code == .userDeclined {
            throw CaptureError.permissionDenied
        }
        try await beginOutput(firstSegment)
    }

    public func newSegment(_ url: URL) async throws {
        try await endOutput()
        try await beginOutput(url)
    }

    public func pause() async throws { try await endOutput() }

    public func stop() async throws {
        try await endOutput()
        try await stream?.stopCapture()
        stream = nil
    }

    public func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {}

    private func beginOutput(_ url: URL) async throws {
        guard let stream else { throw CaptureError.failed("not started") }
        let cfg = SCRecordingOutputConfiguration()
        cfg.outputURL = url
        cfg.outputFileType = .mov
        cfg.videoCodecType = .h264
        let out = SCRecordingOutput(configuration: cfg, delegate: self)
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
            started = c
            do { try stream.addRecordingOutput(out) } catch { started = nil; c.resume(throwing: error) }
        }
        output = out
    }

    /// Removes the current output and waits until its file is complete on disk.
    private func endOutput() async throws {
        guard let stream, let out = output else { return }
        output = nil
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
            finished = c
            do { try stream.removeRecordingOutput(out) } catch { finished = nil; c.resume(throwing: error) }
        }
    }
}

extension ScreenCaptureBackend: SCRecordingOutputDelegate {
    public func recordingOutputDidStartRecording(_ recordingOutput: SCRecordingOutput) {
        started?.resume(); started = nil
    }

    public func recordingOutputDidFinishRecording(_ recordingOutput: SCRecordingOutput) {
        finished?.resume(); finished = nil
    }

    public func recordingOutput(_ recordingOutput: SCRecordingOutput, didFailWithError error: Error) {
        started?.resume(throwing: error); started = nil
        finished?.resume(throwing: error); finished = nil
    }
}
