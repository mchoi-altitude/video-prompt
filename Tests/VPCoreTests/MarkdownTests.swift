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

@Test func promptMatchesGolden() throws {
    let transcript = [Sentence(start: 1, end: 2.5, text: "So, the settings page."),
                      Sentence(start: 3, end: 5.2, text: "See this Save button?")]
    let frames = [ManifestFrame(index: 1, time: 0.5, reasons: ["start"], file: "frames/frame_01_00m00.5s.jpg", width: 740, height: 560),
                  ManifestFrame(index: 2, time: 4.3, reasons: ["drawing", "narration"], file: "frames/frame_02_00m04.3s.jpg",
                                width: 740, height: 560, cursor: [40, 470])]
    let strokes = [ManifestStroke(start: 2.8, end: 4.0, tool: .pen, bbox: [47, 514, 223, 594],
                                  description: "circled the area (47,514)–(223,594)", frameIndex: 2)]
    let m = Manifest(id: "20261006-141402", duration: 12, mode: .window, transcript: transcript, frames: frames, strokes: strokes,
                     timeline: buildTimeline(frames: frames, transcript: transcript, strokes: strokes, clears: [], hidden: [7]),
                     note: "Same on Billing.")
    let golden = try String(contentsOf: Bundle.module.url(forResource: "Golden/prompt", withExtension: "md")!, encoding: .utf8)
    #expect(renderPrompt(m, recordingDir: URL(fileURLWithPath: "/R")) == golden)
}

@Test func silentPromptSaysNoNarration() {
    let m = Manifest(id: "x", duration: 3, mode: .screen, transcript: [], frames: [], strokes: [], timeline: [])
    #expect(renderPrompt(m, recordingDir: URL(fileURLWithPath: "/R")).contains("_(no narration was detected)_"))
}
