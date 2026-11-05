// Builds out/VideoPrompt-windows-beta-setup.exe: the app, its Electron, ffmpeg, whisper-cli and the speech
// model, so nothing else needs installing. Windows only. Publishes nothing.
import { execFileSync, spawnSync } from "node:child_process";
import { createRequire } from "node:module";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

if (process.platform !== "win32") {
  console.error("package:win is for Windows. On Linux, use npm run package.");
  process.exit(1);
}
const desktop = join(dirname(fileURLToPath(import.meta.url)), "..");
const npm = (args) => execFileSync(process.env.ComSpec ?? "cmd.exe", ["/d", "/c", "npm", ...args], { cwd: desktop, stdio: "inherit" });

execFileSync(process.execPath, [join(desktop, "scripts", "fetch-tools.mjs")], { stdio: "inherit" });
npm(["test"]);

// The installer's icon, from the same drawing code as the tray.
const require = createRequire(import.meta.url);
const pixels = require(join(desktop, "dist", "main", "icon.js")).appBitmap(256);
const ffmpeg = join(desktop, "vendor", "bin", "ffmpeg.exe");
const icon = spawnSync(ffmpeg, ["-v", "error", "-y", "-f", "rawvideo", "-pix_fmt", "bgra", "-s", "256x256", "-i", "-", "-frames:v", "1", "-update", "1", join(desktop, "dist", "icon-256.png")], { input: pixels });
if (icon.status !== 0) throw new Error(`icon: ${icon.stderr}`);

npm(["exec", "--", "electron-builder", "--win", "--x64"]);
