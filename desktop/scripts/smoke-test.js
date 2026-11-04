// Checks an installed copy from the inside, with its own Electron, ffmpeg and whisper-cli: processes a
// test recording, then runs vp-frames and speech-to-text. It can't check anything on screen.
// Usage: ELECTRON_RUN_AS_NODE=1 <installed electron> smoke-test.js <app folder> <models folder> <wav>
const assert = require("node:assert/strict");
const { execFileSync, execSync } = require("node:child_process");
const { existsSync, mkdirSync, mkdtempSync, writeFileSync } = require("node:fs");
const { tmpdir } = require("node:os");
const { join } = require("node:path");

const [appDir, models, wav] = process.argv.slice(2);
const dist = join(appDir, "dist");
const { makePaths, processRecording, finalize } = require(join(dist, "process/processor.js"));
const { ffmpeg, findWhisper, transcribeWords } = require(join(dist, "process/tools.js"));

(async () => {
  assert.ok(existsSync(ffmpeg), `bundled ffmpeg not used: ${ffmpeg}`);
  const whisper = findWhisper(models);
  assert.ok(whisper, "whisper-cli or the model wasn't found");
  const words = await transcribeWords(whisper, wav);
  assert.match(words.map((w) => w.text).join(""), /ask not what your country/i);
  console.log("speech-to-text ok:", words.length, "words");

  const paths = makePaths(mkdtempSync(join(tmpdir(), "vp smoke ")));
  const id = "20261104-170000";
  const raw = join(paths.recordings, id, "raw");
  mkdirSync(raw, { recursive: true });
  execFileSync(ffmpeg, ["-v", "error", "-f", "lavfi", "-i", "testsrc2=s=1280x720:r=10:d=3", "-f", "lavfi", "-i", "sine=frequency=440:duration=3", "-c:v", "libvpx", "-b:v", "1M", "-c:a", "libopus", join(raw, "seg_001.webm")]);
  writeFileSync(join(raw, "session.json"), JSON.stringify({ mode: "area", display: { x: 0, y: 0, w: 1280, h: 720 }, area: { x: 100, y: 100, w: 640, h: 360 }, createdAt: new Date().toISOString() }));
  writeFileSync(join(raw, "events.jsonl"), JSON.stringify({ type: "stroke", seg: 1, t0: 0.5, t1: 1, points: [{ x: 200, y: 200 }, { x: 300, y: 210 }], tool: "pen" }) + "\n");
  const vpFrames = join(appDir, "bin/vp-frames.cmd");
  const meta = await processRecording(id, paths, vpFrames, { posixVpFrames: join(appDir, "bin/vp-frames") });
  assert.equal(meta.status, "reviewing");
  const timeline = finalize(id, { note: "smoke" }, paths, vpFrames, { posixVpFrames: join(appDir, "bin/vp-frames") });
  assert.ok(existsSync(join(paths.recordings, id, "overview.jpg")));
  console.log("processing ok:", timeline);

  delete process.env.ELECTRON_RUN_AS_NODE;
  const printed = execSync(`"${vpFrames}" "${join(paths.recordings, id, "video.mp4")}" --from 0.5 --to 1 --fps 2`).toString().trim().split(/\r?\n/);
  assert.equal(printed.length, 2);
  assert.ok(existsSync(printed[0]));
  console.log("vp-frames ok:", printed.length, "frames");
  console.log("SMOKE TEST PASSED");
})().catch((e) => {
  console.error(e);
  process.exit(1);
});
