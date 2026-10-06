#!/bin/bash
# Builds build/Video Prompt.app (app + bundled vp-mcp) without Xcode and signs it.
# Signs with the "Video Prompt Dev" identity when present (stable, so macOS keeps the
# Screen Recording/Microphone grants across rebuilds), else ad-hoc.
set -euo pipefail
cd "$(dirname "$0")/.."
CONFIG=debug; [ "${1:-}" = "--release" ] && CONFIG=release
swift build -c "$CONFIG" --product VideoPrompt
swift build -c "$CONFIG" --product vp-mcp
BIN="$(swift build -c "$CONFIG" --show-bin-path)"
APP="build/Video Prompt.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp "$BIN/VideoPrompt" "$BIN/vp-mcp" "$APP/Contents/MacOS/"
IDENTITY="-"
security find-identity -p codesigning 2>/dev/null | grep -q '"Video Prompt Dev"' && IDENTITY="Video Prompt Dev"
SIGN=(codesign --force --options runtime --timestamp=none --sign "$IDENTITY")
"${SIGN[@]}" "$APP/Contents/MacOS/vp-mcp"
"${SIGN[@]}" --entitlements Resources/VideoPrompt.entitlements "$APP"
echo "$APP (signed: $IDENTITY)"
