# Drives the installed app with real mouse and keyboard input and takes screenshots, for checking
# on a machine nobody is sitting at. It's a guide for a person looking at the results, not a test.
param([Parameter(Mandatory)] [string]$Exe, [Parameter(Mandatory)] [string]$Ffmpeg, [Parameter(Mandatory)] [string]$Out)
$ErrorActionPreference = "Continue"
New-Item -ItemType Directory -Force -Path $Out | Out-Null

Add-Type -AssemblyName System.Drawing, System.Windows.Forms
Add-Type @"
using System.Runtime.InteropServices;
public static class Input {
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern void mouse_event(uint f, uint x, uint y, uint d, System.UIntPtr e);
  [DllImport("user32.dll")] public static extern void keybd_event(byte k, byte s, uint f, System.UIntPtr e);
  [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
}
"@
[Input]::SetProcessDPIAware() | Out-Null

function Shot($name) {
  $b = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
  $bitmap = New-Object System.Drawing.Bitmap $b.Width, $b.Height
  $g = [System.Drawing.Graphics]::FromImage($bitmap)
  $g.CopyFromScreen($b.Location, [System.Drawing.Point]::Empty, $b.Size)
  $bitmap.Save((Join-Path $Out "$name.png"), [System.Drawing.Imaging.ImageFormat]::Png)
  $g.Dispose(); $bitmap.Dispose()
  Write-Host "shot $name"
}
function Move-To($x, $y) { [Input]::SetCursorPos($x, $y) | Out-Null; Start-Sleep -Milliseconds 40 }
function Press { [Input]::mouse_event(2, 0, 0, 0, [UIntPtr]::Zero); Start-Sleep -Milliseconds 80 }
function Release { [Input]::mouse_event(4, 0, 0, 0, [UIntPtr]::Zero); Start-Sleep -Milliseconds 80 }
function Click($x, $y) { Move-To $x $y; Press; Release }
function Drag($points) {
  Move-To $points[0][0] $points[0][1]; Press
  foreach ($p in $points) { Move-To $p[0] $p[1] }
  Release
}
function Keys([byte[]]$codes) {
  foreach ($k in $codes) { [Input]::keybd_event($k, 0, 0, [UIntPtr]::Zero) }
  Start-Sleep -Milliseconds 80
  [array]::Reverse($codes)
  foreach ($k in $codes) { [Input]::keybd_event($k, 0, 2, [UIntPtr]::Zero) }
  Start-Sleep -Milliseconds 300
}

$screen = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
Write-Host "screen $($screen.Width)x$($screen.Height)"

$notepad = Start-Process notepad -PassThru
$app = Start-Process $Exe -PassThru
Start-Sleep -Seconds 8
Shot "01-app-running"
Write-Host "app running: $(-not $app.HasExited)"

# The area picker, from the keyboard shortcut.
Keys @(0x11, 0x12, 0x10, 0x52)  # Ctrl+Alt+Shift+R
Start-Sleep -Seconds 2
Shot "02-picker"

$ax = 150; $ay = 90; $aw = 600; $ah = 340
Move-To $ax $ay; Press
foreach ($i in 1..12) { Move-To ($ax + $aw * $i / 12) ($ay + $ah * $i / 12) }
Shot "03-dragging"
Release
Start-Sleep -Milliseconds 1200
Shot "04-countdown"
Start-Sleep -Seconds 5
Shot "05-recording"

# Draw with Alt+D: a circle inside the area, then a shot right after it and one after it fades.
Keys @(0x12, 0x44)
Start-Sleep -Milliseconds 500
Shot "06-draw-on"
$cx = $ax + 300; $cy = $ay + 170
$circle = 0..36 | ForEach-Object { $t = $_ * [Math]::PI / 18; , @([int]($cx + 110 * [Math]::Cos($t)), [int]($cy + 70 * [Math]::Sin($t))) }
Drag $circle
Start-Sleep -Milliseconds 300
Shot "07-marked"
Keys @(0x1B)  # Esc stops drawing
Start-Sleep -Milliseconds 500
Shot "08-draw-off"

# With Draw off, a click should reach the app underneath.
Click ($ax + 40) ($ay + 40)
Start-Sleep -Seconds 4
Shot "09-faded"

# Stop: the round button at the right of the bar, which sits just below the area.
$barW = 330; $barX = [int]($ax + ($aw - $barW) / 2); $barY = $ay + $ah + 12
Click ($barX + 165 + 90) ($barY + 30)
Start-Sleep -Seconds 2
Shot "10-after-stop"
Start-Sleep -Seconds 20
Shot "11-review"

# Return is Copy reference: it should put the timeline's path on the clipboard and close the window.
Move-To 500 400; Keys @(0x0D)
Start-Sleep -Seconds 2
Shot "12-after-copy"
Write-Host "clipboard: $(Get-Clipboard)"

function Save-Frames($prefix, $times) {
  $root = Join-Path $env:LOCALAPPDATA "VideoPrompt\recordings"
  $latest = Get-ChildItem $root -Directory -ErrorAction SilentlyContinue | Sort-Object Name | Select-Object -Last 1
  if (-not $latest) { Write-Host "no recording folder"; return }
  Write-Host "$prefix recording: $($latest.Name), files: $((Get-ChildItem $latest.FullName).Name -join ', ')"
  $video = Join-Path $latest.FullName "video.mp4"
  if (Test-Path $video) {
    foreach ($t in $times) { & $Ffmpeg -v error -y -ss $t -i $video -frames:v 1 -update 1 (Join-Path $Out "$prefix-video-at-$($t)s.png") }
  }
}

Save-Frames "area" @(0, 0.2, 1)

# Dragging across the whole screen: the bar now sits inside what's recorded, so the video shows whether
# it's really hidden from capture. The screen must show it missing from this frame.
Keys @(0x11, 0x12, 0x10, 0x52)
Start-Sleep -Seconds 2
Move-To 0 0; Press
foreach ($i in 1..12) { Move-To ($screen.Width * $i / 12) ($screen.Height * $i / 12) }
Release
Start-Sleep -Seconds 9
Shot "20-whole-recording"
$barW = 330; $barX = [int](($screen.Width - $barW) / 2); $barY = 12
Click ($barX + 165 + 90) ($barY + 30)
Start-Sleep -Seconds 25
Shot "21-whole-review"
Save-Frames "whole" @(2, 5)
Move-To 500 400; Keys @(0x0D)

# What the first recording contains, to compare with what was on screen.
$root = Join-Path $env:LOCALAPPDATA "VideoPrompt\recordings"
$latest = Get-ChildItem $root -Directory -ErrorAction SilentlyContinue | Sort-Object Name | Select-Object -First 1
if ($latest) {
  Write-Host "recording: $($latest.Name), files: $((Get-ChildItem $latest.FullName).Name -join ', ')"
  $meta = Join-Path $latest.FullName "meta.json"
  if (Test-Path $meta) { Write-Host "meta: $(Get-Content $meta -Raw)" }
  $timeline = Join-Path $latest.FullName "timeline.md"
  if (Test-Path $timeline) { Copy-Item $timeline (Join-Path $Out "timeline.md") }
  $video = Join-Path $latest.FullName "video.mp4"
  if (Test-Path $video) {
    foreach ($t in 1, 4, 6, 9) {
      & $Ffmpeg -v error -y -ss $t -i $video -frames:v 1 -update 1 (Join-Path $Out "video-at-$($t)s.png")
    }
    Copy-Item (Join-Path $latest.FullName "overview.jpg") $Out -ErrorAction SilentlyContinue
  }
} else {
  Write-Host "no recording folder"
}
Stop-Process -Id $app.Id -Force -ErrorAction SilentlyContinue
Stop-Process -Id $notepad.Id -Force -ErrorAction SilentlyContinue
