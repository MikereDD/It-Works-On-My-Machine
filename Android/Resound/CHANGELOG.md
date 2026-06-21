# Changelog

All notable changes to Resound are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.6.2] - 2026-06-21

### Added
- **About dialog**: an "About" button in the editor header opens app version
  (read from PackageInfo), a short description, links to the repo and changelog,
  and FFmpegKit (LGPL) attribution.

[0.6.2]: https://github.com/MikereDD/It-Works-On-My-Machine/tree/main/Android/Resound

## [0.6.0] - 2026-06-21

### Added
- **Visual identity**: a "darkroom for sound" theme — deep ink background, a
  single signal-teal accent pulled from the waveform, amber reserved for the live
  record state, monospace timecodes. Replaces the default Material palette.
- **Filled waveform**: the editor waveform now renders as a filled, mirrored
  shape with a vertical teal gradient, plus grip handles and a brighter playhead.
- **Launcher icon**: adaptive + legacy PNG icons (teal waveform mark on ink)
  across all densities; dark window background removes the white launch flash.
- **Per-clip trim** in the timeline: drag a clip's left/right edge to set its
  source in/out (mix uses atrim); drag the body to move it.
- **Zoom & horizontal scroll** in the timeline: −/+ zoom changes the time scale;
  lanes share one synchronized horizontal scroll.

### Changed
- Editor restyled: scrollable layout, transport row (Open / Record / Play) with
  even widths, waveform in a panel, tonal op grid, secondary actions (Ringtone /
  Multitrack) grouped. Timeline lanes are now cards.
- `Clip` gains `sourceInMs`/`sourceOutMs`; `Effects.mixTimeline` trims each clip
  before delaying and mixing.

[0.6.0]: https://github.com/MikereDD/It-Works-On-My-Machine/tree/main/Android/Resound

## [0.5.0] - 2026-06-21

### Added
- **Multitrack timeline** (`feature/timeline`): a second screen reachable via the
  "Multitrack ▸" button. Add tracks, add clips from files (each decoded to its
  own waveform), drag clips horizontally to position them on a shared time axis,
  and mute tracks.
- **Mixdown export**: `Effects.mixTimeline` delays each clip to its start
  (adelay), applies track volume, and amix'es them (normalize=0) into a single
  file published to Music/Resound.
- `Timeline`/`Track`/`Clip` model; `TimelineScreen` UI; screen navigation in
  `MainActivity` between the editor and the timeline.

### Notes
- Clips span their full source; per-clip trimming within the timeline, plus
  horizontal zoom/scroll, are later refinements. The time axis currently fits
  the project (min 60s) to screen width.

[0.5.0]: https://github.com/MikereDD/It-Works-On-My-Machine/tree/main/Android/Resound

## [0.4.1] - 2026-06-21

### Added
- In-app playback: a Play/Pause button previews the loaded file. Playback runs
  from the current selection's start and stops at its end, and the waveform
  playhead tracks the position live. `AudioPlayer` wraps MediaPlayer; the player
  is prepared on open/record and released with the screen.

[0.4.1]: https://github.com/MikereDD/It-Works-On-My-Machine/tree/main/Android/Resound

## [0.4.0] - 2026-06-21

### Added
- **Voice recorder**: a Record/Stop button (with elapsed timer) captures from
  the mic via MediaRecorder (AAC/m4a). On stop the recording loads straight into
  the editor and a copy is saved to Music/Resound. Requests RECORD_AUDIO at
  first use.
- **Set as Ringtone**: sets the loaded file as the default ringtone. Inserts a
  copy into the MediaStore Ringtones collection and points the system default at
  it. Routes the user to the WRITE_SETTINGS grant screen when needed.
- `AndroidRecorder` (MediaRecorder) and `Ringtones` helper.

### Changed
- `Outputs.publishToMusic` returns `Published(uri, displayPath)` so callers can
  reuse the saved URI (recorder, ringtone).

[0.4.0]: https://github.com/MikereDD/It-Works-On-My-Machine/tree/main/Android/Resound

## [0.3.2] - 2026-06-21

### Changed
- Outputs now save to the shared **Music/Resound** library instead of the
  app-private folder — browsable in any file manager, survives uninstall.
  FFmpeg writes to a cache temp file, then it's published via MediaStore
  (`RELATIVE_PATH = Music/Resound`) on API 29+, or written to the public Music
  dir on API 26-28.
- Status line now reports the save location ("Saved to Music/Resound/…").

### Added
- `WRITE_EXTERNAL_STORAGE` (maxSdk 28) + a one-time runtime request for the
  legacy publish path; 29+ needs no permission.

[0.3.2]: https://github.com/MikereDD/It-Works-On-My-Machine/tree/main/Android/Resound

## [0.3.1] - 2026-06-21

### Changed
- FFmpeg now resolves from Maven Central instead of a vendored AAR:
  `com.moizhassan.ffmpeg:ffmpeg-kit-16kb:6.1.1` — a community ffmpeg-kit
  republish rebuilt for the 16KB page size Android 15 / API 35 requires (the old
  4KB-aligned 6.0 binaries SIGBUS on modern devices). Keeps the
  `com.arthenica.ffmpegkit` API; pulls smart-exception transitively.
- Removed the vendoring machinery: `flatDir` repo, `app/libs/`, the
  `BuildConfig.HAS_FFMPEG` opt-in flag, the reflective engine load, and the
  opt-in `src/ffmpeg/kotlin` source set. `FFmpegKitRunner` is now always
  compiled and selected directly.

[0.3.1]: https://github.com/MikereDD/It-Works-On-My-Machine/tree/main/Android/Resound

## [0.3.0] - 2026-06-21

### Added
- All remaining actions wired through a shared run path (resolve -> Effects ->
  FFmpegRunner -> save + media scan):
  - Immediate: **Vocal Remove** (center-channel).
  - Parameter dialogs (`OpControls`): **Volume**, **Speed**, **Pitch**,
    **Fade**, **EQ** (single band), **Convert** (format picker),
    **Compress** (bitrate picker).
  - Second-file pickers: **Mix**, **Concat**.
- `EditOp` enum + `OpParams` + `OpDialog` (sliders / choice chips) for parameter
  collection.

### Changed
- Editor action buttons are all enabled once a file is loaded; `runSingle` /
  `runDual` replace the Trim-only handler.

### Notes
- Effects apply to the whole file except Trim (which uses the selection);
  per-selection application of other effects is a later refinement.
- Real FFmpeg AAR still required for any of these to actually execute; without
  it the stub reports the engine is missing.

[0.3.0]: https://github.com/MikereDD/It-Works-On-My-Machine/tree/main/Android/Resound

## [0.2.1] - 2026-06-21

### Added
- `MediaCodecWaveformExtractor` — real PCM decode (MediaExtractor + MediaCodec)
  folded into min/max peak buckets as it streams, so the waveform reflects the
  actual audio. Handles 16-bit and float PCM; collapses channels by per-frame
  peak. Falls back to the synthesised shape if decoding fails.
- "Decoding waveform…" status while extraction runs.

### Changed
- DI now provides `MediaCodecWaveformExtractor` (needs app `Context`, passed
  from `ResoundApp`) instead of the placeholder extractor.

### Notes
- Full-file decode; a few-minute track takes ~1–2s. A seek-sampled fast path is
  a possible later optimisation.

[0.2.1]: https://github.com/MikereDD/It-Works-On-My-Machine/tree/main/Android/Resound

## [0.2.0] - 2026-06-21

### Added
- Real SAF file picker (`OpenDocument`, audio/* + video/*); loads source
  metadata (duration, sample rate, channels) into `AudioFile` via
  `MediaExtractor`.
- `AudioFiles.resolveToCache()` — copies a `content://` source into cacheDir so
  FFmpeg has a real path to read.
- `core/io/Outputs` — output path in the app's external Music dir plus a
  `MediaScanner` pass so results show up in media apps.
- `FFmpegKitRunner` — real `FFmpegRunner` over the ffmpeg-kit wrapper API, with
  completion → result and statistics → progress mapping, and cancellation.
- First end-to-end action: **Trim** → `Effects.trimEncode` → FFmpeg → save +
  scan, with live progress and a status line.
- `flatDir` repo + vendored-AAR wiring; `app/libs/README.md` documents how to
  obtain/build `ffmpeg-kit-audio.aar` (Maven binaries are gone post-retirement).
- kotlinx-coroutines-android dependency made explicit.
- FFmpeg backend made opt-in: the build is green without the AAR (falls back to
  `StubFFmpegRunner`); dropping `ffmpeg-kit-audio.aar` into `app/libs/` compiles
  in `FFmpegKitRunner` (opt-in source dir) and auto-selects it via
  `BuildConfig.HAS_FFMPEG`.

### Changed
- DI now defaults to `FFmpegKitRunner` (requires the AAR in `app/libs/`; swap to
  `StubFFmpegRunner` to run the UI without it).
- Editor starts empty with an "Open file" action instead of a demo track.

### Fixed
- Rotating the device no longer drops the loaded file back to the Open screen
  (activity now handles config changes instead of recreating).
- Dragging one selection handle no longer snaps the other back to its start —
  the drag gesture was reading stale selection values captured by `pointerInput`
  (fixed with `rememberUpdatedState`).

### Notes
- Waveform shape is still the synthesised placeholder; only its length reflects
  the real file. Real `MediaCodec` decode is planned for v0.2.1.
- Buttons other than Trim remain TODO.

[0.2.0]: https://github.com/MikereDD/It-Works-On-My-Machine/tree/main/Android/Resound

## [0.1.0] - 2026-06-21

### Added
- Initial project scaffold against the standard typezero Android build matrix
  (AGP 8.7.2, Kotlin 2.0.21, Compose BOM 2024.10.01, compileSdk/targetSdk 35,
  minSdk 26, Java 17, manual DI, arm64-v8a only).
- `core/ffmpeg`: `FFmpegRunner` interface + `StubFFmpegRunner` placeholder.
- `core/audio`: `AudioFile` model, `WaveformExtractor` interface +
  `FakeWaveformExtractor` for UI development.
- `feature/effects`: `Effects` builders mapping every planned operation
  (trim, concat, mix, fade, volume, speed, pitch, EQ, vocal-remove, convert,
  compress, video-to-audio) to FFmpeg argument lists.
- `feature/edit`: `WaveformView` Canvas widget with draggable two-handle
  selection + playhead, and an `EditScreen` shell rendering it.
- `feature/record`: `Recorder` interface stub.
- Manual DI container, Application, single-activity host, minimal dark theme.

### Notes
- No FFmpeg backend is wired in yet (see README → "FFmpeg dependency").
- No file picker yet; the editor renders a synthesised demo waveform.

### Fixed
- Editor content now clears the status bar / home indicator via
  `safeDrawingPadding()` under edge-to-edge.

[0.1.0]: https://github.com/MikereDD/It-Works-On-My-Machine/tree/main/Android/Resound
