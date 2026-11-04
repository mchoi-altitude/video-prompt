#!/usr/bin/env node
// Windows only: downloads the pinned ffmpeg, whisper-cli and speech model into vendor/, checksum-verified.
// The same files are used to develop and to package. Downloads are kept in vendor/downloads.
import { createHash } from "node:crypto";
import { copyFileSync, createWriteStream, existsSync, mkdirSync, readdirSync, readFileSync, renameSync, rmSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { Readable } from "node:stream";
import { pipeline } from "node:stream/promises";
import { execFileSync } from "node:child_process";
import { fileURLToPath } from "node:url";

if (process.platform !== "win32") {
  console.error("fetch-tools is for Windows. On Linux, install ffmpeg and use scripts/build-package.sh.");
  process.exit(1);
}

const FFMPEG_TAG = "autobuild-2026-09-30-13-08"; // a month-end build, which BtbN keeps long-term
const FFMPEG_NAME = "ffmpeg-n9.0.2-17-g2a571b6068-win64-gpl-9.0";
const WHISPER_TAG = "b5454"; // the Windows build of v1.9.5, the version Linux builds
const downloads = [
  {
    file: `${FFMPEG_NAME}.zip`,
    url: `https://github.com/BtbN/FFmpeg-Builds/releases/download/${FFMPEG_TAG}/${FFMPEG_NAME}.zip`,
    sha256: "a0e45723c72141975f51d8666302e614711745f3102b704ca3f82c897a58d278",
  },
  {
    file: "whisper-bin-x64.zip",
    url: `https://github.com/ggml-org/whisper.cpp/releases/download/${WHISPER_TAG}/whisper-bin-x64.zip`,
    sha256: "6ba69e3482d7826214f90a6a9c84ca07782aec1e1d0c6a7c30c994fd5d816ccb",
  },
  {
    file: "whisper.cpp-LICENSE",
    url: "https://raw.githubusercontent.com/ggml-org/whisper.cpp/v1.9.5/LICENSE",
    sha256: "94f29bbed6a22c35b992c5c6ebf0e7c92f13b836b90f36f461c9cf2f0f1d010d",
  },
  {
    file: "ggml-base.en.bin",
    url: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.en.bin",
    sha256: "a03779c86df3323075f5e796cb2ce5029f00ec8869eee3fdfb897afe36c6d002", // same as scripts/install.sh
  },
];

const vendor = join(dirname(fileURLToPath(import.meta.url)), "..", "vendor");
const cache = join(vendor, "downloads");
const bin = join(vendor, "bin");
const models = join(vendor, "models");
for (const d of [cache, bin, models]) mkdirSync(d, { recursive: true });

function sha256(file) {
  return createHash("sha256").update(readFileSync(file)).digest("hex");
}

async function fetchPinned({ file, url, sha256: want }) {
  const dest = join(cache, file);
  if (existsSync(dest) && sha256(dest) === want) return dest;
  console.log(`downloading ${file}`);
  const res = await fetch(url);
  if (!res.ok || !res.body) throw new Error(`${url}: HTTP ${res.status}`);
  const part = `${dest}.part`;
  await pipeline(Readable.fromWeb(res.body), createWriteStream(part));
  const got = sha256(part);
  if (got !== want) {
    rmSync(part, { force: true });
    throw new Error(`${file}: checksum mismatch (got ${got})`);
  }
  renameSync(part, dest);
  return dest;
}

/** Unzips with the tar that ships with Windows, into a fresh folder. Git Bash's GNU tar can come first on
 * PATH, and it reads "C:" as a remote host, so name Windows' own. */
function unzip(zip, name) {
  const out = join(cache, name);
  rmSync(out, { recursive: true, force: true });
  mkdirSync(out);
  execFileSync(join(process.env.SystemRoot ?? "C:\\Windows", "System32", "tar.exe"), ["-xf", zip, "-C", out]);
  return out;
}

function findDir(root, has) {
  if (existsSync(join(root, has))) return root;
  for (const e of readdirSync(root, { withFileTypes: true })) {
    if (!e.isDirectory()) continue;
    const found = findDir(join(root, e.name), has);
    if (found) return found;
  }
  return null;
}

const [ffmpegZip, whisperZip, whisperLicense, model] = await Promise.all(downloads.map(fetchPinned));

const ff = unzip(ffmpegZip, "ffmpeg");
const ffBin = findDir(ff, "ffmpeg.exe");
if (!ffBin) throw new Error("ffmpeg.exe not found in the ffmpeg download");
for (const exe of ["ffmpeg.exe", "ffprobe.exe"]) copyFileSync(join(ffBin, exe), join(bin, exe));
copyFileSync(join(ffBin, "..", "LICENSE.txt"), join(bin, "ffmpeg-LICENSE.txt"));
writeFileSync(
  join(bin, "ffmpeg-SOURCE.txt"),
  [
    "ffmpeg.exe and ffprobe.exe are an unmodified GPL build of FFmpeg by BtbN/FFmpeg-Builds.",
    `Build: https://github.com/BtbN/FFmpeg-Builds/releases/tag/${FFMPEG_TAG} (${FFMPEG_NAME}.zip)`,
    "Build scripts, including the versions of every bundled library: https://github.com/BtbN/FFmpeg-Builds",
    "FFmpeg source for this build: https://github.com/FFmpeg/FFmpeg/tree/2a571b6068",
    "",
  ].join("\r\n"),
);

const wh = unzip(whisperZip, "whisper");
const whBin = findDir(wh, "whisper-cli.exe");
if (!whBin) throw new Error("whisper-cli.exe not found in the whisper download");
for (const f of readdirSync(whBin)) {
  if (f === "whisper-cli.exe" || f.toLowerCase().endsWith(".dll")) copyFileSync(join(whBin, f), join(bin, f));
}
copyFileSync(whisperLicense, join(bin, "whisper.cpp-LICENSE"));
copyFileSync(model, join(models, "ggml-base.en.bin"));

console.log(`ready: ${bin}`);
