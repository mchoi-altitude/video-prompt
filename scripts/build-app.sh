#!/bin/bash
# Builds build/Video Prompt.app (app + bundled vp-mcp) without Xcode and signs it.
# Signs with the "Video Prompt Dev" identity when present (stable, so macOS keeps the
# Screen Recording/Microphone grants across rebuilds), else ad-hoc.
set -euo pipefail
cd "$(dirname "$0")/.."
CONFIG=debug; [ "${1:-}" = "--release" ] && CONFIG=release
swift build -c "$CONFIG" --product VideoPrompt
swift build -c "$CONFIG" --product vp-mcp
swift build -c "$CONFIG" --product vp-frames
BIN="$(swift build -c "$CONFIG" --show-bin-path)"
APP="build/Video Prompt.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp "$BIN/VideoPrompt" "$BIN/vp-mcp" "$BIN/vp-frames" "$APP/Contents/MacOS/"
# VIDEO_PROMPT_SIGN=- forces ad-hoc (e.g. when the keychain would prompt).
IDENTITY="${VIDEO_PROMPT_SIGN:-}"
if [ -z "$IDENTITY" ]; then
  IDENTITY="-"
  security find-identity -p codesigning 2>/dev/null | grep -q '"Video Prompt Dev"' && IDENTITY="Video Prompt Dev"
fi
sign() {
  # A locked keychain makes codesign wait on a dialog that may be hidden: give up after 60 s.
  perl -e 'alarm 60; exec @ARGV' codesign --force --options runtime --timestamp=none --sign "$IDENTITY" "$@"
}
if ! sign "$APP/Contents/MacOS/vp-mcp" || ! sign "$APP/Contents/MacOS/vp-frames" || ! sign --entitlements Resources/VideoPrompt.entitlements "$APP"; then
  echo "Signing with '$IDENTITY' failed or waited on the keychain (unlock it, or answer its dialog)." >&2
  echo "Falling back to ad-hoc: macOS may ask for permissions again for this build." >&2
  IDENTITY="-"
  sign "$APP/Contents/MacOS/vp-mcp" && sign "$APP/Contents/MacOS/vp-frames" && sign --entitlements Resources/VideoPrompt.entitlements "$APP"
fi
echo "$APP (signed: $IDENTITY)"
