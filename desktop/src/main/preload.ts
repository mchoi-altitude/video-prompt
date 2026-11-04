import { contextBridge, ipcRenderer } from "electron";

const on = (channel: string) => (fn: (...args: any[]) => void) => ipcRenderer.on(channel, (_e, ...args) => fn(...args));

contextBridge.exposeInMainWorld("vp", {
  isWindows: process.platform === "win32",
  pickerDone: (drag: object) => ipcRenderer.send("picker-done", drag),
  pickerCancel: () => ipcRenderer.send("picker-cancel"),
  reviewCopyWsl: (edits: object) => ipcRenderer.send("review-copy-wsl", edits),
  recordingsCopyWsl: (id: string) => ipcRenderer.invoke("recordings-copy-wsl", id),
  trayMenuInfo: () => ipcRenderer.invoke("tray-menu-info"),
  trayMenuAction: (action: string) => ipcRenderer.send("tray-menu-action", action),
  trayMenuClose: () => ipcRenderer.send("tray-menu-close"),

  countdownDone: () => ipcRenderer.send("countdown-done"),
  onInit: on("init"),
  onRegion: on("region"),
  onCountdown: on("countdown"),
  onDrawChanged: on("draw-changed"),
  onSetTool: on("set-tool"),
  onUndo: on("undo"),
  onClear: on("clear"),
  strokeActive: (active: boolean) => ipcRenderer.send("stroke-active", active),
  overlayPointer: (x: number, y: number) => ipcRenderer.send("overlay-pointer", x, y),
  barHover: (hovered: boolean) => ipcRenderer.send("bar-hover", hovered),
  stroke: (s: object) => ipcRenderer.send("stroke", s),

  toggleDraw: () => ipcRenderer.send("toggle-draw"),
  togglePause: () => ipcRenderer.send("toggle-pause"),
  stop: () => ipcRenderer.send("stop"),
  setTool: (tool: string) => ipcRenderer.send("set-tool", tool),
  undo: () => ipcRenderer.send("undo"),
  clear: () => ipcRenderer.send("clear"),
  onTimer: on("timer"),
  onState: on("state"),

  segmentChunk: (bytes: ArrayBuffer) => ipcRenderer.invoke("segment-chunk", bytes),

  onReviewReady: on("review-ready"),
  onReviewFailed: on("review-failed"),
  reviewCopy: (edits: object) => ipcRenderer.send("review-copy", edits),
  reviewDiscard: () => ipcRenderer.send("review-discard"),

  recordingsList: () => ipcRenderer.invoke("recordings-list"),
  recordingsCopy: (id: string) => ipcRenderer.invoke("recordings-copy", id),
  recordingsDelete: (id: string) => ipcRenderer.invoke("recordings-delete", id),
  recordingsRetry: (id: string) => ipcRenderer.invoke("recordings-retry", id),
  recordingsReview: (id: string) => ipcRenderer.send("recordings-review", id),
  onRecordingsChanged: on("recordings-changed"),

  settingsGet: () => ipcRenderer.invoke("settings-get"),
  settingsSet: (s: object) => ipcRenderer.invoke("settings-set", s),
});
