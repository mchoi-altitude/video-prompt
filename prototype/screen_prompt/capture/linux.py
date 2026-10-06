"""Linux capture: xdg-desktop-portal ScreenCast -> PipeWire -> gst-launch.

Wayland compositors don't let apps read the screen directly. The ScreenCast portal shows
the system "share your screen" dialog and then hands us a PipeWire stream. With
persist_mode the compositor (KDE, GNOME) remembers the choice, so the dialog only
appears the first time.
"""

import os
import secrets
import subprocess

from .. import paths
from .base import CaptureBackend, CaptureCancelled, CaptureError, SegmentProcess, Target

PORTAL = "org.freedesktop.portal.Desktop"
PORTAL_PATH = "/org/freedesktop/portal/desktop"
SCREENCAST = "org.freedesktop.portal.ScreenCast"

SOURCE_MONITOR = 1
CURSOR_EMBEDDED = 2
PERSIST_UNTIL_REVOKED = 2

FPS = 15


ENCODERS = [
    "x264enc tune=zerolatency speed-preset=veryfast bitrate=4000 key-int-max=30 ! h264parse",
    "openh264enc bitrate=4000000 ! h264parse",
    "vp8enc deadline=1 cpu-used=8 target-bitrate=4000000 threads=4",
]


def _encoder_works(enc: str) -> bool:
    # Actually encode a few frames: Fedora ships a stub OpenH264 whose plugin loads but can't encode.
    test = f"videotestsrc num-buffers=5 ! video/x-raw,width=320,height=240 ! videoconvert ! {enc} ! fakesink"
    try:
        return subprocess.run(["gst-launch-1.0", "-q", test], capture_output=True, timeout=20).returncode == 0
    except subprocess.TimeoutExpired:
        return False


def _video_encoder() -> str:
    for enc in ENCODERS:
        if _encoder_works(enc):
            return enc
    raise CaptureError(
        "No video encoder found for GStreamer (need x264enc, openh264enc or vp8enc). "
        "On Fedora: sudo dnf install gstreamer1-plugin-openh264"
    )


class Portal:
    """Minimal synchronous client for the ScreenCast portal (call from a worker thread)."""

    def __init__(self):
        import gi

        gi.require_version("Gio", "2.0")
        from gi.repository import Gio, GLib

        self.Gio, self.GLib = Gio, GLib
        self.bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)
        self.sender = self.bus.get_unique_name()[1:].replace(".", "_")
        self.session = None

    def _prop(self, name):
        try:
            v = self.bus.call_sync(
                PORTAL, PORTAL_PATH, "org.freedesktop.DBus.Properties", "Get",
                self.GLib.Variant("(ss)", (SCREENCAST, name)),
                None, self.Gio.DBusCallFlags.NONE, 5000, None,
            )
            return v.unpack()[0]
        except Exception:
            return None

    def _request(self, method, signature, args, options):
        """Call a portal method that answers asynchronously via a Request.Response signal."""
        GLib = self.GLib
        token = "sp" + secrets.token_hex(6)
        request_path = f"/org/freedesktop/portal/desktop/request/{self.sender}/{token}"
        options = dict(options, handle_token=GLib.Variant("s", token))

        ctx = GLib.MainContext.new()
        ctx.push_thread_default()
        box = {}
        try:
            # Subscribe before calling, so a fast reply can't be missed.
            sub = self.bus.signal_subscribe(
                None, "org.freedesktop.portal.Request", "Response", request_path, None,
                self.Gio.DBusSignalFlags.NONE,
                lambda *a: box.setdefault("r", a[5].unpack()),
            )
            try:
                self.bus.call_sync(
                    PORTAL, PORTAL_PATH, SCREENCAST, method,
                    GLib.Variant(signature, (*args, options)),
                    None, self.Gio.DBusCallFlags.NONE, -1, None,
                )
                # No timeout: the user may take a while in the screen picker.
                while "r" not in box:
                    ctx.iteration(True)
            finally:
                self.bus.signal_unsubscribe(sub)
        finally:
            ctx.pop_thread_default()

        code, results = box["r"]
        if code == 1:
            raise CaptureCancelled()
        if code != 0:
            raise CaptureError(f"Screen-share portal {method} failed (code {code})")
        return results

    def start(self, restore_token=None):
        GLib = self.GLib
        version = self._prop("version") or 1
        cursor_modes = self._prop("AvailableCursorModes") or 0

        res = self._request(
            "CreateSession", "(a{sv})", (),
            {"session_handle_token": GLib.Variant("s", "sps" + secrets.token_hex(6))},
        )
        self.session = res["session_handle"]

        opts = {
            "types": GLib.Variant("u", SOURCE_MONITOR),
            "multiple": GLib.Variant("b", False),
        }
        if cursor_modes & CURSOR_EMBEDDED:
            opts["cursor_mode"] = GLib.Variant("u", CURSOR_EMBEDDED)
        if version >= 4:
            opts["persist_mode"] = GLib.Variant("u", PERSIST_UNTIL_REVOKED)
            if restore_token:
                opts["restore_token"] = GLib.Variant("s", restore_token)
        self._request("SelectSources", "(oa{sv})", (self.session,), opts)

        res = self._request("Start", "(osa{sv})", (self.session, ""), {})
        streams = res.get("streams") or []
        if not streams:
            raise CaptureError("The portal returned no screen stream")
        node_id, props = streams[0]

        ret, fds = self.bus.call_with_unix_fd_list_sync(
            PORTAL, PORTAL_PATH, SCREENCAST, "OpenPipeWireRemote",
            GLib.Variant("(oa{sv})", (self.session, {})),
            GLib.VariantType.new("(h)"), self.Gio.DBusCallFlags.NONE, -1, None, None,
        )
        fd = fds.get(ret.unpack()[0])
        return fd, node_id, props, res.get("restore_token")

    def close(self):
        if not self.session:
            return
        try:
            self.bus.call_sync(
                PORTAL, self.session, "org.freedesktop.portal.Session", "Close",
                None, None, self.Gio.DBusCallFlags.NONE, 5000, None,
            )
        except Exception:
            pass
        self.session = None


class LinuxBackend(CaptureBackend):
    def __init__(self):
        self.portal = None
        self.fd = None
        self.node_id = None
        # For tests without a desktop: SCREEN_PROMPT_FAKE_SOURCE=1 records a test pattern.
        self.fake = os.environ.get("SCREEN_PROMPT_FAKE_SOURCE") == "1"
        self.encoder = _video_encoder()

    def prepare(self, mode, screen_index):
        if self.fake:
            return Target()
        self.portal = Portal()
        cfg = paths.load_config()
        token = cfg.get("portal_restore_token")
        try:
            fd, node_id, props, new_token = self.portal.start(token)
        except CaptureError:
            if not token:
                raise
            # A stale restore token can make the portal fail; retry with a fresh dialog.
            self.portal.close()
            self.portal = Portal()
            fd, node_id, props, new_token = self.portal.start(None)
        if new_token and new_token != token:
            cfg["portal_restore_token"] = new_token
            paths.save_config(cfg)
        self.fd, self.node_id = fd, node_id
        return Target(position=props.get("position"), size=props.get("size"), extra={"node_id": node_id})

    def _pipeline(self, path):
        if self.fake:
            video = "videotestsrc is-live=true pattern=ball ! video/x-raw,width=1280,height=720"
        else:
            video = (
                f"pipewiresrc fd={self.fd} path={self.node_id} do-timestamp=true keepalive-time=1000"
                # Plain video/x-raw (system memory) keeps it off DMA-BUF, which videoconvert can't read.
                " ! video/x-raw"
            )
        desc = (
            f"{video} ! videoconvert ! videorate ! video/x-raw,format=I420,framerate={FPS}/1"
            f" ! queue max-size-time=3000000000 ! {self.encoder} ! queue"
            f' ! matroskamux name=mux ! filesink location="{path}"'
        )
        if os.environ.get("SCREEN_PROMPT_NO_AUDIO") != "1":
            audio = "audiotestsrc is-live=true wave=silence" if self.fake else "pulsesrc do-timestamp=true"
            desc += (
                f" {audio} ! audioconvert ! audioresample ! audio/x-raw,rate=48000,channels=1"
                " ! queue ! opusenc ! queue ! mux."
            )
        return desc

    def start_segment(self, path, on_started, on_exit):
        fds = ()
        if not self.fake:
            # Give the child its own copy; gst closes it when the segment ends.
            child_fd = os.dup(self.fd)
            os.set_inheritable(child_fd, True)
            fds = (child_fd,)
            saved, self.fd = self.fd, child_fd
        try:
            cmd = ["gst-launch-1.0", "-e", self._pipeline(path)]
            seg = SegmentProcess(
                cmd,
                started_marker=lambda line: line.startswith("New clock") or "Redistribute latency" in line,
                on_started=on_started,
                on_exit=on_exit,
                pass_fds=fds,
            )
        finally:
            if fds:
                self.fd = saved
                os.close(child_fd)
        return seg

    def close(self):
        if self.fd is not None:
            os.close(self.fd)
            self.fd = None
        if self.portal:
            self.portal.close()
            self.portal = None
