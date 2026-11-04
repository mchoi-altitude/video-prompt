#!/usr/bin/env bash
# Installs or updates Video Prompt for the current user, from the unpacked release archive.
# Asks before the one step that needs sudo. --uninstall removes the app but keeps your recordings.
set -euo pipefail

APP_DIR="$HOME/.local/opt/video-prompt"
BIN="$HOME/.local/bin/video-prompt"
DESKTOP_FILE="$HOME/.local/share/applications/video-prompt.desktop"
ICON="$HOME/.local/share/icons/hicolor/256x256/apps/video-prompt.png"
DATA="${VIDEO_PROMPT_HOME:-$HOME/.local/share/VideoPrompt}"
MODEL="$DATA/models/ggml-base.en.bin"
MODEL_URL="https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.en.bin"
MODEL_SHA256="a03779c86df3323075f5e796cb2ce5029f00ec8869eee3fdfb897afe36c6d002"

say() { printf '%s\n' "$*"; }
stop_app() { pkill -f "^$APP_DIR/electron" 2>/dev/null || true; }

if [ "${1:-}" = "--uninstall" ]; then
  stop_app
  rm -rf "$APP_DIR"
  rm -f "$BIN" "$DESKTOP_FILE" "$ICON"
  say "Uninstalled. Your recordings and the speech model are still in $DATA."
  exit 0
fi

HERE="$(dirname "$(readlink -f "$0")")"
[ -x "$HERE/video-prompt/electron" ] || { say "Run this from the unpacked archive." >&2; exit 1; }

encoder_works() {
  for enc in libx264 libopenh264; do
    ffmpeg -v error -f lavfi -i color=s=64x64:r=10:d=0.2 -c:v "$enc" -pix_fmt yuv420p -f null - >/dev/null 2>&1 && return 0
  done
  return 1
}

say "1/4 Video tools"
if command -v ffmpeg >/dev/null && command -v ffprobe >/dev/null && encoder_works; then
  say "    ffmpeg is ready"
else
  say "    Video Prompt needs ffmpeg with a working H.264 encoder."
  if [ -t 0 ] && command -v dnf >/dev/null; then
    read -r -p "    Install it now with: sudo dnf install -y ffmpeg-free openh264 ? [y/N] " answer
    [ "$answer" = "y" ] || [ "$answer" = "Y" ] || { say "    Not installing. Run this again when ffmpeg is installed." >&2; exit 1; }
    sudo dnf install -y ffmpeg-free openh264
  fi
  encoder_works || { say "    ffmpeg still can't encode H.264. On Fedora: sudo dnf install ffmpeg-free openh264" >&2; exit 1; }
fi

say "2/4 App"
stop_app
mkdir -p "$(dirname "$APP_DIR")"
rm -rf "$APP_DIR.new"
cp -r "$HERE/video-prompt" "$APP_DIR.new"
rm -rf "$APP_DIR"
mv "$APP_DIR.new" "$APP_DIR"
WHISPER="$APP_DIR/resources/app/vendor/bin/whisper-cli"
if "$WHISPER" --help >/dev/null 2>&1; then
  say "    installed to $APP_DIR"
else
  say "    Warning: speech-to-text can't run on this computer, so recordings won't have a transcript." >&2
fi

say "3/4 Speech model (148 MB)"
mkdir -p "$DATA/models"
chmod 700 "$DATA"
if [ -f "$MODEL" ] && echo "$MODEL_SHA256  $MODEL" | sha256sum -c --status; then
  say "    already downloaded"
else
  curl -fL --progress-bar -o "$MODEL.part" "$MODEL_URL"
  if echo "$MODEL_SHA256  $MODEL.part" | sha256sum -c --status; then
    mv "$MODEL.part" "$MODEL"
    say "    downloaded and verified"
  else
    rm -f "$MODEL.part"
    say "    Checksum mismatch: not installing the model. Recordings won't have a transcript." >&2
  fi
fi

say "4/4 App launcher"
mkdir -p "$(dirname "$BIN")" "$(dirname "$DESKTOP_FILE")" "$(dirname "$ICON")"
cp "$HERE/video-prompt.png" "$ICON"
cat > "$BIN" <<EOF
#!/bin/sh
exec "$APP_DIR/electron" --ozone-platform=x11 "\$@"
EOF
chmod +x "$BIN"
cat > "$DESKTOP_FILE" <<EOF
[Desktop Entry]
Type=Application
Name=Video Prompt
Comment=Show Claude what you mean by talking and drawing over your screen
Exec="$BIN"
Icon=video-prompt
Terminal=false
Categories=Utility;
StartupWMClass=video-prompt
EOF
command -v update-desktop-database >/dev/null && update-desktop-database -q "$(dirname "$DESKTOP_FILE")" 2>/dev/null || true

if [ "${1:-}" != "--no-launch" ]; then
  setsid "$BIN" >/dev/null 2>&1 < /dev/null &
fi
say "Done. Video Prompt is in your app launcher, and its icon is in the system tray while it runs."
say "To uninstall, run: $(basename "$0") --uninstall"
