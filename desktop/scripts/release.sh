#!/usr/bin/env bash
# Builds the Linux archive and publishes it as the linux-beta pre-release, replacing the last one.
# This repo is public, so anyone can download it. It's separate from the Mac's `beta` release,
# because scripts/release-beta.sh deletes and recreates that one.
set -euo pipefail

cd "$(dirname "$(readlink -f "$0")")/.."
[ -z "$(git status --porcelain)" ] || { echo "Commit your changes first." >&2; exit 1; }
[ "$(git rev-parse HEAD)" = "$(git rev-parse origin/main)" ] || { echo "Release from the latest main." >&2; exit 1; }

scripts/build-package.sh
gh release delete linux-beta --yes --cleanup-tag 2>/dev/null || true
gh release create linux-beta out/VideoPrompt-linux-beta.tar.gz --prerelease --target "$(git rev-parse HEAD)" \
  --title "Video Prompt for Linux (beta)" \
  --notes "For Fedora KDE on Wayland. Unsigned internal beta. Install or update:

\`\`\`bash
cd \"\$(mktemp -d)\" && gh release download linux-beta -R mchoi-altitude/video-prompt -p VideoPrompt-linux-beta.tar.gz \\
  && tar -xzf VideoPrompt-linux-beta.tar.gz && ./video-prompt-linux-beta/install.sh
\`\`\`"
echo "Published: $(gh release view linux-beta --json url -q .url)"
