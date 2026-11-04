// Part of `npm run build`, without shell commands, so it works on Windows too.
const { cpSync, mkdirSync, readdirSync } = require("node:fs");
const { join } = require("node:path");

const from = join(__dirname, "../src/ui");
const to = join(__dirname, "../dist/ui");
mkdirSync(to, { recursive: true });
for (const name of readdirSync(from)) {
  if (name.endsWith(".html")) cpSync(join(from, name), join(to, name));
}
