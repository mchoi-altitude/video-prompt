// `npm start`. On Linux the app runs through XWayland: see "Linux notes" in CLAUDE.md.
const { spawnSync } = require("node:child_process");
const electron = require("electron");

const args = process.platform === "linux" ? ["--ozone-platform=x11", "."] : ["."];
process.exit(spawnSync(electron, args, { stdio: "inherit" }).status ?? 1);
