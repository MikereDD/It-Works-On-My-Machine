#--------------------------------------------
# file:     ytbotrc.py
# author:   Mike Redd
# version:  1.3
# created:  2026-04-18
# updated:  2026-05-03
# desc:     Safe config template for ytbot
#--------------------------------------------

# ── Required ─────────────────────────────────
BOT_TOKEN = "PASTE_YOUR_REAL_BOT_TOKEN_HERE"
ALLOWED_USER_ID = 123456789

# ── Access Control ───────────────────────────
# DM/private chat remains owner-only.
# Group auto-watch is handled by bot permissions + supported platforms.
ALLOW_ALL_USERS = False

# Admin users can use admin commands.
ADMIN_USERS = [
# 123456789,
]

# Optional extra allowed users.
ALLOWED_USERS = [
# 123456789,
]

# Optional legacy/reference group IDs.
# v5.4+ group auto-watch no longer requires this whitelist,
# but keeping known IDs here can still be useful for reference.

ALLOWED_CHAT_IDS = [
# -1001234567890,
]

# ── Runtime Behavior ─────────────────────────
DOWNLOAD_TIMEOUT = 3600
TELEGRAM_UPLOAD_TIMEOUT = 3600
DEBUG_MODE = False

WATCH_FOLDER_ENABLED = True
WATCH_FOLDER_CHAT_ID = None

ARCHIVE_CHAT_ID = None

# ── Dedupe / Intelligence Layer ──────────────
DEDUP_ENABLED = True
DEDUP_TTL_HOURS = 24

# ── Download Quality / Formats ───────────────
MAX_VIDEO_HEIGHT = 1080
PREFER_MP4 = True

# ── Supported Video Platforms ────────────────
# Available preset names:
# youtube, instagram, reddit, tiktok, twitter
ENABLED_VIDEO_PLATFORMS = (
"youtube",
"instagram",
)

# Add one-off domains without editing ytbot.py.
EXTRA_VIDEO_DOMAINS = (
# "example.com",
)

# ── Paths ────────────────────────────────────
# Default is resolved relative to the bot parent directory.
# Override if you want a fixed bot data root.
BASE_DIR = "$HOME/bots"

# ── Notes ───────────────────────────────────
# - Do NOT commit your real BOT_TOKEN.
# - Keep your real config outside version control.
# - This file is safe as a template/example only.
# - For large uploads, run the local Telegram Bot API service.

