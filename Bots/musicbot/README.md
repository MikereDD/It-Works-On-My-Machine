# 🎵 Sandalphon (MusicBot)

> A typezerø Project
> Built to work. Refined to feel right.

---

## 🚀 Overview

Sandalphon is a Telegram music bot that:

* downloads audio from supported sources (yt-dlp)
* supports search + direct links
* cleans filenames and metadata
* delivers Telegram-ready audio
* supports playlists
* processes requests through a queue (stable under load)
* caches audio for instant reuse
* runs on local Bot API for performance

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

## 🧠 Core Flow

```
Input → Queue → Resolve → Download → Cache → Clean → Tag → Deliver
```

---

## 🧰 Commands

```
/music <url or search>
/audio <url or search>
/song <url or search>
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

```
BOT_TOKEN
ALLOWED_USER_IDS
ADMIN_USERS
BASE_DIR
DOWNLOAD_DIR
LOG_FILE
CACHE_ENABLED
CACHE_DIR
```

---

## 🔐 Access Control

```
ADMIN_USERS → always allowed
ALLOWED_USER_IDS → optional whitelist
empty ALLOWED_USER_IDS → public bot
```

---

## 🧪 Known Behavior

* Spotify links → metadata only (no download)
* Amazon Music → fallback search
* YouTube/SoundCloud → primary sources
* Telegram file limit enforced (~49MB)
* Large files are skipped (local API removes most limitations)
* cache is query-based (exact match required)

---

## ⚠️ Gotchas

* ffmpeg must be installed
* yt-dlp must be in PATH
* permissions required for NVMe paths
* some sources may require cookies
* yt-dlp titles can be messy (handled by cleanup logic)

---

## 🧭 Next Up (Planned)

* smarter cache matching (same song, different queries)
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
