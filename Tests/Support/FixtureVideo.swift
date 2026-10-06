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
            for y in 0..<h {
                let row = base + y * stride
                for x in 0..<w { row[x * 4] = b.rgb.2; row[x * 4 + 1] = b.rgb.1; row[x * 4 + 2] = b.rgb.0; row[x * 4 + 3] = 255 }
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
