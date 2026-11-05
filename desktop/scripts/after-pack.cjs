// electron-builder afterPack hook. On Windows, replaces Electron's ffmpeg.dll, which can decode H.264 and AAC, with
// Electron's own build without them (vendor/electron, from scripts/fetch-tools.mjs). The review screen plays VP9
// and Opus, which both builds handle. Runs on the unpacked app, before the installer is made.
const { createHash } = require("node:crypto");
const { copyFileSync, existsSync, readFileSync } = require("node:fs");
const { join } = require("node:path");

// ffmpeg.dll inside ffmpeg-v45.2.2-win32-x64.zip (whose own checksum fetch-tools.mjs checks).
const DLL_SHA256 = "1ba6abf97c49708147a60feb7bff56abd6a449f8c6397dc6acf07e6ae869d842";

exports.default = async function afterPack(context) {
  if (context.electronPlatformName !== "win32") return;
  const desktop = join(__dirname, "..");
  const vendor = join(desktop, "vendor", "electron");
  const electron = JSON.parse(readFileSync(join(desktop, "node_modules", "electron", "package.json"), "utf8")).version;
  const fetched = existsSync(join(vendor, "VERSION")) ? readFileSync(join(vendor, "VERSION"), "utf8").trim() : "nothing";
  if (fetched !== electron) {
    throw new Error(`vendor/electron has ffmpeg.dll for Electron ${fetched}, but the app uses ${electron}: run scripts/fetch-tools.mjs`);
  }
  const dll = join(vendor, "ffmpeg.dll");
  const got = createHash("sha256").update(readFileSync(dll)).digest("hex");
  if (got !== DLL_SHA256) throw new Error(`${dll}: unexpected checksum ${got}`);
  const target = join(context.appOutDir, "ffmpeg.dll");
  if (!existsSync(target)) throw new Error(`no ffmpeg.dll in ${context.appOutDir} to replace`);
  copyFileSync(dll, target);
  console.log("  • ffmpeg.dll replaced with Electron's build without H.264 and AAC");
};
