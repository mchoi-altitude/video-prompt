# video-prompt

Record your screen, draw on it, and talk through what you want — then hand that recording to
Claude Code as a prompt.

**Status:** early. We're aligning on the [user journey](docs/user-journey.md) before building
the app. The first target is a native macOS menu-bar app.

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
swift run vp-process $ID                # prints the prompt.md path
swift build -c release
export VIDEO_PROMPT_MCP=$PWD/.build/release/vp-mcp
claude --plugin-dir plugins/video-prompt   # then: "look at my recording"
```

### The Claude Code plugin

`plugins/video-prompt` runs `vp-mcp`, a stdio MCP server that ships inside the app. It reads the
recordings folder directly and opens no network port. Install it from this repo:

```
/plugin marketplace add mchoi-altitude/video-prompt
/plugin install video-prompt@video-prompt
```

If the Video Prompt app isn't installed, the plugin's server can't start and Claude Code lists it
as failed. Install the app, or set `VIDEO_PROMPT_MCP` to a built `vp-mcp`.

## Repo layout

- `docs/superpowers/specs/2026-10-06-video-prompt-design.md`: the v1 design. Start here.
  (`docs/user-journey.md` is the original draft.)
- `Sources/`: Swift package. `VPCore` (models, storage, timeline, prompt.md), `VPMedia`
  (AVFoundation), `VPProcess` (pipeline + whisper.cpp), `VPMCP` + `vp-mcp` (MCP server),
  `vp-process` (CLI).
- `plugins/video-prompt`, `.claude-plugin/marketplace.json`: the Claude Code plugin.
- `prototype/`: a Python prototype (package name `screen_prompt`) of the post-recording pipeline (join segments → transcribe →
  pick keyframes → write `prompt.md`). It's tested on Linux and kept as a reference; capture and
  UI there are incomplete.
- `CLAUDE.md`: context and decisions for Claude Code sessions working in this repo.
