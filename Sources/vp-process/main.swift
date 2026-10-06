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
    _ = try await Processor(store: Store(paths: paths), paths: paths,
                            transcriber: WhisperCLITranscriber.fromEnvironment(paths: paths)).process(id: id)
    print(paths.recording(id).appending(path: "prompt.md").path)
} catch {
    FileHandle.standardError.write(Data("vp-process: \(error)\n".utf8))
    exit(1)
}
