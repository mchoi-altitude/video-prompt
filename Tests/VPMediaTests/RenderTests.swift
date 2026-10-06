import AVFoundation
import Foundation
import Testing
import VPCore
@testable import VPMedia
import VPTestSupport

private let red = (230, 30, 30), pad = (17, 17, 17)
private let display = Rect(x: 0, y: 0, w: 640, h: 400)

private func quadrants(seconds: Double = 2, say: String? = nil) async throws -> URL {
    let u = tempDir().appending(path: "q.mov")
    try await makeQuadrantVideo(url: u, size: (640, 400), seconds: seconds, sayText: say)
    return u
}

@Test func renderCropsToWindowAndFollowsResize() async throws {
    let src = try await quadrants()
    let out = tempDir().appending(path: "w.mp4")
    // 0–1 s: the window is the top-left quadrant; after 1 s it shrinks to a 160×100 piece of it.
    let r = try await renderWindowVideo(asset: AVURLAsset(url: src), display: display, canvas: (320, 200),
                                        crop: { $0 < 1 ? Rect(x: 0, y: 0, w: 320, h: 200) : Rect(x: 0, y: 0, w: 160, h: 100) },
                                        clicks: [], to: out)
    #expect(r.width == 320 && r.height == 200)
    #expect(isClose(try await pixel(out, at: 0.5, x: 300, y: 180), red))      // whole quadrant shown
    #expect(isClose(try await pixel(out, at: 1.5, x: 100, y: 50), red))       // smaller crop, top-left
    #expect(isClose(try await pixel(out, at: 1.5, x: 300, y: 180), pad))      // padded beyond it
}

@Test func renderClipsToDisplay() async throws {
    let src = try await quadrants()
    let out = tempDir().appending(path: "w.mp4")
    // A window hanging 100 pt off the left edge: only its on-screen part is captured.
    _ = try await renderWindowVideo(asset: AVURLAsset(url: src), display: display, canvas: (220, 200),
                                    crop: { _ in Rect(x: -100, y: 0, w: 320, h: 200) }, clicks: [], to: out)
    #expect(isClose(try await pixel(out, at: 0.5, x: 10, y: 10), red))
}

@Test func hiddenWindowRendersPadding() async throws {
    let src = try await quadrants()
    let out = tempDir().appending(path: "w.mp4")
    _ = try await renderWindowVideo(asset: AVURLAsset(url: src), display: display, canvas: (320, 200),
                                    crop: { $0 < 1 ? Rect(x: 0, y: 0, w: 320, h: 200) : nil }, clicks: [], to: out)
    #expect(isClose(try await pixel(out, at: 1.5, x: 100, y: 100), pad))
}

@Test func clickRingDrawnAtClick() async throws {
    let src = try await quadrants()
    let out = tempDir().appending(path: "w.mp4")
    // Crop the green quadrant so a red ring stands out; click at (80, 100), t = 0.5.
    _ = try await renderWindowVideo(asset: AVURLAsset(url: src), display: display, canvas: (320, 200),
                                    crop: { _ in Rect(x: 320, y: 0, w: 320, h: 200) },
                                    clicks: [ClickMark(t: 0.5, x: 80, y: 100)], to: out)
    // At +0.1 s the ring radius is 6 + 22 × 0.2 ≈ 10.4 px (still 80% opaque).
    let onRing = try await pixel(out, at: 0.6, x: 80 + 10, y: 100)
    #expect(onRing.r > 150 && onRing.g < 150)
    // Gone after 0.5 s: back to the source's own green (H.264 shifts colors, so compare to it).
    let srcGreen = try await pixel(src, at: 1.3, x: 320 + 90, y: 100)
    #expect(isClose(try await pixel(out, at: 1.3, x: 80 + 10, y: 100), (srcGreen.r, srcGreen.g, srcGreen.b), tolerance: 30))
}

@Test func renderCarriesAudio() async throws {
    let src = try await quadrants(seconds: 2, say: "Hello.")
    let out = tempDir().appending(path: "w.mp4")
    let r = try await renderWindowVideo(asset: AVURLAsset(url: src), display: display, canvas: (320, 200),
                                        crop: { _ in Rect(x: 0, y: 0, w: 320, h: 200) }, clicks: [], to: out)
    #expect(r.hasAudio)
    #expect(try await !AVURLAsset(url: out).loadTracks(withMediaType: .audio).isEmpty)
}

@Test func renderWithoutAudio() async throws {
    let src = try await quadrants()
    let out = tempDir().appending(path: "w.mp4")
    let r = try await renderWindowVideo(asset: AVURLAsset(url: src), display: display, canvas: (320, 200),
                                        crop: { _ in Rect(x: 0, y: 0, w: 320, h: 200) }, clicks: [], to: out)
    #expect(!r.hasAudio)
    #expect(abs(r.duration - 2) < 0.2)
}
