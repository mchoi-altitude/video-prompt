import AVFoundation
import CoreGraphics
import Foundation

/// Times where the picture changes a lot: each sample is shrunk to 64×36 grayscale and compared
/// with the previous one; a mean absolute difference above `threshold` (0–1) is a scene change.
public func sceneChanges(in asset: AVAsset, threshold: Double = 0.1, sampleFPS: Double = 4) async throws -> [Double] {
    let duration = try await asset.load(.duration).seconds
    let gen = AVAssetImageGenerator(asset: asset)
    gen.appliesPreferredTrackTransform = true
    gen.maximumSize = CGSize(width: 160, height: 160)
    gen.requestedTimeToleranceBefore = .zero
    gen.requestedTimeToleranceAfter = .zero
    var out: [Double] = []
    var previous: [UInt8]?
    var t = 0.0
    while t < duration {
        let img = try await gen.image(at: CMTime(seconds: t, preferredTimescale: 600)).image
        let gray = grayscale(img, w: 64, h: 36)
        if let p = previous {
            let diff = zip(p, gray).reduce(0) { $0 + abs(Int($1.0) - Int($1.1)) }
            if Double(diff) / Double(gray.count) / 255 > threshold { out.append((t * 100).rounded() / 100) }
        }
        previous = gray
        t += 1 / sampleFPS
    }
    return out
}

func grayscale(_ img: CGImage, w: Int, h: Int) -> [UInt8] {
    var px = [UInt8](repeating: 0, count: w * h)
    px.withUnsafeMutableBytes { buf in
        let ctx = CGContext(data: buf.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w,
                            space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)!
        ctx.interpolationQuality = .low
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
    }
    return px
}
