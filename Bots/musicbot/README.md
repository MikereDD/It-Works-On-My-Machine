# 🎵 Sandalphon (MusicBot)

> A typezerø Project
> Built to work. Refined to feel right.

---

## 🚀 Overview

Sandalphon is a Telegram music bot that:

* downloads audio from supported sources (yt-dlp)
* supports search + direct links
* cleans filenames and metadata
* uses real metadata (artist/title) via yt-dlp
* enforces `Artist - Song` format for all audio
* delivers Telegram-ready audio
* supports playlists
* supports intelligent playlist ingestion
* processes requests through a queue (stable under load)
* caches audio for instant reuse
* caches metadata for faster repeated requests
* builds a **searchable local music library**
* allows playback from stored tracks
* cleans up chat noise after processing
* runs on local Bot API for performance
* supports large file delivery (Local API)
* accepts plain text (no command required)
* supports Spotify metadata → YouTube/yt-dlp matching
* supports admin-only `/reload` and `/restart` controls
* uses unified live progress/status messages
* caches and reuses album artwork intelligently

---

## 📦 Version Notes

### v1.0 → v1.7

*(unchanged — same as your current file)*

---

### v1.8

* embeds album art into audio files (thumbnail support)
* writes full ID3 metadata (artist, title, album, year)
* improves Telegram player display and media player compatibility
* produces cleaner, more professional audio files

---

### v1.9

* adds Spotify metadata → YouTube/yt-dlp matching
* Spotify links are used for accurate metadata
* improves match precision using real track data
* does not download Spotify audio directly

---

### v2.0

* introduces **library mode**
* automatically stores downloaded tracks in a searchable index
* `/library` shows recent stored tracks
* `/find <query>` searches your library
* `/play <query>` plays a track from your library instantly
* `/clearlibrary` resets the library index
* transforms the bot into a **personal music system**

---

### v2.1

* adds admin-only `/reload` command
* adds admin-only `/restart` command
* supports live config/state reload workflow
* supports full process restart from inside Telegram
* improves testing workflow when running inside tmux

---

### v2.2

* introduces unified live progress/status messages
* replaces noisy multi-message updates with a single evolving status message
* adds visual progress bars during processing
* improves perceived responsiveness during downloads and tagging
* cleans up Telegram chat flow significantly


---

### v2.3

* introduces smarter fuzzy library matching
* adds typo-tolerant `/find` and `/play`
* improves artist/title ranking logic
* adds weighted search scoring
* deduplicates library entries using artist/title identity
* tracks local play counts for future ranking improvements


---

### v2.4

* introduces album and artist browsing
* adds `/artists` and `/artist <artist>`
* adds `/albums` and `/album <album or artist>`
* groups tracks by album and artist metadata
* improves library navigation and collection browsing
* pushes Sandalphon further toward media-server behavior


---

### v2.5

* introduces smart album art caching
* adds reusable artwork cache/index system
* falls back to cached artwork when fresh thumbnails are unavailable
* improves consistency of Telegram audio cards
* reduces repeated artwork processing/download overhead
* expands cache reporting with artwork statistics


---

### v2.6

* introduces playlist ingestion and batch importing
* adds `/playlist <playlist url>`
* adds `/playlists`
* supports flat playlist scanning without immediate downloads
* skips existing library tracks when possible
* tracks playlist import history and statistics
* improves large-scale library population workflows

---

## 🧠 Core Flow

```id="flow1"
Input → Playlist Import → Queue → Progress UI → Resolve → Metadata/Spotify → Cache Metadata → Download → Cache Audio → Cache Art → Library Index → Tag (ID3 + Art) → Deliver
```

---

## 🧰 Commands

```id="cmds1"
/music <url or search>
/playlist <playlist url>
/playlists
/queue
/cache
/library
/artists
/artist <artist>
/albums
/album <album or artist>
/find <artist or song>
/play <artist or song>
/clearcache
/clearlibrary
/reload
/restart
/id
/help
```

---

## 💡 Usage

```text id="usage1"
/music The Smiths - How Soon Is Now?
```

or simply:

```text id="usage2"
The Smiths - How Soon Is Now?
```

Spotify links:

```text id="usage3"
https://open.spotify.com/track/...
```

Play from your library:

```text id="usage4"
/play The Smiths
```

Browse artists:

```text id="usage6"
/artists
/artist Deftones
```

Browse albums:

```text id="usage7"
/albums
/album White Pony
```

Import playlists:

```text id="usage8"
/playlist https://youtube.com/playlist?list=...
```

Reload or restart the bot from Telegram:

```text id="usage5"
/reload
/restart
```

---

## ⚙️ Config Notes

Config file: `musicbotrc.py`

Important fields:

```id="cfg1"
BOT_TOKEN
ALLOWED_USER_IDS
ADMIN_USERS
BASE_DIR
DOWNLOAD_DIR
LOG_FILE
CACHE_ENABLED
CACHE_DIR
MAX_FILE_MB
ART_CACHE_DIR
SPOTIFY_METADATA_ENABLED
SPOTIFY_CLIENT_ID
SPOTIFY_CLIENT_SECRET
```

---

## 🔐 Access Control

```id="sec1"
ADMIN_USERS → always allowed  
ALLOWED_USER_IDS → optional whitelist  
empty ALLOWED_USER_IDS → public bot
```

---

## 🧪 Known Behavior

* Spotify links → metadata matching only (no direct audio)
* Amazon Music → fallback search
* YouTube/SoundCloud → primary sources
* Local Bot API removes standard Telegram limits
* cache is query-based (exact match required)
* metadata cache reduces repeated lookups
* library search supports fuzzy matching and typo tolerance
* album/artist browsing depends on available metadata quality
* artwork cache may reuse album art across related tracks
* plain text auto-trigger may ignore very short or generic messages
* `/reload` and `/restart` are admin-only controls
* queue/progress messages auto-update and self-clean when possible
* playlist imports attempt duplicate skipping using library identity

---

## ⚠️ Gotchas

* ffmpeg must be installed
* yt-dlp must be in PATH
* permissions required for NVMe paths
* some sources may require cookies
* first-time requests still require metadata lookup
* library index depends on cached/downloaded files
* `/restart` restarts the Python process; tmux/systemd should keep the session visible/manageable

---

## 🧭 Next Up (Planned)

* higher resolution artwork preference
* artwork normalization/cropping
* smarter album ranking refinements
* artist popularity/play weighting
* smarter artist/title ranking refinements
* background prefetching
* playlist sync/update support

---

## 💬 Notes

* prioritize working over perfect
* fix what feels wrong, not what “looks incomplete”
* avoid over-engineering
* build, test, iterate

---

## 🧾 License

WTFPL — do what you want

---
