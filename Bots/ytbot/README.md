# 🎬 Raziel v5.4.7

> A typezerø Project
> Built for real-world use, not perfection.

![Version](https://img.shields.io/badge/version-v5.4.7-blue)
![Python](https://img.shields.io/badge/python-3.10+-blue)
![License](https://img.shields.io/badge/license-WTFPL-lightgrey)

---

## 🚀 Overview

**Raziel v5.4.7** is a full media pipeline bot with:

* **automatic group link ingestion**
* **clean chat behavior**
* **production-ready logging**
* **large file support via local Telegram Bot API**
* **intelligent dedupe + smarter downloads**
* **strict video-source validation**
* **config-driven platform support**
* **user-controlled quality selection**
* **reply-loop protection**

It accepts input from:

* Telegram (commands, messages, shared links, forwarded links)
* Filesystem (watch folder)
* CLI (direct execution)

Pipeline:

Input → Validate → Queue → Download → Process → Upload → Route → Archive

---

## ✨ Features

### 🧠 Core System

* Persistent queue-based architecture
* Single worker (safe processing)
* Job tracking (queue, history, failures)
* Access control (owner / users / groups)

---

### 🤖 Automatic Group Link Detection

* Watches **all groups the bot is in**

* Detects:

  * pasted links
  * shared previews
  * forwarded messages

* Automatically queues downloads

👉 No commands required

---

### 🧹 Clean Chat Behavior

* Queue messages are **temporary**
* “Added to queue” is auto-deleted when processing starts
* Keeps group chats clean and readable

---

### 🔧 Production Log Mode

* `DEBUG_MODE` toggle
* Development → full logs
* Production → minimal logs

```python
DEBUG_MODE = False
```

---

## 🧠 Intelligence Layer

### 🔁 Dedupe System (v5.4)

* Prevents duplicate downloads
* Uses normalized URLs + persistent cache + TTL

---

### 🚫 Validation Layer (v5.4.1)

* Only supported video sources are processed
* Blocks:

  * non-video URLs
  * unsupported platforms
  * random links

---

### ⚙️ Config-Driven Platforms (v5.4.2)

Control platforms via config (no code edits):

```python
ENABLED_VIDEO_PLATFORMS = (
    "youtube",
    "instagram",
)
```

Available presets:

* youtube
* instagram
* reddit
* tiktok
* twitter

Custom domains:

```python
EXTRA_VIDEO_DOMAINS = ()
```

---

### 🎯 Quality Control (v5.4.3)

Users can choose download quality:

| Command | Behavior       |
| ------- | -------------- |
| `/dl`   | 720p (default) |
| `/hd`   | 1080p          |
| `/full` | Best available |

Config:

```python
DEFAULT_VIDEO_HEIGHT = 720
HD_VIDEO_HEIGHT = 1080
```

---

### 🎛️ Interactive UI

`/ui <url>`

Now supports:

* 🎬 720p
* 🎬 HD
* 🎬 Full
* 🎵 Audio

---

### ✂️ Clip Support

```text
/clip <url> <start> <end>
```

* ffmpeg-powered
* Supports MM:SS / HH:MM:SS
* Validates ranges
* Adds clip info to caption

---

### 📥 Media Handling

* YouTube, Instagram (default enabled)
* yt-dlp backend
* MP4-friendly formats
* Audio extraction

---

### 📦 Smart Upload System

* Uploads up to **~2GB**
* No forced compression
* No multi-part spam
* Extended Telegram upload timeout
* Clean single upload output

---

### 🧵 Reply Behavior

* Replies stay attached to original message
* `/dl`, `/hd`, `/full`, `/audio`, `/clip`, `/ui` all threaded
* Auto-detected links reply to source message

---

### 🛡️ Reply Requeue Protection (v5.4.7)

* Prevents reply loops from reposting uploaded videos
* Replies without a fresh/direct URL are ignored
* Raw Telegram reply payloads are sanitized before fallback scanning
* Stops accidental duplicate reposts when users casually reply to uploads

Ignored:

* reply + text
* reply + emoji
* reply + sticker

Allowed:

* reply + new video URL

---

### 🔇 Clean Group Mode

* Minimal noise output
* `/queue` for visibility

---

### 📁 File Routing

```text
G:\bots\done\video\
G:\bots\done\audio\
G:\bots\done\failed\
```

---

### 📡 Automation

* Watch folder: `G:\bots\watch`

CLI:

```text
python ytbot.py --url "<link>"
python ytbot.py --audio "<link>"
```

---

### 📊 Observability

* `/stats`
* `/status`
* `/failures`
* `/retrylast`

---

## 🧠 Version History

### v5.4.7 (Current)

* Finalized reply-loop protection system
* Hardened reply payload filtering
* Stable repost prevention behavior
* Documentation and release cleanup

---

### v5.4.6

* Strict reply guard to prevent repost loops
* Ignore replies without a fresh/direct URL
* Sanitize `reply_to_message` payloads before fallback scanning

---

### v5.4.5

* Initial reply requeue prevention attempt

---

### v5.4.4

* Unified help branding and bot presentation
* Raziel identity integration

---

### v5.4.3

* Quality control commands (`/dl`, `/hd`, `/full`)
* Per-job quality handling
* UI quality selection

---

### v5.4.2

* Config-driven platform support

---

### v5.4.1

* Validation layer (supported video sources only)

---

### v5.4

* Dedupe system (persistent + TTL)
* Smarter format selection

---

### v5.3.4

* Production log mode (`DEBUG_MODE`)

---

### v5.3.3

* Queue message cleanup

---

### v5.3.2

* Automatic group link detection

---

## 📌 Philosophy

Make it work → Make it better → Make it clean → Make it smart → Make it disciplined → **Give control**

---

## 🧑‍💻 Author

Mike Redd
typezerø Projects

---

## 📜 License

WTFPL
