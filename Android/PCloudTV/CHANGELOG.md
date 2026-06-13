# Changelog

All notable changes to **pCloud TV**. Newest first.
(Add release dates as you tag each version.)

---

## v4.4 — Generated playlists go to /Music/playlists

- "Generate playlists" now writes every generated .m3u into the central /Music/playlists folder (with absolute track paths) instead of dropping one inside each audio folder. They now appear in the Playlists view alongside your hand-saved ones.
- Generated playlists are named by their folder's path under the scanned root (e.g. "Classical - Alexandra Streliski.m3u") so same-named folders don't collide, and regenerating overwrites by name rather than piling up duplicates. Hand-saved playlists in /Music/playlists are left untouched.

---

## v4.3 — Manage saved playlists

- Saved playlists now appear in a **Playlists** folder at the pCloud root, alongside Recently-Played, Music, and Video (it lists the .m3u files in /Music/playlists).
- Tapping a saved playlist opens a manager with **Play**, **Rename**, **Delete**, and full track editing:
  - **Remove tracks** with a per-row ×.
  - **Add tracks** via a built-in folder picker that walks your pCloud library; tapped files are appended.
  - **Save changes** writes the edited list back to the same .m3u.
- Added `renameFile` and a raw playlist reader to the pCloud client to support the above.

---

## v4.2 — Manage recently-played history

- You can now remove saved entries from Recently-Played. Each entry has a remove (×) button, plus a "Clear all" action at the top of the list — handy for clearing out stale entries that point at files since renamed or deleted in pCloud (the "File not found" case).
- The Recently-Played folder continues to sit at the pCloud root alongside Music and Video whenever there's any history, and the list now refreshes immediately after a removal.

---

## v4.1 — Landscape audio layout + smaller seek dot

- The audio now-playing screen is now orientation-aware. In landscape it switches to a side-by-side layout (album art on the left, title and controls on the right) so the play button no longer overlaps the title in the short vertical space. Portrait keeps the centered hero with bottom controls.
- The seek-bar thumb is smaller (10dp) on both the video and audio sliders for a cleaner scrubber.

---

## v4.1 — Landscape audio layout + finer seek dot

- The audio now-playing screen is now orientation-aware. In landscape it switches to a side-by-side layout (cover art on the left, title and controls on the right) so the play button no longer overlaps the title. Portrait keeps the centred hero layout.
- Slimmed the seek-bar thumb a touch more (both the video and audio sliders) so it reads as a fine scrubber dot rather than a large handle.

---

## v4.0 — Player visual polish

- **Gradient scrims:** the player no longer dims the whole frame. Soft dark gradients sit only behind the top and bottom controls, so the middle of the picture stays bright.
- **Matched Cast/Tracks buttons:** the Cast button now uses the same translucent rounded chip as Tracks, so the two read as one tidy control group.
- **Refined seek bar:** slimmer thumb, dimmer inactive track, and tabular time figures (bright elapsed, dimmer total) that don't jitter as the clock ticks. Applied to both the video controls and the audio now-playing screen.
- **Play-button depth:** the play/pause circle gets a soft accent-tinted shadow so it feels tactile rather than flat.
- **Reveal animation:** the top bar slides down and the bottom controls slide up (with a fade) when the controls appear and disappear.

---

## v3.9 — Title-over-controls header layout

- The video player's title now sits on its own full-width line, with the Cast and Tracks buttons grouped on a row directly beneath it. Long filenames get the whole width before truncating, and the controls read as a tidy header block.

---

## v3.8 — Clean player top bar in portrait

- Rebuilt the video player's top bar as a single row: the title now takes the available width and truncates with an ellipsis, while the Cast and Tracks buttons stay grouped at the right. They no longer overlap the title (or each other) in portrait, where a long filename used to run underneath the controls.
- The audio now-playing screen keeps its Cast button in the top-right corner as before.

---

## v3.7 — Cast/Tracks button overlap fix

- In the video player, the Cast button no longer overlaps the **Tracks** pill in the top-right corner. When video controls are visible, Cast now sits to the left of the Tracks button; on the audio now-playing screen (no Tracks button) Cast stays at the edge as before.

---

## v3.6 — Immersive fullscreen player

- While the player is open, the status and navigation bars are now hidden on mobile, so video (and the now-playing screen) isn't framed by the system UI. Swipe from an edge to reveal the bars transiently; they're restored when you leave the player.

---

## v3.5 — Recently-Played folder (sorted by type)

- The old root "recently played" strip is gone; recents now live in a **Recently-Played** folder at the root, next to Music and Video.
- Inside it are **Audio** and **Video** subfolders; each past session is auto-sorted into one by its file type (no re-tagging needed). Tapping an entry resumes that queue, same as before.
- Keeps the curated root clean — three folders, all the same shape.

---

## v3.4 — Curated root (Music / Video only)

- The pCloud root now shows only the **Music** and **Video** folders; everything else at the top level is hidden. Browsing into those folders works normally. (The allowed set is a single constant, easy to extend later.)

---

## v3.3 — Version shown in the header

- A faint version tag (e.g. `v3.3`) now sits in the browse header next to the Cast/⋮ controls, so you can tell at a glance which build you're running without opening the About dialog.

---

## v3.2 — Track tags + cover art on the now-playing screen

- The audio now-playing screen now reads **embedded tags** from the file and shows the real **title**, **artist • album**, and **embedded cover art** instead of the raw filename — pulled live from VLC's metadata, no file changes.
- **Untagged files get a cleaned-up name** as a fallback: the leading track number is stripped, separators become spaces, and words are title-cased (e.g. `02-modest_mouse-the_world_at_large` → "Modest Mouse — The World At Large").
- Cover art falls back to the music-note placeholder when a file has none.

---

## v3.1 — Audio now-playing screen

- **Audio plays like a music app, not a black screen.** When the current track has no video, the player now shows a proper now-playing screen — album-art placeholder, track title, playlist position, and always-visible transport controls — instead of VLC's empty black surface.
- This also fixes audio dropping to a black void after **rotating the device** or **leaving and returning to the app**: the now-playing screen is drawn by the UI layer, so it survives both. (Video playback is unchanged.)

---

## v3.0 — Multiple accounts + a cleaner header

- **Multiple accounts / quick switch:** sign in to more than one pCloud account and switch between them instantly. Accounts are remembered (labelled by email), with "Add account" for a fresh sign-in and per-account switching from the menu.
- **Cleaner header:** the row of labelled buttons (Select, Save .m3u, Sign out) that was crowding the title and breadcrumb is now a single **⋮ menu**. The header is just title + breadcrumb + Cast + ⋮, so long folder names and the full path have room to breathe.
- Sign out now signs out of the active account and drops back to another signed-in account if you have one.

---

## v2.9.2 — Back to the list, polished

- Reverted the v2.9.1 leanback poster rows: the home is the clean vertical list again.
- Polish: tighter cards, stronger focus glow + press feedback, file type/size in the subtitle, and a tappable breadcrumb (tap any parent in the path to jump there).

---

## v2.9.1 — Folders as rows

- While browsing, a folder's contents are grouped into horizontal poster rows by kind (Folders, Videos, Music, Playlists, Images). Search results and multi-select fall back to the vertical list.

---

## v2.9 — TV experience

- Recently played is now a horizontal poster row with thumbnails and focus scale/glow animations (leanback-style home, built on the existing Compose UI).

---

## v2.8.2 — Thumbnails

- The folder browser now shows pCloud thumbnails for image and video files, falling back to the type icon when a thumbnail isn't available.

---

## v2.8.1 — Recently played

- Recently-played history on the home screen: a Continue card plus a "Recently played" list, each resuming where you left off.

---

## v2.8 — Library & discovery

- Search box in every folder: filter the current folder's items by name as you type.

---

## v2.7 — Track switching

- Audio/subtitle choice now sticks: pick a track manually (a language, or subtitles off) and it carries to the next track in a playlist instead of resetting to English each time.
- Music keeps playing in the background when you leave the app; video stops automatically.

---

## v2.6 — Playback stops when it should

- Playback now stops when you leave or background the app (Home, screen off, app switch) instead of playing on. Casting is exempt — the TV keeps playing.
- Auto-pause when a phone call comes in or another app takes over audio (audio focus).
- Note: this turns off silent background (screen-off) audio. A toggle can be added if you want both.

---

## v2.5.3 — Continue + short shared links

- Added a "Continue" card at the top of the library that resumes the last thing you played — the right track of a playlist and the spot within it.
- Shared links: short/redirect links (e.g. tinyurl) now resolve to the real pCloud link, so you can type a short URL instead of a long one (handy on a TV).

---

## v2.5.2 — TV sign-in navigable with a remote

- TV sign-in: the sign-in screen is now fully navigable with a D-pad — it gets initial focus on open and each button is a single focus stop, so the pCloud login, access-token field, and shared-link field are all reachable with a remote.
- The pCloud web login now shows a D-pad-driven pointer on Android TV / Google TV: move it with the arrow keys and press OK to click, so you can fill in the email/password fields (the on-screen keyboard opens when you click a field). This works around the fact that pCloud's web page can't be navigated by a remote on its own.
- The bulk playlist generator's Audiobooks shortcut now points to /Books/Audiobooks.

---

## v2.5.1 — Cast resume, resume memory & headset controls

- Casting: pausing and then resuming a movie no longer fails. The app re-resolves a fresh pCloud stream URL and reloads at the same spot when the old one has expired, and auto-recovers if the receiver drops out.
- Resume memory for video: playback position is remembered per file and now also while casting, so you pick up where you left off on the TV.
- Resume memory for music: each playlist remembers the track you were on (and the position within it), so reopening a playlist resumes at the right song and spot. Finishing a playlist resets it.
- Earbud / Bluetooth controls: play/pause, skip forward and skip backward from a headset now control playback (via a MediaSession), including with the screen off; the track title and play state show on the lock screen.

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
