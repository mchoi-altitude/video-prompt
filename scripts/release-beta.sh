#!/bin/bash
# Builds the internal beta and publishes it as the GitHub Release "beta" on this (private) repo,
# replacing the previous one. Teammates install/update with:
#   cd "$(mktemp -d)" && gh release download beta -R mchoi-altitude/video-prompt -p VideoPrompt-beta.zip \
#     && unzip -q VideoPrompt-beta.zip && ./video-prompt-beta/install.sh
# --dry-run builds the zip without uploading.
set -euo pipefail
cd "$(dirname "$0")/.."
DRY=0; [ "${1:-}" = "--dry-run" ] && DRY=1
[ -z "$(git status --porcelain -- Sources Package.swift Resources scripts)" ] || { echo "Commit your changes first." >&2; exit 1; }
SHA="$(git rev-parse --short HEAD)"

scripts/test.sh >/dev/null
scripts/build-app.sh --release
APP="build/Video Prompt.app"
# Every beta must carry the same signature, or teammates lose their permission grants.
# (Read it into a variable: grep -q under pipefail can fail on SIGPIPE even when it matches.)
SIG="$(codesign -dv --verbose=2 "$APP" 2>&1)"
[[ "$SIG" == *"Authority=Video Prompt Dev"* ]] || { echo "Not signed with 'Video Prompt Dev' (run scripts/make-dev-cert.sh)." >&2; exit 1; }

STAGE="build/video-prompt-beta"
rm -rf "$STAGE" build/VideoPrompt-beta.zip
mkdir -p "$STAGE"
ditto "$APP" "$STAGE/Video Prompt.app"
cp scripts/install.sh "$STAGE/install.sh"
echo "$SHA" > "$STAGE/VERSION"
(cd build && ditto -c -k --keepParent video-prompt-beta VideoPrompt-beta.zip)
echo "Built build/VideoPrompt-beta.zip ($(du -h build/VideoPrompt-beta.zip | cut -f1), $SHA)"
[ $DRY -eq 1 ] && exit 0

gh release delete beta --yes --cleanup-tag 2>/dev/null || true
gh release create beta build/VideoPrompt-beta.zip --prerelease --target "$(git rev-parse HEAD)" \
  --title "Internal beta ($SHA)" \
  --notes "Install or update:
\`\`\`
cd \"\$(mktemp -d)\" && gh release download beta -R mchoi-altitude/video-prompt -p VideoPrompt-beta.zip && unzip -q VideoPrompt-beta.zip && ./video-prompt-beta/install.sh
\`\`\`"
echo "Published: $(gh release view beta --json url -q .url)"
