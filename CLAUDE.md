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
- **Fedora: an Electron app in `desktop/`.** See "Updates after building the Fedora app" in
  `docs/superpowers/specs/2026-11-04-windows-linux-design.md`. The Python/Qt prototype in `prototype/`
  is only a reference now.
- **Windows: the same Electron app.** Platform differences live in `desktop/src/core/platform.ts`, whose
  tests check both systems' answers on either one; Linux answers must not change without a Fedora retest.
  Like the Mac, Windows has Record whole screen / Record selected area… (the app's own picker, no system
  dialog) and hides the control bar from the video. It ships no H.264 or AAC codec of its own (patents;
  Michael, 2026-11-06), so its `video.mp4` is VP9 + Opus. It bundles our own LGPL ffmpeg
  (`desktop/scripts/build-ffmpeg-win.sh`, released by the "ffmpeg for Windows" workflow), Electron's
  H.264-free `ffmpeg.dll` (`desktop/scripts/after-pack.cjs`), whisper-cli and the speech model, all pinned in
  `desktop/scripts/fetch-tools.mjs`, in an unsigned per-user NSIS installer (`npm run package:win`). The
  windows-beta workflow builds, checks and publishes it.

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

## Linux notes

- Electron on Plasma: run with `--ozone-platform=x11`. Windows need `type: "notification"` to stay on
  top, and `setBounds` again after showing, because the size given at creation is confined to the work area.
- Under XWayland, `screen.getCursorScreenPoint()` goes stale once the pointer is over a native Wayland
  app, so use the windows' own pointer events. `getBounds()` can also differ from the real window.
- Resizing a canvas wipes it. A window reaches full size only after it's shown.
- Capture alters colors, so don't encode data in exact color values. Neutral grays arrived intact.
- A Plasma panel can be see-through, so the system theme doesn't say what color is behind the tray
  icon. The icon brings its own dark tile.
- `whisper-cpp` on Fedora has only libraries, with no `whisper-cli`. Build it into `desktop/vendor/bin`.
- ffmpeg can succeed without writing a file, for example an overview of a very short clip.

- Wayland: capture via the xdg-desktop-portal ScreenCast (persist_mode=2 + restore_token
  skips the picker after the first time), then a PipeWire fd → `gst-launch-1.0 pipewiresrc`.
- Run Qt windows through XWayland (`QT_QPA_PLATFORM=xcb`); native Wayland can't keep an
  overlay always-on-top or position windows.
- Fedora ships a stub OpenH264 (`noopenh264`): encoders are listed but fail. Test-encode
  before choosing; fall back to VP8/VP9.

## Windows notes

- Git on Windows converts to CRLF unless told otherwise. `.gitattributes` keeps LF, since shell scripts run
  in WSL and tests compare files byte for byte.
- A focused Electron window answers the default menu's shortcuts: F11 made the see-through control bar full
  screen over the marks. They still reached the video, since the bar is hidden from capture, so check the
  screen, not only the video. The bar is non-focusable and the default menu is removed on Windows.
- A window that closes under the pointer never reports the pointer leaving. Reset hover state yourself.
- Git Bash runs a `.cmd` through `cmd /c`, which splits its path at spaces. Git Bash and WSL use
  `bin/vp-frames.sh`; PowerShell uses `bin/vp-frames.cmd`, called with `&`.
- Node runs a `.cmd` only through `cmd.exe /d /s /c` with every argument quoted.
- Git Bash's `tar` reads `C:` as a remote host. Use `%SystemRoot%\System32\tar.exe`.
- From WSL, a Windows program gets an environment variable only if `WSLENV` names it.
- `desktopCapturer` on Windows gives every screen without a dialog. Match `display_id` to `Display.id`.
- `ffmpeg -codecs` lists h264 and aac even when no code for them is built in. Check with `-encoders` and
  `-decoders` (`desktop/scripts/check-ffmpeg.mjs`).
- Electron's own `ffmpeg.dll` decodes H.264 and AAC. Each Electron release also publishes
  `ffmpeg-v<version>-win32-x64.zip` without them; VP9 is decoded by libvpx inside Electron, so review still
  plays. Updating Electron means updating that zip's and DLL's checksums in `fetch-tools.mjs` and
  `after-pack.cjs`. `electron.exe` itself still contains the OpenH264 encoder (WebRTC).
- With the H.264-free DLL, an old H.264 recording still shows its picture through the graphics card's own
  decoder, but has no sound.
- ffmpeg.org can refuse connections. To build ffmpeg locally like CI, Docker Desktop's `ubuntu:24.04` works.
