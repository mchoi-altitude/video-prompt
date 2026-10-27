import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
import VPCore
import VPMedia

enum Tools {
    static func tool(_ name: String, _ description: String, _ properties: [String: JSONValue] = [:], required: [String] = []) -> JSONValue {
        .object(["name": .string(name), "description": .string(description),
                 "inputSchema": .object(["type": .string("object"), "properties": .object(properties),
                                         "required": .array(required.map { .string($0) })])])
    }

    static let definitions: [JSONValue] = [
        tool("get_latest_recording",
             "Get the user's most recent Video Prompt screen recording: a timeline of what they said, drew and clicked (with timestamps) plus an overview image of the whole video. Use get_frames to look closer at any moment. Use when the user says they recorded something, or says \"look at my recording\"."),
        tool("list_recordings", "List the user's recent Video Prompt recordings with id, title, time and length.",
             ["limit": .object(["type": .string("integer"), "description": .string("How many to list (default 10)")])]),
        tool("get_recording", "Get one Video Prompt recording by id (from list_recordings).",
             ["id": .object(["type": .string("string")])], required: ["id"]),
        tool("get_frames",
             "Frames of a recording's video between two timestamps (seconds), to look closer at what the timeline points to. Default 2 fps, at most 10; up to 20 frames per call. id defaults to the latest recording.",
             ["id": .object(["type": .string("string")]), "from": .object(["type": .string("number")]),
              "to": .object(["type": .string("number")]), "fps": .object(["type": .string("number")])], required: ["from", "to"]),
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

    /// Why a recording can't be fetched yet. Only `ready` recordings are: the user saves or sends
    /// from the review panel, where they can still fix the transcript or discard it.
    static func notReady(_ m: RecordingMeta) -> String {
        let name = "The recording “\(m.title)” (`\(m.id)`)"
        switch m.status {
        case .processing: return "\(name) is still being processed. Try again in a few seconds."
        case .reviewing: return "\(name) is still open in Video Prompt's review panel. Ask the user to press Save or Send there, then try again."
        case .processingFailed: return "\(name) failed to process. The user can retry it from Recordings in the Video Prompt menu."
        case .ready: return "\(name) is ready."
        }
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
            // The newest recording, not the newest ready one: an older one would be the wrong recording.
            guard let newest = store.list().first else {
                return Tools.text("No recordings yet. Ask the user to record one (menu-bar icon or ⌃⌥⌘R), or call wait_for_next_recording.")
            }
            guard newest.status == .ready else {
                var note = Tools.notReady(newest)
                if let older = store.latestReady() {
                    note += " The newest saved one is “\(older.title)” (`\(older.id)`); fetch it with get_recording only if the user wants that one."
                }
                return Tools.text(note)
            }
            return recording(newest.id)
        case "get_recording":
            guard let id = args["id"]?.string, Tools.isValidID(id), let meta = try? store.meta(id) else {
                return Tools.text("No recording with that id. Call list_recordings to see what exists.", isError: true)
            }
            guard meta.status == .ready else { return Tools.text(Tools.notReady(meta), isError: true) }
            return recording(id)
        case "list_recordings":
            let limit = Tools.clampedLimit(args["limit"]?.number ?? 10)
            let rows = store.list().prefix(limit).map { m in
                "\(m.id) · \(m.title) · \(m.createdAt.formatted(date: .abbreviated, time: .shortened)) · \(fmtLen(m.duration)) · \(m.status.rawValue)"
            }
            return Tools.text(rows.isEmpty ? "No recordings yet." : rows.joined(separator: "\n"))
        case "get_frames":
            let id = args["id"]?.string ?? store.list().first?.id
            guard let id, Tools.isValidID(id), let meta = try? store.meta(id) else {
                return Tools.text("No recording with that id. Call list_recordings to see what exists.", isError: true)
            }
            guard meta.status == .ready else { return Tools.text(Tools.notReady(meta), isError: true) }
            guard let m = try? store.manifest(id) else { return Tools.text("Recording \(id) could not be read.", isError: true) }
            return await frames(id: id, manifest: m, from: Tools.clampedSeconds(args["from"]?.number ?? 0),
                                to: Tools.clampedSeconds(args["to"]?.number ?? 0), fps: args["fps"]?.number ?? 2)
        case "wait_for_next_recording":
            return await waitForNext(timeout: Tools.clampedSeconds(args["timeout_s"]?.number ?? 300))
        default:
            return Tools.text("Unknown tool \(name)", isError: true)
        }
    }

    /// timeline.md as text, then the overview contact sheet inline. Marks it fetched.
    func recording(_ id: String) -> JSONValue {
        let dir = store.paths.recording(id)
        guard let m = try? store.manifest(id),
              let timeline = try? String(contentsOf: dir.appending(path: "timeline.md"), encoding: .utf8) else {
            return Tools.text("Recording \(id) could not be read.", isError: true)
        }
        var content: [JSONValue] = [.object(["type": .string("text"), "text": .string(
            timeline + "\nRecording id for get_frames: `\(id)`. The overview image follows.\n")])]
        if let data = try? Data(contentsOf: dir.appending(path: m.overview)) {
            content.append(.object(["type": .string("image"), "data": .string(data.base64EncodedString()), "mimeType": .string("image/jpeg")]))
        }
        try? store.update(id) { $0.fetchedByCwd = cwd }
        return .object(["content": .array(content), "isError": .bool(false)])
    }

    /// Labelled frames for a time range: at most 20 (fps lowered to fit), within the image budget
    /// (shrunk, then thinned to an even spread keeping the first and last).
    func frames(id: String, manifest m: Manifest, from: Double, to: Double, fps: Double) async -> JSONValue {
        let video = store.paths.recording(id).appending(path: m.video.file)
        // Clamp to the recording, so "everything" (0…9999) spreads 20 frames across it.
        let lo = min(max(0, min(from, to)), m.duration), hi = min(max(0, max(from, to)), m.duration)
        let rate = min(max(fps, 0.01), Double(VideoFPS))
        guard let all = try? await extractFrames(video: video, from: lo, to: hi, fps: rate, maxLongEdge: 1568, maxFrames: 20),
              !all.isEmpty else {
            return Tools.text("Couldn't read frames from \(video.path).", isError: true)
        }
        let plan = Tools.attachmentPlan(sizes: all.map { ($0.width, $0.height) }, budgetTokens: imageBudgetTokens)
        let keep = Set(plan.inline)
        let spacing = all.count > 1 ? (all[all.count - 1].t - all[0].t) / Double(all.count - 1) : 0
        var header = String(format: "Frames of recording %@ from %.1f s to %.1f s, one every %.2f s (%d of %d shown).", id,
                            lo, hi, spacing, keep.count, all.count)
        if keep.count < all.count { header += " For the rest, ask for a narrower range or a lower fps." }
        var content: [JSONValue] = [.object(["type": .string("text"), "text": .string(header)])]
        for (i, f) in all.enumerated() where keep.contains(i) {
            var data = f.jpeg
            if plan.scale < 1, let small = Tools.shrinkJPEG(data, maxPixel: Int((Double(max(f.width, f.height)) * plan.scale).rounded())) { data = small }
            content.append(.object(["type": .string("text"), "text": .string(String(format: "%.1f s", f.t))]))
            content.append(.object(["type": .string("image"), "data": .string(data.base64EncodedString()), "mimeType": .string("image/jpeg")]))
        }
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
