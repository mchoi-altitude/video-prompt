#!/usr/bin/env bash
# Builds out/VideoPrompt-linux-beta.tar.gz: the app, its Electron, whisper-cli and install.sh.
# Needs Node, ffmpeg, git, cmake and g++. Run from anywhere. Publishes nothing.
set -euo pipefail

WHISPER_TAG=v1.9.5
cd "$(dirname "$(readlink -f "$0")")/.."

npm ci
npx electron --version >/dev/null  # npm ci leaves Electron's program to be downloaded on first use
npm test

# A portable whisper-cli: the default build is tuned to this machine's CPU and can crash on another.
# AVX2 keeps transcription fast, and install.sh checks that the program runs on the target machine.
[ -d vendor/whisper.cpp ] || git -c advice.detachedHead=false clone -q --depth 1 --branch "$WHISPER_TAG" \
  https://github.com/ggml-org/whisper.cpp.git vendor/whisper.cpp
cmake -S vendor/whisper.cpp -B vendor/whisper.cpp/build-portable -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=OFF \
  -DGGML_NATIVE=OFF -DGGML_AVX=ON -DGGML_AVX2=ON -DGGML_FMA=ON -DGGML_F16C=ON -DWHISPER_BUILD_TESTS=OFF >/dev/null
cmake --build vendor/whisper.cpp/build-portable --target whisper-cli -j"$(nproc)" >/dev/null

STAGE=out/video-prompt-linux-beta
rm -rf out
mkdir -p "$STAGE"
cp scripts/install.sh "$STAGE/"
cp -r node_modules/electron/dist "$STAGE/video-prompt"

APP="$STAGE/video-prompt/resources/app"
mkdir -p "$APP/vendor/bin"
cp package.json ../LICENSE "$APP/"
cp -r dist bin "$APP/"
rm -rf "$APP/dist/test"
cp vendor/whisper.cpp/build-portable/bin/whisper-cli "$APP/vendor/bin/"
cp vendor/whisper.cpp/LICENSE "$APP/vendor/bin/whisper.cpp-LICENSE"
strip "$APP/vendor/bin/whisper-cli"

# The launcher icon, from the same drawing code as the tray.
node -e 'process.stdout.write(require("./dist/main/icon.js").appBitmap(256))' \
  | ffmpeg -v error -y -f rawvideo -pix_fmt bgra -s 256x256 -i - -frames:v 1 -update 1 "$STAGE/video-prompt.png"

tar -C out -czf out/VideoPrompt-linux-beta.tar.gz video-prompt-linux-beta
ls -la out/VideoPrompt-linux-beta.tar.gz
