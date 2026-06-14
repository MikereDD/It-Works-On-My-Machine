# Changelog

All notable changes to Siphon are documented here.
The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.2.0] - 2026-06-14
### Added
- **Cookies support** — load a Netscape `cookies.txt` (exported from a signed-in
  browser) from the Link screen, passed to yt-dlp via `--cookies` to get past
  YouTube's "Sign in to confirm you're not a bot" wall. Stored in app storage and
  reusable across launches; removable from the same screen.
- **YouTube player selector** on the Link screen (Default / TV / Web / iOS / Mobile).
  Switching the impersonated client is the common workaround for YouTube
  `HTTP Error 403`; passed through as `--extractor-args youtube:player_client=<client>`.
- **Update extractor** action in the top-bar menu (stable or nightly channel),
  wrapping `YoutubeDL.updateYoutubeDL`. Refreshes the bundled yt-dlp without
  rebuilding the app — the practical fix when YouTube links start returning
  `HTTP Error 403` because the bundled binary has gone stale. Reported via a snackbar.

### Fixed
- Local-file extraction now invokes the bundled **FFmpeg binary directly** instead
  of yt-dlp. yt-dlp only handles URLs, so local paths were failing with
  `ERROR: [generic] '/storage/...' is not a valid URL`. Links still use yt-dlp.
  Local extraction reads the MediaStore path when accessible and falls back to the
  content URI under scoped storage.

### Changed
- Build now targets the **arm64-v8a** ABI only and skips the universal APK (the
  all-ABI artifact was OOM-ing the packaging task). Add ABIs back to the `splits`
  block for other devices, or use `./gradlew :app:bundleRelease` for a shareable
  multi-device build.

## [0.1.0] - 2026-06-13
### Added
- Initial release of **Siphon**, a Google/Android audio extractor.
- Unified extraction engine built on `youtubedl-android` (yt-dlp + bundled
  Python + FFmpeg) that handles **both local video files and remote links**
  through one pipeline.
- Searchable on-device video picker backed by MediaStore.
- "Audio from a link" tab with clipboard paste and a `Share → Siphon` intent
  filter for sending URLs from other apps.
- Format options: keep-original (lossless copy), MP3, M4A/AAC, Opus, FLAC, WAV.
- Bitrate presets for lossy formats (VBR best, 320/256/192/128/96 kbps).
- Audio tagging for either source: title, artist, album, album artist, genre,
  year, track, comment; optional source-metadata embed and (links) thumbnail
  cover art.
- Output exported to the shared **Music/Siphon** library via MediaStore.
- Live progress with cancel, plus a recent-jobs list.
- Per-ABI APK splits and Git LFS configuration for release binaries.

[Unreleased]: https://github.com/MikereDD/It-Works-On-My-Machine/compare/siphon-v0.2.0...HEAD
[0.2.0]: https://github.com/MikereDD/It-Works-On-My-Machine/releases/tag/siphon-v0.2.0
[0.1.0]: https://github.com/MikereDD/It-Works-On-My-Machine/releases/tag/siphon-v0.1.0
