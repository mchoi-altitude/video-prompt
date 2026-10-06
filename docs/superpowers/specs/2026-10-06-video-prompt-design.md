# Video Prompt v1: design

Status: **revised 2026-10-06 (video-first)** · supersedes the open questions in
[`docs/user-journey.md`](../../user-journey.md)

> **Revision, 2026-10-06: video-first.** Hands-on testing showed "key moments" keyframes miss
> things that matter (a sign-in page and a course page shown for ~1 s each, strokes drawn right
> after a frame). Claude, given a video file and tools, finds even a 0.4 s flash (tested). So a
> recording is now **a window-cropped video at 10 fps with narration**, a timestamped timeline,
> and a one-image overview; Claude pulls frames from the video itself (`get_frames` /
> `vp-frames`). Keyframe selection and frame removal are gone. Sections below are updated.

Clickable prototype of everything below (flow + first-run setup):
https://claude.ai/artifact/4n5ZJ7ogjbBTDF1JrHGZbV

## 1. What and why

A developer working with Claude Code wants to **show** rather than type: "this button, this
spacing, this flow is broken; here's what I want instead." Typing loses the visual context.
Screenshots lose the sequence and the explanation.

Video Prompt is a macOS menu-bar app. You record your Chrome window (or the screen, or an
area), talk, and draw on it with the mouse. On Stop, the recording becomes a video of just
that window (10 fps, with your narration, drawings and click rings), a timestamped timeline of
what you said, drew and clicked, and an overview image. Claude Code gets all three and pulls
frames from the video wherever it needs to look closer.

**Success looks like**

- Under **10 seconds of overhead** between "I want to show Claude this" and Claude having it.
- In most cases Claude's first reply names the right UI element, with no follow-up question.

**Audience:** public, open source. Published from `mchoi-altitude/video-prompt` for now (2FA on). It may
move to an AltitudeIQ GitHub organization later (see §9 for what must be stable from day one).

## 2. Decisions

| # | Topic | Decision |
|---|---|---|
| 1 | Hand-off | **A** (pull: "look at my recording") + **B** (Claude asks and waits) + **clipboard**. No push into an "active" session. |
| 2 | Main button on review | B, when a session is waiting: **"Send to waiting session"**. A, when none is waiting: **"Save & copy reference"** (saves it as the latest recording *and* puts `@"…/timeline.md"` on the clipboard). |
| 3 | Default capture mode | **Record Chrome window.** It's the first menu item and shows the window's tab title. Also offered: whole screen, selected area, another window. |
| 4 | Window resize/move mid-recording | Record the display and log the target window's frame over time, then **render a window-only video that follows it** (§5). The video keeps the largest size the window reached; smaller moments are padded. |
| 5 | Shortcut | **⌃⌥⌘R** starts a recording in the last-used mode (Chrome window by default). |
| 6 | Control bar | Floating ● timer / ❚❚ / ✎ / ■, **hidden from the capture**. Drawings *are* captured. |
| 7 | Countdown | 3-2-1 before recording starts. |
| 8 | Drawing | **Pen, arrow, box**, red only, plus undo and clear. While Draw is on, clicks don't reach apps. Marks **fade after 3 s** by default (setting: keep until Stop). |
| 9 | Time limit | Soft warning at **3:00** ("long recordings give Claude many frames"). No hard stop. |
| 10 | Review step | **On** by default, with the main button focused so **Return sends**. A video preview, the transcript (fixable) and a typed note. **No trimming or frame removal**: Discard and re-record instead. Setting: skip review. |
| 11 | Retention | Auto-delete after **3 days** (setting: 1 / 3 / 7 / 30 days, keep the last 20, never). |
| 12 | Manual delete | **Recordings…** window: trash per row, checkboxes, "Select all sent", bulk delete. Deleted recordings go to the **macOS Trash** (no confirm dialog). |
| 13 | Video | The **window-only video is kept** with the recording and expires with it (§2 #11). The full-display capture (`raw/`) is deleted once the window video exists. 10 fps, full resolution: roughly 3–8 MB per minute. |
| 14 | Recording titles | Taken automatically from the first narration sentence. |
| 15 | First run | Setup window: Screen Recording → Microphone → Connect Claude Code → optional 5-second test (§3.0). |
| 16 | Sharing with teammates | Not in v1. |
| 17 | Privacy controls | No blur or app exclusion in v1. Chrome-window mode (the kept video is cropped to that window), the review preview, and Discard cover it. |
| 18 | Telemetry | **None.** The app makes no network calls except checking for updates (§8). |
| 19 | Frame rate | **10 fps** capture and video (one constant). UI states of ≥ 150 ms land in 1–2 frames; a 0.4 s flash was found in testing. |
| 20 | Clicks | Logged (global mouse monitor, no extra permission) and drawn as a short **ring in the video**; listed in the timeline. |
| 21 | What Claude gets | `timeline.md` (narration, drawings, clicks, hidden-window and pause marks, with times) + `overview.jpg` (a thumbnail per second) + the video path; frames on demand via `get_frames` (plugin) or the bundled `vp-frames` CLI (paste path). No keyframe selection. |

## 3. User journey

### 3.0 One-time setup

Install: `.dmg` download or `brew install --cask video-prompt`. On first launch a
setup window appears. The steps unlock in order, so only one button is live at a time.

1. **Screen Recording.** "Open System Settings" deep-links to Privacy & Security → Screen &
   System Audio Recording. When the user flips the switch, macOS asks the app to quit; **Quit &
   Reopen** relaunches it and setup resumes with progress kept. "Later" leaves the step amber
   with a Quit & Reopen button.
   *Why setup exists at all:* this restart must not happen during the user's first real
   recording.
2. **Microphone.** The system prompt appears. **Don't Allow is not a dead end:** recordings
   work without narration (typed notes only), the step stays amber, and a "Turn on" button
   appears.
3. **Connect Claude Code.** "Copy install commands" copies:
   ```
   /plugin marketplace add mchoi-altitude/video-prompt
   /plugin install video-prompt@video-prompt
   ```
   The step turns green when the plugin is detected (§6.3). **Skip** is allowed: everything
   then works through Copy reference.
4. **Test recording (optional).** Five seconds, then: "Heard: '…' · 3 frames ready."

Footer: the shortcut reminder and "Open at login" (on by default). **Done** is enabled once
steps 1–3 are resolved (done or knowingly skipped or denied). Afterwards, a card points at the
menu-bar icon: "Video Prompt lives up here."

### 3.1 Start

Menu-bar icon (an **amber dot** means a Claude session is waiting) or ⌃⌥⌘R:

```
● Claude is waiting for a recording        (only when one is)
✓ Record Chrome window        ⌃⌥⌘R
    <tab title · host>
  Record whole screen
  Record selected area…
  Record another window…
─────────────
  Recordings…                     <count>
  Settings…
```

3-2-1 countdown, then recording. In Chrome-window mode a red outline hugs the window and
follows it if it moves or resizes.

### 3.2 Show and tell

- Narrate while using the screen normally. The cursor is logged throughout.
- ✎ Draw toggles a full-screen drawing layer (pen / arrow / box). Clicks don't reach apps
  while it's on.
- ❚❚ Pause: nothing is recorded. Each pause ends a segment and resume starts a new one.

### 3.3 Stop and review

■ Stop → "Transcribing on this Mac…" (a few seconds) → review panel:

- A video preview (plays the window video).
- Editable transcript.
- An optional typed note.
- A destination line: "Goes to: claude — ~/project (waiting for this)" or "No session is
  waiting. It's saved as your latest recording."
- Buttons: **Discard** · **Copy reference** · **Send to waiting session ⏎** / **Save & copy
  reference ⏎**.

With review turned off, Stop goes straight to the main action.

### 3.4 Hand-off

| Path | What happens |
|---|---|
| **B: Claude asked** | Claude called `wait_for_next_recording`. Send saves the recording, and that call returns it inline. |
| **A: you ask** | Save & copy. Later, in any session, "look at my recording" → Claude calls `get_latest_recording`. |
| **Clipboard** | Paste `@"~/Library/Application Support/VideoPrompt/recordings/<id>/timeline.md"` into any session. Works without the plugin (Claude uses the bundled `vp-frames` command named in the timeline). |

Copy reference while a session is waiting is allowed. Claude stays waiting, so the user presses
Esc in the terminal and pastes.

### 3.5 Claude acts

Claude receives `timeline.md`: the narration with timestamps, interleaved with drawing notes
("circled (40,470)–(150,510)"), clicks ("clicked (812,96)"), and marks for pauses and a hidden
window; plus `overview.jpg` and the video's path. It looks closer with `get_frames(from, to,
fps)` or `vp-frames`, refers to moments by timestamp, and is told to ask before large changes
when the narration is ambiguous.

### 3.6 Afterwards

Recordings… window (§2 #11–13). Each row shows the title, time, length, status ("Sent to
claude — ~/acme-console" / "Saved · not fetched yet" / "Not sent"), size, "Auto-deletes in N
days", Copy reference and a trash button.

## 4. Architecture

```
┌──────────────────── VideoPrompt.app (Swift, macOS 15+) ───────────────────────┐
│ MenuBar ─ ControlBar ─ DrawingOverlay ─ ReviewPanel ─ RecordingsWindow ─ Setup │
│        │                                                                       │
│ CaptureSession (ScreenCaptureKit: display video + mic)                         │
│ EventLog (cursor, strokes, target-window frames, pauses; one clock)            │
│ Processor (segments → transcript → window video → overview → timeline.md)      │
│ Store (recordings folder, retention sweeper, Trash)                            │
└───────────────────────────────┬────────────────────────────────────────────────┘
                                │ files only (no sockets, no ports)
              ~/Library/Application Support/VideoPrompt/
                 recordings/<id>/{video.mp4, timeline.md, overview.jpg, manifest.json}
                 waiters/<pid>.json          ← written by the MCP server
                                │
┌───────────────────────────────┴───────────────────┐
│ video-prompt-mcp (stdio MCP server, bundled CLI)   │ ← launched by Claude Code
│ get_latest_recording · list_recordings ·           │   through the plugin
│ wait_for_next_recording                            │
└────────────────────────────────────────────────────┘
```

**macOS 15+** (raised from 14 while planning the app): `SCRecordingOutput` and
`SCStreamConfiguration.captureMicrophone` are 15+, and they make each pause-separated segment one
ScreenCaptureKit call with the narration already in the file.

Each unit has one job and one interface:

- **CaptureSession**: start/pause/resume/stop → segment files + audio. Knows nothing about
  drawing.
- **EventLog**: an append-only timeline of `{t, kind, data}` per segment. Pause handling maps
  segment-local times to recording time using the actual segment durations (as in the
  prototype).
- **Processor**: a pure function from (segments, events, mode) to a recording folder. It can be
  tested without any UI.
- **Store**: owns the folder layout, atomic writes, retention, and moving to the Trash.
- **MCP server**: reads the Store's folder. It never talks to the app directly.

## 5. Capture and the recording video

- **Always capture the display** containing the target, excluding only our control bar. The
  drawing overlay *is* included, so marks appear in the frames for free.
- **10 fps** capture (`minimumFrameInterval` 1/10), microphone in the same file.
- **Chrome-window / other-window mode:** poll the target window's frame (about 10 Hz) into the
  EventLog. Processing renders `video.mp4`: every captured frame is cropped to where the window
  was at that moment (clipped to the display) and placed top-left on a fixed canvas the size of
  the largest crop; the rest is padded. A hidden window gives a dark frame. Narration audio is
  carried over. If another window covers Chrome, the video shows what the user actually saw.
- **Area mode:** a fixed crop. **Whole-screen mode:** no crop.
- **Click rings:** each logged click is drawn into the video as a ring that grows and fades over
  0.5 s. Coordinates in the timeline are **video pixels**.
- **Overview:** `overview.jpg`, one thumbnail per second (one per N seconds past 60 s, at most 60
  tiles), each labelled with its time.
- **Narration:** split into sentences using word timestamps. **Drawing notes:** the shape
  heuristic turns strokes into text ("circled the area …").
- **Long edge:** video and frames at full window resolution; `get_frames` scales its output to a
  1568 px long edge (Claude's image size).

**Transcription engine:** on-device only. Apple Speech (`SFSpeechRecognizer` with
`requiresOnDeviceRecognition`) vs whisper.cpp. Choose during planning by accuracy on technical
vocabulary; a whisper.cpp model would be downloaded with a pinned checksum.

## 6. Claude Code plugin

### 6.1 Packaging

A Claude Code plugin in this repo (marketplace `video-prompt`, plugin `video-prompt`). Its MCP
server is a **small native CLI inside the app bundle**, so users need no Python or Node. The
plugin config points at the app's bundled binary (`${VIDEO_PROMPT_MCP:-/Applications/Video
Prompt.app/Contents/MacOS/vp-mcp}`). If the app isn't installed, the server can't start: Claude
Code shows the plugin's MCP server as failed, and the README explains why.

### 6.2 Tools

| Tool | Returns |
|---|---|
| `get_latest_recording()` | The newest recording's `timeline.md` text, `overview.jpg` inline, and the video path. |
| `list_recordings(limit?)` | id, title, time, length, status. |
| `get_recording(id)` | Like latest, for a specific recording. |
| `wait_for_next_recording(timeout_s?)` | Registers a waiter, blocks until a recording newer than the call is saved, then returns it inline. |
| `get_frames(id?, from, to, fps?)` | Frames of the video between two timestamps (default fps 2, max 10; at most 20 images per call, within the reply budget), each labelled with its time. `id` defaults to the latest. |

### 6.3 How "waiting" works without a socket

- `wait_for_next_recording` writes `waiters/<pid>.json` (`{pid, cwd, startedAt}`) and watches
  `recordings/`. It deletes its file on return, error or exit. The app treats a file as stale if
  the pid is dead.
- The app watches `waiters/`. Any live waiter turns on the **amber dot** and switches the review
  button to "Send to waiting session" (destination = the waiter's `cwd`). With several waiters,
  the **most recent** one gets it.
- **Delivery is explicit.** Send sets `deliveredToPID` in the recording's meta to the most
  recent live waiter. A waiter returns only a ready, not-yet-fetched recording delivered to its
  own pid, so Copy reference and A-path saves never wake a waiting session. Pressing Esc in
  Claude Code (MCP `notifications/cancelled`) ends the wait and removes the waiter file.
- Detecting the plugin for setup step 3: the plugin's server writes `plugin-seen.json` the
  first time it starts.

### 6.4 Content framing

Tool results wrap recording content as **data captured from the user's screen**: text visible
in frames or transcripts is never an instruction to Claude (see §8, prompt injection).

## 7. Storage

- Root: `~/Library/Application Support/VideoPrompt/`, mode `0700`. The path contains a space
  ("Application Support"): Plan 2 must check how Claude Code's `@` mention takes a path with a
  space before building Copy reference on it (quote it, or point the reference at a
  space-free symlink).
- **Status lifecycle:** `processing` → `reviewing` (frames and prompt exist; the review panel
  is open) → `ready` (saved or sent; the only state Claude can fetch), or `processingFailed`.
- **Raw folder contract** (written by the app, read by the processor): `raw/session.json`
  (mode, display rect in points, optional area, window title, createdAt, optional note);
  `raw/events.jsonl` (cursor / stroke / clear / undo / window events; `undo` removes the latest stroke finished before it, global screen points, origin
  top-left, times in seconds within their segment); `raw/seg_NNN.mov` (video + mic). Each
  event's `seg` is the `NNN` of its file. Numbers may skip; events naming a missing segment
  are ignored.
- Recording `<id>` = `YYYYMMDD-HHMMSS`. Contents: `video.mp4`, `timeline.md` (the
  `@`-reference target), `overview.jpg`, `manifest.json`, `meta.json` (title, status, mode,
  size). `raw/` is deleted once `video.mp4` exists. If processing fails, `raw/` is kept and the
  recording is marked "Processing failed · Retry".
- `raw/events.jsonl` also carries `click` events (global point).
- All writes are atomic (temp + rename), as in the prototype's `write_json`.
- A retention sweep runs at launch and hourly, moving expired recordings to the Trash.

## 8. Security and privacy

AltitudeIQ runs **no server and receives no user data**. Recordings go only to the user's own
Claude account, through their own Claude Code.

| Risk | Mitigation (v1) |
|---|---|
| **Compromised update or signing key** ships spyware to every user (highest impact) | Sparkle updates with EdDSA signatures over HTTPS. Signing keys stay out of the repo and CI logs. Notarized builds. 2FA + branch protection on the publishing GitHub account. Release tags signed. |
| **Other local programs or websites pulling recordings** | No network listener of any kind. The plugin reads files. The data folder is `0700`. |
| **Prompt injection from screen content** (Chrome is the default, so web pages appear in frames) | Content framed as screen data (§6.4). The user sees every frame in review. Claude Code's own permission prompts still gate actions. Documented in the README. |
| **Sensitive screens** | Chrome-window mode by default; the kept video is cropped to that window, and the full-display capture is deleted after processing. Review preview + Discard. Audio is transcribed on-device. 3-day retention. |
| **Downloaded model tampering** (if whisper.cpp) | Pinned SHA-256 checksum. |
| **Brand and legal** | Named "Video Prompt *for Claude Code*", with no implied Anthropic endorsement. OSS license (MIT proposed). A short privacy statement in the README and on the site. |

## 9. Distribution and identity

**Stable from day one** (changing these later is expensive):

- **Bundle ID** `ai.altitudeiq.videoprompt`. macOS ties Screen Recording and Microphone
  permissions to it.
- **Apple Developer account owned by AltitudeIQ.** The signing team is also part of those
  permission grants, so changing it later forces every user to re-grant.
- **Update-feed URL** `https://altitudeiq.ai/video-prompt/appcast.xml` (proposed). It's baked
  into every installed copy.

**Can move later:** the GitHub repo (`mchoi-altitude/video-prompt` → an org; GitHub redirects),
the plugin install command (README), and the Homebrew cask.

## 10. Out of scope for v1 (later list)

- **Chrome extension** that maps a drawing to the DOM element ("you circled `button.save`").
- Sharing recordings to PRs, issues or teammates.
- Auto-blur (for example password fields) and "never capture these apps."
- Highlighter, colors, text labels.
- Push into an "active" session (option C).
- Linux (see the notes in `CLAUDE.md`).

## 11. To verify early in the build

1. ScreenCaptureKit with a display filter that excludes only the control bar, while including
   our drawing overlay: confirm per macOS version.
2. Window-frame polling for Chrome while it's moved, resized, full-screened or minimized:
   define what a frame shows when the window is minimized (proposal: skip frames; note "window
   hidden" in the timeline).
3. ~~How long Claude Code lets an MCP tool call block~~ **Measured 2026-10-06 (Claude Code
   2.1.291):** a `wait_for_next_recording` call blocked for the full 900 s without being cut
   off. The default stays 300 s, returning "still waiting, call again".
   **Also measured:** Claude Code truncates a tool reply over `MAX_MCP_OUTPUT_TOKENS` (25,000
   by default). 24 full-size frames got cut off after 15. The server now budgets images to 80%
   of that limit: it shrinks frames (long edge never below 1024 px), then attaches an evenly
   spread subset (always the first and last frame) and lists the rest as paths for Read.
   Verified: 24 frames → 22 attached, last frame legible, 2 listed.
4. Transcription engine accuracy on developer speech (§5).

## 12. Testing

- **Processor:** golden tests from recorded fixtures (segments + event logs → expected
  window-video size and crops over time, click rings, window-relative coordinates, `timeline.md`). This includes a fixture with
  a mid-recording resize and one with a pause.
- **Store:** retention sweep, Trash moves, atomic writes, stale waiter cleanup.
- **MCP server:** tool contract tests against a fixture folder, including two concurrent
  waiters.
- **Manual checklist per release:** first-run on a clean macOS user (permissions, Quit &
  Reopen, mic denied, plugin skipped), and both hand-off paths end to end.
