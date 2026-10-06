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
- **User journey before code.** Agree on `docs/user-journey.md` before writing the app.
- **Linux later, maybe.** A Python/Qt + xdg-desktop-portal prototype was started; see "Linux
  notes" below.

## Key technical facts (learned the hard way)

- **Claude doesn't take video input.** A recording has to become keyframes (JPEG) + a
  timestamped transcript + drawing/cursor events on one timeline. `prototype/screen_prompt/process.py`
  does this, and its output format (`manifest.json`, `prompt.md`) is worth keeping.
- Keyframe choice: always the first and last frame, frames just after each finished drawing,
  scene changes (ffmpeg `select='gt(scene,0.1)'`), and the midpoint of each narration sentence.
  They're deduplicated to at least 1.5s apart, capped at about 24, with the long edge at most
  1568px.
- Whisper returns long segments, so we split the narration into sentences using word
  timestamps. That lets it interleave with frames.
- Drawings are logged as points (fractions of the screen) and converted to pixel coordinates in
  the frame images. A simple shape heuristic produces text like "circled the area (x0,y0)–(x1,y1)",
  which gives Claude a text anchor alongside the red marks in the images.
- Pausing = ending a segment and starting a new one; segments are concatenated at the end.
  Event times are stored per segment and mapped using the actual segment durations.
- Handing off to Claude Code, two mechanisms planned (both):
  1. An MCP server with `get_latest_recording` (returns text + images inline), `list_recordings`,
     and maybe `wait_for_next_recording` so Claude can ask the user to record something and wait.
     Ship it as a Claude Code plugin so teammates get it with one install.
  2. Copy an `@/path/to/prompt.md` reference to the clipboard on Stop.
- Python MCP SDK is now v2: `from mcp.server.mcpserver import MCPServer, Image`
  (FastMCP was renamed). Tools returning a list of `str`/`Image` should use
  `structured_output=False`.
- faster-whisper 1.2.1 breaks with PyAV 19 when given a file path. Pass a float32 numpy array
  of 16 kHz mono samples instead. On Mac, consider whisper.cpp or Apple's Speech framework
  instead of Python.

## Linux notes (for later)

- Wayland: capture via the xdg-desktop-portal ScreenCast (persist_mode=2 + restore_token
  skips the picker after the first time), then a PipeWire fd → `gst-launch-1.0 pipewiresrc`.
- Run Qt windows through XWayland (`QT_QPA_PLATFORM=xcb`); native Wayland can't keep an
  overlay always-on-top or position windows.
- Fedora ships a stub OpenH264 (`noopenh264`): encoders are listed but fail. Test-encode
  before choosing; fall back to VP8/VP9.
