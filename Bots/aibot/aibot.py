# ------------------------------------------------------------
# file:     aibot.py
# author:   Mike Redd
# version:  3.4
# created:  2026-04-19
# updated:  2026-04-29
# desc:     Telegram AI bot with text + tiered image generation
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

# ── Branding ─────────────────────────────────────────────────

BOT_NAME = "Zaphkiel"
BOT_VERSION = "3.4"

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

def make_image_filename(prompt: str, tier: str) -> str:
    stamp = datetime.now().strftime("%Y-%m-%d_%H-%M-%S")
    return f"{slugify(prompt)}_{tier}_{stamp}.png"

def get_style_prompt(tier: str) -> str:
    if tier == "low":
        return (
            "Simple cartoon style, playful, clean lines, flat colors, low detail, "
            "stylized, not realistic, fun illustration."
        )

    if tier == "med":
        return (
            "Semi-realistic digital art, good detail, clean lighting, balanced style, "
            "moderate realism, polished but not ultra-photorealistic."
        )

    if tier == "high":
        return (
            "Highly detailed realistic image, cinematic lighting, sharp focus, "
            "realistic textures, realistic proportions, professional digital realism."
        )

    return getattr(
        cfg,
        "IMAGE_STYLE_PROMPT",
        (
            "Hyper-realistic, ultra-detailed, cinematic 4K realism, "
            "professional photography, realistic textures, realistic lighting, "
            "physically accurate shadows, high dynamic range, sharp focus, "
            "real-world lens depth of field, natural proportions, realistic material detail, "
            "lifelike realism, no anime, no cartoon, no illustration, no painterly style, "
            "no plastic skin."
        ),
    ).strip()

def parse_img_request(raw_prompt: str):
    tier = getattr(cfg, "DEFAULT_IMAGE_TIER", "high").strip().lower()
    size = getattr(cfg, "IMAGE_SIZE", "1024x1536").strip()
    quality = getattr(cfg, "IMAGE_QUALITY", "high").strip().lower()

    flags = {
        "--low": "low",
        "--med": "med",
        "--medium": "med",
        "--high": "high",
        "--ultra": "ultra",
    }

    prompt = raw_prompt

    for flag, selected_tier in flags.items():
        if flag in prompt:
            tier = selected_tier
            prompt = prompt.replace(flag, "")

    if "--square" in prompt:
        size = "1024x1024"
        prompt = prompt.replace("--square", "")

    if "--portrait" in prompt:
        size = "1024x1536"
        prompt = prompt.replace("--portrait", "")

    if "--landscape" in prompt:
        size = "1536x1024"
        prompt = prompt.replace("--landscape", "")

    if tier == "low":
        quality = "low"
        size = "1024x1024"
    elif tier == "med":
        quality = "medium"
        size = "1024x1024"
    elif tier == "high":
        quality = "high"
    elif tier == "ultra":
        quality = "high"
        if not any(flag in raw_prompt for flag in ["--square", "--portrait", "--landscape"]):
            size = "1024x1536"

    prompt = re.sub(r"\s+", " ", prompt).strip()
    style_prompt = get_style_prompt(tier)
    final_prompt = f"{prompt}. {style_prompt}"

    return prompt, final_prompt, tier, size, quality

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
        f"🤖 {BOT_NAME} v{BOT_VERSION}\n"
        "The voice of thought.\n\n"
        "Commands:\n"
        "/ai <message>\n"
        "/img <prompt> [--low|--med|--high|--ultra]\n"
        "/img <prompt> [--square|--portrait|--landscape]\n"
        "/help\n"
        "/status\n"
        "/reset"
    )

async def help_cmd(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    if not is_allowed(update) or not update.message:
        return

    await update.message.reply_text(
        f"🤖 {BOT_NAME} v{BOT_VERSION}\n"
        "The voice of thought.\n\n"
        "Commands:\n"
        "/ai <message>\n"
        "  Chat with AI\n\n"
        "/img <prompt>\n"
        "  Generate an image\n\n"
        "Quality flags:\n"
        "  --low     cartoon / simple / fast\n"
        "  --med     balanced semi-realistic\n"
        "  --high    detailed realistic\n"
        "  --ultra   lifelike hyper-realism\n\n"
        "Size flags:\n"
        "  --square      1024x1024\n"
        "  --portrait    1024x1536\n"
        "  --landscape   1536x1024\n\n"
        "Examples:\n"
        "/img angel warrior --low\n"
        "/img zaphkiel white gold armor --ultra --portrait\n"
        "/img dark fantasy throne room --high --landscape\n\n"
        "Info:\n"
        "/status\n"
        "/reset\n\n"
        "⚙️ Built for clarity, not chaos."
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

    raw_prompt = " ".join(context.args).strip()

    if not raw_prompt:
        await update.message.reply_text(
            "Usage: /img <prompt> [--low|--med|--high|--ultra] "
            "[--square|--portrait|--landscape]"
        )
        return

    prompt, final_prompt, tier, size, quality = parse_img_request(raw_prompt)

    if not prompt:
        await update.message.reply_text("Prompt cannot be empty.")
        return

    try:
        logger.info(
            "IMG request from user_id=%s | tier=%s | size=%s | quality=%s | prompt=%r",
            update.effective_user.id,
            tier,
            size,
            quality,
            prompt,
        )

        result = await client.images.generate(
            model=cfg.IMAGE_MODEL,
            prompt=final_prompt,
            size=size,
            quality=quality,
            output_format=cfg.IMAGE_OUTPUT_FORMAT,
        )

        if not result.data:
            raise RuntimeError("Image API returned no data.")

        image_b64 = result.data[0].b64_json

        if not image_b64:
            raise RuntimeError("Image API returned no base64 image payload.")

        image_data = base64.b64decode(image_b64)

        image_filename = make_image_filename(prompt, tier)
        image_path = IMAGE_DIR / image_filename
        image_path.write_bytes(image_data)

        image_stream = BytesIO(image_data)
        image_stream.name = image_filename
        image_stream.seek(0)

        await update.message.reply_photo(
            photo=image_stream,
            caption=(
                f"Prompt: {prompt[:650]}\n"
                f"Tier: {tier} | Size: {size} | Quality: {quality}"
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
        f"{BOT_NAME} v{BOT_VERSION} online\n"
        f"Text model:    {cfg.MODEL}\n"
        f"Image model:   {cfg.IMAGE_MODEL}\n"
        f"Default tier:  {getattr(cfg, 'DEFAULT_IMAGE_TIER', 'high')}\n"
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
    app.add_handler(CommandHandler("help", help_cmd))
    app.add_handler(CommandHandler("ai", ai_cmd))
    app.add_handler(CommandHandler("img", img_cmd))
    app.add_handler(CommandHandler("status", status_cmd))
    app.add_handler(CommandHandler("reset", reset_cmd))

    logger.info("%s v%s starting...", BOT_NAME, BOT_VERSION)
    app.run_polling(drop_pending_updates=True)

if __name__ == "__main__":
    main()
