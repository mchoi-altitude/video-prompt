import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
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

    /// Tool arguments come from the model and may be steered by screen content: never trust them.
    static func clampedSeconds(_ s: Double) -> Double { s.isNaN ? 300 : min(max(s, 0), 3600) }
    static func clampedLimit(_ n: Double) -> Int { n.isNaN ? 10 : Int(min(max(n, 1), 100)) }

    /// A recording id is a plain folder name inside recordings/ (no `/`, no `..`).
    static func isValidID(_ id: String) -> Bool {
        !id.isEmpty && !id.hasPrefix(".") && !id.contains("/") && !id.contains("\\")
    }

    /// Claude's image cost is about width × height / 750 tokens.
    static func imageTokens(_ w: Int, _ h: Int, scale: Double) -> Double { Double(w) * scale * Double(h) * scale / 750 }

    /// Which frames to attach, and at what scale, to stay within `budgetTokens`: first shrink
    /// (never below `minLongEdge`, so UI text stays legible), then attach an evenly spread
    /// subset that always includes the first and last frame.
    static func attachmentPlan(sizes: [(Int, Int)], budgetTokens: Int, minLongEdge: Int = 1024) -> (scale: Double, inline: [Int]) {
        let n = sizes.count
        guard n > 0 else { return (1, []) }
        let budget = Double(max(budgetTokens, 0))
        let total = sizes.reduce(0.0) { $0 + imageTokens($1.0, $1.1, scale: 1) }
        if total <= budget { return (1, Array(0..<n)) }
        let longest = Double(sizes.map { max($0.0, $0.1) }.max()!)
        let floorScale = min(1, Double(minLongEdge) / longest)
        let scale = max(sqrt(budget / total), floorScale)
        let each = total * scale * scale / Double(n)
        let k = min(n, max(min(n, 2), Int(budget / each)))
        if k == n { return (scale, Array(0..<n)) }
        let picks = (0..<k).map { k == 1 ? 0 : Int((Double($0) * Double(n - 1) / Double(k - 1)).rounded()) }
        return (scale, Array(Set(picks)).sorted())
    }

    /// JPEG re-encoded so its long edge is `maxPixel`.
    static func shrinkJPEG(_ data: Data, maxPixel: Int) -> Data? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil),
              let img = CGImageSourceCreateThumbnailAtIndex(src, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: maxPixel,
              ] as CFDictionary) else { return nil }
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(out, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, img, [kCGImageDestinationLossyCompressionQuality: 0.8] as CFDictionary)
        return CGImageDestinationFinalize(dest) ? out as Data : nil
    }

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
            guard let id = args["id"]?.string, Tools.isValidID(id), (try? store.meta(id))?.status == .ready else {
                return Tools.text("No ready recording with that id. Call list_recordings to see what exists.", isError: true)
            }
            return recording(id)
        case "list_recordings":
            let limit = Tools.clampedLimit(args["limit"]?.number ?? 10)
            let rows = store.list().prefix(limit).map { m in
                "\(m.id) · \(m.title) · \(m.createdAt.formatted(date: .abbreviated, time: .shortened)) · \(fmtLen(m.duration)) · \(m.status.rawValue)"
            }
            return Tools.text(rows.isEmpty ? "No recordings yet." : rows.joined(separator: "\n"))
        case "wait_for_next_recording":
            return await waitForNext(timeout: Tools.clampedSeconds(args["timeout_s"]?.number ?? 300))
        default:
            return Tools.text("Unknown tool \(name)", isError: true)
        }
    }

    /// The prompt as text, then every keyframe as an inline image, in order. Marks it fetched.
    func recording(_ id: String) -> JSONValue {
        let dir = store.paths.recording(id)
        guard let m = try? store.manifest(id) else {
            return Tools.text("Recording \(id) could not be read.", isError: true)
        }
        let plan = Tools.attachmentPlan(sizes: m.frames.map { ($0.width, $0.height) }, budgetTokens: imageBudgetTokens)
        let attached = Set(plan.inline)
        var prompt = renderPrompt(m, recordingDir: dir, framesAttached: true)
        let skipped = m.frames.enumerated().filter { !attached.contains($0.offset) }.map(\.element)
        if !skipped.isEmpty {
            prompt += "\n## Frames not attached\n\nThese didn't fit in one reply. Open them with your Read tool if you need them:\n\n"
                + skipped.map { "- Frame \($0.index): `\(dir.appending(path: $0.file).path)`" }.joined(separator: "\n") + "\n"
        }
        var content: [JSONValue] = [.object(["type": .string("text"), "text": .string(prompt)])]
        for (i, f) in m.frames.enumerated() where attached.contains(i) {
            guard var data = try? Data(contentsOf: dir.appending(path: f.file)) else { continue }
            if plan.scale < 1, let small = Tools.shrinkJPEG(data, maxPixel: Int((Double(max(f.width, f.height)) * plan.scale).rounded())) {
                data = small
            }
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
