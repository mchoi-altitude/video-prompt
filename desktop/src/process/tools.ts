import { spawn, spawnSync } from "node:child_process";
import { existsSync, readFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import type { Word } from "../core/models";

export const ffmpeg = process.env.VIDEO_PROMPT_FFMPEG ?? "ffmpeg";
export const ffprobe = process.env.VIDEO_PROMPT_FFPROBE ?? "ffprobe";

/** Runs a tool to completion; rejects with the end of its stderr on failure. */
export function run(cmd: string, args: string[]): Promise<string> {
  return new Promise((resolve, reject) => {
    const p = spawn(cmd, args, { stdio: ["ignore", "pipe", "pipe"] });
    let out = "";
    let err = "";
    p.stdout.on("data", (d) => (out += d));
    p.stderr.on("data", (d) => (err = (err + d).slice(-2000)));
    p.on("error", reject);
    p.on("close", (code) => (code === 0 ? resolve(out) : reject(new Error(`${cmd} exited ${code}: ${err}`))));
  });
}

let chosenEncoder: string | undefined;

/** Fedora can list an H.264 encoder that's a non-working stub, so test-encode before choosing. */
export function h264Encoder(): string {
  if (chosenEncoder) return chosenEncoder;
  for (const enc of ["libx264", "libopenh264"]) {
    const test = spawnSync(ffmpeg, ["-v", "error", "-f", "lavfi", "-i", "color=s=64x64:r=10:d=0.2", "-c:v", enc, "-pix_fmt", "yuv420p", "-f", "null", "-"]);
    if (test.status === 0) return (chosenEncoder = enc);
  }
  throw new Error("no working H.264 encoder in ffmpeg");
}

/** Length of a segment: MediaRecorder's WebM files don't record their duration, so read the last packet. */
export async function segmentDuration(file: string): Promise<number> {
  const out = await run(ffprobe, ["-v", "error", "-show_entries", "packet=pts_time", "-of", "csv=p=0", file]);
  let last = 0;
  for (const line of out.split("\n")) {
    const t = parseFloat(line);
    if (t > last) last = t;
  }
  return last + 0.1;
}

export async function videoInfo(file: string): Promise<{ width: number; height: number; hasAudio: boolean }> {
  const out = await run(ffprobe, ["-v", "error", "-show_entries", "stream=codec_type,width,height", "-of", "json", file]);
  const streams: { codec_type: string; width?: number; height?: number }[] = JSON.parse(out).streams;
  const v = streams.find((s) => s.codec_type === "video");
  if (!v?.width || !v.height) throw new Error(`no video stream in ${file}`);
  return { width: v.width, height: v.height, hasAudio: streams.some((s) => s.codec_type === "audio") };
}

export async function mediaDuration(file: string): Promise<number> {
  return parseFloat(await run(ffprobe, ["-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", file]));
}

/** `whisper-cli`, under either name it's installed as; null when it or the model is missing. */
export function findWhisper(modelsDir: string): { cli: string; model: string } | null {
  const model = process.env.VIDEO_PROMPT_WHISPER_MODEL ?? join(modelsDir, "ggml-base.en.bin");
  const bundled = join(__dirname, "../../vendor/bin", process.platform === "win32" ? "whisper-cli.exe" : "whisper-cli");
  const candidates = [process.env.VIDEO_PROMPT_WHISPER_CLI, "/usr/bin/whisper-cli", "/usr/bin/whisper-cpp", bundled];
  const cli = candidates.find((c): c is string => !!c && existsSync(c));
  return cli && existsSync(model) ? { cli, model } : null;
}

/** One segment per word, so each word carries its own timestamps. */
export async function transcribeWords(whisper: { cli: string; model: string }, wav: string): Promise<Word[]> {
  const base = join(tmpdir(), `vp-whisper-${process.pid}-${Date.now()}`);
  try {
    await run(whisper.cli, ["-m", whisper.model, "-f", wav, "-l", "en", "-ml", "1", "-sow", "-oj", "-of", base, "-np"]);
    return parseWhisper(readFileSync(`${base}.json`, "utf8"));
  } finally {
    rmSync(`${base}.json`, { force: true });
  }
}

export function parseWhisper(json: string): Word[] {
  const items: { offsets: { from: number; to: number }; text: string }[] = JSON.parse(json).transcription;
  return items.flatMap((item) => {
    const t = item.text.trim();
    if (!t || (t.startsWith("[") && t.endsWith("]"))) return [];
    return [{ start: item.offsets.from / 1000, end: item.offsets.to / 1000, text: item.text }];
  });
}
