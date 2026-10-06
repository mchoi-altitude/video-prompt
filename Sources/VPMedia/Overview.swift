import AVFoundation
import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers
import VPCore

public struct OverviewInfo: Sendable, Equatable {
    public var tiles, columns, secondsPerTile, width, height: Int
}

public struct VideoFrame: Sendable, Equatable {
    public var t: Double
    public var jpeg: Data
    public var width, height: Int
}

/// One contact sheet of the whole video: a labelled thumbnail per second (per N seconds past
/// `maxTiles`), six to a row, so Claude sees the entire recording at a glance.
@discardableResult
public func makeOverview(video: URL, to url: URL, maxTiles: Int = 60, tileWidth: Int = 320) async throws -> OverviewInfo {
    let asset = AVURLAsset(url: video)
    let duration = try await asset.load(.duration).seconds
    let every = max(1, Int((duration / Double(maxTiles)).rounded(.up)))
    let times = stride(from: 0.0, to: max(duration, 0.01), by: Double(every)).prefix(maxTiles).map { $0 }
    let gen = AVAssetImageGenerator(asset: asset)
    gen.appliesPreferredTrackTransform = true
    gen.maximumSize = CGSize(width: tileWidth, height: 0)
    gen.requestedTimeToleranceBefore = .zero
    gen.requestedTimeToleranceAfter = CMTime(seconds: 0.2, preferredTimescale: 600)
    var images: [CGImage] = []
    for t in times { images.append(try await gen.image(at: CMTime(seconds: min(t, max(0, duration - 0.05)), preferredTimescale: 600)).image) }
    guard let first = images.first else { throw MediaError.noImage(0) }
    let cols = min(6, images.count), rows = (images.count + cols - 1) / cols, gap = 4
    // Keep the sheet within 4000 px on its long edge (tall windows would make it huge).
    let aspect = Double(first.height) / Double(first.width)
    let natW = Double(cols * tileWidth), natH = Double(rows) * Double(tileWidth) * aspect
    let fit = min(1, Double(4000 - (cols - 1) * gap) / natW, Double(4000 - (rows - 1) * gap) / natH)
    let tw = max(16, Int((Double(tileWidth) * fit).rounded(.down))), th = max(16, Int((Double(tileWidth) * aspect * fit).rounded(.down)))
    let w = cols * tw + (cols - 1) * gap, h = rows * th + (rows - 1) * gap
    let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    ctx.setFillColor(CGColor(gray: 0.15, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
    let font = CTFontCreateWithName("Menlo-Bold" as CFString, max(10, CGFloat(tw) / 14), nil)
    for (i, img) in images.enumerated() {
        let x = (i % cols) * (tw + gap), yTop = (i / cols) * (th + gap)
        let rect = CGRect(x: x, y: h - yTop - th, width: tw, height: th)
        ctx.draw(img, in: rect)
        let s = Int(times[i])
        let label = NSAttributedString(string: String(format: " %d:%02d ", s / 60, s % 60),
                                       attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font, NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 1, alpha: 1)])
        let line = CTLineCreateWithAttributedString(label)
        let b = CTLineGetBoundsWithOptions(line, [])
        ctx.setFillColor(CGColor(gray: 0, alpha: 0.65))
        ctx.fill(CGRect(x: rect.minX + 4, y: rect.maxY - 4 - b.height - 4, width: b.width, height: b.height + 4))
        ctx.textPosition = CGPoint(x: rect.minX + 4, y: rect.maxY - 4 - b.height - 2 - b.minY)
        CTLineDraw(line, ctx)
    }
    guard let sheet = ctx.makeImage() else { throw MediaError.writeFailed("overview") }
    try jpegData(sheet, quality: 0.75).write(to: url, options: .atomic)
    return OverviewInfo(tiles: images.count, columns: cols, secondsPerTile: every, width: w, height: h)
}

/// Frames between two timestamps (clamped to the video, at least one), at up to 10 fps, long
/// edge scaled to `maxLongEdge`. More than `maxFrames` → spread evenly across the range instead.
public func extractFrames(video: URL, from: Double, to: Double, fps: Double, maxLongEdge: Int,
                          maxFrames: Int = 1000) async throws -> [VideoFrame] {
    let asset = AVURLAsset(url: video)
    let duration = try await asset.load(.duration).seconds
    let last = max(0, duration - 0.05)
    let lo = min(max(0, min(from, to)), last), hi = min(max(0, max(from, to)), last)
    var step = 1 / min(max(fps, 0.01), Double(VideoFPS))
    if hi > lo, (hi - lo) / step + 1 > Double(maxFrames) { step = (hi - lo) / Double(max(maxFrames - 1, 1)) }
    var times: [Double] = []
    var t = lo
    while t <= hi + 1e-6, times.count < maxFrames { times.append((t * 100).rounded() / 100); t += step }
    let gen = AVAssetImageGenerator(asset: asset)
    gen.appliesPreferredTrackTransform = true
    gen.requestedTimeToleranceBefore = CMTime(seconds: 0.05, preferredTimescale: 600)
    gen.requestedTimeToleranceAfter = CMTime(seconds: 0.05, preferredTimescale: 600)
    var out: [VideoFrame] = []
    for t in times {
        let img = try await gen.image(at: CMTime(seconds: t, preferredTimescale: 600)).image
        let scaled = scaleToLongEdge(img, maxLongEdge)
        out.append(VideoFrame(t: t, jpeg: try jpegData(scaled, quality: 0.8), width: scaled.width, height: scaled.height))
    }
    return out
}

func scaleToLongEdge(_ img: CGImage, _ maxLongEdge: Int) -> CGImage {
    let (w, h) = frameSize(cropW: Double(img.width), cropH: Double(img.height), longEdge: maxLongEdge)
    guard w != img.width || h != img.height,
          let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                              bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return img }
    ctx.interpolationQuality = .high
    ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
    return ctx.makeImage() ?? img
}

func jpegData(_ image: CGImage, quality: Double) throws -> Data {
    let data = NSMutableData()
    guard let dest = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else { throw MediaError.writeFailed("jpeg") }
    CGImageDestinationAddImage(dest, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
    guard CGImageDestinationFinalize(dest) else { throw MediaError.writeFailed("jpeg") }
    return data as Data
}
