import AVFoundation
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
import VPCore

/// The video frame at `t`, cropped to `crop` (screen points; `display` is the captured display
/// in points, which sets the points→pixels scale).
public func grabFrame(_ asset: AVAsset, at t: Double, crop: Rect, display: Rect) async throws -> CGImage {
    let gen = AVAssetImageGenerator(asset: asset)
    gen.appliesPreferredTrackTransform = true
    gen.requestedTimeToleranceBefore = .zero
    gen.requestedTimeToleranceAfter = .zero
    let img = try await gen.image(at: CMTime(seconds: t, preferredTimescale: 600)).image
    let sx = Double(img.width) / display.w, sy = Double(img.height) / display.h
    let r = CGRect(x: (crop.x - display.x) * sx, y: (crop.y - display.y) * sy, width: crop.w * sx, height: crop.h * sy)
        .integral.intersection(CGRect(x: 0, y: 0, width: img.width, height: img.height))
    guard !r.isEmpty, let out = img.cropping(to: r) else { throw MediaError.noImage(t) }
    return out
}

/// Scales so the long edge is at most `maxLongEdge` (never up) and writes a JPEG.
@discardableResult
public func writeJPEG(_ image: CGImage, maxLongEdge: Int, to url: URL, quality: Double = 0.8) throws -> (w: Int, h: Int) {
    let (w, h) = frameSize(cropW: Double(image.width), cropH: Double(image.height), longEdge: maxLongEdge)
    let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    ctx.interpolationQuality = .high
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
    guard let scaled = ctx.makeImage(),
          let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else {
        throw MediaError.writeFailed(url.lastPathComponent)
    }
    CGImageDestinationAddImage(dest, scaled, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
    guard CGImageDestinationFinalize(dest) else { throw MediaError.writeFailed(url.lastPathComponent) }
    return (w, h)
}
