# Changelog

All notable changes to **pCloud TV**. Newest first.
(Add release dates as you tag each version.)

---

## v2.5.1 — Cast resume, resume memory & headset controls

- Casting: pausing and then resuming a movie no longer fails. The app re-resolves a fresh pCloud stream URL and reloads at the same spot when the old one has expired, and auto-recovers if the receiver drops out.
- Resume memory for video: playback position is remembered per file and now also while casting, so you pick up where you left off on the TV.
- Resume memory for music: each playlist remembers the track you were on (and the position within it), so reopening a playlist resumes at the right song and spot. Finishing a playlist resets it.
- Earbud / Bluetooth controls: play/pause, skip forward and skip backward from a headset now control playback (via a MediaSession), including with the screen off; the track title and play state show on the lock screen.
- TV sign-in: the sign-in screen is now fully navigable with a D-pad — it gets initial focus on open and each button is a single focus stop, so the pCloud login, access-token field, and shared-link field are all reachable with a remote.

---

## v2.5 — 32-bit ARM support

- The APK now bundles both 64-bit (arm64-v8a) and 32-bit (armeabi-v7a) ARM libraries, so it installs on the Chromecast with Google TV and other 32-bit ARM devices. Previous builds were 64-bit only and silently failed to install on those.
- TV login: the cookie banner is now auto-accepted and the web login is focusable with the D-pad, so sign-in works with a remote.

---

## v2.4 — About dialog & header polish

- Added an **About** dialog (info button in the header) showing the installed app version and a link to the changelog on GitHub.
- Polished the header: on narrow/portrait screens the title and action buttons now stack into two rows instead of overlapping; wide screens keep the single-row layout.
- Long folder names in the header now truncate cleanly instead of overlapping.
- Files now show the correct type icon (image, video, audio, document) instead of a music note for everything.

---

## v2.3.1 — Cast crash fix

- Fixed a crash when opening the Cast device picker. The app theme is now AppCompat-derived so the picker dialog can inflate; the app's appearance is unchanged.

---

## v2.3 — Cast discoverability

- Cast now initializes at app startup, so device discovery begins immediately and the Cast button appears as soon as a Chromecast / Google TV is found.
- Added a persistent Cast button to the browse header (not just the player), so it's easy to find once signed in.

---

## v2.2 — Chromecast

- Cast playback to a Chromecast / Google TV via the Cast button in the player (Google Default Media Receiver).
- Works for audio (MP3/AAC/FLAC/Opus) and MP4/H.264 video; MKV/HEVC isn't supported by the stock receiver.
- Fully isolated: when no Cast session is active, local LibVLC playback is byte-for-byte unchanged.

---

## v2.1 — Protect the playlists folder

- The clean/regenerate step (Replace existing) now skips `/Music/playlists` entirely, so curated playlists built from a song selection are never deleted by a bulk regenerate.

---

## v2.0 — Playlists folder

- Playlists built from a song selection now save to a dedicated **`/Music/playlists`** folder (auto-created), instead of the current folder. Entries use absolute paths so they play from anywhere.

---

## v1.9 — Reliable queue playback

- Fixed playlists stopping after the first track: the player stays mounted for the whole queue and swaps media in place, so auto-advance works on-screen and in the background.

---

## v1.8 — Background audio & clean regenerate

- **Background audio**: music continues when you leave the app, via a media foreground service. Video stops on leave (by design).
- **Clean regenerate**: the playlist generator can wipe all existing `.m3u`/`.m3u8` under a path before writing one per folder.

---

## v1.7 — Build playlists by tapping

- **Select** mode: tap tracks in a folder to check them, name the playlist, and save it as an `.m3u` (saved in tap order, into that folder).

---

## v1.6 — Shared links (no account)

- Open pCloud **public share links** (file or folder) with no account, from the sign-in screen.
- Uses pCloud's unauthenticated `showpublink` / `getpublinkdownload`; read-only, only what was shared is reachable.

---

## v1.5 — Polish

- Buffering spinner shown while a stream is loading or stalled.
- Playlist **track position** indicator ("TRACK N / M") in the player.

---

## v1.4 — Background audio & resume

- **Background audio**: music and audiobooks now keep playing with the **screen off**. A partial wake-lock keeps the CPU awake so audio doesn't stop; video still keeps the screen on so you can watch.
- **Resume where you stopped**: playback position is saved per file (throttled while playing, plus on pause and on exit) and restored the next time you open that file. Files played to the end reset so they start fresh.
- Resume positions are stored separately from the session, so signing out doesn't wipe them.
- Added the `WAKE_LOCK` permission.

> Scope: "screen off" covers the app being the foreground app with the display off. Bulletproof background playback after pressing Home / swiping the app away (plus lock-screen controls) would need a foreground media service — planned for a later release.

---

## v1.3 — Bulk playlist generation by path

- The **Save .m3u** action is now a dialog that takes a **pCloud path** (with one-tap **/Music** and **/Audiobooks** buttons).
- Generates recursively: one recursive scan of the path, then an `.m3u` written into **every subfolder that contains audio**, with a live progress overlay.
- Tracks are sorted naturally (so `2` comes before `10`); entries are relative filenames for reliable playback.

---

## v1.2 — Playlist generator

- Added a **Save .m3u** button in the folder browser that builds an `.m3u` of the current folder's audio/video files and uploads it into that pCloud folder.
- Entries are written as relative filenames so the playlist sits next to its media and resolves cleanly on playback.

---

## v1.1 — Playlist playback

- Open **`.m3u` / `.m3u8`** files and play their entries as a **queue**.
- **Auto-advance** to the next track at the end of each one; **skip previous/next** via on-screen buttons and media keys.
- Playlist entries resolve by filename within the same pCloud folder; absolute `http(s)` URLs play directly.
- **HLS `.m3u8`** manifests are detected and handed straight to VLC as a single stream.

---

## v1.0 — Initial release

- **Sign in** through pCloud's own web login, so **two-factor authentication** works; only the access token is stored on the device, never the password. Manual paste-a-token fallback included.
- **Browse** pCloud folders — D-pad on TV, touch on phone — with file-type icons and human-readable file sizes.
- **Playback** through the **VLC (LibVLC)** engine for wide codec support.
- **Auto-hiding controls**: play/pause, ±10s seek, scrub bar.
- **English audio + subtitles** auto-selected (subtitles off when there's no English track), with a manual **Tracks** picker to override audio/subtitle per file — by touch on mobile and by remote (Up/Menu) on TV.
- **Adaptive dark UI** that scales between phone and 10-foot TV layouts.
- **Free rotation** on phones; rotating keeps your place and keeps video playing.
- **Screen stays awake** during playback.
- Ships **arm64-v8a** native libraries (~58 MB APK; covers modern phones and Google TV).

---

## Companion tooling (outside the app)

- **`generate-playlists.ps1`** — a local PowerShell script (wired into `tool-menu.ps1`) that walks a music/audiobook library on disk and writes one `.m3u` per folder, in the same relative-filename format the app reads. Run it before syncing to pCloud, or use the app's built-in generator instead.
