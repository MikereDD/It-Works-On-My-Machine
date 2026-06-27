# Changelog

All notable changes to Parallax are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
