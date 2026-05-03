# 🎬 YTBot v5.3.1

> A typezerø Project
> Built for real-world use, not perfection.

![Version](https://img.shields.io/badge/version-v5.3.1-blue)
![Python](https://img.shields.io/badge/python-3.10+-blue)
![License](https://img.shields.io/badge/license-WTFPL-lightgrey)

---

## 🚀 Overview

**YTBot v5.3.1** is a full media pipeline bot with **large file support via local Telegram Bot API** and a **systemd-managed backend service**.

It accepts input from:

* Telegram (commands, messages, interactive UI)
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

### 📦 Smart Upload System (v5.3.1)

* Uploads up to **~2GB**
* No forced compression
* No multi-part spam
* Extended Telegram upload timeout
* Clean single upload output

---

### 🧵 Reply Behavior

* Replies stay attached to original message
* `/dl`, `/audio`, `/clip`, `/ui` all threaded

---

### 🔇 Clean Group Mode

* No queue spam
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
* CLI:

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

YTBot v5.3.1 requires the **local Bot API server**.

---

### 🥇 systemd service (recommended)

Create:

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

### 🥈 Manual start script

```
~/start-bot-api.sh
```

```bash
#!/usr/bin/env bash

~/src/telegram-bot-api/build/telegram-bot-api \
  --api-id YOUR_API_ID \
  --api-hash YOUR_API_HASH \
  --local \
  --http-port 8081 \
  --dir /mnt/nvme1/work/telegram-bot-api
```

```
chmod +x ~/start-bot-api.sh
```

---

### 🥉 Shell aliases

```
~/.bash.d/aliases
```

```bash
alias botapi="systemctl status telegram-bot-api"
alias botapi-start="sudo systemctl start telegram-bot-api"
alias botapi-stop="sudo systemctl stop telegram-bot-api"
alias botapi-restart="sudo systemctl restart telegram-bot-api"
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
* Upload timeout extended to prevent failures

---

## 🧠 Version History

### v5.3.1 (Current)

* Fixed Telegram upload timeout
* Removed false failure states
* Eliminated duplicate uploads
* Stabilized large file pipeline

---

### v5.3

* Local Bot API support (~2GB uploads)
* Removed 49MB limitation

---

### v5.2

* Reply threading
* UI improvements
* Group behavior cleanup

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

