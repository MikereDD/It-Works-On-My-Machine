# Changelog

All notable changes to Parallax are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.8.9] - 2026-07-04

### Fixed
- Restored the command button icons after they rendered as garbled characters on Windows.
- Assign the button glyphs from code points instead of relying on raw Unicode source literals.
- Save `parallax.ps1` as UTF-8 with BOM so Windows PowerShell 5.1 reads the script correctly.

## [0.8.8] - 2026-07-04

### Changed
- Show the app version beside Parallax in the Windows title bar.
- Keep the version visible when media is loaded by using `Parallax v0.8.8  -  <media title>`.

## [0.8.7] - 2026-07-04

### Changed
- Polished the control bar command buttons with a rounded owner-drawn `VP.PillButton`, icon labels, subtle borders, and cleaner hover/press states.
- Updated play/pause and fullscreen/window labels so the buttons visually track the current state.

## [0.8.6] - 2026-06-27

### Added
- Encrypted-disc hint: when a disc is selected but mpv falls back to idle with no
  playable title (typically AACS/CSS encryption with no decryption library on
  hand), Parallax now shows a one-line dialog pointing to MakeMKV instead of
  leaving a silent black screen.

## [0.8.5] - 2026-06-27

### Fixed
- Time formatting showed the hour an hour too high for times whose fractional
  hour was 0.5 or more (e.g. 1:36:05 rendered as 2:36:05), because the hour was
  derived with `[int]` (which rounds). Now floored. Seek targets were always
  correct; only the labels were wrong.

## [0.8.4] - 2026-06-27

### Added
- **Split evenly** submenu under Episodes: choose how many even episodes to split
  the current title into (2-10) straight from the Tracks popup, no config edit.
  "Auto (detect)" returns to gap-based detection.

## [0.8.3] - 2026-06-27

### Added
- Manual episode split: set `$script:episodeCount` (e.g. 5) to divide the current
  title into that many evenly-spaced **Episodes**, for discs whose chapter timing
  doesn't cleanly mark episode boundaries. Left at 0, the gap auto-detection from
  0.8.2 is used.

## [0.8.2] - 2026-06-27

### Added
- Episode detection for single-title "Play All" discs: when a disc reports one
  long title, the **Tracks** popup gains an **Episodes** section that infers
  episode boundaries from large gaps between chapter timestamps and jumps to
  each. Threshold is `$script:episodeGapSec` (default 600s).

## [0.8.1] - 2026-06-27

### Fixed
- Disc **Titles** now use mpv's `disc-titles` (the earlier `disc-title-list`
  lookup was not a real property and never populated), so the individual titles
  of a multi-title disc - e.g. each episode of a TV-series DVD - appear and can
  be selected.

### Changed
- **Chapters** moved into a submenu so the Tracks popup stays compact on discs
  with many chapters.
- The now-playing name falls back to the disc volume label when mpv reports a
  bare `dvd://` / `bd://` URL.

## [0.8.0] - 2026-06-27

### Added
- Now-playing title: the window title bar and a header atop the **Tracks** popup
  show mpv's `media-title` (a disc's volume label, a file's metadata title, or
  filename), so the disc/media name is visible at a glance.

## [0.7.0] - 2026-06-27

### Added
- Disc navigation in the **Tracks** popup while a disc is playing:
  - **Titles** from mpv's `disc-title-list`, each with its length; selecting one
    loads that title (`dvd://N` / `bd://N`) - good for per-episode TV-series discs.
  - **Chapters** from `chapter-list` (shown whenever a file has more than one),
    each with its start time; selecting jumps to it. Covers TV discs that pack
    every episode into one long "Play All" title as chapters.
  - The current title / chapter is checked.

## [0.6.0] - 2026-06-27

### Added
- Disc playback: a **Disc** button lists optical drives and plays DVD (`dvd://`)
  or Blu-ray (`bd://`), auto-detecting disc type by `VIDEO_TS` / `BDMV` on the
  disc. Commercial discs require decryption libraries (libdvdcss for DVD;
  libaacs + a KEYDB.cfg for Blu-ray).

## [0.5.0] - 2026-06-26

### Added
- Resume playback: position is remembered per file via mpv's watch-later
  mechanism (stored under `%APPDATA%\Parallax\watch_later`). Reopening a file
  seeks back to where you left off; finishing a file clears its resume point.
  Saved on quit and before switching files.

## [0.4.0] - 2026-06-26

### Added
- Fullscreen toggle (`F`, borderless maximized; `Esc` to exit) with the control
  bar and cursor auto-hiding after ~2.5s idle and revealing on mouse movement.
- Focus-independent input layer: key state and the active window are polled in
  the tick loop (via `GetAsyncKeyState` / `GetForegroundWindow`), so transport
  keys work even when mpv's embedded window holds focus.
- Subtitles stay clear of the control bar in windowed mode: `sub-pos` lifts up
  when windowed and returns to the bottom edge in fullscreen, with mpv margins
  forced so subtitles never render outside the window.

### Changed
- All keyboard shortcuts moved from the WinForms `KeyDown` handler to the polled
  input layer. Tick interval lowered to 100ms for snappier reveal and key response.
- Window title is now "Parallax".

## [0.3.0] - 2026-06-26

### Added
- **Tracks** popup menu for switching audio and subtitle streams, sourced from
  mpv's `track-list`; current track checked, plus an **Off** entry for subtitles.
- `TryGetInt` and `GetString` interop helpers (read int64 / UTF-8 string
  properties back from libmpv, freeing mpv-allocated strings via `mpv_free`).

## [0.2.0] - 2026-06-25

### Added
- DWM dark title bar via `DwmSetWindowAttribute`.
- Owner-drawn monochrome sliders (`VP.Slider`) replacing the WinForms `TrackBar`:
  double-buffered, click-to-seek, drag-scrub with live time preview.
- Two-row control bar, flat hover buttons, dedicated volume slider.
- Keyboard shortcuts: space play/pause, arrows for seek and volume.

## [0.1.0] - 2026-06-24

### Added
- Initial libmpv-backed player: HWND embedding, open/play/pause, seek bar,
  position readout, STA relaunch guard, DLL loaded by full path.
