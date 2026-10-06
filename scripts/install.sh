#!/bin/bash
# Video Prompt internal beta installer. Safe to re-run: re-running it is how you update.
# Installs the app, makes sure speech-to-text (whisper.cpp + model) is present, and prints the
# Claude Code plugin commands. Never uses sudo.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
PREFIX="${VP_PREFIX:-/Applications}"
DATA="${VIDEO_PROMPT_HOME:-$HOME/Library/Application Support/VideoPrompt}"
APP="Video Prompt.app"
MODEL="$DATA/models/ggml-base.en.bin"
MODEL_URL="https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.en.bin"
MODEL_SHA256="a03779c86df3323075f5e796cb2ce5029f00ec8869eee3fdfb897afe36c6d002"

say() { printf '\033[1m%s\033[0m\n' "$*"; }
ask() {  # ask "question" → 0 for yes; no terminal → no
  [ -t 0 ] || return 1
  read -r -p "$1 [y/N] " a; [[ "$a" =~ ^[Yy] ]]
}

[ -d "$HERE/$APP" ] || { echo "Can't find $APP next to install.sh" >&2; exit 1; }

say "1/4 Installing $APP into $PREFIX"
pkill -x VideoPrompt 2>/dev/null && sleep 1 || true
mkdir -p "$PREFIX"
rm -rf "$PREFIX/$APP"
ditto "$HERE/$APP" "$PREFIX/$APP"
xattr -dr com.apple.quarantine "$PREFIX/$APP" 2>/dev/null || true

say "2/4 Speech-to-text engine (whisper.cpp)"
if command -v whisper-cli >/dev/null || [ -x /opt/homebrew/bin/whisper-cli ] || [ -x /usr/local/bin/whisper-cli ]; then
  echo "    already installed"
elif command -v brew >/dev/null; then
  if ask "    Install it with Homebrew (brew install whisper-cpp)?"; then brew install whisper-cpp
  else echo "    skipped: recordings will say 'transcription unavailable' until it's installed"; fi
else
  echo "    Homebrew not found: install whisper-cpp yourself to get narration transcribed"
fi

say "3/4 Speech model ($(basename "$MODEL"), 148 MB)"
mkdir -p "$(dirname "$MODEL")"
if [ -f "$MODEL" ] && [ "$(shasum -a 256 "$MODEL" | cut -c1-64)" = "$MODEL_SHA256" ]; then
  echo "    already present and verified"
else
  curl -fL --progress-bar -o "$MODEL.part" "$MODEL_URL"
  got="$(shasum -a 256 "$MODEL.part" | cut -c1-64)"
  if [ "$got" != "$MODEL_SHA256" ]; then
    rm -f "$MODEL.part"; echo "    checksum mismatch ($got): not installing the model" >&2; exit 1
  fi
  mv "$MODEL.part" "$MODEL"; echo "    downloaded and verified"
fi

say "4/4 Starting Video Prompt"
[ -n "${VP_NO_OPEN:-}" ] || open "$PREFIX/$APP"
cat <<'MSG'

Done. Look for the ◉ icon at the right of your menu bar (⌃⌥⌘R records the Chrome window).
The first time, macOS asks for Screen Recording and Microphone access for Video Prompt.

To let Claude Code fetch recordings, paste these into Claude Code once:
  /plugin marketplace add mchoi-altitude/video-prompt
  /plugin install video-prompt@video-prompt

Update later: run the same install command again. Uninstall: quit the app, then
  rm -rf "/Applications/Video Prompt.app" ~/Library/Application\ Support/VideoPrompt
MSG
