@echo off
setlocal
set SCRIPT_DIR=%~dp0
powershell.exe -NoLogo -ExecutionPolicy Bypass -File "%SCRIPT_DIR%..\scripts\Invoke-PreHirePrep.ps1"
echo.
pause
