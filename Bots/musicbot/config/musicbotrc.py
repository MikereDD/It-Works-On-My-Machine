# ------------------------------------------------------------
# file:     musicbotrc.py
# author:   Mike Redd
# version:  1.0
# created:  2026-05-03
# updated:  2026-05-03
# desc:     Configuration for Telegram MusicBot
# ------------------------------------------------------------

BOT_TOKEN = "PUT_YOUR_BOT_TOKEN_HERE"
ALLOWED_USER_ID = 123456789

BASE_DIR = "/mnt/nvme1/work/bots/musicbot"
DOWNLOAD_DIR = "/mnt/nvme1/work/bots/downloads/music"
LOG_FILE = "/mnt/nvme1/work/bots/logs/musicbot.log"

# Optional access control
ALLOWED_USER_IDS = [
    # 123456789
]

MAX_FILE_MB = 49
AUDIO_FORMAT = "mp3"
AUDIO_QUALITY = "0"
