import Foundation
import Testing
import VPCore
@testable import VPMCP
import VPTestSupport

private let myPID: Int32 = 4242

private func server(_ paths: Paths, poll: Duration = .milliseconds(10)) -> MCPServer {
    MCPServer(store: Store(paths: paths), waiters: Waiters(paths: paths), pid: myPID, cwd: "/proj", pollInterval: poll)
}

/// A ready recording with prompt.md and two tiny frame files.
private func addReady(_ paths: Paths, id: String, deliveredTo: Int32? = nil, at: Date = .now) throws {
    let dir = paths.recording(id)
    try FileManager.default.createDirectory(at: dir.appending(path: "frames"), withIntermediateDirectories: true)
    let frames = [ManifestFrame(index: 1, time: 0.5, reasons: ["start"], file: "frames/a.jpg", width: 2, height: 2),
                  ManifestFrame(index: 2, time: 3, reasons: ["end"], file: "frames/b.jpg", width: 2, height: 2)]
    for f in frames { try Data([0xFF, 0xD8, 0xFF]).write(to: dir.appending(path: f.file)) }
    let m = Manifest(id: id, duration: 3, mode: .window, transcript: [], frames: frames, strokes: [],
                     timeline: buildTimeline(frames: frames, transcript: [], strokes: [], clears: [], hidden: []))
    try writeJSON(m, to: dir.appending(path: "manifest.json"))
    try Data(renderPrompt(m, recordingDir: dir).utf8).write(to: dir.appending(path: "prompt.md"))
    try writeJSON(RecordingMeta(id: id, title: "Save button", createdAt: at, duration: 3, mode: .window, status: .ready,
                                deliveredToPID: deliveredTo), to: dir.appending(path: "meta.json"))
}

private func call(_ s: MCPServer, _ json: String) async throws -> [String: Any] {
    let out = try #require(await s.handle(line: json))
    return try #require(JSONSerialization.jsonObject(with: Data(out.utf8)) as? [String: Any])
}

private func toolCall(_ name: String, _ args: String = "{}", id: Int = 2) -> String {
    #"{"jsonrpc":"2.0","id":\#(id),"method":"tools/call","params":{"name":"\#(name)","arguments":\#(args)}}"#
}

private func content(_ r: [String: Any]) -> [[String: Any]] {
    ((r["result"] as? [String: Any])?["content"] as? [[String: Any]]) ?? []
}

@Test func initializeEchoesSupportedVersion() async throws {
    let s = server(Paths(root: tempDir()))
    let r = try await call(s, #"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26","capabilities":{},"clientInfo":{"name":"t","version":"1"}}}"#)
    let res = r["result"] as! [String: Any]
    #expect(res["protocolVersion"] as? String == "2025-03-26")
    #expect((res["serverInfo"] as? [String: Any])?["name"] as? String == "video-prompt")
    #expect(res["capabilities"] as? [String: Any] != nil)
}

@Test func initializeFallsBackForUnknownVersion() async throws {
    let r = try await call(server(Paths(root: tempDir())), #"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"1999-01-01"}}"#)
    #expect((r["result"] as? [String: Any])?["protocolVersion"] as? String == "2025-06-18")
}

@Test func toolsListHasFourTools() async throws {
    let r = try await call(server(Paths(root: tempDir())), #"{"jsonrpc":"2.0","id":1,"method":"tools/list"}"#)
    let names = ((r["result"] as? [String: Any])?["tools"] as? [[String: Any]])?.compactMap { $0["name"] as? String }
    #expect(Set(names ?? []) == ["get_latest_recording", "list_recordings", "get_recording", "wait_for_next_recording"])
}

@Test func latestReturnsTextThenImages() async throws {
    let p = Paths(root: tempDir())
    try addReady(p, id: "r1")
    let r = try await call(server(p), toolCall("get_latest_recording"))
    let c = content(r)
    #expect(c.map { $0["type"] as? String } == ["text", "image", "image"])
    #expect((c[0]["text"] as? String)?.hasPrefix("# Screen recording") == true)
    #expect(c[1]["mimeType"] as? String == "image/jpeg")
    #expect(c[1]["data"] as? String == Data([0xFF, 0xD8, 0xFF]).base64EncodedString())
    #expect(try Store(paths: p).meta("r1").fetchedByCwd == "/proj")
}

@Test func latestWhenEmptyGuidesUser() async throws {
    let c = content(try await call(server(Paths(root: tempDir())), toolCall("get_latest_recording")))
    #expect((c.first?["text"] as? String)?.contains("wait_for_next_recording") == true)
}

@Test func getUnknownRecordingIsError() async throws {
    let r = try await call(server(Paths(root: tempDir())), toolCall("get_recording", #"{"id":"nope"}"#))
    #expect((r["result"] as? [String: Any])?["isError"] as? Bool == true)
}

@Test func listShowsRecordings() async throws {
    let p = Paths(root: tempDir())
    try addReady(p, id: "r1")
    let c = content(try await call(server(p), toolCall("list_recordings")))
    #expect((c.first?["text"] as? String)?.contains("r1") == true)
}

@Test func waitReturnsRecordingDeliveredToThisPID() async throws {
    let p = Paths(root: tempDir())
    let s = server(p)
    async let reply = call(s, toolCall("wait_for_next_recording", #"{"timeout_s":5}"#))
    try await Task.sleep(for: .milliseconds(100))
    #expect(Waiters(paths: p).live(isAlive: { _ in true }).map(\.pid) == [myPID])
    try addReady(p, id: "sent", deliveredTo: myPID)
    let c = content(try await reply)
    #expect(c.map { $0["type"] as? String } == ["text", "image", "image"])
    #expect(Waiters(paths: p).live(isAlive: { _ in true }).isEmpty)
}

@Test func waiterIgnoresRecordingDeliveredToAnotherPID() async throws {
    let p = Paths(root: tempDir())
    try addReady(p, id: "other", deliveredTo: 9999)
    try addReady(p, id: "copied", deliveredTo: nil)
    let c = content(try await call(server(p), toolCall("wait_for_next_recording", #"{"timeout_s":0.3}"#)))
    #expect((c.first?["text"] as? String)?.hasPrefix("Still waiting") == true)
}

@Test func waitIgnoresAlreadyFetched() async throws {
    let p = Paths(root: tempDir())
    try addReady(p, id: "old", deliveredTo: myPID)
    try Store(paths: p).update("old") { $0.fetchedByCwd = "/proj" }
    let c = content(try await call(server(p), toolCall("wait_for_next_recording", #"{"timeout_s":0.3}"#)))
    #expect((c.first?["text"] as? String)?.hasPrefix("Still waiting") == true)
}

@Test func waitUnregistersOnTimeout() async throws {
    let p = Paths(root: tempDir())
    _ = try await call(server(p), toolCall("wait_for_next_recording", #"{"timeout_s":0.1}"#))
    #expect(Waiters(paths: p).live(isAlive: { _ in true }).isEmpty)
}

@Test func cancelledWaitUnregisters() async throws {
    let p = Paths(root: tempDir())
    let s = server(p)
    let out = Collector()
    await s.start(line: toolCall("wait_for_next_recording", #"{"timeout_s":30}"#, id: 7), write: { await out.add($0) })
    try await Task.sleep(for: .milliseconds(100))
    #expect(!Waiters(paths: p).live(isAlive: { _ in true }).isEmpty)
    await s.start(line: #"{"jsonrpc":"2.0","method":"notifications/cancelled","params":{"requestId":7}}"#, write: { await out.add($0) })
    try await Task.sleep(for: .milliseconds(200))
    #expect(Waiters(paths: p).live(isAlive: { _ in true }).isEmpty)
}

@Test func notificationGetsNoReply() async throws {
    #expect(await server(Paths(root: tempDir())).handle(line: #"{"jsonrpc":"2.0","method":"notifications/initialized"}"#) == nil)
}

@Test func unknownMethodIsMethodNotFound() async throws {
    let r = try await call(server(Paths(root: tempDir())), #"{"jsonrpc":"2.0","id":3,"method":"nope"}"#)
    #expect((r["error"] as? [String: Any])?["code"] as? Int == -32601)
}

actor Collector {
    var lines: [String] = []
    func add(_ l: String) { lines.append(l) }
}

@Test func drainWaitsForInFlightReplies() async throws {
    let p = Paths(root: tempDir())
    try addReady(p, id: "r1")
    let s = server(p)
    let out = Collector()
    await s.start(line: toolCall("get_latest_recording", id: 5), write: { await out.add($0) })
    await s.drain()
    #expect(await out.lines.count == 1)
}
