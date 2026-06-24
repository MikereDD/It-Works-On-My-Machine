@echo off
rem ---------------------------------------------------------------------------
rem  cadence.cmd  -  fire-and-forget launcher (bash `&` style)
rem  Backgrounds Cadence in a hidden STA Windows PowerShell host and returns
rem  immediately. Double-click it, or run `cadence` from this folder.
rem  %~dp0 = this file's own folder, so it works wherever the repo lives.
rem ---------------------------------------------------------------------------
start "" powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0audio-player.ps1" -Relaunched
