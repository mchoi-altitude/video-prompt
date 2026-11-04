type Tool = "pen" | "arrow" | "box";
type Meta = { id: string; title: string; createdAt: string; duration: number; status: string; sizeBytes: number; overview: string /* file:// URL */; error?: string };
type Prefs = { retention: { days: number } | { keepLast: number } | "never"; drawingsFade: boolean };
type ReviewData = { id: string; video: string /* file:// URL */; duration: number; transcript: string; transcription: string; note: string };

declare const vp: {
  trayMenuInfo(): Promise<{ busy: boolean; canStop: boolean; count: number; twoModes: boolean; lastMode: "screen" | "area" }>;
  trayMenuAction(action: string): void;
  trayMenuClose(): void;

  pickerDone(area: { x: number; y: number; w: number; h: number } | null): void;

  countdownDone(): void;
  onInit(fn: (o: { origin: { x: number; y: number }; fades: boolean }) => void): void;
  onRegion(fn: (r: { x: number; y: number; w: number; h: number }) => void): void;
  onCountdown(fn: () => void): void;
  onDrawChanged(fn: (on: boolean) => void): void;
  onSetTool(fn: (tool: Tool) => void): void;
  onUndo(fn: () => void): void;
  onClear(fn: () => void): void;
  strokeActive(active: boolean): void;
  overlayPointer(x: number, y: number): void;
  barHover(hovered: boolean): void;
  stroke(s: { t0: number; t1: number; points: { x: number; y: number }[]; tool: Tool }): void;

  toggleDraw(): void;
  togglePause(): void;
  stop(): void;
  setTool(tool: Tool): void;
  undo(): void;
  clear(): void;
  onTimer(fn: (t: { elapsedBefore: number; runningSince: number | null; paused: boolean }) => void): void;
  onState(fn: (state: string) => void): void;

  segmentChunk(bytes: ArrayBuffer): Promise<void>;

  onReviewReady(fn: (d: ReviewData) => void): void;
  onReviewFailed(fn: (error: string) => void): void;
  reviewCopy(edits: { transcriptText: string; note: string }): void;
  reviewDiscard(): void;

  recordingsList(): Promise<Meta[]>;
  recordingsCopy(id: string): Promise<void>;
  recordingsDelete(id: string): Promise<void>;
  recordingsRetry(id: string): Promise<void>;
  recordingsReview(id: string): void;
  onRecordingsChanged(fn: () => void): void;

  settingsGet(): Promise<Prefs>;
  settingsSet(s: Prefs): Promise<void>;
};
