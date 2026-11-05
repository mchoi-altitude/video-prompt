// `npm start`: runs the app from source with the switches its system needs (X11 mode on Linux).
import { spawn } from "node:child_process";
import { createRequire } from "node:module";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const require = createRequire(import.meta.url);
const desktop = join(dirname(fileURLToPath(import.meta.url)), "..");
const electron = require("electron"); // the path to Electron's program
const { electronSwitches } = require(join(desktop, "dist", "core", "platform.js"));

const child = spawn(electron, [desktop, ...electronSwitches(process.platform), ...process.argv.slice(2)], { stdio: "inherit" });
child.on("exit", (code, signal) => process.exit(signal ? 1 : (code ?? 0)));
