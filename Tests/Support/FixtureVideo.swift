import AVFoundation
import CoreVideo
import Foundation

public struct ColorBlock: Sendable {
    public var seconds: Double
    public var rgb: (UInt8, UInt8, UInt8)
    public init(_ seconds: Double, _ rgb: (UInt8, UInt8, UInt8)) { self.seconds = seconds; self.rgb = rgb }
}

public enum FixtureError: Error { case writer(String) }

/// Writes an H.264 .mov of solid-color blocks at 10 fps. With `sayText`, macOS `say` speaks it
/// and the speech is muxed in as the audio track.
public func makeColorVideo(url: URL, size: (Int, Int), blocks: [ColorBlock], sayText: String? = nil) async throws {
    let videoOnly = sayText == nil ? url : url.deletingLastPathComponent().appending(path: "v-\(UUID().uuidString).mov")
    try await writeVideo(url: videoOnly, size: size, blocks: blocks)
    guard let text = sayText else { return }
    let aiff = url.deletingLastPathComponent().appending(path: "a-\(UUID().uuidString).aiff")
    let say = Process()
    say.executableURL = URL(fileURLWithPath: "/usr/bin/say")
    say.arguments = ["-o", aiff.path, text]
    try say.run(); say.waitUntilExit()

    let comp = AVMutableComposition()
    let v = AVURLAsset(url: videoOnly), a = AVURLAsset(url: aiff)
    let vDur = try await v.load(.duration)
    let vt = try await v.loadTracks(withMediaType: .video)[0]
    try comp.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)!
        .insertTimeRange(CMTimeRange(start: .zero, duration: vDur), of: vt, at: .zero)
    let at = try await a.loadTracks(withMediaType: .audio)[0]
    let aDur = try await a.load(.duration)
    try comp.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)!
        .insertTimeRange(CMTimeRange(start: .zero, duration: CMTimeMinimum(aDur, vDur)), of: at, at: .zero)
    guard let ex = AVAssetExportSession(asset: comp, presetName: AVAssetExportPresetHighestQuality) else {
        throw FixtureError.writer("no export session")
    }
    try await ex.export(to: url, as: .mov)
}

private func writeVideo(url: URL, size: (Int, Int), blocks: [ColorBlock]) async throws {
    let (w, h) = size
    let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
    let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
        AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: w, AVVideoHeightKey: h])
    input.expectsMediaDataInRealTime = false
    let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA, kCVPixelBufferWidthKey as String: w,
        kCVPixelBufferHeightKey as String: h])
    writer.add(input)
    guard writer.startWriting() else { throw FixtureError.writer(writer.error.map { "\($0)" } ?? "start") }
    writer.startSession(atSourceTime: .zero)
    let fps = 10
    var frame = 0
    for b in blocks {
        for _ in 0..<Int(b.seconds * Double(fps)) {
            while !input.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(5)) }
            var pb: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, adaptor.pixelBufferPool!, &pb)
            let buf = pb!
            CVPixelBufferLockBaseAddress(buf, [])
            let base = CVPixelBufferGetBaseAddress(buf)!.assumingMemoryBound(to: UInt8.self)
            let stride = CVPixelBufferGetBytesPerRow(buf)
            if b.rgb.0 == b.rgb.1 && b.rgb.1 == b.rgb.2 {
                memset(base, Int32(b.rgb.0), stride * h)  // gray: every byte the same (alpha unused by H.264)
            } else {
                for y in 0..<h {
                    let row = base + y * stride
                    for x in 0..<w { row[x * 4] = b.rgb.2; row[x * 4 + 1] = b.rgb.1; row[x * 4 + 2] = b.rgb.0; row[x * 4 + 3] = 255 }
                }
            }
            CVPixelBufferUnlockBaseAddress(buf, [])
            adaptor.append(buf, withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: CMTimeScale(fps)))
            frame += 1
        }
    }
    input.markAsFinished()
    await writer.finishWriting()
    if writer.status != .completed { throw FixtureError.writer(writer.error.map { "\($0)" } ?? "finish") }
}

public func tempDir() -> URL {
    let d = FileManager.default.temporaryDirectory.appending(path: "vpt-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
    return d
}

/// A video whose four quadrants are red (top-left), green (top-right), blue (bottom-left) and
/// yellow (bottom-right), so crops can be checked by color. 10 fps, optional `say` audio.
public func makeQuadrantVideo(url: URL, size: (Int, Int), seconds: Double, sayText: String? = nil) async throws {
    let (w, h) = size
    let tmp = url.deletingLastPathComponent().appending(path: "q-\(UUID().uuidString).mov")
    let writer = try AVAssetWriter(outputURL: sayText == nil ? url : tmp, fileType: .mov)
    let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
        AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: w, AVVideoHeightKey: h])
    let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA, kCVPixelBufferWidthKey as String: w,
        kCVPixelBufferHeightKey as String: h])
    writer.add(input)
    writer.startWriting(); writer.startSession(atSourceTime: .zero)
    for i in 0..<Int(seconds * 10) {
        while !input.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(5)) }
        var pb: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, adaptor.pixelBufferPool!, &pb)
        let buf = pb!
        CVPixelBufferLockBaseAddress(buf, [])
        let base = CVPixelBufferGetBaseAddress(buf)!.assumingMemoryBound(to: UInt8.self)
        let stride = CVPixelBufferGetBytesPerRow(buf)
        for y in 0..<h {
            for x in 0..<w {
                let (r, g, b): (UInt8, UInt8, UInt8) = switch (x < w / 2, y < h / 2) {
                case (true, true): (230, 30, 30); case (false, true): (30, 200, 30)
                case (true, false): (30, 30, 230); case (false, false): (230, 210, 30)
                }
                let p = base + y * stride + x * 4
                p[0] = b; p[1] = g; p[2] = r; p[3] = 255
            }
        }
        CVPixelBufferUnlockBaseAddress(buf, [])
        adaptor.append(buf, withPresentationTime: CMTime(value: CMTimeValue(i), timescale: 10))
    }
    input.markAsFinished()
    await writer.finishWriting()
    guard let text = sayText else { return }
    // Reuse makeColorVideo's muxing by recording speech over the quadrant video.
    let aiff = url.deletingLastPathComponent().appending(path: "a-\(UUID().uuidString).aiff")
    let say = Process(); say.executableURL = URL(fileURLWithPath: "/usr/bin/say"); say.arguments = ["-o", aiff.path, text]
    try say.run(); say.waitUntilExit()
    let comp = AVMutableComposition()
    let v = AVURLAsset(url: tmp), a = AVURLAsset(url: aiff)
    let vDur = try await v.load(.duration)
    try comp.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)!
        .insertTimeRange(CMTimeRange(start: .zero, duration: vDur), of: try await v.loadTracks(withMediaType: .video)[0], at: .zero)
    let aDur = try await a.load(.duration)
    try comp.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)!
        .insertTimeRange(CMTimeRange(start: .zero, duration: CMTimeMinimum(aDur, vDur)), of: try await a.loadTracks(withMediaType: .audio)[0], at: .zero)
    guard let ex = AVAssetExportSession(asset: comp, presetName: AVAssetExportPresetHighestQuality) else { throw FixtureError.writer("export") }
    try await ex.export(to: url, as: .mov)
}

/// RGB of the pixel at (x, y) (top-left origin) of the video frame at `t`.
public func pixel(_ url: URL, at t: Double, x: Int, y: Int) async throws -> (r: Int, g: Int, b: Int) {
    let gen = AVAssetImageGenerator(asset: AVURLAsset(url: url))
    gen.requestedTimeToleranceBefore = .zero; gen.requestedTimeToleranceAfter = .zero
    let img = try await gen.image(at: CMTime(seconds: t, preferredTimescale: 600)).image
    var px = [UInt8](repeating: 0, count: 4)
    let ctx = CGContext(data: &px, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    ctx.draw(img, in: CGRect(x: -x, y: -(img.height - 1 - y), width: img.width, height: img.height))
    return (Int(px[0]), Int(px[1]), Int(px[2]))
}

public func isClose(_ a: (r: Int, g: Int, b: Int), _ b: (Int, Int, Int), tolerance: Int = 40) -> Bool {
    abs(a.r - b.0) <= tolerance && abs(a.g - b.1) <= tolerance && abs(a.b - b.2) <= tolerance
}

/// A gray video whose frames sit at exactly `times` (seconds), e.g. a jittery 10 fps capture.
public func makeTimedVideo(url: URL, size: (Int, Int), times: [Double]) async throws {
    let (w, h) = size
    let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
    let input = AVAssetWriterInput(mediaType: .video, outputSettings: [AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: w, AVVideoHeightKey: h])
    let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA, kCVPixelBufferWidthKey as String: w, kCVPixelBufferHeightKey as String: h])
    writer.add(input)
    writer.startWriting(); writer.startSession(atSourceTime: .zero)
    for (i, t) in times.enumerated() {
        while !input.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(5)) }
        var pb: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, adaptor.pixelBufferPool!, &pb)
        CVPixelBufferLockBaseAddress(pb!, [])
        memset(CVPixelBufferGetBaseAddress(pb!), Int32(40 + (i % 5) * 40), CVPixelBufferGetBytesPerRow(pb!) * h)
        CVPixelBufferUnlockBaseAddress(pb!, [])
        adaptor.append(pb!, withPresentationTime: CMTime(seconds: t, preferredTimescale: 6000))
    }
    input.markAsFinished()
    await writer.finishWriting()
}
