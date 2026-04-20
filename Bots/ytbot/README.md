# 🎬 YTBot

> A clean, self-hosted Telegram bot for downloading media with `yt-dlp`,
> sending it back to chat, and fetching weather --- all from one place.

------------------------------------------------------------------------

## ✨ Features

-   📥 Download video from **1000+ supported sites**
-   🎵 Extract **audio (MP3)**
-   📤 Send media back to Telegram
-   📦 Auto-compress for Telegram limits
-   🌤️ Weather + 📅 5-day forecast
-   👥 Usage tracking and stats
-   🔒 Owner-only or public modes

------------------------------------------------------------------------

## ▶️ Run

``` powershell
cd G:\bots
python .\ytbot.py
```

------------------------------------------------------------------------

## 🔐 Config

Create:

G:`\bots`{=tex}`\config`{=tex}`\ytbotrc`{=tex}.py

``` python
BOT_TOKEN = "YOUR_TOKEN"
ALLOWED_USER_ID = 123456789
```

------------------------------------------------------------------------

## 🤖 Commands

-   /dl `<url>`{=html}
-   /audio `<url>`{=html}
-   /weather `<place>`{=html}
-   /forecast `<place>`{=html}
-   /whoami
-   /lastusers (owner)
-   /stats (owner)

------------------------------------------------------------------------

## 📊 Logs

G:`\bots`{=tex}`\logs`{=tex}`\ytbot`{=tex}.log

------------------------------------------------------------------------

## 👤 Author

Mike Redd
