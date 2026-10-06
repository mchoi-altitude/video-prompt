import Foundation

public enum CaptureError: Error, Equatable {
    /// Screen Recording isn't allowed for Video Prompt in System Settings.
    case permissionDenied
    case noDisplay(UInt32)
    case failed(String)
}

/// Records one display into pause-separated segment files. Implemented with ScreenCaptureKit
/// in VPCapture; faked in tests.
public protocol CaptureBackend: AnyObject, Sendable {
    func start(displayID: UInt32, excludingWindowIDs: [UInt32], firstSegment: URL) async throws
    /// Finishes the current file (if any) and starts writing `url`.
    func newSegment(_ url: URL) async throws
    /// Finishes the current file; the stream keeps running, nothing is written.
    func pause() async throws
    /// Finishes the current file and stops the stream.
    func stop() async throws
}
