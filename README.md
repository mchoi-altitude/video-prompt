# video-prompt

Record your screen, draw on it, and talk through what you want — then hand that recording to
Claude Code as a prompt.

**Status:** early. The macOS app is in internal beta. The Fedora app runs from source and is still
being tested. Windows isn't available yet.

## Install

- [macOS](#macos-internal-beta)
- [Linux (Fedora KDE)](#linux-fedora-kde)
- [Windows](#windows)

### macOS (internal beta)

You need access to this repo, plus the GitHub CLI (`gh auth login`), Homebrew and Claude Code.
To install, or later to update, run:

```bash
cd "$(mktemp -d)" && gh release download beta -R mchoi-altitude/video-prompt -p VideoPrompt-beta.zip \
  && unzip -q VideoPrompt-beta.zip && ./video-prompt-beta/install.sh
```

The installer copies the app to /Applications, installs whisper.cpp (it asks first) and the speech
model (checksum-verified), opens the app, and prints the two Claude Code `/plugin` commands. The
first run shows a setup window. This beta isn't notarized, so install it only with the command
above, not by downloading the zip in a browser. Report problems in this repo's Issues.
Uninstall: quit the app, then `rm -rf "/Applications/Video Prompt.app" ~/Library/Application\ Support/VideoPrompt`.

Publishing a beta (maintainers): `scripts/release-beta.sh` (or `--dry-run` to build only).

Known issues and deferred fixes: [`docs/known-issues.md`](docs/known-issues.md).

### Linux (Fedora KDE)

Tested on Fedora 44 with KDE Plasma 6.8 on Wayland, one monitor at 100% scale. You need the GitHub CLI
(`gh auth login`) and a CPU with AVX2, which most computers since about 2015 have. To install, or
later to update, run:

```bash
cd "$(mktemp -d)" && gh release download linux-beta -R mchoi-altitude/video-prompt -p VideoPrompt-linux-beta.tar.gz \
  && tar -xzf VideoPrompt-linux-beta.tar.gz && ./video-prompt-linux-beta/install.sh
```

The installer puts the app in `~/.local/opt/video-prompt`, downloads the speech model
(checksum-verified), adds Video Prompt to your app launcher and opens it. If ffmpeg or a working H.264
encoder is missing, it asks before running `sudo dnf install -y ffmpeg-free openh264`. Nothing else
needs a password.

The app appears in the system tray. Click it and choose **Record…** (or press Ctrl+Alt+Shift+R), then
pick your full screen or a region in KDE's dialog, which appears on every recording. A 3-2-1 follows,
then use the control bar to pause, draw and stop. Alt+D toggles drawing, and Esc stops drawing. When
you stop, review the recording and press **Copy reference**, then paste the path into Claude Code.
There's no plugin on Linux yet, so paste is the only way to hand a recording to Claude.

Good to know:

- **Regions:** the app measures where a region is during the countdown, so faint lines can show on
  screen. It then draws a red outline around the region, which isn't in the video. If something at the
  region's corners is changing, such as a playing video, the measurement can fail. That recording
  still saves, with no outline and no coordinates for your marks.
- **The control bar** shows in the video if it's inside what you're recording. It's placed outside a
  measured region when there's room, and you can drag it.
- **Clicks** aren't logged on Linux, because apps can't see clicks in other apps.
- **Recordings** go to the Trash after 3 days by default, which you can change in **Recordings…**. If
  the app stops mid-recording, that recording shows there as failed, with a **Retry** button.
- **Speech-to-text:** without whisper-cli or the model, recordings still save, without a transcript.

To uninstall, run `./video-prompt-linux-beta/install.sh --uninstall` from an unpacked archive. It keeps
`~/.local/share/VideoPrompt`, which holds your recordings and the speech model. Delete that too to
remove everything.

To run from source, use `npm ci` and `npm start` in `desktop/`, with Node.js LTS and ffmpeg installed.
Publishing (maintainers): `desktop/scripts/release.sh` builds the archive, which also needs cmake and
g++, and replaces the `linux-beta` release. `npm run package` builds it without publishing.

### Windows

Not available yet. Work on it has started: see [`desktop/WINDOWS.md`](desktop/WINDOWS.md).

## Developing

This section covers the macOS app. Needs macOS 14+ and Swift 6.3 (the Command Line Tools are enough for the core; the app will need
Xcode). Transcription uses whisper.cpp: `brew install whisper-cpp`.

```bash
scripts/get-dev-model.sh          # whisper base.en model into the data folder
scripts/test.sh                   # all tests (wraps `swift test` with the Testing.framework paths)

# Try the pipeline + plugin without the app:
export VIDEO_PROMPT_HOME=$TMPDIR/vp     # keep test recordings out of the real folder
ln -s "$HOME/Library/Application Support/VideoPrompt/models" $VIDEO_PROMPT_HOME/models
ID=$(scripts/make-fixture.sh)           # needs ffmpeg
swift run vp-process $ID                # prints the timeline.md path
swift build -c release
export VIDEO_PROMPT_MCP=$PWD/.build/release/vp-mcp
claude --plugin-dir plugins/video-prompt   # then: "look at my recording"
```

### The Mac app

No Xcode needed for development. One-time: `scripts/make-dev-cert.sh` creates a local
"Video Prompt Dev" signing identity, so macOS keeps the app's Screen Recording and Microphone
permission across rebuilds. Then:

```bash
scripts/build-app.sh            # → build/Video Prompt.app (debug; --release for release)
open "build/Video Prompt.app"
```

`docs/manual-test.md` is the end-to-end checklist.

### The Claude Code plugin

`plugins/video-prompt` runs `vp-mcp`, a stdio MCP server that ships inside the app. It reads the
recordings folder directly and opens no network port. Install it from this repo:

```
/plugin marketplace add mchoi-altitude/video-prompt
/plugin install video-prompt@video-prompt
```

If the Video Prompt app isn't installed, the plugin's server can't start and Claude Code lists it
as failed. Install the app, or set `VIDEO_PROMPT_MCP` to a built `vp-mcp`.

Claude can fetch a recording only after you press Save or Send in the review panel. Until then
the tools say it's still in review.

`/video-prompt:brief` turns the latest recording into `brief.md`: a short, numbered change list
that names each element by its on-screen text. Claude pulls one frame per piece of feedback
instead of paging through the video. Paste the brief into a session that can't see your Mac,
such as a cloud workspace, or into an issue.

## Repo layout

- `docs/superpowers/specs/2026-10-06-video-prompt-design.md`: the v1 design. Start here.
  (`docs/user-journey.md` is the original draft.)
- `Sources/`: Swift package. `VPCore` (models, storage, timeline.md), `VPMedia`
  (AVFoundation: window video, overview, frame extraction), `VPProcess` (pipeline +
  whisper.cpp), `VPMCP` + `vp-mcp` (MCP server), `vp-process` and `vp-frames` (CLIs), `VPApp` +
  `VPCapture` + `VideoPrompt` (the Mac app).
- `desktop/`: the Fedora app (Electron and TypeScript). `npm test` runs its tests.
- `plugins/video-prompt`, `.claude-plugin/marketplace.json`: the Claude Code plugin.
- `prototype/`: the original Python prototype (package name `screen_prompt`), from before the
  video-first design (it picked keyframes and wrote `prompt.md`). Kept as a reference; capture and
  UI there are incomplete.
- `CLAUDE.md`: context and decisions for Claude Code sessions working in this repo.

## License

[MIT](LICENSE). Contributions are welcome: see [CONTRIBUTING.md](CONTRIBUTING.md).
