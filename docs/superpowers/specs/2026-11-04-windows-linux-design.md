# Video Prompt for Windows and Fedora: design

Status: **draft for review, 2026-11-04**. Builds on the
[Mac design](2026-10-06-video-prompt-design.md), which stays the source of truth for the Mac app.
Where this doc says "same as Mac", that spec and the code it names define the behavior.

Labels: **[Decided]** means Michael chose it. **[Proposed]** means the author's call, open to
correction. Unlabeled detail follows from those.

## Updates after building the Fedora app

The Fedora app in `desktop/` was built and tested on one machine (Fedora 44, Plasma 6.8, one monitor at
100%). These override the sections below where they differ. Windows hasn't been started, so the
Windows parts below are still the plan.

- **One Record option, no area picker (§2, §4).** KDE's dialog already offers full screen or a region,
  so an extra picker felt like being asked twice. The tray menu is Record…, Recordings…, Settings…
  and Quit Video Prompt, plus Stop recording while recording. Left click opens the same items in a small window.
- **The dialog appears on every recording (§4, §9).** The user wants to choose each time, so there's
  no restore token and no "Change monitor…". Electron doesn't say which monitor was chosen, so with
  several monitors the overlay can open on the wrong one.
- **Finding a region (§7).** Electron doesn't report where a region is, and the app needs that for
  the outline, mark coordinates and bar placement. During the countdown, the overlay paints a position
  code at about 3.5% opacity, and the app reads it from the capture as differences from the screen.
  See `desktop/src/core/locate.ts`. Failed readings are rejected, so the recording has no outline and
  its marks have no coordinates. Color-coded patterns gave wrong positions, because capture alters colors.
- **XWayland (§9 test 1).** Native Wayland passed basic drawing, but the overlay could cover the
  control bar. The app runs with `--ozone-platform=x11` and uses the `notification` window type.
- **Review (§4).** The buttons are Copy reference and Discard, and the video plays with sound.
  Copy WSL path isn't built, since it's Windows only.
- **Recordings (§4).** It matches the Mac's window rather than the simple list planned here.
- **Interrupted recordings.** At launch, they're listed as failed with a Retry.
- **Not built yet:** first-run window, packaging, bundled ffmpeg and whisper.cpp (§8), and
  `vp-frames` that runs without the app's own Electron folder.

## 1. Why

AltitudeIQ's team likes Video Prompt, but it only runs on Macs. Teammates on Windows and Fedora
want the same thing: show Claude what they mean by talking and drawing over their screen, rather
than typing it out.

**Success looks like**

- A teammate on either system can go from "I want to show Claude this" to a pasted reference with
  about the same effort as on the Mac, apart from one extra paste.
- Claude's first reply usually names the right UI element, with no follow-up question. This is
  the Mac spec's bar too.

## 2. Goals, non-goals, anti-goals

**Goals**

- One shared app for Windows and Fedora. **[Decided]**
- The user selects an area of the screen, talks, draws, pauses and stops. **[Decided]**
- A review panel whose output is a copied reference, usable in Claude Code or any other tool that
  can read local files. **[Decided]**
- Works for Claude Code in PowerShell and in WSL. **[Decided]**
- Fedora support targets KDE Plasma on Wayland. All Fedora teammates use Plasma. **[Decided]**

**Non-goals for this version**

- "Record Chrome window", or any window-following mode. **[Decided]**
- Sending directly to a waiting Claude session. **[Decided]**
- The MCP plugin and `get_frames`. It can be added later without changing the recording format.
  **[Proposed]**
- GNOME-specific work, such as a shell extension or tray alternative. **[Proposed]**
- Replacing or changing the Mac app. **[Decided]**
- Public release work: code signing, auto-update, store listings and a license review of bundled
  tools. The first audience is AltitudeIQ's team. **[Proposed]**

**Anti-goals: this fails even if it technically works, if**

- The user has to work out which file path or command to use for their setup.
- A paste fails silently because the path is in the wrong form for where Claude is running.
- The app uploads anything. Same as Mac: no server, no telemetry, on-device transcription.

## 3. Approaches

| Approach | Trade-off | Outcome |
|---|---|---|
| **A. Electron** | One interface for both systems using widely known tools. Larger download and more memory, less direct control over capture and overlay windows. | **Chosen by Michael.** |
| B. Qt | Reuses the Python capture prototype in `prototype/`, but that has no drawing or review screens, and Python is harder to package for Windows. | Fallback if Electron's drawing layer fails on Plasma (§9). |
| C. Swift engine + separate interfaces | Reuses the most logic and tests, but means building and maintaining the interface twice, and Swift is less proven on Windows. | Rejected. |

## 4. What the user does

```
Tray icon → Select area → 3-2-1 → Talk and draw → Stop → Review
                                                           ├─ Copy reference  ⏎
                                                           ├─ Copy WSL path   (Windows only)
                                                           └─ Discard
```

### Same as Mac

- 3-2-1 countdown.
- Control bar with timer, pause, draw and stop.
- Pen, arrow and box in red, plus undo and clear. Marks fade after 3 s, with a setting to keep them
  until Stop. Clicks don't reach apps while Draw is on.
- Soft warning at 3:00, no hard stop.
- Review shows a video preview, an editable transcript and a typed note.
- Retention defaults to 3 days, with the same setting options.
- 10 fps video, at most 1080 px tall.

### Different from Mac

| Area | Behavior | Label |
|---|---|---|
| **Tray menu** | Record selected area · Recordings… · Settings… · Quit | [Proposed] wording |
| **Starting** | Selecting an area is the only mode. To record everything, drag across the whole screen. | [Decided] |
| **Picker on Fedora** | The system's screen-share dialog chooses the monitor, then the user drags an area on it. The dialog should appear only the first time, if the spike finds a way (§9). The app then stays on that monitor until the user picks "Change monitor…" in the tray menu, which shows the dialog again. It also shows the dialog again if the remembered monitor is gone. | [Proposed] |
| **Control bar in the video** | Windows: hidden from capture, like the Mac. Fedora: left in the capture, so it's only in the video if it sits inside the selected area. The bar starts outside the area when there's room. When the area fills the screen, it shows, and the area picker says so. | [Proposed] |
| **Click rings** | Windows: same as Mac. Fedora: none, since apps can't see clicks elsewhere. The timeline's intro and entries leave clicks out there. | [Proposed] |
| **Review buttons** | Copy reference (Return) · Copy WSL path (Windows only) · Discard. | [Decided] for Copy reference, Discard and WSL support; [Proposed] for the WSL button |
| **Recordings window** | A simple list: title, time, length, Copy reference and delete. Delete goes to the system trash where available. Needed so a reference can be copied again later. | [Proposed] |
| **First run** | Microphone, speech model download and an optional 5-second test. No plugin step. Fedora also explains the screen-share dialog. | [Proposed] |
| **Shortcuts** | Ctrl+Alt+Shift+R starts recording. Alt+D toggles Draw and Esc stops drawing, registered only while they apply. If Plasma doesn't allow a shortcut, the tray and control bar still do everything, so no feature depends on one. | [Proposed] |

## 5. The reference and WSL

- **Copy reference** copies a plain absolute path to `timeline.md`, with no `@"…"` wrapper, because
  `@` is Claude Code syntax and this reference should work elsewhere. **[Proposed]**
- **Copy WSL path** copies the `/mnt/c/...` form of the same path. **[Proposed]**
- Other apps must be able to read local files and run commands to see the video. We test Claude
  Code in PowerShell and WSL on Windows and Claude Code on Fedora, and treat other apps as
  best-effort rather than promising them.
- `timeline.md` itself names the video, overview and `vp-frames` paths, so Claude in WSL needs usable
  forms of those too. **On Windows the file includes the commands for each environment**: Windows
  shells and WSL. Claude picks the one that fits where it's running. The user never has to choose
  anything beyond which button to press.
- Claude Code on Windows may run commands through either PowerShell or Git Bash, and they quote
  program paths differently. The commands in the timeline must be verified in each.

## 6. Architecture

```
┌──────────────────────── Electron app ─────────────────────────┐
│ Main process: tray, windows, shortcuts, recording state,      │
│               file storage, retention, running tools          │
│ Screens: area picker, control bar, drawing layer, countdown,  │
│          review, recordings, settings, first run              │
└───────────────┬───────────────────────────────┬───────────────┘
                │ writes                        │ runs
                ▼                               ▼
   <data folder>/recordings/<id>/        Bundled ffmpeg, whisper.cpp
     video.mp4, timeline.md,             (no separate user install)
     overview.jpg, manifest.json,
     meta.json
                ▲
                │ reads video.mp4
         vp-frames (bundled command) ◄── Claude runs it
```

- **Location:** a new `desktop/` folder in this repo, in TypeScript. **[Proposed]**
- **Port the logic, don't share code at runtime.** The Swift code (`Sources/VPCore`, `VPApp`,
  `VPProcess`) defines recording state, pause and segment timing, sentence splitting, stroke
  descriptions, coordinate mapping and timeline text. Port those to TypeScript. **[Proposed]**
- **Electron safety:** no remote content, context isolation on and Node access off in screens,
  with the Electron app making no network calls except the speech model download. Local files only,
  with no listening ports.

## 7. Recording and processing

**Capture.** Record the whole monitor containing the selected area with the microphone, at 10 fps,
into one segment file per pause-separated stretch. The drawing layer is in the capture, so marks
appear in the video without extra work. Control bar and picker windows are excluded on Windows.
The method is left to the spike (§9): Electron's built-in capture first, or a helper program if
that can't meet the requirements.

**Events.** Use the Mac's raw folder contract (`session.json`, `events.jsonl`, §7 of the Mac spec).
`mode` is always `area`. There are no `window` events. `click` events appear only on Windows, from a
small native mouse hook, since Electron has no global click API. Segment files may use a different
container from `.mov`. Times are per-segment, as on the Mac.

**Coordinates.** Log events in one consistent screen coordinate system and convert to video pixels,
accounting for display scaling. Mixed-scale multi-monitor setups and Plasma's fractional scaling
are known risks and need tests.

**Processing.** Use ffmpeg to join segments, crop to the area, scale to at most 1080 px tall, force 10
fps, draw click rings and write an H.264 `video.mp4` with AAC narration. Export 16 kHz mono audio for
whisper.cpp, using the same model and checksum as the Mac (`scripts/install.sh`). Then build
`overview.jpg`, `manifest.json`, `timeline.md` and `meta.json`, using the same statuses and failure
handling as `Processor.swift`. `raw/` is deleted on success and kept on failure, with a Retry.

**Timeline.** Same structure as `Tests/VPCoreTests/Golden/timeline.md`, with these changes:

- Remove the `get_frames` wording.
- Say the video shows the selected area, not "the recorded window".
- Leave out click wording when the platform can't log clicks.
- Add the Windows command forms from §5.

Coordinates, stroke descriptions, times, sentence splitting and rounding must match the Mac.

**`vp-frames`.** Same arguments and behavior as `Sources/vp-frames/main.swift`: `<video> --from S --to
E [--fps N] [--out DIR]`, at most 100 frames per call, long edge at most 1568 px, and it prints JPEG
paths one per line. On Windows it must also work when called from WSL, printing paths usable there.
If that doesn't work well, ship a Linux build for WSL too. Claude must not need Node, Python or
ffmpeg installed.

**Storage.** `VIDEO_PROMPT_HOME` overrides the location, as on the Mac. **[Proposed]** defaults:

- Windows: `%LOCALAPPDATA%\VideoPrompt`
- Fedora: `~/.local/share/VideoPrompt`, mode `0700`

Writes are atomic. Paths may contain spaces, since Windows usernames can.

## 8. Distribution

**[Proposed]** For the internal beta:

- Windows: an unsigned installer, with instructions for the SmartScreen warning.
- Fedora: an RPM, or an AppImage if that's simpler.
- Updating means installing the new version. No auto-update.

**Open: where beta builds are published.** The repo is public by Michael's choice, so publishing
there makes the installers public and brings the license review into scope. The §9 test builds from
source and publishes nothing, so this decision waits until the test passes.

ffmpeg and whisper.cpp ship inside the app, partly because Fedora's default H.264 encoder can be a
non-working stub (see `CLAUDE.md`). Their licenses and codecs need review before any public release.

## 9. Test first: 2–3 days on real machines

Throwaway work, and nothing here ships. It lives on the `spike/windows-linux` branch and follows
[`desktop-spike/README.md`](../../../desktop-spike/README.md). Each test runs on a real machine with
Claude Code building the test there and a person at the screen confirming what they see. Michael
runs Fedora first, since its drawing layer is the biggest risk to choosing Electron. A Windows
teammate runs Windows, which must also pass before the full build. Results are text-only, since the
repo is public.

| # | Question | If it fails |
|---|---|---|
| 1 | **Plasma:** does a transparent drawing layer stay on top of other windows, pass clicks through when Draw is off, take drawing input when on, and show up in the capture? | Try XWayland, then a KWin window rule. If still failing, stop and reconsider Qt. |
| 2 | **Plasma:** can capture start without the screen-share dialog after the first time, can we tell which monitor was chosen, and do "Change monitor…" and an unplugged monitor both bring the dialog back? | Try the portal restore-token approach in `prototype/screen_prompt/capture/linux.py`, with a helper program. Otherwise, accept a dialog per recording and report back. |
| 3 | **Plasma:** do the shortcuts work? Do area coordinates line up with the video at fractional scaling? | Tray and control bar only for shortcuts. Coordinates must be fixed: drawing notes depend on them. |
| 4 | **Windows:** is the control bar hidden from capture while the drawing layer stays visible? Is there a capture border? Do coordinates line up on mixed-scale monitors? | Move the bar outside the area, as on Fedora. |
| 5 | **Windows:** does a click hook work without admin rights, and do security tools object? | Ship without click rings, as on Fedora. |
| 6 | **Hand-off:** paste the reference into Claude Code in PowerShell and in WSL, on Fedora, and ideally in Claude Desktop and Conductor. Can Claude read the timeline, run `vp-frames` and find a brief on-screen moment? | Fix the path or command forms, or ship a Linux `vp-frames` for WSL. Record which other apps work. |

**Report back with results and revised estimates before full build.**

## 10. Testing the real build

- **Shared examples:** run the ported logic against the Mac's test cases, including
  `Tests/VPCoreTests/Golden/timeline.md`, with only the §7 differences allowed. Cover a pause, an undo,
  and each stroke-description case.
- **Processing:** fixture recordings produce a video of the right size, crop and frame timing, with
  rings on Windows and coordinates that line up.
- **`vp-frames`:** run from PowerShell, Git Bash, WSL and Fedora, on a path with spaces.
- **Manual checklist per release, on each system:** first run with microphone allowed and denied, the
  whole flow through to Claude finding something in the video, pause, draw, multi-monitor, and
  retention.

## 11. Rough effort

About 3–5 weeks for one engineer using Claude, for an internal beta on both systems. This is a
judgment estimate, not a measurement, and the §9 test may change it.

## 12. Left to the builder

File layout, Electron and tool versions, the capture API and segment format (within §7), native
add-on or helper for the click hook, screen visuals (follow the Mac's dark control bar and
bar-style tool buttons), packaging tools, and how to sequence the work after §9.
Update `CLAUDE.md`'s "Linux later, maybe" note once this ships.
