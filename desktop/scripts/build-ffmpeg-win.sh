#!/usr/bin/env bash
# Builds the ffmpeg.exe and ffprobe.exe that the Windows installer bundles: LGPL, statically linked with
# mingw-w64, and containing only what the app and its tests use (VP8/VP9 through libvpx, Opus, JPEG, WAV).
# No H.264, HEVC or AAC encoder or decoder is built in, so the installer ships none of its own.
# Runs on Ubuntu: CI (.github/workflows/ffmpeg-windows.yml) or WSL. Needs: gcc mingw-w64 nasm pkgconf make zip xz-utils curl git.
# Usage: build-ffmpeg-win.sh <work dir> <output dir>
# Output: <name>.zip (bin/, licenses/, BUILD-INFO.txt), the source tarballs, this script, SHA256SUMS.txt
# and TAG (the release tag to publish under, which is also <name>).
set -euo pipefail

FFMPEG_VERSION=9.0.2
# Checked once against the signature from FFmpeg's release key FCF9 86EA 15E6 E293 A564 4F10 B432 2F04 D676 58D8.
FFMPEG_SHA256=8c3850283eb25fa026482078a04051e0be17347b09ef81a0849bec15a96e002e
LIBVPX_VERSION=1.17.0
LIBVPX_COMMIT=6df3ec34557879fff673706f4a1d9fbd0f3a6f0e
OPUS_VERSION=1.6.1
OPUS_SHA256=6ffcb593207be92584df15b32466ed64bbec99109f007c82205f0194572411a1
# Bump to rebuild the same versions differently. Each release tag is published once and never replaced.
BUILD=1

HOST=x86_64-w64-mingw32
NAME=ffmpeg-win64-$FFMPEG_VERSION-$BUILD

# Only what the app and its tests use. Adding a feature that needs more means adding it here and bumping BUILD.
COMPONENTS=(
  --enable-protocol=file,pipe
  --enable-indev=lavfi                                    # tests: -f lavfi testsrc2, sine, color
  --enable-demuxer=matroska,mov,image2,image_jpeg_pipe    # recorder's WebM segments, video.mp4, test JPEGs
  --enable-muxer=mp4,webm,wav,image2,null                 # video.mp4, test segments, audio.wav, JPEGs, -f null
  --enable-decoder=vp8,vp9,opus,mjpeg,wrapped_avframe,pcm_s16le  # the last two: lavfi sources (tests)
  --enable-encoder=libvpx_vp8,libvpx_vp9,libopus,mjpeg,pcm_s16le,wrapped_avframe
  --enable-parser=vp8,vp9,opus,mjpeg
  --enable-bsf=vp9_superframe,vp9_superframe_split        # mp4 muxer and vp9 decoder need these for VP9
  # processor.ts renderVideo and makeOverview, frames/main.ts, test sources, and filters ffmpeg inserts itself
  --enable-filter=fps,tpad,trim,setpts,crop,scale,format,setsar,aresample,apad,atrim,asetpts,concat,tile,null,anull,aformat,testsrc2,sine,color
)

[ $# -eq 2 ] || { echo "usage: $0 <work dir> <output dir>" >&2; exit 2; }
for t in gcc "$HOST-gcc" nasm pkg-config make zip xz curl git; do
  command -v "$t" >/dev/null || { echo "missing $t: sudo apt-get install -y gcc mingw-w64 nasm pkgconf make zip xz-utils curl git" >&2; exit 1; }
done
SCRIPT=$(readlink -f "$0")
mkdir -p "$1" "$2"
WORK=$(cd "$1" && pwd)
OUT=$(cd "$2" && pwd)
SRC=$WORK/src
PREFIX=$WORK/prefix
JOBS=$(nproc)
rm -rf "$SRC" "$PREFIX" "$WORK/ffmpeg-build" "$WORK/stage"
mkdir -p "$SRC" "$PREFIX" "$WORK/downloads" "$WORK/stage"

fetch() { # file url sha256: downloads once into work/downloads, checksum-verified. A copy already there is reused.
  local f=$WORK/downloads/$1
  if [ -f "$f" ] && echo "$3  $f" | sha256sum -c --status; then return; fi
  curl -fsSL --retry 5 --retry-all-errors --connect-timeout 30 -o "$f.part" "$2"
  if ! echo "$3  $f.part" | sha256sum -c --status; then
    echo "$1: checksum mismatch (got $(sha256sum "$f.part" | cut -d' ' -f1))" >&2
    rm -f "$f.part"
    exit 1
  fi
  mv "$f.part" "$f"
}

echo "== sources"
fetch "ffmpeg-$FFMPEG_VERSION.tar.xz" "https://ffmpeg.org/releases/ffmpeg-$FFMPEG_VERSION.tar.xz" "$FFMPEG_SHA256"
fetch "opus-$OPUS_VERSION.tar.gz" "https://downloads.xiph.org/releases/opus/opus-$OPUS_VERSION.tar.gz" "$OPUS_SHA256"
tar -xJf "$WORK/downloads/ffmpeg-$FFMPEG_VERSION.tar.xz" -C "$SRC"
tar -xzf "$WORK/downloads/opus-$OPUS_VERSION.tar.gz" -C "$SRC"
# libvpx publishes no release tarballs, and GitHub's generated archives can change, so pin the commit.
git -c advice.detachedHead=false clone -q --depth 1 --branch "v$LIBVPX_VERSION" https://chromium.googlesource.com/webm/libvpx "$SRC/libvpx"
got=$(git -C "$SRC/libvpx" rev-parse HEAD)
[ "$got" = "$LIBVPX_COMMIT" ] || { echo "libvpx v$LIBVPX_VERSION is $got, expected $LIBVPX_COMMIT" >&2; exit 1; }
git -C "$SRC/libvpx" archive --prefix="libvpx-$LIBVPX_VERSION/" -o "$WORK/downloads/libvpx-$LIBVPX_VERSION.tar.gz" HEAD

echo "== opus"
(
  cd "$SRC/opus-$OPUS_VERSION"
  # No stack protector: it would need libssp, an extra runtime to ship.
  ./configure -q --host="$HOST" --prefix="$PREFIX" --enable-static --disable-shared \
    --disable-doc --disable-extra-programs --disable-stack-protector
  make -s -j"$JOBS"
  make -s install
)

echo "== libvpx"
(
  cd "$SRC/libvpx"
  # Encoders only: ffmpeg decodes VP8 and VP9 with its own decoders.
  CROSS="$HOST-" ./configure --target=x86_64-win64-gcc --prefix="$PREFIX" --as=nasm \
    --enable-static --disable-shared --disable-examples --disable-tools --disable-docs --disable-unit-tests \
    --disable-vp8-decoder --disable-vp9-decoder >/dev/null
  make -s -j"$JOBS"
  make -s install >/dev/null
)

echo "== ffmpeg"
CONFIGURE=(
  --prefix="$PREFIX" --arch=x86_64 --target-os=mingw32 --cross-prefix="$HOST-" --enable-cross-compile
  --pkg-config=pkg-config --pkg-config-flags=--static
  --extra-cflags="-I$PREFIX/include" --extra-ldflags="-L$PREFIX/lib -static -Wl,--no-insert-timestamp"
  --extra-version="video-prompt-$BUILD"
  --disable-shared --enable-static --disable-doc --disable-ffplay --disable-debug
  # No --enable-gpl, --enable-version3 or --enable-nonfree: the result is LGPL v2.1 or later.
  # --disable-autodetect keeps out everything not asked for, including Windows' and GPU vendors' codecs.
  --disable-autodetect --enable-w32threads --disable-network
  --disable-everything --enable-libvpx --enable-libopus
  "${COMPONENTS[@]}"
)
mkdir -p "$WORK/ffmpeg-build"
(
  cd "$WORK/ffmpeg-build"
  PKG_CONFIG_LIBDIR="$PREFIX/lib/pkgconfig" "$SRC/ffmpeg-$FFMPEG_VERSION/configure" "${CONFIGURE[@]}" >configure.log ||
    { tail -30 configure.log; tail -40 ffbuild/config.log; exit 1; }
  make -s -j"$JOBS"
)
B=$WORK/ffmpeg-build

echo "== checks"
# What got built, from ffmpeg's own build config: fail early on anything patented.
grep -E '^#define CONFIG_[A-Z0-9_]+_(ENCODER|DECODER|DEMUXER|MUXER|PARSER|BSF|FILTER|PROTOCOL|INDEV|OUTDEV) 1' \
  "$B/config_components.h" | awk '{print $2}' | sed 's/^CONFIG_//' | sort >"$WORK/components.txt"
if grep -iE '^(.*(H26[3456]|HEVC|VVC|AAC|X26[45]|OPENH264|NVENC|AMF|QSV|_MF|CUVID|D3D1[12]VA|DXVA|VAAPI|VULKAN).*_(ENCODER|DECODER))$' "$WORK/components.txt"; then
  echo "patented codec built in (above)" >&2
  exit 1
fi
# The exes must run on a plain Windows: only Windows' own DLLs, no mingw runtime DLLs.
for exe in ffmpeg.exe ffprobe.exe; do
  dlls=$("$HOST-objdump" -p "$B/$exe" | awk '/DLL Name:/ {print $3}' | sort -u)
  echo "$exe imports: $(echo $dlls)"
  bad=$(echo "$dlls" | grep -viE '^(KERNEL32|msvcrt|ADVAPI32|SHELL32|USER32|ole32|bcrypt|api-ms-win-[a-z0-9-]+)\.dll$' || true)
  [ -z "$bad" ] || { echo "$exe needs non-system DLLs: $bad" >&2; exit 1; }
done

echo "== package"
S=$WORK/stage/$NAME
mkdir -p "$S/bin" "$S/licenses"
cp "$B/ffmpeg.exe" "$B/ffprobe.exe" "$S/bin/"
cp "$SRC/ffmpeg-$FFMPEG_VERSION/COPYING.LGPLv2.1" "$S/licenses/ffmpeg-COPYING.LGPLv2.1.txt"
cp "$SRC/ffmpeg-$FFMPEG_VERSION/LICENSE.md" "$S/licenses/ffmpeg-LICENSE.md"
cp "$SRC/libvpx/LICENSE" "$S/licenses/libvpx-LICENSE.txt"
cp "$SRC/libvpx/PATENTS" "$S/licenses/libvpx-PATENTS.txt"
cp "$SRC/opus-$OPUS_VERSION/COPYING" "$S/licenses/opus-COPYING.txt"
# The mingw-w64 runtime (startup code, winpthreads) is linked into the exes.
for f in /usr/share/doc/mingw-w64-x86-64-dev/copyright /usr/share/doc/mingw-w64-common/copyright; do
  [ -f "$f" ] && { cat "$f"; echo; }
done >"$S/licenses/mingw-w64-runtime.txt"
[ -s "$S/licenses/mingw-w64-runtime.txt" ] || { echo "mingw-w64 copyright notice not found" >&2; exit 1; }

COMMIT=$(git -C "$(dirname "$SCRIPT")" rev-parse HEAD 2>/dev/null || echo unknown)
{
  echo "Video Prompt's ffmpeg for Windows: $NAME"
  echo
  echo "FFmpeg $FFMPEG_VERSION (LGPL v2.1 or later), statically linked with libvpx $LIBVPX_VERSION (BSD) and"
  echo "Opus $OPUS_VERSION (BSD). It contains no H.264, HEVC or AAC encoder or decoder."
  echo "Note: 'ffmpeg -codecs' still lists h264 and aac. That list is ffmpeg's table of codec names, not code"
  echo "that can encode or decode them; 'ffmpeg -encoders' and 'ffmpeg -decoders' show what is built in."
  echo
  echo "Source code: attached to the GitHub release $NAME of mchoi-altitude/video-prompt:"
  echo "  ffmpeg-$FFMPEG_VERSION.tar.xz  sha256 $FFMPEG_SHA256 (https://ffmpeg.org/releases/)"
  echo "  libvpx-$LIBVPX_VERSION.tar.gz  git commit $LIBVPX_COMMIT (https://chromium.googlesource.com/webm/libvpx)"
  echo "  opus-$OPUS_VERSION.tar.gz  sha256 $OPUS_SHA256 (https://downloads.xiph.org/releases/opus/)"
  echo "Built by desktop/scripts/build-ffmpeg-win.sh (also attached) at commit $COMMIT:"
  echo "  https://github.com/mchoi-altitude/video-prompt/blob/$COMMIT/desktop/scripts/build-ffmpeg-win.sh"
  echo "Toolchain: $("$HOST-gcc" --version | head -1); NASM $(nasm -v | awk '{print $3}'); $( (lsb_release -ds 2>/dev/null || uname -sr) )"
  echo
  echo "Configure: ${CONFIGURE[*]}" | sed "s|$WORK|<work>|g"
  echo
  echo "Built-in components:"
  sed 's/^/  /' "$WORK/components.txt"
} >"$S/BUILD-INFO.txt"

rm -f "$OUT/$NAME.zip"
(cd "$WORK/stage" && zip -qrX "$OUT/$NAME.zip" "$NAME")
cp "$WORK/downloads/ffmpeg-$FFMPEG_VERSION.tar.xz" "$WORK/downloads/opus-$OPUS_VERSION.tar.gz" \
  "$WORK/downloads/libvpx-$LIBVPX_VERSION.tar.gz" "$SCRIPT" "$S/BUILD-INFO.txt" "$OUT/"
echo "$NAME" >"$OUT/TAG"
(cd "$OUT" && sha256sum "$NAME.zip" "ffmpeg-$FFMPEG_VERSION.tar.xz" "libvpx-$LIBVPX_VERSION.tar.gz" \
  "opus-$OPUS_VERSION.tar.gz" build-ffmpeg-win.sh >SHA256SUMS.txt)

echo "== done: $OUT/$NAME.zip"
ls -l "$S/bin"
cat "$OUT/SHA256SUMS.txt"
