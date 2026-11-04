# Builds out\VideoPrompt-windows-beta.zip: the app, its Electron, whisper-cli, ffmpeg and the installer.
# Needs Node, ffmpeg and ffprobe on PATH, git, cmake and Visual Studio's C++ tools. Publishes nothing.
$ErrorActionPreference = "Stop"
$WhisperTag = "v1.9.5"
Set-Location (Join-Path $PSScriptRoot "..")

function Run($exe) {
  & $exe @args
  if ($LASTEXITCODE -ne 0) { throw "$exe failed: $args" }
}

Run npm.cmd run build

# Portable: the default build is tuned to this machine's CPU and can crash on another.
if (-not (Test-Path vendor\whisper.cpp)) {
  Run git -c advice.detachedHead=false clone -q --depth 1 --branch $WhisperTag https://github.com/ggml-org/whisper.cpp.git vendor\whisper.cpp
}
Run cmake -S vendor\whisper.cpp -B vendor\whisper.cpp\build-portable -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=OFF `
  -DGGML_NATIVE=OFF -DGGML_AVX=ON -DGGML_AVX2=ON -DGGML_FMA=ON -DGGML_F16C=ON -DWHISPER_BUILD_TESTS=OFF
Run cmake --build vendor\whisper.cpp\build-portable --target whisper-cli --config Release

$Stage = "out\video-prompt-windows-beta"
if (Test-Path out) { Remove-Item out -Recurse -Force }
New-Item -ItemType Directory -Force -Path $Stage | Out-Null
Copy-Item scripts\install.ps1, scripts\install.cmd $Stage
Run npx.cmd electron --version
Copy-Item node_modules\electron\dist "$Stage\video-prompt" -Recurse

$AppDir = "$Stage\video-prompt\resources\app"
New-Item -ItemType Directory -Force -Path "$AppDir\vendor\bin" | Out-Null
Copy-Item package.json, ..\LICENSE $AppDir
Copy-Item dist, bin $AppDir -Recurse
Remove-Item "$AppDir\dist\test" -Recurse -Force
Copy-Item vendor\whisper.cpp\build-portable\bin\Release\whisper-cli.exe "$AppDir\vendor\bin\"
Copy-Item vendor\whisper.cpp\LICENSE "$AppDir\vendor\bin\whisper.cpp-LICENSE"
Copy-Item (Get-Command ffmpeg).Source, (Get-Command ffprobe).Source "$AppDir\vendor\bin\"

# The Start menu icon, from the same drawing code as the tray.
Run node scripts\write-icon.js video-prompt.raw
Run ffmpeg -v error -y -f rawvideo -pix_fmt bgra -s 256x256 -i video-prompt.raw '-frames:v' 1 -update 1 "$Stage\video-prompt.ico"
Remove-Item video-prompt.raw

Compress-Archive -Path $Stage -DestinationPath out\VideoPrompt-windows-beta.zip
Get-Item out\VideoPrompt-windows-beta.zip | Select-Object Name, Length
