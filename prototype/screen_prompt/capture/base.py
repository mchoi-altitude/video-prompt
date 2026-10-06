"""Capture backends record the screen + microphone into one file per segment.

Pausing ends the current segment and resuming starts a new one; the segments are
joined during post-processing. Each segment is an external process (gst-launch on
Linux, ffmpeg on macOS) so a crash there can't take the UI down with it.
"""

import collections
import os
import signal
import subprocess
import threading
from dataclasses import dataclass, field


class CaptureCancelled(Exception):
    """The user dismissed the screen-picker dialog."""


class CaptureError(Exception):
    pass


@dataclass
class Target:
    """What prepare() decided to record."""

    # Position/size of the captured monitor in desktop coordinates, if known.
    # The app uses it to pick which screen to put the drawing overlay on.
    position: tuple[int, int] | None = None
    size: tuple[int, int] | None = None
    extra: dict = field(default_factory=dict)


class SegmentProcess:
    """Runs one capture process and reports when it actually starts producing output.

    `started_marker(line)` decides from the process's output when capture began, so the
    app's clock (used to timestamp drawings and cursor positions) lines up with the video.
    """

    def __init__(self, cmd, started_marker, on_started, on_exit, pass_fds=(), stop_with_q=False):
        self._started_marker = started_marker
        self._on_started = on_started
        self._on_exit = on_exit
        self._stop_with_q = stop_with_q
        self._stopping = False
        self._started = False
        self.tail = collections.deque(maxlen=30)
        self.proc = subprocess.Popen(
            cmd,
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            pass_fds=pass_fds,
            text=True,
            bufsize=1,
            # Own process group, so a Ctrl+C in the launching terminal doesn't hit it.
            start_new_session=True,
        )
        threading.Thread(target=self._read, daemon=True).start()

    def _read(self):
        for raw in self.proc.stdout:
            line = raw.rstrip()
            if not line:
                continue
            self.tail.append(line)
            if not self._started and self._started_marker(line):
                self._started = True
                self._on_started()
        code = self.proc.wait()
        self._on_exit(code, self._started, self._stopping, "\n".join(self.tail))

    def stop(self, timeout=10.0):
        """Ask the process to finish the file cleanly; block until it has."""
        self._stopping = True
        if self.proc.poll() is not None:
            return
        try:
            if self._stop_with_q:
                self.proc.stdin.write("q")
                self.proc.stdin.flush()
            else:
                self.proc.send_signal(signal.SIGINT)
            self.proc.wait(timeout=timeout)
        except (OSError, subprocess.TimeoutExpired):
            self.proc.kill()
            self.proc.wait()


class CaptureBackend:
    """Interface; see linux.py and macos.py."""

    def prepare(self, mode: str, screen_index: int) -> Target:
        """Blocking. May show a system dialog. mode is 'screen' or 'area'."""
        raise NotImplementedError

    def start_segment(self, path, on_started, on_exit) -> SegmentProcess:
        raise NotImplementedError

    def close(self) -> None:
        pass


def which(name: str) -> bool:
    return any(
        os.access(os.path.join(p, name), os.X_OK) for p in os.environ.get("PATH", "").split(os.pathsep)
    )


def make_backend() -> CaptureBackend:
    import sys

    if sys.platform == "darwin":
        from .macos import MacBackend

        return MacBackend()
    if sys.platform.startswith("linux"):
        from .linux import LinuxBackend

        return LinuxBackend()
    raise CaptureError(f"Unsupported platform: {sys.platform}")
