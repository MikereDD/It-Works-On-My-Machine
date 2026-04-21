#--------------------------------------------
# file:     ytbotrc.py
# author:   Mike Redd
# version:  1.1
# created:  2026-04-18
# updated:  2026-04-20
# desc:     Safe config template for ytbot
#--------------------------------------------

# ── Required ─────────────────────────────────
BOT_TOKEN = "PASTE_YOUR_REAL_BOT_TOKEN_HERE"
ALLOWED_USER_ID = 123456789

# ── Access Control ───────────────────────────
# Who can use the bot
ALLOW_ALL_USERS = False

# Admin users (can use admin commands)
ADMIN_USERS = [ALLOWED_USER_ID]

# Additional allowed users (optional)
ALLOWED_USERS = [ALLOWED_USER_ID]

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
# - This file is meant to be copied and edited locally
# - Keep your real version outside version control