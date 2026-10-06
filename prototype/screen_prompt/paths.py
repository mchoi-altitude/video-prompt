"""Where recordings and settings live, plus small JSON helpers."""

import json
import os
import sys
import time
from pathlib import Path


def data_dir() -> Path:
    if os.environ.get("SCREEN_PROMPT_HOME"):
        base = Path(os.environ["SCREEN_PROMPT_HOME"]).expanduser()
    elif sys.platform == "darwin":
        base = Path.home() / "Library" / "Application Support" / "screen-prompt"
    else:
        xdg = os.environ.get("XDG_DATA_HOME") or str(Path.home() / ".local" / "share")
        base = Path(xdg) / "screen-prompt"
    base.mkdir(parents=True, exist_ok=True)
    return base


def recordings_dir() -> Path:
    d = data_dir() / "recordings"
    d.mkdir(parents=True, exist_ok=True)
    return d


def new_recording_dir() -> Path:
    stamp = time.strftime("%Y%m%d-%H%M%S")
    d = recordings_dir() / stamp
    n = 1
    while d.exists():
        n += 1
        d = recordings_dir() / f"{stamp}-{n}"
    (d / "segments").mkdir(parents=True)
    return d


def read_json(path: Path, default=None):
    try:
        return json.loads(Path(path).read_text())
    except (OSError, ValueError):
        return default


def write_json(path: Path, data) -> None:
    """Write atomically so readers (the MCP server) never see a half-written file."""
    path = Path(path)
    tmp = path.with_suffix(path.suffix + ".tmp")
    tmp.write_text(json.dumps(data, indent=2))
    os.replace(tmp, path)


def load_config() -> dict:
    return read_json(data_dir() / "config.json", {}) or {}


def save_config(cfg: dict) -> None:
    write_json(data_dir() / "config.json", cfg)
