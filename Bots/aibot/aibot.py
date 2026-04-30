# ------------------------------------------------------------
# file:     aibot.py
# author:   Mike Redd
# version:  3.2
# created:  2026-04-19
# updated:  2026-04-29
# desc:     Telegram AI bot with text + high-quality image generation
#           Config via /mnt/nvme1/work/bots/config/aibotrc.py
# ------------------------------------------------------------

import base64
import logging
import os
import re
import sys
from datetime import datetime
from io import BytesIO
from pathlib import Path

from openai import AsyncOpenAI
from telegram import Update
from telegram.error import TimedOut
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

# ── Helpers ──────────────────────────────────────────────────
def is_allowed(update: Update) -> bool:
    user = update.effective_user
    chat = update.effective_chat

    return bool(
        user
        and chat
        and user.id == cfg.ALLOWED_USER_ID
        and chat.type == "private"
    )

def slugify(text: str, max_len: int = 64) -> str:
    text = text.lower().strip()
    text = re.sub(r"[^a-z0-9\s_-]", "", text)
    text = re.sub(r"[\s_-]+", "-", text)
    text = text.strip("-")
    return (text or "image")[:max_len].rstrip("-")

def make_image_filename(prompt: str) -> str:
    stamp = datetime.now().strftime("%Y-%m-%d_%H-%M-%S")
    return f"{slugify(prompt)}_{stamp}.png"

def build_hyperreal_prompt(prompt: str) -> str:
    style = getattr(cfg, "IMAGE_STYLE_PROMPT", "").strip()

    if not style:
        style = (
            "Hyper-realistic, ultra-detailed, cinematic 4K realism, "
            "professional photography, realistic textures, realistic lighting, "
            "physically accurate shadows, high dynamic range, sharp focus, "
            "real-world lens depth of field, natural proportions, no anime, "
            "no cartoon, no illustration, no painterly style, no plastic skin."
        )

    return f"{prompt.strip()}. {style}"

def format_api_error(exc: Exception) -> str:
    msg = str(exc).lower()

    if "insufficient_quota" in msg or "quota" in msg:
        return "OpenAI API quota exceeded. Check billing and usage limits."

    if "rate limit" in msg or "429" in msg:
        return "Rate limit hit. Wait a moment and try again."

    if "invalid_api_key" in msg or "incorrect api key" in msg:
        return "Invalid OpenAI API key. Check aibotrc.py."

    if "model" in msg and "not found" in msg:
        return "Configured model is not available for this API key."

    return f"Request failed: {exc}"

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
        await update.message.reply_text(format_api_error(exc))

async def img_cmd(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    if not is_allowed(update) or not update.message:
        return

    prompt = " ".join(context.args).strip()

    if not prompt:
        await update.message.reply_text("Usage: /img <prompt>")
        return

    try:
        logger.info(
            "IMG request from user_id=%s | prompt=%r",
            update.effective_user.id,
            prompt,
        )

        final_prompt = build_hyperreal_prompt(prompt)

        result = await client.images.generate(
            model=cfg.IMAGE_MODEL,
            prompt=final_prompt,
            size=cfg.IMAGE_SIZE,
            quality=cfg.IMAGE_QUALITY,
            output_format=cfg.IMAGE_OUTPUT_FORMAT,
        )

        if not result.data:
            raise RuntimeError("Image API returned no data.")

        image_b64 = result.data[0].b64_json

        if not image_b64:
            raise RuntimeError("Image API returned no base64 image payload.")

        image_data = base64.b64decode(image_b64)

        image_filename = make_image_filename(prompt)
        image_path = IMAGE_DIR / image_filename
        image_path.write_bytes(image_data)

        image_stream = BytesIO(image_data)
        image_stream.name = image_filename
        image_stream.seek(0)

        await update.message.reply_photo(
            photo=image_stream,
            caption=(
                f"Prompt: {prompt[:700]}\n"
                f"Size: {cfg.IMAGE_SIZE} | Quality: {cfg.IMAGE_QUALITY}"
            ),
            read_timeout=getattr(cfg, "TELEGRAM_READ_TIMEOUT", 120),
            write_timeout=getattr(cfg, "TELEGRAM_WRITE_TIMEOUT", 120),
            connect_timeout=getattr(cfg, "TELEGRAM_CONNECT_TIMEOUT", 30),
            pool_timeout=getattr(cfg, "TELEGRAM_POOL_TIMEOUT", 30),
        )

        logger.info("IMG success | saved=%s", image_path)

    except TimedOut:
        logger.warning("Telegram timed out while sending generated image.")
        await update.message.reply_text(
            "Image was generated and saved locally, but Telegram timed out while sending it."
        )

    except Exception as exc:
        logger.exception("Image generation failed")
        await update.message.reply_text(format_api_error(exc))

async def status_cmd(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    if not is_allowed(update) or not update.message:
        return

    await update.message.reply_text(
        f"AI bot online\n"
        f"Text model:    {cfg.MODEL}\n"
        f"Image model:   {cfg.IMAGE_MODEL}\n"
        f"Image size:    {cfg.IMAGE_SIZE}\n"
        f"Image quality: {cfg.IMAGE_QUALITY}\n"
        f"Image format:  {cfg.IMAGE_OUTPUT_FORMAT}\n"
        f"Config:        {CONFIG_PATH}\n"
        f"Logs:          {LOG_FILE}\n"
        f"Images:        {IMAGE_DIR}"
    )

async def reset_cmd(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    if not is_allowed(update) or not update.message:
        return

    await update.message.reply_text("Reset done.")

# ── Main ─────────────────────────────────────────────────────
def main() -> None:
    app = (
        Application.builder()
        .token(cfg.BOT_TOKEN)
        .read_timeout(getattr(cfg, "TELEGRAM_READ_TIMEOUT", 120))
        .write_timeout(getattr(cfg, "TELEGRAM_WRITE_TIMEOUT", 120))
        .connect_timeout(getattr(cfg, "TELEGRAM_CONNECT_TIMEOUT", 30))
        .pool_timeout(getattr(cfg, "TELEGRAM_POOL_TIMEOUT", 30))
        .build()
    )

    app.add_handler(CommandHandler("start", start_cmd))
    app.add_handler(CommandHandler("ai", ai_cmd))
    app.add_handler(CommandHandler("img", img_cmd))
    app.add_handler(CommandHandler("status", status_cmd))
    app.add_handler(CommandHandler("reset", reset_cmd))

    logger.info("AI bot starting...")
    app.run_polling(drop_pending_updates=True)

if __name__ == "__main__":
    main()
