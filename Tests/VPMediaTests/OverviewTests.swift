import AVFoundation
import Foundation
import ImageIO
import Testing
@testable import VPMedia
import VPTestSupport

private func clip(_ seconds: Double, size: (Int, Int) = (320, 200)) async throws -> URL {
    let u = tempDir().appending(path: "c.mov")
    try await makeColorVideo(url: u, size: size, blocks: [ColorBlock(seconds / 2, (240, 240, 240)), ColorBlock(seconds / 2, (20, 20, 20))])
    return u
}

private func imageSize(_ url: URL) -> (Int, Int)? {
    guard let s = CGImageSourceCreateWithURL(url as CFURL, nil), let i = CGImageSourceCreateImageAtIndex(s, 0, nil) else { return nil }
    return (i.width, i.height)
}

@Test func overviewOneTilePerSecond() async throws {
    let v = try await clip(12)
    let out = tempDir().appending(path: "overview.jpg")
    let r = try await makeOverview(video: v, to: out, maxTiles: 60, tileWidth: 320)
    #expect(r.tiles == 12)
    #expect(r.columns == 6)
    #expect(imageSize(out).map { $0 == (6 * 320 + 5 * 4, 2 * 200 + 4) } == true)
}

@Test func overviewCapsTiles() async throws {
    let v = try await clip(600, size: (64, 40))
    let r = try await makeOverview(video: v, to: tempDir().appending(path: "o.jpg"), maxTiles: 60, tileWidth: 64)
    #expect(r.tiles == 60)
    #expect(r.secondsPerTile == 10)
}

@Test func extractFramesCountAndOrder() async throws {
    let v = try await clip(4)
    let f = try await extractFrames(video: v, from: 1, to: 2, fps: 4, maxLongEdge: 1568)
    #expect(f.map(\.t) == [1, 1.25, 1.5, 1.75, 2])
    #expect(f.allSatisfy { $0.width == 320 && $0.height == 200 && $0.jpeg.count > 100 })
}

@Test func getFramesClampsRange() async throws {
    let v = try await clip(3)
    let past = try await extractFrames(video: v, from: 5, to: 99, fps: 2, maxLongEdge: 1568)
    #expect(past.count == 1 && past[0].t <= 3)
    let reversed = try await extractFrames(video: v, from: 2, to: 1, fps: 2, maxLongEdge: 1568)
    #expect(reversed.map(\.t) == [1, 1.5, 2])
    let tooDense = try await extractFrames(video: v, from: 0, to: 1, fps: 60, maxLongEdge: 1568)
    #expect(tooDense.count == 11)   // fps is capped at 10
}

@Test func extractFramesScalesLongEdge() async throws {
    let v = try await clip(1, size: (3136, 1800))
    let f = try await extractFrames(video: v, from: 0, to: 0, fps: 1, maxLongEdge: 1568)
    #expect(f.first?.width == 1568)
}
