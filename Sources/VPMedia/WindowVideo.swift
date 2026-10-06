import AVFoundation
import CoreGraphics
import CoreVideo
import Foundation
import VPCore

/// A click to draw into the video, in canvas pixels (top-left origin).
public struct ClickMark: Sendable, Equatable {
    public var t, x, y: Double
    public init(t: Double, x: Double, y: Double) { self.t = t; self.x = x; self.y = y }
}

public struct RenderedVideo: Sendable, Equatable {
    public var width, height: Int
    public var duration: Double
    public var hasAudio: Bool
}

/// Renders the recorded window as its own video: every captured frame is cropped to `crop(t)`
/// (screen points; clipped to `display`), drawn top-left on a fixed `canvas` (pixels) padded with
/// #111111, click rings drawn on top. Narration audio is carried over unchanged.
public func renderWindowVideo(asset: AVAsset, display: Rect, canvas: (Int, Int), crop: @escaping @Sendable (Double) -> Rect?,
                              clicks: [ClickMark], fps: Int = VideoFPS, to url: URL) async throws -> RenderedVideo {
    let (cw, ch) = (max(2, canvas.0 / 2 * 2), max(2, canvas.1 / 2 * 2))
    let silent = url.deletingLastPathComponent().appending(path: ".render-\(UUID().uuidString).mp4")
    defer { try? FileManager.default.removeItem(at: silent) }
    guard let track = try await asset.loadTracks(withMediaType: .video).first else { throw MediaError.noVideoTrack("render") }
    let natural = try await track.load(.naturalSize)
    let sx = Double(natural.width) / display.w, sy = Double(natural.height) / display.h

    // Decode in order, full resolution, BGRA.
    let reader = try AVAssetReader(asset: asset)
    let output = AVAssetReaderTrackOutput(track: track, outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
    output.alwaysCopiesSampleData = false
    reader.add(output)

    let writer = try AVAssetWriter(outputURL: silent, fileType: .mp4)
    let codec: AVVideoCodecType = cw * ch > 4096 * 2304 ? .hevc : .h264
    let input = AVAssetWriterInput(mediaType: .video, outputSettings: [AVVideoCodecKey: codec, AVVideoWidthKey: cw, AVVideoHeightKey: ch])
    input.expectsMediaDataInRealTime = false
    let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA, kCVPixelBufferWidthKey as String: cw,
        kCVPixelBufferHeightKey as String: ch])
    writer.add(input)
    guard reader.startReading() else { throw reader.error ?? MediaError.writeFailed("render read") }
    guard writer.startWriting() else { throw writer.error ?? MediaError.writeFailed("render write") }
    writer.startSession(atSourceTime: .zero)

    let space = CGColorSpaceCreateDeviceRGB()
    let bitmap = CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue
    let step = 1.0 / Double(fps)
    // Each frame belongs to its nearest 1/fps slot; the first frame of each new slot is kept.
    // (Comparing against a running "next" time drops early-jittered frames and, through
    // floating-point floor(0.3 / 0.1) == 2, lets extra ones through.)
    var lastSlot = -1
    var last = 0.0
    while let sample = output.copyNextSampleBuffer() {
        let pts = CMSampleBufferGetPresentationTimeStamp(sample)
        let t = pts.seconds
        let slot = Int((t / step).rounded())
        guard slot > lastSlot, let src = CMSampleBufferGetImageBuffer(sample) else { continue }
        lastSlot = slot
        last = t
        try await waitUntilReady(input)
        guard let pool = adaptor.pixelBufferPool else { throw MediaError.writeFailed("pool") }
        var outBuf: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, pool, &outBuf)
        guard let dst = outBuf else { throw MediaError.writeFailed("buffer") }
        CVPixelBufferLockBaseAddress(dst, [])
        CVPixelBufferLockBaseAddress(src, .readOnly)
        let ctx = CGContext(data: CVPixelBufferGetBaseAddress(dst), width: cw, height: ch, bitsPerComponent: 8,
                            bytesPerRow: CVPixelBufferGetBytesPerRow(dst), space: space, bitmapInfo: bitmap)!
        ctx.setFillColor(CGColor(srgbRed: 17 / 255, green: 17 / 255, blue: 17 / 255, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: cw, height: ch))
        if let c = crop(t).flatMap({ clipRect($0, to: display) }),
           let srcCtx = CGContext(data: CVPixelBufferGetBaseAddress(src), width: CVPixelBufferGetWidth(src),
                                  height: CVPixelBufferGetHeight(src), bitsPerComponent: 8,
                                  bytesPerRow: CVPixelBufferGetBytesPerRow(src), space: space, bitmapInfo: bitmap),
           let full = srcCtx.makeImage() {
            let px = CGRect(x: (c.x - display.x) * sx, y: (c.y - display.y) * sy, width: c.w * sx, height: c.h * sy).integral
                .intersection(CGRect(x: 0, y: 0, width: full.width, height: full.height))
            if let piece = full.cropping(to: px) {
                // CG's origin is bottom-left: pin the piece to the canvas's top-left.
                ctx.draw(piece, in: CGRect(x: 0, y: Double(ch) - Double(piece.height), width: Double(piece.width), height: Double(piece.height)))
            }
        }
        drawClickRings(ctx, clicks: clicks, t: t, canvasHeight: ch)
        CVPixelBufferUnlockBaseAddress(src, .readOnly)
        CVPixelBufferUnlockBaseAddress(dst, [])
        if !adaptor.append(dst, withPresentationTime: pts) { throw writer.error ?? MediaError.writeFailed("append") }
    }
    input.markAsFinished()
    await writer.finishWriting()
    if writer.status != .completed { throw writer.error ?? MediaError.writeFailed("render finish") }
    if reader.status == .failed { throw reader.error ?? MediaError.writeFailed("render read") }

    // Carry the narration over (passthrough), or keep the silent render.
    let audio = try await asset.loadTracks(withMediaType: .audio).first
    try? FileManager.default.removeItem(at: url)
    let duration = last + step
    guard let audio else {
        try FileManager.default.moveItem(at: silent, to: url)
        return RenderedVideo(width: cw, height: ch, duration: duration, hasAudio: false)
    }
    let rendered = AVURLAsset(url: silent)
    let comp = AVMutableComposition()
    let vDur = try await rendered.load(.duration)
    try comp.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)!
        .insertTimeRange(CMTimeRange(start: .zero, duration: vDur), of: try await rendered.loadTracks(withMediaType: .video)[0], at: .zero)
    let aRange = try await audio.load(.timeRange)
    try comp.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)!
        .insertTimeRange(CMTimeRange(start: aRange.start, duration: CMTimeMinimum(aRange.duration, vDur)), of: audio, at: .zero)
    guard let ex = AVAssetExportSession(asset: comp, presetName: AVAssetExportPresetPassthrough) else {
        throw MediaError.writeFailed("mux")
    }
    try await ex.export(to: url, as: .mp4)
    return RenderedVideo(width: cw, height: ch, duration: duration, hasAudio: true)
}

/// Waits for the encoder, but never forever: a starved hardware encoder must fail, not hang.
func waitUntilReady(_ input: AVAssetWriterInput, timeout: Double = 15) async throws {
    let deadline = Date().addingTimeInterval(timeout)
    while !input.isReadyForMoreMediaData {
        if Date() > deadline { throw MediaError.writeFailed("video encoder not ready after \(Int(timeout)) s") }
        try await Task.sleep(for: .milliseconds(2))
    }
}

func clipRect(_ r: Rect, to b: Rect) -> Rect? {
    let x0 = max(r.x, b.x), y0 = max(r.y, b.y), x1 = min(r.x + r.w, b.x + b.w), y1 = min(r.y + r.h, b.y + b.h)
    return x1 > x0 && y1 > y0 ? Rect(x: x0, y: y0, w: x1 - x0, h: y1 - y0) : nil
}

/// A ring that grows from 6 to 28 px and fades out over 0.5 s after each click.
func drawClickRings(_ ctx: CGContext, clicks: [ClickMark], t: Double, canvasHeight: Int) {
    for c in clicks where t >= c.t && t - c.t <= 0.5 {
        let p = (t - c.t) / 0.5
        let r = 6 + 22 * p
        ctx.setStrokeColor(CGColor(srgbRed: 0xE5 / 255, green: 0x48 / 255, blue: 0x4D / 255, alpha: 1 - p))
        ctx.setLineWidth(3)
        ctx.strokeEllipse(in: CGRect(x: c.x - r, y: Double(canvasHeight) - c.y - r, width: 2 * r, height: 2 * r))
    }
}
