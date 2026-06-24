# Cadence

A sleek, fully owner-drawn local audio player for Windows — monochrome
Material-style UI, NAudio engine, live FFT visualizer, and a real library
browser. Part of the `personaltools/` toolkit.

**Latest: v0.2.0** · [Changelog](https://github.com/MikereDD/It-Works-On-My-Machine/blob/main/personaltools/audio-player/CHANGELOG.md)

## Highlights
- **Wide format support** — MP3, FLAC, M4A/AAC, WAV, WMA, OGG, OPUS via NAudio
  and system codecs.
- **Live spectrum visualizer** — a real FFT off a pass-through tap, drawn as
  center-mirrored grey spikes in a recessed well (no fake animation).
- **Library browser** — a lazy-loaded folder tree with saved roots persisted to
  config, so a large collection is navigated rather than flattened.
- **Playlist queue** — shuffle, repeat-all, auto-advance, full-path dedupe, and
  M3U / M3U8 import.
- **Monochrome Material UI** — tonal pill buttons, a FAB transport, toggle
  chips, recessed dark-grey wells, and a subtle depth gradient.
- **Tags + album art** — via TagLibSharp when present, with a filename fallback.

## Requirements
- Windows with **Windows PowerShell 5.1** available (used for the WinForms STA
  apartment). It runs fine when launched from PowerShell 7 — the script
  self-relaunches into 5.1.
- NAudio + TagLibSharp DLLs in `.\lib` (fetched by `setup-naudio.ps1`).

## Setup & run
```powershell
# one-time: fetch NAudio + TagLibSharp into .\lib
.\setup-naudio.ps1

# unblock (needed whenever files arrive via a browser/download), then run
Get-ChildItem . -Recurse -Include *.ps1,*.dll | Unblock-File
.\audio-player.ps1
```
Keep `Unblock-File` on its own line — it must finish before launch, and a
machine-scope GPO enforces execution policy regardless of `-ExecutionPolicy
Bypass`. The launcher self-relaunches `-NoProfile -STA` under Windows
PowerShell 5.1 for WinForms.

> Run only `audio-player.ps1` — it dot-sources the engine and UI modules
> itself. Don't `& .\*.ps1`, or the modules and the setup script run too.

## Controls
| Input | Action |
|-------|--------|
| `Space` | Play / pause |
| `Ctrl+Left` / `Ctrl+Right` | Previous / next |
| `M` | Mute toggle |
| Double-click file / `.m3u` | Play |
| Right-click folder (tree) | Add recursively |
| Library button | Add / remove / clear saved roots |

## Layout
| File | Role |
|------|------|
| `audio-player.ps1` | Main GUI — layout, wiring, position + visualizer timers |
| `player.engine.ps1` | NAudio playback engine + FFT spectrum tap |
| `player.ui.ps1` | Theme palette, owner-drawn controls, live visualizer |
| `setup-naudio.ps1` | NuGet dependency fetcher (`-> .\lib`) |

Runtime files written next to the script: `cadence.config.json` (saved library
roots) and `cadence-startup.log` (startup/exception log).

## Visualizer
A compiled C# tap copies samples into a ring buffer as they play; a UI timer
runs an FFT, folds it into log-spaced bands, and paints center-mirrored grey
spikes (bass mid-grey to treble near-white) inside a recessed, light-bordered
well. If the tap fails to compile it falls back to an idle baseline — audio is
never routed through anything that could interrupt playback.

## Changelog
See [CHANGELOG.md](https://github.com/MikereDD/It-Works-On-My-Machine/blob/main/personaltools/audio-player/CHANGELOG.md).
