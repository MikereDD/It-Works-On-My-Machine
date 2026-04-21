# 🎬 YTBot v4.3

### A Queue-Based Telegram Media Pipeline

---

## 🚀 Overview

**YTBot v4.3** is a full-featured Telegram media bot that transforms simple links into a structured media pipeline.

It accepts input from:

* 📩 Telegram (commands, messages, interactive UI)
* 📂 Filesystem (watch folder)
* 💻 CLI (direct execution)

…and processes everything through a **queue-based system**:

```text
Input → Queue → Download → Process → Route → Archive
```

This is no longer just a downloader—it’s a **media ingestion system**.

---

## ✨ Features

### 🧠 Core System

* Persistent **queue-based architecture**
* Job tracking (queue, history, failures)
* Single worker (safe, no overlapping downloads)
* Access control (owner / allowed users / public mode)

---

### 🎛️ Interactive UI

Use `/ui <url>` to get a preview with buttons:

* 🎬 Video
* 🎵 Audio
* ❌ Cancel

No need to remember commands—just click.

---

### 📥 Media Handling

* Supports YouTube, Reddit, Instagram (best-effort), and more via **yt-dlp**
* Smart format selection (MP4-friendly)
* Automatic fallback handling
* Audio extraction via `ffmpeg`

---

### 📦 Smart Upload System

* Detects large files
* Auto-compresses using `ffmpeg`
* Falls back to document upload if needed
* Prevents Telegram upload failures

---

### 📁 File Routing

Processed media is automatically organized:

```text
G:\bots\done\video\
G:\bots\done\audio\
G:\bots\done\failed\
```

---

### 📡 Automation

* 📂 Watch folder ingestion (`G:\bots\watch`)
* 💻 CLI mode:

  ```bash
  python ytbot.py --url "<link>"
  python ytbot.py --audio "<link>"
  ```

---

### 📊 Observability

* `/stats` → usage summary
* `/lastusers` → recent activity
* `/failures` → recent errors
* `/retrylast` → retry failed job

Includes:

* unique users
* domain tracking (top sites)
* timestamps

---

### 🌦️ Extras

* `/weather <location>`
* `/forecast <location>`

Powered by Open-Meteo (no API key required).

---

## 🧩 Architecture

```text
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
```

---

## ⚙️ Setup

### 1. Install Python packages

```bash
pip install yt-dlp python-telegram-bot
```

---

### 2. Install dependencies

* **ffmpeg** (required for audio + compression)
* **ffprobe** (comes with ffmpeg)

Verify:

```bash
ffmpeg -version
ffprobe -version
```

---

### 3. Configure bot

Create:

```text
G:\bots\config\ytbotrc.py
```

Example:

```python
BOT_TOKEN = "YOUR_TELEGRAM_BOT_TOKEN"
ALLOWED_USER_ID = 123456789

ADMIN_USERS = [123456789]
ALLOWED_USERS = [123456789]
ALLOW_ALL_USERS = False

ARCHIVE_CHAT_ID = None
WATCH_FOLDER_ENABLED = True
DOWNLOAD_TIMEOUT = 900
```

---

### 4. Run the bot

```bash
python ytbot.py
```

---

## 🧪 Usage

### Basic

```text
/dl <url>       → download video
/audio <url>    → extract audio
/ui <url>       → interactive preview
```

### Queue

```text
/queue          → show queue
/clearqueue     → clear queue (admin)
/retrylast      → retry last failed job
```

### System

```text
/stats          → usage stats
/status         → system status
/groups         → tracked groups
```

---

## ⚠️ Notes

* Instagram may fail without authentication (platform limitation)
* Large files are automatically compressed, but quality may be reduced
* Ensure `ffmpeg` is installed for full functionality

---

## 🧠 Version History

### v4.3 (Current)

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

This project follows a simple idea:

> **Make it work reliably first. Then make it powerful. Then make it pleasant.**

---

## 🧑‍💻 Author

**Mike Redd**
typezerø Projects

---

## 📜 License

This project is licensed under the **WTFPL** —  
Do What The F*ck You Want To Public License.

Basically:
> Do whatever you want with it.

Requires:
- Python 3.10+
- ffmpeg + ffprobe installed and in PATH
