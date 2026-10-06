import Foundation
import Testing
import VPCore
@testable import VPMCP
import VPTestSupport

private let myPID: Int32 = 4242

private func server(_ paths: Paths, poll: Duration = .milliseconds(10)) -> MCPServer {
    MCPServer(store: Store(paths: paths), waiters: Waiters(paths: paths), pid: myPID, cwd: "/proj", pollInterval: poll)
}

private func addReady(_ p: Paths, id: String, deliveredTo: Int32? = nil, at: Date = .now) throws {
    try makeProcessedRecording(p, id: id, status: .ready, deliveredTo: deliveredTo, createdAt: at)
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

@Test func toolsListHasFiveTools() async throws {
    let r = try await call(server(Paths(root: tempDir())), #"{"jsonrpc":"2.0","id":1,"method":"tools/list"}"#)
    let names = ((r["result"] as? [String: Any])?["tools"] as? [[String: Any]])?.compactMap { $0["name"] as? String }
    #expect(Set(names ?? []) == ["get_latest_recording", "list_recordings", "get_recording", "get_frames", "wait_for_next_recording"])
}

@Test func latestReturnsTimelineAndOverview() async throws {
    let p = Paths(root: tempDir())
    try addReady(p, id: "r1")
    let r = try await call(server(p), toolCall("get_latest_recording"))
    let c = content(r)
    #expect(c.map { $0["type"] as? String } == ["text", "image"])
    #expect((c[0]["text"] as? String)?.hasPrefix("# Screen recording") == true)
    #expect((c[0]["text"] as? String)?.contains("get_frames") == true)
    #expect(c[1]["mimeType"] as? String == "image/jpeg")
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
    #expect(c.map { $0["type"] as? String } == ["text", "image"])
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

@Test func shutdownCancelsWaitsAndRemovesWaiter() async throws {
    let p = Paths(root: tempDir())
    let s = server(p)
    let out = Collector()
    await s.start(line: toolCall("wait_for_next_recording", #"{"timeout_s":30}"#, id: 9), write: { await out.add($0) })
    try await Task.sleep(for: .milliseconds(100))
    let start = ContinuousClock.now
    await s.shutdown()
    #expect(ContinuousClock.now - start < .seconds(2))
    #expect(Waiters(paths: p).live(isAlive: { _ in true }).isEmpty)
}

@Test func badLimitDoesNotCrash() async throws {
    let p = Paths(root: tempDir())
    try addReady(p, id: "r1")
    for limit in ["-1", "0", "1e300"] {
        let c = content(try await call(server(p), toolCall("list_recordings", #"{"limit":\#(limit)}"#)))
        #expect((c.first?["text"] as? String)?.contains("r1") == true)
    }
}

@Test func timeoutIsClamped() {
    #expect(Tools.clampedSeconds(1e300) == 3600)
    #expect(Tools.clampedSeconds(-5) == 0)
    #expect(Tools.clampedSeconds(.nan) == 300)
    #expect(Tools.clampedLimit(-1) == 1)
    #expect(Tools.clampedLimit(1e300) == 100)
}

@Test func getRecordingRejectsPathTraversal() async throws {
    let p = Paths(root: tempDir())
    try addReady(p, id: "r1")
    // A ready-looking recording outside recordings/.
    try FileManager.default.copyItem(at: p.recording("r1"), to: p.root.appending(path: "evil"))
    let r = try await call(server(p), toolCall("get_recording", #"{"id":"../evil"}"#))
    #expect((r["result"] as? [String: Any])?["isError"] as? Bool == true)
    #expect(try readJSON(RecordingMeta.self, from: p.root.appending(path: "evil/meta.json")).fetchedByCwd == nil)
}


@Test func smallRecordingsAttachEverythingFullSize() {
    let p = Tools.attachmentPlan(sizes: Array(repeating: (1568, 980), count: 6), budgetTokens: 20000)
    #expect(p.scale == 1)
    #expect(p.inline == [0, 1, 2, 3, 4, 5])
}

@Test func largeRecordingsShrinkThenSpreadAttachments() {
    let p = Tools.attachmentPlan(sizes: Array(repeating: (1568, 980), count: 24), budgetTokens: 20000)
    #expect(abs(p.scale - 1024.0 / 1568) < 0.001)     // shrunk, but never below a 1024 px long edge
    #expect(p.inline.count == 22)
    #expect(p.inline.first == 0 && p.inline.last == 23)  // first and last frame always attached
}


private func addWithVideo(_ p: Paths, id: String, seconds: Double = 4) async throws {
    let v = tempDir().appending(path: "v.mov")
    try await makeColorVideo(url: v, size: (320, 200), blocks: [ColorBlock(seconds / 2, (240, 240, 240)), ColorBlock(seconds / 2, (20, 20, 20))])
    try makeProcessedRecording(p, id: id, status: .ready, video: v)
}

private func images(_ c: [[String: Any]]) -> Int { c.filter { $0["type"] as? String == "image" }.count }

@Test func getFramesReturnsLabelledImages() async throws {
    let p = Paths(root: tempDir())
    try await addWithVideo(p, id: "r1")
    let c = content(try await call(server(p), toolCall("get_frames", #"{"id":"r1","from":1,"to":2,"fps":2}"#)))
    #expect(images(c) == 3)
    let texts = c.compactMap { $0["text"] as? String }.joined(separator: "\n")
    #expect(texts.contains("1.0 s") && texts.contains("1.5 s") && texts.contains("2.0 s"))
}

@Test func getFramesDefaultsToLatest() async throws {
    let p = Paths(root: tempDir())
    try await addWithVideo(p, id: "r1")
    let c = content(try await call(server(p), toolCall("get_frames", #"{"from":0,"to":0}"#)))
    #expect(images(c) == 1)
}

@Test func getFramesCapsAtTwenty() async throws {
    let p = Paths(root: tempDir())
    try await addWithVideo(p, id: "r1")
    let c = content(try await call(server(p), toolCall("get_frames", #"{"from":0,"to":3.9,"fps":10}"#)))
    #expect(images(c) <= 20 && images(c) >= 10)
}

@Test func getFramesRespectsBudget() async throws {
    let p = Paths(root: tempDir())
    try await addWithVideo(p, id: "r1")
    let s = MCPServer(store: Store(paths: p), waiters: Waiters(paths: p), pid: 4242, cwd: "/proj", imageBudgetTokens: 0)
    let c = content(try await call(s, toolCall("get_frames", #"{"from":0,"to":3,"fps":2}"#)))
    #expect(images(c) == 2)   // first and last only; the rest are named so Claude can ask again
    #expect(c.compactMap { $0["text"] as? String }.joined().contains("narrower range"))
}

@Test func getFramesUnknownIdIsError() async throws {
    let r = try await call(server(Paths(root: tempDir())), toolCall("get_frames", #"{"id":"nope","from":0,"to":1}"#))
    #expect((r["result"] as? [String: Any])?["isError"] as? Bool == true)
}

@Test func getFramesWholeRangeSpreadsAcrossVideo() async throws {
    let p = Paths(root: tempDir())
    try await addWithVideo(p, id: "r1", seconds: 12)
    let c = content(try await call(server(p), toolCall("get_frames", #"{"from":0,"to":9999}"#)))
    #expect(images(c) >= 10)
    let header = c.first?["text"] as? String ?? ""
    #expect(header.contains("to 12.0 s") || header.contains("to 11.9 s"))
}

@Test func latestDescriptionMentionsOverviewNotKeyframes() async throws {
    let r = try await call(server(Paths(root: tempDir())), #"{"jsonrpc":"2.0","id":1,"method":"tools/list"}"#)
    let tools = (r["result"] as? [String: Any])?["tools"] as? [[String: Any]] ?? []
    let d = tools.first { $0["name"] as? String == "get_latest_recording" }?["description"] as? String ?? ""
    #expect(!d.contains("keyframe") && d.contains("get_frames"))
}
