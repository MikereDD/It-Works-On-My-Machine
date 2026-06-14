# Siphon

Extract audio from a video — from a **local file** or a **link** — in the format
and quality you want, with full metadata tagging. Android / Kotlin + Jetpack
Compose.

**Latest version: 0.1.0** · [Changelog](https://github.com/MikereDD/It-Works-On-My-Machine/blob/main/Android/Siphon/CHANGELOG.md)

📦 **Download:** [Siphon-v0.1.0.apk](https://github.com/MikereDD/It-Works-On-My-Machine/raw/main/Android/Siphon/releases/Siphon-v0.1.0.apk) — arm64-v8a, ~78 MB
*(committed to `releases/` via Git LFS; see [Build](#build) for other ABIs)*

## What it does

- **Local videos** — a searchable list of everything MediaStore knows about.
  Tap one, pick a format, tag it, extract.
- **Links** — paste a URL (or `Share → Siphon` from another app). The stream is
  pulled and the audio extracted into your chosen format.
- **Best quality by default** — the *Keep original* option copies the source
  audio stream with no re-encoding (zero generation loss). Switch to MP3 / M4A /
  Opus / FLAC / WAV with bitrate presets when you want a specific container.
- **Tagging for both sources** — title, artist, album, album artist, genre,
  year, track and comment are written into the output, plus optional
  source-metadata and (for links) embedded thumbnail cover art.
- Finished files land in **Music/Siphon** so any player picks them up.

## How it works

Both sources use [`youtubedl-android`](https://github.com/yausername/youtubedl-android)
(the maintained `io.github.junkfood02` fork), which bundles yt-dlp, Python and FFmpeg —
but they take different paths because yt-dlp only understands URLs:

- **Links** go through yt-dlp, which downloads and extracts the audio. Tags are
  injected into its FFmpeg pass via `--postprocessor-args "ExtractAudio:-metadata ..."`
  (see `engine/CommandFactory.kt`).
- **Local files** are handed straight to the bundled FFmpeg binary
  (`<nativeLibDir>/libffmpeg.so`) — extraction, transcode, bitrate and `-metadata`
  tagging in one pass (see `engine/FfmpegArgs.kt` / `engine/LocalFfmpegExtractor.kt`).

Both builders are pure and unit-tested, and present the same format / quality /
tagging options to the UI. This replaces the old ffmpeg-kit approach, retired in 2025.

## Build

Standard Android Studio project — open `Android/Siphon/` and run, or:

```bash
./gradlew :app:assembleRelease
```

Build matrix: AGP 8.7.2 · Gradle 8.9 · Kotlin 2.0.21 · Compose BOM 2024.10.01 ·
compileSdk/targetSdk 35 · minSdk 26 · Java 17 · manual DI.

> **Note on size & ABIs.** The bundled Python + FFmpeg binaries are large, so the
> build targets a single ABI — **arm64-v8a** (modern phones, including Pixels) —
> and skips the universal APK, which was exhausting Gradle's heap during packaging.
> To build for other devices, add ABIs back to the `splits { abi { include(...) } }`
> block in `app/build.gradle.kts`; for a shareable multi-device build use an App
> Bundle: `./gradlew :app:bundleRelease`. `android:extractNativeLibs="true"` is
> required for the bundled binaries to run. Built APKs are committed to
> `releases/` as `Siphon-v<version>.apk` (tracked via Git LFS), which is where the
> download link above resolves.

## Permissions

- `READ_MEDIA_VIDEO` (API 33+) / `READ_EXTERNAL_STORAGE` (≤32) — list local videos.
- `INTERNET` — link extraction.

## Tests

```bash
./gradlew :app:testDebugUnitTest
```

`CommandFactoryTest` covers the yt-dlp (link) args — format/bitrate selection,
thumbnail embedding, and tag quoting/escaping. `FfmpegArgsTest` covers the local
FFmpeg args — codec/bitrate selection, VBR vs. CBR, unquoted `-metadata` tokens,
and copy-container mapping from the source codec.

## Usage note

Only extract audio from content you own or otherwise have the right to use.

---
Part of [It-Works-On-My-Machine](https://github.com/MikereDD/It-Works-On-My-Machine).
