"""Turn a finished recording into something Claude can read.

Claude takes images and text, not video, so a recording becomes:
  recording.mp4    (or .webm) the joined (and cropped) video, for humans
  transcript.json  narration with timestamps (local Whisper)
  frames/*.jpg     keyframes: scene changes, finished drawings, and moments of speech
  manifest.json    everything above plus drawings/cursor, on one timeline
  prompt.md        the same timeline as Markdown, for @-mentioning in Claude Code
"""

import argparse
import json
import math
import os
import re
import subprocess
import sys
from pathlib import Path

from . import paths

MAX_FRAMES = int(os.environ.get("SCREEN_PROMPT_MAX_FRAMES", "24"))
MIN_FRAME_GAP = 1.5  # seconds between chosen keyframes
FRAME_LONG_EDGE = 1568  # Claude's recommended max image size
SCENE_THRESHOLD = 0.1
WHISPER_MODEL = os.environ.get("SCREEN_PROMPT_WHISPER_MODEL", "small")


def _run(cmd, **kw):
    return subprocess.run(cmd, capture_output=True, text=True, **kw)


def _probe(path):
    r = _run(["ffprobe", "-v", "error", "-print_format", "json", "-show_format", "-show_streams", str(path)])
    if r.returncode != 0:
        return None
    info = json.loads(r.stdout)
    try:
        duration = float(info["format"]["duration"])
    except (KeyError, ValueError):
        return None
    video = next((s for s in info["streams"] if s["codec_type"] == "video"), None)
    if not video:
        return None
    return {
        "duration": duration,
        "width": int(video["width"]),
        "height": int(video["height"]),
        "has_audio": any(s["codec_type"] == "audio" for s in info["streams"]),
    }


# (output file, video args, audio args), best first. Each is test-encoded before use, because
# an encoder can be listed but unusable (e.g. Fedora's stub OpenH264).
CODECS = [
    ("recording.mp4", ["-c:v", "libx264", "-preset", "veryfast", "-crf", "23"], ["-c:a", "aac", "-b:a", "96k"]),
    ("recording.mp4", ["-c:v", "h264_videotoolbox", "-b:v", "4M"], ["-c:a", "aac", "-b:a", "96k"]),
    ("recording.mp4", ["-c:v", "libopenh264", "-b:v", "3M"], ["-c:a", "aac", "-b:a", "96k"]),
    ("recording.webm", ["-c:v", "libvpx-vp9", "-deadline", "realtime", "-cpu-used", "8", "-b:v", "2M", "-row-mt", "1"],
     ["-c:a", "libopus", "-b:a", "64k"]),
    ("recording.webm", ["-c:v", "libvpx", "-deadline", "realtime", "-cpu-used", "8", "-b:v", "3M"],
     ["-c:a", "libopus", "-b:a", "64k"]),
]


def _pick_codec():
    for name, vargs, aargs in CODECS:
        r = _run(["ffmpeg", "-v", "error", "-f", "lavfi", "-i", "testsrc2=size=320x240:duration=0.2",
                  "-pix_fmt", "yuv420p", *vargs, "-f", "null", "-"])
        if r.returncode == 0:
            return name, vargs, aargs
    raise RuntimeError("ffmpeg has no working video encoder (tried H.264, VP9, VP8).")


def _even(x):
    return max(2, int(x) // 2 * 2)


def join_segments(rec: Path, segments, region):
    """Concatenate segments, crop to the selected area, and write recording.mp4."""
    w, h = segments[0]["width"], segments[0]["height"]
    with_audio = all(s["has_audio"] for s in segments)
    inputs, parts = [], []
    for i, s in enumerate(segments):
        inputs += ["-i", s["path"]]
        parts.append(f"[{i}:v]scale={w}:{h},setsar=1,fps=15[v{i}]")
        if with_audio:
            parts.append(f"[{i}:a]aresample=async=1000,aformat=channel_layouts=mono[a{i}]")
    joined = "".join(f"[v{i}]" + (f"[a{i}]" if with_audio else "") for i in range(len(segments)))
    parts.append(f"{joined}concat=n={len(segments)}:v=1:a={1 if with_audio else 0}[vj]" + ("[aj]" if with_audio else ""))

    if region:
        cw, ch = _even(w * region["w"]), _even(h * region["h"])
        cx, cy = int(w * region["x"]), int(h * region["y"])
        cx, cy = min(cx, w - cw), min(cy, h - ch)
        parts.append(f"[vj]crop={cw}:{ch}:{cx}:{cy},format=yuv420p[vout]")
    else:
        parts.append(f"[vj]scale={_even(w)}:{_even(h)},format=yuv420p[vout]")

    name, vargs, aargs = _pick_codec()
    out = rec / name
    cmd = ["ffmpeg", "-hide_banner", "-v", "error", "-y", *inputs, "-filter_complex", ";".join(parts),
           "-map", "[vout]", *vargs]
    if with_audio:
        cmd += ["-map", "[aj]", *aargs]
    if name.endswith(".mp4"):
        cmd += ["-movflags", "+faststart"]
    cmd.append(str(out))
    r = _run(cmd)
    if r.returncode != 0:
        raise RuntimeError(f"ffmpeg failed joining segments:\n{r.stderr[-2000:]}")
    return out, with_audio


def transcribe(rec: Path, video: Path, progress):
    wav = rec / "audio.wav"
    r = _run(["ffmpeg", "-v", "error", "-y", "-i", str(video), "-vn", "-ac", "1", "-ar", "16000", str(wav)])
    if r.returncode != 0:
        return []
    progress(f"Transcribing ({WHISPER_MODEL} model)…")
    from faster_whisper import WhisperModel

    import wave

    import numpy as np

    # Hand Whisper raw samples rather than a path, so it doesn't need PyAV to decode
    # (faster-whisper 1.2 breaks with PyAV 19).
    with wave.open(str(wav)) as w:
        samples = np.frombuffer(w.readframes(w.getnframes()), np.int16).astype(np.float32) / 32768.0
    model = WhisperModel(WHISPER_MODEL, device="auto", compute_type="int8")
    segments, _info = model.transcribe(samples, vad_filter=True, beam_size=5, word_timestamps=True)

    # Whisper segments can span many sentences; split at sentence ends so narration
    # interleaves with the frames it describes.
    out, words = [], []

    def flush():
        text = "".join(w.word for w in words).strip()
        if text:
            out.append({"start": round(words[0].start, 2), "end": round(words[-1].end, 2), "text": text})
        words.clear()

    for seg in segments:
        for w in seg.words or []:
            words.append(w)
            if w.word.rstrip().endswith((".", "?", "!")):
                flush()
        flush()
    wav.unlink(missing_ok=True)
    return out


def scene_changes(video: Path):
    r = _run(["ffmpeg", "-hide_banner", "-i", str(video), "-an",
              "-vf", f"scale=480:-2,select='gt(scene,{SCENE_THRESHOLD})',showinfo", "-f", "null", "-"])
    return [float(t) for t in re.findall(r"pts_time:([\d.]+)", r.stderr)]


def choose_frame_times(duration, scenes, strokes, transcript):
    """Pick keyframes by priority, keeping them at least MIN_FRAME_GAP apart."""
    end = max(0.0, duration - 0.3)
    candidates = [(9, 0.5 if duration > 1 else 0.0, "start"), (8, end, "end")]
    candidates += [(5, min(s["end"] + 0.3, end), "drawing") for s in strokes]
    candidates += [(3, min(t + 0.4, end), "scene change") for t in scenes]
    candidates += [(2, min((s["start"] + s["end"]) / 2, end), "narration") for s in transcript]

    chosen = []
    for prio, t, reason in sorted(candidates, key=lambda c: -c[0]):
        near = next((c for c in chosen if abs(c["time"] - t) < MIN_FRAME_GAP), None)
        if near:
            if reason not in near["reasons"]:
                near["reasons"].append(reason)
            continue
        if len(chosen) >= MAX_FRAMES:
            continue
        chosen.append({"time": round(t, 2), "reasons": [reason]})
    return sorted(chosen, key=lambda c: c["time"])


def frame_size(w, h):
    scale = min(1.0, FRAME_LONG_EDGE / max(w, h))
    return _even(w * scale), _even(h * scale)


def extract_frames(rec: Path, video: Path, frames, fw, fh):
    fdir = rec / "frames"
    fdir.mkdir(exist_ok=True)
    for i, f in enumerate(frames, 1):
        t = f["time"]
        name = f"frame_{i:02d}_{int(t // 60):02d}m{t % 60:04.1f}s.jpg"
        out = fdir / name
        _run(["ffmpeg", "-v", "error", "-y", "-ss", str(t), "-i", str(video), "-frames:v", "1",
              "-vf", f"scale={fw}:{fh}", "-q:v", "3", str(out)])
        f["index"] = i
        f["path"] = str(out)


def _to_frame_px(pt, region, fw, fh):
    """Screen fraction -> pixel in the (cropped, scaled) frame images, or None if outside."""
    rx, ry, rw, rh = (region["x"], region["y"], region["w"], region["h"]) if region else (0, 0, 1, 1)
    x, y = (pt[0] - rx) / rw, (pt[1] - ry) / rh
    if not (0 <= x <= 1 and 0 <= y <= 1):
        return None
    return [round(x * fw), round(y * fh)]


def describe_stroke(points_px):
    xs, ys = [p[0] for p in points_px], [p[1] for p in points_px]
    bbox = [min(xs), min(ys), max(xs), max(ys)]
    bw, bh = bbox[2] - bbox[0], bbox[3] - bbox[1]
    start, end = points_px[0], points_px[-1]
    gap = math.dist(start, end)
    if len(points_px) > 8 and gap < 0.3 * max(bw, bh, 1) and min(bw, bh) > 15:
        shape = f"circled the area ({bbox[0]},{bbox[1]})–({bbox[2]},{bbox[3]})"
    elif bh < 0.2 * max(bw, 1):
        shape = f"underlined/marked horizontally from ({bbox[0]},{bbox[1]}) to ({bbox[2]},{bbox[3]})"
    else:
        shape = f"drew a line from ({start[0]},{start[1]}) to ({end[0]},{end[1]})"
    return bbox, shape


def map_events(events, offsets, region, fw, fh):
    """Convert per-segment event times to video time and screen fractions to frame pixels."""
    strokes, cursor, clears = [], [], []
    for e in events:
        off = offsets.get(e.get("seg"))
        if off is None:
            continue
        if e["type"] == "stroke":
            pts = [p for p in (_to_frame_px(pt, region, fw, fh) for pt in e["points"]) if p]
            if len(pts) < 2:
                continue
            bbox, shape = describe_stroke(pts)
            strokes.append({"start": round(off + e["t0"], 2), "end": round(off + e["t1"], 2),
                            "color": e.get("color"), "bbox": bbox, "description": shape})
        elif e["type"] == "cursor":
            p = _to_frame_px((e["x"], e["y"]), region, fw, fh)
            if p:
                cursor.append((off + e["t"], p))
        elif e["type"] == "clear":
            clears.append(round(off + e["t"], 2))
    return strokes, sorted(cursor), clears


def _cursor_at(cursor, t):
    best = None
    for ct, p in cursor:
        if ct > t + 0.2:
            break
        if t - ct <= 1.5:
            best = p
    return best


def fmt(t):
    return f"{int(t // 60):02d}:{int(t % 60):02d}"


def build_timeline(frames, transcript, strokes, clears):
    items = [{"time": f["time"], "kind": "frame", "frame": f["index"]} for f in frames]
    items += [{"time": s["start"], "kind": "speech", "end": s["end"], "text": s["text"]} for s in transcript]
    items += [{"time": s["end"], "kind": "drawing", "description": s["description"]} for s in strokes]
    items += [{"time": t, "kind": "clear"} for t in clears]
    order = {"speech": 0, "drawing": 1, "clear": 2, "frame": 3}
    return sorted(items, key=lambda i: (i["time"], order[i["kind"]]))


PREAMBLE = (
    "The user recorded their screen while narrating a request for you. Treat the narration as "
    "their prompt and the frames as what they were looking at and pointing to. Red pen marks in "
    "the frames are annotations the user drew to highlight things; drawing coordinates below are "
    "pixels in the frame images. If the narration is ambiguous, ask before making large changes."
)


def render_markdown(m):
    lines = [
        f"# Screen recording {m['id']} ({fmt(m['duration'])} long)",
        "",
        PREAMBLE,
        "",
        "## What the user said",
        "",
        (" ".join(s["text"] for s in m["transcript"]) or "_(no narration was detected)_"),
        "",
        "## Timeline",
        "",
        f"Frames are {m['frame_size'][0]}×{m['frame_size'][1]} JPEGs. **View each frame image with "
        "your Read tool, in order**, alongside the narration around it.",
        "",
    ]
    frames = {f["index"]: f for f in m["frames"]}
    for item in m["timeline"]:
        t = fmt(item["time"])
        if item["kind"] == "speech":
            lines.append(f"- **[{t}]** 🎙 “{item['text']}”")
        elif item["kind"] == "drawing":
            lines.append(f"- **[{t}]** ✏️ The user {item['description']}")
        elif item["kind"] == "clear":
            lines.append(f"- **[{t}]** The user cleared their drawings")
        else:
            f = frames[item["frame"]]
            extra = f" — cursor at ({f['cursor'][0]},{f['cursor'][1]})" if f.get("cursor") else ""
            lines.append(f"- **[{t}]** 🖼 Frame {f['index']} ({', '.join(f['reasons'])}){extra}: `{f['path']}`")
    lines += ["", f"Full video (for humans): `{m['video']}`", ""]
    return "\n".join(lines)


def process_recording(rec: Path, progress=lambda msg: None) -> Path:
    rec = Path(rec)
    session = paths.read_json(rec / "session.json", {})
    session["status"] = "processing"
    paths.write_json(rec / "session.json", session)
    try:
        progress("Joining video…")
        segments, offsets, offset = [], {}, 0.0
        for i, p in enumerate(session.get("segments", [])):
            info = _probe(p)
            if not info or info["duration"] < 0.2:
                continue
            offsets[i] = offset
            offset += info["duration"]
            segments.append({**info, "path": p})
        region = session.get("region")
        if segments:
            video, has_audio = join_segments(rec, segments, region)
        elif existing := next((p for p in (rec / "recording.mp4", rec / "recording.webm") if _probe(p)), None):
            # Reprocessing after the segments were cleaned up: reuse the joined video.
            video = existing
            has_audio = _probe(video)["has_audio"]
            offsets = {int(k): v for k, v in session.get("segment_offsets", {}).items()}
        else:
            raise RuntimeError("Nothing was recorded (no usable video segments).")
        session["segment_offsets"] = {str(k): v for k, v in offsets.items()}
        vinfo = _probe(video)
        duration = vinfo["duration"]
        fw, fh = frame_size(vinfo["width"], vinfo["height"])

        transcript = transcribe(rec, video, progress) if has_audio else []
        paths.write_json(rec / "transcript.json", transcript)

        progress("Picking keyframes…")
        events = []
        if (rec / "events.jsonl").exists():
            events = [json.loads(l) for l in (rec / "events.jsonl").read_text().splitlines() if l.strip()]
        strokes, cursor, clears = map_events(events, offsets, region, fw, fh)
        frames = choose_frame_times(duration, scene_changes(video), strokes, transcript)
        extract_frames(rec, video, frames, fw, fh)
        for f in frames:
            f["cursor"] = _cursor_at(cursor, f["time"])

        manifest = {
            "id": rec.name,
            "created_at": session.get("created_at"),
            "duration": round(duration, 2),
            "video": str(video),
            "video_size": [vinfo["width"], vinfo["height"]],
            "frame_size": [fw, fh],
            "region": region,
            "transcript": transcript,
            "frames": frames,
            "drawings": strokes,
            "timeline": build_timeline(frames, transcript, strokes, clears),
        }
        paths.write_json(rec / "manifest.json", manifest)
        (rec / "prompt.md").write_text(render_markdown(manifest))

        if os.environ.get("SCREEN_PROMPT_KEEP_SEGMENTS") != "1":
            for s in segments:
                Path(s["path"]).unlink(missing_ok=True)

        session["status"] = "ready"
        paths.write_json(rec / "session.json", session)
        return rec / "prompt.md"
    except Exception as e:
        session["status"] = "failed"
        session["error"] = str(e)
        paths.write_json(rec / "session.json", session)
        raise


def main():
    ap = argparse.ArgumentParser(description="(Re)process a screen-prompt recording directory.")
    ap.add_argument("recording", nargs="?", help="recording directory (default: newest)")
    args = ap.parse_args()
    rec = Path(args.recording) if args.recording else max(paths.recordings_dir().iterdir(), default=None)
    if not rec:
        sys.exit("No recordings found.")
    print(process_recording(rec, progress=print))


if __name__ == "__main__":
    main()
