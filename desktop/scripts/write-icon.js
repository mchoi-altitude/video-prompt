// Writes the app icon as raw 256x256 BGRA pixels, for ffmpeg to convert.
const { writeFileSync } = require("node:fs");
const { appBitmap } = require("../dist/main/icon.js");

writeFileSync(process.argv[2], appBitmap(256));
