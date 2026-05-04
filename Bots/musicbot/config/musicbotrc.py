# ------------------------------------------------------------
# file:     musicbotrc.py
# author:   Mike Redd
# version:  1.4
# created:  2026-05-03
# updated:  2026-05-03
# desc:     Configuration for Sandalphon (MusicBot)
# ------------------------------------------------------------

# ── Required ─────────────────────────────────────────────────
BOT_TOKEN = "PUT_YOUR_BOT_TOKEN_HERE"

# ── Access Control ───────────────────────────────────────────

# Leave empty to allow all users
ALLOWED_USER_IDS = [
    # 123456789
]

# Admin users (bypass restrictions / future admin commands)
ADMIN_USERS = [
    # 123456789
]

# ── Paths ────────────────────────────────────────────────────
BASE_DIR = "/mnt/nvme1/work/bots/Sandalphon"
DOWNLOAD_DIR = "/mnt/nvme1/work/bots/downloads/music"
LOG_FILE = "/mnt/nvme1/work/bots/logs/musicbot.log"

# ── Audio Settings ───────────────────────────────────────────
MAX_FILE_MB = 500
AUDIO_FORMAT = "mp3"
AUDIO_QUALITY = "0"

# ── Playlist Settings ────────────────────────────────────────
PLAYLIST_LIMIT = 10

# ── Local Telegram Bot API (recommended) ─────────────────────
LOCAL_BOT_API_URL = "http://127.0.0.1:8081/bot"
LOCAL_BOT_API_FILE_URL = "http://127.0.0.1:8081/file/bot"

# ── yt-dlp Cookies (optional) ────────────────────────────────
COOKIES_FILE = ""

# ── Spotify Metadata (optional) ──────────────────────────────
SPOTIFY_METADATA_ENABLED = False
SPOTIFY_CLIENT_ID = ""
SPOTIFY_CLIENT_SECRET = ""

# ── Cache Settings (v1.4) ────────────────────────────────────
CACHE_ENABLED = True
CACHE_DIR = "/mnt/nvme1/work/bots/cache/musicbot"