"""macOS capture: ffmpeg's avfoundation input (screen + microphone in one process).

The first run triggers macOS's Screen Recording and Microphone permission prompts for
the terminal (or app) that launched screen-prompt; grant both, then restart it.
"""

import os
import re
import subprocess

from .base import CaptureBackend, CaptureError, SegmentProcess, Target, which

FPS = 15


def _list_devices():
    out = subprocess.run(
        ["ffmpeg", "-hide_banner", "-f", "avfoundation", "-list_devices", "true", "-i", ""],
        capture_output=True, text=True,
    ).stderr
    video, audio, section = [], [], None
    for line in out.splitlines():
        if "AVFoundation video devices" in line:
            section = video
        elif "AVFoundation audio devices" in line:
            section = audio
        elif section is not None and (m := re.search(r"\[(\d+)\] (.+)$", line)):
            section.append((int(m.group(1)), m.group(2).strip()))
    return video, audio


def _encoder_args():
    encoders = subprocess.run(["ffmpeg", "-hide_banner", "-encoders"], capture_output=True, text=True).stdout
    if "h264_videotoolbox" in encoders:
        return ["-c:v", "h264_videotoolbox", "-b:v", "6M", "-realtime", "1"]
    if "libx264" in encoders:
        return ["-c:v", "libx264", "-preset", "ultrafast", "-crf", "23"]
    return ["-c:v", "mpeg4", "-q:v", "4"]


class MacBackend(CaptureBackend):
    def __init__(self):
        if not which("ffmpeg"):
            raise CaptureError("ffmpeg not found. Install it with: brew install ffmpeg")
        self.input = None
        self.encoder = _encoder_args()

    def prepare(self, mode, screen_index):
        video, audio = _list_devices()
        screens = [(i, name) for i, name in video if name.startswith("Capture screen")]
        if not screens:
            raise CaptureError(
                "ffmpeg sees no screens. Grant Screen Recording permission to your terminal in "
                "System Settings > Privacy & Security, then restart screen-prompt."
            )
        # avfoundation lists screens in the same order Qt does (main display first).
        vid = screens[min(screen_index, len(screens) - 1)][0]
        if os.environ.get("SCREEN_PROMPT_NO_AUDIO") == "1":
            aud = "none"
        else:
            wanted = os.environ.get("SCREEN_PROMPT_MAC_AUDIO")
            match = [i for i, name in audio if wanted and wanted.lower() in name.lower()]
            aud = str(match[0] if match else (audio[0][0] if audio else "none"))
        self.input = f"{vid}:{aud}"
        return Target(extra={"avfoundation_input": self.input})

    def start_segment(self, path, on_started, on_exit):
        cmd = [
            "ffmpeg", "-hide_banner", "-y",
            "-f", "avfoundation", "-capture_cursor", "1", "-capture_mouse_clicks", "1",
            "-framerate", str(FPS), "-i", self.input,
            *self.encoder, "-pix_fmt", "yuv420p", "-c:a", "aac", "-b:a", "96k",
            str(path),
        ]
        return SegmentProcess(
            cmd,
            started_marker=lambda line: line.startswith("Output #0") or line.startswith("frame="),
            on_started=on_started,
            on_exit=on_exit,
            stop_with_q=True,
        )
