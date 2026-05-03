# 🎬 YTBot v5.3.3

> A typezerø Project
> Built for real-world use, not perfection.

![Version](https://img.shields.io/badge/version-v5.3.3-blue)
![Python](https://img.shields.io/badge/python-3.10+-blue)
![License](https://img.shields.io/badge/license-WTFPL-lightgrey)

---

## 🚀 Overview

**YTBot v5.3.3** is a full media pipeline bot with **automatic group link ingestion**, **clean chat behavior**, and **large file support via local Telegram Bot API**.

It accepts input from:

* Telegram (commands, messages, shared links, forwarded links)
* Filesystem (watch folder)
* CLI (direct execution)

Pipeline:

Input → Queue → Download → Process → Upload → Route → Archive

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

### 🧹 Clean Chat Behavior (v5.3.3)

* Queue messages are now **temporary**
* “Added to queue” is automatically removed when processing starts
* Reduces noise in active group chats

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

* YouTube, Reddit, Instagram (best-effort)
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

## 🧩 Architecture

Telegram / CLI / Watch Folder
↓
Queue
↓
Worker
↓
yt-dlp
↓
ffmpeg (clip/audio)
↓
Upload (Telegram API)
↓
Archive + History

---

## ⚙️ Setup

### Install Python deps

```
pip install -r requirements.txt
```

OR

```
pip install "python-telegram-bot>=22.0" "yt-dlp>=2026.03.17"
```

---

### Install system deps

```
sudo pacman -S ffmpeg ffprobe
```

Verify:

```
ffmpeg -version
ffprobe -version
```

---

### Configure bot

```
G:\bots\config\ytbotrc.py
```

Example:

```python
BOT_TOKEN = "YOUR_TOKEN"

ADMIN_USERS = [123456789]
ALLOWED_USERS = [123456789]

DOWNLOAD_TIMEOUT = 3600
TELEGRAM_UPLOAD_TIMEOUT = 3600
```

---

## ⚠️ REQUIRED: Local Telegram Bot API

YTBot v5.3.3 requires the **local Bot API server** for large uploads.

---

### 🥇 systemd service (recommended)

```
/etc/systemd/system/telegram-bot-api.service
```

```ini
[Unit]
Description=Telegram Bot API (Local)
After=network.target

[Service]
User=typezero
WorkingDirectory=/mnt/nvme1/work/telegram-bot-api
ExecStart=/home/typezero/src/telegram-bot-api/build/telegram-bot-api \
  --api-id YOUR_API_ID \
  --api-hash YOUR_API_HASH \
  --local \
  --http-port 8081 \
  --dir /mnt/nvme1/work/telegram-bot-api

Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
```

Enable + start:

```
sudo systemctl daemon-reload
sudo systemctl enable telegram-bot-api
sudo systemctl start telegram-bot-api
```

---

### 🥈 Optional: Start script

```
~/start-bot-api.sh
```

---

### 🥉 Optional: Aliases

```
alias botapi="systemctl status telegram-bot-api"
alias botapi-log="journalctl -u telegram-bot-api -f"
```

---

## ▶️ Run bot

```
python ytbot.py
```

---

## 🧪 Usage

```
/dl <url>
/audio <url>
/clip <url> <start> <end>
/ui <url>

/queue
/clearqueue
/retrylast
```

---

## ⚠️ Notes

* Instagram may require cookies
* ffmpeg required for media processing
* Local Bot API required for large uploads
* Commands work even if privacy is enabled
* Auto group watching requires bot permissions

---

## 🧠 Version History

### v5.3.3 (Current)

* Queue message cleanup (auto-delete “Added to queue”)
* Cleaner group chat behavior

---

### v5.3.2

* Automatic group link detection
* Shared + forwarded link support
* Full message handler coverage

---

### v5.3.1

* Upload timeout fixes
* Stability improvements

---

### v5.3

* Local Bot API (~2GB uploads)

---

### v5.2

* Reply threading
* UI improvements

---

## 📌 Philosophy

Make it work → Make it better → Make it clean

---

## 🧑‍💻 Author

Mike Redd
typezerø Projects

---

## 📜 License

WTFPL

---

## ✅ Requirements

* Python 3.10+
* ffmpeg
* ffprobe

