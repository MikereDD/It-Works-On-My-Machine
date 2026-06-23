# 📰 Gabriel (CardBot)

> A typezerø Project
> Built for real-world use, not perfection.

![Version](https://img.shields.io/badge/version-v0.8.2-blue) ![Python](https://img.shields.io/badge/python-3.10+-blue) ![License](https://img.shields.io/badge/license-WTFPL-lightgrey)

---

# 🚀 Overview

Gabriel is a Telegram-native link-preview bot focused on:

- clean Open Graph card rendering
- low-noise group interaction
- metadata-aware previews
- passive link watching
- operational reliability

Gabriel accepts input from:

- Telegram commands
- pasted/shared links
- forwarded links
- group auto-watch

Pipeline:

```
Link → Fetch → Extract OG → Render Card → Reply
```

---

# ✨ Features

## 🖼️ Card Rendering

- Open Graph / Twitter Card extraction
- Pillow-rendered preview card
- dark theme, cyan→teal accent
- favicon source-chip next to the domain
- hero image cover-crop with gradient blend into the body (1.92:1)
- title and blurb wrapping with ellipsis
- text-only fallback for tiny or missing images
- post-aware layout for X/Twitter and Telegram (t.me): post text as the focus, author/channel byline, avatar chip
- inline color emoji (flags, etc.) via Noto Color Emoji
- X quote tweets: nested quoted/replied-to tweet, real avatars, and verified badges (via X syndication, with OG fallback)

---

## 🤖 Telegram-Native UX

- automatic group link detection
- owner-only private chats
- per-chat auto-watch opt-out
- native-media skip (won't card a message that already has media)
- 30s per-chat dedupe
- silent failure in groups, notify in DMs

---

## 🧠 Metadata Layer

- og:title / og:description / og:image
- `<title>` and meta-description fallbacks
- whitespace normalization
- tracking-param stripping (utm_*, fbclid, gclid, …)
- relative image URL resolution
- HTML content-type validation

---

## ⚙️ Config & Ops

- `cardbotrc.py` loader (shared `config/` dir)
- `CARDBOT_TOKEN` env fallback
- file + stream logging
- off-thread card rendering
- `HTTPXRequest` timeouts

---

# 🎛️ Commands

```
/start
/help
/status   (owner only)
/clean    (owner only)
```

---

# 📦 Setup

Install (shared venv on the Pi):

```
venv/bin/pip install -r requirements.txt
sudo pacman -S ttf-dejavu noto-fonts-emoji
```

Config — copy the example and fill it in:

```
cp cardbotrc.example.py ../config/cardbotrc.py
```

Set `BOT_TOKEN` (from @BotFather) and `ALLOWED_USER_ID` (your numeric Telegram
ID — DM @userinfobot). For group watching, set the bot's BotFather privacy to
**Disable**.

Run:

```
venv/bin/python cardbot.py
```

---

# 📚 Notes & Version History

Full release notes:

```
CHANGELOG.md
```

[View the changelog »](https://github.com/MikereDD/It-Works-On-My-Machine/blob/main/Bots/cardbot/CHANGELOG.md)

---

# 📌 Philosophy

```
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
