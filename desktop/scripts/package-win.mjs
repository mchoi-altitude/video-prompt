// Builds out/VideoPrompt-windows-beta-setup.exe: the app, its Electron, ffmpeg, whisper-cli and the speech
// model, so nothing else needs installing. Windows only. Publishes nothing.
import { execFileSync } from "node:child_process";
import { writeFileSync } from "node:fs";
import { createRequire } from "node:module";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { crc32, deflateSync } from "node:zlib";

if (process.platform !== "win32") {
  console.error("package:win is for Windows. On Linux, use npm run package.");
  process.exit(1);
}
const desktop = join(dirname(fileURLToPath(import.meta.url)), "..");
const npm = (args) => execFileSync(process.env.ComSpec ?? "cmd.exe", ["/d", "/c", "npm", ...args], { cwd: desktop, stdio: "inherit" });

/** A PNG from BGRA pixels. Written here because the bundled ffmpeg has only what the app itself needs. */
function png(width, height, bgra) {
  const row = width * 4 + 1;
  const raw = Buffer.alloc(row * height); // each row: filter type 0, then RGBA
  for (let y = 0; y < height; y++) {
    for (let x = 0; x < width; x++) {
      const s = (y * width + x) * 4;
      const d = y * row + 1 + x * 4;
      raw[d] = bgra[s + 2];
      raw[d + 1] = bgra[s + 1];
      raw[d + 2] = bgra[s];
      raw[d + 3] = bgra[s + 3];
    }
  }
  const chunk = (type, data) => {
    const body = Buffer.concat([Buffer.from(type, "ascii"), data]);
    const len = Buffer.alloc(4);
    len.writeUInt32BE(data.length);
    const crc = Buffer.alloc(4);
    crc.writeUInt32BE(crc32(body));
    return Buffer.concat([len, body, crc]);
  };
  const header = Buffer.alloc(13);
  header.writeUInt32BE(width, 0);
  header.writeUInt32BE(height, 4);
  header.set([8, 6, 0, 0, 0], 8); // 8-bit RGBA, no interlace
  const signature = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);
  return Buffer.concat([signature, chunk("IHDR", header), chunk("IDAT", deflateSync(raw)), chunk("IEND", Buffer.alloc(0))]);
}

execFileSync(process.execPath, [join(desktop, "scripts", "fetch-tools.mjs")], { stdio: "inherit" });
npm(["test"]);

// The installer's icon, from the same drawing code as the tray.
const require = createRequire(import.meta.url);
writeFileSync(join(desktop, "dist", "icon-256.png"), png(256, 256, require(join(desktop, "dist", "main", "icon.js")).appBitmap(256)));

npm(["exec", "--", "electron-builder", "--win", "--x64", "--publish", "never"]);
