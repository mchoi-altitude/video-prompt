@echo off
rem Runs vp-frames with the app's own Electron, so Claude doesn't need Node installed.
setlocal
set "electron=%~dp0..\..\..\electron.exe"
if not exist "%electron%" set "electron=%~dp0..\node_modules\electron\dist\electron.exe"
set ELECTRON_RUN_AS_NODE=1
"%electron%" "%~dp0..\dist\frames\main.js" %*
