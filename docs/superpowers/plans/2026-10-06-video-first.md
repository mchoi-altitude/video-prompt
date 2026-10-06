# Video-First Recording Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace keyframe selection with a window-cropped 10 fps video (narration, drawings,
click rings), a timestamped `timeline.md`, and an `overview.jpg`. Claude pulls frames with
`get_frames` (plugin) or `vp-frames` (bundled CLI).

**Architecture:** Three new VPMedia pieces: render the window video, make the overview, extract
frames. The Processor is rewired to them, and keyframe choice and scene detection go away.
VPMCP gains `get_frames`. A new `vp-frames` executable. The app captures at 10 fps, logs
clicks, and the review panel previews the video.

**Tech Stack:** as Plans 1–2 (Swift 6.3, AVFoundation, CoreGraphics/CoreText, AVKit for the preview).

**Spec:** `docs/superpowers/specs/2026-10-06-video-prompt-design.md`, revision "video-first" (§1, §2 #4/#10/#13/#17/#19–21, §3.3–3.5, §5, §6.2, §7).

## Global Constraints

- `VideoFPS = 10` in one place (VPCore), used by capture, render and defaults.
- Video: H.264 (HEVC when the canvas is larger than 4096×2304), `.mp4`, AAC narration when present.
- Canvas = the largest clipped crop over the recording, in video pixels, rounded to even.
  Content is placed top-left; the rest is padded `#111111`. Hidden window → a fully padded frame.
- Click ring: red `#E5484D`, 3 px line, radius from 6 px to 28 px and alpha from 1 to 0 over 0.5 s,
  centred on the click in video pixels.
- Timeline coordinates are video pixels (top-left of the canvas).
- `get_frames`: fps default 2, max 10; at most 20 images per call; output long edge ≤ 1568;
  stays within the existing image-token budget (`Tools.attachmentPlan`).
- `timeline.md` keeps the screen-data framing preamble (spec §6.4) and names both ways to look
  closer (`get_frames` and the `vp-frames` command with the absolute path of the app's binary).
- Clicks are logged with an `NSEvent` global monitor for left-mouse-down (no permission needed).

## Review Focus

1. **A window that moves to another display mid-recording.** Its crop clips to the recorded display, so the frames are partly padded rather than wrong (`renderClipsToDisplay`).
2. **Pause/resume.** The video is continuous across segments, and the timeline marks each pause point (`timelineMarksPauses`).
3. **No audio track** (mic denied). The video still renders, without audio (`renderWithoutAudio`).
4. **`get_frames` with a range past the end, or from > to.** It clamps to [0, duration] and returns at least one frame (`getFramesClampsRange`).
5. **A very long recording (10 min).** The overview stays ≤ 60 tiles (`overviewCapsTiles`).

### Task 1: Window video renderer (VPMedia)
`renderWindowVideo(asset:display:canvas:crop:clicks:to:) async throws -> (w, h, duration)`, where `crop: (Double) -> Rect?` gives screen points per time, and `clicks: [ClickMark(t, x, y)]` are in video pixels.
Tests (fixture videos): `renderCropsToWindowAndFollowsResize` (pixel colors inside and outside the crop before and after the change; canvas = the largest crop); `renderClipsToDisplay`; `hiddenWindowRendersPadding`; `clickRingDrawnAtClick` (a red pixel on the ring at t+0.2 s, none at t+0.8 s); `renderCarriesAudio`; `renderWithoutAudio`.

### Task 2: Overview + frame extraction (VPMedia)
`makeOverview(video:to:maxTiles:tileWidth:) throws -> (tiles, w, h)` (time labels drawn with CoreText); `extractFrames(video:from:to:fps:maxLongEdge:) async throws -> [Frame(t, jpeg, w, h)]` (clamped range, ≥ 1 frame).
Tests: `overviewOneTilePerSecond`; `overviewCapsTiles`; `extractFramesCountAndOrder`; `getFramesClampsRange` (on the extractor).

### Task 3: Models, Processor, timeline (VPCore/VPProcess)
`RawEvent.click(seg,t,p)`; `Manifest` gets `video {file, width, height, fps}`, `clicks`, `pauses`, and drops `frames`; strokes keep `bbox` + `description` in video pixels. The Processor does: join → sentences → crop timeline → canvas → `video.mp4` → `overview.jpg` → manifest → `timeline.md` → remove `raw/` (unless keepRaw) → `reviewing`. `renderTimeline(m, recordingDir:, vpFramesPath:)` (golden file). Finalize edits only the transcript and the note.
Tests: update the processor and finalize tests; `timelineMatchesGolden`; `timelineMarksPauses`; `clicksAppearInTimeline`.

### Task 4: MCP + vp-frames
`get_latest_recording`/`get_recording`/`wait_for_next_recording` return the timeline text + overview image. New `get_frames {id?, from, to, fps?}`. The `vp-frames <video> --from S --to E [--fps N] [--out DIR]` CLI prints the written JPEG paths. build-app.sh bundles it.
Tests: `latestReturnsTimelineAndOverview`; `getFramesReturnsLabelledImages`; `getFramesDefaultsToLatest`; `getFramesRespectsBudget`.

### Task 5: App
10 fps capture; click monitor → `RawRecorder.log(.click)`; the review panel shows an `AVPlayerView` of `video.mp4` (no frame grid); ReviewModel/edits lose `removed`; the reference points at `timeline.md`; Recordings thumbnails come from `overview.jpg`.
Tests: `referencePointsAtTimeline`; `clickIsLogged` (RawRecorder); ReviewModel tests updated.

### Task 6: Proof
Rebuild, run the three scenario pages through the app (automation URLs), then ask Claude Code each scenario's question from `timeline.md` alone, scoring its answers. Report the table, and the frames it pulled, to the user.
