#!/bin/bash
# Builds a raw recording (12 s Chrome-like window, narration, one circle, a resize at 6 s)
# under $VIDEO_PROMPT_HOME (or the real data root) and prints its id. Needs ffmpeg.
set -euo pipefail
ROOT="${VIDEO_PROMPT_HOME:-$HOME/Library/Application Support/VideoPrompt}"
ID="$(date +%Y%m%d-%H%M%S)"
RAW="$ROOT/recordings/$ID/raw"
mkdir -p "$RAW"
TMP="$(mktemp -d)"
say -o "$TMP/n.aiff" "So, the settings page. See this Save button, down here on the left? It's gray, so people miss it. Make it the primary button and put it on the right, next to Cancel."
ffmpeg -v error -f lavfi -i "testsrc=size=1440x900:rate=10:duration=12" -i "$TMP/n.aiff" \
  -t 12 -c:v libx264 -pix_fmt yuv420p -c:a aac "$RAW/seg_001.mov"
NOW="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
cat > "$RAW/session.json" <<JSON
{"mode":"window","display":{"x":0,"y":0,"w":1440,"h":900},"windowTitle":"Settings · localhost:5173","createdAt":"$NOW"}
JSON
python3 - "$RAW/events.jsonl" <<'PY'
import json, math, sys
ev = [{"type": "window", "seg": 1, "t": 0, "frame": {"x": 40, "y": 64, "w": 740, "h": 560}, "visible": True},
      {"type": "window", "seg": 1, "t": 6, "frame": {"x": 40, "y": 64, "w": 640, "h": 560}, "visible": True}]
pts = [{"x": 135 + 88 * math.cos(i / 16 * 2 * math.pi), "y": 554 + 40 * math.sin(i / 16 * 2 * math.pi)} for i in range(17)]
ev.append({"type": "stroke", "seg": 1, "t0": 2.8, "t1": 4.0, "points": pts, "tool": "pen"})
ev.append({"type": "cursor", "seg": 1, "t": 4.1, "p": {"x": 135, "y": 554}})
open(sys.argv[1], "w").write("\n".join(json.dumps(e) for e in ev))
PY
rm -rf "$TMP"
echo "$ID"
