import AVFoundation
import Foundation
import Testing
import VPCore
import VPMedia
@testable import VPProcess
import VPTestSupport

private let available = WhisperCLITranscriber.fromEnvironment(paths: .default()) != nil

@Test(.enabled(if: available, "needs whisper-cli and models/ggml-base.en.bin (scripts/get-dev-model.sh)"))
func whisperTranscribesSaidSentence() async throws {
    let d = tempDir(), mov = d.appending(path: "t.mov"), wav = d.appending(path: "t.wav")
    try await makeColorVideo(url: mov, size: (64, 64), blocks: [ColorBlock(4, (0, 0, 0))], sayText: "Make the save button blue.")
    #expect(try await exportMonoWAV16k(AVURLAsset(url: mov), to: wav))
    let words = try await WhisperCLITranscriber.fromEnvironment(paths: .default())!.words(wav: wav)
    let text = words.map(\.text).joined().lowercased()
    #expect(text.contains("save"))
    #expect(text.contains("blue"))
    #expect(zip(words, words.dropFirst()).allSatisfy { $0.start <= $1.start })
}

@Test func parsesWhisperJSON() throws {
    let json = """
    {"transcription":[{"offsets":{"from":0,"to":320},"text":" Make"},{"offsets":{"from":320,"to":500},"text":" the"},
     {"offsets":{"from":500,"to":600},"text":""},{"offsets":{"from":600,"to":900},"text":" [BLANK_AUDIO]"},
     {"offsets":{"from":900,"to":1400},"text":" blue."}]}
    """
    let w = try WhisperCLITranscriber.parse(Data(json.utf8))
    #expect(w == [Word(start: 0, end: 0.32, text: " Make"), Word(start: 0.32, end: 0.5, text: " the"),
                  Word(start: 0.9, end: 1.4, text: " blue.")])
}
