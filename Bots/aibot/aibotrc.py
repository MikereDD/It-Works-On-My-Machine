# ------------------------------------------------------------
# file:     aibotrc.py
# author:   Mike Redd
# version:  1.1
# created:  2026-04-29
# updated:  2026-04-29
# desc:     Configuration for Zahkiel AI bot
# ------------------------------------------------------------

# ── REQUIRED ─────────────────────────────────────────────────
BOT_TOKEN = "YOUR_TELEGRAM_BOT_TOKEN"
OPENAI_API_KEY = "YOUR_OPENAI_API_KEY"
ALLOWED_USER_ID = 123456789

# ── MODELS ───────────────────────────────────────────────────
MODEL = "gpt-5.4-mini"
IMAGE_MODEL = "gpt-image-1"

# ── IMAGE SETTINGS: BEST QUALITY / HYPER REALISM ─────────────
IMAGE_SIZE = "1024x1536"
IMAGE_QUALITY = "high"
IMAGE_OUTPUT_FORMAT = "png"

IMAGE_STYLE_PROMPT = (
    "Hyper-realistic, ultra-detailed, cinematic 4K realism, "
    "professional photography, realistic textures, realistic lighting, "
    "physically accurate shadows, high dynamic range, sharp focus, "
    "real-world lens depth of field, natural proportions, realistic material detail, "
    "no anime, no cartoon, no illustration, no painterly style, no plastic skin."
)

# ── PATHS ────────────────────────────────────────────────────
LOG_DIR = "/mnt/nvme1/work/bots/logs"
IMAGE_SAVE_DIR = "/mnt/nvme1/work/bots/images"

# ── TELEGRAM TIMEOUTS ────────────────────────────────────────
TELEGRAM_READ_TIMEOUT = 120
TELEGRAM_WRITE_TIMEOUT = 120
TELEGRAM_CONNECT_TIMEOUT = 30
TELEGRAM_POOL_TIMEOUT = 30
