import Foundation
import Testing
@testable import VPCore

@Test func wordsSplitIntoSentences() {
    let w = [Word(start: 1, end: 1.4, text: " So,"), Word(start: 1.5, end: 2.04, text: " the page."),
             Word(start: 3, end: 3.3, text: " See"), Word(start: 3.4, end: 4.006, text: " this?"),
             Word(start: 5, end: 5.5, text: " trailing")]
    #expect(sentences(from: w) == [Sentence(start: 1, end: 2.04, text: "So, the page."),
                                   Sentence(start: 3, end: 4.01, text: "See this?"),
                                   Sentence(start: 5, end: 5.5, text: "trailing")])
}

private var utc: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c }
private let at1414 = ISO8601DateFormatter().date(from: "2026-10-06T14:14:02Z")!

@Test func titleFromFirstSentence() {
    #expect(title(for: [Sentence(start: 0, end: 1, text: "So, the settings page.")], createdAt: at1414, calendar: utc)
            == "So, the settings page")
}

@Test func titleCutsAtWordBoundary() {
    let long = "Make the primary button on the settings page blue and move it right next to Cancel please."
    let t = title(for: [Sentence(start: 0, end: 1, text: long)], createdAt: at1414, calendar: utc)
    #expect(t == "Make the primary button on the settings page blue and move…")
    #expect(t.count <= 61)
}

@Test func titleFallsBackToTime() {
    #expect(title(for: [], createdAt: at1414, calendar: utc) == "Recording 14:14")
}

private func manifest(transcript: [Sentence], strokes: [ManifestStroke] = [], clicks: [ManifestClick] = [],
                      hidden: [Double] = [], pauses: [Double] = [], note: String? = nil) -> Manifest {
    Manifest(id: "20261006-141402", duration: 12, mode: .window, transcript: transcript,
             video: VideoInfo(file: "video.mp4", width: 1394, height: 1050, fps: 10, hasAudio: true),
             overview: "overview.jpg", overviewSecondsPerTile: 1, strokes: strokes, clicks: clicks,
             timeline: buildTimeline(transcript: transcript, strokes: strokes, clicks: clicks, clears: [], hidden: hidden, pauses: pauses),
             note: note)
}

@Test func timelineMatchesGolden() throws {
    let m = manifest(transcript: [Sentence(start: 1, end: 2.5, text: "So, the settings page."),
                                  Sentence(start: 3, end: 5.2, text: "See this Save button?")],
                     strokes: [ManifestStroke(start: 2.8, end: 4.0, tool: .pen, bbox: [47, 514, 223, 594],
                                              description: "circled the area (47,514)–(223,594)")],
                     clicks: [ManifestClick(t: 6.2, x: 812, y: 96)], hidden: [7], pauses: [8.5], note: "Same on Billing.")
    let golden = try String(contentsOf: Bundle.module.url(forResource: "Golden/timeline", withExtension: "md")!, encoding: .utf8)
    #expect(renderTimeline(m, recordingDir: URL(fileURLWithPath: "/R"), vpFrames: "/Apps/vp-frames") == golden)
}

@Test func silentTimelineSaysNoNarration() {
    #expect(renderTimeline(manifest(transcript: []), recordingDir: URL(fileURLWithPath: "/R"), vpFrames: "x")
        .contains("_(no narration was detected)_"))
}

@Test func timelineMarksPauses() {
    #expect(renderTimeline(manifest(transcript: [], pauses: [3.25]), recordingDir: URL(fileURLWithPath: "/R"), vpFrames: "x")
        .contains("- **[00:03.3]** ⏸ The user paused recording here"))
}
