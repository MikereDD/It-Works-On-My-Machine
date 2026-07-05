<p align="center">
  <img src="./mediaforge.png" alt="MediaForge icon" width="96" />
</p>

<h1 align="center">MediaForge</h1>

<p align="center">
  <strong>A polished PowerShell front end for ripping, backing up, encoding, sampling, and documenting physical media.</strong>
</p>

<p align="center">
  <img alt="Platform" src="https://img.shields.io/badge/platform-Windows-0d1117?style=for-the-badge" />
  <img alt="Shell" src="https://img.shields.io/badge/shell-PowerShell-0d1117?style=for-the-badge" />
  <img alt="Version" src="https://img.shields.io/badge/version-1.7.0-0d1117?style=for-the-badge" />
  <img alt="License" src="https://img.shields.io/badge/license-WTFPL-0d1117?style=for-the-badge" />
</p>

---

## Overview

**MediaForge** is the all-in-one Windows GUI for Mike Redd's personal media workflow.
It brings the DVD, Blu-ray, CD, sample, and NFO tools into one cleaner launcher while keeping each original engine script separate and reusable.

The goal is simple: put the whole media pipeline behind a single, nicer window without hiding the power of the individual scripts.

MediaForge can help with:

- DVD ripping and HEVC encoding
- Blu-ray backup, metadata capture, and encoding
- Blu-ray sidecar / track metadata dumps
- Standalone MKV sample creation
- MediaInfo / NFO generation
- Audio CD ripping to FLAC tracks
- Audio CD ripping to single-image FLAC + CUE
- Launching the older focused GUI tools when needed

---

## Project layout

MediaForge lives under the personal PowerShell tools folder:

```text
$HOME\PS\scripts\personaltools\MediaForge\
```

Expected bundle layout:

```text
MediaForge/
├─ mediaforge-gui.ps1              # Main all-in-one GUI
├─ MediaForge.vbs                  # Quiet launcher
├─ mediaforge.ico                  # App icon
├─ mediaforge.png                  # README / UI image
│
├─ media-encoder-gui.ps1           # Compatibility launcher / shim
│
├─ bluray-backup.ps1               # Blu-ray decrypt / backup / metadata
├─ bluray-trackdump.ps1            # Blu-ray metadata-only track dump
├─ BRencoder.ps1                   # Blu-ray / MKV encoder engine
├─ BRencoder-gui.ps1               # Focused Blu-ray encoder GUI
│
├─ dvd-ripper-encoder.ps1          # DVD rip + encode engine
├─ dvd-ripper-encoder-gui.ps1      # Focused DVD encoder GUI
│
├─ cd-tracks-flac.ps1              # Audio CD to individual FLAC tracks
├─ cd-image-flac.ps1               # Audio CD to FLAC image + CUE
├─ cd-ripper-gui.ps1               # Focused CD ripper GUI
├─ cd-ripper-gui.vbs               # Quiet CD ripper launcher
│
├─ mkv-sample.ps1                  # MKV sample creator
└─ minfocreate.ps1                 # NFO / MediaInfo helper
```

---

## Main workflow

MediaForge is designed around a practical disc-to-library workflow.

### 1. Pick a source

Use the GUI to select a DVD drive, Blu-ray source, existing video file, or audio CD workflow.

### 2. Capture metadata

Blu-ray workflows use sidecar metadata so track selection, languages, forced subtitles, and defaults can be handled more consistently.

### 3. Encode cleanly

The encoder scripts stay separate from the GUI. MediaForge starts each engine in its own background runspace so matching function names do not collide.

### 4. Add finishing tools

After an encode, MediaForge can also run sample creation and NFO generation so the final folder is ready for a media library.

---

## Included tools

| Tool | Script | Purpose |
| --- | --- | --- |
| MediaForge GUI | `mediaforge-gui.ps1` | Main all-in-one front end |
| DVD Encoder | `dvd-ripper-encoder.ps1` | DVD rip and encode pipeline |
| DVD Encoder GUI | `dvd-ripper-encoder-gui.ps1` | Focused DVD GUI |
| Blu-ray Backup | `bluray-backup.ps1` | Blu-ray backup and metadata capture |
| Blu-ray Track Dump | `bluray-trackdump.ps1` | Metadata-only Blu-ray scan |
| Blu-ray Encoder | `BRencoder.ps1` | HEVC encode pipeline |
| Blu-ray Encoder GUI | `BRencoder-gui.ps1` | Focused Blu-ray GUI |
| CD Track Ripper | `cd-tracks-flac.ps1` | Rip CD to separate FLAC tracks |
| CD Image Ripper | `cd-image-flac.ps1` | Rip CD to image FLAC + CUE |
| CD Ripper GUI | `cd-ripper-gui.ps1` | Focused CD GUI |
| MKV Sample | `mkv-sample.ps1` | Create sample clips |
| MiNfoCreate | `minfocreate.ps1` | Generate NFO / MediaInfo output |

---

## Requirements

MediaForge is built for Windows and PowerShell.

Recommended environment:

- Windows 10 or Windows 11
- Windows PowerShell with STA support for WinForms
- PowerShell 7 for normal shell work is fine, but the GUI relaunches under Windows PowerShell when needed
- Optical drive for DVD / Blu-ray / CD workflows
- Enough disk space for full-disc backups and HEVC outputs

External tools used by the underlying scripts may include:

- MakeMKV
- FFmpeg / FFprobe
- MKVToolNix
- MediaInfo
- MusicBrainz / metadata helpers for CD workflows
- OMDb configuration for richer NFO output when available

---

## Install

Copy the `MediaForge` folder into:

```powershell
$HOME\PS\scripts\personaltools\MediaForge
```

Copy the updated tool menu into:

```powershell
$HOME\PS\scripts\menu\tool-menu.ps1
```

For a patch zip that contains `personaltools` and `menu`, extract it into:

```powershell
$HOME\PS\scripts
```

Example:

```powershell
Expand-Archive .\MediaForge-personaltools-patch.zip -DestinationPath "$HOME\PS\scripts" -Force
```

---

## Launch

From the tool menu, choose:

```text
MediaForge (GUI)
```

Direct launch:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -STA -File "$HOME\PS\scripts\personaltools\MediaForge\mediaforge-gui.ps1"
```

Quiet launcher:

```powershell
wscript "$HOME\PS\scripts\personaltools\MediaForge\MediaForge.vbs"
```

---

## Notes

MediaForge does not replace the engine scripts. It wraps them.

That is intentional. Each pipeline can still be tested, patched, and launched on its own. The GUI gives them a shared front door while keeping the actual media logic modular.

Logs are written to the temp folder during GUI startup and tool execution, which helps diagnose launch issues without needing the UI to fully render.

---

## Roadmap

Planned polish ideas:

- Continue tightening the main GUI layout
- Improve status panels and progress feedback
- Keep standalone tool panels selectable
- Make Sample and NFO workflows feel first-class
- Keep the focused DVD, Blu-ray, and CD GUIs available for direct launch
- Improve README screenshots once the UI settles

---

## Philosophy

MediaForge is built for a personal workflow first.

It does not try to be a giant commercial media suite. It is a clean front end for scripts that already work, with enough polish to make the workflow feel like a real app.

Small tools. Clear purpose. Good output.

---

## License

Released under the WTFPL as part of the **It Works On My Machine** project.
