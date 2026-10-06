import Foundation
import VPCore

/// MCP over stdio for Claude Code. It only reads and writes the Store's files; it never talks
/// to the app directly.
public actor MCPServer {
    let store: Store
    let waiters: Waiters
    let pid: Int32
    let cwd: String
    let now: @Sendable () -> Date
    let pollInterval: Duration
    /// Image tokens one tool reply may carry. Claude Code cuts replies above
    /// MAX_MCP_OUTPUT_TOKENS (25,000 by default), so stay at 80% of it.
    let imageBudgetTokens: Int
    private var running: [JSONValue: Task<Void, Never>] = [:]

    static let supportedVersions = ["2024-11-05", "2025-03-26", "2025-06-18"]

    public init(store: Store, waiters: Waiters, pid: Int32, cwd: String, now: @escaping @Sendable () -> Date = { .now },
                pollInterval: Duration = .milliseconds(500), imageBudgetTokens: Int? = nil) {
        self.store = store; self.waiters = waiters; self.pid = pid; self.cwd = cwd; self.now = now; self.pollInterval = pollInterval
        let limit = Int(ProcessInfo.processInfo.environment["MAX_MCP_OUTPUT_TOKENS"] ?? "") ?? 25_000
        self.imageBudgetTokens = imageBudgetTokens ?? limit * 8 / 10
    }

    /// Handles one line concurrently with the others, so a blocked wait doesn't hold up pings,
    /// and a `notifications/cancelled` can stop it.
    public func start(line: String, write: @escaping @Sendable (String) async -> Void) {
        if let req = try? JSONDecoder().decode(Request.self, from: Data(line.utf8)),
           req.method == "notifications/cancelled", let target = req.params?["requestId"] {
            running.removeValue(forKey: target)?.cancel()
            return
        }
        let id = (try? JSONDecoder().decode(Request.self, from: Data(line.utf8)))?.id
        let task = Task {
            if let out = await self.handle(line: line) { await write(out) }
            if let id { self.finished(id) }
        }
        if let id { running[id] = task }
    }

    private func finished(_ id: JSONValue) { running[id] = nil }

    /// stdin closed: stop waiting (so no waiter outlives the session), then let replies finish.
    public func shutdown() async {
        for task in running.values { task.cancel() }
        await drain()
    }

    /// Waits for every in-flight request to finish writing its reply.
    public func drain() async {
        for task in Array(running.values) { await task.value }
    }

    /// One JSON-RPC message in, at most one response line out (nil for notifications).
    public func handle(line: String) async -> String? {
        guard let req = try? JSONDecoder().decode(Request.self, from: Data(line.utf8)) else {
            return errorResponse(id: .null, code: -32700, message: "Parse error")
        }
        guard let id = req.id else { return nil }
        switch req.method {
        case "initialize":
            let asked = req.params?["protocolVersion"]?.string ?? ""
            let version = Self.supportedVersions.contains(asked) ? asked : "2025-06-18"
            return response(id: id, result: .object([
                "protocolVersion": .string(version),
                "capabilities": .object(["tools": .object([:])]),
                "serverInfo": .object(["name": .string("video-prompt"), "version": .string("0.1.0")]),
            ]))
        case "ping":
            return response(id: id, result: .object([:]))
        case "tools/list":
            return response(id: id, result: .object(["tools": .array(Tools.definitions)]))
        case "tools/call":
            let name = req.params?["name"]?.string ?? ""
            let args = req.params?["arguments"] ?? .object([:])
            return response(id: id, result: await callTool(name, args))
        default:
            return errorResponse(id: id, code: -32601, message: "Method not found: \(req.method)")
        }
    }
}
