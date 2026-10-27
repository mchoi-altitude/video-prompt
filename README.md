# video-prompt

Record your screen, draw on it, and talk through what you want — then hand that recording to
Claude Code as a prompt.

**Status:** early. We're aligning on the [user journey](docs/user-journey.md) before building
the app. The first target is a native macOS menu-bar app.

## Internal beta (team members)

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

## Developing

Needs macOS 14+ and Swift 6.3 (the Command Line Tools are enough for the core; the app will need
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
- `plugins/video-prompt`, `.claude-plugin/marketplace.json`: the Claude Code plugin.
- `prototype/`: the original Python prototype (package name `screen_prompt`), from before the
  video-first design (it picked keyframes and wrote `prompt.md`). Kept as a reference; capture and
  UI there are incomplete.
- `CLAUDE.md`: context and decisions for Claude Code sessions working in this repo.
