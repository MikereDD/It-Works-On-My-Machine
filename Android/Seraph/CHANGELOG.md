# Changelog

All notable changes to Seraph are documented here.
The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.0] - 2026-06-14

First baseline of **Seraph** — a Material 3 / Jetpack Compose audio tagger for
Android, the tagging companion to the video-to-audio extractor.

### Added
- **Folder browsing** — the library navigates by directory rather than flattening
  everything into one list. On pCloud the two scan paths (`/Music`,
  `/Books/Audiobooks`) are the top-level entries; tap to descend into albums, tap a
  track to tag it, and Back (or the up arrow) climbs out. Rename acts on the
  current folder. Device browsing works the same from the picked tree.
- **Two storage sources** behind a `StorageSource` abstraction, switchable in the
  library: device (Storage Access Framework, persisted read/write) and **pCloud**
  (HTTP API). pCloud sign-in opens pCloud's real web login in a WebView (so
  Google sign-in and 2FA work) and captures the session's auth token — no app
  key, OAuth app, or redirect; region is auto-detected. Renames are a single
  server-side `renamefile`, and tag edits download to cache, edit, and re-upload.
  Scanning is scoped to `PCloudConfig.SCAN_PATHS` (`/Music`, `/Books/Audiobooks`).
- Recursive scan for taggable audio (`mp3`, `flac`, `m4a`, `mp4`, `ogg`, `opus`,
  `wav`, `aac`, `wma`).
- Read/write of title, artist, album, album artist, track no./total, disc, year,
  genre, comment, and embedded front-cover art via jaudiotagger (cache
  round-trip to satisfy scoped storage / the pCloud round-trip).
- **MusicBrainz** WS/2 lookup with full manual override, plus Cover Art Archive
  front covers; descriptive User-Agent + ~1 req/sec throttle. The editor returns
  to the library automatically after a successful save.
- **Per-directory batch renaming** from a token template (`{track} {total}
  {title} {artist} {album} {albumartist} {year} {disc}`). Values come from the
  tags (MusicBrainz once looked up, or manual edits); track falls back to
  sequential folder order and total to the folder's file count. Empty tokens
  collapse their separators; names are sanitized for Android and Windows (pCloud
  syncs back to Windows). Live preview, two-pass rename so a target can't clobber
  a sibling.
- Manual DI (`AppContainer` + `ViewModelFactory`), no Hilt/Dagger. PNG launcher
  icons (wing + note) at all mipmap densities; no vector drawables.

### Known gaps / next up
- AcoustID fingerprint identification for files with no usable tags (lookup
  currently keys off existing tags / filename).
- pCloud folder browser — currently lists from a configured root folder; the
  token is in plain `SharedPreferences` (swap to `EncryptedSharedPreferences`).
- Whole-album batch tagging; no undo yet (saves and renames are immediate).

[Unreleased]: https://github.com/MikereDD/It-Works-On-My-Machine/compare/seraph-v0.1.0...HEAD
[0.1.0]: https://github.com/MikereDD/It-Works-On-My-Machine/releases/tag/seraph-v0.1.0
