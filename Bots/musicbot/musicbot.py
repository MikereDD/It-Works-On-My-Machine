#!/usr/bin/env python3
# ------------------------------------------------------------
# file:     musicbot.py
# author:   Mike Redd
# version:  1.1
# created:  2026-05-03
# updated:  2026-05-03
# desc:     Sandalphon - Telegram music bot with polished UX
# ------------------------------------------------------------

import asyncio
import logging
import re
import shutil
import subprocess
import sys
import uuid
from pathlib import Path

from telegram import Update
from telegram.ext import Application, CommandHandler, ContextTypes

# ── Branding ─────────────────────────────────────────────────

BOT_NAME = "Sandalphon"
BOT_VERSION = "1.1"


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


# ── Paths / Logging ──────────────────────────────────────────

BASE_DIR = Path(getattr(cfg, "BASE_DIR", Path(__file__).parent))
DOWNLOAD_DIR = Path(getattr(cfg, "DOWNLOAD_DIR", BASE_DIR / "downloads"))
LOG_FILE = Path(getattr(cfg, "LOG_FILE", BASE_DIR / "musicbot.log"))

DOWNLOAD_DIR.mkdir(parents=True, exist_ok=True)
LOG_FILE.parent.mkdir(parents=True, exist_ok=True)

logging.basicConfig(
    filename=str(LOG_FILE),
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
)

console = logging.StreamHandler()
console.setLevel(logging.INFO)
logging.getLogger("").addHandler(console)

BOT_TOKEN = getattr(cfg, "BOT_TOKEN", "")
ALLOWED_USER_IDS = set(getattr(cfg, "ALLOWED_USER_IDS", []))
MAX_FILE_MB = int(getattr(cfg, "MAX_FILE_MB", 49))
AUDIO_FORMAT = getattr(cfg, "AUDIO_FORMAT", "mp3")
AUDIO_QUALITY = getattr(cfg, "AUDIO_QUALITY", "0")

LOCAL_BOT_API_URL = getattr(cfg, "LOCAL_BOT_API_URL", "")
LOCAL_BOT_API_FILE_URL = getattr(cfg, "LOCAL_BOT_API_FILE_URL", "")
COOKIES_FILE = getattr(cfg, "COOKIES_FILE", "")


# ── Helpers ──────────────────────────────────────────────────

def allowed(update: Update) -> bool:
    if not ALLOWED_USER_IDS:
        return True

    user = update.effective_user
    return bool(user and user.id in ALLOWED_USER_IDS)


def is_url(text: str) -> bool:
    return bool(re.match(r"^https?://", text.strip(), re.I))


def is_spotify_url(text: str) -> bool:
    lowered = text.lower()
    return "open.spotify.com" in lowered or "spotify.link" in lowered


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


def find_audio_file(workdir: Path) -> Path | None:
    audio_exts = [".mp3", ".m4a", ".opus", ".ogg", ".flac", ".wav"]
    files = [
        p for p in workdir.iterdir()
        if p.is_file() and p.suffix.lower() in audio_exts
    ]

    if not files:
        return None

    return max(files, key=lambda p: p.stat().st_size)


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
        r"\bofficial\s+music\s+video\b",
        r"\bofficial\s+video\b",
        r"\bofficial\s+audio\b",
        r"\blyric\s+video\b",
        r"\blyrics\b",
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


def build_target(input_text: str) -> str:
    input_text = input_text.strip()

    if is_url(input_text) and not is_spotify_url(input_text):
        return input_text

    return f"ytsearch1:{input_text}"


def retag_audio_file(audio_file: Path, display_title: str) -> Path:
    """
    Rewrites metadata so Telegram displays the cleaned title instead of the
    noisy embedded title from yt-dlp/YouTube.
    """
    artist, title = split_artist_title(display_title)
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
        str(temp_file),
    ]

    result = run_cmd(cmd)

    if result.returncode != 0 or not temp_file.exists():
        logging.warning("Metadata rewrite failed. Keeping original file.")
        logging.warning(result.stdout)
        return audio_file

    audio_file.unlink(missing_ok=True)
    temp_file.rename(audio_file)
    return audio_file


def download_audio(input_text: str) -> tuple[Path | None, str]:
    job_id = uuid.uuid4().hex[:8]
    workdir = DOWNLOAD_DIR / f"job-{job_id}"
    workdir.mkdir(parents=True, exist_ok=True)

    try:
        target = build_target(input_text)

        output_template = str(workdir / "%(title)s.%(ext)s")

        cmd = [
            "yt-dlp",
            "--no-playlist",
            "-x",
            "--audio-format", AUDIO_FORMAT,
            "--audio-quality", AUDIO_QUALITY,
            "--embed-thumbnail",
            "--add-metadata",
            "--restrict-filenames",
            "-o", output_template,
            target,
        ]

        if COOKIES_FILE and Path(COOKIES_FILE).exists():
            cmd.extend(["--cookies", COOKIES_FILE])

        result = run_cmd(cmd)

        if result.returncode != 0:
            logging.error(result.stdout)
            return None, result.stdout[-3500:]

        audio_file = find_audio_file(workdir)

        if not audio_file:
            return None, "Download finished but no audio file was found."

        display_title = clean_title(audio_file.stem)
        final_file = unique_path(
            DOWNLOAD_DIR / f"{clean_name(display_title)}{audio_file.suffix.lower()}"
        )

        shutil.move(str(audio_file), str(final_file))

        final_file = retag_audio_file(final_file, display_title)

        return final_file, "OK"

    finally:
        shutil.rmtree(workdir, ignore_errors=True)


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
        "/id\n"
        "/help\n\n"
        "Examples:\n"
        "/music https://youtube.com/watch?v=...\n"
        "/music https://soundcloud.com/artist/song\n"
        "/music the smiths how soon is now\n\n"
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

        audio_file, status = await asyncio.to_thread(download_audio, query)

        if not audio_file:
            logging.error("Download failed: %s", status)
            await notice.edit_text(
                "⚠️ Couldn't process that.\n\nTry another link or search."
            )
            return

        size = file_size_mb(audio_file)
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
                performer=artist,
                title=title,
            )

        await notice.delete()

    except Exception as e:
        logging.exception("Unhandled error")
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

    logging.info("%s v%s started.", BOT_NAME, BOT_VERSION)
    app.run_polling()


if __name__ == "__main__":
    main()

