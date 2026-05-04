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
* processes requests through a queue (stable under load)
* caches audio for instant reuse
* cleans up chat noise after processing
* runs on local Bot API for performance
* supports large file delivery (Local API)

---

## 📦 Version Notes

### v1.0

* working pipeline (search → download → convert → send)
* yt-dlp integration
* basic Telegram commands

---

### v1.1

* Sandalphon branding
* improved UX messaging
* cleaned filenames
* fixed duplicate artist/title issues
* ID3 metadata rewrite (Telegram display fix)

---

### v1.2

* playlist support (`/playlist`)
* metadata system (Spotify optional, yt-dlp fallback)
* improved tagging (artist/title/album/year)
* admin user system
* local Telegram Bot API support

---

### v1.3

* request queue system (FIFO)
* prevents concurrent downloads
* stabilizes multi-request handling
* `/queue` command

---

### v1.4

* audio caching system
* instant reuse of previously downloaded tracks
* cache index (`index.json`)
* `/cache` command (stats)
* `/clearcache` command

---

### v1.4.1

* fixed cached track titles (no more hash filenames)
* removed "Added to queue" messages after completion
* improved chat cleanliness and UX
* minor stability improvements

---

### v1.4.2

* enforce `Artist - Song` format for all outputs
* uses user query as fallback when metadata is incomplete
* ensures consistent naming across commands
* improves cache title accuracy

---

### v1.5

* real metadata extraction using `yt-dlp --dump-json`
* uses artist/title from source instead of filename guessing
* removes reliance on filename parsing
* improves accuracy across all sources
* fallback still uses query when metadata is unavailable

---

### v1.5.1

* simplified command interface (single `/music` command)
* removed `/audio` and `/song` aliases
* aligned file size limits with Local Bot API
* supports large file uploads (config-driven limit)
* improved real-world usability for long tracks and mixes

---

## 🧠 Core Flow

```id="flow1"
Input → Queue → Resolve → Metadata → Download → Cache → Clean → Tag → Deliver
```

---

## 🧰 Commands

```id="cmds1"
/music <url or search>
/playlist <playlist url>
/queue
/cache
/clearcache
/id
/help
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

* Spotify links → metadata only (no download)
* Amazon Music → fallback search
* YouTube/SoundCloud → primary sources
* Local Bot API removes standard Telegram size limits
* file size limit is controlled via config (`MAX_FILE_MB`)
* cache is query-based (exact match required)
* metadata is source-driven when available, fallback to query when not

---

## ⚠️ Gotchas

* ffmpeg must be installed
* yt-dlp must be in PATH
* permissions required for NVMe paths
* some sources may require cookies
* metadata calls add a small overhead (extra yt-dlp call)

---

## 🧭 Next Up (Planned)

* smarter cache matching (same song, different queries)
* cache metadata reuse (avoid extra metadata calls)
* local media library mode
* queue prioritization (admin priority)
* background prefetching
* better album art handling

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
