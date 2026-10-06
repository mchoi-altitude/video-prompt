import Foundation
import VPCore

public protocol Transcriber: Sendable {
    func words(wav: URL) async throws -> [Word]
}

public enum TranscriberError: Error { case failed(status: Int32, stderr: String) }

/// On-device transcription with whisper.cpp's `whisper-cli`, one segment per word so each word
/// carries its own timestamps.
public struct WhisperCLITranscriber: Transcriber {
    public let cli: URL
    public let model: URL
    public init(cli: URL, model: URL) { self.cli = cli; self.model = model }

    /// `VIDEO_PROMPT_WHISPER_CLI` / `VIDEO_PROMPT_WHISPER_MODEL`, else Homebrew's whisper-cli and
    /// `models/ggml-base.en.bin`. nil when either is missing.
    public static func fromEnvironment(paths: Paths) -> WhisperCLITranscriber? {
        let env = ProcessInfo.processInfo.environment
        let fm = FileManager.default
        let cliPath = env["VIDEO_PROMPT_WHISPER_CLI"]
            ?? ["/opt/homebrew/bin/whisper-cli", "/usr/local/bin/whisper-cli"].first { fm.isExecutableFile(atPath: $0) }
        let modelPath = env["VIDEO_PROMPT_WHISPER_MODEL"] ?? paths.models.appending(path: "ggml-base.en.bin").path
        guard let cliPath, fm.isExecutableFile(atPath: cliPath), fm.fileExists(atPath: modelPath) else { return nil }
        return WhisperCLITranscriber(cli: URL(fileURLWithPath: cliPath), model: URL(fileURLWithPath: modelPath))
    }

    public func words(wav: URL) async throws -> [Word] {
        let base = FileManager.default.temporaryDirectory.appending(path: "vp-whisper-\(UUID().uuidString)")
        let p = Process()
        p.executableURL = cli
        p.arguments = ["-m", model.path, "-f", wav.path, "-l", "en", "-ml", "1", "-sow", "-oj", "-of", base.path, "-np"]
        let err = Pipe()
        p.standardError = err
        p.standardOutput = FileHandle.nullDevice
        try p.run()
        let errData = err.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        let json = base.appendingPathExtension("json")
        defer { try? FileManager.default.removeItem(at: json) }
        guard p.terminationStatus == 0 else {
            throw TranscriberError.failed(status: p.terminationStatus, stderr: String(decoding: errData, as: UTF8.self))
        }
        return try Self.parse(Data(contentsOf: json))
    }

    private struct Output: Decodable {
        struct Item: Decodable { struct Off: Decodable { var from, to: Int }; var offsets: Off; var text: String }
        var transcription: [Item]
    }

    static func parse(_ data: Data) throws -> [Word] {
        try JSONDecoder().decode(Output.self, from: data).transcription.compactMap { item in
            let t = item.text.trimmingCharacters(in: .whitespaces)
            guard !t.isEmpty, !(t.hasPrefix("[") && t.hasSuffix("]")) else { return nil }
            return Word(start: Double(item.offsets.from) / 1000, end: Double(item.offsets.to) / 1000, text: item.text)
        }
    }
}
