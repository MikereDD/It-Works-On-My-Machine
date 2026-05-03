#!/usr/bin/env python3
# ------------------------------------------------------------
# file:     musicbot.py
# author:   Mike Redd
# version:  1.2
# created:  2026-05-03
# updated:  2026-05-03
# desc:     Sandalphon - Telegram music bot with metadata + playlist support
# ------------------------------------------------------------

import asyncio
import json
import logging
import re
import shutil
import subprocess
import sys
import uuid
from pathlib import Path
from urllib.parse import urlparse

from telegram import Update
from telegram.ext import Application, CommandHandler, ContextTypes

# ── Branding ─────────────────────────────────────────────────

BOT_NAME = "Sandalphon"
BOT_VERSION = "1.2"


# ── Config Loader ────────────────────────────────────────────

CONFIG_PATHS = [
    Path("/mnt/nvme1/work/bots/config/musicbotrc.py"),
    Path.home() / "bots/config/musicbotrc.py",
    Path(__file__).parent / "config/musicbotrc.py",
]

config_file = next((p for p in CONFIG_PATHS if p.exists()), None)

if not config_file:
    print("ERROR: musicbotrc.py not found.")
    sys.exit(1)

sys.path.insert(0, str(config_file.parent))
import musicbotrc as cfg  # noqa: E402


# ── Paths / Settings ─────────────────────────────────────────

BASE_DIR = Path(getattr(cfg, "BASE_DIR", Path(__file__).parent))
DOWNLOAD_DIR = Path(getattr(cfg, "DOWNLOAD_DIR", BASE_DIR / "downloads"))
LOG_FILE = Path(getattr(cfg, "LOG_FILE", BASE_DIR / "musicbot.log"))

DOWNLOAD_DIR.mkdir(parents=True, exist_ok=True)
LOG_FILE.parent.mkdir(parents=True, exist_ok=True)

BOT_TOKEN = getattr(cfg, "BOT_TOKEN", "")
ALLOWED_USER_IDS = set(getattr(cfg, "ALLOWED_USER_IDS", []))
ADMIN_USERS = set(getattr(cfg, "ADMIN_USERS", []))

MAX_FILE_MB = int(getattr(cfg, "MAX_FILE_MB", 49))
AUDIO_FORMAT = getattr(cfg, "AUDIO_FORMAT", "mp3")
AUDIO_QUALITY = getattr(cfg, "AUDIO_QUALITY", "0")
PLAYLIST_LIMIT = int(getattr(cfg, "PLAYLIST_LIMIT", 10))

LOCAL_BOT_API_URL = getattr(cfg, "LOCAL_BOT_API_URL", "")
LOCAL_BOT_API_FILE_URL = getattr(cfg, "LOCAL_BOT_API_FILE_URL", "")
COOKIES_FILE = getattr(cfg, "COOKIES_FILE", "")

SPOTIFY_METADATA_ENABLED = bool(getattr(cfg, "SPOTIFY_METADATA_ENABLED", False))
SPOTIFY_CLIENT_ID = getattr(cfg, "SPOTIFY_CLIENT_ID", "")
SPOTIFY_CLIENT_SECRET = getattr(cfg, "SPOTIFY_CLIENT_SECRET", "")


# ── Logging ──────────────────────────────────────────────────

logging.basicConfig(
    filename=str(LOG_FILE),
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
)

console = logging.StreamHandler()
console.setLevel(logging.INFO)
logging.getLogger("").addHandler(console)


# ── Access / Input Helpers ───────────────────────────────────

def allowed(update: Update) -> bool:
    user = update.effective_user

    if not user:
        return False

    user_id = user.id

    # Admins always allowed
    if user_id in ADMIN_USERS:
        return True

    # Empty whitelist means public bot
    if not ALLOWED_USER_IDS:
        return True

    return user_id in ALLOWED_USER_IDS


def is_url(text: str) -> bool:
    return bool(re.match(r"^https?://", text.strip(), re.I))


def is_spotify_url(text: str) -> bool:
    lowered = text.lower()
    return "open.spotify.com" in lowered or "spotify.link" in lowered


def is_amazon_music_url(text: str) -> bool:
    lowered = text.lower()
    return "music.amazon." in lowered or "amazon.com/music" in lowered


def is_probably_playlist(text: str) -> bool:
    lowered = text.lower()

    playlist_markers = [
        "list=",
        "/playlist",
        "/sets/",
        "playlist?",
        "album/",
    ]

    return any(marker in lowered for marker in playlist_markers)


def file_size_mb(path: Path) -> float:
    return path.stat().st_size / (1024 * 1024)


def run_cmd(cmd: list[str], cwd: Path | None = None) -> subprocess.CompletedProcess:
    logging.info("Running: %s", " ".join(cmd))

    return subprocess.run(
        cmd,
        cwd=str(cwd) if cwd else None,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        check=False,
    )


def clean_name(name: str) -> str:
    name = re.sub(r'[\\/:*?"<>|]', "-", name)
    name = re.sub(r"\s+", " ", name).strip()
    return name[:180] or "audio"


def clean_title(title: str) -> str:
    """Clean noisy yt-dlp/video titles for nicer Telegram display and tags."""
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

    # "The Smiths - The Smiths - How Soon Is Now" -> "The Smiths - How Soon Is Now"
    if len(parts) >= 3 and parts[0].lower() == parts[1].lower():
        parts = [parts[0], *parts[2:]]

    # "Artist - Title - extra junk" -> "Artist - Title"
    if len(parts) > 2:
        parts = parts[:2]

    title = " - ".join(parts) if parts else title
    title = re.sub(r"\s+", " ", title).strip(" -")

    return title[:120] or "audio"


def split_artist_title(display_title: str) -> tuple[str, str]:
    parts = [p.strip() for p in display_title.split(" - ", 1)]

    if len(parts) == 2 and parts[0] and parts[1]:
        return parts[0][:64], parts[1][:64]

    return BOT_NAME, display_title[:64]


def unique_path(path: Path) -> Path:
    if not path.exists():
        return path

    counter = 2
    while True:
        candidate = path.with_name(f"{path.stem} ({counter}){path.suffix}")
        if not candidate.exists():
            return candidate
        counter += 1


# ── Metadata Helpers ─────────────────────────────────────────

def extract_track_id_from_spotify_url(url: str) -> str | None:
    match = re.search(r"open\.spotify\.com/track/([A-Za-z0-9]+)", url)
    if match:
        return match.group(1)

    return None


def get_spotify_token() -> str | None:
    if not (SPOTIFY_METADATA_ENABLED and SPOTIFY_CLIENT_ID and SPOTIFY_CLIENT_SECRET):
        return None

    try:
        import base64
        import requests

        auth = f"{SPOTIFY_CLIENT_ID}:{SPOTIFY_CLIENT_SECRET}"
        auth_b64 = base64.b64encode(auth.encode()).decode()

        resp = requests.post(
            "https://accounts.spotify.com/api/token",
            headers={"Authorization": f"Basic {auth_b64}"},
            data={"grant_type": "client_credentials"},
            timeout=10,
        )

        if resp.status_code != 200:
            logging.warning("Spotify token failed: %s", resp.text)
            return None

        return resp.json().get("access_token")

    except Exception:
        logging.exception("Spotify token lookup failed")
        return None


def get_spotify_metadata(url: str) -> dict | None:
    track_id = extract_track_id_from_spotify_url(url)
    token = get_spotify_token()

    if not (track_id and token):
        return None

    try:
        import requests

        resp = requests.get(
            f"https://api.spotify.com/v1/tracks/{track_id}",
            headers={"Authorization": f"Bearer {token}"},
            timeout=10,
        )

        if resp.status_code != 200:
            logging.warning("Spotify track lookup failed: %s", resp.text)
            return None

        data = resp.json()

        artist = ", ".join(a["name"] for a in data.get("artists", []))
        title = data.get("name", "")
        album = data.get("album", {}).get("name", "")
        release_date = data.get("album", {}).get("release_date", "")
        year = release_date[:4] if release_date else ""
        cover = ""

        images = data.get("album", {}).get("images", [])
        if images:
            cover = images[0].get("url", "")

        if not title:
            return None

        return {
            "artist": artist or BOT_NAME,
            "title": title,
            "album": album,
            "year": year,
            "cover": cover,
            "search": f"{artist} - {title}",
        }

    except Exception:
        logging.exception("Spotify metadata lookup failed")
        return None


def get_ytdlp_metadata(target: str, playlist: bool = False) -> dict | None:
    cmd = [
        "yt-dlp",
        "--dump-single-json",
        "--no-warnings",
    ]

    if not playlist:
        cmd.append("--no-playlist")

    if COOKIES_FILE and Path(COOKIES_FILE).exists():
        cmd.extend(["--cookies", COOKIES_FILE])

    cmd.append(target)

    result = run_cmd(cmd)

    if result.returncode != 0:
        logging.warning("yt-dlp metadata failed: %s", result.stdout[-1000:])
        return None

    try:
        return json.loads(result.stdout)
    except json.JSONDecodeError:
        logging.warning("Could not decode yt-dlp metadata JSON")
        return None


def metadata_from_ytdlp_info(info: dict) -> dict:
    title = info.get("track") or info.get("title") or "audio"
    artist = (
        info.get("artist")
        or info.get("creator")
        or info.get("uploader")
        or BOT_NAME
    )
    album = info.get("album") or ""
    year = str(info.get("release_year") or info.get("upload_date", "")[:4] or "")
    cover = info.get("thumbnail") or ""

    display_title = clean_title(f"{artist} - {title}") if artist else clean_title(title)
    parsed_artist, parsed_title = split_artist_title(display_title)

    return {
        "artist": parsed_artist,
        "title": parsed_title,
        "album": album,
        "year": year,
        "cover": cover,
        "search": f"{parsed_artist} - {parsed_title}",
        "display": display_title,
    }


def build_metadata(input_text: str) -> dict | None:
    if is_spotify_url(input_text):
        spotify_meta = get_spotify_metadata(input_text)
        if spotify_meta:
            spotify_meta["display"] = clean_title(f"{spotify_meta['artist']} - {spotify_meta['title']}")
            return spotify_meta

    # Amazon Music has no clean simple API here; we let yt-dlp/title lookup or search handle it.
    return None


# ── Download / Tagging ───────────────────────────────────────

def build_target(input_text: str, metadata: dict | None = None) -> str:
    input_text = input_text.strip()

    if metadata and metadata.get("search"):
        return f"ytsearch1:{metadata['search']}"

    if is_url(input_text) and not is_spotify_url(input_text):
        return input_text

    return f"ytsearch1:{input_text}"


def find_audio_file(workdir: Path) -> Path | None:
    audio_exts = [".mp3", ".m4a", ".opus", ".ogg", ".flac", ".wav"]

    files = [
        p for p in workdir.iterdir()
        if p.is_file() and p.suffix.lower() in audio_exts
    ]

    if not files:
        return None

    return max(files, key=lambda p: p.stat().st_size)


def retag_audio_file(audio_file: Path, meta: dict) -> Path:
    """
    Rewrites metadata so Telegram displays clean tags instead of noisy embedded
    YouTube/yt-dlp metadata.
    """
    artist = meta.get("artist") or BOT_NAME
    title = meta.get("title") or audio_file.stem
    album = meta.get("album") or ""
    year = meta.get("year") or ""

    temp_file = audio_file.with_name(f"{audio_file.stem}.tagged{audio_file.suffix}")

    cmd = [
        "ffmpeg",
        "-y",
        "-i", str(audio_file),
        "-map", "0",
        "-c", "copy",
        "-metadata", f"title={title}",
        "-metadata", f"artist={artist}",
        "-metadata", f"album_artist={artist}",
    ]

    if album:
        cmd.extend(["-metadata", f"album={album}"])

    if year:
        cmd.extend(["-metadata", f"date={year}"])

    cmd.append(str(temp_file))

    result = run_cmd(cmd)

    if result.returncode != 0 or not temp_file.exists():
        logging.warning("Metadata rewrite failed. Keeping original file.")
        logging.warning(result.stdout)
        return audio_file

    audio_file.unlink(missing_ok=True)
    temp_file.rename(audio_file)
    return audio_file


def download_audio(input_text: str, playlist: bool = False, playlist_index: int | None = None) -> tuple[Path | None, str, dict | None]:
    job_id = uuid.uuid4().hex[:8]
    workdir = DOWNLOAD_DIR / f"job-{job_id}"
    workdir.mkdir(parents=True, exist_ok=True)

    try:
        external_meta = build_metadata(input_text)
        target = build_target(input_text, external_meta)

        output_template = str(workdir / "%(title)s.%(ext)s")

        cmd = [
            "yt-dlp",
            "-x",
            "--audio-format", AUDIO_FORMAT,
            "--audio-quality", AUDIO_QUALITY,
            "--embed-thumbnail",
            "--add-metadata",
            "--restrict-filenames",
            "-o", output_template,
        ]

        if not playlist:
            cmd.append("--no-playlist")

        if playlist and playlist_index is not None:
            cmd.extend(["--playlist-items", str(playlist_index)])

        if COOKIES_FILE and Path(COOKIES_FILE).exists():
            cmd.extend(["--cookies", COOKIES_FILE])

        cmd.append(target)

        result = run_cmd(cmd)

        if result.returncode != 0:
            logging.error(result.stdout)
            return None, result.stdout[-3500:], None

        audio_file = find_audio_file(workdir)

        if not audio_file:
            return None, "Download finished but no audio file was found.", None

        if external_meta:
            meta = external_meta
            display_title = meta.get("display") or clean_title(f"{meta.get('artist', BOT_NAME)} - {meta.get('title', audio_file.stem)}")
        else:
            display_title = clean_title(audio_file.stem)
            artist, title = split_artist_title(display_title)
            meta = {
                "artist": artist,
                "title": title,
                "album": "",
                "year": "",
                "cover": "",
                "display": display_title,
            }

        final_file = unique_path(
            DOWNLOAD_DIR / f"{clean_name(display_title)}{audio_file.suffix.lower()}"
        )

        shutil.move(str(audio_file), str(final_file))
        final_file = retag_audio_file(final_file, meta)

        return final_file, "OK", meta

    finally:
        shutil.rmtree(workdir, ignore_errors=True)


def get_playlist_items(url: str) -> list[str]:
    """
    Return webpage URLs for playlist entries, capped by PLAYLIST_LIMIT.
    """
    info = get_ytdlp_metadata(url, playlist=True)

    if not info:
        return []

    entries = info.get("entries") or []
    urls = []

    for entry in entries:
        if not entry:
            continue

        webpage_url = entry.get("webpage_url") or entry.get("url")

        if not webpage_url:
            continue

        if not str(webpage_url).startswith("http"):
            # YouTube extractor sometimes gives only an ID.
            if entry.get("ie_key", "").lower() == "youtube" or info.get("extractor_key") == "YoutubeTab":
                webpage_url = f"https://www.youtube.com/watch?v={webpage_url}"

        urls.append(str(webpage_url))

        if len(urls) >= PLAYLIST_LIMIT:
            break

    return urls


# ── Telegram Commands ────────────────────────────────────────

async def start_cmd(update: Update, context: ContextTypes.DEFAULT_TYPE):
    await help_cmd(update, context)


async def help_cmd(update: Update, context: ContextTypes.DEFAULT_TYPE):
    msg = (
        f"🎵 {BOT_NAME} v{BOT_VERSION}\n"
        "The voice of music.\n\n"
        "Commands:\n"
        "/music <url or search>\n"
        "/audio <url or search>\n"
        "/song <url or search>\n"
        "/playlist <playlist url>\n"
        "/id\n"
        "/help\n\n"
        "Examples:\n"
        "/music https://youtube.com/watch?v=...\n"
        "/music https://soundcloud.com/artist/song\n"
        "/music the smiths how soon is now\n"
        "/playlist https://youtube.com/playlist?list=...\n\n"
        "Use only with music you own, created, have permission to download, "
        "or public/royalty-free sources."
    )

    await update.message.reply_text(msg)


async def id_cmd(update: Update, context: ContextTypes.DEFAULT_TYPE):
    user = update.effective_user
    chat = update.effective_chat

    await update.message.reply_text(
        f"User ID: `{user.id}`\nChat ID: `{chat.id}`",
        parse_mode="Markdown",
    )


async def music_cmd(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if not allowed(update):
        await update.message.reply_text("Access denied.")
        return

    if not context.args:
        await update.message.reply_text("Usage: /music <url or search>")
        return

    query = " ".join(context.args).strip()

    notice = await update.message.reply_text(f"🎧 {BOT_NAME} is listening...")

    try:
        await notice.edit_text("🎶 Finding the track...")

        audio_file, status, meta = await asyncio.to_thread(download_audio, query)

        if not audio_file:
            logging.error("Download failed: %s", status)
            await notice.edit_text(
                "⚠️ Couldn't process that.\n\nTry another link or search."
            )
            return

        size = file_size_mb(audio_file)

        if meta:
            display_title = meta.get("display") or clean_title(audio_file.stem)
            artist = meta.get("artist") or BOT_NAME
            title = meta.get("title") or display_title
        else:
            display_title = clean_title(audio_file.stem)
            artist, title = split_artist_title(display_title)

        if size > MAX_FILE_MB:
            await notice.edit_text(
                f"📦 File too large ({size:.1f} MB)\n"
                "Try a shorter or different track."
            )
            return

        await notice.edit_text("📀 Preparing audio...")
        await asyncio.sleep(0.5)

        await notice.edit_text("⬆️ Sending to you...")

        with audio_file.open("rb") as f:
            await update.message.reply_audio(
                audio=f,
                filename=f"{display_title}{audio_file.suffix.lower()}",
                performer=artist[:64],
                title=title[:64],
            )

        await notice.delete()

    except Exception as e:
        logging.exception("Unhandled error")
        await notice.edit_text(f"Error: {e}")


async def playlist_cmd(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if not allowed(update):
        await update.message.reply_text("Access denied.")
        return

    if not context.args:
        await update.message.reply_text("Usage: /playlist <playlist url>")
        return

    url = " ".join(context.args).strip()

    if not is_url(url):
        await update.message.reply_text("Playlist needs a URL.")
        return

    notice = await update.message.reply_text(
        f"📜 {BOT_NAME} is reading the playlist..."
    )

    try:
        items = await asyncio.to_thread(get_playlist_items, url)

        if not items:
            await notice.edit_text("⚠️ Couldn't read playlist entries.")
            return

        await notice.edit_text(
            f"📜 Found {len(items)} tracks. Sending up to {PLAYLIST_LIMIT}..."
        )

        sent = 0
        skipped = 0

        for idx, item_url in enumerate(items, start=1):
            await notice.edit_text(f"🎶 Track {idx}/{len(items)}: downloading...")

            audio_file, status, meta = await asyncio.to_thread(download_audio, item_url)

            if not audio_file:
                logging.error("Playlist item failed: %s", status)
                skipped += 1
                continue

            size = file_size_mb(audio_file)

            if meta:
                display_title = meta.get("display") or clean_title(audio_file.stem)
                artist = meta.get("artist") or BOT_NAME
                title = meta.get("title") or display_title
            else:
                display_title = clean_title(audio_file.stem)
                artist, title = split_artist_title(display_title)

            if size > MAX_FILE_MB:
                skipped += 1
                logging.warning("Skipping large playlist file: %s %.1f MB", audio_file.name, size)
                continue

            await notice.edit_text(f"⬆️ Track {idx}/{len(items)}: sending...")

            with audio_file.open("rb") as f:
                await update.message.reply_audio(
                    audio=f,
                    filename=f"{display_title}{audio_file.suffix.lower()}",
                    performer=artist[:64],
                    title=title[:64],
                )

            sent += 1
            await asyncio.sleep(0.75)

        await notice.edit_text(
            f"✅ Playlist done.\nSent: {sent}\nSkipped: {skipped}"
        )

    except Exception as e:
        logging.exception("Unhandled playlist error")
        await notice.edit_text(f"Error: {e}")


# ── Main ─────────────────────────────────────────────────────

def main():
    if not BOT_TOKEN or BOT_TOKEN == "PUT_YOUR_BOT_TOKEN_HERE":
        print("ERROR: Set BOT_TOKEN in musicbotrc.py")
        sys.exit(1)

    builder = Application.builder().token(BOT_TOKEN)

    if LOCAL_BOT_API_URL:
        builder = builder.base_url(LOCAL_BOT_API_URL)

    if LOCAL_BOT_API_FILE_URL:
        builder = builder.base_file_url(LOCAL_BOT_API_FILE_URL)

    app = builder.build()

    app.add_handler(CommandHandler("start", start_cmd))
    app.add_handler(CommandHandler("help", help_cmd))
    app.add_handler(CommandHandler("id", id_cmd))
    app.add_handler(CommandHandler("music", music_cmd))
    app.add_handler(CommandHandler("audio", music_cmd))
    app.add_handler(CommandHandler("song", music_cmd))
    app.add_handler(CommandHandler("playlist", playlist_cmd))

    logging.info("%s v%s started.", BOT_NAME, BOT_VERSION)
    app.run_polling()


if __name__ == "__main__":
    main()

