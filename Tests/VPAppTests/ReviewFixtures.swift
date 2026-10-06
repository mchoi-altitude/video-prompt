import Foundation
import VPCore
import VPProcess
import VPTestSupport
@testable import VPApp

final class FakePasteboard: Pasteboard, @unchecked Sendable {
    var value: String?
    func setString(_ s: String) { value = s }
}

final class RecordingTrasher: Trasher, @unchecked Sendable {
    var trashed: [String] = []
    func trash(_ url: URL) throws { trashed.append(url.lastPathComponent); try FileManager.default.removeItem(at: url) }
}

/// A recording in review: two sentences.
func reviewingRecording(_ p: Paths, id: String = "20261006-141402") throws -> String {
    try makeProcessedRecording(p, id: id, status: .reviewing)
}
