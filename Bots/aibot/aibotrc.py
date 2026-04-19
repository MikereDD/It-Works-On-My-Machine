# ------------------------------------------------------------
# file:     aibotrc.py
# version:  1.3
# created:  2026-04-19
# updated:  2026-04-19
# desc:     Private config for aibot
# ------------------------------------------------------------

BOT_TOKEN = "YOUR_TELEGRAM_BOT_TOKEN"
OPENAI_API_KEY = "YOUR_OPENAI_API_KEY"
ALLOWED_USER_ID = 123456789

MODEL = "gpt-5.4-mini"
VISION_MODEL = "gpt-5.4-mini"
IMAGE_MODEL = "gpt-image-1"

IMAGE_SIZE = "1024x1024"
IMAGE_QUALITY = "auto"
IMAGE_SAVE_DIR = "G:/bots/images"

MAX_MEMORY = 12
MAX_INPUT_CHARS = 2000
RATE_LIMIT_SECONDS = 5

MAX_IMAGES_PER_MINUTE = 3
MAX_IMAGES_PER_DAY = 25

TELEGRAM_READ_TIMEOUT = 60
TELEGRAM_WRITE_TIMEOUT = 60
TELEGRAM_CONNECT_TIMEOUT = 30
TELEGRAM_POOL_TIMEOUT = 30