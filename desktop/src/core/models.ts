// Port of Sources/VPCore/Models.swift, minus the window mode and delivery fields this app doesn't use.

export const VIDEO_FPS = 10;
export const VIDEO_MAX_HEIGHT = 1080;

export type Rect = { x: number; y: number; w: number; h: number };
export type Point = { x: number; y: number };
export type StrokeTool = "pen" | "arrow" | "box";

/** `raw/session.json`. */
export type RawSession = {
  mode: "area";
  display: Rect;
  area: Rect;
  /** The stream is a region chosen in the system's dialog, so it's never cropped. */
  regionFromDialog?: boolean;
  /** `area` is where that region was measured to be. Without this, marks can't be placed in it. */
  regionLocated?: boolean;
  createdAt: string;
};

/** One line of `raw/events.jsonl`. Times are seconds into segment `seg`; points are global, origin top-left. */
export type RawEvent =
  | { type: "stroke"; seg: number; t0: number; t1: number; points: Point[]; tool: StrokeTool }
  | { type: "clear"; seg: number; t: number }
  | { type: "undo"; seg: number; t: number }
  | { type: "click"; seg: number; t: number; p: Point };

export type Sentence = { start: number; end: number; text: string };
export type Word = Sentence;

export type ManifestStroke = { start: number; end: number; tool: StrokeTool; bbox: number[]; description: string };
export type ManifestClick = { t: number; x: number; y: number };
export type TranscriptionState = "ok" | "noSpeech" | "noAudio" | "unavailable";

export type TimelineItem =
  | { kind: "speech"; time: number; end: number; text: string }
  | { kind: "drawing"; time: number; description: string }
  | { kind: "clear"; time: number }
  | { kind: "click"; time: number; x: number; y: number }
  | { kind: "pause"; time: number };

export type Manifest = {
  id: string;
  duration: number;
  mode: "area";
  transcript: Sentence[];
  transcription: TranscriptionState;
  video: { file: string; width: number; height: number; fps: number; hasAudio: boolean };
  overview: string;
  overviewSecondsPerTile: number;
  strokes: ManifestStroke[];
  clicks: ManifestClick[];
  /** False where the platform can't log clicks, so the timeline doesn't imply it would show them. */
  clicksLogged: boolean;
  timeline: TimelineItem[];
  note?: string;
};

export type RecordingStatus = "processing" | "reviewing" | "ready" | "processingFailed";

/** `meta.json`, written last: a folder without it doesn't exist yet for readers. */
export type RecordingMeta = {
  id: string;
  title: string;
  createdAt: string;
  duration: number;
  mode: "area";
  status: RecordingStatus;
  sizeBytes: number;
  error?: string;
};
