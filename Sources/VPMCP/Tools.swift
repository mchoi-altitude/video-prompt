import Foundation
import VPCore

enum Tools {
    static func tool(_ name: String, _ description: String, _ properties: [String: JSONValue] = [:], required: [String] = []) -> JSONValue {
        .object(["name": .string(name), "description": .string(description),
                 "inputSchema": .object(["type": .string("object"), "properties": .object(properties),
                                         "required": .array(required.map { .string($0) })])])
    }

    static let definitions: [JSONValue] = [
        tool("get_latest_recording",
             "Get the user's most recent Video Prompt screen recording (narration, timeline and keyframe images). Use when the user says they recorded something, or says \"look at my recording\"."),
        tool("list_recordings", "List the user's recent Video Prompt recordings with id, title, time and length.",
             ["limit": .object(["type": .string("integer"), "description": .string("How many to list (default 10)")])]),
        tool("get_recording", "Get one Video Prompt recording by id (from list_recordings).",
             ["id": .object(["type": .string("string")])], required: ["id"]),
        tool("wait_for_next_recording",
             "Ask the user to show you something, then call this: it waits until they record and press Send in Video Prompt, and returns that recording.",
             ["timeout_s": .object(["type": .string("number"), "description": .string("Seconds to wait (default 300)")])]),
    ]

    static func text(_ s: String, isError: Bool = false) -> JSONValue {
        .object(["content": .array([.object(["type": .string("text"), "text": .string(s)])]), "isError": .bool(isError)])
    }
}

extension MCPServer {
    func callTool(_ name: String, _ args: JSONValue) async -> JSONValue {
        switch name {
        case "get_latest_recording":
            guard let meta = store.latestReady() else {
                return Tools.text("No recordings yet. Ask the user to record one (menu-bar icon or ⌃⌥⌘R), or call wait_for_next_recording.")
            }
            return recording(meta.id)
        case "get_recording":
            guard let id = args["id"]?.string, (try? store.meta(id))?.status == .ready else {
                return Tools.text("No ready recording with that id. Call list_recordings to see what exists.", isError: true)
            }
            return recording(id)
        case "list_recordings":
            let limit = Int(args["limit"]?.number ?? 10)
            let rows = store.list().prefix(limit).map { m in
                "\(m.id) · \(m.title) · \(m.createdAt.formatted(date: .abbreviated, time: .shortened)) · \(fmtLen(m.duration)) · \(m.status.rawValue)"
            }
            return Tools.text(rows.isEmpty ? "No recordings yet." : rows.joined(separator: "\n"))
        case "wait_for_next_recording":
            return await waitForNext(timeout: args["timeout_s"]?.number ?? 300)
        default:
            return Tools.text("Unknown tool \(name)", isError: true)
        }
    }

    /// prompt.md as text, then every keyframe as an inline image, in order. Marks it fetched.
    func recording(_ id: String) -> JSONValue {
        let dir = store.paths.recording(id)
        guard let prompt = try? String(contentsOf: dir.appending(path: "prompt.md"), encoding: .utf8),
              let m = try? store.manifest(id) else {
            return Tools.text("Recording \(id) could not be read.", isError: true)
        }
        var content: [JSONValue] = [.object(["type": .string("text"), "text": .string(prompt)])]
        for f in m.frames {
            guard let data = try? Data(contentsOf: dir.appending(path: f.file)) else { continue }
            content.append(.object(["type": .string("image"), "data": .string(data.base64EncodedString()), "mimeType": .string("image/jpeg")]))
        }
        try? store.update(id) { $0.fetchedByCwd = cwd }
        return .object(["content": .array(content), "isError": .bool(false)])
    }

    /// Registers this session as waiting, then returns the first ready recording the app
    /// delivered to this pid that hasn't been fetched yet.
    func waitForNext(timeout: Double) async -> JSONValue {
        try? waiters.register(Waiter(pid: pid, cwd: cwd, startedAt: now()))
        defer { waiters.unregister(pid: pid) }
        let deadline = ContinuousClock.now + .milliseconds(Int(timeout * 1000))
        while ContinuousClock.now < deadline, !Task.isCancelled {
            if let m = store.list().first(where: { $0.status == .ready && $0.deliveredToPID == pid && $0.fetchedByCwd == nil }) {
                return recording(m.id)
            }
            try? await Task.sleep(for: pollInterval)
        }
        return Tools.text("Still waiting — the user hasn't sent a recording yet. Call wait_for_next_recording again if they still intend to.")
    }
}

private func fmtLen(_ s: Double) -> String { String(format: "%d:%02d", Int(s) / 60, Int(s) % 60) }
