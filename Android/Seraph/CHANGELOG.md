# Changelog

All notable changes to Seraph are documented here.
The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.3.0] - 2026-06-14

### Fixed
- **Album match / rename failed with `ExceptionInInitializerError`.** The filename
  template compiled a control-character regex (`\x00-\x1F`) in a static field that
  some Android builds reject, which took down the whole renderer the first time it
  ran. Rewrote it with no compiled regex (pure-code sanitization), so matching and
  renaming work again.
- **Album match now pairs files by title.** Matching tries the leading track
  number, then song-title similarity (filenames usually contain the title),
  then sorted order — so a folder like `101-the_beatles-love_me_do.mp3` lines up
  with the release even when the numbering is disc-prefixed. The review screen
  reports the file/track counts (and any error) when nothing matches.
- **Crash when opening the tag editor or applying cover art.** Embedded/fetched
  artwork is now decoded downsampled and off the main thread, so large covers
  (1400px+) no longer exhaust memory. MusicBrainz lookups and album apply are
  also fully guarded — a bad response surfaces a message instead of crashing.

### Added
- **Multi-select in the library.** Long-press a track to start a selection, tap
  to add/remove, and use the select-all toggle to grab the whole folder. The
  album-match and rename actions then operate on just the selected files. Back
  clears the selection before leaving the folder.
- **In-app crash log.** Uncaught exceptions are recorded and shown under
  "Last crash" on the About screen, with copy/clear — so a crash can be reported
  without adb.
- **Album match (MusicBrainz)** — from inside an album folder (or a selection),
  tap the album button to search MusicBrainz for the release, pick the right one,
  and the app matches the folder's files to the tracklist (by track number or
  song title). Review the result, then apply in one pass: it writes tags
  (title, artist, album, album artist, track number/total, year) to every file
  and, optionally, embeds the cover art and renames the files from the template.
  Works on device and pCloud alike.
- **About screen** — app icon, version, credits (jaudiotagger, MusicBrainz +
  Cover Art Archive, pCloud), a source link, and a **Sign out of pCloud** action.
  Reached from the info button in the library top bar.

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

[Unreleased]: https://github.com/MikereDD/It-Works-On-My-Machine/compare/seraph-v0.3.0...HEAD
[0.3.0]: https://github.com/MikereDD/It-Works-On-My-Machine/compare/seraph-v0.1.0...seraph-v0.3.0
[0.1.0]: https://github.com/MikereDD/It-Works-On-My-Machine/releases/tag/seraph-v0.1.0
