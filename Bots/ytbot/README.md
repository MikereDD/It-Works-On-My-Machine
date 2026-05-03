# 🎬 YTBot v5.4.1

> A typezerø Project
> Built for real-world use, not perfection.

![Version](https://img.shields.io/badge/version-v5.4.1-blue)
![Python](https://img.shields.io/badge/python-3.10+-blue)
![License](https://img.shields.io/badge/license-WTFPL-lightgrey)

---

## 🚀 Overview

**YTBot v5.4.1** is a full media pipeline bot with:

* **automatic group link ingestion**
* **clean chat behavior**
* **production-ready logging**
* **large file support via local Telegram Bot API**
* **intelligent dedupe + smarter downloads**
* **strict video-source validation**

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

* Works across:

  * pasted links
  * forwarded links
  * tracking variants

* Uses:

  * normalized URLs
  * persistent cache (`state/dedup.json`)
  * TTL expiration

---

### 🎯 Smarter Downloads (v5.4)

* Prefer MP4/M4A formats
* Limit resolution automatically
* Reduce oversized downloads

---

### 🚫 Supported Video Sources Only (v5.4.1)

* Only valid video domains are processed
* Prevents:

  * article links
  * unsupported sites
  * random URLs hitting yt-dlp

Config:

```python
SUPPORTED_VIDEO_DOMAINS = (
    "youtube.com",
    "youtu.be",
    "m.youtube.com",
    "instagram.com",
)
```

👉 Validation happens **before queueing**

---

### 🎛️ Interactive UI

`/ui <url>`

* Video
* Audio
* Cancel
* Preserves message context

---

### ✂️ Clip Support

```
/clip <url> <start> <end>
```

* ffmpeg-powered
* Supports MM:SS / HH:MM:SS
* Validates ranges
* Adds clip info to caption

---

### 📥 Media Handling

* YouTube, Instagram (primary supported sources)
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
* `/dl`, `/audio`, `/clip`, `/ui` all threaded
* Auto-detected links reply to source message

---

### 🔇 Clean Group Mode

* Minimal noise output
* `/queue` for visibility

---

### 📁 File Routing

```
G:\bots\done\video\
G:\bots\done\audio\
G:\bots\done\failed\
```

---

### 📡 Automation

* Watch folder: `G:\bots\watch`

CLI:

```
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

### v5.4.1 (Current)

* Restrict pipeline to supported video sources
* Early validation layer (fail-fast)
* Reduced yt-dlp failures and noise

---

### v5.4

* Dedupe system (persistent + TTL)
* URL normalization
* Smarter yt-dlp format selection

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

Make it work → Make it better → Make it clean → Make it smart → **Make it disciplined**

---

## 🧑‍💻 Author

Mike Redd
typezerø Projects

---

## 📜 License

WTFPL

---

