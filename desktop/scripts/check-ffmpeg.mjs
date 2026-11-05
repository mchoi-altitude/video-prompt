#!/usr/bin/env node
// Checks a Windows ffmpeg build (scripts/build-ffmpeg-win.sh): exactly the allowed encoders and decoders, so
// nothing patented that we'd have to license (H.264, HEVC, AAC...), no hardware codecs, and an LGPL licence.
// With --smoke, also runs each kind of ffmpeg command the app and its tests run, so a missing component
// shows up here rather than in a user's recording.
// Usage: node scripts/check-ffmpeg.mjs <folder with ffmpeg and ffprobe> [--smoke]
// `ffmpeg -codecs` isn't used: it lists h264 and aac from ffmpeg's table of codec names even when no code
// for them is built in. -encoders and -decoders list what is.
import { execFileSync } from "node:child_process";
import { existsSync, mkdtempSync, readFileSync, rmSync, statSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

const ENCODERS = ["libopus", "libvpx", "libvpx-vp9", "mjpeg", "pcm_s16le", "wrapped_avframe"];
const DECODERS = ["mjpeg", "opus", "pcm_s16le", "vp8", "vp9", "wrapped_avframe"];
const PATENTED = /h26[3-6]|hevc|vvc|avc|x26[45]|openh264|aac|nvenc|amf|qsv|_mf$|cuvid|vaapi|vulkan|d3d1[12]|fdk/i;

const [dir, flag] = process.argv.slice(2);
if (!dir || (flag && flag !== "--smoke")) {
  console.error("usage: check-ffmpeg.mjs <folder with ffmpeg and ffprobe> [--smoke]");
  process.exit(2);
}
const exe = process.platform === "win32" ? ".exe" : "";
const ffmpeg = join(dir, `ffmpeg${exe}`);
const ffprobe = join(dir, `ffprobe${exe}`);
for (const f of [ffmpeg, ffprobe]) if (!existsSync(f)) fail([`${f} not found`]);

const run = (cmd, args) => execFileSync(cmd, args, { encoding: "utf8", stdio: ["ignore", "pipe", "pipe"] });

function fail(problems) {
  for (const p of problems) console.error(`check-ffmpeg: ${p}`);
  process.exit(1);
}

/** Names from `-encoders` / `-decoders`: the second column of each line after the "------" rule. */
function listed(tool, kind) {
  const lines = run(tool, ["-hide_banner", `-${kind}`]).split(/\r?\n/);
  const start = lines.findIndex((l) => l.trim().startsWith("------"));
  return lines.slice(start + 1).map((l) => l.trim().split(/\s+/)[1]).filter(Boolean).sort();
}

function compare(what, got, want) {
  const problems = [];
  for (const n of got.filter((n) => !want.includes(n))) {
    problems.push(PATENTED.test(n) ? `${what}: ${n} is built in, and it's a codec we must not ship` : `${what}: unexpected ${n}`);
  }
  for (const n of want.filter((n) => !got.includes(n))) problems.push(`${what}: ${n} is missing`);
  return problems;
}

const problems = [
  ...compare("ffmpeg encoders", listed(ffmpeg, "encoders"), ENCODERS),
  ...compare("ffmpeg decoders", listed(ffmpeg, "decoders"), DECODERS),
  ...compare("ffprobe decoders", listed(ffprobe, "decoders"), DECODERS),
];
const hwaccels = run(ffmpeg, ["-hide_banner", "-hwaccels"]).split(/\r?\n/).slice(1).map((l) => l.trim()).filter(Boolean);
if (hwaccels.length) problems.push(`hardware acceleration built in: ${hwaccels.join(", ")}`);
const licence = run(ffmpeg, ["-hide_banner", "-L"]).replace(/\s+/g, " ");
if (!licence.includes("GNU Lesser General Public License")) problems.push("licence isn't LGPL");
const buildconf = run(ffmpeg, ["-hide_banner", "-buildconf"]);
for (const opt of ["--enable-gpl", "--enable-nonfree", "--enable-version3"]) {
  if (buildconf.includes(opt)) problems.push(`built with ${opt}`);
}
if (problems.length) fail(problems);
console.log(`check-ffmpeg: ${dir}: encoders ${ENCODERS.join(" ")}; decoders ${DECODERS.join(" ")}; LGPL`);

if (flag === "--smoke") smoke();

/** The kinds of commands src/process, src/frames and src/test run, with the Windows encoding settings. */
function smoke() {
  const t = mkdtempSync(join(tmpdir(), "check-ffmpeg-"));
  const f = (name) => join(t, name);
  const ff = (...args) => run(ffmpeg, ["-v", "error", "-y", ...args]);
  const probe = (...args) => run(ffprobe, ["-v", "error", ...args]);
  const made = (name) => {
    if (!existsSync(f(name)) || statSync(f(name)).size === 0) fail([`smoke: ${name} wasn't written`]);
  };
  try {
    // Recorder-like segments: VP8 + Opus WebM, and one cut off part-way (tests do both).
    ff("-f", "lavfi", "-i", "testsrc2=s=640x400:r=10:d=3", "-f", "lavfi", "-i", "sine=frequency=440:duration=3",
      "-c:v", "libvpx", "-b:v", "1M", "-c:a", "libopus", f("seg_001.webm"));
    made("seg_001.webm");
    const bytes = readFileSync(f("seg_001.webm"));
    writeFileSync(f("seg_002.webm"), bytes.subarray(0, Math.floor(bytes.length * 0.7)));
    probe("-show_entries", "packet=pts_time", "-of", "csv=p=0", f("seg_002.webm"));
    probe("-show_entries", "stream=codec_type,width,height", "-of", "json", f("seg_001.webm"));

    // processor.ts renderVideo's filter graph, encoded as Windows' video.mp4.
    const filters = [];
    let joined = "";
    ["1.000", "1.000"].forEach((d, i) => {
      filters.push(`[${i}:v]fps=10:start_time=0,tpad=stop_mode=clone:stop_duration=${d},trim=duration=${d},setpts=PTS-STARTPTS,` +
        `crop=600:360:10:10,scale=600:360:flags=lanczos,format=yuv420p,setsar=1[v${i}]`);
      filters.push(`[${i}:a]aresample=async=1:first_pts=0,apad,atrim=duration=${d},asetpts=PTS-STARTPTS[a${i}]`);
      joined += `[v${i}][a${i}]`;
    });
    filters.push(`${joined}concat=n=2:v=1:a=1[v][a]`);
    ff("-i", f("seg_001.webm"), "-i", f("seg_002.webm"), "-filter_complex", filters.join(";"), "-map", "[v]", "-map", "[a]",
      "-c:a", "libopus", "-b:a", "64k", "-c:v", "libvpx-vp9", "-crf", "36", "-b:v", "4M", "-deadline", "realtime",
      "-cpu-used", "8", "-row-mt", "1", "-tune-content", "screen", "-g", "50", "-r", "10", "-movflags", "+faststart", f("video.mp4"));
    made("video.mp4");
    const codecs = probe("-show_entries", "stream=codec_name", "-of", "csv=p=0", f("video.mp4")).split(/\r?\n/).filter(Boolean);
    if (codecs.join(",") !== "vp9,opus") fail([`smoke: video.mp4 has ${codecs.join(",")}, expected vp9,opus`]);
    probe("-show_entries", "format=duration", "-of", "csv=p=0", f("video.mp4"));
    probe("-count_packets", "-select_streams", "v:0", "-show_entries", "stream=nb_read_packets", "-of", "csv=p=0", f("video.mp4"));

    // Overview contact sheet, the speech-to-text WAV and a vp-frames frame.
    ff("-i", f("video.mp4"), "-vf", "fps=1/1:start_time=0:round=up,scale=160:96,tile=2x1:padding=4,format=yuvj420p",
      "-frames:v", "1", "-q:v", "4", "-strict", "unofficial", "-update", "1", f("overview.jpg"));
    made("overview.jpg");
    ff("-i", f("video.mp4"), "-vn", "-ac", "1", "-ar", "16000", f("audio.wav"));
    made("audio.wav");
    ff("-ss", "1", "-i", f("video.mp4"), "-frames:v", "1",
      "-vf", "scale='if(gt(iw,ih),min(iw,1568),-2)':'if(gt(iw,ih),-2,min(ih,1568))',format=yuvj420p",
      "-q:v", "3", "-strict", "unofficial", "-update", "1", f("frame.jpg"));
    made("frame.jpg");
    if (probe("-show_entries", "stream=width", "-of", "csv=p=0", f("frame.jpg")).trim() !== "600") fail(["smoke: frame.jpg has the wrong width"]);

    // -f null, as tools.ts's encoder probe does on Linux and tests may.
    ff("-f", "lavfi", "-i", "color=s=64x64:r=10:d=0.2", "-c:v", "libvpx-vp9", "-f", "null", "-");
  } catch (e) {
    fail([`smoke: ${String(e.stderr || e.message).trim()}`]);
  } finally {
    rmSync(t, { recursive: true, force: true });
  }
  console.log("check-ffmpeg: smoke run passed");
}
