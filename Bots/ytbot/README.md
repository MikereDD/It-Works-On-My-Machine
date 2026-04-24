# 🎬 YTBot v5.2

> A typezerø Project  
> Built for real-world use, not perfection.

![Version](https://img.shields.io/badge/version-v5.2-blue)
![Python](https://img.shields.io/badge/python-3.10+-blue)
![License](https://img.shields.io/badge/license-WTFPL-lightgrey)

---

## 🚀 Overview

**YTBot v5.2** is a full-featured Telegram media bot that transforms simple links into a structured media pipeline.

It accepts input from:

- Telegram (commands, messages, interactive UI)  
- Filesystem (watch folder)  
- CLI (direct execution)  

…and processes everything through a queue system:

Input → Queue → Download → Process → Route → Archive

---

## ✨ Features

### 🧠 Core System

- Persistent queue-based architecture  
- Job tracking (queue, history, failures)  
- Single worker (safe, no overlapping downloads)  
- Access control (owner / allowed users / group-based / public mode)  

---

### 🎛️ Interactive UI

Use `/ui <url>` to preview media with buttons:

- Video  
- Audio  
- Cancel  

Now preserves the original request context after selection.

---

### ✂️ Clip Support

Command:
`/clip <url> <start> <end>`

Examples:
`/clip https://youtube.com/... 00:01:00 00:01:30`  
`/clip https://youtube.com/... 01:02:10 01:03:00`

- Uses ffmpeg  
- Supports MM:SS and HH:MM:SS  
- Validates clip range  
- Keeps metadata  
- Adds clip range to caption  

---

### 📥 Media Handling

- YouTube, Reddit, Instagram (best-effort), more via yt-dlp  
- Smart MP4-friendly formats  
- Audio extraction via ffmpeg  

---

### 📦 Smart Upload System

- Auto compression for large files  
- Telegram-safe uploads  
- Fallback to document upload  
- Metadata captions for `/ui`, `/dl`, `/audio`, `/clip`  

---

### 🧵 Reply Threading (v5.2)

- `/dl`, `/audio`, `/clip` reply to original command  
- `/ui` replies to original `/ui` request  
- Raw links reply to original message  
- Status + final upload stay attached  

---

### 🔇 Clean Group Behavior (v5.2)

- No queue spam in groups  
- Private chats still show queue position  
- `/queue` is the source of truth  

---

### 📁 File Routing

G:\bots\done\video\  
G:\bots\done\audio\  
G:\bots\done\failed\  

---

### 📡 Automation

- Watch folder: G:\bots\watch  
- CLI:

python ytbot.py --url "<link>"  
python ytbot.py --audio "<link>"  

---

### 📊 Observability

- `/stats` → usage  
- `/lastusers` → activity  
- `/failures` → errors  
- `/retrylast` → retry  

---

### 📖 Role-Aware Help

- `/help` adapts based on context  
- Admins see everything  
- Users see only allowed commands  

---

### 🌦️ Extras

- `/weather <location>`  
- `/forecast <location>`  

---

## 🧩 Architecture

Telegram / CLI / Watch Folder  
↓  
Queue  
↓  
Worker  
↓  
Download (yt-dlp)  
↓  
Process (clip / compress)  
↓  
Send → Route → Archive  
↓  
History / Failures / Stats  

---

## ⚙️ Setup

### Install packages

pip install -r requirements.txt  

OR  

pip install "python-telegram-bot>=22.0" "yt-dlp>=2026.03.17"  

---

### Install dependencies

ffmpeg  
ffprobe  

Verify:

ffmpeg -version  
ffprobe -version  

---

### Configure bot

Create:

G:\bots\config\ytbotrc.py  

Example:

BOT_TOKEN = "YOUR_TELEGRAM_BOT_TOKEN"  
ALLOWED_USER_ID = 123456789  

ADMIN_USERS = [123456789]  
ALLOWED_USERS = [123456789]  
ALLOW_ALL_USERS = False  
ALLOWED_CHAT_IDS = []  

ARCHIVE_CHAT_ID = None  
WATCH_FOLDER_ENABLED = True  
DOWNLOAD_TIMEOUT = 900  

---

### Run

python ytbot.py  

---

## 🧪 Usage

/dl <url>  
/audio <url>  
/clip <url> <start> <end>  
/ui <url>  

/queue  
/clearqueue  
/retrylast  

/stats  
/status  
/groups  

---

## ⚠️ Notes

- Instagram may require cookies  
- Large files are compressed automatically  
- ffmpeg required for:
  - audio
  - compression
  - clipping  
- ffprobe required for validation  

---

## 🛡️ .gitignore

config/ytbotrc.py  
state/  
logs/  
downloads/  
cookies/  

---

## 🧠 Version History

### v5.2 (Current)

- Full reply threading across all commands  
- `/ui` now preserves original message context  
- Silent queue behavior in groups  
- Cleaner UX and reduced noise  

### v5.0

- `/clip` support  
- Media pipeline expansion  

### v4.x

- Queue system, UI, metadata, access control improvements  

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

- Python 3.10+  
- ffmpeg  
- ffprobe  