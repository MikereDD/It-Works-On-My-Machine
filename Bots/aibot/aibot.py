# ------------------------------------------------------------
# file:     aibot.py
# author:   Mike Redd
# version:  3.1
# created:  2026-04-19
# updated:  2026-04-29
# desc:     Telegram AI bot with text + image generation
#           Config via /mnt/nvme1/work/bots/config/aibotrc.py
# ------------------------------------------------------------

import base64
import logging
import os
import sys
from io import BytesIO
from pathlib import Path

from openai import AsyncOpenAI
from telegram import Update
from telegram.ext import Application, CommandHandler, ContextTypes

# ── Load config ───────────────────────────────────────────────
CONFIG_PATH = Path(
    os.getenv("AIBOT_CONFIG", "/mnt/nvme1/work/bots/config/aibotrc.py")
)

if not CONFIG_PATH.exists():
    raise RuntimeError(f"Config not found: {CONFIG_PATH}")

if str(CONFIG_PATH.parent) not in sys.path:
    sys.path.insert(0, str(CONFIG_PATH.parent))

try:
    import aibotrc as cfg
except ImportError as exc:
    raise RuntimeError(f"Could not import config: {CONFIG_PATH}") from exc

# ── Paths ─────────────────────────────────────────────────────
LOG_DIR = Path(cfg.LOG_DIR)
IMAGE_DIR = Path(cfg.IMAGE_SAVE_DIR)

LOG_DIR.mkdir(parents=True, exist_ok=True)
IMAGE_DIR.mkdir(parents=True, exist_ok=True)

LOG_FILE = LOG_DIR / "aibot.log"

# ── Logging ──────────────────────────────────────────────────
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s | %(levelname)s | %(name)s | %(message)s",
    handlers=[
        logging.FileHandler(LOG_FILE, encoding="utf-8"),
        logging.StreamHandler(),
    ],
)

logger = logging.getLogger(__name__)

# ── OpenAI client ─────────────────────────────────────────────
client = AsyncOpenAI(api_key=cfg.OPENAI_API_KEY)

# ── Auth check: private DM + your Telegram ID only ────────────
def is_allowed(update: Update) -> bool:
    user = update.effective_user
    chat = update.effective_chat

    return bool(
        user
        and chat
        and user.id == cfg.ALLOWED_USER_ID
        and chat.type == "private"
    )

# ── Commands ─────────────────────────────────────────────────
async def start_cmd(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    if not is_allowed(update) or not update.message:
        return

    await update.message.reply_text(
        "AI Bot Ready.\n\n"
        "Commands:\n"
        "/ai <message>\n"
        "/img <prompt>\n"
        "/status\n"
        "/reset"
    )

async def ai_cmd(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    if not is_allowed(update) or not update.message:
        return

    prompt = " ".join(context.args).strip()

    if not prompt:
        await update.message.reply_text("Usage: /ai <message>")
        return

    try:
        logger.info("AI request from user_id=%s", update.effective_user.id)

        response = await client.responses.create(
            model=cfg.MODEL,
            input=prompt,
        )

        reply = (response.output_text or "").strip()
        if not reply:
            reply = "Empty response from model."

        await update.message.reply_text(reply)

    except Exception as exc:
        logger.exception("AI request failed")
        await update.message.reply_text(f"AI request failed: {exc}")

async def img_cmd(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    if not is_allowed(update) or not update.message:
        return

    prompt = " ".join(context.args).strip()

    if not prompt:
        await update.message.reply_text("Usage: /img <prompt>")
        return

    try:
        logger.info("IMG request from user_id=%s | prompt=%r", update.effective_user.id, prompt)

        result = await client.images.generate(
            model=cfg.IMAGE_MODEL,
            prompt=prompt,
            size=cfg.IMAGE_SIZE,
        )

        if not result.data:
            raise RuntimeError("Image API returned no data.")

        image_b64 = result.data[0].b64_json

        if not image_b64:
            raise RuntimeError("Image API returned no base64 image payload.")

        # Correct Python 3 base64 decode
        image_data = base64.b64decode(image_b64)

        image_filename = "latest.png"
        image_path = IMAGE_DIR / image_filename

        # Save locally
        image_path.write_bytes(image_data)

        # Send to Telegram
        image_stream = BytesIO(image_data)
        image_stream.name = image_filename
        image_stream.seek(0)

        await update.message.reply_photo(
            photo=image_stream,
            caption=f"Prompt: {prompt[:900]}",
        )

        logger.info("IMG success | saved=%s", image_path)

    except Exception as exc:
        logger.exception("Image generation failed")
        await update.message.reply_text(f"Image generation failed: {exc}")

async def status_cmd(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    if not is_allowed(update) or not update.message:
        return

    await update.message.reply_text(
        f"AI bot online\n"
        f"Text model:  {cfg.MODEL}\n"
        f"Image model: {cfg.IMAGE_MODEL}\n"
        f"Image size:  {cfg.IMAGE_SIZE}\n"
        f"Config:      {CONFIG_PATH}\n"
        f"Logs:        {LOG_FILE}\n"
        f"Images:      {IMAGE_DIR}"
    )

async def reset_cmd(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    if not is_allowed(update) or not update.message:
        return

    await update.message.reply_text("Reset done.")

# ── Main ─────────────────────────────────────────────────────
def main() -> None:
    app = Application.builder().token(cfg.BOT_TOKEN).build()

    app.add_handler(CommandHandler("start", start_cmd))
    app.add_handler(CommandHandler("ai", ai_cmd))
    app.add_handler(CommandHandler("img", img_cmd))
    app.add_handler(CommandHandler("status", status_cmd))
    app.add_handler(CommandHandler("reset", reset_cmd))

    logger.info("AI bot starting...")
    app.run_polling(drop_pending_updates=True)

if __name__ == "__main__":
    main()
