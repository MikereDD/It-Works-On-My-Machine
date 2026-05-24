#--------------------------------------------
# file:     ytbot.py
# author:   Mike Redd
# version:  6.7
# created:  2026-04-18
# updated:  2026-05-18
# desc:     Queue-based Telegram media bot
#           with interactive UI, weather,
#           forecast, routing, archive send,
#           watch folder, CLI mode,
#           and clip support
#--------------------------------------------

import argparse
import importlib
import asyncio
from datetime import datetime
import json
import html
import logging
import os
import re
import shutil
import subprocess
import sys
import time
import uuid
from collections import Counter
from pathlib import Path
from urllib.parse import urlencode, urlparse
from urllib.request import urlopen

# ── Branding ─────────────────────────────────────────────────

BOT_NAME = "Raziel"
BOT_VERSION = "6.8"

import yt_dlp
from telegram import (
    InlineKeyboardButton,
    InlineKeyboardMarkup,
    InlineQueryResultArticle,
    InputTextMessageContent,
    Update,
)
from telegram.constants import ParseMode
from telegram.ext import (
    ApplicationBuilder,
    CallbackQueryHandler,
    ChatMemberHandler,
    CommandHandler,
    ContextTypes,
    InlineQueryHandler,
    MessageHandler,
    filters,
)
from telegram.request import HTTPXRequest

# ── Private Config ──────────────────────────────────────────────────────────────
APP_DIR = Path(__file__).resolve().parent
ROOT_DIR = APP_DIR.parent

CONFIG_DIR = ROOT_DIR / "config"
CONFIG_FILE = CONFIG_DIR / "ytbotrc.py"

if not CONFIG_FILE.exists():
    raise RuntimeError(f"Missing config file: {CONFIG_FILE}")

sys.path.insert(0, str(CONFIG_DIR))

try:
    import ytbotrc
except Exception as e:
    raise RuntimeError(f"Failed to load config file {CONFIG_FILE}: {e}")

BOT_TOKEN = getattr(ytbotrc, "BOT_TOKEN", "")
OWNER_ID = getattr(ytbotrc, "ALLOWED_USER_ID", 0)

_configured_base = getattr(ytbotrc, "BASE_DIR", ROOT_DIR)
BASE_DIR = Path(os.path.expandvars(os.path.expanduser(str(_configured_base)))).resolve()

ADMIN_USERS = set(getattr(ytbotrc, "ADMIN_USERS", [OWNER_ID]) or [OWNER_ID])
ALLOWED_USERS = set(getattr(ytbotrc, "ALLOWED_USERS", [OWNER_ID]) or [OWNER_ID])
ALLOW_ALL_USERS = getattr(ytbotrc, "ALLOW_ALL_USERS", False)
AUTO_WATCH_DISABLED_CHAT_IDS = set(getattr(ytbotrc, "AUTO_WATCH_DISABLED_CHAT_IDS", []))

DOWNLOAD_TIMEOUT = getattr(ytbotrc, "DOWNLOAD_TIMEOUT", 3600)
TELEGRAM_UPLOAD_TIMEOUT = getattr(ytbotrc, "TELEGRAM_UPLOAD_TIMEOUT", 3600)
DEBUG_MODE = getattr(ytbotrc, "DEBUG_MODE", False)
DEDUP_ENABLED = getattr(ytbotrc, "DEDUP_ENABLED", True)
DEDUP_TTL_HOURS = getattr(ytbotrc, "DEDUP_TTL_HOURS", 24)
MAX_VIDEO_HEIGHT = getattr(ytbotrc, "MAX_VIDEO_HEIGHT", 1080)
PREFER_MP4 = getattr(ytbotrc, "PREFER_MP4", True)

# Caption/context behavior:
# expandable = clean media caption + full source context in expandable reply
# caption    = legacy v6.0-style source text inside media caption
# minimal    = title/uploader/platform/duration/source only
CAPTION_METADATA_MODE = getattr(ytbotrc, "CAPTION_METADATA_MODE", "expandable")
CAPTION_CONTEXT_MAX_CHARS = int(getattr(ytbotrc, "CAPTION_CONTEXT_MAX_CHARS", 3500))
CAPTION_SKIP_LOW_VALUE_CONTEXT = getattr(ytbotrc, "CAPTION_SKIP_LOW_VALUE_CONTEXT", True)
CAPTION_CONTEXT_MIN_MEANINGFUL_CHARS = int(getattr(ytbotrc, "CAPTION_CONTEXT_MIN_MEANINGFUL_CHARS", 60))

FORECAST_COLLAPSE_DETAILS = getattr(ytbotrc, "FORECAST_COLLAPSE_DETAILS", True)
FORECAST_VISIBLE_DAYS = int(getattr(ytbotrc, "FORECAST_VISIBLE_DAYS", 1))
NOISE_MESSAGE_DELETE_SECONDS = int(getattr(ytbotrc, "NOISE_MESSAGE_DELETE_SECONDS", 12))

# Validation policy:
# True  = only allow configured ENABLED_VIDEO_PLATFORMS / EXTRA_VIDEO_DOMAINS
# False = allow any URL and let yt-dlp decide if it can extract it
STRICT_PLATFORM_VALIDATION = getattr(ytbotrc, "STRICT_PLATFORM_VALIDATION", False)
MEDIA_PREFLIGHT_ENABLED = getattr(ytbotrc, "MEDIA_PREFLIGHT_ENABLED", True)
MEDIA_PREFLIGHT_TIMEOUT = int(getattr(ytbotrc, "MEDIA_PREFLIGHT_TIMEOUT", 20))
MEDIA_PREFLIGHT_NOISE_DELETE_SECONDS = int(getattr(ytbotrc, "MEDIA_PREFLIGHT_NOISE_DELETE_SECONDS", 8))

# Local Telegram Bot API support (optional)
LOCAL_BOT_API_URL = getattr(ytbotrc, "LOCAL_BOT_API_URL", "")
LOCAL_BOT_API_FILE_URL = getattr(ytbotrc, "LOCAL_BOT_API_FILE_URL", "")

DEFAULT_VIDEO_HEIGHT = getattr(ytbotrc, "DEFAULT_VIDEO_HEIGHT", 720)
HD_VIDEO_HEIGHT = getattr(ytbotrc, "HD_VIDEO_HEIGHT", 1080)
VIDEO_PLATFORM_PRESETS = {
    "youtube": (
        "youtube.com",
        "youtu.be",
        "m.youtube.com",
        "music.youtube.com",
    ),
    "instagram": (
        "instagram.com",
    ),
    "reddit": (
        "reddit.com",
        "redd.it",
        "v.redd.it",
    ),
    "tiktok": (
        "tiktok.com",
        "vm.tiktok.com",
        "vt.tiktok.com",
    ),
    "twitter": (
        "x.com",
        "twitter.com",
    ),
    "facebook": (
        "facebook.com",
        "m.facebook.com",
        "www.facebook.com",
        "fb.watch",
    ),
    "bitchute": (
        "bitchute.com",
        "www.bitchute.com",
    ),
}

ENABLED_VIDEO_PLATFORMS = tuple(getattr(
    ytbotrc,
    "ENABLED_VIDEO_PLATFORMS",
    (
        "youtube",
        "instagram",
    ),
))

EXTRA_VIDEO_DOMAINS = tuple(getattr(ytbotrc, "EXTRA_VIDEO_DOMAINS", ()))

def build_supported_video_domains() -> tuple[str, ...]:
    domains: list[str] = []

    for platform in ENABLED_VIDEO_PLATFORMS:
        domains.extend(VIDEO_PLATFORM_PRESETS.get(str(platform).lower(), ()))

    domains.extend(EXTRA_VIDEO_DOMAINS)

    cleaned: list[str] = []
    seen = set()

    for domain in domains:
        d = str(domain).strip().lower()
        if not d:
            continue
        if d.startswith("www."):
            d = d[4:]
        if d not in seen:
            seen.add(d)
            cleaned.append(d)

    return tuple(cleaned)

SUPPORTED_VIDEO_DOMAINS = build_supported_video_domains()
ARCHIVE_CHAT_ID = getattr(ytbotrc, "ARCHIVE_CHAT_ID", None)
WATCH_FOLDER_ENABLED = getattr(ytbotrc, "WATCH_FOLDER_ENABLED", True)
WATCH_FOLDER_CHAT_ID = getattr(ytbotrc, "WATCH_FOLDER_CHAT_ID", None) or OWNER_ID

if not BOT_TOKEN:
    raise RuntimeError(
        f"BOT_TOKEN is missing in {CONFIG_FILE}. "
        "Copy your template/example config to the live config path and set a real token."
    )

if not OWNER_ID:
    raise RuntimeError(
        f"ALLOWED_USER_ID is missing in {CONFIG_FILE}. "
        "Set the Telegram user ID that owns/administers the bot."
    )

# ── Paths ───────────────────────────────────────────────────────────────────────
STATE_DIR = BASE_DIR / "state"
DOWNLOAD_DIR = BASE_DIR / "downloads"
LOG_DIR = BASE_DIR / "logs"
DONE_VIDEO_DIR = BASE_DIR / "done" / "video"
DONE_AUDIO_DIR = BASE_DIR / "done" / "audio"
FAILED_DIR = BASE_DIR / "done" / "failed"
WATCH_DIR = BASE_DIR / "watch"
COOKIES_DIR = BASE_DIR / "cookies"
YOUTUBE_COOKIES_FILE = COOKIES_DIR / "youtube_cookies.txt"
KNOWN_CHATS_FILE = BASE_DIR / "known_chats.json"
QUEUE_FILE = STATE_DIR / "queue.json"
HISTORY_FILE = STATE_DIR / "history.json"
FAILURES_FILE = STATE_DIR / "failures.json"
DEDUP_FILE = STATE_DIR / "dedup.json"
LOG_FILE = LOG_DIR / "ytbot.log"

for d in [
    STATE_DIR, DOWNLOAD_DIR, LOG_DIR, DONE_VIDEO_DIR,
    DONE_AUDIO_DIR, FAILED_DIR, WATCH_DIR, COOKIES_DIR
]:
    d.mkdir(parents=True, exist_ok=True)

# ── Limits ──────────────────────────────────────────────────────────────────────
DELETE_AFTER_SEND      = False
MAX_UPLOAD_BYTES       = 1900 * 1024 * 1024  # local Bot API safe ceiling (~1.9GB)
MIN_VALID_VIDEO_BYTES  = 100 * 1024
MIN_VALID_AUDIO_BYTES  = 100 * 1024
MAX_HISTORY_ENTRIES    = 500

# ── Globals ─────────────────────────────────────────────────────────────────────
URL_RE = re.compile(r"https?://\S+", re.IGNORECASE)
QUEUE: list[dict] = []
HISTORY: list[dict] = []
FAILURES: list[dict] = []
KNOWN_CHATS: dict = {}
DEDUP_CACHE: dict = {}
CURRENT_JOB: dict | None = None

STATE_LOCK = asyncio.Lock()
PENDING_UI: dict[str, dict] = {}

# ── Logging ─────────────────────────────────────────────────────────────────────
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s | %(levelname)s | %(name)s | %(message)s",
    handlers=[
        logging.FileHandler(LOG_FILE, encoding="utf-8"),
        logging.StreamHandler(sys.stdout),
    ],
)
log = logging.getLogger("ytbot")
log.setLevel(logging.INFO if DEBUG_MODE else logging.WARNING)


def reload_runtime_config() -> None:
    """
    Reload ytbotrc.py and refresh runtime-safe settings.

    This does not restart the Telegram app, active downloads, queue worker,
    or persisted state. It only refreshes values that are safe to update live.
    """
    global ytbotrc
    global ADMIN_USERS, ALLOWED_USERS, ALLOW_ALL_USERS, AUTO_WATCH_DISABLED_CHAT_IDS
    global DOWNLOAD_TIMEOUT, TELEGRAM_UPLOAD_TIMEOUT, DEBUG_MODE
    global DEDUP_ENABLED, DEDUP_TTL_HOURS, MAX_VIDEO_HEIGHT, PREFER_MP4
    global CAPTION_METADATA_MODE, CAPTION_CONTEXT_MAX_CHARS, CAPTION_SKIP_LOW_VALUE_CONTEXT, CAPTION_CONTEXT_MIN_MEANINGFUL_CHARS
    global FORECAST_COLLAPSE_DETAILS, FORECAST_VISIBLE_DAYS, NOISE_MESSAGE_DELETE_SECONDS
    global STRICT_PLATFORM_VALIDATION, MEDIA_PREFLIGHT_ENABLED, MEDIA_PREFLIGHT_TIMEOUT, MEDIA_PREFLIGHT_NOISE_DELETE_SECONDS
    global LOCAL_BOT_API_URL, LOCAL_BOT_API_FILE_URL
    global DEFAULT_VIDEO_HEIGHT, HD_VIDEO_HEIGHT
    global ENABLED_VIDEO_PLATFORMS, EXTRA_VIDEO_DOMAINS, SUPPORTED_VIDEO_DOMAINS
    global ARCHIVE_CHAT_ID, WATCH_FOLDER_ENABLED, WATCH_FOLDER_CHAT_ID

    importlib.invalidate_caches()
    ytbotrc = importlib.reload(ytbotrc)

    ADMIN_USERS = set(getattr(ytbotrc, "ADMIN_USERS", [OWNER_ID]) or [OWNER_ID])
    ALLOWED_USERS = set(getattr(ytbotrc, "ALLOWED_USERS", [OWNER_ID]) or [OWNER_ID])
    ALLOW_ALL_USERS = getattr(ytbotrc, "ALLOW_ALL_USERS", False)
    AUTO_WATCH_DISABLED_CHAT_IDS = set(getattr(ytbotrc, "AUTO_WATCH_DISABLED_CHAT_IDS", []))

    DOWNLOAD_TIMEOUT = getattr(ytbotrc, "DOWNLOAD_TIMEOUT", 3600)
    TELEGRAM_UPLOAD_TIMEOUT = getattr(ytbotrc, "TELEGRAM_UPLOAD_TIMEOUT", 3600)
    DEBUG_MODE = getattr(ytbotrc, "DEBUG_MODE", False)
    DEDUP_ENABLED = getattr(ytbotrc, "DEDUP_ENABLED", True)
    DEDUP_TTL_HOURS = getattr(ytbotrc, "DEDUP_TTL_HOURS", 24)
    MAX_VIDEO_HEIGHT = getattr(ytbotrc, "MAX_VIDEO_HEIGHT", 1080)
    PREFER_MP4 = getattr(ytbotrc, "PREFER_MP4", True)
    CAPTION_METADATA_MODE = getattr(ytbotrc, "CAPTION_METADATA_MODE", "expandable")
    CAPTION_CONTEXT_MAX_CHARS = int(getattr(ytbotrc, "CAPTION_CONTEXT_MAX_CHARS", 3500))
    CAPTION_SKIP_LOW_VALUE_CONTEXT = getattr(ytbotrc, "CAPTION_SKIP_LOW_VALUE_CONTEXT", True)
    CAPTION_CONTEXT_MIN_MEANINGFUL_CHARS = int(getattr(ytbotrc, "CAPTION_CONTEXT_MIN_MEANINGFUL_CHARS", 60))
    STRICT_PLATFORM_VALIDATION = getattr(ytbotrc, "STRICT_PLATFORM_VALIDATION", False)
    MEDIA_PREFLIGHT_ENABLED = getattr(ytbotrc, "MEDIA_PREFLIGHT_ENABLED", True)
    MEDIA_PREFLIGHT_TIMEOUT = int(getattr(ytbotrc, "MEDIA_PREFLIGHT_TIMEOUT", 20))
    MEDIA_PREFLIGHT_NOISE_DELETE_SECONDS = int(getattr(ytbotrc, "MEDIA_PREFLIGHT_NOISE_DELETE_SECONDS", 8))

    LOCAL_BOT_API_URL = getattr(ytbotrc, "LOCAL_BOT_API_URL", "")
    LOCAL_BOT_API_FILE_URL = getattr(ytbotrc, "LOCAL_BOT_API_FILE_URL", "")

    DEFAULT_VIDEO_HEIGHT = getattr(ytbotrc, "DEFAULT_VIDEO_HEIGHT", 720)
    HD_VIDEO_HEIGHT = getattr(ytbotrc, "HD_VIDEO_HEIGHT", 1080)

    ENABLED_VIDEO_PLATFORMS = tuple(getattr(
        ytbotrc,
        "ENABLED_VIDEO_PLATFORMS",
        (
            "youtube",
            "instagram",
        ),
    ))
    EXTRA_VIDEO_DOMAINS = tuple(getattr(ytbotrc, "EXTRA_VIDEO_DOMAINS", ()))
    SUPPORTED_VIDEO_DOMAINS = build_supported_video_domains()

    ARCHIVE_CHAT_ID = getattr(ytbotrc, "ARCHIVE_CHAT_ID", None)
    WATCH_FOLDER_ENABLED = getattr(ytbotrc, "WATCH_FOLDER_ENABLED", True)
    WATCH_FOLDER_CHAT_ID = getattr(ytbotrc, "WATCH_FOLDER_CHAT_ID", None) or OWNER_ID

    log.setLevel(logging.INFO if DEBUG_MODE else logging.WARNING)



# ── JSON persistence ────────────────────────────────────────────────────────────
def load_json(path: Path, default):
    if not path.exists():
        return default
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except Exception as e:
        log.warning("Failed to load %s: %s", path, e)
        return default

def save_json(path: Path, data) -> None:
    path.write_text(json.dumps(data, indent=2, ensure_ascii=False), encoding="utf-8")


# ── State init ──────────────────────────────────────────────────────────────────
QUEUE = load_json(QUEUE_FILE, [])
HISTORY = load_json(HISTORY_FILE, [])
FAILURES = load_json(FAILURES_FILE, [])
KNOWN_CHATS = load_json(KNOWN_CHATS_FILE, {})
DEDUP_CACHE = load_json(DEDUP_FILE, {})


# ── Helpers ─────────────────────────────────────────────────────────────────────
def is_admin(user_id: int) -> bool:
    return user_id in ADMIN_USERS or user_id == OWNER_ID

def can_use(user_id: int) -> bool:
    return ALLOW_ALL_USERS or user_id in ALLOWED_USERS or is_admin(user_id)

def can_use_context(user_id: int, chat_id: int, chat_type: str) -> bool:
    """
    Group auto-watch behavior:
    - Any group/supergroup the bot is in can trigger downloads.
    - Private chat remains owner-only.
    - Other chat types are ignored.
    """
    if chat_type in ("group", "supergroup"):
        return True

    if chat_type == "private":
        return user_id == OWNER_ID

    return False


def auto_watch_disabled_for_chat(chat) -> bool:
    """
    Return True when passive link ingestion is disabled for this chat.

    This only applies to automatic pasted/shared/forwarded link handling.
    Explicit commands still work:
    /dl, /hd, /full, /audio, /clip, /ui
    /rdl, /rhd, /rfull, /raudio, /rui
    """
    if not chat:
        return False

    if getattr(chat, "type", None) not in ("group", "supergroup"):
        return False

    return int(chat.id) in AUTO_WATCH_DISABLED_CHAT_IDS


def message_has_native_telegram_media(message) -> bool:
    """
    Return True when a message already contains Telegram-native media.

    Passive auto-watch should ignore source links inside captions on these
    messages because the user already shared/uploaded media into the chat.

    Explicit commands still work separately.
    """
    if not message:
        return False

    media_attrs = (
        "video",
        "animation",
        "document",
        "audio",
        "voice",
        "video_note",
    )

    return any(bool(getattr(message, attr, None)) for attr in media_attrs)

def is_private_chat(update: Update) -> bool:
    return bool(update.effective_chat and update.effective_chat.type == "private")

def format_size(num_bytes: int) -> str:
    size = float(num_bytes)
    for unit in ("B", "KB", "MB", "GB", "TB"):
        if size < 1024:
            return f"{size:.2f} {unit}"
        size /= 1024
    return f"{num_bytes} B"

def format_duration(seconds: int | float | None) -> str:
    if seconds is None:
        return "Unknown"
    seconds = int(seconds)
    h, rem = divmod(seconds, 3600)
    m, s = divmod(rem, 60)
    if h:
        return f"{h}h {m}m {s}s"
    if m:
        return f"{m}m {s}s"
    return f"{s}s"

def shorten_url(url: str, max_len: int = 50) -> str:
    return url if len(url) <= max_len else url[:max_len - 3] + "..."


def clean_metadata_text(value: str | None, max_len: int = 2600) -> str:
    """
    Clean source post text / description for Telegram captions.
    """
    if not value:
        return ""

    text_value = str(value).replace("\r\n", "\n").replace("\r", "\n")
    text_value = re.sub(r"\n{3,}", "\n\n", text_value)
    text_value = re.sub(r"[ \t]+", " ", text_value)
    text_value = text_value.strip()

    if not text_value:
        return ""

    if len(text_value) <= max_len:
        return text_value

    trimmed = text_value[: max_len - 1].rstrip()
    last_break = max(
        trimmed.rfind("\n\n"),
        trimmed.rfind(". "),
        trimmed.rfind("! "),
        trimmed.rfind("? "),
    )

    if last_break > max_len * 0.55:
        trimmed = trimmed[: last_break + 1].rstrip()

    return trimmed + "…"


def first_nonempty(*values) -> str:
    for value in values:
        if value is None:
            continue
        text_value = str(value).strip()
        if text_value:
            return text_value
    return ""


PLATFORM_ICONS = {
    "YouTube": "▶",
    "X / Twitter": "𝕏",
    "Instagram": "◎",
    "TikTok": "♫",
    "Facebook": "ⓕ",
    "Reddit": "⬡",
    "BitChute": "◉",
}


def platform_label(url: str) -> str:
    host = get_domain(url)
    if "youtube" in host or "youtu.be" in host:
        return "YouTube"
    if "x.com" in host or "twitter.com" in host:
        return "X / Twitter"
    if "instagram.com" in host:
        return "Instagram"
    if "facebook.com" in host or "fb.watch" in host:
        return "Facebook"
    if "tiktok.com" in host:
        return "TikTok"
    if "reddit.com" in host or "redd.it" in host:
        return "Reddit"
    if "bitchute.com" in host:
        return "BitChute"
    return host or "Source"


def platform_display(url: str) -> str:
    label = platform_label(url)
    icon = PLATFORM_ICONS.get(label, "◇")

    # Avoid ugly "X X / Twitter" rendering when Telegram fonts display
    # the X icon as a plain X.
    display_names = {
        "X / Twitter": "Twitter",
    }

    display_name = display_names.get(label, label)
    return f"{icon} {display_name}"


def get_source_context(meta: dict) -> str:
    """
    Return the best available source context from yt-dlp metadata.

    v6.2 preserves source context separately from the media caption because
    Telegram expandable blockquotes are reliable in normal messages, but not
    reliable inside video/audio/document captions across clients.
    """
    title = clean_metadata_text(meta.get("title"), max_len=180) or ""
    about = clean_metadata_text(
        first_nonempty(
            meta.get("post_text"),
            meta.get("description"),
            meta.get("fulltitle"),
            meta.get("alt_title"),
        ),
        max_len=max(CAPTION_CONTEXT_MAX_CHARS, 500),
    )

    if about and title and about.strip().lower() == title.strip().lower():
        return ""

    return about


def build_upload_caption(
    meta: dict,
    mode: str,
    clip_start: str | None = None,
    clip_end: str | None = None,
) -> str:
    """
    Build the visible Telegram media caption.

    v6.2 keeps media uploads clean and stable:
    title -> uploader -> platform -> duration -> clip range -> source URL.

    Source context is sent as a separate expandable normal message when enabled,
    avoiding unreliable caption parsing and malformed media caption entities.
    """
    title = clean_metadata_text(meta.get("title"), max_len=180) or "Untitled"
    uploader = clean_metadata_text(meta.get("uploader"), max_len=120) or "Unknown uploader"
    url = meta.get("webpage_url") or meta.get("original_url") or ""

    footer_lines = [
        f"👤 {uploader}",
        f"{platform_display(url)}",
    ]

    duration = meta.get("duration")
    if duration:
        footer_lines.append(f"⏱️ {format_duration(duration)}")

    if mode == "clip" and clip_start and clip_end:
        footer_lines.append(format_clip_range(clip_start, clip_end))

    if url:
        footer_lines.append(f"🔗 {url}")

    return (f"🎞️ {title}\n\n" + "\n".join(footer_lines))[:1000]


LOW_VALUE_CONTEXT_PREFIXES = (
    "watch more",
    "watch full",
    "full video",
    "full episode",
    "listen here",
    "read more",
    "more here",
    "subscribe",
    "like and subscribe",
    "follow me",
    "follow us",
    "check out",
    "sign up",
    "sign-up",
    "join our",
    "join my",
    "catch my livestream",
    "for merch",
    "merch",
    "tour &",
    "tour and",
    "premium content",
    "sponsor",
    "new sponsor",
    "promo code",
    "use code",
    "affiliate",
    "patreon",
    "discord",
    "telegram",
    "instagram",
    "tiktok",
    "rumble",
    "youtube",
    "x ▶",
    "x:",
    "twitter",
)

LOW_VALUE_CONTEXT_DOMAINS = (
    "youtube.com/",
    "youtu.be/",
    "t.me/",
    "telegram.me/",
    "instagram.com/",
    "twitter.com/",
    "x.com/",
    "tiktok.com/",
    "rumble.com/",
    "patreon.com/",
    "discord.gg/",
    "discord.com/",
    "buymeacoffee.com/",
    "locals.com/",
    "substack.com/",
    "linktr.ee/",
)

def strip_context_line_noise(context: str, source_url: str = "") -> str:
    """
    Remove obvious creator-infrastructure lines from source context.

    This is intentionally conservative. It targets link dumps, sponsor/promo
    boilerplate, merch/social funnels, and event-list style lines while keeping
    actual post commentary when present.
    """
    if not context:
        return ""

    source_url_norm = (source_url or "").strip().lower()
    kept: list[str] = []

    for raw_line in context.splitlines():
        line = raw_line.strip()
        if not line:
            if kept and kept[-1] != "":
                kept.append("")
            continue

        lowered = line.lower()
        compact = re.sub(r"\s+", " ", lowered)

        # Drop exact/near source URL repeats and pure links.
        if source_url_norm and lowered == source_url_norm:
            continue
        if re.fullmatch(r"https?://\S+", line, flags=re.IGNORECASE):
            continue

        # Drop obvious promo/social/funnel prefix lines.
        if any(compact.startswith(prefix) for prefix in LOW_VALUE_CONTEXT_PREFIXES):
            continue

        # Drop lines that are mostly social/platform link dumps.
        if any(domain in lowered for domain in LOW_VALUE_CONTEXT_DOMAINS):
            # Keep a line with a URL only if it also has enough non-URL words.
            without_urls = re.sub(r"https?://\S+", "", line).strip()
            word_count = len(re.findall(r"[A-Za-z]{3,}", without_urls))
            if word_count < 8:
                continue

        # Drop compact event schedule lines like "Tampa, FL | June 13".
        if re.search(r"\b[A-Z][a-z]+,\s*[A-Z]{2}\s*\|\s*(Jan|Feb|Mar|Apr|May|Jun|June|Jul|July|Aug|Sep|Sept|Oct|Nov|Dec)", line):
            continue

        # Drop timestamp/chapter lines.
        if re.match(r"^\d{1,2}:\d{2}(?::\d{2})?\b", line):
            continue

        kept.append(raw_line.rstrip())

    cleaned = "\n".join(kept)
    cleaned = re.sub(r"\n{3,}", "\n\n", cleaned).strip()
    return cleaned


def is_meaningful_source_context(context: str, title: str = "", source_url: str = "") -> bool:
    """
    Decide whether source context is worth sending as an expandable message.

    v6.3 avoids noisy expansions like:
    - "Watch more here: <link>"
    - pure social link dumps
    - sponsor/promo blocks
    - tour-date lists
    - context that duplicates the title
    """
    if not context:
        return False

    title_norm = (title or "").strip().lower()
    context_norm = context.strip().lower()

    if title_norm and context_norm == title_norm:
        return False

    cleaned = strip_context_line_noise(context, source_url=source_url)
    if not cleaned:
        return False

    # Count meaningful words after stripping URLs and punctuation-heavy noise.
    no_urls = re.sub(r"https?://\S+", "", cleaned)
    words = re.findall(r"[A-Za-z][A-Za-z'’-]{2,}", no_urls)
    unique_words = {w.lower() for w in words}

    min_chars = max(int(CAPTION_CONTEXT_MIN_MEANINGFUL_CHARS), 20)
    if len(no_urls.strip()) < min_chars:
        return False

    if len(unique_words) < 6:
        return False

    # If the cleaned content is still mostly links/symbols, skip it.
    alnum_chars = sum(ch.isalnum() for ch in no_urls)
    total_chars = max(len(no_urls), 1)
    if alnum_chars / total_chars < 0.35:
        return False

    return True


def build_expandable_context_message(meta: dict) -> str | None:
    """
    Build a separate expandable source-context message.

    v6.3 only sends this when the context adds meaningful information beyond
    the media card. Low-value promo/social/link noise is skipped.
    """
    mode_name = str(CAPTION_METADATA_MODE or "expandable").strip().lower()
    if mode_name != "expandable":
        return None

    about = get_source_context(meta)
    if not about:
        return None

    title = clean_metadata_text(meta.get("title"), max_len=180) or "Source Context"
    url = meta.get("webpage_url") or meta.get("original_url") or ""

    if CAPTION_SKIP_LOW_VALUE_CONTEXT and not is_meaningful_source_context(about, title=title, source_url=url):
        return None

    about = strip_context_line_noise(about, source_url=url) if CAPTION_SKIP_LOW_VALUE_CONTEXT else about
    about = clean_metadata_text(about, max_len=CAPTION_CONTEXT_MAX_CHARS)

    if not about:
        return None

    safe_title = html.escape(title)
    safe_about = html.escape(about)

    return (
        f"📖 <b>Source Context</b> — {safe_title}\n\n"
        f"<blockquote expandable>{safe_about}</blockquote>"
    )


def make_progress_bar(percent: float | None, width: int = 12) -> str:
    if percent is None:
        return "░" * width
    percent = max(0.0, min(100.0, float(percent)))
    filled = int(round((percent / 100.0) * width))
    return "█" * filled + "░" * (width - filled)

def format_eta(seconds: int | float | None) -> str:
    if seconds is None:
        return "unknown"
    try:
        seconds = int(seconds)
    except Exception:
        return "unknown"
    h, rem = divmod(seconds, 3600)
    m, s = divmod(rem, 60)
    return f"{h:02}:{m:02}:{s:02}" if h else f"{m:02}:{s:02}"

def percent_from_progress(progress: dict) -> float | None:
    downloaded = progress.get("downloaded_bytes") or 0
    total = progress.get("total_bytes") or progress.get("total_bytes_estimate")
    if not total:
        return None
    try:
        return (float(downloaded) / float(total)) * 100.0
    except Exception:
        return None

def format_progress_status(title: str, uploader: str, mode: str, quality: str, progress: dict) -> str:
    percent = percent_from_progress(progress)
    bar = make_progress_bar(percent)
    pct = f"{percent:.1f}%" if percent is not None else "working"
    downloaded = progress.get("downloaded_bytes") or 0
    total = progress.get("total_bytes") or progress.get("total_bytes_estimate") or 0
    speed = progress.get("speed")
    eta = progress.get("eta")
    phase = "✅ Download complete" if progress.get("status") == "finished" else f"⬇️ Downloading {mode} ({get_quality_label(quality)})…"

    lines = [f"🎞️ {title}", f"👤 {uploader}", "", phase, f"{bar} {pct}"]

    if total:
        lines.append(f"📦 {format_size(int(downloaded))} / {format_size(int(total))}")
    elif downloaded:
        lines.append(f"📦 {format_size(int(downloaded))}")

    if speed:
        try:
            lines.append(f"⚡ {format_size(int(speed))}/s")
        except Exception:
            pass

    if eta is not None:
        lines.append(f"⏱️ ETA: {format_eta(eta)}")

    return "\n".join(lines)

def make_download_progress_hook(app, chat_id: int, message_id: int, title: str, uploader: str, mode: str, quality: str):
    loop = asyncio.get_running_loop()
    state = {"last_edit": 0.0, "last_text": ""}

    async def edit_status(text: str) -> None:
        try:
            await app.bot.edit_message_text(chat_id=chat_id, message_id=message_id, text=text[:3900])
        except Exception as e:
            if DEBUG_MODE:
                log.debug("Progress edit skipped: %s", e)

    def hook(progress: dict) -> None:
        now = time.time()
        if progress.get("status") != "finished" and now - state["last_edit"] < 3.0:
            return

        text = format_progress_status(title, uploader, mode, quality, progress)
        if text == state["last_text"]:
            return

        state["last_edit"] = now
        state["last_text"] = text

        try:
            loop.call_soon_threadsafe(asyncio.create_task, edit_status(text))
        except RuntimeError:
            pass

    return hook

def get_queue_position() -> int:
    return len(QUEUE) + (1 if CURRENT_JOB else 0)

def remember_chat(chat) -> None:
    if not chat or chat.type not in ("group", "supergroup", "channel"):
        return
    KNOWN_CHATS[str(chat.id)] = {
        "id": chat.id,
        "title": getattr(chat, "title", None) or getattr(chat, "full_name", None) or "Unknown",
        "type": chat.type,
    }
    save_json(KNOWN_CHATS_FILE, KNOWN_CHATS)

def forget_chat(chat_id: int) -> None:
    KNOWN_CHATS.pop(str(chat_id), None)
    save_json(KNOWN_CHATS_FILE, KNOWN_CHATS)

def extract_url(text: str | None) -> str | None:
    if not text:
        return None
    match = URL_RE.search(text.strip())
    return match.group(0) if match else None


def extract_reply_target_url(message) -> str | None:
    reply = getattr(message, "reply_to_message", None)
    if not reply:
        return None
    return extract_url_from_message(reply)



async def delete_message_later(message, delay: float | None = None) -> None:
    """
    Delete temporary/noisy bot messages after a short delay.
    """
    if not message:
        return

    try:
        await asyncio.sleep(NOISE_MESSAGE_DELETE_SECONDS if delay is None else delay)
        await message.delete()
    except Exception:
        pass


async def send_temporary_reply(message, text: str, delay: float | None = None, **kwargs):
    """
    Send a temporary reply and schedule it for cleanup.
    """
    sent = await message.reply_text(text, **kwargs)
    asyncio.create_task(delete_message_later(sent, delay))
    return sent


async def delete_command_message_later(message, delay: float = 2.0) -> None:
    """
    Delete short helper/command messages after Raziel has accepted the job.

    This keeps reply-driven commands like /rdl from leaving command noise
    in group chats.
    """
    if not message:
        return

    try:
        await asyncio.sleep(delay)
        await message.delete()
    except Exception:
        pass


async def handle_reply_download_command(
    update: Update,
    context: ContextTypes.DEFAULT_TYPE,
    mode: str = "video",
    quality: str = "default",
    use_ui: bool = False,
    include_metadata: bool = False,
) -> None:
    message = update.effective_message
    chat = update.effective_chat
    user = update.effective_user

    if not message or not chat or not user:
        return

    if not can_use_context(user.id, chat.id, chat.type):
        return

    url = extract_reply_target_url(message)

    if not url:
        await send_temporary_reply(message, "❌ No supported URL found in the replied message.")
        return

    if not is_supported_video_url(url):
        await send_temporary_reply(message, "❌ Unsupported or invalid media URL.")
        return

    if not await media_preflight_allows_queue(message, url):
        asyncio.create_task(delete_command_message_later(message))
        return

    if is_duplicate_url(url):
        await send_temporary_reply(message, "♻️ That media was already queued/downloaded recently.")
        asyncio.create_task(delete_command_message_later(message))
        return

    remember_chat(chat)

    if use_ui:
        await create_ui_message(update, context, url)
        asyncio.create_task(delete_command_message_later(message))
        return

    job = create_job(
        user_id=user.id,
        chat_id=chat.id,
        url=url,
        mode=mode,
        source="reply-command",
        reply_to_message_id=message.reply_to_message.message_id if message.reply_to_message else None,
        quality=quality,
        include_metadata=include_metadata,
    )

    async with STATE_LOCK:
        QUEUE.append(job)
        save_queue_state()

    remember_dedup_url(url, job["id"], chat.id)

    queue_msg = await message.reply_text(
        "🎬 Added to queue\n\n"
        f"🔗 {shorten_url(url)}\n"
        f"📥 Mode: {mode}\n"
        f"🎞️ Quality: {get_quality_label(quality)}\n"
        f"📋 Queue position: {get_queue_position()}"
    )

    job["queue_message_id"] = queue_msg.message_id
    save_queue_state()

    asyncio.create_task(delete_command_message_later(message))



# ── Metadata Commands ─────────────────────────────────────────

async def dlmeta_cmd(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    await generic_download_command(update, context, mode="video", quality="default", include_metadata=True)

async def hdmeta_cmd(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    await generic_download_command(update, context, mode="video", quality="hd", include_metadata=True)

async def fullmeta_cmd(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    await generic_download_command(update, context, mode="video", quality="full", include_metadata=True)

async def audiometa_cmd(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    await generic_download_command(update, context, mode="audio", include_metadata=True)

async def rdlmeta_cmd(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    await handle_reply_download_command(update, context, mode="video", include_metadata=True)

async def rhdmeta_cmd(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    await handle_reply_download_command(update, context, mode="video", quality="hd", include_metadata=True)

async def rfullmeta_cmd(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    await handle_reply_download_command(update, context, mode="video", quality="full", include_metadata=True)

async def raudiometa_cmd(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    await handle_reply_download_command(update, context, mode="audio", include_metadata=True)

def get_bot_mention_names() -> set[str]:
    """
    Names that should wake Raziel in normal chat messages.

    Deployment-specific Telegram usernames belong in ytbotrc.py, not here.

    Config options:
    BOT_USERNAME = "Razi3l_bot"

    BOT_MENTION_ALIASES = (
        "raziel",
        "@raziel",
        "razi3l_bot",
        "@razi3l_bot",
    )
    """
    names = {
        BOT_NAME.lower(),
        f"@{BOT_NAME.lower()}",
    }

    bot_username = getattr(ytbotrc, "BOT_USERNAME", "")
    if bot_username:
        username = str(bot_username).strip().lower().lstrip("@")
        if username:
            names.add(username)
            names.add(f"@{username}")

    configured = getattr(ytbotrc, "BOT_MENTION_ALIASES", ())
    for item in configured or ():
        name = str(item).strip().lower()
        if not name:
            continue

        cleaned = name.lstrip("@")
        names.add(cleaned)
        names.add(f"@{cleaned}")

    return names

def parse_mention_command(text: str | None) -> tuple[str, str] | None:
    """
    Parse natural mention commands.

    Supported examples:
    - @Raziel weather Houston
    - Raziel forecast Houston
    - @Raziel queue
    - @Raziel status
    - @Raziel help
    """
    if not text:
        return None

    raw = text.strip()
    if not raw:
        return None

    parts = raw.split(maxsplit=2)
    if len(parts) < 2:
        return None

    mention = parts[0].strip().rstrip(":,").lower()
    if mention not in get_bot_mention_names():
        return None

    command = parts[1].strip().lower().lstrip("/")
    args = parts[2].strip() if len(parts) >= 3 else ""

    aliases = {
        "w": "weather",
        "temp": "weather",
        "temps": "weather",
        "f": "forecast",
        "q": "queue",
        "help": "help",
        "commands": "help",
        "status": "status",
        "stats": "stats",
        "reload": "reload",
        "restart": "restart",
    }

    command = aliases.get(command, command)
    return command, args


async def run_mention_command(update: Update, ctx: ContextTypes.DEFAULT_TYPE) -> bool:
    """
    Execute mention commands before normal URL handling.

    Returning True means the message was handled and should not continue
    into the media/link ingestion pipeline.
    """
    remember_chat(update.effective_chat)

    message = update.effective_message
    user = update.effective_user
    chat = update.effective_chat

    if not message or not user or not chat:
        return False

    if getattr(user, "is_bot", False):
        return True

    parsed = parse_mention_command(
        getattr(message, "text", None) or getattr(message, "caption", None)
    )

    if not parsed:
        return False

    command, args = parsed
    user_id = user.id
    admin_here = is_admin(user_id)

    try:
        if command == "weather":
            if not args:
                await send_temporary_reply(message, "Usage: @Raziel weather Houston")
                return True
            result = await asyncio.to_thread(get_current_weather_for_location, args)
            await message.reply_text(result, parse_mode=forecast_parse_mode(result))
            return True

        if command == "forecast":
            if not args:
                await send_temporary_reply(message, "Usage: @Raziel forecast Houston")
                return True
            result = await asyncio.to_thread(get_5day_forecast_for_location, args)
            await message.reply_text(result, parse_mode=forecast_parse_mode(result))
            return True

        if command == "queue":
            if not QUEUE and not CURRENT_JOB:
                await message.reply_text("Queue is empty.")
                return True

            lines = ["📋 *Queue*"]
            if CURRENT_JOB:
                lines.extend([
                    "",
                    "*Now Processing:*",
                    f"• `{CURRENT_JOB['url']}`",
                    f"• mode: `{CURRENT_JOB.get('mode', 'video')}`",
                    f"• quality: `{get_quality_label(CURRENT_JOB.get('quality', 'default'))}`",
                ])

            if QUEUE:
                lines.extend(["", "*Pending:*"])
                for idx, job in enumerate(QUEUE[:10], start=1):
                    lines.append(
                        f"{idx}. `{job['url']}` "
                        f"[{job.get('mode', 'video')} / {get_quality_label(job.get('quality', 'default'))}]"
                    )

            await message.reply_text("\\n".join(lines), parse_mode=ParseMode.MARKDOWN)
            return True

        if command == "help":
            lines = [
                f"🎬 *{BOT_NAME} v{BOT_VERSION}*",
                "The watcher of links.",
                "",
                "*Mention Commands:*",
                "@Raziel weather <place>",
                "@Raziel forecast <place>",
                "@Raziel queue",
                "@Raziel help",
                "",
                "*Reply Commands:*",
                "Reply to a message containing a link:",
                "/rdl — default video",
                "/rhd — HD video",
                "/rfull — best/full video",
                "/raudio — audio",
                "/rui — quality UI",
                "",
                "*Metadata Commands:*",
                "/dlmeta — video + metadata",
                "/hdmeta — HD + metadata",
                "/fullmeta — full quality + metadata",
                "/audiometa — audio + metadata",
                "/rdlmeta — reply video + metadata",
                "/rhdmeta — reply HD + metadata",
                "/rfullmeta — reply full + metadata",
                "/raudiometa — reply audio + metadata",
            ]

            if admin_here:
                lines.extend([
                    "",
                    "*Admin Mentions:*",
                    "@Raziel status",
                    "@Raziel stats",
                    "@Raziel reload",
                    "@Raziel restart",
                ])

            await message.reply_text("\\n".join(lines), parse_mode=ParseMode.MARKDOWN)
            return True

        if command == "status":
            if not admin_here:
                return True
            await message.reply_text(
                f"*Bot Status:* online\\n"
                f"*Current Job:* {'yes' if CURRENT_JOB else 'no'}\\n"
                f"*Queue Length:* {len(QUEUE)}\\n"
                f"*Debug Mode:* {DEBUG_MODE}\\n"
                f"*Dedupe:* {DEDUP_ENABLED} ({DEDUP_TTL_HOURS}h TTL)\\n"
                f"*Enabled Platforms:* {', '.join(ENABLED_VIDEO_PLATFORMS)}\\n"
                f"*Supported Domains:* {', '.join(SUPPORTED_VIDEO_DOMAINS)}",
                f"*Auto-Watch Disabled:* `{len(AUTO_WATCH_DISABLED_CHAT_IDS)}`",
                parse_mode=ParseMode.MARKDOWN,
            )
            return True

        if command == "stats":
            if not admin_here:
                return True
            unique_users = len({h["user"] for h in HISTORY if "user" in h})
            await message.reply_text(
                f"📊 *{BOT_NAME} Stats*\\n\\n"
                f"• Queue: {len(QUEUE)}\\n"
                f"• Active Job: {'yes' if CURRENT_JOB else 'no'}\\n"
                f"• Completed: {len(HISTORY)}\\n"
                f"• Failed: {len(FAILURES)}\\n"
                f"• Unique Users: {unique_users}",
                parse_mode=ParseMode.MARKDOWN,
            )
            return True

        if command == "reload":
            if not admin_here:
                return True
            reload_runtime_config()
            await message.reply_text(
                f"♻️ *{BOT_NAME} v{BOT_VERSION} reloaded*\\n\\n"
                f"*Debug Mode:* `{DEBUG_MODE}`\\n"
                f"*Enabled Platforms:* `{', '.join(ENABLED_VIDEO_PLATFORMS)}`\\n"
                f"*Supported Domains:* `{', '.join(SUPPORTED_VIDEO_DOMAINS)}`",
                parse_mode=ParseMode.MARKDOWN,
            )
            return True

        if command == "restart":
            if not admin_here:
                return True

            if CURRENT_JOB or QUEUE:
                await message.reply_text(
                    "⚠️ Cannot restart while Raziel is busy.\\n"
                    "Queue or current job is active."
                )
                return True

            await message.reply_text(f"🔄 {BOT_NAME} v{BOT_VERSION} restarting...")
            log.warning("Mention restart requested by admin %s", user_id)
            await asyncio.sleep(2)
            os.execv(sys.executable, [sys.executable] + sys.argv)

        # Mentioned Raziel, but command is unknown. Stay quiet.
        return True

    except Exception as e:
        log.exception("Mention command failed: %s", command)
        await message.reply_text(f"❌ {str(e)[:300]}")
        return True



def parse_inline_query(text: str | None) -> tuple[str, str] | None:
    """
    Parse Telegram inline-mode queries.

    Telegram sends only the text after the bot username, so:
    @Razi3l_bot weather Houston
    arrives here as:
    weather Houston
    """
    if not text:
        return None

    raw = text.strip()
    if not raw:
        return None

    parts = raw.split(maxsplit=1)
    command = parts[0].strip().lower().lstrip("/")
    args = parts[1].strip() if len(parts) > 1 else ""

    aliases = {
        "w": "weather",
        "temp": "weather",
        "temps": "weather",
        "f": "forecast",
        "weather": "weather",
        "forecast": "forecast",
        "help": "help",
        "commands": "help",
    }

    command = aliases.get(command, command)
    if command not in {"weather", "forecast", "help"}:
        return None

    return command, args


async def inline_query_cmd(update: Update, ctx: ContextTypes.DEFAULT_TYPE) -> None:
    """
    Telegram inline mode support.

    After enabling inline mode in BotFather, users can type:
    @Razi3l_bot weather Houston
    inside chats where Raziel is not a member.
    """
    query = update.inline_query
    if not query:
        return

    parsed = parse_inline_query(query.query or "")
    results = []

    if not parsed:
        help_text = (
            f"🎬 {BOT_NAME} v{BOT_VERSION}\n\n"
            "Inline examples:\n"
            "@Razi3l_bot weather Houston\n"
            "@Razi3l_bot forecast Houston"
        )

        results.append(
            InlineQueryResultArticle(
                id=str(uuid.uuid4()),
                title="Raziel inline help",
                description="Try: weather Houston or forecast Houston",
                input_message_content=InputTextMessageContent(help_text),
            )
        )

        await query.answer(results, cache_time=5, is_personal=True)
        return

    command, args = parsed

    if command == "help":
        help_text = (
            f"🎬 *{BOT_NAME} v{BOT_VERSION}*\n\n"
            "*Inline Commands:*\n"
            "`weather <place>` — current weather\n"
            "`forecast <place>` — 5-day forecast\n\n"
            "*Examples:*\n"
            "`@Razi3l_bot weather Houston`\n"
            "`@Razi3l_bot forecast Tokyo`"
        )

        results.append(
            InlineQueryResultArticle(
                id=str(uuid.uuid4()),
                title="Raziel inline commands",
                description="Weather and forecast from any chat",
                input_message_content=InputTextMessageContent(
                    help_text,
                    parse_mode=ParseMode.MARKDOWN,
                ),
            )
        )

        await query.answer(results, cache_time=5, is_personal=True)
        return

    if not args:
        usage = "Usage:\nweather Houston\nforecast Houston"
        results.append(
            InlineQueryResultArticle(
                id=str(uuid.uuid4()),
                title="Missing location",
                description="Example: weather Houston",
                input_message_content=InputTextMessageContent(usage),
            )
        )
        await query.answer(results, cache_time=5, is_personal=True)
        return

    try:
        if command == "weather":
            result_text = await asyncio.to_thread(get_current_weather_for_location, args)
            title = f"Weather for {args}"
            description = "Current weather"
        elif command == "forecast":
            result_text = await asyncio.to_thread(get_5day_forecast_for_location, args)
            title = f"Forecast for {args}"
            description = "5-day forecast"
        else:
            return

        results.append(
            InlineQueryResultArticle(
                id=str(uuid.uuid4()),
                title=title[:64],
                description=description,
                input_message_content=InputTextMessageContent(
                    result_text,
                    parse_mode=forecast_parse_mode(result_text),
                ),
            )
        )
    except Exception as e:
        results.append(
            InlineQueryResultArticle(
                id=str(uuid.uuid4()),
                title="Raziel lookup failed",
                description=str(e)[:80],
                input_message_content=InputTextMessageContent(
                    f"❌ Inline lookup failed:\n{str(e)[:300]}"
                ),
            )
        )

    await query.answer(results, cache_time=30, is_personal=True)



def is_forwarded_bot_output(message) -> bool:
    """
    Detect forwarded bot/media output so Raziel does not re-ingest its own
    previously uploaded videos or captions when they are forwarded into a group.
    """
    if not message:
        return False

    origin = getattr(message, "forward_origin", None)
    if origin:
        sender_user = getattr(origin, "sender_user", None)
        sender_chat = getattr(origin, "sender_chat", None)
        chat = getattr(origin, "chat", None)
        sender_name = getattr(origin, "sender_user_name", None) or getattr(origin, "sender_name", None)

        if sender_user:
            if getattr(sender_user, "is_bot", False):
                return True

            name_parts = [
                getattr(sender_user, "first_name", ""),
                getattr(sender_user, "last_name", ""),
                getattr(sender_user, "username", ""),
            ]
            if any(str(part).lower() == BOT_NAME.lower() for part in name_parts if part):
                return True

        for source in (sender_chat, chat):
            if not source:
                continue

            title = getattr(source, "title", "") or getattr(source, "full_name", "") or ""
            username = getattr(source, "username", "") or ""

            if str(title).lower() == BOT_NAME.lower() or str(username).lower() == BOT_NAME.lower():
                return True

        if sender_name and str(sender_name).lower() == BOT_NAME.lower():
            return True

    forward_from = getattr(message, "forward_from", None)
    if forward_from:
        if getattr(forward_from, "is_bot", False):
            return True

        name_parts = [
            getattr(forward_from, "first_name", ""),
            getattr(forward_from, "last_name", ""),
            getattr(forward_from, "username", ""),
        ]
        if any(str(part).lower() == BOT_NAME.lower() for part in name_parts if part):
            return True

    forward_from_chat = getattr(message, "forward_from_chat", None)
    if forward_from_chat:
        title = getattr(forward_from_chat, "title", "") or ""
        username = getattr(forward_from_chat, "username", "") or ""
        if str(title).lower() == BOT_NAME.lower() or str(username).lower() == BOT_NAME.lower():
            return True

    forward_sender_name = getattr(message, "forward_sender_name", None)
    if forward_sender_name and str(forward_sender_name).lower() == BOT_NAME.lower():
        return True

    return False

def extract_url_from_message(message) -> str | None:
    """
    Telegram shared/forwarded messages can place URLs in:
    - message.text
    - message.caption
    - URL entities
    - text_link entity .url
    - raw message payload/link preview fields
    """
    if not message:
        return None

    for value in (getattr(message, "text", None), getattr(message, "caption", None)):
        url = extract_url(value)
        if url:
            return url

    entity_sources = [
        (getattr(message, "text", None) or "", getattr(message, "entities", None) or []),
        (getattr(message, "caption", None) or "", getattr(message, "caption_entities", None) or []),
    ]

    for source_text, entities in entity_sources:
        for ent in entities:
            ent_url = getattr(ent, "url", None)
            if ent_url:
                return ent_url

            if getattr(ent, "type", None) == "url" and source_text:
                try:
                    candidate = source_text[ent.offset: ent.offset + ent.length]
                    url = extract_url(candidate)
                    if url:
                        return url
                except Exception:
                    pass

    # Raw fallback for odd Telegram payloads.
    # Important: do NOT scan reply_to_message, or replying to one of Raziel's
    # uploaded videos can re-discover the old caption URL and queue it again.
    try:
        raw = message.to_dict()
        if isinstance(raw, dict):
            raw.pop("reply_to_message", None)

        stack = [raw]
        while stack:
            item = stack.pop()
            if isinstance(item, dict):
                stack.extend(item.values())
            elif isinstance(item, list):
                stack.extend(item)
            elif isinstance(item, str):
                url = extract_url(item)
                if url:
                    return url
    except Exception:
        pass

    return None


def normalize_url_for_dedupe(url: str) -> str:
    """
    Normalize noisy shared URLs so the same video is not downloaded repeatedly.
    """
    try:
        parsed = urlparse(url.strip())
        scheme = parsed.scheme or "https"
        host = parsed.netloc.lower()

        if host.startswith("www."):
            host = host[4:]
        if host == "m.youtube.com":
            host = "youtube.com"

        query_pairs = {}
        if parsed.query:
            for part in parsed.query.split("&"):
                if "=" in part:
                    k, v = part.split("=", 1)
                    query_pairs[k] = v

        if host == "youtu.be":
            video_id = parsed.path.strip("/").split("/")[0]
            if video_id:
                return f"https://youtube.com/watch?v={video_id}"

        if host in ("youtube.com", "music.youtube.com") and parsed.path == "/watch":
            video_id = query_pairs.get("v")
            if video_id:
                return f"https://youtube.com/watch?v={video_id}"

        if host in ("youtube.com", "music.youtube.com") and parsed.path.startswith("/shorts/"):
            video_id = parsed.path.split("/shorts/", 1)[1].split("/")[0]
            if video_id:
                return f"https://youtube.com/shorts/{video_id}"

        clean = parsed._replace(scheme=scheme, netloc=host, query="", fragment="")
        return clean.geturl()
    except Exception:
        return url.strip()


def prune_dedup_cache() -> None:
    if not DEDUP_ENABLED:
        return

    ttl_seconds = max(int(DEDUP_TTL_HOURS), 1) * 3600
    cutoff = time.time() - ttl_seconds

    expired = [
        key for key, value in DEDUP_CACHE.items()
        if value.get("time", 0) < cutoff
    ]

    for key in expired:
        DEDUP_CACHE.pop(key, None)

    if expired:
        save_json(DEDUP_FILE, DEDUP_CACHE)


def is_duplicate_url(url: str) -> bool:
    if not DEDUP_ENABLED:
        return False

    prune_dedup_cache()
    key = normalize_url_for_dedupe(url)
    return key in DEDUP_CACHE


def remember_dedup_url(url: str, job_id: str, chat_id: int) -> None:
    if not DEDUP_ENABLED:
        return

    key = normalize_url_for_dedupe(url)
    DEDUP_CACHE[key] = {
        "url": url,
        "job_id": job_id,
        "chat": chat_id,
        "time": time.time(),
    }
    save_json(DEDUP_FILE, DEDUP_CACHE)


def ffmpeg_exists() -> bool:
    return shutil.which("ffmpeg") is not None

def ffprobe_exists() -> bool:
    return shutil.which("ffprobe") is not None

def log_startup_checks() -> None:
    log.info("Config file: %s", CONFIG_FILE)
    log.info("Base dir: %s", BASE_DIR)
    log.info("ffmpeg found: %s", ffmpeg_exists())
    log.info("ffprobe found: %s", ffprobe_exists())
    log.info("YouTube cookie file present: %s", YOUTUBE_COOKIES_FILE.exists())
    log.info("Strict platform validation: %s", STRICT_PLATFORM_VALIDATION)
    log.info("Enabled video platforms: %s", ENABLED_VIDEO_PLATFORMS)
    log.info("Supported video domains: %s", SUPPORTED_VIDEO_DOMAINS)
    log.info("Auto-watch disabled chat IDs: %s", sorted(AUTO_WATCH_DISABLED_CHAT_IDS))

    allowed_chat_ids = set(getattr(ytbotrc, "ALLOWED_CHAT_IDS", []))
    if allowed_chat_ids:
        log.info(
            "Group auto-watch is enabled for all groups/supergroups. "
            "Configured ALLOWED_CHAT_IDS retained for reference: %s",
            allowed_chat_ids,
        )
    else:
        log.info("Group auto-watch is enabled for all groups/supergroups the bot is in.")

def get_domain(url: str) -> str:
    try:
        return urlparse(url).netloc.lower()
    except Exception:
        return "unknown"

def get_top_domains(limit: int = 5) -> list[tuple[str, int]]:
    counts = Counter(get_domain(h["url"]) for h in HISTORY if h.get("url"))
    return counts.most_common(limit)

def get_download_folder_count() -> int:
    return sum(1 for p in DOWNLOAD_DIR.iterdir() if p.is_file())

def get_download_folder_size() -> int:
    return sum(p.stat().st_size for p in DOWNLOAD_DIR.iterdir() if p.is_file())

def read_last_log_lines(max_lines: int =1500) -> list[str]:
    if not LOG_FILE.exists():
        return []
    try:
        with LOG_FILE.open("r", encoding="utf-8", errors="replace") as f:
            return f.readlines()[-max_lines:]
    except Exception as e:
        log.warning("Failed to read log file: %s", e)
        return []

def parse_recent_users_from_logs(max_lines: int = 500, limit: int = 10) -> list[dict]:
    lines = read_last_log_lines(max_lines=max_lines)
    results = []
    seen = set()

    pattern = re.compile(
        r"^(?P<timestamp>\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2},\d{3}).*?"
        r"Download requested by user (?P<user_id>[-]?\d+) in chat (?P<chat_id>[-]?\d+): (?P<url>\S+)"
    )

    for line in reversed(lines):
        match = pattern.search(line)
        if not match:
            continue

        user_id = match.group("user_id")
        if user_id in seen:
            continue
        seen.add(user_id)

        results.append({
            "timestamp": match.group("timestamp"),
            "user_id": user_id,
            "chat_id": match.group("chat_id"),
            "url": match.group("url"),
        })

        if len(results) >= limit:
            break

    return results

def count_download_requests_in_logs(max_lines: int = 5000) -> int:
    return sum(1 for line in read_last_log_lines(max_lines) if "Download requested by user " in line)

def get_most_recent_download_timestamp(max_lines: int = 5000) -> str | None:
    recent = parse_recent_users_from_logs(max_lines=max_lines, limit=1)
    return recent[0]["timestamp"] if recent else None

def clear_download_dir() -> None:
    for p in DOWNLOAD_DIR.iterdir():
        if p.is_file():
            try:
                p.unlink()
            except Exception as e:
                log.warning("Failed to delete %s: %s", p, e)

def create_job(
    user_id: int,
    chat_id: int,
    url: str,
    mode: str = "video",
    source: str = "telegram",
    reply_to_message_id: int | None = None,
    clip_start: str | None = None,
    clip_end: str | None = None,
    quality: str = "default",
    include_metadata: bool = False,
) -> dict:
    return {
        "id": str(uuid.uuid4()),
        "user": user_id,
        "chat": chat_id,
        "url": url,
        "mode": mode,
        "time": time.time(),
        "source": source,
        "reply_to_message_id": reply_to_message_id,
        "clip_start": clip_start,
        "clip_end": clip_end,
        "quality": quality,
        "include_metadata": include_metadata,
    }

def save_queue_state() -> None:
    save_json(QUEUE_FILE, QUEUE)

def save_history_state() -> None:
    if len(HISTORY) > MAX_HISTORY_ENTRIES:
        del HISTORY[:-MAX_HISTORY_ENTRIES]
    save_json(HISTORY_FILE, HISTORY)

def save_failures_state() -> None:
    if len(FAILURES) > MAX_HISTORY_ENTRIES:
        del FAILURES[:-MAX_HISTORY_ENTRIES]
    save_json(FAILURES_FILE, FAILURES)


# ── Weather helpers ─────────────────────────────────────────────────────────────
OPEN_METEO_GEOCODE_URL = "https://geocoding-api.open-meteo.com/v1/search"
OPEN_METEO_FORECAST_URL = "https://api.open-meteo.com/v1/forecast"

WEATHER_CODE_MAP = {
    0: ("☀️", "Clear"),
    1: ("🌤️", "Mainly clear"),
    2: ("⛅", "Partly cloudy"),
    3: ("☁️", "Overcast"),
    45: ("🌫️", "Fog"),
    48: ("🌫️", "Rime fog"),
    51: ("🌦️", "Light drizzle"),
    53: ("🌦️", "Moderate drizzle"),
    55: ("🌧️", "Dense drizzle"),
    56: ("🌧️", "Light freezing drizzle"),
    57: ("🌧️", "Dense freezing drizzle"),
    61: ("🌦️", "Slight rain"),
    63: ("🌧️", "Moderate rain"),
    65: ("🌧️", "Heavy rain"),
    66: ("🌧️", "Light freezing rain"),
    67: ("🌧️", "Heavy freezing rain"),
    71: ("🌨️", "Slight snow"),
    73: ("❄️", "Moderate snow"),
    75: ("❄️", "Heavy snow"),
    77: ("🌨️", "Snow grains"),
    80: ("🌦️", "Slight rain showers"),
    81: ("🌧️", "Moderate rain showers"),
    82: ("🌧️", "Violent rain showers"),
    85: ("🌨️", "Slight snow showers"),
    86: ("❄️", "Heavy snow showers"),
    95: ("⛈️", "Thunderstorm"),
    96: ("⛈️", "Thunderstorm with slight hail"),
    99: ("⛈️", "Thunderstorm with heavy hail"),
}

WEEKDAY_EMOJI = {
    0: "🌞",
    1: "🌤️",
    2: "🌦️",
    3: "⛅",
    4: "🌥️",
    5: "🌙",
    6: "✨",
}

def http_get_json(url: str, params: dict) -> dict:
    query = urlencode(params)
    with urlopen(f"{url}?{query}", timeout=15) as resp:
        return json.loads(resp.read().decode("utf-8"))

def weather_code_to_display(code: int | None) -> str:
    if code is None:
        return "❓ Unknown"
    icon, text = WEATHER_CODE_MAP.get(code, ("❓", f"Code {code}"))
    return f"{icon} {text}"

def weather_code_to_icon(code: int | None) -> str:
    if code is None:
        return "❓"
    icon, _ = WEATHER_CODE_MAP.get(code, ("❓", "Unknown"))
    return icon

def geocode_location(name: str) -> dict:
    data = http_get_json(
        OPEN_METEO_GEOCODE_URL,
        {"name": name, "count": 1, "language": "en", "format": "json"},
    )
    results = data.get("results") or []
    if not results:
        raise RuntimeError(f"No location found for: {name}")
    return results[0]

def build_place_label(loc: dict, fallback_name: str) -> str:
    parts = [loc.get("name", fallback_name)]
    if loc.get("admin1"):
        parts.append(loc["admin1"])
    if loc.get("country"):
        parts.append(loc["country"])
    return ", ".join(parts)

def get_current_weather_for_location(name: str) -> str:
    loc = geocode_location(name)
    label = build_place_label(loc, name)

    data = http_get_json(
        OPEN_METEO_FORECAST_URL,
        {
            "latitude": loc["latitude"],
            "longitude": loc["longitude"],
            "current": "temperature_2m,weather_code,relative_humidity_2m,wind_speed_10m",
            "temperature_unit": "fahrenheit",
            "wind_speed_unit": "mph",
            "forecast_days": 1,
        },
    )

    current = data.get("current") or {}
    units = data.get("current_units") or {}

    temp = current.get("temperature_2m")
    humidity = current.get("relative_humidity_2m")
    wind = current.get("wind_speed_10m")
    condition = weather_code_to_display(current.get("weather_code"))

    if temp is None:
        raise RuntimeError("Weather response did not include temperature.")

    lines = [
        f"🌤️ *Weather for {label}*",
        "",
        f"🌡️ *Temp:* {temp}{units.get('temperature_2m', '°F')}",
        f"🫧 *Humidity:* {humidity}{units.get('relative_humidity_2m', '%')}" if humidity is not None else None,
        f"💨 *Wind:* {wind} {units.get('wind_speed_10m', 'mph')}" if wind is not None else None,
        f"🛰️ *Condition:* {condition}",
    ]
    return "\n".join(line for line in lines if line is not None)



def forecast_parse_mode(text: str) -> str:
    """
    Forecasts using expandable Telegram blockquotes require HTML parse mode.
    """
    return ParseMode.HTML if "<blockquote expandable>" in text else ParseMode.MARKDOWN


def get_5day_forecast_for_location(name: str) -> str:
    loc = geocode_location(name)
    label = build_place_label(loc, name)

    data = http_get_json(
        OPEN_METEO_FORECAST_URL,
        {
            "latitude": loc["latitude"],
            "longitude": loc["longitude"],
            "daily": "weather_code,temperature_2m_max,temperature_2m_min,precipitation_sum",
            "temperature_unit": "fahrenheit",
            "precipitation_unit": "inch",
            "forecast_days": 5,
            "timezone": "auto",
        },
    )

    daily = data.get("daily") or {}
    units = data.get("daily_units") or {}

    times = daily.get("time") or []
    codes = daily.get("weather_code") or []
    highs = daily.get("temperature_2m_max") or []
    lows = daily.get("temperature_2m_min") or []
    rains = daily.get("precipitation_sum") or []

    if not times:
        raise RuntimeError("Forecast response did not include daily data.")

    def build_day_block(i: int, html_mode: bool = False) -> str:
        try:
            day_name = datetime.fromisoformat(times[i]).strftime("%a")
            weekday_idx = datetime.fromisoformat(times[i]).weekday()
        except Exception:
            day_name = times[i]
            weekday_idx = i % 7

        code = codes[i] if i < len(codes) else None
        icon = weather_code_to_icon(code)
        _, weather_text = WEATHER_CODE_MAP.get(code, ("❓", "Unknown")) if code is not None else ("❓", "Unknown")

        if html_mode:
            day_fmt = f"<b>{html.escape(day_name)}</b>"
            weather_text = html.escape(weather_text)
        else:
            day_fmt = f"*{day_name}*"

        lines = [
            f"{WEEKDAY_EMOJI.get(weekday_idx, '📅')} {day_fmt} — {icon} {weather_text}"
        ]

        if i < len(highs):
            lines.append(f"   🔺 {highs[i]}{units.get('temperature_2m_max', '°F')}")
        if i < len(lows):
            lines.append(f"   🔻 {lows[i]}{units.get('temperature_2m_min', '°F')}")
        if i < len(rains):
            lines.append(f"   🌧️ {rains[i]} {units.get('precipitation_sum', 'inch')}")

        return "\n".join(lines)

    if not FORECAST_COLLAPSE_DETAILS:
        lines = [f"🗓️ *5-Day Forecast for {label}*", ""]
        for i in range(len(times)):
            lines.append(build_day_block(i))
            if i != len(times) - 1:
                lines.append("")
        return "\n".join(lines)

    visible_days = max(1, min(int(FORECAST_VISIBLE_DAYS), len(times)))

    visible_blocks = [
        build_day_block(i, html_mode=True)
        for i in range(visible_days)
    ]

    hidden_blocks = [
        build_day_block(i, html_mode=True)
        for i in range(visible_days, len(times))
    ]

    lines = [
        f"🗓️ <b>5-Day Forecast for {html.escape(label)}</b>",
        "",
    ]

    for block in visible_blocks:
        lines.append(block)
        lines.append("")

    if hidden_blocks:
        lines.append("📖 <b>Extended Forecast</b>")
        lines.append(
            "<blockquote expandable>"
            + "\n\n".join(hidden_blocks)
            + "</blockquote>"
        )

    return "\n".join(lines).strip()


# ── Media metadata / download ───────────────────────────────────────────────────
def is_youtube_url(url: str) -> bool:
    lower = url.lower()
    return "youtube.com/" in lower or "youtu.be/" in lower or "m.youtube.com/" in lower

def is_instagram_url(url: str) -> bool:
    return "instagram.com/" in url.lower()

def is_supported_video_url(url: str) -> bool:
    """
    Validate media URLs according to config policy.

    STRICT_PLATFORM_VALIDATION = True:
        Only allow domains from ENABLED_VIDEO_PLATFORMS and EXTRA_VIDEO_DOMAINS.

    STRICT_PLATFORM_VALIDATION = False:
        Allow any http(s) URL and let yt-dlp decide whether it can extract it.
        This avoids constantly editing ytbot.py for every yt-dlp-supported site.
    """
    try:
        parsed = urlparse(url.strip())
        host = parsed.netloc.lower()
        scheme = parsed.scheme.lower()

        if scheme not in ("http", "https"):
            return False

        if not host:
            return False

        if not STRICT_PLATFORM_VALIDATION:
            return True

        if host.startswith("www."):
            host = host[4:]

        if host == "m.youtube.com":
            host = "youtube.com"

        return any(
            host == domain or host.endswith(f".{domain}")
            for domain in SUPPORTED_VIDEO_DOMAINS
        )
    except Exception:
        return False

def get_cookiefile_for_url(url: str) -> str | None:
    if is_youtube_url(url) and YOUTUBE_COOKIES_FILE.exists():
        return str(YOUTUBE_COOKIES_FILE)
    return None


def info_has_downloadable_media(info: dict | None) -> bool:
    """
    Return True only when yt-dlp metadata exposes downloadable media.

    This filters out valid-but-not-media URLs, especially text-only X/Twitter
    posts, Reddit self posts, article links, etc.
    """
    if not info:
        return False

    # Playlists/containers can expose entries; allow if any entry has media.
    entries = info.get("entries")
    if entries:
        for entry in entries:
            if info_has_downloadable_media(entry):
                return True

    formats = info.get("formats") or []
    if formats:
        for fmt in formats:
            if not isinstance(fmt, dict):
                continue

            vcodec = (fmt.get("vcodec") or "").lower()
            acodec = (fmt.get("acodec") or "").lower()
            url = fmt.get("url")

            # A real downloadable media format should have a URL and at least
            # an audio or video codec. "none" means that stream type is absent.
            if url and (vcodec not in ("", "none") or acodec not in ("", "none")):
                return True

    # Some extractors expose direct media URL/extension without full formats.
    direct_url = info.get("url")
    ext = (info.get("ext") or "").lower()
    if direct_url and ext in {
        "mp4", "m4v", "mov", "webm", "mkv", "avi",
        "mp3", "m4a", "opus", "ogg", "wav", "flac",
    }:
        return True

    requested = info.get("requested_downloads") or []
    if requested:
        return True

    return False


def media_preflight_check(url: str) -> tuple[bool, str]:
    """
    Check whether a URL actually contains downloadable media before queueing.

    This prevents noisy queue/fail behavior for text-only posts.
    """
    if not MEDIA_PREFLIGHT_ENABLED:
        return True, "preflight disabled"

    if not is_supported_video_url(url):
        return False, "unsupported URL"

    opts = {
        "quiet": True,
        "no_warnings": True,
        "noplaylist": True,
        "skip_download": True,
        "socket_timeout": MEDIA_PREFLIGHT_TIMEOUT,
        "extract_flat": False,
    }

    cookiefile = get_cookiefile_for_url(url)
    if cookiefile:
        opts["cookiefile"] = cookiefile

    if is_instagram_url(url):
        opts["nocheckcertificate"] = True

    try:
        with yt_dlp.YoutubeDL(opts) as ydl:
            info = ydl.extract_info(url, download=False)

        if info_has_downloadable_media(info):
            return True, "media found"

        return False, "no downloadable media found"

    except Exception as e:
        # If yt-dlp says no video/media was found, treat as no media and do not queue.
        error = str(e)
        low = error.lower()

        no_media_markers = (
            "no video could be found",
            "no media could be found",
            "no video found",
            "no downloadable",
            "unsupported url",
            "not a video",
            "does not contain",
            "no formats found",
        )

        if any(marker in low for marker in no_media_markers):
            return False, error[:240]

        # For transient/network/auth failures, allow queueing so the normal
        # downloader can produce the existing detailed failure behavior.
        return True, f"preflight uncertain: {error[:160]}"


async def media_preflight_allows_queue(message, url: str) -> bool:
    """
    Async wrapper for media preflight.

    Returns True when queueing should continue.
    Returns False after quietly notifying/cleaning low-value no-media URLs.
    """
    allowed, reason = await asyncio.to_thread(media_preflight_check, url)

    if allowed:
        return True

    # No-media links are not worth turning into queue/failure noise.
    # Send a small temporary notice so the user knows Raziel ignored it.
    try:
        await send_temporary_reply(
            message,
            "ℹ️ No downloadable media found in that link.",
            delay=MEDIA_PREFLIGHT_NOISE_DELETE_SECONDS,
        )
    except Exception:
        pass

    return False



def get_media_info(url: str) -> dict:
    if not is_supported_video_url(url):
        raise RuntimeError("Unsupported video source.")

    opts = {
        "quiet": True,
        "noplaylist": True,
        "skip_download": True,
    }
    cookiefile = get_cookiefile_for_url(url)
    if cookiefile:
        opts["cookiefile"] = cookiefile
    if is_instagram_url(url):
        opts["nocheckcertificate"] = True

    with yt_dlp.YoutubeDL(opts) as ydl:
        info = ydl.extract_info(url, download=False)

    post_text = first_nonempty(
        info.get("description"),
        info.get("fulltitle"),
        info.get("alt_title"),
        info.get("title"),
    )

    return {
        "title": info.get("title", "Unknown title"),
        "fulltitle": info.get("fulltitle"),
        "alt_title": info.get("alt_title"),
        "description": info.get("description"),
        "post_text": post_text,
        "duration": info.get("duration"),
        "uploader": first_nonempty(
            info.get("uploader"),
            info.get("channel"),
            info.get("creator"),
            info.get("artist"),
            "Unknown uploader",
        ),
        "webpage_url": info.get("webpage_url", url),
        "original_url": url,
    }

def has_video_stream(path: Path) -> bool:
    if not ffprobe_exists():
        return False
    cmd = [
        "ffprobe", "-v", "error",
        "-select_streams", "v:0",
        "-show_entries", "stream=codec_type",
        "-of", "default=noprint_wrappers=1:nokey=1",
        str(path),
    ]
    result = subprocess.run(cmd, capture_output=True, text=True)
    return result.returncode == 0 and "video" in result.stdout.lower()

def get_duration_seconds(path: Path) -> float:
    if not ffprobe_exists():
        raise RuntimeError("ffprobe is not installed or not in PATH.")
    cmd = [
        "ffprobe", "-v", "error",
        "-show_entries", "format=duration",
        "-of", "default=noprint_wrappers=1:nokey=1",
        str(path),
    ]
    result = subprocess.run(cmd, capture_output=True, text=True, check=True)
    return float(result.stdout.strip())

def is_valid_video_file(path: Path) -> bool:
    try:
        if not path.exists() or not path.is_file():
            return False
        if path.stat().st_size < MIN_VALID_VIDEO_BYTES:
            return False
        if not has_video_stream(path):
            return False
        if get_duration_seconds(path) <= 0.5:
            return False
        return True
    except Exception as e:
        log.warning("Video validation failed for %s: %s", path, e)
        return False


def get_quality_height(quality: str | None) -> int | None:
    q = (quality or "default").lower()

    if q == "full":
        return None
    if q == "hd":
        return int(HD_VIDEO_HEIGHT)

    return int(DEFAULT_VIDEO_HEIGHT)


def get_quality_label(quality: str | None) -> str:
    q = (quality or "default").lower()

    if q == "full":
        return "full/best"
    if q == "hd":
        return f"hd/{HD_VIDEO_HEIGHT}p"

    return f"default/{DEFAULT_VIDEO_HEIGHT}p"


def build_ydl_opts(url: str, outtmpl: str, mode: str, quality: str = "default", progress_hook=None) -> dict:
    opts: dict = {
        "outtmpl": outtmpl,
        "noplaylist": True,
        "quiet": True,
        "no_warnings": True,
        "restrictfilenames": False,
        "compat_opts": ["no-certifi"],
    }

    if progress_hook:
        opts["progress_hooks"] = [progress_hook]

    if mode == "audio":
        opts["format"] = "bestaudio/best"
        opts["postprocessors"] = [{
            "key": "FFmpegExtractAudio",
            "preferredcodec": "mp3",
            "preferredquality": "192",
        }]
    else:
        max_height = get_quality_height(quality)

        if max_height is None:
            height_filter = ""
        else:
            height_filter = f"[height<={max_height}]"

        if is_instagram_url(url):
            if max_height is None:
                opts["format"] = "bestvideo+bestaudio/best"
            else:
                opts["format"] = (
                    f"bestvideo{height_filter}+bestaudio/"
                    f"best{height_filter}/best"
                )
            opts["nocheckcertificate"] = True
        else:
            if PREFER_MP4:
                if max_height is None:
                    opts["format"] = (
                        "bv*[ext=mp4]+ba[ext=m4a]/"
                        "bv*+ba/"
                        "b[ext=mp4]/"
                        "best"
                    )
                else:
                    opts["format"] = (
                        f"bv*{height_filter}[ext=mp4]+ba[ext=m4a]/"
                        f"bv*{height_filter}+ba/"
                        f"b{height_filter}[ext=mp4]/"
                        f"b{height_filter}/"
                        f"best"
                    )
            else:
                if max_height is None:
                    opts["format"] = "bv*+ba/best"
                else:
                    opts["format"] = (
                        f"bv*{height_filter}+ba/"
                        f"b{height_filter}/"
                        f"best"
                    )

        opts["merge_output_format"] = "mp4"

    cookiefile = get_cookiefile_for_url(url)
    if cookiefile:
        opts["cookiefile"] = cookiefile

    return opts

def download_media(url: str, mode: str, quality: str = "default", progress_hook=None) -> Path:
    if not is_supported_video_url(url):
        raise RuntimeError("Unsupported video source.")

    clear_download_dir()

    ext_hint = "%(ext)s" if mode != "audio" else "mp3"
    outtmpl = str(DOWNLOAD_DIR / f"%(title).100s [%(id)s].{ext_hint}")

    opts = build_ydl_opts(url, outtmpl, mode, quality, progress_hook=progress_hook)

    with yt_dlp.YoutubeDL(opts) as ydl:
        ydl.download([url])

    files = [p for p in DOWNLOAD_DIR.iterdir() if p.is_file()]
    if not files:
        raise RuntimeError("No file downloaded")

    file = max(files, key=lambda f: f.stat().st_size)

    if mode == "audio":
        if file.stat().st_size < MIN_VALID_AUDIO_BYTES:
            raise RuntimeError("Downloaded audio file is invalid/empty")
        return file

    if not is_valid_video_file(file):
        raise RuntimeError("Downloaded file is not a valid playable video")

    return file

def normalize_timecode(value: str) -> str:
    value = value.strip()

    if not re.fullmatch(r"\d{1,2}:\d{2}(?::\d{2})?", value):
        raise RuntimeError("Time must be HH:MM:SS or MM:SS")

    parts = [int(p) for p in value.split(":")]
    if len(parts) == 2:
        minutes, seconds = parts
        hours = 0
    else:
        hours, minutes, seconds = parts

    if minutes < 0 or seconds < 0 or seconds > 59 or minutes > 59:
        raise RuntimeError("Invalid time value")

    return f"{hours:02d}:{minutes:02d}:{seconds:02d}"

def timecode_to_seconds(value: str) -> int:
    parts = [int(p) for p in value.split(":")]
    if len(parts) == 2:
        minutes, seconds = parts
        return minutes * 60 + seconds
    hours, minutes, seconds = parts
    return hours * 3600 + minutes * 60 + seconds

def format_clip_range(start_time: str, end_time: str) -> str:
    """
    Format clip start/end timestamps for upload captions.
    Includes total clip duration so the uploaded clip is self-explanatory.
    """
    try:
        start_norm = normalize_timecode(start_time)
        end_norm = normalize_timecode(end_time)
        duration = max(timecode_to_seconds(end_norm) - timecode_to_seconds(start_norm), 0)
        return f"⏱️ Clip: {start_norm} → {end_norm} ({format_duration(duration)})"
    except Exception:
        return f"⏱️ Clip: {start_time} → {end_time}"

def clip_video(input_file: Path, start_time: str, end_time: str) -> Path:
    if not ffmpeg_exists():
        raise RuntimeError("ffmpeg is not installed or not in PATH.")

    start_time = normalize_timecode(start_time)
    end_time = normalize_timecode(end_time)

    start_sec = timecode_to_seconds(start_time)
    end_sec = timecode_to_seconds(end_time)

    if end_sec <= start_sec:
        raise RuntimeError("End time must be after start time.")

    output = input_file.with_name(f"{input_file.stem}_clip.mp4")

    cmd = [
        "ffmpeg", "-y",
        "-ss", start_time,
        "-to", end_time,
        "-i", str(input_file),
        "-c:v", "libx264",
        "-c:a", "aac",
        "-movflags", "+faststart",
        str(output),
    ]

    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0 or not output.exists() or output.stat().st_size == 0:
        raise RuntimeError(f"Clip creation failed: {result.stderr[:300]}")

    if not is_valid_video_file(output):
        raise RuntimeError("Created clip is not a valid playable video")

    return output

def compress_to_telegram(input_file: Path) -> Path:
    """
    Re-encode the video to fit within MAX_UPLOAD_BYTES.
    Uses duration-aware bitrate targeting across up to three resolution steps
    (480p → 360p → 240p) to guarantee the output fits.
    """
    if not ffmpeg_exists():
        raise RuntimeError("ffmpeg is not installed or not in PATH — cannot compress.")

    duration = get_duration_seconds(input_file)
    if duration <= 0:
        raise RuntimeError("Could not determine video duration for compression.")

    target_audio_bps = 64_000
    target_total_bps = int((MAX_UPLOAD_BYTES * 8) / duration * 0.92)
    target_video_bps = max(target_total_bps - target_audio_bps, 120_000)

    attempts = [
        ("480:-2", target_video_bps),
        ("360:-2", max(int(target_video_bps * 0.75), 100_000)),
        ("240:-2", max(int(target_video_bps * 0.55), 80_000)),
    ]

    for idx, (scale, video_bps) in enumerate(attempts, start=1):
        output = input_file.with_name(f"compressed_{input_file.stem}_p{idx}.mp4")
        cmd = [
            "ffmpeg", "-y", "-i", str(input_file),
            "-vf", f"scale={scale}",
            "-c:v", "libx264",
            "-b:v", str(video_bps),
            "-maxrate", str(int(video_bps * 1.3)),
            "-bufsize", str(int(video_bps * 2)),
            "-preset", "medium",
            "-movflags", "+faststart",
            "-c:a", "aac",
            "-b:a", str(target_audio_bps),
            str(output),
        ]
        log.info("Compress attempt %s: scale=%s video_bps=%s", idx, scale, video_bps)
        result = subprocess.run(cmd, capture_output=True, text=True)

        if result.returncode != 0 or not output.exists() or output.stat().st_size == 0:
            log.warning("Compression attempt %s failed: %s", idx, result.stderr[:300])
            continue

        out_size = output.stat().st_size
        log.info("Compressed output size: %s", format_size(out_size))

        if out_size <= MAX_UPLOAD_BYTES:
            return output

        output.unlink(missing_ok=True)
        log.warning("Attempt %s still too large (%s), trying smaller resolution.", idx, format_size(out_size))

    raise RuntimeError(
        f"Could not compress video to fit within {format_size(MAX_UPLOAD_BYTES)} "
        f"after {len(attempts)} attempts."
    )

def route_file(path: Path, mode: str) -> Path:
    dest_dir = DONE_AUDIO_DIR if mode == "audio" else DONE_VIDEO_DIR
    dest = dest_dir / path.name
    counter = 1
    while dest.exists():
        dest = dest_dir / f"{path.stem}_{counter}{path.suffix}"
        counter += 1
    shutil.move(str(path), str(dest))
    return dest

def save_failed_copy(path: Path | None, job_id: str) -> None:
    if not path or not path.exists():
        return
    try:
        dest = FAILED_DIR / f"{job_id}_{path.name}"
        shutil.move(str(path), str(dest))
    except Exception as e:
        log.warning("Failed to route failed file %s: %s", path, e)


# ── Queue worker ────────────────────────────────────────────────────────────────
async def process_job(app, job: dict) -> None:
    chat_id = job["chat"]
    url = job["url"]
    mode = job.get("mode", "video")
    quality = job.get("quality", "default")
    reply_to_message_id = job.get("reply_to_message_id")
    clip_start = job.get("clip_start")
    clip_end = job.get("clip_end")

    log.info(
        "Download requested by user %s in chat %s: %s",
        job["user"], job["chat"], url
    )

    status_msg = await app.bot.send_message(
        chat_id,
        "🔍 Fetching metadata…",
        reply_to_message_id=reply_to_message_id,
    )

    downloaded_file: Path | None = None
    sent_file: Path | None = None
    routed_file: Path | None = None

    try:
        meta = await asyncio.to_thread(get_media_info, url)

        caption = None
        context_message = None
        if job.get("source") in ("ui", "dl", "audio", "clip", "raw_url"):
            caption = build_upload_caption(meta, mode, clip_start, clip_end)
            context_message = build_expandable_context_message(meta) if job.get("include_metadata") else None

        await status_msg.edit_text(
            f"🎞️ {meta['title']}\n"
            f"👤 {meta['uploader']}\n"
            f"⏱️ {format_duration(meta['duration'])}\n\n"
            f"⬇️ Downloading {mode} ({get_quality_label(quality)})…"
        )

        download_mode = "audio" if mode == "audio" else "video"

        progress_hook = make_download_progress_hook(
            app,
            chat_id,
            status_msg.message_id,
            meta["title"],
            meta["uploader"],
            mode,
            quality,
        )

        downloaded_file = await asyncio.wait_for(
            asyncio.to_thread(download_media, url, download_mode, quality, progress_hook),
            timeout=DOWNLOAD_TIMEOUT,
        )
        sent_file = downloaded_file

        if mode == "clip":
            if not clip_start or not clip_end:
                raise RuntimeError("Clip job is missing start or end time.")
            await status_msg.edit_text(
                f"🎞️ {meta['title']}\n"
                f"👤 {meta['uploader']}\n"
                f"{format_clip_range(clip_start, clip_end)}\n"
                f"✂️ Clipping…"
            )
            clipped = await asyncio.to_thread(clip_video, sent_file, clip_start, clip_end)
            if sent_file.exists():
                sent_file.unlink()
            sent_file = clipped

        if mode in ("video", "clip"):
            size_mb = sent_file.stat().st_size / (1024 * 1024)
            if sent_file.stat().st_size > MAX_UPLOAD_BYTES:
                await status_msg.edit_text(f"📦 Large file ({size_mb:.1f} MB)\nProcessing…")
                compressed = await asyncio.to_thread(compress_to_telegram, sent_file)
                if sent_file.exists():
                    sent_file.unlink()
                sent_file = compressed

        size_str = format_size(sent_file.stat().st_size)

        # Queue confirmation messages are temporary in all chat types,
        # including DMs. Delete them once upload begins so only the final
        # media/caption remains.
        queue_message_id = job.get("queue_message_id")
        if queue_message_id:
            try:
                await app.bot.delete_message(
                    chat_id=chat_id,
                    message_id=queue_message_id,
                )
            except Exception as e:
                log.debug("Could not delete queue message %s: %s", queue_message_id, e)

        await status_msg.edit_text(f"📤 Uploading… ({size_str})")

        sent_message = None
        with sent_file.open("rb") as f:
            if mode == "audio":
                sent_message = await app.bot.send_audio(
                    chat_id,
                    f,
                    filename=sent_file.name,
                    caption=caption,
                    reply_to_message_id=reply_to_message_id
                )
            else:
                try:
                    sent_message = await app.bot.send_video(
                        chat_id,
                        f,
                        filename=sent_file.name,
                        supports_streaming=True,
                        caption=caption,
                        reply_to_message_id=reply_to_message_id
                    )
                except Exception:
                    f.seek(0)
                    sent_message = await app.bot.send_document(
                        chat_id,
                        f,
                        filename=sent_file.name,
                        caption=caption,
                        reply_to_message_id=reply_to_message_id
                    )

        if context_message and sent_message:
            try:
                await app.bot.send_message(
                    chat_id=chat_id,
                    text=context_message,
                    parse_mode=ParseMode.HTML,
                    disable_web_page_preview=True,
                )
            except Exception as e:
                log.warning("Failed to send expandable source context: %s", e)

        if ARCHIVE_CHAT_ID:
            with sent_file.open("rb") as f:
                if mode == "audio":
                    await app.bot.send_audio(
                        ARCHIVE_CHAT_ID,
                        f,
                        filename=sent_file.name,
                        caption=caption,
                    )
                else:
                    try:
                        await app.bot.send_video(
                            ARCHIVE_CHAT_ID,
                            f,
                            filename=sent_file.name,
                            supports_streaming=True,
                            caption=caption,
                        )
                    except Exception:
                        f.seek(0)
                        await app.bot.send_document(
                            ARCHIVE_CHAT_ID,
                            f,
                            filename=sent_file.name,
                            caption=caption,
                        )

        routed_file = await asyncio.to_thread(route_file, sent_file, "audio" if mode == "audio" else "video")

        job["status"] = "success"
        job["completed_time"] = time.time()
        job["saved_to"] = str(routed_file)
        HISTORY.append(job)
        save_history_state()

        await status_msg.delete()

    except asyncio.TimeoutError:
        job["status"] = "failed"
        job["error"] = f"Download timed out after {DOWNLOAD_TIMEOUT}s"
        job["failed_time"] = time.time()
        FAILURES.append(job)
        save_failures_state()
        save_failed_copy(sent_file or downloaded_file, job["id"])
        await status_msg.edit_text(
            "❌ *Download Failed*\n\n`Timed out waiting for the download to finish.`",
            parse_mode=ParseMode.MARKDOWN,
        )
    except Exception as e:
        job["status"] = "failed"
        job["error"] = str(e)
        job["failed_time"] = time.time()
        FAILURES.append(job)
        save_failures_state()
        save_failed_copy(sent_file or downloaded_file, job["id"])

        err = str(e)
        err_lower = err.lower()
        if "sign in to confirm you're not a bot" in err_lower:
            friendly = (
                "🔒 YouTube blocked anonymous access.\n"
                f"Add a cookie file at:\n`{YOUTUBE_COOKIES_FILE}`"
            )
        elif "rate-limit" in err_lower or "requested content is not available" in err_lower:
            friendly = "🚫 Instagram blocked this request — rate-limited or login required."
        elif "no file downloaded" in err_lower or "not a valid playable video" in err_lower:
            friendly = "⚠️ The site responded but no playable video was produced."
        elif "invalid data found when processing input" in err_lower or "postprocessing" in err_lower:
            friendly = "⚠️ The downloaded data wasn't a valid video file."
        elif "certificate_verify_failed" in err_lower or "unable to get local issuer certificate" in err_lower:
            friendly = "🔐 SSL certificate verification failed for that site."
        elif "ffmpeg" in err_lower or "ffprobe" in err_lower:
            friendly = f"⚙️ {err}"
        elif "could not compress" in err_lower:
            friendly = f"📏 {err}"
        elif "request entity too large" in err_lower:
            friendly = f"📏 Telegram rejected the upload — file exceeded {format_size(MAX_UPLOAD_BYTES)}."
        else:
            friendly = f"❌ {err[:300]}"
            log.exception("Unhandled error in process_job for %s", url)

        await status_msg.edit_text(
            f"❌ *Download Failed*\n\n{friendly}",
            parse_mode=ParseMode.MARKDOWN,
        )

async def queue_worker(app) -> None:
    global CURRENT_JOB
    while True:
        await asyncio.sleep(1)
        if CURRENT_JOB or not QUEUE:
            continue

        async with STATE_LOCK:
            if not QUEUE:
                continue
            CURRENT_JOB = QUEUE.pop(0)
            save_queue_state()

        try:
            await process_job(app, CURRENT_JOB)
        except Exception:
            log.exception("Unexpected error in queue_worker for job %s", CURRENT_JOB.get("id"))
        finally:
            async with STATE_LOCK:
                CURRENT_JOB = None

async def watch_folder_worker() -> None:
    while True:
        await asyncio.sleep(5)

        if not WATCH_FOLDER_ENABLED:
            continue

        for txt_file in WATCH_DIR.glob("*.txt"):
            try:
                urls = []
                for line in txt_file.read_text(encoding="utf-8").splitlines():
                    url = extract_url(line.strip())
                    if url and is_supported_video_url(url):
                        urls.append(url)
                for url in urls:
                    QUEUE.append(create_job(OWNER_ID, WATCH_FOLDER_CHAT_ID, url, mode="video", source="watch"))
                save_queue_state()
                txt_file.unlink()
            except Exception as e:
                log.warning("Watch-folder processing failed for %s: %s", txt_file, e)


# ── Telegram interactive UI ─────────────────────────────────────────────────────
async def ui_cmd(update: Update, ctx: ContextTypes.DEFAULT_TYPE) -> None:
    remember_chat(update.effective_chat)

    if not can_use_context(
        update.effective_user.id,
        update.effective_chat.id,
        update.effective_chat.type,
    ):
        await update.message.reply_text("🚫 Not allowed here.")
        return

    if not ctx.args:
        await update.message.reply_text(
            "❌ Invalid usage\n\n"
            "Example:\n"
            "/ui https://example.com/video"
        )
        return

    url = extract_url(" ".join(ctx.args))
    if not url:
        await update.message.reply_text("That does not look like a valid URL.")
        return

    if not is_supported_video_url(url):
        await update.message.reply_text("❌ Unsupported video source.")
        return

    try:
        info = await asyncio.to_thread(get_media_info, url)

        short_id = str(uuid.uuid4())[:8]
        PENDING_UI[short_id] = {
            "url": url,
            "user_id": update.effective_user.id,
            "chat_id": update.effective_chat.id,
        }

        keyboard = InlineKeyboardMarkup([
            [
                InlineKeyboardButton("🎬 720p", callback_data=f"dl|video|{short_id}"),
                InlineKeyboardButton("🎬 HD", callback_data=f"dl|hd|{short_id}"),
            ],
            [
                InlineKeyboardButton("🎬 Full", callback_data=f"dl|full|{short_id}"),
                InlineKeyboardButton("🎵 Audio", callback_data=f"dl|audio|{short_id}"),
            ],
            [
                InlineKeyboardButton("❌ Cancel", callback_data=f"dl|cancel|{short_id}")
            ]
        ])

        await update.message.reply_text(
            f"🎞️ *Preview*\n\n"
            f"*Title:* {info['title']}\n"
            f"*Uploader:* {info['uploader']}\n"
            f"*Duration:* {format_duration(info['duration'])}",
            parse_mode=ParseMode.MARKDOWN,
            reply_markup=keyboard,
        )
    except Exception as e:
        await update.message.reply_text(f"Preview error: {e}")

async def ui_button_cb(update: Update, ctx: ContextTypes.DEFAULT_TYPE) -> None:
    query = update.callback_query
    if not query:
        return

    await query.answer()

    user = query.from_user
    chat = query.message.chat if query.message else None

    if not user or not chat:
        return

    if not can_use_context(user.id, chat.id, chat.type):
        await query.edit_message_text("🚫 Not allowed here.")
        return

    data = query.data or ""
    parts = data.split("|", 2)

    if len(parts) < 2:
        await query.edit_message_text("Invalid action.")
        return

    action = parts[1]
    short_id = parts[2] if len(parts) == 3 else None

    if action == "cancel":
        if short_id:
            PENDING_UI.pop(short_id, None)
        await query.edit_message_text("❌ Cancelled.")
        return

    if not short_id:
        await query.edit_message_text("Invalid media request.")
        return

    pending = PENDING_UI.pop(short_id, None)
    if not pending:
        await query.edit_message_text("⚠️ This request has already been used or expired.")
        return

    quality = "default"
    mode = action

    if action == "hd":
        mode = "video"
        quality = "hd"
    elif action == "full":
        mode = "video"
        quality = "full"

    url = pending["url"]

    job = create_job(user.id, chat.id, url, mode=mode, source="ui", quality=quality)
    QUEUE.append(job)
    save_queue_state()

    pos = get_queue_position()
    await query.edit_message_text(
        f"✅ Added to queue\n"
        f"🔢 Position: {pos}\n"
        f"{'🎬' if mode == 'video' else '🎵'} Mode: {mode}\n"
        f"📺 Quality: {get_quality_label(quality)}",
        parse_mode=ParseMode.MARKDOWN,
    )


# ── Commands ────────────────────────────────────────────────────────────────────
USER_COMMAND_LIST = (
    "/start         — welcome & command list\n"
    "/help          — usage instructions\n"
    "/dl <url>      — queue video download (720p default)\n"
    "/hd <url>      — queue HD video download (1080p)\n"
    "/full <url>    — queue best available video download\n"
    "/audio <url>   — queue audio download\n"
    "/clip <url> <start> <end> — queue clipped video\n"
    "/ui <url>      — preview with buttons\n"
        "/rdl          — reply-download default video\n"
        "/rhd          — reply-download HD video\n"
        "/rfull        — reply-download best/full video\n"
        "/raudio       — reply-download audio\n"
        "/rui          — reply-open preview/buttons\n"
    "/queue         — show queue\n"
    "/weather <p>   — current weather\n"
    "/forecast <p>  — 5-day forecast\n"
    "/whoami        — show your Telegram/chat IDs\n"
    "`@Razi3l_bot weather <place>` — inline/mention weather\n"
    "`@Razi3l_bot forecast <place>` — inline/mention forecast"
)

ADMIN_COMMAND_LIST = (
    "/lastusers     — recent users seen in logs\n"
    "/stats         — usage summary\n"
    "/status        — bot status\n"
    "/groups        — list remembered groups\n"
    "/cleanup       — clear downloads folder\n"
    "/failures      — recent failures\n"
    "/retrylast     — retry last failure\n"
    "/reload        — reload config without restart\n"
    "/restart       — restart Raziel safely\n"
    "/clearqueue    — clear queue\n"
    "/leave         — leave current group\n"
    "/leavechat     — leave a group by ID\n"
    "/delete        — delete replied bot message\n"
    "/del           — alias for /delete\n"
    "/rm            — alias for /delete\n"
    "/shutdown      — stop the bot"
)

async def start_cmd(update: Update, _ctx: ContextTypes.DEFAULT_TYPE) -> None:
    remember_chat(update.effective_chat)

    user = update.effective_user
    chat = update.effective_chat

    lines = [
        f"👋 *{BOT_NAME} v{BOT_VERSION}*",
        "",
        "The watcher of links.",
        "",
        USER_COMMAND_LIST,
    ]

    if user and chat and is_admin(user.id):
        lines.extend([
            "",
            "*Admin Commands:*",
            ADMIN_COMMAND_LIST,
        ])

    await update.message.reply_text(
        "\n".join(lines),
        parse_mode=ParseMode.MARKDOWN,
    )

async def help_cmd(update: Update, _ctx: ContextTypes.DEFAULT_TYPE) -> None:
    remember_chat(update.effective_chat)

    user = update.effective_user
    chat = update.effective_chat

    user_id = user.id if user else 0
    chat_id = chat.id if chat else 0
    chat_type = chat.type if chat else "private"

    allowed_here = can_use_context(user_id, chat_id, chat_type)
    admin_here = is_admin(user_id)

    lines = [
        f"🎬 *{BOT_NAME} v{BOT_VERSION}*",
        "The watcher of links.",
        "",
        "Paste a supported media URL, or use `/ui <url>` for buttons.",
        "",
    ]

    if admin_here:
        lines.extend([
            "*User Commands:*",
            USER_COMMAND_LIST,
            "",
            "*Admin Commands:*",
            ADMIN_COMMAND_LIST,
        ])
    elif allowed_here:
        lines.extend([
            "*Available Commands:*",
            USER_COMMAND_LIST,
        ])
    else:
        lines.extend([
            "🚫 You are not allowed to use download features here.",
            "",
            "*Available Commands:*",
            "/help          — usage instructions\n"
            "/whoami        — show your Telegram/chat IDs\n"
            "/weather <p>   — current weather\n"
            "/forecast <p>  — 5-day forecast",
        ])

    await update.message.reply_text(
        "\n".join(lines),
        parse_mode=ParseMode.MARKDOWN,
    )

async def queue_video_command(
    update: Update,
    ctx: ContextTypes.DEFAULT_TYPE,
    quality: str = "default",
    label: str = "dl",
) -> None:
    remember_chat(update.effective_chat)

    if not can_use_context(
        update.effective_user.id,
        update.effective_chat.id,
        update.effective_chat.type,
    ):
        await update.message.reply_text("🚫 Not allowed here.")
        return

    url = extract_url(" ".join(ctx.args)) if ctx.args else None
    if not url:
        await update.message.reply_text(
            "❌ Invalid usage\n\n"
            f"Example:\n"
            f"/{label} https://example.com/video"
        )
        return

    if not is_supported_video_url(url):
        await update.message.reply_text("❌ Unsupported video source.")
        return

    job = create_job(
        update.effective_user.id,
        update.effective_chat.id,
        url,
        mode="video",
        source=label,
        reply_to_message_id=update.message.message_id if update.message else None,
        quality=quality,
        include_metadata=include_metadata,
    )
    QUEUE.append(job)
    save_queue_state()
    pos = get_queue_position()
    queue_msg = await update.message.reply_text(
        f"📥 Added to queue\n"
        f"🔢 Position: {pos}\n"
        f"🎬 Mode: video\n"
        f"📺 Quality: {get_quality_label(quality)}"
    )
    job["queue_message_id"] = queue_msg.message_id
    save_queue_state()

async def dl_cmd(update: Update, ctx: ContextTypes.DEFAULT_TYPE) -> None:
    await queue_video_command(update, ctx, quality="default", label="dl")

async def hd_cmd(update: Update, ctx: ContextTypes.DEFAULT_TYPE) -> None:
    await queue_video_command(update, ctx, quality="hd", label="hd")

async def full_cmd(update: Update, ctx: ContextTypes.DEFAULT_TYPE) -> None:
    await queue_video_command(update, ctx, quality="full", label="full")

async def audio_cmd(update: Update, ctx: ContextTypes.DEFAULT_TYPE) -> None:
    remember_chat(update.effective_chat)

    if not can_use_context(
        update.effective_user.id,
        update.effective_chat.id,
        update.effective_chat.type,
    ):
        await update.message.reply_text("🚫 Not allowed here.")
        return

    url = extract_url(" ".join(ctx.args)) if ctx.args else None
    if not url:
        await update.message.reply_text(
            "❌ Invalid usage\n\n"
            "Example:\n"
            "/audio https://example.com/video"
        )
        return

    if not is_supported_video_url(url):
        await update.message.reply_text("❌ Unsupported video source.")
        return

    if not await media_preflight_allows_queue(update.effective_message, url):
        return

    if not ffmpeg_exists():
        await update.message.reply_text("ffmpeg is required for audio extraction.")
        return

    job = create_job(
        update.effective_user.id,
        update.effective_chat.id,
        url,
        mode="audio",
        source="audio"
    )
    QUEUE.append(job)
    save_queue_state()
    pos = get_queue_position()
    queue_msg = await update.message.reply_text(
        f"📥 Added to queue\n"
        f"🔢 Position: {pos}\n"
        f"🎵 Mode: audio"
    )
    job["queue_message_id"] = queue_msg.message_id
    save_queue_state()

async def clip_cmd(update: Update, ctx: ContextTypes.DEFAULT_TYPE) -> None:
    remember_chat(update.effective_chat)

    if not can_use_context(
        update.effective_user.id,
        update.effective_chat.id,
        update.effective_chat.type,
    ):
        await update.message.reply_text("🚫 Not allowed here.")
        return

    if len(ctx.args) < 3:
        await update.message.reply_text(
            "❌ Invalid usage\n\n"
            "Example:\n"
            "/clip https://example.com/video 00:01:00 00:01:30"
        )
        return

    url = extract_url(ctx.args[0])
    if not url:
        await update.message.reply_text("That does not look like a valid URL.")
        return

    if not is_supported_video_url(url):
        await update.message.reply_text("❌ Unsupported video source.")
        return

    if not ffmpeg_exists():
        await update.message.reply_text("ffmpeg is required for clip creation.")
        return

    try:
        clip_start = normalize_timecode(ctx.args[1])
        clip_end = normalize_timecode(ctx.args[2])

        if timecode_to_seconds(clip_end) <= timecode_to_seconds(clip_start):
            await update.message.reply_text("End time must be after start time.")
            return
    except Exception as e:
        await update.message.reply_text(f"Clip time error: {e}")
        return

    job = create_job(
        update.effective_user.id,
        update.effective_chat.id,
        url,
        mode="clip",
        source="clip",
        reply_to_message_id=update.message.message_id if update.message else None,
        clip_start=clip_start,
        clip_end=clip_end,
        quality="default",
    )
    QUEUE.append(job)
    save_queue_state()

    pos = get_queue_position()
    queue_msg = await update.message.reply_text(
        f"✂️ Clip added to queue\n"
        f"🔢 Position: {pos}\n"
        f"{format_clip_range(clip_start, clip_end)}"
    )
    job["queue_message_id"] = queue_msg.message_id
    save_queue_state()

async def queue_cmd(update: Update, _ctx: ContextTypes.DEFAULT_TYPE) -> None:
    if not QUEUE and not CURRENT_JOB:
        await update.message.reply_text("Queue is empty.")
        return

    lines = ["📋 *Queue*"]
    if CURRENT_JOB:
        lines.extend([
            "",
            "*Now Processing:*",
            f"• `{CURRENT_JOB['url']}`",
            f"• mode: `{CURRENT_JOB.get('mode', 'video')}`",
            f"• quality: `{get_quality_label(CURRENT_JOB.get('quality', 'default'))}`",
        ])

    if QUEUE:
        lines.extend(["", "*Pending:*"])
        for idx, job in enumerate(QUEUE[:10], start=1):
            lines.append(
                f"{idx}. `{job['url']}` "
                f"[{job.get('mode', 'video')} / {get_quality_label(job.get('quality', 'default'))}]"
            )

    await update.message.reply_text("\n".join(lines), parse_mode=ParseMode.MARKDOWN)

async def weather_cmd(update: Update, ctx: ContextTypes.DEFAULT_TYPE) -> None:
    if not ctx.args:
        await update.message.reply_text(
            "❌ Invalid usage\n\n"
            "Example:\n"
            "/weather Kingsville"
        )
        return
    try:
        result = await asyncio.to_thread(get_current_weather_for_location, " ".join(ctx.args).strip())
        await update.message.reply_text(result, parse_mode=forecast_parse_mode(result))
    except Exception as e:
        await update.message.reply_text(f"Weather error: {e}")

async def forecast_cmd(update: Update, ctx: ContextTypes.DEFAULT_TYPE) -> None:
    if not ctx.args:
        await update.message.reply_text(
            "❌ Invalid usage\n\n"
            "Example:\n"
            "/forecast Kingsville"
        )
        return
    try:
        result = await asyncio.to_thread(get_5day_forecast_for_location, " ".join(ctx.args).strip())
        await update.message.reply_text(result, parse_mode=forecast_parse_mode(result))
    except Exception as e:
        await update.message.reply_text(f"Forecast error: {e}")

async def whoami_cmd(update: Update, _ctx: ContextTypes.DEFAULT_TYPE) -> None:
    user = update.effective_user
    chat = update.effective_chat
    await update.message.reply_text(
        f"🪪 *Who am I?*\n\n"
        f"*User:* {user.full_name if user else 'unknown'}\n"
        f"*Username:* {'@' + user.username if user and user.username else 'none'}\n"
        f"*User ID:* `{user.id if user else 'unknown'}`\n"
        f"*Chat:* {getattr(chat, 'title', None) or getattr(chat, 'full_name', None) or 'private'}\n"
        f"*Chat Type:* {chat.type if chat else 'unknown'}\n"
        f"*Chat ID:* `{chat.id if chat else 'unknown'}`\n"
        f"*Bot Owner:* {'yes' if is_admin(user.id) else 'no'}\n"
        f"*Can Download Here:* {'yes' if can_use_context(user.id, chat.id, chat.type) else 'no'}\n",
        parse_mode=ParseMode.MARKDOWN,
    )

async def lastusers_cmd(update: Update, _ctx: ContextTypes.DEFAULT_TYPE) -> None:
    if not is_admin(update.effective_user.id):
        return

    recent = parse_recent_users_from_logs(limit=10)
    if not recent:
        await update.message.reply_text("No recent users found in the log yet.")
        return

    lines = ["👥 *Recent users seen in logs*", ""]
    for idx, item in enumerate(recent, start=1):
        short_url = shorten_url(item["url"])
        lines.append(
            f"{idx}. 👤 `{item['user_id']}`\n"
            f"   💬 `{item['chat_id']}`\n"
            f"   🕒 `{item['timestamp']}`\n"
            f"   🔗 `{short_url}`"
        )

    await update.message.reply_text("\n\n".join(lines), parse_mode=ParseMode.MARKDOWN)

async def stats_cmd(update: Update, _ctx: ContextTypes.DEFAULT_TYPE) -> None:
    if not is_admin(update.effective_user.id):
        return

    unique_users = len({h["user"] for h in HISTORY if "user" in h})
    top_domains = get_top_domains()
    last_seen = get_most_recent_download_timestamp()

    lines = [
        "📊 *Bot Stats*",
        "",
        "🧠 *System*",
        f"• Mode: {'Public' if ALLOW_ALL_USERS else 'Restricted'}",
        f"• Active Job: {'Yes' if CURRENT_JOB else 'No'}",
        f"• Queue: {len(QUEUE)}",
        "",
        "📦 *Activity*",
        f"• Completed: {len(HISTORY)}",
        f"• Failed: {len(FAILURES)}",
        f"• Unique Users: {unique_users}",
        f"• Requests (recent): {count_download_requests_in_logs()}",
        f"• Last Activity: `{last_seen}`" if last_seen else "• Last Activity: none",
        "",
        "💾 *Storage*",
        f"• Files: {get_download_folder_count()}",
        f"• Size: {format_size(get_download_folder_size())}",
        "",
        "🌐 *Top Domains*",
    ]

    if top_domains:
        for domain, count in top_domains:
            lines.append(f"• `{domain}` — {count}")
    else:
        lines.append("• none yet")

    await update.message.reply_text("\n".join(lines), parse_mode=ParseMode.MARKDOWN)

async def status_cmd(update: Update, _ctx: ContextTypes.DEFAULT_TYPE) -> None:
    if not is_admin(update.effective_user.id):
        return

    allowed_chat_ids = set(getattr(ytbotrc, "ALLOWED_CHAT_IDS", []))

    await update.message.reply_text(
        f"*Bot Status:* online\n"
        f"*Current Job:* {'yes' if CURRENT_JOB else 'no'}\n"
        f"*Queue Length:* {len(QUEUE)}\n"
        f"*Watched Groups:* {', '.join(str(i) for i in allowed_chat_ids) if allowed_chat_ids else 'none'}\n"
        f"*Archive Chat:* {ARCHIVE_CHAT_ID if ARCHIVE_CHAT_ID else 'none'}\n"
        f"*Watch Folder:* {WATCH_FOLDER_ENABLED}\n"
        f"*Download Timeout:* {DOWNLOAD_TIMEOUT}s\n"
        f"*Telegram Upload Timeout:* {TELEGRAM_UPLOAD_TIMEOUT}s\n"
        f"*Debug Mode:* {DEBUG_MODE}\n"
        f"*Dedupe:* {DEDUP_ENABLED} ({DEDUP_TTL_HOURS}h TTL)\n"
        f"*Default Video Height:* {DEFAULT_VIDEO_HEIGHT}p\n"
        f"*HD Video Height:* {HD_VIDEO_HEIGHT}p\n"
        f"*Legacy Max Video Height:* {MAX_VIDEO_HEIGHT}p\n"
        f"*Prefer MP4:* {PREFER_MP4}\n"
        f"*Enabled Platforms:* {', '.join(ENABLED_VIDEO_PLATFORMS)}\n"
        f"*Supported Video Domains:* {', '.join(SUPPORTED_VIDEO_DOMAINS)}\n"
        f"*Extra Video Domains:* {', '.join(EXTRA_VIDEO_DOMAINS) if EXTRA_VIDEO_DOMAINS else 'none'}\n"
        f"*ffmpeg:* {ffmpeg_exists()}\n"
        f"*ffprobe:* {ffprobe_exists()}\n"
        f"*YouTube Cookies:* {'yes' if YOUTUBE_COOKIES_FILE.exists() else 'no'}",
        parse_mode=ParseMode.MARKDOWN,
    )

async def groups_cmd(update: Update, _ctx: ContextTypes.DEFAULT_TYPE) -> None:
    if not is_admin(update.effective_user.id):
        return
    if not is_private_chat(update):
        await update.message.reply_text("ℹ️ Use this command in a private chat with me.")
        return
    if not KNOWN_CHATS:
        await update.message.reply_text("No remembered groups or channels yet.")
        return
    lines = ["*Remembered groups/channels:*"]
    for _, c in sorted(KNOWN_CHATS.items(), key=lambda kv: kv[1]["title"].lower()):
        lines.append(f'`{c["id"]}` — {c["title"]} ({c["type"]})')
    lines += ["", "Use `/leavechat <chat_id>` to leave one."]
    await update.message.reply_text("\n".join(lines), parse_mode=ParseMode.MARKDOWN)

async def cleanup_cmd(update: Update, _ctx: ContextTypes.DEFAULT_TYPE) -> None:
    if not is_admin(update.effective_user.id):
        return
    cleared = 0
    freed = 0
    for p in DOWNLOAD_DIR.iterdir():
        if p.is_file():
            freed += p.stat().st_size
            p.unlink()
            cleared += 1
    await update.message.reply_text(
        f"🧹 Cleanup complete.\nDeleted: {cleared}\nFreed: {format_size(freed)}"
    )

async def failures_cmd(update: Update, _ctx: ContextTypes.DEFAULT_TYPE) -> None:
    if not is_admin(update.effective_user.id):
        return
    if not FAILURES:
        await update.message.reply_text("No failures.")
        return

    lines = ["❌ *Recent Failures*", ""]
    for item in FAILURES[-5:]:
        lines.append(
            f"*URL:* `{item.get('url', 'unknown')}`\n"
            f"*Mode:* `{item.get('mode', 'video')}`\n"
            f"*Error:* `{item.get('error', 'unknown')}`"
        )
        lines.append("")

    await update.message.reply_text("\n".join(lines), parse_mode=ParseMode.MARKDOWN)

async def retrylast_cmd(update: Update, _ctx: ContextTypes.DEFAULT_TYPE) -> None:
    if not is_admin(update.effective_user.id):
        return
    if not FAILURES:
        await update.message.reply_text("No failures.")
        return

    last = FAILURES[-1].copy()
    last["id"] = str(uuid.uuid4())
    last["time"] = time.time()
    last.pop("error", None)
    last.pop("failed_time", None)
    last["source"] = "retry"

    QUEUE.append(last)
    save_queue_state()

    pos = get_queue_position()
    await update.message.reply_text(
        f"🔁 Retrying last failure.\n"
        f"🔢 Position: {pos}"
    )



async def restart_cmd(update: Update, _ctx: ContextTypes.DEFAULT_TYPE) -> None:
    if not is_admin(update.effective_user.id):
        return

    if has_active_jobs():
        await update.message.reply_text(
            "⚠️ Cannot restart while Raziel is busy.\n"
            "Queue or current job is active."
        )
        return

    await update.message.reply_text(
        f"🔄 {BOT_NAME} v{BOT_VERSION} restarting..."
    )

    try:
        log.warning("Restart requested by admin %s", update.effective_user.id)
        log.warning("Restarting Raziel via os.execv...")
    except Exception:
        pass

    await asyncio.sleep(2)

    os.execv(sys.executable, [sys.executable] + sys.argv)


async def reload_cmd(update: Update, _ctx: ContextTypes.DEFAULT_TYPE) -> None:
    if not is_admin(update.effective_user.id):
        return

    try:
        reload_runtime_config()

        await update.message.reply_text(
            f"♻️ *{BOT_NAME} v{BOT_VERSION} reloaded*\n\n"
            f"*Config:* `{CONFIG_FILE}`\n"
            f"*Debug Mode:* `{DEBUG_MODE}`\n"
            f"*Download Timeout:* `{DOWNLOAD_TIMEOUT}s`\n"
            f"*Telegram Upload Timeout:* `{TELEGRAM_UPLOAD_TIMEOUT}s`\n"
            f"*Default Quality:* `{DEFAULT_VIDEO_HEIGHT}p`\n"
            f"*HD Quality:* `{HD_VIDEO_HEIGHT}p`\n"
            f"*Validation Mode:* `{'strict' if STRICT_PLATFORM_VALIDATION else 'open yt-dlp'}`\n"
            f"*Enabled Platforms:* `{', '.join(ENABLED_VIDEO_PLATFORMS)}`\n"
            f"*Supported Domains:* `{', '.join(SUPPORTED_VIDEO_DOMAINS)}`",
            parse_mode=ParseMode.MARKDOWN,
        )
    except Exception as e:
        log.exception("Config reload failed")
        await update.message.reply_text(
            f"❌ *Reload failed*\n\n`{str(e)[:500]}`",
            parse_mode=ParseMode.MARKDOWN,
        )


async def clearqueue_cmd(update: Update, _ctx: ContextTypes.DEFAULT_TYPE) -> None:
    if not is_admin(update.effective_user.id):
        return
    QUEUE.clear()
    save_queue_state()
    await update.message.reply_text("🧹 Queue cleared.")

async def leave_cmd(update: Update, ctx: ContextTypes.DEFAULT_TYPE) -> None:
    if not is_admin(update.effective_user.id):
        return
    chat = update.effective_chat
    if not chat:
        return
    if is_private_chat(update):
        await update.message.reply_text("ℹ️ Use /leavechat from private chat instead.")
        return
    await update.message.reply_text("Leaving current group…")
    await ctx.bot.leave_chat(chat.id)
    forget_chat(chat.id)

async def leavechat_cmd(update: Update, ctx: ContextTypes.DEFAULT_TYPE) -> None:
    if not is_admin(update.effective_user.id):
        return
    if not is_private_chat(update):
        await update.message.reply_text("ℹ️ Use this command in a private chat with me.")
        return
    if not ctx.args:
        await update.message.reply_text(
            "❌ Invalid usage\n\n"
            "Example:\n"
            "/leavechat -1001234567890"
        )
        return
    try:
        target_id = int(ctx.args[0])
    except ValueError:
        await update.message.reply_text("Chat ID must be numeric.")
        return

    if str(target_id) not in KNOWN_CHATS:
        await update.message.reply_text(
            "⚠️ That chat ID isn't in my remembered list.\n"
            "Use /groups to see known chats first."
        )
        return

    chat_info = KNOWN_CHATS[str(target_id)]
    await update.message.reply_text(
        f"Leaving `{chat_info['title']}` (`{target_id}`)",
        parse_mode=ParseMode.MARKDOWN,
    )
    await ctx.bot.leave_chat(target_id)
    forget_chat(target_id)

async def shutdown_cmd(update: Update, ctx: ContextTypes.DEFAULT_TYPE) -> None:
    if not is_admin(update.effective_user.id):
        return
    await update.message.reply_text("🛑 Shutting down…")
    await ctx.application.stop()


# ── Track group joins/leaves ────────────────────────────────────────────────────
async def track_chat_member(update: Update, _ctx: ContextTypes.DEFAULT_TYPE) -> None:
    cmu = update.my_chat_member
    if not cmu:
        return
    new_status = cmu.new_chat_member.status
    if new_status in ("member", "administrator"):
        remember_chat(cmu.chat)
    elif new_status in ("left", "kicked"):
        forget_chat(cmu.chat.id)


# ── Message handler for raw/shared/forwarded URLs ───────────────────────────────
async def handle_url(update: Update, _ctx: ContextTypes.DEFAULT_TYPE) -> None:
    message = update.message
    if not message:
        return

    if message_has_native_telegram_media(message):
        if DEBUG_MODE:
            log.info("Telegram-native media message ignored for passive auto-watch.")
        return

    remember_chat(update.effective_chat)

    if auto_watch_disabled_for_chat(update.effective_chat):
        if DEBUG_MODE:
            log.info("Auto-watch disabled for chat %s; passive link ignored.", update.effective_chat.id)
        return

    if await run_mention_command(update, _ctx):
        return

    user = update.effective_user
    chat = update.effective_chat

    if user and getattr(user, "is_bot", False):
        return


    # Forward-safe ingestion:
    # If a user forwards one of Raziel's uploaded videos/posts into a watched group,
    # the forwarded caption may still contain the original source URL.
    # That is inherited bot output, not fresh user intent, so ignore it.
    if is_forwarded_bot_output(message):
        if DEBUG_MODE:
            log.info("Forwarded bot/Raziel output ignored.")
        return

    if not user or not chat:
        return

    if not can_use_context(user.id, chat.id, chat.type):
        return

    if DEBUG_MODE:
        log.info(
            "WATCH HIT chat=%s type=%s text=%r caption=%r entities=%r caption_entities=%r",
            chat.id,
            chat.type,
            getattr(message, "text", None),
            getattr(message, "caption", None),
            getattr(message, "entities", None),
            getattr(message, "caption_entities", None),
        )

    url = None

    # ── 1. Plain text
    if message.text:
        url = extract_url(message.text)

    # ── 2. Caption (shared previews use this)
    if not url and message.caption:
        url = extract_url(message.caption)

    # ── 3. Entities (text_link + url)
    if not url:
        for ent in (message.entities or []) + (message.caption_entities or []):
            if getattr(ent, "url", None):
                url = ent.url
                break

            if getattr(ent, "type", None) == "url":
                try:
                    source = message.text or message.caption or ""
                    candidate = source[ent.offset: ent.offset + ent.length]
                    u = extract_url(candidate)
                    if u:
                        url = u
                        break
                except Exception:
                    pass

    # ── 4. Reply guard + raw fallback (forwarded weird cases)
    # If this is a reply and the NEW message itself did not contain a direct URL,
    # ignore it. Telegram may include the replied-to media caption/link in the
    # payload, which can otherwise requeue Raziel's own uploaded video.
    if not url and getattr(message, "reply_to_message", None):
        if DEBUG_MODE:
            log.info("Reply with no new direct URL ignored.")
        return

    if not url:
        try:
            raw = message.to_dict()
            if isinstance(raw, dict):
                raw.pop("reply_to_message", None)

            for v in str(raw).split():
                u = extract_url(v)
                if u:
                    url = u
                    break
        except Exception:
            pass

    if not url:
        return

    if not is_supported_video_url(url):
        if DEBUG_MODE:
            log.info("Ignored unsupported/non-video URL: %s", url)
        return

    if DEBUG_MODE:
        log.info("URL DETECTED: %s", url)

    if is_duplicate_url(url):
        if DEBUG_MODE:
            log.info("Duplicate URL ignored: %s", url)
        return

    pos = get_queue_position()

    queue_msg = await message.reply_text(
        f"📥 Added to queue\n"
        f"🔢 Position: {pos}\n"
        f"🎬 Mode: video\n"
        f"📺 Quality: {get_quality_label('default')}"
    )

    job = create_job(
        user.id,
        chat.id,
        url,
        mode="video",
        source="raw_url",
        reply_to_message_id=message.message_id,
        quality="default",
    )
    job["queue_message_id"] = queue_msg.message_id

    QUEUE.append(job)
    save_queue_state()


# ── CLI mode ────────────────────────────────────────────────────────────────────
def run_cli(url: str, mode: str = "video") -> None:
    print(f"Downloading {mode}: {url}")
    path = download_media(url, mode, "default")
    print(f"Downloaded: {path}")
    routed = route_file(path, "audio" if mode == "audio" else "video")
    print(f"Saved to: {routed}")


# ── Main ────────────────────────────────────────────────────────────────────────


async def rdl_cmd(update: Update, context: ContextTypes.DEFAULT_TYPE):
    await handle_reply_download_command(update, context, mode="video", quality="default")


async def rhd_cmd(update: Update, context: ContextTypes.DEFAULT_TYPE):
    await handle_reply_download_command(update, context, mode="video", quality="hd")


async def rfull_cmd(update: Update, context: ContextTypes.DEFAULT_TYPE):
    await handle_reply_download_command(update, context, mode="video", quality="full")


async def raudio_cmd(update: Update, context: ContextTypes.DEFAULT_TYPE):
    await handle_reply_download_command(update, context, mode="audio", quality="default")


async def rui_cmd(update: Update, context: ContextTypes.DEFAULT_TYPE):
    await handle_reply_download_command(update, context, mode="video", quality="default", use_ui=True)


async def delete_reply_cmd(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """
    Delete a replied-to message, then delete the cleanup command itself.

    Usage:
    Reply to a Raziel/bot message with:
    /delete
    /del
    /rm
    """
    message = update.effective_message
    user = update.effective_user
    chat = update.effective_chat

    if not message or not user or not chat:
        return

    if not can_use_context(user.id, chat.id, chat.type):
        return

    reply = getattr(message, "reply_to_message", None)

    if not reply:
        await send_temporary_reply(message, "Reply to a Raziel message with /delete.")
        asyncio.create_task(delete_command_message_later(message, delay=2.0))
        return

    try:
        await reply.delete()
    except Exception:
        await send_temporary_reply(message, "❌ Could not delete that message.")
        asyncio.create_task(delete_command_message_later(message, delay=2.0))
        return

    asyncio.create_task(delete_command_message_later(message, delay=0.5))



def build_app():
    request = HTTPXRequest(
        connect_timeout=30,
        read_timeout=TELEGRAM_UPLOAD_TIMEOUT,
        write_timeout=TELEGRAM_UPLOAD_TIMEOUT,
        pool_timeout=30,
    )

    builder = (
        ApplicationBuilder()
        .token(BOT_TOKEN)
        .request(request)
    )

    if LOCAL_BOT_API_URL:
        builder = builder.base_url(LOCAL_BOT_API_URL)

    if LOCAL_BOT_API_FILE_URL:
        builder = builder.base_file_url(LOCAL_BOT_API_FILE_URL)

    app = builder.build()

    app.add_handler(InlineQueryHandler(inline_query_cmd))
    app.add_handler(CommandHandler("start", start_cmd))
    app.add_handler(CommandHandler("help", help_cmd))

    # ── Reply-driven commands ───────────────────────────────
    app.add_handler(CommandHandler("rdl", rdl_cmd))
    app.add_handler(CommandHandler("rhd", rhd_cmd))
    app.add_handler(CommandHandler("rfull", rfull_cmd))
    app.add_handler(CommandHandler("raudio", raudio_cmd))
    app.add_handler(CommandHandler("rui", rui_cmd))

    # ── Manual cleanup commands ─────────────────────────────
    app.add_handler(CommandHandler("delete", delete_reply_cmd))
    app.add_handler(CommandHandler("del", delete_reply_cmd))
    app.add_handler(CommandHandler("rm", delete_reply_cmd))
    app.add_handler(CommandHandler("dl", dl_cmd))
    app.add_handler(CommandHandler("hd", hd_cmd))
    app.add_handler(CommandHandler("full", full_cmd))
    app.add_handler(CommandHandler("audio", audio_cmd))
    app.add_handler(CommandHandler("dlmeta", dlmeta_cmd))
    app.add_handler(CommandHandler("hdmeta", hdmeta_cmd))
    app.add_handler(CommandHandler("fullmeta", fullmeta_cmd))
    app.add_handler(CommandHandler("audiometa", audiometa_cmd))
    app.add_handler(CommandHandler("rdlmeta", rdlmeta_cmd))
    app.add_handler(CommandHandler("rhdmeta", rhdmeta_cmd))
    app.add_handler(CommandHandler("rfullmeta", rfullmeta_cmd))
    app.add_handler(CommandHandler("raudiometa", raudiometa_cmd))
    app.add_handler(CommandHandler("clip", clip_cmd))
    app.add_handler(CommandHandler("ui", ui_cmd))
    app.add_handler(CommandHandler("queue", queue_cmd))
    app.add_handler(CommandHandler("weather", weather_cmd))
    app.add_handler(CommandHandler("forecast", forecast_cmd))
    app.add_handler(CommandHandler("whoami", whoami_cmd))
    app.add_handler(CommandHandler("lastusers", lastusers_cmd))
    app.add_handler(CommandHandler("stats", stats_cmd))
    app.add_handler(CommandHandler("status", status_cmd))
    app.add_handler(CommandHandler("groups", groups_cmd))
    app.add_handler(CommandHandler("cleanup", cleanup_cmd))
    app.add_handler(CommandHandler("failures", failures_cmd))
    app.add_handler(CommandHandler("retrylast", retrylast_cmd))
    app.add_handler(CommandHandler("reload", reload_cmd))
    app.add_handler(CommandHandler("restart", restart_cmd))
    app.add_handler(CommandHandler("clearqueue", clearqueue_cmd))
    app.add_handler(CommandHandler("leave", leave_cmd))
    app.add_handler(CommandHandler("leavechat", leavechat_cmd))
    app.add_handler(CommandHandler("shutdown", shutdown_cmd))

    app.add_handler(CallbackQueryHandler(ui_button_cb, pattern=r"^dl\|"))
    app.add_handler(ChatMemberHandler(track_chat_member, ChatMemberHandler.MY_CHAT_MEMBER))
    app.add_handler(MessageHandler(filters.ALL & ~filters.COMMAND, handle_url))

    async def on_start(app_instance):
        asyncio.create_task(queue_worker(app_instance))
        asyncio.create_task(watch_folder_worker())

    app.post_init = on_start
    return app


async def mention_cmd(update: Update, ctx: ContextTypes.DEFAULT_TYPE) -> None:
    """
    Group-friendly natural command layer.

    Allows:
    @Raziel weather Houston
    @Raziel forecast Houston
    @Raziel queue
    @Raziel status
    @Raziel help
    """
    remember_chat(update.effective_chat)

    message = update.effective_message
    user = update.effective_user
    chat = update.effective_chat

    if not message or not user or not chat:
        return

    if getattr(user, "is_bot", False):
        return

    parsed = parse_mention_command(getattr(message, "text", None) or getattr(message, "caption", None))
    if not parsed:
        return

    command, args = parsed
    user_id = user.id
    chat_id = chat.id
    chat_type = chat.type

    allowed_here = can_use_context(user_id, chat_id, chat_type)
    admin_here = is_admin(user_id)

    try:
        if command == "weather":
            if not args:
                await send_temporary_reply(message, "Usage: @Raziel weather Houston")
                return
            result = await asyncio.to_thread(get_current_weather_for_location, args)
            await message.reply_text(result, parse_mode=forecast_parse_mode(result))
            return

        if command == "forecast":
            if not args:
                await send_temporary_reply(message, "Usage: @Raziel forecast Houston")
                return
            result = await asyncio.to_thread(get_5day_forecast_for_location, args)
            await message.reply_text(result, parse_mode=forecast_parse_mode(result))
            return

        if command == "queue":
            if not QUEUE and not CURRENT_JOB:
                await message.reply_text("Queue is empty.")
                return

            lines = ["📋 *Queue*"]
            if CURRENT_JOB:
                lines.extend([
                    "",
                    "*Now Processing:*",
                    f"• `{CURRENT_JOB['url']}`",
                    f"• mode: `{CURRENT_JOB.get('mode', 'video')}`",
                    f"• quality: `{get_quality_label(CURRENT_JOB.get('quality', 'default'))}`",
                ])

            if QUEUE:
                lines.extend(["", "*Pending:*"])
                for idx, job in enumerate(QUEUE[:10], start=1):
                    lines.append(
                        f"{idx}. `{job['url']}` "
                        f"[{job.get('mode', 'video')} / {get_quality_label(job.get('quality', 'default'))}]"
                    )

            await message.reply_text("\n".join(lines), parse_mode=ParseMode.MARKDOWN)
            return

        if command == "help":
            lines = [
                f"🎬 *{BOT_NAME} v{BOT_VERSION}*",
                "The watcher of links.",
                "",
                "*Mention Commands:*",
                "@Raziel weather <place>",
                "@Raziel forecast <place>",
                "@Raziel queue",
                "@Raziel help",
            ]

            if admin_here:
                lines.extend([
                    "",
                    "*Admin Mentions:*",
                    "@Raziel status",
                    "@Raziel stats",
                    "@Raziel reload",
                    "@Raziel restart",
                ])

            await message.reply_text("\n".join(lines), parse_mode=ParseMode.MARKDOWN)
            return

        if command == "status":
            if not admin_here:
                return
            await message.reply_text(
                f"*Bot Status:* online\n"
                f"*Current Job:* {'yes' if CURRENT_JOB else 'no'}\n"
                f"*Queue Length:* {len(QUEUE)}\n"
                f"*Debug Mode:* {DEBUG_MODE}\n"
                f"*Dedupe:* {DEDUP_ENABLED} ({DEDUP_TTL_HOURS}h TTL)\n"
                f"*Enabled Platforms:* {', '.join(ENABLED_VIDEO_PLATFORMS)}\n"
                f"*Supported Domains:* {', '.join(SUPPORTED_VIDEO_DOMAINS)}",
                parse_mode=ParseMode.MARKDOWN,
            )
            return

        if command == "stats":
            if not admin_here:
                return
            unique_users = len({h["user"] for h in HISTORY if "user" in h})
            await message.reply_text(
                f"📊 *{BOT_NAME} Stats*\n\n"
                f"• Queue: {len(QUEUE)}\n"
                f"• Active Job: {'yes' if CURRENT_JOB else 'no'}\n"
                f"• Completed: {len(HISTORY)}\n"
                f"• Failed: {len(FAILURES)}\n"
                f"• Unique Users: {unique_users}",
                parse_mode=ParseMode.MARKDOWN,
            )
            return

        if command == "reload":
            if not admin_here:
                return
            reload_runtime_config()
            await message.reply_text(
                f"♻️ *{BOT_NAME} v{BOT_VERSION} reloaded*\n\n"
                f"*Debug Mode:* `{DEBUG_MODE}`\n"
                f"*Validation Mode:* `{'strict' if STRICT_PLATFORM_VALIDATION else 'open yt-dlp'}`\n"
                f"*Enabled Platforms:* `{', '.join(ENABLED_VIDEO_PLATFORMS)}`\n"
                f"*Supported Domains:* `{', '.join(SUPPORTED_VIDEO_DOMAINS)}`",
                parse_mode=ParseMode.MARKDOWN,
            )
            return

        if command == "restart":
            if not admin_here:
                return

            if CURRENT_JOB or QUEUE:
                await message.reply_text(
                    "⚠️ Cannot restart while Raziel is busy.\n"
                    "Queue or current job is active."
                )
                return

            await message.reply_text(f"🔄 {BOT_NAME} v{BOT_VERSION} restarting...")
            log.warning("Mention restart requested by admin %s", user_id)
            await asyncio.sleep(2)
            os.execv(sys.executable, [sys.executable] + sys.argv)

        # Unknown mention command: stay quiet to avoid being annoying in groups.
        return

    except Exception as e:
        log.exception("Mention command failed: %s", command)
        await message.reply_text(f"❌ {str(e)[:300]}")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--url", help="Download one URL from CLI")
    parser.add_argument("--audio", help="Download one URL as audio from CLI")
    args = parser.parse_args()

    if args.url:
        run_cli(args.url, mode="video")
        return
    if args.audio:
        run_cli(args.audio, mode="audio")
        return

    app = build_app()
    log.info(
        "Bot starting… owner=%s allow_all=%s base_dir=%s archive_chat=%s watch_folder=%s timeout=%s",
        OWNER_ID,
        ALLOW_ALL_USERS,
        BASE_DIR,
        ARCHIVE_CHAT_ID if ARCHIVE_CHAT_ID else "none",
        WATCH_FOLDER_ENABLED,
        DOWNLOAD_TIMEOUT,
    )
    if not SUPPORTED_VIDEO_DOMAINS:
        log.warning(
            "No supported video domains are enabled. "
            "Set ENABLED_VIDEO_PLATFORMS or EXTRA_VIDEO_DOMAINS in ytbotrc.py."
        )
    log_startup_checks()
    app.run_polling()

if __name__ == "__main__":
    main()