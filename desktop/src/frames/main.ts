// vp-frames <video> --from S --to E [--fps N] [--out DIR]
// Same arguments and output as Sources/vp-frames/main.swift: writes JPEG frames and prints their
// paths, one per line, in time order. At most 100 frames per call: wider ranges are spread evenly.
import { mkdirSync, mkdtempSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { ffmpeg, mediaDuration, run } from "../process/tools";

const usage = "usage: vp-frames <video> --from S --to E [--fps N (≤10, default 2)] [--out DIR]\n";
const VIDEO_FPS = 10;
const MAX_FRAMES = 100;
const MAX_LONG_EDGE = 1568;

function fail(message: string): never {
  process.stderr.write(`vp-frames: ${message}\n${usage}`);
  process.exit(2);
}

const options = new Map<string, string>();
let video: string | undefined;
const rest = process.argv.slice(2);
while (rest.length) {
  const a = rest.shift()!;
  if (["--from", "--to", "--fps", "--out"].includes(a)) {
    if (!rest.length) fail(`${a} needs a value`);
    options.set(a, rest.shift()!);
  } else if (a.startsWith("--")) fail(`unknown option ${a}`);
  else if (video === undefined) video = a;
  else fail(`unexpected argument ${a}`);
}
if (video === undefined) fail("no video given");

function number(flag: string, fallback?: number): number {
  const s = options.get(flag);
  if (s === undefined) {
    if (fallback === undefined) fail(`${flag} is required`);
    return fallback;
  }
  const v = Number(s);
  if (s.trim() === "" || !Number.isFinite(v)) fail(`${flag} must be a number, got "${s}"`);
  return v;
}

const from = number("--from");
const to = number("--to", from);
const fps = number("--fps", 2);

async function main(path: string) {
  const out = options.get("--out") ?? mkdtempSync(join(tmpdir(), "vp-frames-"));
  mkdirSync(out, { recursive: true });
  const last = Math.max(0, (await mediaDuration(path)) - 0.05);
  const lo = Math.min(Math.max(0, Math.min(from, to)), last);
  const hi = Math.min(Math.max(0, Math.max(from, to)), last);
  let step = 1 / Math.min(Math.max(fps, 0.01), VIDEO_FPS);
  if (hi > lo && (hi - lo) / step + 1 > MAX_FRAMES) step = (hi - lo) / (MAX_FRAMES - 1);
  const times: number[] = [];
  for (let t = lo; t <= hi + 1e-6 && times.length < MAX_FRAMES; t += step) times.push(Math.round(t * 100) / 100);
  const scale = `scale='if(gt(iw,ih),min(iw,${MAX_LONG_EDGE}),-2)':'if(gt(iw,ih),-2,min(ih,${MAX_LONG_EDGE}))'`;
  for (let i = 0; i < times.length; i++) {
    const t = times[i];
    const name = `${String(i + 1).padStart(3, "0")}_t${t.toFixed(2).padStart(8, "0")}s.jpg`;
    const file = join(out, name);
    await run(ffmpeg, ["-v", "error", "-y", "-ss", String(t), "-i", path, "-frames:v", "1", "-vf", `${scale},format=yuvj420p`, "-q:v", "3", "-strict", "unofficial", "-update", "1", file]);
    console.log(file);
  }
}

main(video).catch((e) => {
  process.stderr.write(`vp-frames: ${e}\n`);
  process.exit(1);
});
