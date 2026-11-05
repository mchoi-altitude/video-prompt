// Copies the screens' HTML next to their compiled scripts. Node rather than `cp`, so it also runs on Windows.
import { copyFileSync, mkdirSync, readdirSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const desktop = join(dirname(fileURLToPath(import.meta.url)), "..");
const from = join(desktop, "src", "ui");
const to = join(desktop, "dist", "ui");
mkdirSync(to, { recursive: true });
for (const f of readdirSync(from)) if (f.endsWith(".html")) copyFileSync(join(from, f), join(to, f));
