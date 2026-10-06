import AVFoundation
import Foundation

public enum MediaError: Error, Equatable { case noVideoTrack(String), noImage(Double), writeFailed(String) }

/// Concatenates pause-separated segments into one asset. `durations` is keyed by 1-based
/// segment number and holds each segment's real length, for mapping event times.
public func joinSegments(_ urls: [URL]) async throws -> (asset: AVAsset, durations: [Int: Double]) {
    let comp = AVMutableComposition()
    let video = comp.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)!
    var audio: AVMutableCompositionTrack?
    var cursor = CMTime.zero
    var durations: [Int: Double] = [:]
    for (i, url) in urls.enumerated() {
        let asset = AVURLAsset(url: url)
        guard let vt = try await asset.loadTracks(withMediaType: .video).first else {
            throw MediaError.noVideoTrack(url.lastPathComponent)
        }
        let range = try await vt.load(.timeRange)
        try video.insertTimeRange(range, of: vt, at: cursor)
        if i == 0 { video.preferredTransform = try await vt.load(.preferredTransform) }
        if let at = try await asset.loadTracks(withMediaType: .audio).first {
            audio = audio ?? comp.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
            let ar = try await at.load(.timeRange)
            try audio?.insertTimeRange(CMTimeRange(start: ar.start, duration: CMTimeMinimum(ar.duration, range.duration)), of: at, at: cursor)
        }
        durations[i + 1] = range.duration.seconds
        cursor = cursor + range.duration
    }
    return (comp, durations)
}
