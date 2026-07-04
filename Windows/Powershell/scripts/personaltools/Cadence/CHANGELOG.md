# Changelog

All notable changes to Cadence are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.4.6] - 2026-07-04

Custom playlist management pass.

### Added
- New Playlists button with actions to start a new empty playlist, open an
  `.m3u` / `.m3u8`, save the current queue as a named Cadence playlist, export
  the queue as an M3U file, load saved playlists, append saved playlists, and
  open the playlists folder.
- App-managed saved playlists live in `cadence.playlists` next to the script.
- Queue right-click menu now includes `Save current queue as playlist...`.
- Keyboard shortcuts: `Ctrl+S` saves the current queue as a named playlist and
  `Ctrl+O` opens a playlist file.

### Changed
- README and HELP now document custom playlist behavior.

## [0.4.5] - 2026-07-04

Documentation pass for the player UI.

### Added
- New `HELP.md` with a full guide to the app layout, buttons, right-click menus,
  keyboard shortcuts, album-art behavior, runtime files, and troubleshooting.

### Changed
- README now links to `HELP.md` from the Controls section and lists it in the
  project layout table.

## [0.4.4] - 2026-07-04

Shuffle and repeat controls pass.

### Added
- Repeat is now a three-state mode: Off, All, and One. The repeat pill cycles
  through the modes and updates its label so the current mode is visible.
- Right-click the queue to toggle Shuffle or choose a specific Repeat mode.
- Keyboard shortcuts: `S` toggles Shuffle and `R` cycles Repeat mode.

### Changed
- Repeat state is persisted as `repeatMode` in `cadence.config.json` while still
  reading the old boolean `repeat` setting for compatibility.


## [0.4.3] - 2026-07-03

Album art fallback pass for libraries whose tracks have metadata but no embedded
cover image.

### Added
- Optional online album-art lookup through Apple's public iTunes Search endpoint
  when embedded art and local sidecar images are missing. Downloaded covers are
  cached in `cadence.art-cache` so repeat plays do not hit the network.
- Right-click album-art menu with:
  - `Choose cover image for this album...` to copy a selected image beside the
    current track as `folder.jpg`/`folder.png`.
  - `Retry online art lookup`.
  - `Online album art lookup` toggle, persisted in `cadence.config.json`.

### Changed
- Album art lookup order is now embedded tag art -> local sidecar image ->
  cached/online cover lookup.

## [0.4.2] - 2026-07-03

Album art deep fix and visible build stamp.

### Added
- The running build is now visible in the window title and as a small bottom-right version stamp, so screenshots show the exact build being tested.
- The album-art box now has a tooltip showing whether art came from embedded tags, a sidecar image, or nothing found.
- Album-art attempts are written to `cadence-startup.log` for easy debugging.

### Fixed
- Embedded art extraction now tries every TagLibSharp byte-access path instead of only `.Data.Data`, which is more reliable across TagLibSharp versions and PowerShell hosts.
- Embedded art now tries the front cover first, then every other embedded picture until one decodes.
- Sidecar art lookup now searches hidden files, Windows Media Player `AlbumArt_*.jpg` files, common names, fuzzy cover names, and a one-image album folder.
- Sidecar lookup now checks the track folder first and then nearby parent folders, covering common `Artist/Album/Tracks` layouts.

## [0.4.1] - 2026-07-03

Album art reliability pass.

### Fixed
- Album art now falls back to common sidecar images beside the track when no
  embedded image is available: `cover`, `folder`, `front`, `album`,
  `albumart`, `artwork`, `AlbumArt`, and `AlbumArtSmall` with `.jpg`, `.jpeg`,
  `.png`, `.bmp`, or `.gif`.
- Embedded art is cloned from the tag stream before the stream is disposed, so
  the PictureBox is never holding an image backed by a closed stream.
- Swapping, clearing, and closing tracks now detach the PictureBox before
  disposing the old bitmap, preventing disposed-image repaint glitches during
  fast track changes.

## [0.4.0] - 2026-06-27

Drag-and-drop, persisted settings, queue export, and switchable visualizer
palettes.

### Added
- Drag-and-drop: drop files, folders, or `.m3u`/`.m3u8` playlists onto the
  window to add them to the queue (folders are scanned recursively).
- Export the current queue as an `.m3u8`/`.m3u` playlist (right-click the queue
  -> "Export queue as M3U...").

### Changed
- Settings now persist alongside the saved library roots in
  `cadence.config.json`: volume, shuffle, repeat, and the visualizer palette are
  restored on launch.
- Visualizer palettes: right-click the visualizer to switch between Monochrome
  (default), Full spectrum, and Indigo; the choice is saved.

## [0.3.0] - 2026-06-24

Search, a much better visualizer, and a pwsh-native launch.

### Added
- Queue search: a live filter box above the queue narrows it to matching
  tracks as you type. A view-to-model map keeps playback correct while filtered
  (double-click still plays the right track and the now-playing row follows),
  `Esc` clears it, and typing is shortcut-safe (Space/M go to the box, not the
  transport).
- App icon: a visualizer-bars mark (`docs/cadence.ico`) — the recessed well,
  gradient bars, and peak caps from the spectrum view — on the window title bar,
  taskbar, and alt-tab.

### Changed
- Visualizer reworked for real motion and depth: a gamma curve expands the
  dynamic range so loud bands tower and quiet ones drop (no more uniform wall),
  with fewer/wider gradient bars (bright tip fading to a dark foot), rounded
  tops, and floating peak-hold caps that snap up and fall under gravity.
- Renamed the entry script `audio-player.ps1` -> `cadence.ps1` (the folder stays
  `audio-player/`).
- Launch hardening: when the launching shell isn't already STA, the player
  relaunches HIDDEN into Windows PowerShell `-STA` -- the reliable STA host for
  the owner-draw paint handlers, since `pwsh -File` runs MTA in practice -- so
  only the player window shows, with no stray console. A `-Relaunched` sentinel
  prevents relaunch loops, and a new `cadence.cmd` gives a fire-and-forget
  launch.

### Fixed
- Native scrollbars on the library tree and queue now use the Windows dark theme
  (`SetWindowTheme` / `DarkMode_Explorer`) instead of rendering as light strips.

## [0.2.0] - 2026-06-23

A large pass turning the v0.1.0 scaffold into a usable player: a live
visualizer, a real library browser, playlist plumbing, the Windows PowerShell
5.1 launch path, and a full monochrome Material-style redesign.

### Added
- Live spectrum visualizer: a compiled C# pass-through tap copies audio into a
  ring buffer; a ~25fps UI timer runs an FFT, folds it into log-spaced bands,
  and draws center-mirrored spikes with fast-attack / slow-decay smoothing. The
  bar count adapts to the window width. If the tap can't compile it falls back
  to an idle baseline; playback is never affected.
- Library tree browser: a lazy-loaded folder tree (split above the queue) so a
  large library is navigated, not flattened. Folders load only when expanded;
  double-click a file or `.m3u` to play, right-click a folder to add it
  recursively.
- Saved library roots, persisted to `cadence.config.json`: add multiple roots
  for local / external / cloud paths, each a top-level tree node. The "Library"
  button menu adds a root, removes the selected one, or clears all; roots reload
  on launch and fall back to drives when none are saved.
- M3U / M3U8 import via Add Files: parses the playlist, resolves relative paths
  against its folder, handles `file://` URIs and BOM/quotes, and skips remote
  streams.
- Queue handling: batched inserts (`BeginUpdate`/`EndUpdate`), full-path
  dedupe, natural numeric sort, and a wait-cursor + "added N tracks" status when
  scanning a folder.

### Changed
- Complete monochrome Material redesign of the whole UI:
  - Palette reduced to greys (no blue) with explicit depth tokens.
  - Buttons are Material 3: tonal pill action buttons with a soft bevel and
    hover/press state layers, a FAB for play (dark disc, soft ring, top sheen,
    white glyph), bare circular icon buttons for prev/next/stop with a
    circular hover state layer, and outlined/filled toggle chips for
    shuffle/repeat.
  - Depth: a vertical gradient ground, raised surfaces for the art card and
    pills, and recessed dark-grey wells for the playlist, tree, and visualizer.
  - Visualizer reworked into a recessed well with a light-grey hairline border
    and desaturated grey spikes (bass mid-grey to treble near-white), replacing
    the indigo ramp.
  - Sliders given a recessed groove and a light-grey knob with a soft ring.

### Fixed
- Launcher relaunches via Windows PowerShell 5.1 instead of `pwsh -STA`
  (pwsh 7 is MTA and rejects `-STA`, which caused a silent child-window crash).
- Script-wide `trap` logs startup errors to `cadence-startup.log` and shows a
  message box, so failures are never silent.
- All sources kept strictly ASCII to avoid mojibake when 5.1 reads BOM-less
  files as Windows-1252.
- Spectrum C# tap compiles under Windows PowerShell 5.1: explicit `netstandard`
  reference added, and `lock`/`Monitor` usage removed so the 5.1 compiler can
  satisfy the build.
- Guarded `WaveOutEvent` teardown so rapid track changes can't crash on a
  disposed wait handle; global WinForms exception handlers log to the startup
  log instead of crashing.
- `SetCompatibleTextRenderingDefault` wrapped so re-running in the same session
  no longer throws.
- Transport buttons recenter cleanly on resize (full-ground repaint clears the
  old positions) and each icon button paints the matching gradient slice behind
  it, so the circular regions blend into the background instead of leaving ghost
  discs.

## [0.1.0] - 2026-06-23

### Added
- Initial scaffold: WinForms GUI with dot-sourced `player.engine.ps1` and
  `player.ui.ps1` modules, mirroring the media-encoder-gui layout.
- NAudio backend (`MediaFoundationReader` + `WaveOutEvent`) covering MP3, FLAC,
  M4A/AAC, WAV, WMA, OGG, OPUS via system codecs.
- Owner-drawn dark theme: transport glyph buttons (play/pause/stop/prev/next),
  draggable seek slider, volume slider, shuffle/repeat pills, owner-drawn
  playlist.
- Metadata + album art via optional TagLibSharp, with filename fallback.
- Add files / add folder (recursive), clear, double-click-to-play.
- Auto-advance on track end, shuffle, repeat-all.
- Keyboard shortcuts: Space (play/pause), Ctrl+Left/Right (prev/next),
  M (mute toggle).
- `setup-naudio.ps1` dependency fetcher (NuGet -> `lib\`, with `Unblock-File`).
- `New-Visualizer` stub with the FFT integration recipe documented inline.

[Unreleased]: https://github.com/MikereDD/It-Works-On-My-Machine/commits/main
[0.4.6]: https://github.com/MikereDD/It-Works-On-My-Machine/tree/main/Windows/Powershell/scripts/personaltools/Cadence
[0.4.5]: https://github.com/MikereDD/It-Works-On-My-Machine/tree/main/Windows/Powershell/scripts/personaltools/Cadence
[0.4.4]: https://github.com/MikereDD/It-Works-On-My-Machine/tree/main/Windows/Powershell/scripts/personaltools/Cadence
[0.4.3]: https://github.com/MikereDD/It-Works-On-My-Machine/tree/main/Windows/Powershell/scripts/personaltools/Cadence
[0.4.2]: https://github.com/MikereDD/It-Works-On-My-Machine/tree/main/Windows/Powershell/scripts/personaltools/Cadence
[0.4.1]: https://github.com/MikereDD/It-Works-On-My-Machine/tree/main/Windows/Powershell/scripts/personaltools/Cadence
[0.4.0]: https://github.com/MikereDD/It-Works-On-My-Machine/tree/main/Windows/Powershell/scripts/personaltools/Cadence
[0.3.0]: https://github.com/MikereDD/It-Works-On-My-Machine/tree/main/Windows/Powershell/scripts/personaltools/Cadence
[0.2.0]: https://github.com/MikereDD/It-Works-On-My-Machine/tree/main/Windows/Powershell/scripts/personaltools/Cadence
[0.1.0]: https://github.com/MikereDD/It-Works-On-My-Machine/tree/main/Windows/Powershell/scripts/personaltools/Cadence
