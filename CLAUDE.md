# Context for Claude Code

## What we're building

A "video prompt" tool for Claude Code. The user clicks a menu-bar icon, records all or part of
the screen, and can draw on the screen with the mouse while narrating. Recording can be started,
paused and stopped. When they stop, the recording is turned into something Claude can use and
handed to a Claude Code session.

## Decisions so far

- **Mac first.** Most users are on macOS. Build a native Swift app (menu-bar / `NSStatusItem`):
  - ScreenCaptureKit for screen + mic capture. It can exclude the app's own control bar and
    overlay windows from the recording if we want that.
  - A real `.app` gets its own Screen Recording and Microphone permission prompts (a script
    would inherit the terminal's).
  - Distribute as a signed and notarized `.dmg` and/or Homebrew cask (needs an Apple Developer
    account).
- **User journey decided (2026-10-06).** The source of truth is
  `docs/superpowers/specs/2026-10-06-video-prompt-design.md` (clickable prototype linked there).
  Public open-source release, bundle ID `ai.altitudeiq.videoprompt`, AltitudeIQ-owned Apple
  Developer account.
- **Linux later, maybe.** A Python/Qt + xdg-desktop-portal prototype was started; see "Linux
  notes" below.

## Key technical facts (learned the hard way)

- **Video-first (2026-10-06).** Picking "key moments" missed brief screens. A recording is now
  the recorded window as `video.mp4` (10 fps, narration, drawings, click rings) + `timeline.md` +
  `overview.jpg`; Claude pulls frames itself with the `get_frames` MCP tool or the bundled
  `vp-frames` CLI. The API has no video content type, but Claude as an agent with the file and
  a frame tool handles video well (it found a 0.4 s flash in testing). Don't reintroduce
  keyframe selection.
- Whisper returns long segments, so we split the narration into sentences using word
  timestamps. That lets it interleave with the other timeline events.
- Drawings and clicks are logged in global top-left screen points and converted to pixels of the
  recording video. A shape heuristic produces text like "circled the area (x0,y0)–(x1,y1)" (or
  "drew a curved mark around …" for open loops) as a text anchor for the red marks.
- Pausing = ending a segment and starting a new one; segments are concatenated at the end.
  Event times are stored per segment and mapped using the actual segment durations.
- Handing off to Claude Code, two mechanisms planned (both):
  1. An MCP server with `get_latest_recording` (returns text + images inline), `list_recordings`,
     and maybe `wait_for_next_recording` so Claude can ask the user to record something and wait.
     Ship it as a Claude Code plugin so teammates get it with one install.
  2. Copy an `@"/path/to/timeline.md"` reference to the clipboard (quoted: the data root,
     "Application Support", has a space).
- Python MCP SDK is now v2: `from mcp.server.mcpserver import MCPServer, Image`
  (FastMCP was renamed). Tools returning a list of `str`/`Image` should use
  `structured_output=False`.
- faster-whisper 1.2.1 breaks with PyAV 19 when given a file path. Pass a float32 numpy array
  of 16 kHz mono samples instead. On Mac, consider whisper.cpp or Apple's Speech framework
  instead of Python.

## Working on this Mac (learned the hard way)

- No Xcode: SwiftPM + Command Line Tools. Tests: `scripts/test.sh` (Testing.framework paths;
  `--no-parallel`, because parallel video tests starve the hardware encoder and hang).
- After changing a struct/enum's stored layout, incremental test builds can crash silently or fail
  oddly: `rm -rf .build` before believing a failure.
- In zsh, `log` is a builtin. Read the app's logs with `/usr/bin/log show --predicate
  'subsystem == "ai.altitudeiq.videoprompt"'`.
- Don't run `screencapture` or other permission-needing commands from the terminal: macOS then
  asks the user to grant *iTerm* and restart it.
- The app is signed with a local "Video Prompt Dev" identity so permission grants survive
  rebuilds; ad-hoc builds leave stale grants (`tccutil reset ScreenCapture
  ai.altitudeiq.videoprompt`). `build-app.sh` gives up on a keychain-blocked codesign after 60 s.
- On a full menu bar, macOS can put a new status item under the MacBook notch; the app asks for
  the far-right position (`NSStatusItem Preferred Position`).

## Linux notes (for later)

- Wayland: capture via the xdg-desktop-portal ScreenCast (persist_mode=2 + restore_token
  skips the picker after the first time), then a PipeWire fd → `gst-launch-1.0 pipewiresrc`.
- Run Qt windows through XWayland (`QT_QPA_PLATFORM=xcb`); native Wayland can't keep an
  overlay always-on-top or position windows.
- Fedora ships a stub OpenH264 (`noopenh264`): encoders are listed but fail. Test-encode
  before choosing; fall back to VP8/VP9.
