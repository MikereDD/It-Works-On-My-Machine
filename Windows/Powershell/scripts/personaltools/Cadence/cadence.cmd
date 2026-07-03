@echo off
setlocal
set "SCRIPT_DIR=%~dp0"
start "Cadence" powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File "%SCRIPT_DIR%cadence.ps1"
endlocal
