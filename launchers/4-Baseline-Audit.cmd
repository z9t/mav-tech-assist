@echo off
setlocal
set SCRIPT_DIR=%~dp0
powershell.exe -NoLogo -ExecutionPolicy Bypass -File "%SCRIPT_DIR%..\scripts\Invoke-BaselineAudit.ps1"
echo.
pause
