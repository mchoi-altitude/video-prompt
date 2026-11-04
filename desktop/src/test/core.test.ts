import assert from "node:assert/strict";
import { execFileSync, spawnSync } from "node:child_process";
import { mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import type { Manifest, Manifest as M, RecordingMeta } from "../core/models";
import { buildTimeline, expiredRecordings, type Retention, describeStroke, renderTimeline, segmentOffsets, sentences, stamp, titleFor, toFramePixels } from "../core/timeline";
import { finalize, makePaths, processRecording, readJSON, recoverInterrupted } from "../process/processor";
import { ffmpeg, ffprobe, parseWhisper } from "../process/tools";
import { blended, locate, patternSteps, SAMPLE_INSET, stepLevel, type RGB, type Step } from "../core/locate";

const repo = join(__dirname, "../../..");

/** Runs bin/vp-frames, or bin/vp-frames.cmd on Windows. Node runs a .cmd only through cmd.exe, which
 * needs each argument quoted, since test folders have spaces. */
function runVpFrames(args: string[]): Buffer {
  if (process.platform !== "win32") return execFileSync(join(repo, "desktop/bin/vp-frames"), args);
  const line = [join(repo, "desktop", "bin", "vp-frames.cmd"), ...args].map((a) => `"${a}"`).join(" ");
  const r = spawnSync(process.env.ComSpec ?? "cmd.exe", ["/d", "/s", "/c", `"${line}"`], { windowsVerbatimArguments: true });
  if (r.status !== 0) throw new Error(`vp-frames.cmd exited ${r.status}: ${r.stderr}`);
  return r.stdout;
}
const circle: number[][] = [[47, 554], [90, 514], [180, 514], [223, 554], [180, 594], [90, 594], [47, 560], [50, 555], [47, 554]];

test("the timeline matches the Mac's golden file, apart from the design's §7 differences", () => {
  const strokes = [{ start: 3, end: 4, tool: "pen" as const, bbox: [47, 514, 223, 594], description: describeStroke(circle, "pen").text }];
  const clicks = [{ t: 6.2, x: 812, y: 96 }];
  const transcript = [
    { start: 1, end: 2.5, text: "So, the settings page." },
    { start: 3, end: 4.5, text: "See this Save button?" },
  ];
  const m: Manifest = {
    id: "20261006-141402",
    duration: 12.5,
    mode: "area",
    transcript,
    transcription: "ok",
    video: { file: "video.mp4", width: 1394, height: 1050, fps: 10, hasAudio: true },
    overview: "overview.jpg",
    overviewSecondsPerTile: 1,
    strokes,
    clicks,
    clicksLogged: true,
    timeline: buildTimeline(transcript, strokes, clicks, [], [8.5]),
    note: "Same on Billing.",
  };
  const golden = readFileSync(join(repo, "Tests/VPCoreTests/Golden/timeline.md"), "utf8")
    .replace("It shows only the recorded window.", "It shows only the selected area.")
    .replace("call `get_frames` (from, to, fps) if you have the Video Prompt tools, or run", "run")
    .replace("--from 12.0 --to 14.0", "--from 0.0 --to 2.0")
    .replace("- **[00:07.0]** The recorded window was hidden\n", "");
  assert.equal(renderTimeline(m, "/R", "/Apps/vp-frames"), golden);
});

test("on Windows the timeline gives vp-frames for PowerShell, Git Bash and WSL", () => {
  const m: M = {
    id: "x", duration: 5, mode: "area", transcript: [], transcription: "noAudio",
    video: { file: "video.mp4", width: 100, height: 100, fps: 10, hasAudio: false },
    overview: "overview.jpg", overviewSecondsPerTile: 1, strokes: [], clicks: [], clicksLogged: false, timeline: [],
  };
  const dir = "C:\\Users\\A B\\AppData\\Local\\VideoPrompt\\recordings\\x";
  const text = renderTimeline(m, dir, "C:\\Users\\A B\\AppData\\Local\\Programs\\Video Prompt\\resources\\app\\bin\\vp-frames.cmd");
  const section = text.slice(text.indexOf("## The recording"), text.indexOf("## Timeline"));
  assert.equal(section, [
    "## The recording",
    "",
    "- **Video:** `C:\\Users\\A B\\AppData\\Local\\VideoPrompt\\recordings\\x\\video.mp4` (100×100, 10 fps). It shows only the selected area.",
    "- **Overview:** `C:\\Users\\A B\\AppData\\Local\\VideoPrompt\\recordings\\x\\overview.jpg` (in WSL: `/mnt/c/Users/A B/AppData/Local/VideoPrompt/recordings/x/overview.jpg`): one thumbnail per second. Look at it first.",
    "- **Look closer at any moment:** run",
    "  the command for your shell, and view the JPEGs it prints with your Read tool.",
    "  - PowerShell: `& \"C:\\Users\\A B\\AppData\\Local\\Programs\\Video Prompt\\resources\\app\\bin\\vp-frames.cmd\" \"C:\\Users\\A B\\AppData\\Local\\VideoPrompt\\recordings\\x\\video.mp4\" --from 0.0 --to 2.0 --fps 5`",
    "  - Git Bash: `\"C:/Users/A B/AppData/Local/Programs/Video Prompt/resources/app/bin/vp-frames.sh\" \"C:/Users/A B/AppData/Local/VideoPrompt/recordings/x/video.mp4\" --from 0.0 --to 2.0 --fps 5`",
    "  - WSL: `\"/mnt/c/Users/A B/AppData/Local/Programs/Video Prompt/resources/app/bin/vp-frames.sh\" \"/mnt/c/Users/A B/AppData/Local/VideoPrompt/recordings/x/video.mp4\" --from 0.0 --to 2.0 --fps 5`",
    "  Check the moments the narration and drawings point to; brief states may last under a second.",
    "",
    "",
  ].join("\n"));
});

test("timeline leaves out click wording where clicks can't be logged", () => {
  const m: M = {
    id: "x", duration: 5, mode: "area", transcript: [], transcription: "noAudio",
    video: { file: "video.mp4", width: 100, height: 100, fps: 10, hasAudio: false },
    overview: "overview.jpg", overviewSecondsPerTile: 1, strokes: [], clicks: [], clicksLogged: false, timeline: [],
  };
  const text = renderTimeline(m, "/R", "/vp-frames");
  assert.doesNotMatch(text, /click/i);
  assert.match(text, /microphone was off/);
});

test("the example command stays inside a short recording", () => {
  const m: M = {
    id: "x", duration: 1.5, mode: "area", transcript: [], transcription: "noSpeech",
    video: { file: "video.mp4", width: 100, height: 100, fps: 10, hasAudio: false },
    overview: "overview.jpg", overviewSecondsPerTile: 1, strokes: [], clicks: [], clicksLogged: false, timeline: [],
  };
  assert.match(renderTimeline(m, "/R", "/vp-frames"), /--from 0\.0 --to 1\.5/);
});

test("stroke descriptions cover each case", () => {
  assert.equal(describeStroke(circle, "pen").text, "circled the area (47,514)–(223,594)");
  assert.equal(describeStroke([[0, 0], [50, 50]], "arrow").text, "drew an arrow from (0,0) to (50,50)");
  assert.equal(describeStroke([[0, 0], [50, 50]], "box").text, "boxed the area (0,0)–(50,50)");
  assert.equal(describeStroke([[0, 10], [100, 12]], "pen").text, "underlined/marked horizontally from (0,10) to (100,12)");
  assert.equal(describeStroke([[0, 0], [50, 90]], "pen").text, "drew a line from (0,0) to (50,90)");
  const hook = [[0, 0], [40, 0], [80, 0], [100, 30], [100, 60], [100, 90], [70, 100], [40, 100], [20, 100], [20, 60]];
  assert.match(describeStroke(hook, "pen").text, /curved mark|circled/);
});

test("sentences, titles, stamps and coordinates", () => {
  const words = [" So,", " the", " page.", " See", " this?"].map((text, i) => ({ start: i, end: i + 0.5, text }));
  assert.deepEqual(sentences(words).map((s) => [s.start, s.end, s.text]), [[0, 2.5, "So, the page."], [3, 4.5, "See this?"]]);
  assert.equal(titleFor([{ start: 0, end: 1, text: "Fix the button." }], new Date()), "Fix the button");
  assert.equal(titleFor([], new Date(2026, 0, 1, 9, 5)), "Recording 09:05");
  assert.ok(titleFor([{ start: 0, end: 1, text: "word ".repeat(30) }], new Date()).endsWith("…"));
  assert.equal(stamp(64.25), "01:04.3");
  assert.deepEqual(toFramePixels({ x: 150, y: 100 }, { x: 100, y: 50, w: 100, h: 100 }, 200, 200), [100, 100]);
  assert.equal(toFramePixels({ x: 99, y: 100 }, { x: 100, y: 50, w: 100, h: 100 }, 200, 200), null);
  assert.deepEqual([...segmentOffsets(new Map([[3, 2], [1, 5]]))], [[1, 0], [3, 5]]);
});

test("auto-delete removes what the policy says, and never a recording still processing", () => {
  const now = Date.parse("2026-11-04T12:00:00Z");
  const ago = (days: number) => new Date(now - days * 86400_000).toISOString();
  const metas = [
    { id: "today", status: "ready", createdAt: ago(0.1) },
    { id: "edge", status: "ready", createdAt: ago(2.9) },
    { id: "old", status: "ready", createdAt: ago(5) },
    { id: "old-review", status: "reviewing", createdAt: ago(5) },
    { id: "old-busy", status: "processing", createdAt: ago(5) },
  ];
  const ids = (policy: Retention) => expiredRecordings(metas, policy, now).map((m) => m.id);
  assert.deepEqual(ids({ days: 3 }), ["old", "old-review"]);
  assert.deepEqual(ids({ days: 1 }), ["edge", "old", "old-review"]);
  assert.deepEqual(ids({ keepLast: 2 }), ["old", "old-review"]);
  assert.deepEqual(ids("never"), []);
});

test("recordings cut off by a crash are listed as failed, and Retry recovers them", async () => {
  const paths = makePaths(mkdtempSync(join(tmpdir(), "vp test ")));
  const session = JSON.stringify({ mode: "area", display: { x: 0, y: 0, w: 640, h: 400 }, area: { x: 0, y: 0, w: 640, h: 400 }, createdAt: "2026-11-04T15:32:10.000Z" });
  const start = (id: string, meta?: object) => {
    const raw = join(paths.recordings, id, "raw");
    mkdirSync(raw, { recursive: true });
    writeFileSync(join(raw, "session.json"), session);
    writeFileSync(join(raw, "events.jsonl"), "");
    if (meta) writeFileSync(join(paths.recordings, id, "meta.json"), JSON.stringify(meta));
    return raw;
  };
  const raw = start("cut-off");
  // A file that stops mid-write, as a crash leaves it.
  const whole = join(raw, "whole.webm");
  execFileSync(ffmpeg, ["-v", "error", "-f", "lavfi", "-i", "testsrc2=s=640x400:r=10:d=3", "-f", "lavfi", "-i", "sine=frequency=440:duration=3", "-c:v", "libvpx", "-b:v", "1M", "-c:a", "libopus", whole]);
  const bytes = readFileSync(whole);
  writeFileSync(join(raw, "seg_001.webm"), bytes.subarray(0, Math.floor(bytes.length * 0.7)));
  rmSync(whole);
  start("stuck", { id: "stuck", status: "processing", createdAt: "2026-11-04T15:32:10.000Z" });
  start("failed-before", { id: "failed-before", status: "processingFailed", title: "keep", createdAt: "2026-11-04T15:32:10.000Z" });
  mkdirSync(join(paths.recordings, "finished"));
  writeFileSync(join(paths.recordings, "finished", "meta.json"), JSON.stringify({ id: "finished", status: "ready" }));

  assert.deepEqual(recoverInterrupted(paths).sort(), ["cut-off", "stuck"]);
  const meta = (id: string) => readJSON<RecordingMeta>(join(paths.recordings, id, "meta.json"));
  assert.equal(meta("cut-off").status, "processingFailed");
  assert.equal(meta("stuck").status, "processingFailed");
  assert.equal(meta("failed-before").title, "keep");
  assert.equal(meta("finished").status, "ready");
  assert.deepEqual(recoverInterrupted(paths), [], "nothing to do the second time");

  const retried = await processRecording("cut-off", paths, "/vp-frames");
  assert.equal(retried.status, "reviewing");
  assert.ok(retried.duration > 1, `kept ${retried.duration}s`);
  assert.ok(readFileSync(join(paths.recordings, "cut-off", "video.mp4")).length > 0);
});

test("a very short recording still gets its overview", async () => {
  const paths = makePaths(mkdtempSync(join(tmpdir(), "vp test ")));
  const id = "20261104-150000";
  const raw = join(paths.recordings, id, "raw");
  mkdirSync(raw, { recursive: true });
  execFileSync(ffmpeg, ["-v", "error", "-f", "lavfi", "-i", "testsrc2=s=696x444:r=10:d=0.3", "-f", "lavfi", "-i", "sine=frequency=440:duration=0.3", "-c:v", "libvpx", "-b:v", "1M", "-c:a", "libopus", join(raw, "seg_001.webm")]);
  writeFileSync(join(raw, "session.json"), JSON.stringify({ mode: "area", display: { x: 0, y: 0, w: 696, h: 444 }, area: { x: 0, y: 0, w: 696, h: 444 }, createdAt: new Date().toISOString() }));
  writeFileSync(join(raw, "events.jsonl"), "");
  assert.equal((await processRecording(id, paths, "/vp-frames")).status, "reviewing");
  assert.ok(readFileSync(join(paths.recordings, id, "overview.jpg")).length > 0);
});

test("whisper output drops bracketed non-speech", () => {
  const json = JSON.stringify({ transcription: [
    { offsets: { from: 0, to: 500 }, text: " Hello." },
    { offsets: { from: 500, to: 900 }, text: " [BLANK_AUDIO]" },
  ] });
  assert.deepEqual(parseWhisper(json), [{ start: 0, end: 0.5, text: " Hello." }]);
});

test("a region from the system dialog is kept whole, and its marks don't claim coordinates", async () => {
  const paths = makePaths(mkdtempSync(join(tmpdir(), "vp test ")));
  const id = "20261104-130000";
  const raw = join(paths.recordings, id, "raw");
  mkdirSync(raw, { recursive: true });
  execFileSync(ffmpeg, ["-v", "error", "-f", "lavfi", "-i", "testsrc2=s=488x318:r=10:d=1", "-c:v", "libvpx", "-b:v", "1M", join(raw, "seg_001.webm")]);
  writeFileSync(join(raw, "session.json"), JSON.stringify({
    mode: "area", display: { x: 0, y: 0, w: 1920, h: 1200 }, area: { x: 0, y: 0, w: 1920, h: 1200 }, regionFromDialog: true, createdAt: new Date().toISOString(),
  }));
  writeFileSync(join(raw, "events.jsonl"), JSON.stringify({ type: "stroke", seg: 1, t0: 0.1, t1: 0.5, points: [{ x: 900, y: 700 }, { x: 950, y: 720 }], tool: "pen" }) + "\n");
  await processRecording(id, paths, "/vp-frames");
  const m = readJSON<Manifest>(join(paths.recordings, id, "manifest.json"));
  assert.deepEqual([m.video.width, m.video.height], [488, 318]);
  assert.equal(m.strokes.length, 1);
  assert.match(readFileSync(join(paths.recordings, id, "timeline.md"), "utf8"), /drew a mark \(its position isn't known/);
});

test("a region is located from the faint code, and changes on screen are rejected", () => {
  const W = 1920, H = 1200;
  const steps = patternSteps(W, H);
  assert.equal(steps.length, 11);
  const gray = (v: number): RGB => [v, v, v];
  const samplesFor = (rx: number, ry: number, rw: number, rh: number, under: [number, number]) => {
    const before = { width: rw, height: rh, first: gray(under[0]), last: gray(under[1]) };
    const seen = (step: Step, x: number, y: number, s: number) => gray(Math.round(blended(s, stepLevel(step, x, y))));
    const samples = steps.map((step) => ({
      width: rw, height: rh,
      first: seen(step, rx + SAMPLE_INSET, ry + SAMPLE_INSET, under[0]),
      last: seen(step, rx + rw - 1 - SAMPLE_INSET, ry + rh - 1 - SAMPLE_INSET, under[1]),
    }));
    return { before, samples };
  };
  const regions = [[0, 0, 488, 318], [701, 433, 488, 318], [1432, 882, 488, 318], [63, 64, 200, 100], [240, 489, 642, 524], [1278, 676, 642, 524], [857, 367, 522, 330], [0, 0, 1919, 1199]];
  // Whatever's on screen under the test pixels: black, white, dark and light UI.
  for (const under of [[0, 255], [255, 0], [34, 240], [128, 128]] as [number, number][]) {
    for (const [rx, ry, rw, rh] of regions) {
      const { before, samples } = samplesFor(rx, ry, rw, rh, under);
      assert.deepEqual(locate(steps, before, samples, before, W, H), { x: rx, y: ry }, `region ${rx},${ry} over ${under}`);
    }
  }
  // Something on screen changing during the measurement is caught, by either check.
  const { before, samples } = samplesFor(701, 433, 488, 318, [34, 240]);
  assert.equal(locate(steps, before, samples, { ...before, first: gray(120) }, W, H), null, "the screen changed");
  const changed = samples.map((s, i) => (i === 3 ? { ...s, first: gray(200) } : s));
  assert.equal(locate(steps, before, changed, before, W, H), null, "one frame was off");
});

test("marks in a located region get real video coordinates", async () => {
  const paths = makePaths(mkdtempSync(join(tmpdir(), "vp test ")));
  const id = "20261104-140000";
  const raw = join(paths.recordings, id, "raw");
  mkdirSync(raw, { recursive: true });
  execFileSync(ffmpeg, ["-v", "error", "-f", "lavfi", "-i", "testsrc2=s=488x318:r=10:d=1", "-c:v", "libvpx", "-b:v", "1M", join(raw, "seg_001.webm")]);
  writeFileSync(join(raw, "session.json"), JSON.stringify({
    mode: "area", display: { x: 0, y: 0, w: 1920, h: 1200 }, area: { x: 700, y: 400, w: 488, h: 318 }, regionFromDialog: true, regionLocated: true, createdAt: new Date().toISOString(),
  }));
  const stroke = (x: number) => JSON.stringify({ type: "stroke", seg: 1, t0: 0.1, t1: 0.5, points: [{ x, y: 410 }, { x: x + 100, y: 412 }], tool: "pen" });
  writeFileSync(join(raw, "events.jsonl"), [stroke(710), stroke(10)].join("\n") + "\n");
  await processRecording(id, paths, "/vp-frames");
  const m = readJSON<Manifest>(join(paths.recordings, id, "manifest.json"));
  assert.deepEqual([m.video.width, m.video.height], [488, 318]);
  assert.equal(m.strokes.length, 1, "a mark outside the region isn't in the video");
  assert.deepEqual(m.strokes[0].bbox, [10, 10, 110, 12]);
});

test("processing joins paused segments, crops to the area and maps marks to video pixels", async () => {
  const root = mkdtempSync(join(tmpdir(), "vp test "));
  const paths = makePaths(root);
  const id = "20261104-120000";
  const raw = join(paths.recordings, id, "raw");
  mkdirSync(raw, { recursive: true });
  for (const [n, d] of [[1, 2], [2, 1]]) {
    execFileSync(ffmpeg, ["-v", "error", "-f", "lavfi", "-i", `testsrc2=s=1920x1200:r=10:d=${d}`,
      "-f", "lavfi", "-i", `sine=frequency=440:duration=${d}`, "-c:v", "libvpx", "-b:v", "1M", "-c:a", "libopus", join(raw, `seg_00${n}.webm`)]);
  }
  writeFileSync(join(raw, "session.json"), JSON.stringify({
    mode: "area", display: { x: 0, y: 0, w: 1920, h: 1200 }, area: { x: 100, y: 100, w: 800, h: 600 }, createdAt: new Date().toISOString(),
  }));
  const events = [
    { type: "stroke", seg: 1, t0: 0.5, t1: 0.9, points: [{ x: 100, y: 100 }, { x: 900, y: 110 }], tool: "pen" },
    { type: "stroke", seg: 2, t0: 0.1, t1: 0.2, points: [{ x: 500, y: 400 }, { x: 600, y: 500 }], tool: "arrow" },
    { type: "undo", seg: 2, t: 0.5 },
    { type: "clear", seg: 2, t: 0.6 },
  ];
  writeFileSync(join(raw, "events.jsonl"), events.map((e) => JSON.stringify(e)).join("\n") + "\n");

  const meta = await processRecording(id, paths, "/vp-frames");
  assert.equal(meta.status, "reviewing");
  const dir = join(paths.recordings, id);
  const m = readJSON<Manifest>(join(dir, "manifest.json"));
  assert.deepEqual([m.video.width, m.video.height], [800, 600]);
  assert.ok(Math.abs(m.duration - 3.2) < 0.4, `duration ${m.duration}`);
  assert.equal(m.strokes.length, 1, "undo removes the arrow");
  assert.deepEqual(m.strokes[0].bbox, [0, 0, 800, 10]);
  const pause = m.timeline.find((i) => i.kind === "pause")!;
  assert.ok(pause.time > 1.8 && pause.time < 2.4, `pause at ${pause.time}`);
  const frames = Number(execFileSync(ffprobe, ["-v", "error", "-count_packets", "-select_streams", "v:0", "-show_entries", "stream=nb_read_packets", "-of", "csv=p=0", join(dir, "video.mp4")]).toString().replace(/\D/g, ""));
  assert.ok(Math.abs(frames / m.duration - 10) < 1, `${frames} frames in ${m.duration}s`);
  assert.equal(readJSON<RecordingMeta>(join(dir, "meta.json")).status, "reviewing");

  const timeline = finalize(id, { transcriptText: "Edited words.", note: "A note" }, paths, "/vp-frames");
  const text = readFileSync(timeline, "utf8");
  assert.match(text, /Edited words\./);
  assert.match(text, /## Typed note\n\nA note/);
  assert.equal(readJSON<RecordingMeta>(join(dir, "meta.json")).status, "ready");

  const out = runVpFrames([join(dir, "video.mp4"), "--from", "0.5", "--to", "1", "--fps", "2"]).toString().trim().split(/\r?\n/);
  assert.deepEqual(out.map((p) => p.replace(/.*[\\/]/, "")), ["001_t00000.50s.jpg", "002_t00001.00s.jpg"]);
  assert.match(execFileSync(ffprobe, ["-v", "error", "-show_entries", "stream=width", "-of", "csv=p=0", out[0]]).toString(), /800/);

  // Windows: Git Bash runs vp-frames.sh instead, since cmd splits the .cmd's path at spaces there.
  if (process.platform === "win32") {
    const sh = execFileSync("bash", [join(repo, "desktop", "bin", "vp-frames.sh"), join(dir, "video.mp4"), "--from", "0.5", "--to", "1", "--fps", "2"]);
    assert.deepEqual(sh.toString().trim().split(/\r?\n/).map((p) => p.replace(/.*[\\/]/, "")), ["001_t00000.50s.jpg", "002_t00001.00s.jpg"]);
  }
});
