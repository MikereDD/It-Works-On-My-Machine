# 🎬 YTBot v4.8

> A typezerø Project  
> Built for real-world use, not perfection.

![Version](https://img.shields.io/badge/version-v4.8-blue)
![Python](https://img.shields.io/badge/python-3.10+-blue)
![License](https://img.shields.io/badge/license-WTFPL-lightgrey)

---

## 🚀 Overview

**YTBot v4.8** is a full-featured Telegram media bot that transforms simple links into a structured media pipeline.

It accepts input from:

* 📩 Telegram (commands, messages, interactive UI)
* 📂 Filesystem (watch folder)
* 💻 CLI (direct execution)

…and processes everything through a **queue-based system**:

Input → Queue → Download → Process → Route → Archive

This is no longer just a downloader—it’s a **media ingestion system**.

---

## ✨ Features

### 🧠 Core System

* Persistent queue-based architecture  
* Job tracking (queue, history, failures)  
* Single worker (safe, no overlapping downloads)  
* Access control (owner / allowed users / group-based control / public mode)  

---

### 🎛️ Interactive UI

Use `/ui <url>` to get a preview with buttons:

- 🎬 Video  
- 🎵 Audio  
- ❌ Cancel  

No need to remember commands—just click.

---

### 📥 Media Handling

* Supports YouTube, Reddit, Instagram (best-effort), and more via yt-dlp  
* Smart format selection (MP4-friendly)  
* Automatic fallback handling  
* Audio extraction via ffmpeg  

---

### 📦 Smart Upload System

* Detects large files  
* Auto-compresses using ffmpeg  
* Falls back to document upload if needed  
* Prevents Telegram upload failures  
* Metadata captions (title, uploader, link) for `/ui`, `/dl`, `/audio`  

---

### 📁 File Routing

G:\bots\done\video\  
G:\bots\done\audio\  
G:\bots\done\failed\  

---

### 📡 Automation

* Watch folder ingestion (`G:\bots\watch`)  
* CLI mode:

python ytbot.py --url "<link>"  
python ytbot.py --audio "<link>"  

---

### 📊 Observability

* /stats → usage summary  
* /lastusers → recent activity  
* /failures → recent errors  
* /retrylast → retry failed job  

Includes:

* unique users  
* domain tracking (top sites)  
* timestamps  

---

### 📖 Role-Aware Help System

* `/help` dynamically adapts based on user context  
* `/start` mirrors command visibility  

Behavior:

- **Admins (DM or group)** → full command list  
- **Allowed group users** → user commands only  
- **Unauthorized users** → minimal safe commands  

No more command clutter or exposing admin tools to regular users.

---

### 🌦️ Extras

* /weather <location>  
* /forecast <location>  

Powered by Open-Meteo (no API key required).

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
  Validate + Compress (ffmpeg)  
            ↓  
   Send → Route → Archive  
            ↓  
   History / Failures / Stats  

---

## 📜 Version Notes

Detailed version history is available in:

notes/

---

## ⚙️ Setup

### 1. Install Python packages

pip install -r requirements.txt  

OR  

pip install "python-telegram-bot>=22.0" "yt-dlp>=2026.03.17"  

---

### 2. Install dependencies

* ffmpeg (required for audio + compression)  
* ffprobe (comes with ffmpeg)  

Verify:

ffmpeg -version  
ffprobe -version  

---

### 3. Configure bot

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

### 4. Run the bot

python ytbot.py  

---

## 🧪 Usage

### Basic

/dl <url>       → download video  
/audio <url>    → extract audio  
/ui <url>       → interactive preview  

### Queue

/queue          → show queue  
/clearqueue     → clear queue (admin)  
/retrylast      → retry last failed job  

### System

/stats          → usage stats  
/status         → system status  
/groups         → tracked groups  

---

## ⚠️ Notes

* Instagram may fail without authentication (platform limitation)  
* Large files are automatically compressed; quality may be reduced  
* ffmpeg is required for audio extraction and compression  
* ffprobe is required for video validation  

---

## 🛡️ Recommended .gitignore

config/ytbotrc.py  
state/  
logs/  
downloads/  
cookies/  

---

## 🧠 Version History

### v4.8 (Current)

* Role-aware `/help` and `/start` output  
* Split command visibility (user vs admin)  
* Context-aware command display (DM vs group vs unauthorized)  
* Cleaner UX with reduced command clutter  
* Improved maintainability via structured command lists  

### v4.7

* Metadata captions added to uploaded media (title, uploader, source link)  
* Captions applied to `/ui`, `/dl`, and `/audio` workflows  
* Introduced source-aware job behavior (`ui`, `dl`, `audio`, `raw_url`, `watch`)  
* Captions excluded from raw URL and automated workflows  
* Applied consistent caption handling to archive uploads  
* Improved media traceability and sharing experience  

### v4.6

* Chat-aware access control (`can_use_context`)  
* Group-based usage via `ALLOWED_CHAT_IDS`  
* DM access restricted to owner by default  
* Updated command handlers and UI callbacks to enforce context-aware permissions  
* Improved `/whoami` to reflect real access context  
* Safer, clearer configuration template (`ytbotrc.py`)  
* Group access disabled by default in template  

### v4.5

* Runtime hardening and stability improvements  
* Improved compression with duration-aware bitrate targeting  
* Safer Telegram UI handling (short callback IDs instead of full URLs)  
* Better error messaging and failure categorization  
* Watch folder enhancements (`WATCH_FOLDER_CHAT_ID`)  
* History and failure list size limits  

### v4.4

* Queue position feedback when adding jobs  
* Improved `/stats` formatting and readability  
* Enhanced `/lastusers` with timestamps and shortened URLs  
* Clearer command responses and usage messages  
* Improved DM vs group behavior handling  
* Better processing status feedback and error visibility  

### v4.3

* Interactive UI (buttons)  
* Compression + upload fallback  
* Video validation  
* Improved logging and stats  

### v4.2

* Metadata extraction  
* File routing  
* Watch folder + CLI mode  

### v4.1

* yt-dlp + Telegram integration  

### v4.0

* Queue-based core system  

---

## 📌 Philosophy

Make it work → Make it better → Make it clean  

---

## 🧑‍💻 Author

Mike Redd  
typezerø Projects  

---

## 📜 License

WTFPL — Do What The F*ck You Want To Public License  

---

## ✅ Requirements

- Python 3.10+  
- ffmpeg in PATH  
- ffprobe in PATH  