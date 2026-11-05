// Both systems' answers, checked on either one. The Linux ones are what the app used before Windows support.
import assert from "node:assert/strict";
import { test } from "node:test";
import { barTakesFocus, keepsDefaultMenu, captureMode, dataRoot, electronSwitches, hidesBarFromCapture, logsClicks, modelCandidates, restrictsDataFolder, toolPath, vpFramesPath, whisperCandidates, windowType } from "../core/platform";

const none = () => false;
const all = () => true;

test("Linux keeps its paths and window settings", () => {
  assert.equal(dataRoot("linux", {}, "/home/a"), "/home/a/.local/share/VideoPrompt");
  assert.equal(dataRoot("linux", { VIDEO_PROMPT_HOME: "/tmp/vp" }, "/home/a"), "/tmp/vp");
  assert.equal(restrictsDataFolder("linux"), true);
  assert.deepEqual(windowType("linux"), { type: "notification" });
  assert.equal(hidesBarFromCapture("linux"), false);
  assert.equal(barTakesFocus("linux"), true);
  assert.equal(keepsDefaultMenu("linux"), true);
  assert.equal(captureMode("linux"), "dialog");
  assert.equal(logsClicks("linux"), false);
  assert.deepEqual(electronSwitches("linux"), ["--ozone-platform=x11"]);
  assert.equal(vpFramesPath("linux", "/opt/app"), "/opt/app/bin/vp-frames");
});

test("Linux finds tools where it did before", () => {
  assert.equal(toolPath("linux", "ffmpeg", {}, "/opt/app", all), "ffmpeg");
  assert.equal(toolPath("linux", "ffprobe", {}, "/opt/app", all), "ffprobe");
  assert.equal(toolPath("linux", "ffmpeg", { VIDEO_PROMPT_FFMPEG: "/x/ffmpeg" }, "/opt/app"), "/x/ffmpeg");
  assert.deepEqual(whisperCandidates("linux", {}, "/opt/app"), ["/usr/bin/whisper-cli", "/usr/bin/whisper-cpp", "/opt/app/vendor/bin/whisper-cli"]);
  assert.deepEqual(whisperCandidates("linux", { VIDEO_PROMPT_WHISPER_CLI: "/w" }, "/opt/app")[0], "/w");
  assert.deepEqual(modelCandidates("linux", {}, "/d/models", "/opt/app"), ["/d/models/ggml-base.en.bin"]);
  assert.deepEqual(modelCandidates("linux", { VIDEO_PROMPT_WHISPER_MODEL: "/m.bin" }, "/d/models", "/opt/app"), ["/m.bin"]);
});

test("Windows uses AppData, its own picker and the bundled tools", () => {
  assert.equal(dataRoot("win32", { LOCALAPPDATA: "C:\\Users\\A B\\AppData\\Local" }, "C:\\Users\\A B"), "C:\\Users\\A B\\AppData\\Local\\VideoPrompt");
  assert.equal(dataRoot("win32", {}, "C:\\Users\\A B"), "C:\\Users\\A B\\AppData\\Local\\VideoPrompt");
  assert.equal(restrictsDataFolder("win32"), false);
  assert.deepEqual(windowType("win32"), {});
  assert.equal(hidesBarFromCapture("win32"), true);
  assert.equal(barTakesFocus("win32"), false);
  assert.equal(keepsDefaultMenu("win32"), false);
  assert.equal(captureMode("win32"), "picker");
  assert.equal(logsClicks("win32"), false);
  assert.deepEqual(electronSwitches("win32"), []);
  assert.equal(vpFramesPath("win32", "C:\\App"), "C:\\App\\bin\\vp-frames.cmd");
  assert.equal(toolPath("win32", "ffmpeg", {}, "C:\\App", all), "C:\\App\\vendor\\bin\\ffmpeg.exe");
  assert.equal(toolPath("win32", "ffprobe", {}, "C:\\App", none), "ffprobe");
  assert.deepEqual(whisperCandidates("win32", {}, "C:\\App"), ["C:\\App\\vendor\\bin\\whisper-cli.exe"]);
  assert.deepEqual(modelCandidates("win32", {}, "C:\\D\\models", "C:\\App"), ["C:\\D\\models\\ggml-base.en.bin", "C:\\App\\vendor\\models\\ggml-base.en.bin"]);
});
