import asyncio
import base64
import logging
import re
import sys
import time
from collections import defaultdict, deque
from datetime import datetime
from io import BytesIO
from pathlib import Path
from typing import Any, Deque, Dict, List, Tuple

from openai import AsyncOpenAI
from telegram import Update
from telegram.constants import ChatAction
from telegram.error import TimedOut
from telegram.ext import (
    Application,
    CommandHandler,
    ContextTypes,
    MessageHandler,
    filters,
)

# ------------------------------------------------------------
# file:     aibot.py
# version:  3.1
# created:  2026-04-19
# updated:  2026-04-19
# desc:     Telegram AI bot with text, vision, and image generation
#           Config via G:\bots\config\aibotrc.py
#           Includes image presets, local saving, and rate limits
# ------------------------------------------------------------

# ── Config load ───────────────────────────────────────────────
CONFIG_DIR = Path("G:/bots/config")
CONFIG_FILE = CONFIG_DIR / "aibotrc.py"

if not CONFIG_FILE.exists():
    raise RuntimeError(f"Config file not found: {CONFIG_FILE}")

if str(CONFIG_DIR) not in sys.path:
    sys.path.insert(0, str(CONFIG_DIR))

try:
    import aibotrc as cfg
except ImportError as exc:
    raise RuntimeError(f"Could not import config: {CONFIG_FILE}") from exc

# ── Paths ─────────────────────────────────────────────────────
LOG_DIR = Path("G:/bots/logs")
LOG_DIR.mkdir(parents=True, exist_ok=True)
LOG_FILE = LOG_DIR / "aibot.log"

IMAGE_SAVE_DIR = Path(getattr(cfg, "IMAGE_SAVE_DIR", "G:/bots/images"))
IMAGE_SAVE_DIR.mkdir(parents=True, exist_ok=True)

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

# ── Config values ─────────────────────────────────────────────
TELEGRAM_BOT_TOKEN = getattr(cfg, "BOT_TOKEN", "").strip()
OPENAI_API_KEY = getattr(cfg, "OPENAI_API_KEY", "").strip()

OPENAI_MODEL = getattr(cfg, "MODEL", "gpt-5.4-mini").strip()
VISION_MODEL = getattr(cfg, "VISION_MODEL", OPENAI_MODEL).strip()
IMAGE_MODEL = getattr(cfg, "IMAGE_MODEL", "gpt-image-1").strip()
IMAGE_SIZE = getattr(cfg, "IMAGE_SIZE", "1024x1024").strip()
IMAGE_QUALITY = getattr(cfg, "IMAGE_QUALITY", "auto").strip().lower()

MAX_MEMORY = int(getattr(cfg, "MAX_MEMORY", 12))
MAX_INPUT_CHARS = int(getattr(cfg, "MAX_INPUT_CHARS", 2000))
RATE_LIMIT_SECONDS = int(getattr(cfg, "RATE_LIMIT_SECONDS", 5))

TELEGRAM_READ_TIMEOUT = int(getattr(cfg, "TELEGRAM_READ_TIMEOUT", 60))
TELEGRAM_WRITE_TIMEOUT = int(getattr(cfg, "TELEGRAM_WRITE_TIMEOUT", 60))
TELEGRAM_CONNECT_TIMEOUT = int(getattr(cfg, "TELEGRAM_CONNECT_TIMEOUT", 30))
TELEGRAM_POOL_TIMEOUT = int(getattr(cfg, "TELEGRAM_POOL_TIMEOUT", 30))

MAX_IMAGES_PER_MINUTE = int(getattr(cfg, "MAX_IMAGES_PER_MINUTE", 3))
MAX_IMAGES_PER_DAY = int(getattr(cfg, "MAX_IMAGES_PER_DAY", 25))

try:
    ALLOWED_USER_ID = int(getattr(cfg, "ALLOWED_USER_ID", 0))
except (TypeError, ValueError) as exc:
    raise RuntimeError("ALLOWED_USER_ID must be an integer in aibotrc.py") from exc

for name, value in [
    ("BOT_TOKEN", TELEGRAM_BOT_TOKEN),
    ("OPENAI_API_KEY", OPENAI_API_KEY),
]:
    if not value:
        raise RuntimeError(f"{name} is missing in aibotrc.py")

if not ALLOWED_USER_ID:
    raise RuntimeError("ALLOWED_USER_ID is missing or invalid in aibotrc.py")

client = AsyncOpenAI(api_key=OPENAI_API_KEY)

# ── Types ─────────────────────────────────────────────────────
Message = Dict[str, str]
MemoryKey = Tuple[int, int]

# ── State ─────────────────────────────────────────────────────
CHAT_MEMORY: Dict[MemoryKey, Deque[Message]] = defaultdict(
    lambda: deque(maxlen=MAX_MEMORY)
)
LAST_REQUEST: Dict[MemoryKey, float] = {}
IMAGE_REQUESTS_MINUTE: Dict[MemoryKey, Deque[float]] = defaultdict(deque)
IMAGE_REQUESTS_DAY: Dict[MemoryKey, Deque[float]] = defaultdict(deque)

SYSTEM_PROMPT: Message = {
    "role": "system",
    "content": (
        "You are a helpful Telegram assistant. "
        "Be concise, accurate, and practical. "
        "If the user asks for code, provide complete working examples."
    ),
}

PROMPT_PRESETS: Dict[str, str] = {
    "angel": (
        "hyper realistic angelic portrait, white-gold armor, luminous wings, "
        "celestial atmosphere, ultra-detailed face, cinematic lighting, 4k realism"
    ),
    "zaphkiel": (
        "hyper realistic angelic AI avatar named Zaphkiel, white-gold armor, "
        "blue eyes, luminous halo, divine futuristic aesthetic, ultra detailed, cinematic lighting, 4k"
    ),
    "icon": (
        "clean minimalist icon, centered subject, simple background, crisp edges, "
        "high clarity, polished digital design"
    ),
    "wallpaper": (
        "epic cinematic wallpaper, ultra detailed, dramatic lighting, rich atmosphere, "
        "wide composition, 4k realism"
    ),
    "portrait": (
        "hyper realistic portrait, ultra detailed skin, realistic eyes, cinematic lighting, "
        "high contrast, professional photography"
    ),
    "darkfantasy": (
        "dark fantasy, cinematic lighting, ultra detailed, moody atmosphere, "
        "dramatic composition, high realism"
    ),
}

# ── Helpers ───────────────────────────────────────────────────
def is_allowed_user(update: Update) -> bool:
    user = update.effective_user
    return bool(user and user.id == ALLOWED_USER_ID)

def memory_key(update: Update) -> MemoryKey:
    return (update.effective_chat.id, update.effective_user.id)

def is_rate_limited(key: MemoryKey) -> bool:
    return (time.monotonic() - LAST_REQUEST.get(key, 0)) < RATE_LIMIT_SECONDS

def build_messages(key: MemoryKey, user_text: str) -> List[Message]:
    return [SYSTEM_PROMPT, *CHAT_MEMORY[key], {"role": "user", "content": user_text}]

def remember_exchange(key: MemoryKey, user_text: str, reply_text: str) -> None:
    CHAT_MEMORY[key].append({"role": "user", "content": user_text})
    CHAT_MEMORY[key].append({"role": "assistant", "content": reply_text})
    LAST_REQUEST[key] = time.monotonic()

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

def slugify_filename(text: str, max_length: int = 60) -> str:
    text = text.lower().strip()
    text = re.sub(r"[^a-z0-9\s_-]", "", text)
    text = re.sub(r"[\s_-]+", "-", text)
    text = text.strip("-")
    if not text:
        text = "image"
    return text[:max_length].rstrip("-")

def make_image_filename(prompt: str) -> str:
    stamp = datetime.now().strftime("%Y-%m-%d_%H-%M-%S")
    slug = slugify_filename(prompt)
    return f"{slug}_{stamp}.png"

def prune_old_requests(requests: Deque[float], window_seconds: int) -> None:
    cutoff = time.time() - window_seconds
    while requests and requests[0] < cutoff:
        requests.popleft()

def check_image_limits(key: MemoryKey) -> str | None:
    minute_q = IMAGE_REQUESTS_MINUTE[key]
    day_q = IMAGE_REQUESTS_DAY[key]

    prune_old_requests(minute_q, 60)
    prune_old_requests(day_q, 86400)

    if len(minute_q) >= MAX_IMAGES_PER_MINUTE:
        return f"Image limit reached: max {MAX_IMAGES_PER_MINUTE} per minute."

    if len(day_q) >= MAX_IMAGES_PER_DAY:
        return f"Image limit reached: max {MAX_IMAGES_PER_DAY} per day."

    return None

def record_image_request(key: MemoryKey) -> None:
    now = time.time()
    IMAGE_REQUESTS_MINUTE[key].append(now)
    IMAGE_REQUESTS_DAY[key].append(now)
    LAST_REQUEST[key] = time.monotonic()

async def keep_typing(update: Update, stop_event: asyncio.Event) -> None:
    while not stop_event.is_set():
        if update.effective_chat:
            await update.effective_chat.send_action(ChatAction.TYPING)
        await asyncio.sleep(4)

async def send_long_message(
    update: Update, text: str, chunk_size: int = 3500
) -> None:
    if not update.message:
        return

    for i in range(0, len(text), chunk_size):
        await update.message.reply_text(text[i:i + chunk_size])

async def download_photo_data_url_from_message(message: Any) -> str:
    if not message or not message.photo:
        raise RuntimeError("No photo found in message.")

    telegram_file = await message.photo[-1].get_file()
    buffer = BytesIO()
    await telegram_file.download_to_memory(out=buffer)

    image_bytes = buffer.getvalue()
    image_b64 = base64.b64encode(image_bytes).decode("utf-8")
    return f"data:image/jpeg;base64,{image_b64}"

async def ask_text_model(key: MemoryKey, user_text: str) -> str:
    messages = build_messages(key, user_text)

    stream = await client.chat.completions.create(
        model=OPENAI_MODEL,
        messages=messages,
        stream=True,
    )

    chunks: List[str] = []
    async for chunk in stream:
        delta = chunk.choices[0].delta.content
        if delta:
            chunks.append(delta)

    reply = "".join(chunks).strip() or "Empty response from model."
    remember_exchange(key, user_text, reply)
    return reply

async def ask_vision_model(
    key: MemoryKey, user_text: str, image_data_url: str
) -> str:
    response = await client.chat.completions.create(
        model=VISION_MODEL,
        messages=[
            {
                "role": "user",
                "content": [
                    {"type": "text", "text": user_text},
                    {"type": "image_url", "image_url": {"url": image_data_url}},
                ],
            }
        ],
    )

    reply = (response.choices[0].message.content or "").strip() or "Empty response from model."
    remember_exchange(key, f"[vision] {user_text}", reply)
    return reply

def parse_img_flags(raw_text: str) -> Tuple[str, str, str]:
    prompt = raw_text.strip()
    size = IMAGE_SIZE
    quality = IMAGE_QUALITY

    flag_map = {
        "--square": "1024x1024",
        "--portrait": "1024x1536",
        "--landscape": "1536x1024",
        "--hd": "high",
        "--high": "high",
        "--medium": "medium",
        "--low": "low",
        "--auto": "auto",
    }

    found_flags: List[str] = []
    for flag, value in flag_map.items():
        if flag in prompt:
            found_flags.append(flag)
            if "x" in value:
                size = value
            else:
                quality = value

    for flag in found_flags:
        prompt = prompt.replace(flag, "")

    prompt = re.sub(r"\s+", " ", prompt).strip()
    return prompt, size, quality

def build_preset_prompt(preset_name: str, extra_text: str) -> str:
    base = PROMPT_PRESETS[preset_name]
    extra_text = extra_text.strip()
    if extra_text:
        return f"{base}, {extra_text}"
    return base

async def generate_image(prompt: str, size: str, quality: str) -> bytes:
    result = await client.images.generate(
        model=IMAGE_MODEL,
        prompt=prompt,
        size=size,
        quality=quality,
    )

    if not result.data:
        raise RuntimeError("Image API returned no data.")

    image_b64 = getattr(result.data[0], "b64_json", None)
    if not image_b64:
        raise RuntimeError("Image API returned no image payload.")

    return base64.b64decode(image_b64)

def save_image_locally(image_bytes: bytes, filename: str) -> Path:
    out_path = IMAGE_SAVE_DIR / filename
    out_path.write_bytes(image_bytes)
    return out_path

def extract_vision_prompt(context: ContextTypes.DEFAULT_TYPE) -> str:
    if context.args:
        return " ".join(context.args).strip()
    return "Describe this image clearly and usefully."

def build_img_caption(
    prompt: str,
    size: str,
    quality: str,
    filename: str,
) -> str:
    prompt_short = prompt[:700]
    return (
        f"Prompt: {prompt_short}\n"
        f"Size: {size} | Quality: {quality}\n"
        f"File: {filename}"
    )[:1024]

# ── Commands ──────────────────────────────────────────────────
async def ai_cmd(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    if not is_allowed_user(update) or not update.message:
        return

    if not context.args:
        await update.message.reply_text("Usage: /ai <your message>")
        return

    user_text = " ".join(context.args).strip()
    if not user_text:
        await update.message.reply_text("Usage: /ai <your message>")
        return

    if len(user_text) > MAX_INPUT_CHARS:
        await update.message.reply_text(
            f"Message too long (max {MAX_INPUT_CHARS} characters)."
        )
        return

    key = memory_key(update)
    if is_rate_limited(key):
        await update.message.reply_text(
            f"Please wait {RATE_LIMIT_SECONDS}s between requests."
        )
        return

    stop_typing = asyncio.Event()
    typing_task = asyncio.create_task(keep_typing(update, stop_typing))

    try:
        logger.info("AI request | chat=%s user=%s", key[0], key[1])
        reply = await ask_text_model(key, user_text)
        await send_long_message(update, reply)
    except Exception as exc:
        logger.exception("AI command failed | prompt=%r", user_text)
        await update.message.reply_text(format_api_error(exc))
    finally:
        stop_typing.set()
        typing_task.cancel()

async def img_cmd(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    if not is_allowed_user(update) or not update.message:
        return

    if not context.args:
        await update.message.reply_text(
            "Usage: /img <prompt> [--square|--portrait|--landscape] [--hd|--high|--medium|--low|--auto]"
        )
        return

    raw_prompt = " ".join(context.args).strip()
    if not raw_prompt:
        await update.message.reply_text(
            "Usage: /img <prompt> [--square|--portrait|--landscape] [--hd|--high|--medium|--low|--auto]"
        )
        return

    prompt, size, quality = parse_img_flags(raw_prompt)

    if not prompt:
        await update.message.reply_text("Prompt cannot be empty.")
        return

    if len(prompt) > MAX_INPUT_CHARS:
        await update.message.reply_text(
            f"Prompt too long (max {MAX_INPUT_CHARS} characters)."
        )
        return

    key = memory_key(update)

    if is_rate_limited(key):
        await update.message.reply_text(
            f"Please wait {RATE_LIMIT_SECONDS}s between requests."
        )
        return

    limit_error = check_image_limits(key)
    if limit_error:
        await update.message.reply_text(limit_error)
        return

    stop_typing = asyncio.Event()
    typing_task = asyncio.create_task(keep_typing(update, stop_typing))

    try:
        logger.info(
            "IMG request | chat=%s user=%s | prompt=%r | size=%s | quality=%s",
            key[0], key[1], prompt, size, quality
        )

        image_bytes = await generate_image(prompt, size, quality)
        record_image_request(key)

        filename = make_image_filename(prompt)
        saved_path = save_image_locally(image_bytes, filename)

        image_stream = BytesIO(image_bytes)
        image_stream.name = filename
        image_stream.seek(0)

        await update.message.reply_photo(
            photo=image_stream,
            caption=build_img_caption(prompt, size, quality, filename),
            read_timeout=TELEGRAM_READ_TIMEOUT,
            write_timeout=TELEGRAM_WRITE_TIMEOUT,
            connect_timeout=TELEGRAM_CONNECT_TIMEOUT,
            pool_timeout=TELEGRAM_POOL_TIMEOUT,
        )

        logger.info(
            "IMG success | chat=%s user=%s | saved=%s",
            key[0], key[1], saved_path
        )

    except TimedOut:
        logger.warning("IMG send timed out | prompt=%r", prompt)
        await update.message.reply_text(
            "Image was generated and saved locally, but Telegram timed out while sending it. "
            "It may still have been delivered."
        )

    except Exception as exc:
        logger.exception("IMG command failed | prompt=%r", prompt)
        await update.message.reply_text(format_api_error(exc))

    finally:
        stop_typing.set()
        typing_task.cancel()

async def imgz_cmd(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    if not is_allowed_user(update) or not update.message:
        return

    if not context.args:
        presets = ", ".join(sorted(PROMPT_PRESETS.keys()))
        await update.message.reply_text(
            f"Usage: /imgz <preset> [extra words]\nPresets: {presets}"
        )
        return

    preset_name = context.args[0].lower().strip()
    extra = " ".join(context.args[1:]).strip()

    if preset_name not in PROMPT_PRESETS:
        presets = ", ".join(sorted(PROMPT_PRESETS.keys()))
        await update.message.reply_text(
            f"Unknown preset: {preset_name}\nAvailable: {presets}"
        )
        return

    built_prompt = build_preset_prompt(preset_name, extra)

    class DummyContext:
        def __init__(self, args: List[str]) -> None:
            self.args = args

    await img_cmd(update, DummyContext([built_prompt]))

async def presets_cmd(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    if not is_allowed_user(update) or not update.message:
        return

    lines = ["Image presets:"]
    for name in sorted(PROMPT_PRESETS.keys()):
        lines.append(f"- {name}")
    lines.append("")
    lines.append("Use: /imgz <preset> [extra words]")
    await update.message.reply_text("\n".join(lines))

async def vision_cmd(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    if not is_allowed_user(update) or not update.message:
        return

    target_message = update.message.reply_to_message
    if not target_message or not target_message.photo:
        await update.message.reply_text(
            "Reply to a photo with /vision <question>\n"
            "Example: /vision what is in this image?"
        )
        return

    user_text = extract_vision_prompt(context)
    if len(user_text) > MAX_INPUT_CHARS:
        await update.message.reply_text(
            f"Question too long (max {MAX_INPUT_CHARS} characters)."
        )
        return

    key = memory_key(update)
    if is_rate_limited(key):
        await update.message.reply_text(
            f"Please wait {RATE_LIMIT_SECONDS}s between requests."
        )
        return

    stop_typing = asyncio.Event()
    typing_task = asyncio.create_task(keep_typing(update, stop_typing))

    try:
        logger.info(
            "VISION request | chat=%s user=%s | prompt=%r",
            key[0],
            key[1],
            user_text,
        )
        image_data_url = await download_photo_data_url_from_message(target_message)
        reply = await ask_vision_model(key, user_text, image_data_url)
        await send_long_message(update, reply)
    except Exception as exc:
        logger.exception("VISION command failed | prompt=%r", user_text)
        await update.message.reply_text(format_api_error(exc))
    finally:
        stop_typing.set()
        typing_task.cancel()

async def photo_message_handler(
    update: Update, context: ContextTypes.DEFAULT_TYPE
) -> None:
    if not is_allowed_user(update) or not update.message or not update.message.photo:
        return

    caption = (update.message.caption or "").strip()
    if not caption.lower().startswith("/vision"):
        return

    prompt = caption[7:].strip() or "Describe this image clearly and usefully."

    if len(prompt) > MAX_INPUT_CHARS:
        await update.message.reply_text(
            f"Question too long (max {MAX_INPUT_CHARS} characters)."
        )
        return

    key = memory_key(update)
    if is_rate_limited(key):
        await update.message.reply_text(
            f"Please wait {RATE_LIMIT_SECONDS}s between requests."
        )
        return

    stop_typing = asyncio.Event()
    typing_task = asyncio.create_task(keep_typing(update, stop_typing))

    try:
        logger.info(
            "PHOTO VISION request | chat=%s user=%s | prompt=%r",
            key[0],
            key[1],
            prompt,
        )
        image_data_url = await download_photo_data_url_from_message(update.message)
        reply = await ask_vision_model(key, prompt, image_data_url)
        await send_long_message(update, reply)
    except Exception as exc:
        logger.exception("Photo vision handler failed | prompt=%r", prompt)
        await update.message.reply_text(format_api_error(exc))
    finally:
        stop_typing.set()
        typing_task.cancel()

async def start_cmd(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    if not is_allowed_user(update) or not update.message:
        return

    await update.message.reply_text(
        "AI Bot Ready.\n\n"
        "Commands:\n"
        "/ai <message>       — ask AI\n"
        "/img <prompt>       — generate image\n"
        "/imgz <preset> ...  — generate image from preset\n"
        "/presets            — list image presets\n"
        "/vision <question>  — reply to a photo with this\n"
        "/status             — bot info\n"
        "/reset              — clear memory\n"
        "/help               — show this message"
    )

async def help_cmd(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    if not is_allowed_user(update) or not update.message:
        return

    await update.message.reply_text(
        "Command usage:\n"
        "/ai <message>       — ask AI\n"
        "/img <prompt>       — generate image\n"
        "/imgz <preset> ...  — use saved prompt style\n"
        "/presets            — show presets\n"
        "/vision <question>  — reply to a photo with this command\n"
        "Send a photo with caption '/vision describe this' also works\n"
        "\n"
        "Image flags:\n"
        "--square | --portrait | --landscape\n"
        "--hd | --high | --medium | --low | --auto\n"
        "\n"
        "Examples:\n"
        "/img white-gold angel warrior --portrait --hd\n"
        "/imgz zaphkiel holding a glowing sword\n"
    )

async def status_cmd(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    if not is_allowed_user(update) or not update.message:
        return

    key = memory_key(update)
    mem_used = len(CHAT_MEMORY.get(key, []))

    minute_q = IMAGE_REQUESTS_MINUTE[key]
    day_q = IMAGE_REQUESTS_DAY[key]
    prune_old_requests(minute_q, 60)
    prune_old_requests(day_q, 86400)

    await update.message.reply_text(
        f"AI bot online\n"
        f"Text model:     {OPENAI_MODEL}\n"
        f"Vision model:   {VISION_MODEL}\n"
        f"Image model:    {IMAGE_MODEL}\n"
        f"Image size:     {IMAGE_SIZE}\n"
        f"Image quality:  {IMAGE_QUALITY}\n"
        f"Memory:         {mem_used}/{MAX_MEMORY} messages\n"
        f"Max input:      {MAX_INPUT_CHARS} chars\n"
        f"Images/minute:  {len(minute_q)}/{MAX_IMAGES_PER_MINUTE}\n"
        f"Images/day:     {len(day_q)}/{MAX_IMAGES_PER_DAY}\n"
        f"Image folder:   {IMAGE_SAVE_DIR}\n"
        f"Log file:       {LOG_FILE}"
    )

async def reset_cmd(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    if not is_allowed_user(update) or not update.message:
        return

    key = memory_key(update)
    CHAT_MEMORY.pop(key, None)
    LAST_REQUEST.pop(key, None)
    await update.message.reply_text("Memory cleared.")

# ── Main ─────────────────────────────────────────────────────
def main() -> None:
    app = (
        Application.builder()
        .token(TELEGRAM_BOT_TOKEN)
        .read_timeout(TELEGRAM_READ_TIMEOUT)
        .write_timeout(TELEGRAM_WRITE_TIMEOUT)
        .connect_timeout(TELEGRAM_CONNECT_TIMEOUT)
        .pool_timeout(TELEGRAM_POOL_TIMEOUT)
        .build()
    )

    app.add_handler(CommandHandler("start", start_cmd))
    app.add_handler(CommandHandler("help", help_cmd))
    app.add_handler(CommandHandler("status", status_cmd))
    app.add_handler(CommandHandler("reset", reset_cmd))
    app.add_handler(CommandHandler("ai", ai_cmd))
    app.add_handler(CommandHandler("img", img_cmd))
    app.add_handler(CommandHandler("imgz", imgz_cmd))
    app.add_handler(CommandHandler("presets", presets_cmd))
    app.add_handler(CommandHandler("vision", vision_cmd))
    app.add_handler(
        MessageHandler(filters.PHOTO & filters.Caption(True), photo_message_handler)
    )

    logger.info(
        "AI Bot starting | text=%s | vision=%s | image=%s | image_dir=%s | log=%s",
        OPENAI_MODEL,
        VISION_MODEL,
        IMAGE_MODEL,
        IMAGE_SAVE_DIR,
        LOG_FILE,
    )
    app.run_polling(drop_pending_updates=True)

if __name__ == "__main__":
    main()