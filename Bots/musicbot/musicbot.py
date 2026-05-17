#!/usr/bin/env python3
# ------------------------------------------------------------
# file:     musicbot.py
# author:   Mike Redd
# version:  2.4
# created:  2026-05-03
# updated:  2026-05-03
# desc:     Sandalphon - Queue/cache music bot with album and artist browsing
# ------------------------------------------------------------

import asyncio
import difflib
import hashlib
import json
import logging
import os
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
BOT_VERSION = "2.4"

# ── Config ───────────────────────────────────────────────────
sys.path.insert(0, str(Path.home() / "bots/config"))
import musicbotrc as cfg  # noqa: E402

BOT_TOKEN = cfg.BOT_TOKEN

ADMIN_USERS = set(getattr(cfg, "ADMIN_USERS", []))

DOWNLOAD_DIR = Path(cfg.DOWNLOAD_DIR)
DOWNLOAD_DIR.mkdir(parents=True, exist_ok=True)

MAX_FILE_MB = int(getattr(cfg, "MAX_FILE_MB", 1900))

# Optional Spotify metadata matching
SPOTIFY_METADATA_ENABLED = bool(getattr(cfg, "SPOTIFY_METADATA_ENABLED", False))
SPOTIFY_CLIENT_ID = getattr(cfg, "SPOTIFY_CLIENT_ID", "")
SPOTIFY_CLIENT_SECRET = getattr(cfg, "SPOTIFY_CLIENT_SECRET", "")

# Optional cache config
CACHE_ENABLED = bool(getattr(cfg, "CACHE_ENABLED", True))
CACHE_DIR = Path(getattr(cfg, "CACHE_DIR", "/mnt/nvme1/work/bots/cache/musicbot"))
CACHE_AUDIO_DIR = CACHE_DIR / "audio"
CACHE_INDEX_FILE = CACHE_DIR / "index.json"
METADATA_CACHE_FILE = CACHE_DIR / "metadata.json"
LIBRARY_INDEX_FILE = CACHE_DIR / "library.json"

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


def is_spotify_url(query):
    lowered = (query or "").lower()
    return "open.spotify.com" in lowered or "spotify.link" in lowered


def extract_spotify_track_id(url):
    match = re.search(r"open\.spotify\.com/track/([A-Za-z0-9]+)", url or "")
    return match.group(1) if match else None


def get_spotify_token():
    if not (SPOTIFY_METADATA_ENABLED and SPOTIFY_CLIENT_ID and SPOTIFY_CLIENT_SECRET):
        return None

    try:
        import base64
        import urllib.parse
        import urllib.request

        auth = f"{SPOTIFY_CLIENT_ID}:{SPOTIFY_CLIENT_SECRET}"
        auth_b64 = base64.b64encode(auth.encode("utf-8")).decode("utf-8")

        data = urllib.parse.urlencode({"grant_type": "client_credentials"}).encode("utf-8")
        req = urllib.request.Request(
            "https://accounts.spotify.com/api/token",
            data=data,
            headers={
                "Authorization": f"Basic {auth_b64}",
                "Content-Type": "application/x-www-form-urlencoded",
            },
            method="POST",
        )

        with urllib.request.urlopen(req, timeout=15) as resp:
            payload = json.loads(resp.read().decode("utf-8"))

        return payload.get("access_token")

    except Exception:
        logging.exception("Spotify token lookup failed")
        return None


def get_spotify_metadata(query):
    if not is_spotify_url(query):
        return None

    track_id = extract_spotify_track_id(query)

    if not track_id:
        return None

    token = get_spotify_token()

    if not token:
        return None

    try:
        import urllib.request

        req = urllib.request.Request(
            f"https://api.spotify.com/v1/tracks/{track_id}",
            headers={"Authorization": f"Bearer {token}"},
            method="GET",
        )

        with urllib.request.urlopen(req, timeout=15) as resp:
            data = json.loads(resp.read().decode("utf-8"))

        artist = ", ".join(a.get("name", "") for a in data.get("artists", []) if a.get("name"))
        title = data.get("name", "")
        album = (data.get("album") or {}).get("name", "")
        release_date = (data.get("album") or {}).get("release_date", "")
        year = release_date[:4] if release_date else ""

        if not title:
            return None

        artist = clean_title(artist)
        title = clean_title(title)

        return {
            "artist": artist,
            "title": title,
            "album": album,
            "year": year,
            "display": clean_title(f"{artist} - {title}") if artist else title,
            "search": clean_title(f"{artist} - {title}") if artist else title,
            "source": "spotify",
        }

    except Exception:
        logging.exception("Spotify metadata lookup failed")
        return None


def resolve_download_query(query):
    """
    Convert metadata-only sources like Spotify into a searchable yt-dlp target.
    Spotify audio is not downloaded directly. Spotify metadata is used to
    search YouTube/yt-dlp for the matching track.
    """
    spotify_meta = get_spotify_metadata(query)

    if spotify_meta and spotify_meta.get("search"):
        return spotify_meta["search"], spotify_meta

    return query, None



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



def load_library_index():
    if not CACHE_ENABLED or not LIBRARY_INDEX_FILE.exists():
        return {}

    try:
        return json.loads(LIBRARY_INDEX_FILE.read_text(encoding="utf-8"))
    except Exception:
        logging.exception("Failed to read library index")
        return {}


def save_library_index(index):
    if not CACHE_ENABLED:
        return

    try:
        tmp = LIBRARY_INDEX_FILE.with_suffix(".tmp")
        tmp.write_text(json.dumps(index, indent=2, sort_keys=True), encoding="utf-8")
        tmp.replace(LIBRARY_INDEX_FILE)
    except Exception:
        logging.exception("Failed to write library index")


def normalize_library_text(text):
    text = clean_title(text or "").lower()
    text = re.sub(r"[^a-z0-9\s-]", " ", text)
    text = re.sub(r"\s+", " ", text).strip()
    return text


def library_identity(metadata=None, display=None):
    """
    Build a stable library identity so the same song does not get added
    multiple times from different queries/links.
    """
    metadata = metadata or {}

    artist = normalize_library_text(metadata.get("artist", ""))
    title = normalize_library_text(metadata.get("title", ""))

    if artist and title:
        return cache_key(f"{artist} - {title}")

    return cache_key(normalize_library_text(display or ""))


def fuzzy_ratio(a, b):
    return difflib.SequenceMatcher(
        None,
        normalize_library_text(a),
        normalize_library_text(b),
    ).ratio()


def library_match_score(term, item):
    term_norm = normalize_library_text(term)

    if not term_norm:
        return 0

    artist = normalize_library_text(item.get("artist", ""))
    title = normalize_library_text(item.get("title", ""))
    album = normalize_library_text(item.get("album", ""))
    display = normalize_library_text(item.get("display", ""))
    search_text = normalize_library_text(item.get("search_text", display))

    score = 0

    # Exact/contains matches
    if term_norm == display:
        score += 100
    elif term_norm in display:
        score += 50

    if artist and term_norm == artist:
        score += 45
    elif artist and term_norm in artist:
        score += 30

    if title and term_norm == title:
        score += 40
    elif title and term_norm in title:
        score += 25

    if album and term_norm in album:
        score += 10

    # Word scoring
    words = [w for w in term_norm.split() if w]

    for word in words:
        if artist and word in artist:
            score += 8
        if title and word in title:
            score += 7
        if album and word in album:
            score += 3
        if word in search_text:
            score += 2

    # Fuzzy scoring for typos
    fuzzy_display = fuzzy_ratio(term_norm, display)
    fuzzy_artist = fuzzy_ratio(term_norm, artist) if artist else 0
    fuzzy_title = fuzzy_ratio(term_norm, title) if title else 0

    score += int(fuzzy_display * 25)
    score += int(fuzzy_artist * 20)
    score += int(fuzzy_title * 20)

    return score


def add_to_library(query, audio_file, metadata=None):
    if not CACHE_ENABLED or not audio_file or not audio_file.exists():
        return

    title = ""
    artist = ""
    album = ""
    year = ""
    display = ""

    if metadata:
        artist = metadata.get("artist", "")
        title = metadata.get("title", "")
        album = metadata.get("album", "")
        year = metadata.get("year", "")
        display = metadata.get("display", "")

    if not display:
        display = get_cached_title_by_path(audio_file) or clean_title(audio_file.stem)

    key = library_identity(metadata, display)
    index = load_library_index()
    existing = index.get(key, {})

    # Keep first-added timestamp, but refresh path/query/metadata.
    index[key] = {
        "query": query,
        "display": display,
        "artist": artist,
        "title": title,
        "album": album,
        "year": year,
        "path": str(audio_file),
        "search_text": normalize_library_text(f"{display} {artist} {title} {album} {year}"),
        "added": int(existing.get("added", time.time())),
        "updated": int(time.time()),
        "plays": int(existing.get("plays", 0)),
    }

    save_library_index(index)


def search_library(term, limit=10):
    if not normalize_library_text(term):
        return []

    index = load_library_index()
    results = []

    for key, item in index.items():
        path = Path(item.get("path", ""))
        if not path.exists():
            continue

        score = library_match_score(term, item)

        if score >= 12:
            results.append((score, item))

    results.sort(
        key=lambda x: (
            x[0],
            x[1].get("plays", 0),
            x[1].get("updated", x[1].get("added", 0)),
        ),
        reverse=True,
    )

    return [item for _, item in results[:limit]]


def clear_library():
    if LIBRARY_INDEX_FILE.exists():
        LIBRARY_INDEX_FILE.unlink()


def group_library_by_artist():
    index = load_library_index()
    groups = {}

    for item in index.values():
        path = Path(item.get("path", ""))
        if not path.exists():
            continue

        artist = item.get("artist") or "Unknown Artist"
        groups.setdefault(artist, []).append(item)

    for artist in groups:
        groups[artist].sort(
            key=lambda item: (
                normalize_library_text(item.get("album", "")),
                normalize_library_text(item.get("title", item.get("display", ""))),
            )
        )

    return dict(sorted(groups.items(), key=lambda x: normalize_library_text(x[0])))


def group_library_by_album():
    index = load_library_index()
    groups = {}

    for item in index.values():
        path = Path(item.get("path", ""))
        if not path.exists():
            continue

        artist = item.get("artist") or "Unknown Artist"
        album = item.get("album") or "Unknown Album"
        key = f"{artist} - {album}"
        groups.setdefault(key, []).append(item)

    for album_key in groups:
        groups[album_key].sort(
            key=lambda item: normalize_library_text(item.get("title", item.get("display", "")))
        )

    return dict(sorted(groups.items(), key=lambda x: normalize_library_text(x[0])))


def search_album_groups(term, limit=10):
    term_norm = normalize_library_text(term)
    groups = group_library_by_album()
    results = []

    for album_key, items in groups.items():
        album_norm = normalize_library_text(album_key)
        score = 0

        if term_norm == album_norm:
            score += 100
        elif term_norm in album_norm:
            score += 50

        score += int(fuzzy_ratio(term_norm, album_norm) * 40)

        for item in items:
            score += library_match_score(term, item) // 4

        if score >= 15:
            results.append((score, album_key, items))

    results.sort(key=lambda x: x[0], reverse=True)
    return [(album_key, items) for _, album_key, items in results[:limit]]


def search_artist_groups(term, limit=10):
    term_norm = normalize_library_text(term)
    groups = group_library_by_artist()
    results = []

    for artist, items in groups.items():
        artist_norm = normalize_library_text(artist)
        score = 0

        if term_norm == artist_norm:
            score += 100
        elif term_norm in artist_norm:
            score += 50

        score += int(fuzzy_ratio(term_norm, artist_norm) * 45)

        for item in items:
            score += library_match_score(term, item) // 5

        if score >= 15:
            results.append((score, artist, items))

    results.sort(key=lambda x: x[0], reverse=True)
    return [(artist, items) for _, artist, items in results[:limit]]


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

    spotify_meta = get_spotify_metadata(query)
    if spotify_meta:
        return add_metadata_to_cache(query, spotify_meta)

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


def add_to_cache(query, audio_file, metadata=None):
    if not CACHE_ENABLED or not audio_file or not audio_file.exists():
        return audio_file

    key = cache_key(query)
    title = (metadata.get("display") if metadata else None) or build_title_from_metadata(query, clean_title(audio_file.stem))
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
        add_to_library(query, cached_path, metadata)

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

    if LIBRARY_INDEX_FILE.exists():
        LIBRARY_INDEX_FILE.unlink()

# ── Downloading ──────────────────────────────────────────────

def embed_metadata(audio_path, metadata, thumbnail_path=None):
    if not audio_path.exists():
        return audio_path

    output = audio_path.with_name(audio_path.stem + "_tagged.mp3")

    cmd = [
        "ffmpeg",
        "-y",
        "-i", str(audio_path),
    ]

    if thumbnail_path and thumbnail_path.exists():
        cmd += ["-i", str(thumbnail_path)]

    cmd += ["-map", "0:a"]

    if thumbnail_path and thumbnail_path.exists():
        cmd += [
            "-map", "1:v",
            "-c:v", "mjpeg",
            "-disposition:v", "attached_pic",
        ]

    cmd += [
        "-c:a", "copy",
        "-metadata", f"title={metadata.get('title','')}",
        "-metadata", f"artist={metadata.get('artist','')}",
        "-metadata", f"album={metadata.get('album','')}",
        "-metadata", f"date={metadata.get('year','')}",
        str(output),
    ]

    run_cmd(cmd)

    if output.exists():
        audio_path.unlink(missing_ok=True)
        return output

    return audio_path


def download_audio(query):
    cached = get_cached_audio(query)

    if cached:
        return cached, True

    job = DOWNLOAD_DIR / f"job-{uuid.uuid4().hex[:8]}"
    job.mkdir(parents=True, exist_ok=True)

    try:
        download_query, source_meta = resolve_download_query(query)
        target = f"ytsearch1:{download_query}" if not download_query.startswith("http") else download_query

        cmd = [
            "yt-dlp",
            "-x",
            "--audio-format", "mp3",
            "--audio-quality", "0",
            "--embed-thumbnail",
            "--write-thumbnail",
            "--convert-thumbnails", "jpg",
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

        thumbs = list(job.glob("*.jpg"))
        thumbnail = thumbs[0] if thumbs else None

        meta = source_meta or get_media_metadata(query)
        if meta:
            file = embed_metadata(file, meta, thumbnail)

        title = (meta.get("display") if meta else None) or build_title_from_metadata(query, clean_title(file.stem))
        final = DOWNLOAD_DIR / f"{safe_filename(title)}{file.suffix.lower()}"

        counter = 2
        while final.exists():
            final = DOWNLOAD_DIR / f"{safe_filename(title)} ({counter}){file.suffix.lower()}"
            counter += 1

        shutil.move(str(file), str(final))

        cached_file = add_to_cache(query, final, meta)

        return cached_file, False

    finally:
        shutil.rmtree(job, ignore_errors=True)


def progress_bar(percent, width=10):
    percent = max(0, min(100, int(percent)))
    filled = round(width * percent / 100)
    return "█" * filled + "░" * (width - filled)


async def update_status(msg, percent, stage, detail=None):
    bar = progress_bar(percent)

    text = f"{bar} {percent}%\n{stage}"

    if detail:
        detail = str(detail)
        if len(detail) > 120:
            detail = detail[:117] + "..."
        text += f"\n{detail}"

    try:
        await msg.edit_text(text)
    except Exception:
        logging.exception("Failed to update status message")



# ── Queue Processor ──────────────────────────────────────────
async def process_queue(app):
    global PROCESSING

    if PROCESSING:
        return

    PROCESSING = True

    while QUEUE:
        update, query, queue_message_id = QUEUE.popleft()
        chat_id = update.effective_chat.id
        msg = None

        try:
            # Reuse the queue confirmation as the live status message.
            # This keeps the chat clean: one message evolves instead of many.
            if queue_message_id:
                try:
                    msg = await app.bot.edit_message_text(
                        chat_id=chat_id,
                        message_id=queue_message_id,
                        text=f"{progress_bar(5)} 5%\n🎶 Queued\n{query}",
                    )
                except Exception:
                    msg = await app.bot.send_message(
                        chat_id,
                        f"{progress_bar(5)} 5%\n🎶 Queued\n{query}",
                    )
            else:
                msg = await app.bot.send_message(
                    chat_id,
                    f"{progress_bar(5)} 5%\n🎶 Queued\n{query}",
                )

            await update_status(msg, 15, "🔎 Resolving metadata...", query)

            cached = get_cached_audio(query)

            if cached:
                audio = cached
                from_cache = True
                await update_status(msg, 70, "⚡ Found in cache", query)
            else:
                await update_status(msg, 25, "⬇️ Downloading audio...", query)
                audio, from_cache = await asyncio.to_thread(download_audio, query)

            if not audio:
                await msg.edit_text("❌ Failed")
                continue

            await update_status(msg, 75, "🧪 Checking file...", audio.name)

            size = file_size_mb(audio)
            title = get_cached_title_by_path(audio) or clean_title(audio.stem)

            await update_status(msg, 85, "🏷️ Preparing title/metadata...", title)
            title = build_title_from_metadata(query, title)

            if size > MAX_FILE_MB:
                await msg.edit_text(f"📦 Too large ({size:.1f} MB)")
                continue

            if from_cache:
                await update_status(msg, 95, "⚡ Cached. Sending...", title)
            else:
                await update_status(msg, 95, "⬆️ Sending...", title)

            with audio.open("rb") as f:
                await app.bot.send_audio(
                    chat_id=chat_id,
                    audio=f,
                    filename=f"{title}{audio.suffix.lower()}",
                    title=title[:64],
                )

            await update_status(msg, 100, "✅ Sent", title)

            try:
                await msg.delete()
            except Exception:
                pass

        except Exception:
            logging.exception("Queue error")
            if msg:
                try:
                    await msg.edit_text("❌ Queue error")
                except Exception:
                    pass

    PROCESSING = False

def is_admin(user_id):
    return not ADMIN_USERS or user_id in ADMIN_USERS


async def admin_only(update):
    user_id = update.effective_user.id if update.effective_user else 0

    if not is_admin(user_id):
        await update.message.reply_text("❌ Admin only")
        return False

    return True



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
        "/library\n"
        "/artists\n"
        "/artist <artist>\n"
        "/albums\n"
        "/album <album or artist>\n"
        "/find <artist or song>\n"
        "/play <artist or song>\n"
        "/clearcache\n"
        "/clearlibrary\n"
        "/reload\n"
        "/restart\n"
        "/help\n\n"
        "You can also just type an artist/song search or paste a supported link."
    )


async def music(update: Update, context: ContextTypes.DEFAULT_TYPE):
    query = " ".join(context.args).strip()

    if not query:
        await update.message.reply_text("Usage: /music <url or search>")
        return

    if PROCESSING:
        queue_msg = await update.message.reply_text(f"➕ Queued ({len(QUEUE) + 1} waiting)")
    else:
        queue_msg = await update.message.reply_text("➕ Queued")

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
            f"➕ Queued ({len(QUEUE) + 1} waiting)"
        )
    else:
        queue_msg = await update.message.reply_text("➕ Queued")

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
    library_count = len(load_library_index())

    await update.message.reply_text(
        f"🗃 Cache\n"
        f"Enabled: {CACHE_ENABLED}\n"
        f"Tracks: {count}\n"
        f"Metadata: {metadata_count}\n"
        f"Library: {library_count}\n"
        f"Size: {size_mb:.1f} MB"
    )


async def clearcache_cmd(update: Update, context: ContextTypes.DEFAULT_TYPE):
    clear_cache()
    await update.message.reply_text("🧹 Cache cleared")

async def library_cmd(update: Update, context: ContextTypes.DEFAULT_TYPE):
    index = load_library_index()
    count = len(index)

    if not index:
        await update.message.reply_text("📚 Library empty")
        return

    items = sorted(
        index.values(),
        key=lambda item: item.get("added", 0),
        reverse=True,
    )[:15]

    lines = [f"📚 Library ({count} tracks)", ""]

    for i, item in enumerate(items, start=1):
        lines.append(f"{i}. {item.get('display', 'Unknown')}")

    await update.message.reply_text("\n".join(lines))


async def find_cmd(update: Update, context: ContextTypes.DEFAULT_TYPE):
    term = " ".join(context.args).strip()

    if not term:
        await update.message.reply_text("Usage: /find <artist or song>")
        return

    results = search_library(term)

    if not results:
        await update.message.reply_text("No library matches found.")
        return

    lines = [f"🔎 Results for: {term}", ""]

    for i, item in enumerate(results, start=1):
        lines.append(f"{i}. {item.get('display', 'Unknown')}")

    await update.message.reply_text("\n".join(lines))


async def play_cmd(update: Update, context: ContextTypes.DEFAULT_TYPE):
    term = " ".join(context.args).strip()

    if not term:
        await update.message.reply_text("Usage: /play <artist or song>")
        return

    results = search_library(term, limit=1)

    if not results:
        await update.message.reply_text("No library match found. Try /music to download it.")
        return

    item = results[0]
    path = Path(item.get("path", ""))

    if not path.exists():
        await update.message.reply_text("Library entry exists, but file is missing.")
        return

    title = item.get("display", clean_title(path.stem))

    # Track local library plays for future ranking.
    index = load_library_index()
    for key, entry in index.items():
        if entry.get("path") == str(path):
            entry["plays"] = int(entry.get("plays", 0)) + 1
            entry["last_played"] = int(time.time())
            index[key] = entry
            save_library_index(index)
            break

    with path.open("rb") as f:
        await update.message.reply_audio(
            audio=f,
            filename=f"{title}{path.suffix.lower()}",
            title=title[:64],
        )


async def clearlibrary_cmd(update: Update, context: ContextTypes.DEFAULT_TYPE):
    clear_library()
    await update.message.reply_text("🧹 Library index cleared")





async def artists_cmd(update: Update, context: ContextTypes.DEFAULT_TYPE):
    groups = group_library_by_artist()

    if not groups:
        await update.message.reply_text("🎤 Artist library empty")
        return

    lines = [f"🎤 Artists ({len(groups)})", ""]

    for i, (artist, items) in enumerate(list(groups.items())[:25], start=1):
        lines.append(f"{i}. {artist} ({len(items)})")

    await update.message.reply_text("\n".join(lines))


async def artist_cmd(update: Update, context: ContextTypes.DEFAULT_TYPE):
    term = " ".join(context.args).strip()

    if not term:
        await update.message.reply_text("Usage: /artist <artist>")
        return

    results = search_artist_groups(term, limit=1)

    if not results:
        await update.message.reply_text("No artist match found.")
        return

    artist, items = results[0]

    lines = [f"🎤 {artist} ({len(items)} tracks)", ""]

    for i, item in enumerate(items[:25], start=1):
        album = item.get("album", "")
        title = item.get("title") or item.get("display", "Unknown")
        if album:
            lines.append(f"{i}. {title} — {album}")
        else:
            lines.append(f"{i}. {title}")

    await update.message.reply_text("\n".join(lines))


async def albums_cmd(update: Update, context: ContextTypes.DEFAULT_TYPE):
    groups = group_library_by_album()

    if not groups:
        await update.message.reply_text("💿 Album library empty")
        return

    lines = [f"💿 Albums ({len(groups)})", ""]

    for i, (album_key, items) in enumerate(list(groups.items())[:25], start=1):
        lines.append(f"{i}. {album_key} ({len(items)})")

    await update.message.reply_text("\n".join(lines))


async def album_cmd(update: Update, context: ContextTypes.DEFAULT_TYPE):
    term = " ".join(context.args).strip()

    if not term:
        await update.message.reply_text("Usage: /album <album or artist>")
        return

    results = search_album_groups(term, limit=1)

    if not results:
        await update.message.reply_text("No album match found.")
        return

    album_key, items = results[0]

    lines = [f"💿 {album_key} ({len(items)} tracks)", ""]

    for i, item in enumerate(items[:25], start=1):
        title = item.get("title") or item.get("display", "Unknown")
        lines.append(f"{i}. {title}")

    await update.message.reply_text("\n".join(lines))


async def reload_cmd(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if not await admin_only(update):
        return

    global PROCESSING

    PROCESSING = False

    logging.info("Reload requested")

    await update.message.reply_text(
        f"♻️ {BOT_NAME} config/state reloaded"
    )


async def restart_cmd(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if not await admin_only(update):
        return

    await update.message.reply_text(
        f"🔄 Restarting {BOT_NAME}..."
    )

    logging.info("Restart requested")

    python = sys.executable
    os.execv(python, [python] + sys.argv)



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
    app.add_handler(CommandHandler("library", library_cmd))
    app.add_handler(CommandHandler("artists", artists_cmd))
    app.add_handler(CommandHandler("artist", artist_cmd))
    app.add_handler(CommandHandler("albums", albums_cmd))
    app.add_handler(CommandHandler("album", album_cmd))
    app.add_handler(CommandHandler("find", find_cmd))
    app.add_handler(CommandHandler("play", play_cmd))
    app.add_handler(CommandHandler("clearcache", clearcache_cmd))
    app.add_handler(CommandHandler("clearlibrary", clearlibrary_cmd))
    app.add_handler(CommandHandler("reload", reload_cmd))
    app.add_handler(CommandHandler("restart", restart_cmd))
    app.add_handler(MessageHandler(filters.TEXT & ~filters.COMMAND, auto_music))

    logging.info("%s v%s started.", BOT_NAME, BOT_VERSION)
    app.run_polling()

if __name__ == "__main__":
    main()