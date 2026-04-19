# YTBot

Telegram bot for downloading media with `yt-dlp`, sending it back to Telegram, and showing weather with Open-Meteo.

This repo is based on the current bot script and config shown in the uploaded files. It uses a private config file for secrets, supports owner-only or open usage, and includes current weather plus a 5-day forecast. fileciteturn6file0 fileciteturn6file1

## Features

- Download video from supported `yt-dlp` sites
- Download audio as MP3
- Upload back to Telegram
- Compression fallback to fit Telegram bot upload limits
- YouTube cookie-file support
- Current weather lookup
- 5-day forecast lookup
- Group tracking and owner-only management commands

## Files

- `ytbot.py` — main bot script
- `config/ytbotrc.py` — private config file
- `cookies/youtube_cookies.txt` — optional YouTube cookies file

## Commands

- `/start` — welcome and command list
- `/help` — usage help
- `/dl <url>` — download video explicitly
- `/audio <url>` — download audio only as MP3
- `/weather <place>` — current weather
- `/forecast <place>` — 5-day forecast
- `/status` — bot/system status (owner)
- `/groups` — list remembered groups (owner)
- `/cleanup` — delete leftover files (owner)
- `/leave` — leave current group (owner)
- `/leavechat <chat_id>` — leave a remembered group by ID (owner)
- `/shutdown` — stop the bot (owner)

## Requirements

Install Python packages:

```powershell
python -m pip install -r requirements.txt
```

## requirements.txt

The included `requirements.txt` installs:

- `python-telegram-bot`
- `yt-dlp`

## External tools

You also need these installed and available in `PATH`:

- `ffmpeg`
- `ffprobe`

These are required for:
- audio extraction
- media validation
- compression to fit Telegram upload limits

## Config

Create this file:

```text
G:\bots\config\ytbotrc.py
```

Example:

```python
#--------------------------------------------
# file:     ytbotrc.py
# author:   Mike Redd
# version:  1.0
# created:  2026-04-18
# updated:  2026-04-18
# desc:     Private config for ytbot
#--------------------------------------------

BOT_TOKEN = "PASTE_YOUR_REAL_BOT_TOKEN_HERE"
ALLOWED_USER_ID = 123456789

# Optional settings:
# ALLOW_ALL_USERS  = False
# DOWNLOAD_TIMEOUT = 300
```

That matches the uploaded config layout. fileciteturn6file0

## Optional YouTube cookies

If YouTube blocks anonymous access, export a Netscape-format cookies file to:

```text
G:\bots\cookies\youtube_cookies.txt
```

The script checks for that file automatically for YouTube URLs. fileciteturn6file1

## Run

```powershell
cd G:\bots
python .\ytbot.py
```

## Notes

- Instagram handling may still depend on site behavior and anonymous-access limits.
- Weather and forecast use Open-Meteo via standard library HTTP calls, so no extra weather package is required.
- Open-Meteo geocoding and forecast requests are built directly into the script. fileciteturn6file1

## Suggested layout

```text
G:\bots
├── ytbot.py
├── config
│   └── ytbotrc.py
├── cookies
│   └── youtube_cookies.txt
├── downloads
└── logs
```
