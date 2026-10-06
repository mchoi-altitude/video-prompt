import AVFoundation
import Foundation
import VPCore
import VPMedia

public enum ProcessorError: Error, Equatable { case noSegments, missing(String) }

/// Turns `recordings/<id>/raw/` into `video.mp4`, `overview.jpg`, `manifest.json`, `timeline.md` and a `reviewing`
/// `meta.json`; `finalize` makes it `ready` once the user saves or sends it.
/// On failure the raw folder is kept and the recording is marked `processingFailed`.
public struct Processor: Sendable {
    let store: Store
    let paths: Paths
    let transcriber: Transcriber?
    let calendar: Calendar
    /// Experiments only: keep `raw/` so the recording can be reprocessed differently.
    let keepRaw: Bool
    /// The `vp-frames` command named in timeline.md (the paste path has no MCP tools).
    let vpFramesPath: String
    /// The video is scaled down (not cropped) to at most this height.
    let maxVideoHeight: Int

    public init(store: Store, paths: Paths, transcriber: Transcriber?, calendar: Calendar = .current, keepRaw: Bool = false,
                vpFramesPath: String = Processor.defaultVPFramesPath, maxVideoHeight: Int = VideoMaxHeight) {
        self.maxVideoHeight = maxVideoHeight
        self.store = store; self.paths = paths; self.transcriber = transcriber; self.calendar = calendar; self.keepRaw = keepRaw
        self.vpFramesPath = vpFramesPath
    }

    /// `vp-frames` next to the running binary (inside the app bundle, or in .build for dev).
    public static var defaultVPFramesPath: String {
        let here = Bundle.main.executableURL?.deletingLastPathComponent() ?? URL(fileURLWithPath: "/Applications/Video Prompt.app/Contents/MacOS")
        return here.appending(path: "vp-frames").path
    }

    public func process(id: String, now: Date = .now) async throws -> RecordingMeta {
        let dir = paths.recording(id), raw = paths.raw(id)
        let session = try readJSON(RawSession.self, from: raw.appending(path: "session.json"))
        var meta = RecordingMeta(id: id, title: "Processing…", createdAt: session.createdAt, duration: 0,
                                 mode: session.mode, status: .processing)
        try writeJSON(meta, to: dir.appending(path: "meta.json"))
        do {
            meta = try await run(id: id, dir: dir, raw: raw, session: session, meta: meta)
            try writeJSON(meta, to: dir.appending(path: "meta.json"))
            return meta
        } catch {
            meta.status = .processingFailed
            meta.error = "\(error)"
            try? writeJSON(meta, to: dir.appending(path: "meta.json"))
            throw error
        }
    }

    private func run(id: String, dir: URL, raw: URL, session: RawSession, meta: RecordingMeta) async throws -> RecordingMeta {
        let fm = FileManager.default
        let segURLs = try fm.contentsOfDirectory(at: raw, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix("seg_") }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        guard !segURLs.isEmpty else { throw ProcessorError.noSegments }
        let (asset, byPosition) = try await joinSegments(segURLs)
        // Events name segments by the number in `seg_NNN.mov`, which can skip (an empty segment
        // the app dropped), so key durations by file number, not position.
        var durations: [Int: Double] = [:]
        for (i, url) in segURLs.enumerated() {
            guard let n = segmentNumber(url) else { continue }
            durations[n] = byPosition[i + 1]
        }
        let offsets = segmentOffsets(durations: durations)
        let pauses = offsets.values.filter { $0 > 0 }.sorted().map(round2)
        guard let vt = try await asset.loadTracks(withMediaType: .video).first else { throw MediaError.noVideoTrack(id) }
        let natural = try await vt.load(.naturalSize)
        let sx = Double(natural.width) / session.display.w, sy = Double(natural.height) / session.display.h

        // Events → recording time.
        let events = try readEvents(raw.appending(path: "events.jsonl"))
        var windows: [WindowSample] = [], clicksRaw: [(t: Double, p: Point)] = [], clears: [Double] = []
        var rawStrokes: [(t0: Double, t1: Double, points: [Point], tool: StrokeTool)] = []
        for e in events {
            switch e {
            case let .window(seg, t, frame, visible): if let o = offsets[seg] { windows.append(WindowSample(t: o + t, frame: frame, visible: visible)) }
            case .cursor: break  // the cursor is in the video itself
            case let .click(seg, t, p): if let o = offsets[seg] { clicksRaw.append((o + t, p)) }
            case let .clear(seg, t): if let o = offsets[seg] { clears.append(round2(o + t)) }
            case let .stroke(seg, t0, t1, pts, tool): if let o = offsets[seg] { rawStrokes.append((o + t0, o + t1, pts, tool)) }
            case let .undo(seg, t):
                // Drop the latest stroke finished before the undo: it never meant anything.
                if let o = offsets[seg], let i = rawStrokes.lastIndex(where: { $0.t1 <= o + t }) { rawStrokes.remove(at: i) }
            }
        }
        let timeline = CropTimeline(mode: session.mode, display: session.display, area: session.area, windowSamples: windows)
        let display = session.display
        // Only the on-screen part of a window is in the capture, so crop and map with that part.
        let crop: @Sendable (Double) -> Rect? = { t in timeline.crop(at: t).flatMap { clip($0, to: display) } }
        // Canvas: the largest crop the recording ever had, in video pixels.
        let crops = (windows.isEmpty ? [0.0] : windows.map(\.t)).compactMap(crop)
        let fullW = (crops.map(\.w).max() ?? display.w) * sx, fullH = (crops.map(\.h).max() ?? display.h) * sy
        // Scale (never crop) so the video is at most maxVideoHeight tall.
        let outScale = min(1, Double(maxVideoHeight) / fullH)
        let canvas = (Int((fullW * outScale).rounded()), Int((fullH * outScale).rounded()))
        /// A screen point → video pixels at time t (content sits top-left on the canvas).
        func videoPixels(_ p: Point, at t: Double) -> [Int]? {
            guard let c = crop(t) else { return nil }
            return toFramePixels(p, crop: c, frameW: Int((c.w * sx * outScale).rounded()), frameH: Int((c.h * sy * outScale).rounded()))
        }

        // Narration.
        var transcript: [Sentence] = []
        let wav = raw.appending(path: "audio.wav")
        let transcription: TranscriptionState
        if !(try await exportMonoWAV16k(asset, to: wav)) {
            transcription = .noAudio
        } else if let transcriber {
            transcript = sentences(from: try await transcriber.words(wav: wav))
            transcription = transcript.isEmpty ? .noSpeech : .ok
        } else {
            transcription = .unavailable
        }

        let clicks = clicksRaw.compactMap { c in videoPixels(c.p, at: c.t).map { ManifestClick(t: round2(c.t), x: $0[0], y: $0[1]) } }
        var strokes: [ManifestStroke] = []
        for s in rawStrokes {
            let px = s.points.compactMap { videoPixels($0, at: s.t1) }
            guard px.count >= 2 else { continue }
            let (bbox, text) = describeStroke(px, tool: s.tool)
            strokes.append(ManifestStroke(start: round2(s.t0), end: round2(s.t1), tool: s.tool, bbox: bbox, description: text))
        }
        let hidden = windows.filter { !$0.visible }.map { round2($0.t) }

        // The window video, then its overview.
        let rendered = try await renderWindowVideo(asset: asset, display: display, canvas: canvas, crop: crop,
                                                   clicks: clicks.map { ClickMark(t: $0.t, x: Double($0.x), y: Double($0.y)) },
                                                   outputScale: outScale, to: dir.appending(path: "video.mp4"))
        let overview = try await makeOverview(video: dir.appending(path: "video.mp4"), to: dir.appending(path: "overview.jpg"))

        let manifest = Manifest(id: id, duration: round2(rendered.duration), mode: session.mode, transcript: transcript,
                                transcription: transcription,
                                video: VideoInfo(file: "video.mp4", width: rendered.width, height: rendered.height, fps: VideoFPS,
                                                 hasAudio: rendered.hasAudio),
                                overview: "overview.jpg", overviewSecondsPerTile: overview.secondsPerTile, strokes: strokes, clicks: clicks,
                                timeline: buildTimeline(transcript: transcript, strokes: strokes, clicks: clicks, clears: clears,
                                                        hidden: hidden, pauses: pauses),
                                note: session.note)
        try writeJSON(manifest, to: dir.appending(path: "manifest.json"))
        try writeAtomically(Data(renderTimeline(manifest, recordingDir: dir, vpFrames: vpFramesPath).utf8), to: dir.appending(path: "timeline.md"))
        if !keepRaw { try fm.removeItem(at: raw) }

        var out = meta
        out.status = .reviewing
        out.duration = manifest.duration
        out.title = title(for: transcript, createdAt: meta.createdAt, calendar: calendar)
        out.sizeBytes = folderSize(dir)
        return out
    }

    private func readEvents(_ url: URL) throws -> [RawEvent] {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return try text.split(whereSeparator: \.isNewline).map { try JSON.decoder.decode(RawEvent.self, from: Data($0.utf8)) }
    }
}

/// `seg_003.mov` → 3.
func segmentNumber(_ url: URL) -> Int? {
    let name = url.deletingPathExtension().lastPathComponent
    guard name.hasPrefix("seg_") else { return nil }
    return Int(name.dropFirst(4))
}

/// The part of `r` inside `bounds`; nil when none of it is.
func clip(_ r: Rect, to bounds: Rect) -> Rect? {
    let x0 = max(r.x, bounds.x), y0 = max(r.y, bounds.y)
    let x1 = min(r.x + r.w, bounds.x + bounds.w), y1 = min(r.y + r.h, bounds.y + bounds.h)
    guard x1 > x0, y1 > y0 else { return nil }
    return Rect(x: x0, y: y0, w: x1 - x0, h: y1 - y0)
}

func round2(_ x: Double) -> Double { (x * 100).rounded() / 100 }

func folderSize(_ dir: URL) -> Int64 {
    let e = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: [.fileSizeKey])
    var total: Int64 = 0
    while let u = e?.nextObject() as? URL { total += Int64((try? u.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
    return total
}
