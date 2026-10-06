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

    public init(store: Store, paths: Paths, transcriber: Transcriber?, calendar: Calendar = .current) {
        self.store = store; self.paths = paths; self.transcriber = transcriber; self.calendar = calendar
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
        let (asset, durations) = try await joinSegments(segURLs)
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
            }
        }
        let crops = CropTimeline(mode: session.mode, display: session.display, area: session.area, windowSamples: windows)
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
            guard let crop = crops.crop(at: pick.time) else { hidden.append(pick.time); continue }
            let index = frames.count + 1
            let t = pick.time
            let name = String(format: "frame_%02d_%02dm%04.1fs.jpg", index, Int(t / 60), t.truncatingRemainder(dividingBy: 60))
            let img = try await grabFrame(asset, at: t, crop: crop, display: session.display)
            let size = try writeJPEG(img, maxLongEdge: 1568, to: framesDir.appending(path: name))
            let d = dims(crop)
            let cur = cursor(at: t, in: cursorPts.map { CursorSample(t: $0.t, p: [Int($0.p.x.rounded()), Int($0.p.y.rounded())]) })
                .flatMap { toFramePixels(Point(x: Double($0[0]), y: Double($0[1])), crop: crop, frameW: d.w, frameH: d.h) }
            frames.append(ManifestFrame(index: index, time: t, reasons: pick.reasons, file: "frames/\(name)",
                                        width: size.w, height: size.h, cursor: cur))
        }

        // Drawings, in the pixels of the frame they appear in.
        var strokes: [ManifestStroke] = []
        for s in rawStrokes {
            guard let crop = crops.crop(at: s.t1) else { continue }
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
        try fm.removeItem(at: raw)

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

func round2(_ x: Double) -> Double { (x * 100).rounded() / 100 }

func folderSize(_ dir: URL) -> Int64 {
    let e = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: [.fileSizeKey])
    var total: Int64 = 0
    while let u = e?.nextObject() as? URL { total += Int64((try? u.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
    return total
}
