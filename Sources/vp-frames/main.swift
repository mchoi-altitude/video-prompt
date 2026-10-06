import Foundation
import VPMedia

// vp-frames <video> --from S --to E [--fps N] [--out DIR]
// Writes JPEG frames of a Video Prompt recording (so Claude Code can look closer without
// ffmpeg) and prints their paths, one per line, in time order. At most 100 frames per call:
// wider ranges are spread evenly. Each call writes to a fresh folder unless --out is given.
let usage = "usage: vp-frames <video> --from S --to E [--fps N (≤10, default 2)] [--out DIR]\n"
func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("vp-frames: \(message)\n\(usage)".utf8))
    exit(2)
}

var video: String?
var options: [String: String] = [:]
var rest = Array(CommandLine.arguments.dropFirst())
while !rest.isEmpty {
    let a = rest.removeFirst()
    if ["--from", "--to", "--fps", "--out"].contains(a) {
        guard !rest.isEmpty else { fail("\(a) needs a value") }
        options[a] = rest.removeFirst()
    } else if a.hasPrefix("--") {
        fail("unknown option \(a)")
    } else if video == nil {
        video = a
    } else {
        fail("unexpected argument \(a)")
    }
}
guard let video else { fail("no video given") }
@MainActor func number(_ flag: String, default d: Double?) -> Double {
    guard let s = options[flag] else {
        guard let d else { fail("\(flag) is required") }
        return d
    }
    guard let v = Double(s), v.isFinite else { fail("\(flag) must be a number, got \"\(s)\"") }
    return v
}
let from = number("--from", default: nil)
let to = number("--to", default: from)
let fps = number("--fps", default: 2)
let videoURL = URL(fileURLWithPath: video)
let out = options["--out"].map { URL(fileURLWithPath: $0) }
    ?? FileManager.default.temporaryDirectory.appending(path: "vp-frames/\(UUID().uuidString.prefix(8))")
do {
    try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
    let frames = try await extractFrames(video: videoURL, from: from, to: to, fps: fps, maxLongEdge: 1568, maxFrames: 100)
    for (i, f) in frames.enumerated() {
        // Index first (unique even when two times round alike), then the exact time.
        let file = out.appending(path: String(format: "%03d_t%08.2fs.jpg", i + 1, f.t))
        try f.jpeg.write(to: file)
        print(file.path)
    }
} catch {
    FileHandle.standardError.write(Data("vp-frames: \(error)\n".utf8))
    exit(1)
}
