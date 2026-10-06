import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
import VPCore

/// A recording as the processor leaves it: manifest, timeline.md, overview.jpg and a stand-in
/// video.mp4 (real bytes are only needed by tests that decode it; pass `video:` for those).
@discardableResult
public func makeProcessedRecording(_ p: Paths, id: String = "20261006-141402", status: RecordingStatus = .ready,
                                   transcript: [Sentence] = [Sentence(start: 1, end: 2, text: "So, the settings page."),
                                                             Sentence(start: 3, end: 4, text: "See this.")],
                                   deliveredTo: Int32? = nil, createdAt: Date = .now, video: URL? = nil) throws -> String {
    let dir = p.recording(id)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    if let video { try FileManager.default.copyItem(at: video, to: dir.appending(path: "video.mp4")) }
    else { try Data([0, 0, 0, 0]).write(to: dir.appending(path: "video.mp4")) }
    try tinyJPEG().write(to: dir.appending(path: "overview.jpg"))
    let m = Manifest(id: id, duration: 12, mode: .window, transcript: transcript,
                     video: VideoInfo(file: "video.mp4", width: 640, height: 400, fps: VideoFPS, hasAudio: false),
                     overview: "overview.jpg", overviewSecondsPerTile: 1, strokes: [], clicks: [],
                     timeline: buildTimeline(transcript: transcript, strokes: [], clicks: [], clears: [], hidden: [], pauses: []))
    try writeJSON(m, to: dir.appending(path: "manifest.json"))
    try Data(renderTimeline(m, recordingDir: dir, vpFrames: "vp-frames").utf8).write(to: dir.appending(path: "timeline.md"))
    try writeJSON(RecordingMeta(id: id, title: "So, the settings page", createdAt: createdAt, duration: 12, mode: .window, status: status,
                                deliveredToPID: deliveredTo), to: dir.appending(path: "meta.json"))
    return id
}

public func tinyJPEG() throws -> Data {
    let ctx = CGContext(data: nil, width: 8, height: 8, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    ctx.setFillColor(CGColor(gray: 0.5, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
    let data = NSMutableData()
    let dest = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
    CGImageDestinationFinalize(dest)
    return data as Data
}
