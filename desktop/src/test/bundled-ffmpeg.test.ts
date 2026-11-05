// Windows bundles its own ffmpeg (scripts/fetch-tools.mjs). It must have exactly the allowed codecs and none we'd
// have to license, such as H.264, HEVC or AAC. Since package:win runs these tests, no installer gets built with
// any other ffmpeg. Linux uses the system's ffmpeg, so there's nothing to check there.
import { execFileSync } from "node:child_process";
import { join } from "node:path";
import { test } from "node:test";

const desktop = join(__dirname, "../..");

test("the bundled ffmpeg has only the allowed codecs", { skip: process.platform !== "win32" && "Linux uses the system's ffmpeg" }, () => {
  try {
    execFileSync(process.execPath, [join(desktop, "scripts", "check-ffmpeg.mjs"), join(desktop, "vendor", "bin")], { stdio: "pipe" });
  } catch (e) {
    throw new Error(String((e as { stderr?: Buffer }).stderr ?? e));
  }
});
