<p align="center">
  <img src="./mediaforge.png" alt="MediaForge icon" width="128" />
</p>

<h1 align="center">MediaForge</h1>

<p align="center">
  <strong>Blu-ray, DVD, CD, metadata, samples, posters, and NFO tools in one PowerShell project.</strong>
</p>

<p align="center">
  <img alt="Version" src="https://img.shields.io/badge/version-v1.9.7-d9dde4?style=for-the-badge&labelColor=111318">
  <img alt="PowerShell" src="https://img.shields.io/badge/PowerShell-7.6+-d9dde4?style=for-the-badge&labelColor=111318">
  <img alt="Platform" src="https://img.shields.io/badge/Windows-Media%20Tools-d9dde4?style=for-the-badge&labelColor=111318">
  <img alt="Project" src="https://img.shields.io/badge/It%20Works%20On%20My%20Machine-MediaForge-d9dde4?style=for-the-badge&labelColor=111318">
</p>

<p align="center">
  <img src="./assets/screenshots/mediaforge-v1.9.7.png" alt="MediaForge v1.9.7 GUI screenshot" width="950" />
</p>

---

## What it is

**MediaForge** is the media ripping and encoding toolbox for the *It Works On My Machine* repo.

It wraps the Blu-ray, DVD, CD, sample, metadata, poster, and NFO helper scripts into one project folder with a GUI front end and Tool Menu support.

```text
$HOME\PS\scripts\personaltools\MediaForge\
```

---

## Main launcher

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -STA -File "$HOME\PS\scripts\personaltools\MediaForge\mediaforge-gui.ps1"
```

Or double-click:

```text
MediaForge.vbs
```

`media-encoder-gui.ps1` is kept only as a compatibility shim for older menu entries. The real GUI is:

```text
mediaforge-gui.ps1
```

---

## Features

| Area | What MediaForge does |
|---|---|
| **Blu-ray** | Backup, track dump, metadata sidecars, HEVC encode, audio/subtitle language handling |
| **DVD** | Rip and encode through the production DVD workflow |
| **Audio CD** | FLAC ripping, MusicBrainz lookup, album art workflow, track/image modes |
| **Samples** | Create MKV/MP4 sample clips from finished media |
| **Metadata** | Create MiNFO / NFO style reports for finished media |
| **IMDb / Posters** | Metadata lookup and poster grabbing through the helper tools |
| **GUI** | One polished front end for DVD, Blu-ray, file tools, and Audio CD workflows |
| **Tool Menu** | Scripts are grouped under MediaForge for clean launching |

---

## Included scripts

```text
MediaForge\
  mediaforge-gui.ps1              # real GUI
  media-encoder-gui.ps1           # compatibility shim
  MediaForge.vbs                  # double-click launcher

  bluray-backup.ps1
  bluray-trackdump.ps1
  BRencoder.ps1
  BRencoder-gui.ps1

  dvd-ripper-encoder.ps1
  dvd-ripper-encoder-gui.ps1

  cd-image-flac.ps1
  cd-tracks-flac.ps1
  cd-ripper-gui.ps1
  cd-ripper-gui.vbs

  mkv-sample.ps1
  minfocreate.ps1
  imdbdump.ps1
  imdbthumbgrab.ps1

  mediaforge.ico
  mediaforge.png

  assets\
    icons\
      dvd.png
      bluray.png
      file.png
      audiocd.png
    screenshots\
      mediaforge-v1.9.7.png
```

---

## Install

From PowerShell, after extracting the package:

```powershell
$src = "$HOME\Downloads\MediaForge-v1.9.7-readme-screenshot\MediaForge"
$dst = "$HOME\PS\scripts\personaltools\MediaForge"

New-Item -ItemType Directory -Force $dst | Out-Null
Copy-Item "$src\*" "$dst\" -Recurse -Force

Get-ChildItem $dst -Recurse | Unblock-File
```

Launch it:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -STA -File "$HOME\PS\scripts\personaltools\MediaForge\mediaforge-gui.ps1"
```

---

## Tool Menu

The Tool Menu should point MediaForge GUI entries at:

```text
MediaForge\mediaforge-gui.ps1
```

Console helper scripts should run from the MediaForge folder so local files, icons, logs, sidecars, and helper paths resolve correctly.

Recommended Tool Menu entries include:

```text
MediaForge (GUI)
MediaForge DVD Encoder
MediaForge Blu-ray Backup
MediaForge Blu-ray Track Dump
MediaForge Blu-ray Encoder
MediaForge MKV Sample
MediaForge IMDb Dump
MediaForge Poster Grab
MediaForge MiNfoCreate
```

---

## GUI notes

The v1.9.7 GUI keeps the proven v1.8/v1.9.1 layout and workflow intact while continuing the premium dark MediaForge theme direction.

This pass keeps:

```text
current workflow
current script wiring
source tile icons
flicker-safe timer behavior
progress card layout fix
```

The GUI supports:

```text
DVD       -> scan/rip/encode workflow
Blu-ray   -> backup/trackdump/encode workflow
File      -> sample/minfo side tools
Audio CD  -> CD ripper GUI / FLAC workflows
```

The **After Encode** panel supports optional automatic post-steps:

```text
Sample
Minfo / NFO
```

Manual helper buttons are also available:

```text
Create sample
Create minfo
Dump sidecar
IMDb
Poster
```

---

## Requirements

MediaForge expects the normal media toolchain to be installed and available through the configured paths or `%PATH%`.

Common tools:

```text
PowerShell 7+
MakeMKV
ffmpeg / ffprobe
mkvmerge / mkvpropedit
MediaInfo
cdda2wav
flac
metaflac
```

Some workflows can still run when optional helpers are missing, but production ripping and tagging works best when the full stack is installed.

---

## Project rule

MediaForge uses `$HOME`-based paths and should not hard-code a specific Windows user folder.

```text
Good:  $HOME\PS\scripts\personaltools\MediaForge
Bad:   C:\Users\Somebody\...
```

---

## Release notes

### v1.9.7 Progress Layout Fix

- Keeps the premium MediaForge theme direction.
- Moves Encode and Cancel lower inside the Progress card so they do not crowd the progress bar.
- Compresses the stage strip so Scan / Decrypt / Encode / Sample / Minfo stay left of the action buttons.
- Prevents the progress bar from stretching under the action buttons on resize.
- Keeps layout, workflow, buttons, source icons, and script wiring unchanged.
- Adds the current GUI screenshot to the README.

### v1.9.6 Source Icon / Selection Tuning

- Source tile icons live in `assets/icons/`.
- Cleaner transparent Blu-ray source icon.
- Darker selected source tile.
- Keeps the v1.9.4 flicker fix and v1.9.5 icon workflow.

### v1.9.4 Premium Theme Flicker Fix

- Removes repeated full-theme repainting from the UI timer to prevent visual flashing/flicker.
- Enables flicker-safe double buffering where supported.
- Keeps layout, workflow, buttons, and script wiring unchanged.

---

## Philosophy

MediaForge is meant to be practical, local, and repairable.

It is not trying to be a streaming platform. It is a personal media workshop: rip the disc, preserve the tracks, tag the output, create the sidecars, and keep the workflow understandable.

> If it works on my machine, it gets forged here.
