import AVFoundation
import Foundation
import VPCore
import VPMedia

public enum ProcessorError: Error, Equatable { case noSegments, missing(String) }

/// Turns `recordings/<id>/raw/` into frames, `manifest.json`, `prompt.md` and a `reviewing`
/// `meta.json`; `finalize` makes it `ready` once the user saves or sends it.
/// On failure the raw folder is kept and the recording is marked `processingFailed`.
public struct Processor: Sendable {
    let store: Store
    let paths: Paths
    let transcriber: Transcriber?
    let calendar: Calendar
    /// Experiments only: keep `raw/` so the recording can be reprocessed differently.
    let keepRaw: Bool

    public init(store: Store, paths: Paths, transcriber: Transcriber?, calendar: Calendar = .current, keepRaw: Bool = false) {
        self.store = store; self.paths = paths; self.transcriber = transcriber; self.calendar = calendar; self.keepRaw = keepRaw
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
        let duration = try await asset.load(.duration).seconds
        guard let vt = try await asset.loadTracks(withMediaType: .video).first else { throw MediaError.noVideoTrack(id) }
        let natural = try await vt.load(.naturalSize)
        let sx = Double(natural.width) / session.display.w, sy = Double(natural.height) / session.display.h

        // Events → recording time.
        let events = try readEvents(raw.appending(path: "events.jsonl"))
        var windows: [WindowSample] = [], cursorPts: [(t: Double, p: Point)] = [], clears: [Double] = []
        var rawStrokes: [(t0: Double, t1: Double, points: [Point], tool: StrokeTool)] = []
        for e in events {
            switch e {
            case let .window(seg, t, frame, visible): if let o = offsets[seg] { windows.append(WindowSample(t: o + t, frame: frame, visible: visible)) }
            case let .cursor(seg, t, p): if let o = offsets[seg] { cursorPts.append((o + t, p)) }
            case let .clear(seg, t): if let o = offsets[seg] { clears.append(round2(o + t)) }
            case let .stroke(seg, t0, t1, pts, tool): if let o = offsets[seg] { rawStrokes.append((o + t0, o + t1, pts, tool)) }
            case let .undo(seg, t):
                // Drop the latest stroke finished before the undo: it never meant anything.
                if let o = offsets[seg], let i = rawStrokes.lastIndex(where: { $0.t1 <= o + t }) { rawStrokes.remove(at: i) }
            }
        }
        let timeline = CropTimeline(mode: session.mode, display: session.display, area: session.area, windowSamples: windows)
        // Only the on-screen part of a window is in the video, so crop and map with that part.
        func crop(at t: Double) -> Rect? { timeline.crop(at: t).flatMap { clip($0, to: session.display) } }
        func dims(_ c: Rect) -> (w: Int, h: Int) { frameSize(cropW: c.w * sx, cropH: c.h * sy) }

        // Narration.
        var transcript: [Sentence] = []
        let wav = raw.appending(path: "audio.wav")
        if let transcriber, try await exportMonoWAV16k(asset, to: wav) {
            transcript = sentences(from: try await transcriber.words(wav: wav))
        }

        // Keyframes.
        let scenes = try await sceneChanges(in: asset)
        let picks = chooseFrameTimes(duration: duration, scenes: scenes, strokeEnds: rawStrokes.map(\.t1), sentences: transcript)
        let framesDir = dir.appending(path: "frames")
        try fm.createDirectory(at: framesDir, withIntermediateDirectories: true)
        var frames: [ManifestFrame] = [], hidden: [Double] = []
        for pick in picks {
            guard let crop = crop(at: pick.time) else { hidden.append(pick.time); continue }
            let index = frames.count + 1
            let t = pick.time
            let name = String(format: "frame_%02d_%02dm%04.1fs.jpg", index, Int(t / 60), t.truncatingRemainder(dividingBy: 60))
            let img = try await grabFrame(asset, at: t, crop: crop, display: session.display)
            let size = try writeJPEG(img, maxLongEdge: 1568, to: framesDir.appending(path: name))
            let cur = cursor(at: t, in: cursorPts.map { CursorSample(t: $0.t, p: [Int($0.p.x.rounded()), Int($0.p.y.rounded())]) })
                .flatMap { toFramePixels(Point(x: Double($0[0]), y: Double($0[1])), crop: crop, frameW: size.w, frameH: size.h) }
            frames.append(ManifestFrame(index: index, time: t, reasons: pick.reasons, file: "frames/\(name)",
                                        width: size.w, height: size.h, cursor: cur))
        }

        // Drawings, in the pixels of the frame they appear in.
        var strokes: [ManifestStroke] = []
        for s in rawStrokes {
            guard let crop = crop(at: s.t1) else { continue }
            let d = dims(crop)
            let px = s.points.compactMap { toFramePixels($0, crop: crop, frameW: d.w, frameH: d.h) }
            guard px.count >= 2 else { continue }
            let (bbox, text) = describeStroke(px, tool: s.tool)
            strokes.append(ManifestStroke(start: round2(s.t0), end: round2(s.t1), tool: s.tool, bbox: bbox, description: text,
                                          frameIndex: frames.first { $0.time >= s.t1 }?.index))
        }

        let manifest = Manifest(id: id, duration: round2(duration), mode: session.mode, transcript: transcript, frames: frames,
                                strokes: strokes,
                                timeline: buildTimeline(frames: frames, transcript: transcript, strokes: strokes, clears: clears, hidden: hidden),
                                note: session.note)
        try writeJSON(manifest, to: dir.appending(path: "manifest.json"))
        try writeAtomically(Data(renderPrompt(manifest, recordingDir: dir).utf8), to: dir.appending(path: "prompt.md"))
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
