// What differs between Linux and Windows, in one place. Each function takes the platform, so the tests
// check both systems' answers on either one. The Linux answers must stay what the app used before
// Windows support, since Fedora can't be retested from Windows.
import { existsSync } from "node:fs";
import { posix, win32 } from "node:path";

export type Platform = NodeJS.Platform;
type Env = Record<string, string | undefined>;

const pathFor = (p: Platform) => (p === "win32" ? win32 : posix);

/** The data folder. `VIDEO_PROMPT_HOME` overrides it, as on the Mac. */
export function dataRoot(p: Platform, env: Env, home: string): string {
  if (env.VIDEO_PROMPT_HOME) return env.VIDEO_PROMPT_HOME;
  if (p === "win32") return win32.join(env.LOCALAPPDATA ?? win32.join(home, "AppData", "Local"), "VideoPrompt");
  return posix.join(home, ".local/share/VideoPrompt");
}

/** Linux keeps the data folder private with mode 0700. Windows' per-user AppData already is. */
export const restrictsDataFolder = (p: Platform) => p !== "win32";

/** On Plasma, the overlay and bar only stay above other windows as notification windows. */
export const windowType = (p: Platform): { type?: string } => (p === "win32" ? {} : { type: "notification" });

/** Fedora can't hide the bar from the capture. Windows can (`setContentProtection`). */
export const hidesBarFromCapture = (p: Platform) => p === "win32";

/** On Windows the bar never takes keyboard focus, like the Mac's: keys such as F11 stay with the app
 * the user is showing. Electron's default menu also goes, or its shortcuts (F11 full screen, Ctrl+R
 * reload, Ctrl+W close) would act on our windows. Fedora keeps both as they were. */
export const barTakesFocus = (p: Platform) => p !== "win32";
export const keepsDefaultMenu = (p: Platform) => p !== "win32";

/** Fedora's system dialog chooses what's recorded. Windows has none, so the app's own picker does. */
export const captureMode = (p: Platform): "dialog" | "picker" => (p === "win32" ? "picker" : "dialog");

/** Nothing logs clicks yet: Fedora can't see them, and Windows needs a native mouse hook. */
export const logsClicks = (_p: Platform) => false;

/** Command-line switches the app needs, given when it starts. */
export const electronSwitches = (p: Platform): string[] => (p === "linux" ? ["--ozone-platform=x11"] : []);

/** `appDir` is the folder with `package.json`: `desktop/` from source, `resources/app` installed. */
export function vpFramesPath(p: Platform, appDir: string): string {
  return pathFor(p).join(appDir, "bin", p === "win32" ? "vp-frames.cmd" : "vp-frames");
}

/** ffmpeg or ffprobe. Windows uses the bundled copy when there is one; Linux uses the system's. */
export function toolPath(p: Platform, name: "ffmpeg" | "ffprobe", env: Env, appDir: string, exists = existsSync): string {
  const override = env[name === "ffmpeg" ? "VIDEO_PROMPT_FFMPEG" : "VIDEO_PROMPT_FFPROBE"];
  if (override) return override;
  if (p === "win32") {
    const bundled = win32.join(appDir, "vendor", "bin", `${name}.exe`);
    if (exists(bundled)) return bundled;
  }
  return name;
}

/** Where whisper-cli may be, in order. */
export function whisperCandidates(p: Platform, env: Env, appDir: string): string[] {
  const own = env.VIDEO_PROMPT_WHISPER_CLI ? [env.VIDEO_PROMPT_WHISPER_CLI] : [];
  if (p === "win32") return [...own, win32.join(appDir, "vendor", "bin", "whisper-cli.exe")];
  return [...own, "/usr/bin/whisper-cli", "/usr/bin/whisper-cpp", posix.join(appDir, "vendor/bin/whisper-cli")];
}

/** Where the speech model may be, in order. Windows bundles it with the app. */
export function modelCandidates(p: Platform, env: Env, modelsDir: string, appDir: string): string[] {
  const name = "ggml-base.en.bin";
  if (env.VIDEO_PROMPT_WHISPER_MODEL) return [env.VIDEO_PROMPT_WHISPER_MODEL];
  const path = pathFor(p);
  if (p === "win32") return [path.join(modelsDir, name), path.join(appDir, "vendor", "models", name)];
  return [path.join(modelsDir, name)];
}
