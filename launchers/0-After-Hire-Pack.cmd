@echo off
setlocal
set SCRIPT_DIR=%~dp0

echo Running after-hire pack...
echo.

powershell.exe -NoLogo -ExecutionPolicy Bypass -File "%SCRIPT_DIR%..\scripts\Invoke-Declientify.ps1"
if errorlevel 1 goto :fail

powershell.exe -NoLogo -ExecutionPolicy Bypass -File "%SCRIPT_DIR%..\scripts\Invoke-BaselineAudit.ps1"
if errorlevel 1 goto :fail

echo.
echo After-hire pack complete.
pause
exit /b 0

:fail
echo.
echo After-hire pack stopped because one of the scripts returned an error.
pause
exit /b 1
