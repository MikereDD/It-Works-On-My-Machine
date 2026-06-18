#--------------------------------------------
# file: cardbotrc.py  (example)
# desc: Config for "Gabriel" (cardbot.py).
#       Copy to  Bots/config/cardbotrc.py
#       and fill in the real values.
#--------------------------------------------

# Telegram bot token from BotFather (required).
# Leave blank to read it from the CARDBOT_TOKEN env var instead.
BOT_TOKEN = ""

# Your Telegram user ID - owns/administers the bot.
# Private chats are restricted to this user unless ALLOW_ALL_USERS is True.
ALLOWED_USER_ID = 0

# Extra users permitted in private chat (besides the owner).
ALLOWED_USERS = []
ADMIN_USERS = []

# If True, anyone may DM the bot. Groups are always allowed to auto-watch.
ALLOW_ALL_USERS = False

# Group/supergroup chat IDs where passive link-watching is turned OFF.
AUTO_WATCH_DISABLED_CHAT_IDS = []

# Verbose logging (INFO instead of WARNING).
DEBUG_MODE = False

# Base dir for logs/ (defaults to the Bots/ repo root).
# BASE_DIR = "~/cardbot"
