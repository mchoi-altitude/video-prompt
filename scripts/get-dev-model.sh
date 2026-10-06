#!/bin/bash
# Dev only: fetch the whisper.cpp base.en model. Release builds pin a checksum (Plan 3).
set -euo pipefail
ROOT="${VIDEO_PROMPT_HOME:-$HOME/Library/Application Support/VideoPrompt}"
mkdir -p "$ROOT/models"
OUT="$ROOT/models/ggml-base.en.bin"
[ -s "$OUT" ] && { echo "already have $OUT"; exit 0; }
curl -fL --progress-bar -o "$OUT.part" https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.en.bin
mv "$OUT.part" "$OUT"
echo "$OUT"
