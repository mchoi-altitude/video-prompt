# Installs or updates Video Prompt for the current user, from the unpacked release archive.
# Needs no admin rights. -Uninstall removes the app but keeps your recordings.
param([switch]$NoLaunch, [switch]$Uninstall)
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

$App = Join-Path $env:LOCALAPPDATA "Programs\VideoPrompt"
$Data = if ($env:VIDEO_PROMPT_HOME) { $env:VIDEO_PROMPT_HOME } else { Join-Path $env:LOCALAPPDATA "VideoPrompt" }
$Model = Join-Path $Data "models\ggml-base.en.bin"
$ModelUrl = "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.en.bin"
$ModelSha256 = "a03779c86df3323075f5e796cb2ce5029f00ec8869eee3fdfb897afe36c6d002"
$Shortcut = Join-Path ([Environment]::GetFolderPath("Programs")) "Video Prompt.lnk"

function Stop-App {
  Get-Process electron -ErrorAction SilentlyContinue | Where-Object { $_.Path -eq (Join-Path $App "electron.exe") } | Stop-Process -Force
  Start-Sleep -Milliseconds 500
}

function Test-Model {
  (Test-Path $Model) -and ((Get-FileHash $Model -Algorithm SHA256).Hash -ieq $ModelSha256)
}

if ($Uninstall) {
  Stop-App
  Remove-Item $App -Recurse -Force -ErrorAction SilentlyContinue
  Remove-Item $Shortcut -Force -ErrorAction SilentlyContinue
  Write-Host "Uninstalled. Your recordings and the speech model are still in $Data."
  exit 0
}

$Here = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not (Test-Path (Join-Path $Here "video-prompt\electron.exe"))) { throw "Run this from the unpacked archive." }

Write-Host "1/3 App"
Stop-App
if (Test-Path $App) { Remove-Item $App -Recurse -Force }
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $App) | Out-Null
Copy-Item (Join-Path $Here "video-prompt") $App -Recurse
Copy-Item (Join-Path $Here "video-prompt.ico") $App
Write-Host "    installed to $App"

Write-Host "2/3 Speech model (148 MB)"
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Model) | Out-Null
if (Test-Model) {
  Write-Host "    already downloaded"
} else {
  Invoke-WebRequest -Uri $ModelUrl -OutFile "$Model.part" -UseBasicParsing
  if ((Get-FileHash "$Model.part" -Algorithm SHA256).Hash -ieq $ModelSha256) {
    Move-Item "$Model.part" $Model -Force
    Write-Host "    downloaded and verified"
  } else {
    Remove-Item "$Model.part" -Force
    Write-Warning "Checksum mismatch: not installing the model. Recordings won't have a transcript."
  }
}

Write-Host "3/3 Start menu"
$Link = (New-Object -ComObject WScript.Shell).CreateShortcut($Shortcut)
$Link.TargetPath = Join-Path $App "electron.exe"
$Link.IconLocation = Join-Path $App "video-prompt.ico"
$Link.Description = "Show Claude what you mean by talking and drawing over your screen"
$Link.Save()

if (-not $NoLaunch) { Start-Process (Join-Path $App "electron.exe") }
Write-Host "Done. Video Prompt is in your Start menu, and its icon is in the system tray while it runs."
Write-Host "To uninstall, run: install.cmd -Uninstall"
