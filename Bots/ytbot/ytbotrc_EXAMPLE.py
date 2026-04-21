#--------------------------------------------
# file:     ytbotrc.py
# author:   Mike Redd
# version:  1.2
# created:  2026-04-18
# updated:  2026-04-21
# desc:     Safe config template for ytbot
#--------------------------------------------

# ── Required ─────────────────────────────────
BOT_TOKEN = "PASTE_YOUR_REAL_BOT_TOKEN_HERE"
ALLOWED_USER_ID = 123456789

# ── Access Control ───────────────────────────
# Access behavior:
# - DM: owner only (default)
# - Groups: controlled by ALLOWED_CHAT_IDS
# - Public mode: set ALLOW_ALL_USERS = True

# Allow everyone (public bot mode)
ALLOW_ALL_USERS = False

# Admin users (can use admin commands)
ADMIN_USERS = [ALLOWED_USER_ID]

# Additional allowed users (optional)
# Only used if you want specific users besides the owner to have access
ALLOWED_USERS = []

# Additional allowed groups (optional)
# If set, anyone in these groups can use the bot
# Leave empty to disable group access entirely
ALLOWED_CHAT_IDS = []

# ── Behavior ─────────────────────────────────
# Max time (seconds) before download is cancelled
DOWNLOAD_TIMEOUT = 900

# Enable watch folder ingestion
WATCH_FOLDER_ENABLED = True

# Optional: forward all completed downloads to another chat
# Example: your private channel ID
ARCHIVE_CHAT_ID = None

# ── Paths (optional override) ────────────────
# Default is "G:/bots"
# Only change if you move your bot to another location
# BASE_DIR = "G:/bots"

# ── Notes ───────────────────────────────────
# - Do NOT commit your real BOT_TOKEN
# - Copy this file to your local config directory and edit it
# - Keep your real version outside version control