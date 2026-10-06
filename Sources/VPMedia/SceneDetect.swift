import AVFoundation
import CoreGraphics
import CoreVideo
import Foundation

/// Times where the picture changes a lot. The video is decoded once, in order, scaled down by the
/// decoder; every 1/`sampleFPS` s a 64×36 grayscale grid is compared with the previous one, and a
/// mean absolute difference above `threshold` (0–1) is a scene change.
public func sceneChanges(in asset: AVAsset, threshold: Double = 0.1, sampleFPS: Double = 4) async throws -> [Double] {
    guard let track = try await asset.loadTracks(withMediaType: .video).first else { return [] }
    let reader = try AVAssetReader(asset: asset)
    let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        kCVPixelBufferWidthKey as String: 160, kCVPixelBufferHeightKey as String: 90])
    output.alwaysCopiesSampleData = false
    reader.add(output)
    guard reader.startReading() else { throw reader.error ?? MediaError.writeFailed("scene read") }

    var out: [Double] = []
    var previous: [UInt8]?
    var next = 0.0
    while let sample = output.copyNextSampleBuffer() {
        let t = CMSampleBufferGetPresentationTimeStamp(sample).seconds
        guard t + 0.001 >= next, let pb = CMSampleBufferGetImageBuffer(sample) else { continue }
        next = (t * sampleFPS).rounded(.down) / sampleFPS + 1 / sampleFPS
        let gray = grayscale(pb, w: 64, h: 36)
        if let p = previous {
            let diff = zip(p, gray).reduce(0) { $0 + abs(Int($1.0) - Int($1.1)) }
            if Double(diff) / Double(gray.count) / 255 > threshold { out.append((t * 100).rounded() / 100) }
        }
        previous = gray
    }
    if reader.status == .failed { throw reader.error ?? MediaError.writeFailed("scene read") }
    return out
}

/// Box-averaged luminance grid from a BGRA pixel buffer.
func grayscale(_ pb: CVPixelBuffer, w: Int, h: Int) -> [UInt8] {
    CVPixelBufferLockBaseAddress(pb, .readOnly)
    defer { CVPixelBufferUnlockBaseAddress(pb, .readOnly) }
    let pw = CVPixelBufferGetWidth(pb), ph = CVPixelBufferGetHeight(pb), stride = CVPixelBufferGetBytesPerRow(pb)
    let base = CVPixelBufferGetBaseAddress(pb)!.assumingMemoryBound(to: UInt8.self)
    var out = [UInt8](repeating: 0, count: w * h)
    for gy in 0..<h {
        let y0 = gy * ph / h, y1 = max(y0 + 1, (gy + 1) * ph / h)
        for gx in 0..<w {
            let x0 = gx * pw / w, x1 = max(x0 + 1, (gx + 1) * pw / w)
            var sum = 0
            for y in y0..<y1 {
                let row = base + y * stride
                for x in x0..<x1 {
                    let p = row + x * 4
                    sum += (Int(p[2]) * 299 + Int(p[1]) * 587 + Int(p[0]) * 114) / 1000
                }
            }
            out[gy * w + gx] = UInt8(sum / ((y1 - y0) * (x1 - x0)))
        }
    }
    return out
}
