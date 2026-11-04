@echo off
rem Runs vp-frames with the app's own Electron, so Claude doesn't need Node installed.
setlocal
set "here=%~dp0"
rem Installed: resources\app\bin. From source: desktop\bin.
set "electron=%here%..\..\..\Video Prompt.exe"
if not exist "%electron%" set "electron=%here%..\node_modules\electron\dist\electron.exe"
set ELECTRON_RUN_AS_NODE=1
"%electron%" "%here%..\dist\frames\main.js" %*
exit /b %errorlevel%
