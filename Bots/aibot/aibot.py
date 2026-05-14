# ------------------------------------------------------------
# file:     aibot.py
# author:   Mike Redd
# version:  3.9
# created:  2026-04-19
# updated:  2026-05-09
# desc:     Telegram AI bot with text + tiered image generation
#           Config via /mnt/nvme1/work/bots/config/aibotrc.py
# ------------------------------------------------------------

import asyncio
import base64
import importlib
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
from telegram.ext import Application, CommandHandler, ContextTypes, MessageHandler, filters

# ── Branding ─────────────────────────────────────────────────

BOT_NAME = "Zaphkiel"
BOT_VERSION = "3.9"

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

CONVERT_DIR = IMAGE_DIR / "converted"
CONVERT_DIR.mkdir(parents=True, exist_ok=True)

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

# ── Reload Support ────────────────────────────────────────────
def reload_runtime_config() -> None:
    global cfg, LOG_DIR, IMAGE_DIR, CONVERT_DIR, LOG_FILE, client

    cfg = importlib.reload(cfg)

    LOG_DIR = Path(cfg.LOG_DIR)
    IMAGE_DIR = Path(cfg.IMAGE_SAVE_DIR)

    LOG_DIR.mkdir(parents=True, exist_ok=True)
    IMAGE_DIR.mkdir(parents=True, exist_ok=True)

    CONVERT_DIR = IMAGE_DIR / "converted"
    CONVERT_DIR.mkdir(parents=True, exist_ok=True)

    LOG_FILE = LOG_DIR / "aibot.log"

    client = AsyncOpenAI(api_key=cfg.OPENAI_API_KEY)

# ── Helpers ──────────────────────────────────────────────────
def get_admin_users() -> set[int]:
    users = set(getattr(cfg, "ADMIN_USERS", []) or [])
    owner = getattr(cfg, "ALLOWED_USER_ID", 0)
    if owner:
        users.add(owner)
    return users

def is_admin(user_id: int | None) -> bool:
    return bool(user_id and user_id in get_admin_users())

def can_use_context(user_id: int | None, chat_type: str | None) -> bool:
    if not user_id:
        return False

    if is_admin(user_id):
        return chat_type == "private" or bool(getattr(cfg, "ALLOW_GROUPS", False))

    allowed_users = set(getattr(cfg, "ALLOWED_USERS", []) or [])
    if user_id in allowed_users:
        return chat_type == "private" or bool(getattr(cfg, "ALLOW_GROUPS", False))

    return False

def is_allowed(update: Update) -> bool:
    user = update.effective_user
    chat = update.effective_chat
    return bool(user and chat and can_use_context(user.id, chat.type))

def get_public_bot_mention() -> str:
    username = str(getattr(cfg, "BOT_USERNAME", "") or "").strip().lstrip("@")
    return f"@{username}" if username else BOT_NAME

def get_bot_mention_names() -> set[str]:
    names = {BOT_NAME.lower()}

    username = str(getattr(cfg, "BOT_USERNAME", "") or "").strip().lower().lstrip("@")
    if username:
        names.add(username)
        names.add(f"@{username}")

    for item in getattr(cfg, "BOT_MENTION_ALIASES", ()) or ():
        alias = str(item).strip().lower().lstrip("@")
        if alias:
            names.add(alias)
            names.add(f"@{alias}")

    return names

def parse_mention_command(text: str | None) -> tuple[str, str] | None:
    if not text:
        return None

    parts = text.strip().split(maxsplit=2)
    if len(parts) < 2:
        return None

    mention = parts[0].strip().rstrip(":,").lower()
    if mention not in get_bot_mention_names():
        return None

    command = parts[1].strip().lower().lstrip("/")
    args = parts[2].strip() if len(parts) >= 3 else ""

    aliases = {
        "ask": "ai",
        "chat": "ai",
        "talk": "ai",
        "draw": "img",
        "image": "img",
        "picture": "img",
        "styles": "styles",
        "style": "styles",
        "help": "help",
        "status": "status",
        "reload": "reload",
        "restart": "restart",
    }

    return aliases.get(command, command), args

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


def get_convert_presets() -> dict:
    return getattr(
        cfg,
        "CONVERT_STYLE_PRESETS",
        {
            "ghibli": (
                "Studio Ghibli 1990s hand-painted cel animation style. Preserve composition, pose, "
                "facial identity, clothing, camera angle, and subject count. Soft watercolor backgrounds, "
                "gouache textures, warm natural lighting, cinematic framing, expressive eyes, subtle emotion, "
                "clean hand-drawn lines, and whimsical environmental detail. Avoid: modern anime gloss, "
                "plastic skin, oversaturated colors, blurry faces, distorted anatomy, extra/missing limbs, "
                "text, logos, or watermarks."
            ),
            "cozy-anime": (
                "Transform this image into a whimsical hand-painted animated fantasy style, "
                "soft watercolor backgrounds, warm lighting, dreamy atmosphere, expressive detail."
            ),
            "comic": (
                "Transform this image into a dramatic comic book illustration, bold ink lines, "
                "cinematic lighting, vivid colors, dynamic composition."
            ),
            "hyperreal": (
                "Transform this image into a hyper-realistic cinematic 4K photograph, "
                "lifelike textures, realistic lighting, sharp focus, natural detail."
            ),
            "oilpaint": (
                "Transform this image into a detailed classical oil painting, rich brush strokes, "
                "painterly texture, dramatic light, museum-quality finish."
            ),
            "darkfantasy": (
                "Transform this image into a dark fantasy movie poster style, moody lighting, "
                "cinematic atmosphere, gothic detail, dramatic composition."
            ),
        },
    )

def get_convert_style_prompt(style: str) -> str | None:
    presets = get_convert_presets()
    return presets.get(style)

def make_converted_filename(style: str) -> str:
    stamp = datetime.now().strftime("%Y-%m-%d_%H-%M-%S")
    return f"{slugify(style)}_converted_{stamp}.png"

async def download_reply_photo(update: Update) -> Path:
    if not update.message or not update.message.reply_to_message:
        raise RuntimeError("Reply to an image with /convert <style>")

    reply = update.message.reply_to_message

    if not reply.photo:
        raise RuntimeError("Reply target does not contain an image.")

    photo = reply.photo[-1]
    telegram_file = await photo.get_file()

    temp_input = CONVERT_DIR / "convert_input.jpg"
    await telegram_file.download_to_drive(temp_input)

    return temp_input


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


async def animate_progress(message, done_event: asyncio.Event, label: str = "Working") -> None:
    frames = [
        "▱▱▱▱▱▱▱▱▱▱ 0%",
        "▰▱▱▱▱▱▱▱▱▱ 10%",
        "▰▰▱▱▱▱▱▱▱▱ 20%",
        "▰▰▰▱▱▱▱▱▱▱ 30%",
        "▰▰▰▰▱▱▱▱▱▱ 40%",
        "▰▰▰▰▰▱▱▱▱▱ 50%",
        "▰▰▰▰▰▰▱▱▱▱ 60%",
        "▰▰▰▰▰▰▰▱▱▱ 70%",
        "▰▰▰▰▰▰▰▰▱▱ 80%",
        "▰▰▰▰▰▰▰▰▰▱ 90%",
    ]

    i = 0

    while not done_event.is_set():
        try:
            await message.edit_text(f"🎨 {label}...\n{frames[i % len(frames)]}")
        except Exception:
            pass

        i += 1
        await asyncio.sleep(2)

async def stop_progress(
    progress_msg,
    done_event: asyncio.Event,
    progress_task,
    delete_message: bool = True,
) -> None:
    try:
        done_event.set()
    except Exception:
        pass

    try:
        await progress_task
    except Exception:
        pass

    if delete_message:
        try:
            await progress_msg.delete()
        except Exception:
            pass


async def delayed_restart() -> None:
    await asyncio.sleep(1)
    os.execv(sys.executable, [sys.executable] + sys.argv)

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
        "/convert <style>  (reply to image)\n"
        "/styles\n"
        "/help\n"
        "/status\n"
        "/reload\n"
        "/restart\n"
        "/reset\n\n"
        "Mention examples:\n"
        f"{get_public_bot_mention()} ask <message>\n"
        f"{get_public_bot_mention()} img <prompt>"
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
        "Mention examples:\n"
        f"{get_public_bot_mention()} ask explain this error\n"
        f"{get_public_bot_mention()} img angel warrior --ultra --portrait\n\n"
        "Convert images:\n"
        "/convert cozy-anime   Reply to an image to restyle it\n"
        "/convert comic\n"
        "/convert hyperreal\n"
        "/styles              List available convert styles\n\n"
        "System:\n"
        "/status\n"
        "/reload   Reload config without restarting\n"
        "/restart  Restart bot process after code edits\n"
        "/reset\n\n"
        "⚙️ Built for clarity, not chaos."
    )


async def send_ai_reply(update: Update, prompt: str) -> None:
    if not update.message:
        return

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


async def send_image_reply(update: Update, context: ContextTypes.DEFAULT_TYPE, raw_prompt: str) -> None:
    if not update.message:
        return

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
        progress_msg = await update.message.reply_text(
            f"🎨 Generating image...\n"
            f"Tier: {tier} | Size: {size} | Quality: {quality}"
        )

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

        try:
            await progress_msg.delete()
        except Exception:
            pass

        logger.info("IMG success | saved=%s", image_path)

    except TimedOut:
        logger.warning("Telegram timed out while sending generated image.")
        await update.message.reply_text(
            "Image was generated and saved locally, but Telegram timed out while sending it."
        )

    except Exception as exc:
        logger.exception("Image generation failed")
        await update.message.reply_text(format_api_error(exc))



async def ai_cmd(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    if not is_allowed(update) or not update.message:
        return

    await send_ai_reply(update, " ".join(context.args).strip())

async def img_cmd(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    if not is_allowed(update) or not update.message:
        return

    await send_image_reply(update, context, " ".join(context.args).strip())

async def styles_cmd(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    if not is_allowed(update) or not update.message:
        return

    presets = get_convert_presets()

    lines = [f"🎨 {BOT_NAME} conversion styles:", ""]
    for name in sorted(presets.keys()):
        lines.append(f"• {name}")

    lines.extend([
        "",
        "Usage:",
        "/convert <style>",
        "",
        "Reply to an image with the command above.",
    ])

    await update.message.reply_text("\n".join(lines))

async def convert_cmd(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    if not is_allowed(update) or not update.message:
        return

    style = " ".join(context.args).strip().lower()

    if not style:
        await update.message.reply_text(
            "Usage: /convert <style>\n\n"
            "Reply to an image with this command.\n"
            "Use /styles to list available styles."
        )
        return

    style_prompt = get_convert_style_prompt(style)

    if not style_prompt:
        await update.message.reply_text(
            f"Unknown style: {style}\n\n"
            "Use /styles to list available styles."
        )
        return

    try:
        logger.info(
            "CONVERT request from user_id=%s | style=%s",
            update.effective_user.id,
            style,
        )

        progress_msg = await update.message.reply_text(
            f"🎨 Converting image using style: {style}\n"
            "▱▱▱▱▱▱▱▱▱▱ 0%"
        )

        done_event = asyncio.Event()
        progress_task = context.application.create_task(
            animate_progress(
                progress_msg,
                done_event,
                f"Converting image using style: {style}",
            )
        )

        input_path = await download_reply_photo(update)

        with open(input_path, "rb") as image_file:
            result = await client.images.edit(
                model=cfg.IMAGE_MODEL,
                image=image_file,
                prompt=style_prompt,
                size=getattr(cfg, "CONVERT_IMAGE_SIZE", cfg.IMAGE_SIZE),
                quality=getattr(cfg, "CONVERT_IMAGE_QUALITY", cfg.IMAGE_QUALITY),
            )

        if not result.data:
            raise RuntimeError("Image edit API returned no data.")

        image_b64 = result.data[0].b64_json

        if not image_b64:
            raise RuntimeError("Image edit API returned no base64 image payload.")

        image_data = base64.b64decode(image_b64)

        image_filename = make_converted_filename(style)
        image_path = CONVERT_DIR / image_filename
        image_path.write_bytes(image_data)

        image_stream = BytesIO(image_data)
        image_stream.name = image_filename
        image_stream.seek(0)

        await update.message.reply_photo(
            photo=image_stream,
            caption=f"Converted style: {style}",
            read_timeout=getattr(cfg, "TELEGRAM_READ_TIMEOUT", 120),
            write_timeout=getattr(cfg, "TELEGRAM_WRITE_TIMEOUT", 120),
            connect_timeout=getattr(cfg, "TELEGRAM_CONNECT_TIMEOUT", 30),
            pool_timeout=getattr(cfg, "TELEGRAM_POOL_TIMEOUT", 30),
        )

        await stop_progress(progress_msg, done_event, progress_task, delete_message=True)

        logger.info("CONVERT success | saved=%s", image_path)

    except TimedOut:
        logger.warning("Telegram timed out while sending converted image.")

        if "done_event" in locals() and "progress_task" in locals() and "progress_msg" in locals():
            await stop_progress(progress_msg, done_event, progress_task, delete_message=False)
            try:
                await progress_msg.edit_text(
                    "⚠️ Image was converted and saved locally, but Telegram timed out while sending it."
                )
            except Exception:
                pass
        else:
            await update.message.reply_text(
                "Image was converted and saved locally, but Telegram timed out while sending it."
            )

    except Exception as exc:
        logger.exception("Image conversion failed")

        if "done_event" in locals() and "progress_task" in locals() and "progress_msg" in locals():
            await stop_progress(progress_msg, done_event, progress_task, delete_message=False)
            try:
                await progress_msg.edit_text(f"❌ Conversion failed: {format_api_error(exc)}")
            except Exception:
                await update.message.reply_text(format_api_error(exc))
        else:
            await update.message.reply_text(format_api_error(exc))



async def mention_cmd(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    if not update.message:
        return

    parsed = parse_mention_command(update.message.text)
    if not parsed:
        return

    if not is_allowed(update):
        return

    command, args = parsed

    if command == "ai":
        await send_ai_reply(update, args)
        return

    if command == "img":
        await send_image_reply(update, context, args)
        return

    if command == "help":
        await help_cmd(update, context)
        return

    if command == "styles":
        await styles_cmd(update, context)
        return

    if command == "status":
        await status_cmd(update, context)
        return

    if command == "reload":
        await reload_cmd(update, context)
        return

    if command == "restart":
        await restart_cmd(update, context)
        return


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
        f"Bot username:  {get_public_bot_mention()}\n"
        f"Groups:        {'enabled' if getattr(cfg, 'ALLOW_GROUPS', False) else 'disabled'}\n"
        f"Admins:        {len(get_admin_users())}\n"
        f"Config:        {CONFIG_PATH}\n"
        f"Logs:          {LOG_FILE}\n"
        f"Images:        {IMAGE_DIR}\n"
        f"Converted:     {CONVERT_DIR}\n"
        f"Styles:        {len(get_convert_presets())}"
    )

async def reload_cmd(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    if not is_allowed(update) or not update.message:
        return

    try:
        reload_runtime_config()

        logger.info("Config reloaded from %s", CONFIG_PATH)

        await update.message.reply_text(
            f"🔄 {BOT_NAME} config reloaded\n\n"
            f"Text model:    {cfg.MODEL}\n"
            f"Image model:   {cfg.IMAGE_MODEL}\n"
            f"Default tier:  {getattr(cfg, 'DEFAULT_IMAGE_TIER', 'high')}\n"
            f"Image size:    {cfg.IMAGE_SIZE}\n"
            f"Image quality: {cfg.IMAGE_QUALITY}\n"
            f"Image format:  {cfg.IMAGE_OUTPUT_FORMAT}\n"
            f"Logs:          {LOG_FILE}\n"
            f"Images:        {IMAGE_DIR}\n"
            f"Converted:     {CONVERT_DIR}\n"
            f"Styles:        {len(get_convert_presets())}"
        )

    except Exception as exc:
        logger.exception("Config reload failed")
        await update.message.reply_text(f"Config reload failed: {exc}")

async def restart_cmd(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    if not is_allowed(update) or not update.message:
        return

    logger.info("Restart requested by user_id=%s", update.effective_user.id)

    await update.message.reply_text(
        f"♻️ Restarting {BOT_NAME}...\n"
        "The tmux pane should stay alive."
    )

    context.application.create_task(delayed_restart())

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

    app.add_handler(MessageHandler(filters.TEXT & ~filters.COMMAND, mention_cmd))
    app.add_handler(CommandHandler("start", start_cmd))
    app.add_handler(CommandHandler("help", help_cmd))
    app.add_handler(CommandHandler("ai", ai_cmd))
    app.add_handler(CommandHandler("img", img_cmd))
    app.add_handler(CommandHandler("convert", convert_cmd))
    app.add_handler(CommandHandler("styles", styles_cmd))
    app.add_handler(CommandHandler("status", status_cmd))
    app.add_handler(CommandHandler("reload", reload_cmd))
    app.add_handler(CommandHandler("restart", restart_cmd))
    app.add_handler(CommandHandler("reset", reset_cmd))

    logger.info("%s v%s starting...", BOT_NAME, BOT_VERSION)
    app.run_polling(drop_pending_updates=True)

if __name__ == "__main__":
    main()