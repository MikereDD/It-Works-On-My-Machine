# 🎬 Raziel (VideoBot)

> A typezerø Project  
> Built for real-world use, not perfection.

![Version](https://img.shields.io/badge/version-v6.9-blue)
![Python](https://img.shields.io/badge/python-3.10+-blue)
![License](https://img.shields.io/badge/license-WTFPL-lightgrey)

---

# 🚀 Overview

Raziel is a Telegram-native media pipeline bot focused on:

- automatic media ingestion
- intelligent queue handling
- clean group interaction
- metadata-aware uploads
- low-noise Telegram UX
- large-file support
- operational reliability
- smart media workflows

Raziel accepts input from:

- Telegram commands
- pasted/shared links
- forwarded links
- watch folders
- direct CLI execution

Pipeline:

```text
Input → Validate → Queue → Download → Process → Upload → Route → Archive
```

---

# ✨ Features

## 🧠 Core System

- Persistent queue architecture
- Safe single-worker processing
- Queue/job tracking
- Access control support
- Automatic retry handling
- Runtime-safe operations

---

## 🤖 Telegram-Native UX

- Automatic group link detection
- Reply-thread aware downloads
- Interactive quality UI
- Mention-based interaction
- Telegram inline utilities
- Automatic queue cleanup
- Low-noise group behavior
- Expandable source-context presentation
- Collapsible forecast presentation
- Reply-driven download commands

Reply commands:

```text
/rdl
/rhd
/rfull
/raudio
/rui
```

---

## 🎞️ Media Handling

- yt-dlp backend
- MP4-friendly workflows
- Audio extraction
- Clip support
- Metadata-aware uploads
- Smart format selection
- Platform-aware upload branding
- Source-context preservation

Supported platforms include:

- YouTube
- Instagram
- TikTok
- Reddit
- X/Twitter
- Facebook
- BitChute

---

## 🧠 Intelligence Layer

Raziel includes:

- persistent dedupe protection
- metadata-aware uploads
- expandable source-context handling
- intelligent metadata filtering
- reply-loop protection
- configurable validation policy
- Telegram-native UX systems
- inline and mention interaction
- collapsible forecast presentation
- smart queue cleanup behavior

---

## 🌦️ Weather & Utility Features

- Current weather lookup
- Multi-day forecasts
- Expandable forecast presentation
- Inline weather queries
- Mention-driven utility interaction

Examples:

```text
/weather Houston
/forecast Tokyo
@Razi3l_bot weather Houston
```

---

## 🎛️ Interactive UI

```text
/ui <url>
```

Supports:

- 🎬 720p
- 🎬 HD
- 🎬 Full
- 🎵 Audio

---

## ✂️ Clip Support

```text
/clip <url> <start> <end>
```

Features:

- ffmpeg-powered clipping
- timestamp normalization
- clip duration calculation
- metadata-aware clip captions

---

## 📦 Smart Upload System

- Large-file Telegram uploads
- Local Telegram Bot API support
- Extended upload timeout handling
- Queue cleanup automation
- Cleaner upload presentation
- Reply-aware uploads

---

## 🧵 Reply Behavior

- Replies stay attached to original messages
- Auto-detected links remain threaded
- Queue behavior preserves conversation context
- Reply-driven commands reduce repost clutter

---

## 🔇 Clean Group Mode

Raziel prioritizes:

- reduced chat spam
- temporary operational messages
- clean scrolling behavior
- readable uploads
- meaningful metadata only

---

## 📁 File Routing

```text
G:\bots\done\video\
G:\bots\done\audio\
G:\bots\done\failed\
```

---

## 📡 Automation

Watch folder support:

```text
G:\bots\watch
```

CLI examples:

```text
python ytbot.py --url "<link>"
python ytbot.py --audio "<link>"
```

---

## 📊 Observability

Commands:

```text
/stats
/status
/failures
/retrylast
/queue
```

---

# 📚 Notes & Version History

Detailed release notes and architectural evolution:

```text
notes/README.md
```

---

# 📌 Philosophy

```text
Make it work
→ Make it better
→ Make it clean
→ Make it smart
→ Make it disciplined
→ Give control
```

---

# 🧑‍💻 Author

Mike Redd  
typezerø Projects

---

# 📜 License

WTFPL

