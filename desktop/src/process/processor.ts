// Port of Sources/VPProcess/Processor.swift and Finalize.swift, with ffmpeg in place of AVFoundation.
import { mkdirSync, readdirSync, readFileSync, renameSync, rmSync, statSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { buildTimeline, describeStroke, renderTimeline, round2, segmentOffsets, sentences, titleFor, toFramePixels } from "../core/timeline";
import {
  VIDEO_FPS,
  VIDEO_MAX_HEIGHT,
  type Manifest,
  type ManifestStroke,
  type Point,
  type RawEvent,
  type RawSession,
  type Rect,
  type RecordingMeta,
  type Sentence,
  type StrokeTool,
  type TranscriptionState,
} from "../core/models";
import { ffmpeg, findWhisper, h264Encoder, mediaDuration, run, segmentDuration, transcribeWords, videoInfo } from "./tools";

export type Paths = { root: string; recordings: string; models: string };

export function makePaths(root: string): Paths {
  return { root, recordings: join(root, "recordings"), models: join(root, "models") };
}

export function writeAtomically(path: string, data: string) {
  mkdirSync(dirname(path), { recursive: true });
  const tmp = `${path}.tmp-${process.pid}`;
  writeFileSync(tmp, data);
  renameSync(tmp, path);
}

export const writeJSON = (path: string, value: unknown) => writeAtomically(path, JSON.stringify(value, null, 2));
export const readJSON = <T>(path: string): T => JSON.parse(readFileSync(path, "utf8"));

function folderSize(dir: string): number {
  let total = 0;
  for (const e of readdirSync(dir, { withFileTypes: true })) {
    const p = join(dir, e.name);
    total += e.isDirectory() ? folderSize(p) : statSync(p).size;
  }
  return total;
}

const even = (v: number) => Math.max(2, Math.round(v / 2) * 2);

/** The part of `r` inside `bounds`; null when none of it is. */
function clip(r: Rect, b: Rect): Rect | null {
  const x0 = Math.max(r.x, b.x);
  const y0 = Math.max(r.y, b.y);
  const x1 = Math.min(r.x + r.w, b.x + b.w);
  const y1 = Math.min(r.y + r.h, b.y + b.h);
  return x1 > x0 && y1 > y0 ? { x: x0, y: y0, w: x1 - x0, h: y1 - y0 } : null;
}

function segmentNumber(name: string): number | null {
  const m = /^seg_(\d+)\./.exec(name);
  return m ? Number(m[1]) : null;
}

/** Turns `recordings/<id>/raw/` into a `reviewing` recording. On failure `raw/` is kept for a Retry. */
export async function processRecording(id: string, paths: Paths, vpFrames: string): Promise<RecordingMeta> {
  const dir = join(paths.recordings, id);
  const raw = join(dir, "raw");
  const session = readJSON<RawSession>(join(raw, "session.json"));
  const meta: RecordingMeta = { id, title: "Processing…", createdAt: session.createdAt, duration: 0, mode: "area", status: "processing", sizeBytes: 0 };
  writeJSON(join(dir, "meta.json"), meta);
  try {
    const done = await runPipeline(id, dir, raw, session, meta, paths, vpFrames);
    writeJSON(join(dir, "meta.json"), done);
    return done;
  } catch (e) {
    const failed: RecordingMeta = { ...meta, status: "processingFailed", error: String(e) };
    writeJSON(join(dir, "meta.json"), failed);
    throw e;
  }
}

async function runPipeline(id: string, dir: string, raw: string, session: RawSession, meta: RecordingMeta, paths: Paths, vpFrames: string): Promise<RecordingMeta> {
  const names = readdirSync(raw).filter((n) => segmentNumber(n) !== null).sort();
  if (!names.length) throw new Error("no segments");
  const files = names.map((n) => join(raw, n));
  const lengths = await Promise.all(files.map(segmentDuration));
  // Events name segments by file number, which can skip an empty segment, so key by number.
  const durations = new Map(names.map((n, i) => [segmentNumber(n)!, lengths[i]]));
  const offsets = segmentOffsets(durations);
  const pauses = [...offsets.values()].filter((o) => o > 0).sort((a, b) => a - b).map(round2);
  const infos = await Promise.all(files.map(videoInfo));
  const natural = infos[0];
  const hasAudio = infos.every((i) => i.hasAudio);

  const fromDialog = session.regionFromDialog === true;
  const located = fromDialog && session.regionLocated === true;
  // A region from the dialog is already the whole stream.
  const frame: Rect = located ? session.area : fromDialog ? { x: 0, y: 0, w: natural.width, h: natural.height } : session.display;
  const crop = fromDialog ? frame : clip(session.area, frame) ?? frame;
  const sx = natural.width / frame.w;
  const sy = natural.height / frame.h;
  const outScale = Math.min(1, VIDEO_MAX_HEIGHT / (crop.h * sy));
  const width = even(crop.w * sx * outScale);
  const height = even(crop.h * sy * outScale);

  const eventsText = readFileSync(join(raw, "events.jsonl"), "utf8");
  const events: RawEvent[] = eventsText.split("\n").filter(Boolean).map((l) => JSON.parse(l));
  const clears: number[] = [];
  const clicksRaw: { t: number; p: Point }[] = [];
  const rawStrokes: { t0: number; t1: number; points: Point[]; tool: StrokeTool }[] = [];
  for (const e of events) {
    const o = offsets.get(e.seg);
    if (o === undefined) continue;
    if (e.type === "stroke") rawStrokes.push({ t0: o + e.t0, t1: o + e.t1, points: e.points, tool: e.tool });
    else if (e.type === "clear") clears.push(round2(o + e.t));
    else if (e.type === "click") clicksRaw.push({ t: o + e.t, p: e.p });
    else {
      // Drop the latest stroke finished before the undo: it never meant anything.
      const at = o + e.t;
      for (let i = rawStrokes.length - 1; i >= 0; i--) {
        if (rawStrokes[i].t1 <= at) {
          rawStrokes.splice(i, 1);
          break;
        }
      }
    }
  }
  const videoPixels = (p: Point) => toFramePixels(p, crop, width, height);
  const strokes: ManifestStroke[] = [];
  for (const s of rawStrokes) {
    if (fromDialog && !located) {
      strokes.push({ start: round2(s.t0), end: round2(s.t1), tool: s.tool, bbox: [], description: "drew a mark (its position isn't known, so look for red marks in the video around this time)" });
      continue;
    }
    const px = s.points.flatMap((p) => videoPixels(p) ?? []);
    const pts: number[][] = [];
    for (let i = 0; i < px.length; i += 2) pts.push([px[i], px[i + 1]]);
    if (pts.length < 2) continue;
    const { bbox, text } = describeStroke(pts, s.tool);
    strokes.push({ start: round2(s.t0), end: round2(s.t1), tool: s.tool, bbox, description: text });
  }
  const clicks = clicksRaw.flatMap((c) => {
    const px = videoPixels(c.p);
    return px ? [{ t: round2(c.t), x: px[0], y: px[1] }] : [];
  });

  const video = join(dir, "video.mp4");
  const cropX = Math.round((crop.x - frame.x) * sx);
  const cropY = Math.round((crop.y - frame.y) * sy);
  await renderVideo(files, lengths, hasAudio, { cw: even(crop.w * sx), ch: even(crop.h * sy), cx: cropX, cy: cropY, width, height }, video);
  const duration = await mediaDuration(video);

  const { secondsPerTile } = await makeOverview(video, duration, width, height, join(dir, "overview.jpg"));

  // A speech-to-text failure shouldn't lose the recording: it's still saved, and says so.
  let transcript: Sentence[] = [];
  let transcription: TranscriptionState = "noAudio";
  if (hasAudio) {
    const whisper = findWhisper(paths.models);
    if (!whisper) transcription = "unavailable";
    else {
      const wav = join(raw, "audio.wav");
      await run(ffmpeg, ["-v", "error", "-y", "-i", video, "-vn", "-ac", "1", "-ar", "16000", wav]);
      try {
        transcript = sentences(await transcribeWords(whisper, wav));
        transcription = transcript.length ? "ok" : "noSpeech";
      } catch (e) {
        console.error("transcription failed", e);
        transcription = "unavailable";
      }
    }
  }

  const manifest: Manifest = {
    id,
    duration: round2(duration),
    mode: "area",
    transcript,
    transcription,
    video: { file: "video.mp4", width, height, fps: VIDEO_FPS, hasAudio },
    overview: "overview.jpg",
    overviewSecondsPerTile: secondsPerTile,
    strokes,
    clicks,
    clicksLogged: process.platform === "win32",
    timeline: buildTimeline(transcript, strokes, clicks, clears, pauses),
  };
  writeJSON(join(dir, "manifest.json"), manifest);
  writeAtomically(join(dir, "timeline.md"), renderTimeline(manifest, dir, vpFrames));
  rmSync(raw, { recursive: true, force: true });
  return {
    ...meta,
    status: "reviewing",
    duration: manifest.duration,
    title: titleFor(transcript, new Date(meta.createdAt)),
    sizeBytes: folderSize(dir),
  };
}

/** Joins segments, holding the last frame to each segment's end since a still screen emits few frames. */
async function renderVideo(
  files: string[],
  lengths: number[],
  hasAudio: boolean,
  g: { cw: number; ch: number; cx: number; cy: number; width: number; height: number },
  out: string,
) {
  const filters: string[] = [];
  let joined = "";
  files.forEach((_, i) => {
    const d = lengths[i].toFixed(3);
    filters.push(
      `[${i}:v]fps=${VIDEO_FPS}:start_time=0,tpad=stop_mode=clone:stop_duration=${d},trim=duration=${d},setpts=PTS-STARTPTS,` +
        `crop=${g.cw}:${g.ch}:${g.cx}:${g.cy},scale=${g.width}:${g.height}:flags=lanczos,format=yuv420p,setsar=1[v${i}]`,
    );
    joined += `[v${i}]`;
    if (hasAudio) {
      filters.push(`[${i}:a]aresample=async=1:first_pts=0,apad,atrim=duration=${d},asetpts=PTS-STARTPTS[a${i}]`);
      joined += `[a${i}]`;
    }
  });
  filters.push(`${joined}concat=n=${files.length}:v=1:a=${hasAudio ? 1 : 0}${hasAudio ? "[v][a]" : "[v]"}`);
  const args = ["-v", "error", "-y", ...files.flatMap((f) => ["-i", f]), "-filter_complex", filters.join(";"), "-map", "[v]"];
  if (hasAudio) args.push("-map", "[a]", "-c:a", "aac", "-b:a", "96k");
  args.push("-c:v", h264Encoder(), "-b:v", "4M", "-r", String(VIDEO_FPS), "-movflags", "+faststart", out);
  await run(ffmpeg, args);
}

/** Contact sheet: same tile limits as Sources/VPMedia/Overview.swift. */
async function makeOverview(video: string, duration: number, width: number, height: number, out: string) {
  const maxTiles = 60;
  const tileWidth = 320;
  const gap = 4;
  const secondsPerTile = Math.max(1, Math.ceil(duration / maxTiles));
  const tiles = Math.min(maxTiles, Math.max(1, Math.ceil(duration / secondsPerTile)));
  const cols = Math.min(6, tiles);
  const rows = Math.ceil(tiles / cols);
  const aspect = height / width;
  const fit = Math.min(1, (4000 - (cols - 1) * gap) / (cols * tileWidth), (4000 - (rows - 1) * gap) / (rows * tileWidth * aspect));
  const tw = Math.max(16, Math.floor(tileWidth * fit));
  const th = Math.max(16, Math.floor(tileWidth * aspect * fit));
  await run(ffmpeg, [
    "-v", "error", "-y", "-i", video,
    "-vf", `fps=1/${secondsPerTile},scale=${tw}:${th},tile=${cols}x${rows}:padding=${gap}`,
    "-frames:v", "1", "-q:v", "4", "-update", "1", out,
  ]);
  return { secondsPerTile };
}

/** Applies the review panel's edits, rewrites `manifest.json` and `timeline.md`, and marks it `ready`. */
export function finalize(id: string, edits: { transcriptText?: string; note?: string }, paths: Paths, vpFrames: string): string {
  const dir = join(paths.recordings, id);
  const m = readJSON<Manifest>(join(dir, "manifest.json"));
  const text = edits.transcriptText?.trim();
  if (text !== undefined && text !== m.transcript.map((s) => s.text).join(" ")) {
    m.transcript = text ? [{ start: 0, end: m.duration, text }] : [];
    m.timeline = m.timeline.filter((i) => i.kind !== "speech");
    if (text) m.timeline.unshift({ kind: "speech", time: 0, end: m.duration, text });
  }
  if (edits.note !== undefined) m.note = edits.note || undefined;
  writeJSON(join(dir, "manifest.json"), m);
  const timeline = join(dir, "timeline.md");
  writeAtomically(timeline, renderTimeline(m, dir, vpFrames));
  const meta = readJSON<RecordingMeta>(join(dir, "meta.json"));
  writeJSON(join(dir, "meta.json"), { ...meta, status: "ready", sizeBytes: folderSize(dir) });
  return timeline;
}
