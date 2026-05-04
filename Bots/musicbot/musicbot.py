#!/usr/bin/env python3
# ------------------------------------------------------------
# file:     musicbot.py
# author:   Mike Redd
# version:  1.7
# created:  2026-05-03
# updated:  2026-05-03
# desc:     Sandalphon - Queue system + audio caching + metadata caching
# ------------------------------------------------------------

import asyncio
import hashlib
import json
import logging
import re
import shutil
import subprocess
import sys
import time
import uuid
from collections import deque
from pathlib import Path

from telegram import Update
from telegram.ext import Application, CommandHandler, ContextTypes, MessageHandler, filters

# ── Branding ─────────────────────────────────────────────────
BOT_NAME = "Sandalphon"
BOT_VERSION = "1.7"

# ── Config ───────────────────────────────────────────────────
sys.path.insert(0, str(Path.home() / "bots/config"))
import musicbotrc as cfg  # noqa: E402

BOT_TOKEN = cfg.BOT_TOKEN

DOWNLOAD_DIR = Path(cfg.DOWNLOAD_DIR)
DOWNLOAD_DIR.mkdir(parents=True, exist_ok=True)

MAX_FILE_MB = int(getattr(cfg, "MAX_FILE_MB", 1900))

# Optional cache config
CACHE_ENABLED = bool(getattr(cfg, "CACHE_ENABLED", True))
CACHE_DIR = Path(getattr(cfg, "CACHE_DIR", "/mnt/nvme1/work/bots/cache/musicbot"))
CACHE_AUDIO_DIR = CACHE_DIR / "audio"
CACHE_INDEX_FILE = CACHE_DIR / "index.json"
METADATA_CACHE_FILE = CACHE_DIR / "metadata.json"

if CACHE_ENABLED:
    CACHE_AUDIO_DIR.mkdir(parents=True, exist_ok=True)
    CACHE_INDEX_FILE.parent.mkdir(parents=True, exist_ok=True)

# ── Queue System ─────────────────────────────────────────────
QUEUE = deque()
PROCESSING = False

# ── Helpers ──────────────────────────────────────────────────
def run_cmd(cmd):
    logging.info("Running: %s", " ".join(str(x) for x in cmd))
    return subprocess.run(
        cmd,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        check=False,
    )


def file_size_mb(path):
    return path.stat().st_size / (1024 * 1024)


def clean_title(title):
    title = title.replace("_", " ")

    junk_patterns = [
        r"\(\s*official\s+music\s+video\s*\)",
        r"\[\s*official\s+music\s+video\s*\]",
        r"\(\s*official\s+video\s*\)",
        r"\[\s*official\s+video\s*\]",
        r"\(\s*official\s+audio\s*\)",
        r"\[\s*official\s+audio\s*\]",
        r"\(\s*lyrics?\s*\)",
        r"\[\s*lyrics?\s*\]",
        r"\(\s*visualizer\s*\)",
        r"\[\s*visualizer\s*\]",
        r"\bofficial\s+music\s+video\b",
        r"\bofficial\s+video\b",
        r"\bofficial\s+audio\b",
        r"\blyric\s+video\b",
        r"\blyrics\b",
        r"\bvisualizer\b",
        r"\bHD\b",
        r"\b4K\b",
    ]

    for pattern in junk_patterns:
        title = re.sub(pattern, "", title, flags=re.IGNORECASE)

    title = re.sub(r"\s*[–—]\s*", " - ", title)
    title = re.sub(r"\s+", " ", title).strip(" -")

    parts = [p.strip() for p in title.split(" - ") if p.strip()]

    if len(parts) >= 3 and parts[0].lower() == parts[1].lower():
        parts = [parts[0], *parts[2:]]

    if len(parts) > 2:
        parts = parts[:2]

    title = " - ".join(parts) if parts else title
    title = re.sub(r"\s+", " ", title).strip(" -")

    return title[:120] or "audio"


def force_artist_song_title(query, title):
    """
    Always prefer "Band/Artist - Song" for Telegram sends.

    If yt-dlp/cache only gives the song title, use the user's command text
    as the fallback artist source when it was typed as "Artist - Song".
    """
    query = clean_title(query or "")
    title = clean_title(title or "")

    if " - " in title:
        return title

    if " - " in query:
        artist, query_song = [p.strip() for p in query.split(" - ", 1)]

        if artist and title:
            return clean_title(f"{artist} - {title}")

        if artist and query_song:
            return clean_title(f"{artist} - {query_song}")

    return title


def load_metadata_cache():
    if not CACHE_ENABLED or not METADATA_CACHE_FILE.exists():
        return {}

    try:
        return json.loads(METADATA_CACHE_FILE.read_text(encoding="utf-8"))
    except Exception:
        logging.exception("Failed to read metadata cache")
        return {}


def save_metadata_cache(index):
    if not CACHE_ENABLED:
        return

    try:
        tmp = METADATA_CACHE_FILE.with_suffix(".tmp")
        tmp.write_text(json.dumps(index, indent=2, sort_keys=True), encoding="utf-8")
        tmp.replace(METADATA_CACHE_FILE)
    except Exception:
        logging.exception("Failed to write metadata cache")


def get_cached_metadata(query):
    if not CACHE_ENABLED:
        return None

    index = load_metadata_cache()
    key = cache_key(query)
    item = index.get(key)

    if not item:
        return None

    item["hits"] = int(item.get("hits", 0)) + 1
    item["last_used"] = int(time.time())
    index[key] = item
    save_metadata_cache(index)

    return item.get("metadata")


def add_metadata_to_cache(query, metadata):
    if not CACHE_ENABLED or not metadata:
        return metadata

    index = load_metadata_cache()
    key = cache_key(query)

    index[key] = {
        "query": query,
        "metadata": metadata,
        "created": int(time.time()),
        "last_used": int(time.time()),
        "hits": int(index.get(key, {}).get("hits", 0)),
    }

    save_metadata_cache(index)
    return metadata


def get_media_metadata(query):
    """
    Read metadata from yt-dlp JSON so we can use real artist/title when available
    instead of relying only on filenames.

    v1.7 caches metadata so repeated requests do not need another yt-dlp
    metadata lookup.
    """
    query = (query or "").strip()

    cached_meta = get_cached_metadata(query)
    if cached_meta:
        return cached_meta

    target = f"ytsearch1:{query}" if not query.startswith("http") else query

    cmd = [
        "yt-dlp",
        "--dump-json",
        "--no-playlist",
        target,
    ]

    result = run_cmd(cmd)

    if result.returncode != 0 or not result.stdout.strip():
        return None

    try:
        first_json_line = result.stdout.strip().splitlines()[0]
        data = json.loads(first_json_line)
    except Exception:
        logging.exception("Failed to parse yt-dlp metadata JSON")
        return None

    artist = (
        data.get("artist")
        or data.get("creator")
        or data.get("uploader")
        or data.get("channel")
        or ""
    )

    title = (
        data.get("track")
        or data.get("title")
        or ""
    )

    album = data.get("album") or ""
    year = str(data.get("release_year") or data.get("upload_date", "")[:4] or "")

    artist = clean_title(artist)
    title = clean_title(title)

    if not title:
        return None

    metadata = {
        "artist": artist,
        "title": title,
        "album": album,
        "year": year,
        "display": clean_title(f"{artist} - {title}") if artist else title,
    }

    return add_metadata_to_cache(query, metadata)


def build_title_from_metadata(query, fallback_title):
    """
    Prefer yt-dlp metadata. Fall back to query-driven Artist - Song formatting.
    """
    meta = get_media_metadata(query)

    if meta and meta.get("display"):
        return meta["display"]

    return force_artist_song_title(query, fallback_title)



def safe_filename(name):
    name = re.sub(r'[\\/:*?"<>|]', "-", name)
    name = re.sub(r"\s+", " ", name).strip()
    return name[:180] or "audio"


def normalize_query(query):
    return re.sub(r"\s+", " ", query.strip()).lower()


def cache_key(query):
    return hashlib.sha256(normalize_query(query).encode("utf-8")).hexdigest()


def load_cache_index():
    if not CACHE_ENABLED or not CACHE_INDEX_FILE.exists():
        return {}

    try:
        return json.loads(CACHE_INDEX_FILE.read_text(encoding="utf-8"))
    except Exception:
        logging.exception("Failed to read cache index")
        return {}


def save_cache_index(index):
    if not CACHE_ENABLED:
        return

    try:
        tmp = CACHE_INDEX_FILE.with_suffix(".tmp")
        tmp.write_text(json.dumps(index, indent=2, sort_keys=True), encoding="utf-8")
        tmp.replace(CACHE_INDEX_FILE)
    except Exception:
        logging.exception("Failed to write cache index")


def get_cached_audio(query):
    if not CACHE_ENABLED:
        return None

    index = load_cache_index()
    key = cache_key(query)
    item = index.get(key)

    if not item:
        return None

    path = Path(item.get("path", ""))

    if not path.exists():
        index.pop(key, None)
        save_cache_index(index)
        return None

    item["hits"] = int(item.get("hits", 0)) + 1
    item["last_used"] = int(time.time())
    index[key] = item
    save_cache_index(index)

    return path


def get_cached_title_by_path(audio_path):
    if not CACHE_ENABLED or not audio_path:
        return None

    audio_path = Path(audio_path)

    try:
        index = load_cache_index()
        for item in index.values():
            cached_path = Path(item.get("path", ""))
            if cached_path == audio_path:
                return item.get("title")
    except Exception:
        logging.exception("Failed to look up cached title")

    return None


def add_to_cache(query, audio_file):
    if not CACHE_ENABLED or not audio_file or not audio_file.exists():
        return audio_file

    key = cache_key(query)
    title = build_title_from_metadata(query, clean_title(audio_file.stem))
    cached_path = CACHE_AUDIO_DIR / f"{key}{audio_file.suffix.lower()}"

    try:
        if not cached_path.exists():
            shutil.copy2(audio_file, cached_path)

        index = load_cache_index()
        index[key] = {
            "query": query,
            "title": title,
            "path": str(cached_path),
            "size_mb": round(file_size_mb(cached_path), 2),
            "created": int(time.time()),
            "last_used": int(time.time()),
            "hits": int(index.get(key, {}).get("hits", 0)),
        }
        save_cache_index(index)

        return cached_path

    except Exception:
        logging.exception("Failed to add file to cache")
        return audio_file


def clear_cache():
    if CACHE_AUDIO_DIR.exists():
        shutil.rmtree(CACHE_AUDIO_DIR, ignore_errors=True)

    CACHE_AUDIO_DIR.mkdir(parents=True, exist_ok=True)

    if CACHE_INDEX_FILE.exists():
        CACHE_INDEX_FILE.unlink()

    if METADATA_CACHE_FILE.exists():
        METADATA_CACHE_FILE.unlink()

# ── Downloading ──────────────────────────────────────────────
def download_audio(query):
    cached = get_cached_audio(query)

    if cached:
        return cached, True

    job = DOWNLOAD_DIR / f"job-{uuid.uuid4().hex[:8]}"
    job.mkdir(parents=True, exist_ok=True)

    try:
        target = f"ytsearch1:{query}" if not query.startswith("http") else query

        cmd = [
            "yt-dlp",
            "-x",
            "--audio-format", "mp3",
            "--audio-quality", "0",
            "-o", str(job / "%(title)s.%(ext)s"),
            target,
        ]

        result = run_cmd(cmd)

        if result.returncode != 0:
            logging.error(result.stdout)
            return None, False

        files = list(job.glob("*.mp3"))

        if not files:
            return None, False

        file = max(files, key=lambda p: p.stat().st_size)
        title = build_title_from_metadata(query, clean_title(file.stem))
        final = DOWNLOAD_DIR / f"{safe_filename(title)}{file.suffix.lower()}"

        counter = 2
        while final.exists():
            final = DOWNLOAD_DIR / f"{safe_filename(title)} ({counter}){file.suffix.lower()}"
            counter += 1

        shutil.move(str(file), str(final))

        cached_file = add_to_cache(query, final)

        return cached_file, False

    finally:
        shutil.rmtree(job, ignore_errors=True)

# ── Queue Processor ──────────────────────────────────────────
async def process_queue(app):
    global PROCESSING

    if PROCESSING:
        return

    PROCESSING = True

    while QUEUE:
        update, query, queue_message_id = QUEUE.popleft()
        chat_id = update.effective_chat.id

        try:
            msg = await app.bot.send_message(chat_id, f"🎶 Processing: {query}")

            audio, from_cache = await asyncio.to_thread(download_audio, query)

            if not audio:
                await msg.edit_text("❌ Failed")
                continue

            size = file_size_mb(audio)
            title = get_cached_title_by_path(audio) or clean_title(audio.stem)
            title = build_title_from_metadata(query, title)

            if size > MAX_FILE_MB:
                await msg.edit_text(f"📦 Too large ({size:.1f} MB)")
                continue

            if from_cache:
                await msg.edit_text("⚡ Found in cache. Sending...")
            else:
                await msg.edit_text("⬆️ Sending...")

            with audio.open("rb") as f:
                await app.bot.send_audio(
                    chat_id=chat_id,
                    audio=f,
                    filename=f"{title}{audio.suffix.lower()}",
                    title=title[:64],
                )

            if queue_message_id:
                try:
                    await app.bot.delete_message(
                        chat_id=chat_id,
                        message_id=queue_message_id,
                    )
                except Exception:
                    pass

            await msg.delete()

        except Exception:
            logging.exception("Queue error")

    PROCESSING = False

# ── Commands ─────────────────────────────────────────────────
async def start_cmd(update: Update, context: ContextTypes.DEFAULT_TYPE):
    await help_cmd(update, context)


async def help_cmd(update: Update, context: ContextTypes.DEFAULT_TYPE):
    await update.message.reply_text(
        f"🎵 {BOT_NAME} v{BOT_VERSION}\n"
        "The voice of music.\n\n"
        "Commands:\n"
        "/music <url or search>\n"
        "/queue\n"
        "/cache\n"
        "/clearcache\n"
        "/help\n\n"
        "You can also just type an artist/song search without a command."
    )


async def music(update: Update, context: ContextTypes.DEFAULT_TYPE):
    query = " ".join(context.args).strip()

    if not query:
        await update.message.reply_text("Usage: /music <url or search>")
        return

    if PROCESSING:
        queue_msg = await update.message.reply_text(f"➕ Added to queue ({len(QUEUE) + 1} waiting)")
    else:
        queue_msg = await update.message.reply_text("➕ Added to queue")

    QUEUE.append((update, query, queue_msg.message_id))

    asyncio.create_task(process_queue(context.application))


async def auto_music(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if not update.message or not update.message.text:
        return

    query = update.message.text.strip()

    # ignore commands
    if query.startswith("/"):
        return

    # ignore very short messages
    if len(query) < 4:
        return

    # ignore common chatter
    ignored_exact = {
        "hi", "hello", "hey", "yo",
        "lol", "lmao", "rofl",
        "thanks", "thank you",
        "ok", "okay", "k",
        "yes", "no"
    }

    if query.lower() in ignored_exact:
        return

    # must look like music
    looks_like_music = any([
        " - " in query,
        len(query.split()) >= 2,
        "http" in query,
    ])

    if not looks_like_music:
        return

    # ignore obvious non-music phrases
    ignored_phrases = [
        "how are you",
        "what are you",
        "who are you",
        "where are you",
        "why are you",
    ]

    lower = query.lower()
    if any(p in lower for p in ignored_phrases):
        return

    if PROCESSING:
        queue_msg = await update.message.reply_text(
            f"➕ Added to queue ({len(QUEUE) + 1} waiting)"
        )
    else:
        queue_msg = await update.message.reply_text("➕ Added to queue")

    QUEUE.append((update, query, queue_msg.message_id))

    asyncio.create_task(process_queue(context.application))


async def queue_cmd(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if not QUEUE:
        await update.message.reply_text("Queue empty")
        return

    text = "\n".join([f"{i + 1}. {q}" for i, (_, q, _) in enumerate(QUEUE)])
    await update.message.reply_text(text)


async def cache_cmd(update: Update, context: ContextTypes.DEFAULT_TYPE):
    index = load_cache_index()
    count = len(index)

    size_mb = 0.0
    for item in index.values():
        path = Path(item.get("path", ""))
        if path.exists():
            size_mb += file_size_mb(path)

    metadata_count = len(load_metadata_cache())

    await update.message.reply_text(
        f"🗃 Cache\n"
        f"Enabled: {CACHE_ENABLED}\n"
        f"Tracks: {count}\n"
        f"Metadata: {metadata_count}\n"
        f"Size: {size_mb:.1f} MB"
    )


async def clearcache_cmd(update: Update, context: ContextTypes.DEFAULT_TYPE):
    clear_cache()
    await update.message.reply_text("🧹 Cache cleared")

# ── Main ─────────────────────────────────────────────────────
def main():
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s [%(levelname)s] %(message)s",
    )

    builder = Application.builder().token(BOT_TOKEN)

    local_api = getattr(cfg, "LOCAL_BOT_API_URL", "")
    local_file_api = getattr(cfg, "LOCAL_BOT_API_FILE_URL", "")

    if local_api:
        builder = builder.base_url(local_api)

    if local_file_api:
        builder = builder.base_file_url(local_file_api)

    app = builder.build()

    app.add_handler(CommandHandler("start", start_cmd))
    app.add_handler(CommandHandler("help", help_cmd))
    app.add_handler(CommandHandler("music", music))
    app.add_handler(CommandHandler("queue", queue_cmd))
    app.add_handler(CommandHandler("cache", cache_cmd))
    app.add_handler(CommandHandler("clearcache", clearcache_cmd))
    app.add_handler(MessageHandler(filters.TEXT & ~filters.COMMAND, auto_music))

    logging.info("%s v%s started.", BOT_NAME, BOT_VERSION)
    app.run_polling()

if __name__ == "__main__":
    main()
