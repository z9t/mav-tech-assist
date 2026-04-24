@echo off
setlocal
set SCRIPT_DIR=%~dp0
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_DIR%..\scripts\Start-Dashboard.ps1" -Page "network-helper.html"
