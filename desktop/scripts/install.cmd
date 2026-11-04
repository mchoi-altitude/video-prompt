@echo off
rem Runs the installer without changing the machine's PowerShell policy.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0install.ps1" %*
