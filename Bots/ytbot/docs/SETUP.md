# ⚙️ YTBot Setup Guide (v6.8)

> Full setup for Arakiel / Arch Linux environment
> Covers dependencies, Telegram Bot API, and ytbot configuration

---

## 🧩 Overview

YTBot requires:

* Python environment
* ffmpeg / ffprobe
* Telegram Bot API (local server)
* ytbot configuration

---

## 📦 1. Install System Dependencies

```bash
sudo pacman -S ffmpeg ffprobe git base-devel
```

Optional (recommended):

```bash
sudo pacman -S nodejs
```

---

## 🐍 2. Python Environment

```bash
cd /mnt/nvme1/work/bots
python -m venv venv
source venv/bin/activate
```

Install packages:

```bash
pip install -U pip
pip install "python-telegram-bot>=22.0" "yt-dlp>=2026.03.17"
```

---

## ⚙️ 3. Configure ytbot

Create config:

```bash
mkdir -p /mnt/nvme1/work/bots/config
nano /mnt/nvme1/work/bots/config/ytbotrc.py
```

Example:

```python
BOT_TOKEN = "YOUR_TELEGRAM_BOT_TOKEN"

ADMIN_USERS = [123456789]
ALLOWED_USERS = [123456789]

DOWNLOAD_TIMEOUT = 3600
TELEGRAM_UPLOAD_TIMEOUT = 3600

WATCH_FOLDER_ENABLED = True
ARCHIVE_CHAT_ID = None
```

---

## 🤖 4. Telegram Bot API (Local Server)

YTBot v5.3+ requires local Bot API for large uploads.

---

### 📥 Build Telegram Bot API

```bash
cd ~/src
git clone --recursive https://github.com/tdlib/telegram-bot-api.git
cd telegram-bot-api
mkdir build && cd build
cmake -DCMAKE_BUILD_TYPE=Release ..
cmake --build . --target telegram-bot-api -j$(nproc)
```

---

### 🔑 Get API Credentials

From Telegram:

* `api_id`
* `api_hash`

---

## 🥇 5. Run via systemd (Recommended)

Create service:

```bash
sudo nano /etc/systemd/system/telegram-bot-api.service
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

```bash
sudo systemctl daemon-reload
sudo systemctl enable telegram-bot-api
sudo systemctl start telegram-bot-api
```

---

### 🔍 Verify

```bash
systemctl status telegram-bot-api
```

Logs:

```bash
journalctl -u telegram-bot-api -f
```

---

## 🥈 6. Optional: Start Script

```bash
nano ~/start-bot-api.sh
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

```bash
chmod +x ~/start-bot-api.sh
```

---

## 🥉 7. Optional: Shell Aliases

Add to:

```bash
~/.bash.d/aliases
```

```bash
alias botapi="systemctl status telegram-bot-api"
alias botapi-start="sudo systemctl start telegram-bot-api"
alias botapi-stop="sudo systemctl stop telegram-bot-api"
alias botapi-restart="sudo systemctl restart telegram-bot-api"
alias botapi-log="journalctl -u telegram-bot-api -f"
```

Reload shell:

```bash
source ~/.bashrc
```

---

## ▶️ 8. Run YTBot

```bash
cd /mnt/nvme1/work/bots
source venv/bin/activate
python ytbot.py
```

---

## 🧪 9. Test

In Telegram:

```text
/dl https://youtu.be/kRPvE8CPub0
```

Expected:

* Download starts
* No timeout errors
* Single upload (no duplicates)

---

## ⚠️ Troubleshooting

### ❌ Upload times out

Check:

```bash
journalctl -u telegram-bot-api -f
```

Increase:

```python
TELEGRAM_UPLOAD_TIMEOUT = 3600
```

---

### ❌ yt-dlp fails

```bash
pip install -U yt-dlp
```

---

### ❌ ffmpeg missing
:1

```bash
sudo pacman -S ffmpeg
```

---

### ❌ Bot not responding

Check:

```bash
systemctl status telegram-bot-api
```

---

## ✅ Final Checklist

* [ ] Bot API running
* [ ] ytbot config created
* [ ] ffmpeg installed
* [ ] venv active
* [ ] bot starts without errors

---

## 🧠 Notes

* Local Bot API removes 50MB limit
* Uploads up to ~2GB supported
* systemd ensures reliability

---

## 🚀 Result

You now have:

* persistent bot backend
* large media pipeline
* automated service startup
* clean dev workflow

---

**YTBot is now production-ready.**

