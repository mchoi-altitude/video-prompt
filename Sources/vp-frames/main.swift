import Foundation
import VPMedia

// vp-frames <video> --from S --to E [--fps N] [--out DIR]
// Writes JPEG frames of a Video Prompt recording (so Claude Code can look closer without
// ffmpeg) and prints their paths, one per line, in time order.
var args = Array(CommandLine.arguments.dropFirst())
@MainActor func value(_ flag: String) -> String? {
    guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
    defer { args.removeSubrange(i...i + 1) }
    return args[i + 1]
}
let from = Double(value("--from") ?? "") ?? 0
let to = Double(value("--to") ?? "") ?? from
let fps = Double(value("--fps") ?? "") ?? 2
let outArg = value("--out")
guard let videoPath = args.first else {
    FileHandle.standardError.write(Data("usage: vp-frames <video> --from S --to E [--fps N] [--out DIR]\n".utf8))
    exit(2)
}
let video = URL(fileURLWithPath: videoPath)
let out = outArg.map { URL(fileURLWithPath: $0) }
    ?? FileManager.default.temporaryDirectory.appending(path: "vp-frames-\(video.deletingLastPathComponent().lastPathComponent)")
do {
    try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
    for f in try await extractFrames(video: video, from: from, to: to, fps: fps, maxLongEdge: 1568) {
        let file = out.appending(path: String(format: "t%06.1fs.jpg", f.t))
        try f.jpeg.write(to: file)
        print(file.path)
    }
} catch {
    FileHandle.standardError.write(Data("vp-frames: \(error)\n".utf8))
    exit(1)
}
