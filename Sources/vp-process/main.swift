import Foundation
import VPCore
import VPProcess

// vp-process <id>: process recordings/<id>/raw and print the prompt.md path.
let args = CommandLine.arguments.dropFirst()
guard let id = args.first else {
    FileHandle.standardError.write(Data("usage: vp-process <recording-id>\n".utf8))
    exit(2)
}
let paths = Paths.default()
do {
    let store = Store(paths: paths)
    _ = try await Processor(store: store, paths: paths,
                            transcriber: WhisperCLITranscriber.fromEnvironment(paths: paths)).process(id: id)
    // No review panel here: save it as-is so Claude can fetch it.
    print(try finalize(id: id, edits: ReviewEdits(), store: store, paths: paths).path)
} catch {
    FileHandle.standardError.write(Data("vp-process: \(error)\n".utf8))
    exit(1)
}
