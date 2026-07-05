# MediaForge Complete Pack v1.4.0

This pack moves the ripping/encoding scripts into one project folder:

```text
$HOME\PS\scripts\personaltools\MediaForge\
```

Included from your uploaded files:

```text
bluray-backup.ps1
bluray-trackdump.ps1
BRencoder.ps1
BRencoder-gui.ps1
cd-image-flac.ps1
cd-ripper-gui.ps1
cd-ripper-gui.vbs
cd-tracks-flac.ps1
dvd-ripper-encoder.ps1
dvd-ripper-encoder-gui.ps1
media-encoder-gui.ps1
media-encoder.ico
MediaForge.vbs
```

The patched `tool-menu.ps1` points the media tools at `personaltools\MediaForge\...` and launches GUI tools with `powershell.exe -STA`.

## Install

From PowerShell, after extracting this zip:

```powershell
$src = "$HOME\Downloads\MediaForge-complete-v1.4.0"
$personal = "$HOME\PS\scripts\personaltools"
$menu = "$HOME\PS\scripts\menu"

New-Item -ItemType Directory -Force "$personal\MediaForge" | Out-Null
Copy-Item "$src\MediaForge\*" "$personal\MediaForge\" -Recurse -Force
Copy-Item "$src\tool-menu.ps1" "$menu\tool-menu.ps1" -Force

Get-ChildItem "$personal\MediaForge" -Recurse | Unblock-File
Unblock-File "$menu\tool-menu.ps1"
```

## Launch

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -STA -File "$HOME\PS\scripts\personaltools\MediaForge\media-encoder-gui.ps1"
```

Or use Tool Menu and choose **MediaForge (GUI)**.

## Optional old-path shim

If anything still launches `personaltools\media-encoder-gui.ps1`, create this wrapper there:

```powershell
$target = Join-Path $PSScriptRoot 'MediaForge\media-encoder-gui.ps1'
& powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File $target @args
```
