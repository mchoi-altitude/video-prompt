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


