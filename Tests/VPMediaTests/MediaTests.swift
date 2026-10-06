import AVFoundation
import Foundation
import Testing
import VPCore
@testable import VPMedia
import VPTestSupport

@Test func joinReportsSegmentDurations() async throws {
    let d = tempDir()
    let a = d.appending(path: "seg_001.mov"), b = d.appending(path: "seg_002.mov")
    try await makeColorVideo(url: a, size: (64, 64), blocks: [ColorBlock(2, (255, 0, 0))])
    try await makeColorVideo(url: b, size: (64, 64), blocks: [ColorBlock(2, (0, 0, 255))])
    let j = try await joinSegments([a, b])
    #expect(abs(j.durations[1]! - 2) < 0.15)
    #expect(abs(j.durations[2]! - 2) < 0.15)
    #expect(abs(try await j.asset.load(.duration).seconds - 4) < 0.25)
}

@Test func sceneChangeFoundAtColorSwitch() async throws {
    let u = tempDir().appending(path: "s.mov")
    try await makeColorVideo(url: u, size: (160, 90), blocks: [ColorBlock(2, (255, 255, 255)), ColorBlock(2, (0, 0, 0))])
    let scenes = try await sceneChanges(in: AVURLAsset(url: u))
    #expect(scenes.count == 1)
    #expect(abs(scenes[0] - 2.0) <= 0.3)
}

@Test func grabFrameCropsAndScales() async throws {
    let d = tempDir(), u = d.appending(path: "big.mov")
    try await makeColorVideo(url: u, size: (3136, 1800), blocks: [ColorBlock(1, (10, 200, 10))])
    // Display is 1568×900 points on a 2× screen; crop the top half in points.
    let img = try await grabFrame(AVURLAsset(url: u), at: 0.5, crop: Rect(x: 0, y: 0, w: 1568, h: 450),
                                  display: Rect(x: 0, y: 0, w: 1568, h: 900))
    #expect(img.width == 3136 && img.height == 900)
    let size = try writeJPEG(img, maxLongEdge: 1568, to: d.appending(path: "f.jpg"))
    #expect(size == (1568, 450))
    #expect(FileManager.default.fileExists(atPath: d.appending(path: "f.jpg").path))
}

@Test func wavExportFalseWithoutAudio() async throws {
    let d = tempDir(), u = d.appending(path: "silent.mov")
    try await makeColorVideo(url: u, size: (64, 64), blocks: [ColorBlock(1, (0, 0, 0))])
    #expect(try await exportMonoWAV16k(AVURLAsset(url: u), to: d.appending(path: "a.wav")) == false)
}

@Test func wavExportWritesSpeech() async throws {
    let d = tempDir(), u = d.appending(path: "talk.mov")
    try await makeColorVideo(url: u, size: (64, 64), blocks: [ColorBlock(3, (0, 0, 0))], sayText: "Hello there.")
    let wav = d.appending(path: "a.wav")
    #expect(try await exportMonoWAV16k(AVURLAsset(url: u), to: wav))
    let data = try Data(contentsOf: wav)
    #expect(String(decoding: data.prefix(4), as: UTF8.self) == "RIFF")
    #expect(data.count > 16000)  // > 0.5 s of 16-bit mono at 16 kHz
}

private let ffmpeg = ["/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg"].first { FileManager.default.isExecutableFile(atPath: $0) }

/// Retina-size, busy 30 fps video with a long keyframe interval, like a real screen recording.
@Test(.enabled(if: ffmpeg != nil, "needs ffmpeg to build a realistic fixture"))
func sceneDetectionIsFastOnLongRecordings() async throws {
    let u = tempDir().appending(path: "long.mov")
    let p = Process()
    p.executableURL = URL(fileURLWithPath: ffmpeg!)
    p.arguments = ["-v", "error", "-f", "lavfi", "-i", "testsrc2=size=2880x1800:rate=30:duration=30",
                   "-c:v", "libx264", "-preset", "ultrafast", "-g", "300", "-pix_fmt", "yuv420p", u.path]
    try p.run(); p.waitUntilExit()
    let start = ContinuousClock.now
    _ = try await sceneChanges(in: AVURLAsset(url: u))
    let elapsed = ContinuousClock.now - start
    #expect(elapsed < .seconds(3), "30 s retina recording took \(elapsed)")
}

@Test func sceneChangeFoundInLongRecording() async throws {
    let u = tempDir().appending(path: "long.mov")
    try await makeColorVideo(url: u, size: (640, 400), blocks: [ColorBlock(15, (240, 240, 240)), ColorBlock(15, (20, 20, 20))])
    let scenes = try await sceneChanges(in: AVURLAsset(url: u))
    #expect(scenes.count == 1 && abs(scenes[0] - 15) <= 0.3)
}
