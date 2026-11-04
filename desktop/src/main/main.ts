// The app: tray, recording state, windows and file storage. See docs/superpowers/specs/2026-11-04-windows-linux-design.md.
import { app, BrowserWindow, clipboard, desktopCapturer, globalShortcut, ipcMain, Menu, nativeImage, screen, session, shell, Tray, type Display } from "electron";
import { createWriteStream, existsSync, mkdirSync, appendFileSync, chmodSync, readdirSync, type WriteStream } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";
import type { Manifest, Point, RawEvent, RawSession, Rect, RecordingMeta, StrokeTool } from "../core/models";
import { appBitmap, trayBitmap } from "./icon";
import { locate, patternSteps, SAMPLE_INSET, type Sample } from "../core/locate";
import { expiredRecordings, type Retention } from "../core/timeline";
import { dataRoot, restrictsDataFolder, vpFramesPath, windowType } from "../core/platform";
import { finalize, makePaths, processRecording, recoverInterrupted, readJSON, writeJSON } from "../process/processor";

const platform = process.platform;
const root = dataRoot(platform, process.env, homedir());
const paths = makePaths(root);
const vpFrames = vpFramesPath(platform, join(__dirname, "../.."));
const settingsFile = join(root, "settings.json");

type Settings = { retention: Retention; drawingsFade: boolean };
const defaults: Settings = { retention: { days: 3 }, drawingsFade: true };

function loadSettings(): Settings {
  // Missing keys keep their defaults, so adding a setting never resets the others.
  return existsSync(settingsFile) ? { ...defaults, ...readJSON<Partial<Settings>>(settingsFile) } : { ...defaults };
}

type State = "idle" | "selecting" | "countdown" | "recording" | "paused" | "processing";
let state: State = "idle";
let settings = defaults;

let tray: Tray | undefined;
let recorder: BrowserWindow | undefined;
let overlay: BrowserWindow | undefined;
let bar: BrowserWindow | undefined;
let recordingsWindow: BrowserWindow | undefined;
let settingsWindow: BrowserWindow | undefined;

let recordingId = "";
let rawDir = "";
let segment = 0;
let segmentStart: number | null = null;
let segmentFile: WriteStream | undefined;
let elapsedBefore = 0;
let currentOrigin: { x: number; y: number } | undefined;

function ui(name: string) {
  return join(__dirname, "../ui", `${name}.html`);
}

const webPreferences = {
  preload: join(__dirname, "preload.js"),
  contextIsolation: true,
  nodeIntegration: false,
  sandbox: true,
};

const rect = (b: { x: number; y: number; width: number; height: number }): Rect => ({ x: b.x, y: b.y, w: b.width, h: b.height });

// ---- Tray

function trayIcon() {
  const pixels = 44;
  const live = state === "countdown" || state === "recording" || state === "paused";
  const bitmap = trayBitmap(live ? "recording" : "idle", pixels);
  return nativeImage.createFromBitmap(bitmap, { width: pixels, height: pixels, scaleFactor: 2 });
}

function windowIcon() {
  const pixels = 256;
  return nativeImage.createFromBitmap(appBitmap(pixels), { width: pixels, height: pixels });
}

function refreshTray() {
  const busy = state !== "idle";
  tray?.setContextMenu(
    Menu.buildFromTemplate([
      ...(state === "recording" || state === "paused" ? [{ label: "Stop recording", click: () => void stopRecording() }] : []),
      { label: "Record…", enabled: !busy, accelerator: "Ctrl+Alt+Shift+R", click: () => void startFlow() },
      { type: "separator" },
      { label: "Recordings…", click: openRecordings },
      { label: "Settings…", click: openSettings },
      { label: "Quit Video Prompt", click: () => app.quit() },
    ]),
  );
}

// Electron can't reliably open the native menu from a left click on Linux, so left click opens this
// small window with the same items. It sits by the tray: at the corner of the work area, on
// whichever side the panel leaves room, since neither the tray's position nor (under XWayland) the
// cursor's is known while it's over the panel.
let trayMenu: BrowserWindow | undefined;

function closeTrayMenu() {
  trayMenu?.destroy();
  trayMenu = undefined;
}

function toggleTrayMenu() {
  if (trayMenu) return closeTrayMenu();
  const { bounds, workArea } = screen.getPrimaryDisplay();
  const width = 280;
  const canStop = state === "recording" || state === "paused";
  // Four rows, or five with Stop, plus the divider, padding and border.
  const height = (canStop ? 5 : 4) * 24 + 9 + 12;
  const panelOnTop = workArea.y > bounds.y;
  trayMenu = new BrowserWindow({
    x: workArea.x + workArea.width - width - 8,
    y: panelOnTop ? workArea.y + 8 : workArea.y + workArea.height - height - 8,
    width,
    height,
    frame: false,
    transparent: true,
    resizable: false,
    skipTaskbar: true,
    alwaysOnTop: true,
    show: false,
    webPreferences,
  });
  trayMenu.loadFile(ui("tray-menu"));
  trayMenu.once("ready-to-show", () => trayMenu?.show());
  trayMenu.on("blur", closeTrayMenu);
}

ipcMain.handle("tray-menu-info", () => ({
  busy: state !== "idle",
  canStop: state === "recording" || state === "paused",
  count: listRecordings().filter((m) => m.status !== "processing").length,
}));
ipcMain.on("tray-menu-close", closeTrayMenu);
ipcMain.on("tray-menu-action", (_e, action: string) => {
  closeTrayMenu();
  if (action === "stop") void stopRecording();
  else if (action === "record") void startFlow();
  else if (action === "recordings") openRecordings();
  else if (action === "settings") openSettings();
  else if (action === "quit") app.quit();
});

// ---- Starting: the system's dialog chooses what's recorded (a screen or a region), then countdown

async function startFlow() {
  if (state !== "idle") return;
  setState("selecting");
  try {
    recorder ??= createRecorder();
    await recorderReady;
    // A user gesture is required for getDisplayMedia; this hidden window can't have one otherwise.
    const got: { width: number; height: number } = await recorder.webContents.executeJavaScript("startCapture()", true);
    const screenChosen = screen.getAllDisplays().find((d) => Math.round(d.size.width * d.scaleFactor) === got.width && Math.round(d.size.height * d.scaleFactor) === got.height);
    await beginRecording(screenChosen ?? screen.getDisplayNearestPoint(screen.getCursorScreenPoint()), screenChosen ? null : got);
  } catch (e) {
    console.error("capture didn't start", e);
    setState("idle"); // Cancelling the system dialog lands here too.
  }
}

// The bar is wider while the drawing tools show, like the Mac's. Its window includes the hint line.
const BAR_WIDTH = 330;
const BAR_WIDTH_DRAWING = 430;
const BAR_HEIGHT = 86;

function placeBar(display: Display, area: Rect | null) {
  const width = BAR_WIDTH;
  const height = BAR_HEIGHT;
  const b = display.bounds;
  if (area) {
    // Outside the region when there's room, since Fedora can't hide the bar from the capture.
    const x = Math.round(Math.max(b.x, Math.min(area.x + (area.w - width) / 2, b.x + b.width - width)));
    const below = area.y + area.h + 12;
    const above = area.y - height - 12;
    if (below + height <= b.y + b.height - 50) return { x, y: below, width, height };
    if (above >= b.y) return { x, y: above, width, height };
  }
  return { x: b.x + Math.round((b.width - width) / 2), y: b.y + 12, width, height };
}

/** Resizes around the bar's center, wherever the user has dragged it. */
function resizeBar(width: number) {
  if (!bar) return;
  const b = bar.getBounds();
  bar.setBounds({ x: Math.round(b.x + (b.width - width) / 2), y: b.y, width, height: b.height });
}


const sleep = (ms: number) => new Promise((resolve) => setTimeout(resolve, ms));

/** Where on screen a region from the dialog is, by reading stripes the overlay paints. See core/locate.ts. */
async function locateRegion(display: Display, got: { width: number; height: number }): Promise<Rect | null> {
  const scale = display.scaleFactor;
  const screenW = Math.round(display.size.width * scale);
  const screenH = Math.round(display.size.height * scale);
  const inRecorder = (code: string) => recorder!.webContents.executeJavaScript(code, true);
  const inOverlay = (code: string) => overlay!.webContents.executeJavaScript(code, true);
  const read = (): Promise<Sample> => inRecorder(`readProbe(${SAMPLE_INSET})`);
  const began = Date.now();
  const steps = patternSteps(screenW, screenH);
  try {
    await inRecorder("startProbe()");
    await sleep(150);
    // More tries cover something on screen changing at the test pixels, while there's still time
    // to finish about when the countdown does.
    for (let attempt = 1; attempt === 1 || (attempt <= 3 && Date.now() - began < 1500); attempt++) {
      const before = await read();
      const samples: Sample[] = [];
      for (const step of steps) {
        const start: number = await inRecorder("probeFrames()");
        await inOverlay(`paintPattern(${JSON.stringify(step)})`);
        // Wait for frames from after the paint. Real captures showed the first two can still be old.
        const deadline = Date.now() + 250;
        while (Date.now() < deadline && (await inRecorder("probeFrames()")) < start + 3) await sleep(10);
        samples.push(await read());
      }
      await inOverlay("clearPattern()");
      await sleep(120);
      const after = await read();
      const at = locate(steps, before, samples, after, screenW, screenH);
      console.error("region measured", JSON.stringify({ at, got, attempt, ms: Date.now() - began, before: before.first, first: samples.map((s) => s.first[0]) }));
      if (at) return { x: display.bounds.x + at.x / scale, y: display.bounds.y + at.y / scale, w: got.width / scale, h: got.height / scale };
    }
    return null;
  } catch (e) {
    console.error("couldn't measure the region", e);
    return null;
  } finally {
    await inRecorder("stopProbe()").catch(() => undefined);
    await inOverlay("clearPattern()");
  }
}

/** `region` is the capture's size when the dialog gave a region rather than a whole screen. */
async function beginRecording(display: Display, region: { width: number; height: number } | null) {
  overlay = new BrowserWindow({ ...display.bounds, ...windowType(platform), transparent: true, frame: false, hasShadow: false, resizable: false, skipTaskbar: true, focusable: false, alwaysOnTop: true, show: false, webPreferences });
  overlay.setAlwaysOnTop(true, "screen-saver");
  overlay.setVisibleOnAllWorkspaces(true);
  overlay.setIgnoreMouseEvents(true);
  overlay.loadFile(ui("overlay"));
  await new Promise<void>((resolve) => overlay!.once("ready-to-show", () => resolve()));
  overlay.showInactive();
  overlay.setBounds(display.bounds);
  currentOrigin = { x: display.bounds.x, y: display.bounds.y };
  overlay.webContents.send("init", { origin: { x: display.bounds.x, y: display.bounds.y }, fades: settings.drawingsFade });
  // The only thing to notice is the countdown: a region is measured behind it, and recording starts
  // when both have finished.
  setState("countdown");
  const counted = new Promise<void>((resolve) => ipcMain.once("countdown-done", () => resolve()));
  overlay.webContents.send("countdown");
  const located = region ? await locateRegion(display, region) : null;
  if (located) overlay.webContents.send("region", located);

  recordingId = newRecordingId();
  rawDir = join(paths.recordings, recordingId, "raw");
  mkdirSync(rawDir, { recursive: true });
  const raw: RawSession = {
    mode: "area",
    display: rect(display.bounds),
    area: located ?? rect(display.bounds),
    regionFromDialog: region !== null,
    regionLocated: located !== null,
    createdAt: new Date().toISOString(),
  };
  writeJSON(join(rawDir, "session.json"), raw);
  appendFileSync(join(rawDir, "events.jsonl"), "");
  segment = 0;
  elapsedBefore = 0;

  bar = new BrowserWindow({ ...placeBar(display, located), ...windowType(platform), transparent: true, hasShadow: false, frame: false, resizable: false, skipTaskbar: true, alwaysOnTop: true, show: false, webPreferences });
  bar.setAlwaysOnTop(true, "screen-saver");
  bar.setVisibleOnAllWorkspaces(true);
  bar.loadFile(ui("bar"));
  bar.once("ready-to-show", () => bar?.showInactive());

  await counted;
  await startSegment();
}

// ---- Segments

async function startSegment() {
  segment += 1;
  const name = `seg_${String(segment).padStart(3, "0")}.webm`;
  segmentFile = createWriteStream(join(rawDir, name));
  await recorder!.webContents.executeJavaScript("startSegment()", true);
  segmentStart = Date.now();
  setState("recording");
  sendTimer();
}

async function endSegment() {
  if (segmentStart !== null) elapsedBefore += Date.now() - segmentStart;
  segmentStart = null;
  setDraw(false);
  await recorder!.webContents.executeJavaScript("stopSegment()", true);
  await new Promise<void>((resolve) => (segmentFile ? segmentFile.end(() => resolve()) : resolve()));
  segmentFile = undefined;
}

ipcMain.handle("segment-chunk", (_e, bytes: ArrayBuffer) => {
  segmentFile?.write(Buffer.from(bytes));
});

function sendTimer() {
  bar?.webContents.send("timer", { elapsedBefore, runningSince: segmentStart, paused: state === "paused" });
}

ipcMain.on("toggle-pause", async () => {
  if (state === "recording") {
    await endSegment();
    setState("paused");
    sendTimer();
  } else if (state === "paused") {
    await startSegment();
  }
});

ipcMain.on("stop", () => void stopRecording());

async function stopRecording() {
  if (state !== "recording" && state !== "paused") return;
  const wasRecording = state === "recording";
  setState("processing");
  if (wasRecording) await endSegment();
  await recorder!.webContents.executeJavaScript("stopCapture()", true);
  overlay?.destroy();
  bar?.destroy();
  overlay = bar = undefined;
  await runProcessing(recordingId);
}

async function runProcessing(id: string) {
  const review = openReview(id);
  try {
    await processRecording(id, paths, vpFrames);
    if (!review.isDestroyed()) review.webContents.send("review-ready", reviewData(id));
  } catch (e) {
    console.error("processing failed", e);
    if (!review.isDestroyed()) review.webContents.send("review-failed", String(e));
  }
  setState("idle");
  recordingsWindow?.webContents.send("recordings-changed");
}

// ---- Drawing

let drawOn = false;
let strokeActive = false;
let barHovered = false;
let handOver: NodeJS.Timeout | undefined;

// The overlay can end up above the bar, and stacking isn't ours to control on every system. So while
// Draw is on, let clicks through the overlay whenever the pointer is over the bar. This uses the
// windows' own pointer events: under XWayland the global cursor position goes stale once the pointer
// is over a native Wayland app.
ipcMain.on("bar-hover", (_e, hovered: boolean) => {
  barHovered = hovered;
  clearTimeout(handOver);
  if (drawOn && !strokeActive) overlay?.setIgnoreMouseEvents(hovered);
});

ipcMain.on("overlay-pointer", (_e, x: number, y: number) => {
  if (!drawOn || strokeActive || !bar || !overlay || !currentOrigin) return;
  const b = bar.getBounds();
  const gx = x + currentOrigin.x;
  const gy = y + currentOrigin.y;
  if (gx < b.x || gx >= b.x + b.width || gy < b.y || gy >= b.y + b.height) return;
  overlay.setIgnoreMouseEvents(true);
  // The bar should report the pointer now. If it left too fast for that, take drawing input back.
  clearTimeout(handOver);
  handOver = setTimeout(() => {
    if (drawOn && !barHovered) overlay?.setIgnoreMouseEvents(false);
  }, 200);
});

function setDraw(on: boolean) {
  if (on === drawOn) return;
  drawOn = on;
  strokeActive = false;
  clearTimeout(handOver);
  overlay?.setIgnoreMouseEvents(!on || barHovered);
  overlay?.webContents.send("draw-changed", on);
  bar?.webContents.send("draw-changed", on);
  resizeBar(on ? BAR_WIDTH_DRAWING : BAR_WIDTH);
  globalShortcut.unregister("Escape");
  if (on) globalShortcut.register("Escape", () => setDraw(false));
}

function logEvent(event: RawEvent) {
  appendFileSync(join(rawDir, "events.jsonl"), JSON.stringify(event) + "\n");
}

const secondsIn = (at: number) => Math.max(0, (at - segmentStart!) / 1000);

ipcMain.on("toggle-draw", () => {
  if (state === "recording") setDraw(!drawOn);
});
ipcMain.on("stroke-active", (_e, active: boolean) => {
  strokeActive = active;
});
ipcMain.on("set-tool", (_e, tool: StrokeTool) => overlay?.webContents.send("set-tool", tool));
ipcMain.on("stroke", (_e, s: { t0: number; t1: number; points: Point[]; tool: StrokeTool }) => {
  if (segmentStart === null) return;
  logEvent({ type: "stroke", seg: segment, t0: secondsIn(s.t0), t1: secondsIn(s.t1), points: s.points, tool: s.tool });
});
ipcMain.on("undo", () => {
  overlay?.webContents.send("undo");
  if (segmentStart !== null) logEvent({ type: "undo", seg: segment, t: secondsIn(Date.now()) });
});
ipcMain.on("clear", () => {
  overlay?.webContents.send("clear");
  if (segmentStart !== null) logEvent({ type: "clear", seg: segment, t: secondsIn(Date.now()) });
});

// ---- Review

function reviewData(id: string) {
  const dir = join(paths.recordings, id);
  const m = readJSON<Manifest>(join(dir, "manifest.json"));
  return {
    id,
    video: join(dir, "video.mp4"),
    duration: m.duration,
    transcript: m.transcript.map((s) => s.text).join(" "),
    transcription: m.transcription,
    note: m.note ?? "",
  };
}

function openReview(id: string) {
  const win = new BrowserWindow({ width: 720, height: 720, title: "Review recording", icon: windowIcon(), autoHideMenuBar: true, webPreferences });
  win.loadFile(ui("review"));
  let decided = false;
  const decide = (channel: string, edits?: { transcriptText: string; note: string }) => {
    decided = true;
    if (channel === "review-copy") clipboard.writeText(finalize(id, edits!, paths, vpFrames));
    win.destroy();
    recordingsWindow?.webContents.send("recordings-changed");
  };
  const copy = (e: Electron.IpcMainEvent, edits: { transcriptText: string; note: string }) => {
    if (e.sender === win.webContents) decide("review-copy", edits);
  };
  const discard = async (e: Electron.IpcMainEvent) => {
    if (e.sender !== win.webContents) return;
    decide("review-discard");
    await trashRecording(id);
  };
  ipcMain.on("review-copy", copy);
  ipcMain.on("review-discard", discard);
  win.on("closed", () => {
    ipcMain.off("review-copy", copy);
    ipcMain.off("review-discard", discard);
    // Closing without choosing keeps it, so the reference can still be copied from Recordings.
    if (!decided && readMeta(id)?.status === "reviewing") finalize(id, {}, paths, vpFrames);
    recordingsWindow?.webContents.send("recordings-changed");
  });
  return win;
}

// ---- Recordings and retention

function newRecordingId(): string {
  const d = new Date();
  const p = (n: number) => String(n).padStart(2, "0");
  const stamp = `${d.getFullYear()}${p(d.getMonth() + 1)}${p(d.getDate())}-${p(d.getHours())}${p(d.getMinutes())}${p(d.getSeconds())}`;
  let id = stamp;
  for (let n = 2; existsSync(join(paths.recordings, id)); n++) id = `${stamp}-${n}`;
  return id;
}

function readMeta(id: string): RecordingMeta | null {
  const file = join(paths.recordings, id, "meta.json");
  return existsSync(file) ? readJSON<RecordingMeta>(file) : null;
}

function listRecordings(): RecordingMeta[] {
  if (!existsSync(paths.recordings)) return [];
  return readdirSync(paths.recordings)
    .flatMap((id) => readMeta(id) ?? [])
    .sort((a, b) => b.createdAt.localeCompare(a.createdAt));
}

async function trashRecording(id: string) {
  await shell.trashItem(join(paths.recordings, id));
}

async function sweep() {
  const expired = expiredRecordings(listRecordings(), settings.retention, Date.now());
  // One that can't be trashed shouldn't block the rest.
  for (const m of expired) await trashRecording(m.id).catch((e) => console.error("couldn't trash", m.id, e));
}

function openRecordings() {
  if (recordingsWindow) return recordingsWindow.show();
  recordingsWindow = new BrowserWindow({ width: 1000, height: 520, minWidth: 900, minHeight: 360, title: "Recordings", icon: windowIcon(), autoHideMenuBar: true, webPreferences });
  recordingsWindow.loadFile(ui("recordings"));
  recordingsWindow.on("closed", () => (recordingsWindow = undefined));
}

ipcMain.handle("recordings-list", () => listRecordings().map((m) => ({ ...m, overview: join(paths.recordings, m.id, "overview.jpg") })));
ipcMain.on("recordings-review", (_e, id: string) => {
  const review = openReview(id);
  review.webContents.once("did-finish-load", () => review.webContents.send("review-ready", reviewData(id)));
});
ipcMain.handle("recordings-copy", (_e, id: string) => clipboard.writeText(join(paths.recordings, id, "timeline.md")));
ipcMain.handle("recordings-delete", async (_e, id: string) => {
  await trashRecording(id);
  recordingsWindow?.webContents.send("recordings-changed");
});
ipcMain.handle("recordings-retry", async (_e, id: string) => {
  if (state !== "idle") return;
  setState("processing");
  await runProcessing(id);
});

function openSettings() {
  if (settingsWindow) return settingsWindow.show();
  settingsWindow = new BrowserWindow({ width: 420, height: 120, title: "Settings", icon: windowIcon(), autoHideMenuBar: true, webPreferences });
  settingsWindow.loadFile(ui("settings"));
  settingsWindow.on("closed", () => (settingsWindow = undefined));
}

ipcMain.handle("settings-get", () => settings);
ipcMain.handle("settings-set", (_e, next: Settings) => {
  settings = next;
  writeJSON(settingsFile, settings);
  void sweep().then(() => recordingsWindow?.webContents.send("recordings-changed"));
});

// ---- Capture source and state

let recorderReady: Promise<void> = Promise.resolve();

function createRecorder() {
  const win = new BrowserWindow({ show: false, webPreferences: { ...webPreferences, backgroundThrottling: false } });
  recorderReady = win.loadFile(ui("recorder"));
  return win;
}

function setState(next: State) {
  state = next;
  refreshTray();
  tray?.setImage(trayIcon());
  bar?.webContents.send("state", next);
  // Alt+D is registered only while it applies, so it never takes the key from other apps.
  if (next === "recording" && !globalShortcut.isRegistered("Alt+D")) globalShortcut.register("Alt+D", () => setDraw(!drawOn));
  if (next !== "recording") globalShortcut.unregister("Alt+D");
}

// One copy at a time: opening the app again just opens its menu.
if (!app.requestSingleInstanceLock()) app.quit();
app.on("second-instance", () => toggleTrayMenu());

app.whenReady().then(() => {
  mkdirSync(paths.recordings, { recursive: true });
  if (!process.env.VIDEO_PROMPT_HOME && restrictsDataFolder(platform)) chmodSync(root, 0o700);
  settings = loadSettings();
  recoverInterrupted(paths);
  session.defaultSession.setDisplayMediaRequestHandler(async (_request, callback) => {
    // On Wayland this call is what opens the system's screen-share dialog.
    const sources = await desktopCapturer.getSources({ types: ["screen"] });
    if (sources[0]) callback({ video: sources[0] });
    else callback({});
  });
  tray = new Tray(trayIcon());
  tray.setToolTip("Video Prompt");
  tray.on("click", toggleTrayMenu);
  refreshTray();
  const ok = globalShortcut.register("Ctrl+Alt+Shift+R", () => void startFlow());
  if (!ok) console.error("Ctrl+Alt+Shift+R is taken; the tray menu still starts a recording");
  void sweep();
  setInterval(() => void sweep(), 3600_000);
});

app.on("window-all-closed", () => {
  // Stay in the tray.
});
app.on("will-quit", () => globalShortcut.unregisterAll());
