# video-prompt

Record your screen, draw on it, and talk through what you want — then hand that recording to
Claude Code as a prompt.

**Status:** early. We're aligning on the [user journey](docs/user-journey.md) before building
the app. The first target is a native macOS menu-bar app.

## Repo layout

- `docs/user-journey.md`: draft user journey and open decisions. Start here.
- `prototype/`: a Python prototype (package name `screen_prompt`) of the post-recording pipeline (join segments → transcribe →
  pick keyframes → write `prompt.md`). It's tested on Linux and kept as a reference; capture and
  UI there are incomplete.
- `CLAUDE.md`: context and decisions for Claude Code sessions working in this repo.
