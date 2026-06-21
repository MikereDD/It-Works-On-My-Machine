<p align="center">
  <img src="https://github.com/MikereDD/It-Works-On-My-Machine/raw/main/Android/Resound/icon.png" width="120" alt="Resound" />
</p>

# Resound

A personal, ad-free audio editor and multitrack mixer for Android. Open or
record audio, edit it, arrange clips across tracks, and export — all processing
handled by FFmpeg, with results saved to your shared `Music/Resound` library.

Built with Kotlin and Jetpack Compose.

## Download

**[Download the latest APK (v0.6.2)](https://github.com/MikereDD/It-Works-On-My-Machine/raw/refs/heads/main/Android/Resound/releases/Resound-v0.6.2.apk)**

arm64-v8a only. Sideload-friendly; no Play Store, no account.

## Features

- **Editor** — open any audio (or video) file via the system picker, see a real
  `MediaCodec`-decoded waveform, and drag a two-handle selection.
- **Eleven operations** — Trim, Mix, Concat, Fade, Volume, Speed, Pitch, EQ,
  Vocal Remove, Convert, Compress — each wired end to end through FFmpeg with
  live progress, saving the result to `Music/Resound`.
- **Recorder** — one-tap voice recording (AAC/m4a) that loads straight into the
  editor and saves a copy.
- **Playback** — preview the loaded file or the current selection with a live
  playhead.
- **Set as ringtone** — make any loaded file the system default ringtone.
- **Multitrack** — stack tracks, add clips, drag to position, drag clip edges to
  trim, zoom and scroll the time axis, mute tracks, and export a mixdown
  (`atrim` + `adelay` + `amix`).
- **About** — version, links, and attribution from the editor header.

## Status — v0.6.2

Feature-complete for the core workflow: single-file editing, recording,
playback, ringtones, and multitrack mixing, with the Resound visual identity
(dark theme, signal-teal accent, adaptive launcher icon) and an About dialog.

## Roadmap

| Version | Goal |
|---------|------|
| 0.1.0   | Scaffold + waveform editor shell |
| 0.2.0   | File picker (SAF), `FFmpegKitRunner`, **Trim** end to end ✓ |
| 0.2.1   | Real `MediaCodec` waveform decode ✓ |
| 0.3.0   | Wire all remaining actions ✓ |
| 0.4.0   | Voice recorder, set-as-ringtone ✓ |
| 0.4.1   | In-app playback ✓ |
| 0.5.0   | Multitrack timeline ✓ |
| 0.6.0   | Visual identity, launcher icon, clip trim + zoom/scroll ✓ |
| 0.6.2   | About dialog ✓ |
| later   | RMS waveform rendering; quality vocal removal (on-device Demucs/Spleeter) |

## FFmpeg dependency

The app talks to FFmpeg through `FFmpegRunner`, implemented by `FFmpegKitRunner`
over the ffmpeg-kit wrapper API. arthenica's ffmpeg-kit was retired and pulled
from Maven Central, so this uses a community republish rebuilt for the **16KB
page size** that Android 15 / API 35 requires:

```
implementation("com.moizhassan.ffmpeg:ffmpeg-kit-16kb:6.1.1")
```

It keeps the original `com.arthenica.ffmpegkit` API and pulls `smart-exception`
transitively. Nothing to vendor — sync and build. Swap the coordinate if you
prefer another republish (e.g. `io.github.maitrungduc1410:ffmpeg-kit-audio:6.0.1`,
which is FFmpeg 6.0 and not 16KB-aligned).

## Build

Standard matrix: AGP 8.7.2, Gradle 8.9, Kotlin 2.0.21, Compose BOM 2024.10.01,
compileSdk/targetSdk 35, minSdk 26, Java 17. arm64-v8a only (FFmpeg native libs).

```
./gradlew :app:assembleRelease
```

> Generate the Gradle wrapper once locally with `gradle wrapper --gradle-version 8.9`
> (wrapper jar/scripts are intentionally not committed).

## Changelog

See [CHANGELOG.md](https://github.com/MikereDD/It-Works-On-My-Machine/blob/main/Android/Resound/CHANGELOG.md).
