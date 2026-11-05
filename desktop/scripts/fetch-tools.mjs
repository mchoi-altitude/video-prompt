#!/usr/bin/env node
// Windows only: downloads the pinned ffmpeg, whisper-cli, speech model and Electron's ffmpeg.dll into vendor/,
// checksum-verified. The same files are used to develop and to package. Downloads are kept in vendor/downloads.
// ffmpeg is our own LGPL build without H.264 or AAC: scripts/build-ffmpeg-win.sh, released by
// .github/workflows/ffmpeg-windows.yml. To try a build that isn't released, set VIDEO_PROMPT_FFMPEG_ZIP to its zip
// (e.g. from that workflow's artifact). It isn't checksum-verified, and the windows-beta workflow refuses it.
import { createHash } from "node:crypto";
import { copyFileSync, cpSync, createWriteStream, existsSync, mkdirSync, readdirSync, readFileSync, renameSync, rmSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { Readable } from "node:stream";
import { pipeline } from "node:stream/promises";
import { execFileSync } from "node:child_process";
import { fileURLToPath } from "node:url";

if (process.platform !== "win32") {
  console.error("fetch-tools is for Windows. On Linux, install ffmpeg and use scripts/build-package.sh.");
  process.exit(1);
}

const FFMPEG_TAG = "ffmpeg-win64-9.0.2-1";
const FFMPEG_SHA256 = ""; // of the released zip, set once the release exists
const ELECTRON_VERSION = "45.2.2"; // must match package.json: its ffmpeg.dll replaces Electron's at packaging
const WHISPER_TAG = "b5454"; // the Windows build of v1.9.5, the version Linux builds
const REPO = "https://github.com/mchoi-altitude/video-prompt";

const desktop = join(dirname(fileURLToPath(import.meta.url)), "..");
const vendor = join(desktop, "vendor");
const cache = join(vendor, "downloads");
const bin = join(vendor, "bin");
const models = join(vendor, "models");
const electronDir = join(vendor, "electron");

const electronWanted = JSON.parse(readFileSync(join(desktop, "package.json"), "utf8")).devDependencies.electron;
if (electronWanted !== ELECTRON_VERSION) {
  throw new Error(`package.json uses Electron ${electronWanted}: update ELECTRON_VERSION and the ffmpeg.dll checksums ` +
    "here and in scripts/after-pack.cjs (from that release's SHASUMS256.txt)");
}
const localFfmpeg = process.env.VIDEO_PROMPT_FFMPEG_ZIP;
if (!localFfmpeg && !FFMPEG_SHA256) {
  throw new Error(`${FFMPEG_TAG} isn't released yet. Set VIDEO_PROMPT_FFMPEG_ZIP to a build of it (scripts/build-ffmpeg-win.sh).`);
}

const downloads = [
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
  {
    // Built by Electron without proprietary codecs: no H.264 or AAC. Checksum from the release's SHASUMS256.txt.
    file: `ffmpeg-v${ELECTRON_VERSION}-win32-x64.zip`,
    url: `https://github.com/electron/electron/releases/download/v${ELECTRON_VERSION}/ffmpeg-v${ELECTRON_VERSION}-win32-x64.zip`,
    sha256: "f62587999170d22deca40d6c40d5b4faa2b23989b113c5f282792b2d873794aa",
  },
];
if (!localFfmpeg) {
  downloads.push({ file: `${FFMPEG_TAG}.zip`, url: `${REPO}/releases/download/${FFMPEG_TAG}/${FFMPEG_TAG}.zip`, sha256: FFMPEG_SHA256 });
}

mkdirSync(cache, { recursive: true });
mkdirSync(models, { recursive: true });
// Start clean, so nothing from an earlier ffmpeg (or its licence) is left to ship.
for (const d of [bin, electronDir]) {
  rmSync(d, { recursive: true, force: true });
  mkdirSync(d, { recursive: true });
}

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

const fetched = Object.fromEntries((await Promise.all(downloads.map(fetchPinned))).map((path, i) => [downloads[i].file, path]));

// ffmpeg and ffprobe, with the build's licences and notes.
if (localFfmpeg) console.warn(`WARNING: using ${localFfmpeg}, not the released ${FFMPEG_TAG}. It isn't checksum-verified.`);
const ff = unzip(localFfmpeg ?? fetched[`${FFMPEG_TAG}.zip`], "ffmpeg");
const ffBin = findDir(ff, "ffmpeg.exe");
if (!ffBin) throw new Error("ffmpeg.exe not found in the ffmpeg zip");
const ffRoot = join(ffBin, "..");
for (const exe of ["ffmpeg.exe", "ffprobe.exe"]) copyFileSync(join(ffBin, exe), join(bin, exe));
cpSync(join(ffRoot, "licenses"), join(bin, "ffmpeg-licenses"), { recursive: true });
copyFileSync(join(ffRoot, "BUILD-INFO.txt"), join(bin, "ffmpeg-BUILD-INFO.txt"));
writeFileSync(
  join(bin, "ffmpeg-SOURCE.txt"),
  [
    ...(localFfmpeg ? [`UNPINNED local build: ${localFfmpeg}`, ""] : []),
    "ffmpeg.exe and ffprobe.exe are Video Prompt's own LGPL build of FFmpeg with libvpx and Opus. It has no H.264,",
    "HEVC or AAC encoder or decoder. How it was built: ffmpeg-BUILD-INFO.txt. Licences: ffmpeg-licenses.",
    `The build and all its source code: ${REPO}/releases/tag/${FFMPEG_TAG}`,
    "",
    "The app's ffmpeg.dll is Electron's own build without proprietary codecs (no H.264 or AAC):",
    `ffmpeg-v${ELECTRON_VERSION}-win32-x64.zip from https://github.com/electron/electron/releases/tag/v${ELECTRON_VERSION}.`,
    "Its licence is in LICENSES.chromium.html, next to the app.",
    "",
  ].join("\r\n"),
);

// Electron's ffmpeg.dll without H.264 and AAC, which scripts/after-pack.cjs puts in the installer.
const el = unzip(fetched[`ffmpeg-v${ELECTRON_VERSION}-win32-x64.zip`], "electron-ffmpeg");
copyFileSync(join(el, "ffmpeg.dll"), join(electronDir, "ffmpeg.dll"));
writeFileSync(join(electronDir, "VERSION"), ELECTRON_VERSION);

const wh = unzip(fetched["whisper-bin-x64.zip"], "whisper");
const whBin = findDir(wh, "whisper-cli.exe");
if (!whBin) throw new Error("whisper-cli.exe not found in the whisper download");
for (const f of readdirSync(whBin)) {
  if (f === "whisper-cli.exe" || f.toLowerCase().endsWith(".dll")) copyFileSync(join(whBin, f), join(bin, f));
}
copyFileSync(fetched["whisper.cpp-LICENSE"], join(bin, "whisper.cpp-LICENSE"));
copyFileSync(fetched["ggml-base.en.bin"], join(models, "ggml-base.en.bin"));

console.log(`ready: ${bin}`);
