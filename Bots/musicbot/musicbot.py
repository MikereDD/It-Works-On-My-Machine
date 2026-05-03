#!/usr/bin/env python3
# ------------------------------------------------------------
# file:     musicbot.py
# author:   Mike Redd
# version:  1.0.1
# created:  2026-05-03
# updated:  2026-05-03
# desc:     Telegram bot for downloading audio from supported sources
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

BOT_TOKEN = cfg.BOT_TOKEN
ALLOWED_USER_IDS = set(getattr(cfg, "ALLOWED_USER_IDS", []))
MAX_FILE_MB = int(getattr(cfg, "MAX_FILE_MB", 49))
AUDIO_FORMAT = getattr(cfg, "AUDIO_FORMAT", "mp3")
AUDIO_QUALITY = getattr(cfg, "AUDIO_QUALITY", "0")


# ── Helpers ──────────────────────────────────────────────────

def allowed(update: Update) -> bool:
    if not ALLOWED_USER_IDS:
        return True

    user = update.effective_user
    return bool(user and user.id in ALLOWED_USER_IDS)


def is_url(text: str) -> bool:
    return bool(re.match(r"^https?://", text.strip(), re.I))


def is_spotify_url(text: str) -> bool:
    return "open.spotify.com" in text.lower() or "spotify.link" in text.lower()


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
    files = [p for p in workdir.iterdir() if p.suffix.lower() in audio_exts]

    if not files:
        return None

    return max(files, key=lambda p: p.stat().st_size)


def clean_name(name: str) -> str:
    name = re.sub(r'[\\/:*?"<>|]', "-", name)
    name = re.sub(r"\s+", " ", name).strip()
    return name[:180]


def normalize_title_separators(title: str) -> str:
    """Normalize filename/video-title separators into a simple Artist - Title style."""
    title = title.replace("_", " ")
    title = title.replace("&amp;", "&")
    title = re.sub(r"\s*[–—−]\s*", " - ", title)
    title = re.sub(r"\s*[:|•]\s*", " - ", title)
    title = re.sub(r"\s+", " ", title)
    return title.strip(" -")


def clean_title(title: str) -> str:
    """Clean noisy yt-dlp/video titles for nicer Telegram display and ID3 title tags."""
    title = normalize_title_separators(title)

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
        r"\bremastered\b",
        r"\bHD\b",
        r"\b4K\b",
    ]

    for pattern in junk_patterns:
        title = re.sub(pattern, "", title, flags=re.IGNORECASE)

    title = normalize_title_separators(title)
    parts = [p.strip() for p in title.split(" - ") if p.strip()]

    # Fix duplicate artist patterns:
    # "The Smiths - The Smiths - How Soon Is Now" -> "The Smiths - How Soon Is Now"
    while len(parts) >= 2 and parts[0].casefold() == parts[1].casefold():
        parts.pop(1)

    # Keep sane Artist - Title output when YouTube gives extra fragments.
    if len(parts) >= 2:
        title = f"{parts[0]} - {parts[1]}"
    elif parts:
        title = parts[0]
    else:
        title = "audio"

    title = re.sub(r"\s+", " ", title).strip(" -")
    return title[:120] or "audio"


def split_artist_title(display_title: str) -> tuple[str | None, str]:
    """Return artist/title for Telegram and embedded metadata."""
    parts = [p.strip() for p in display_title.split(" - ", 1)]
    if len(parts) == 2 and parts[0] and parts[1]:
        return parts[0], parts[1]
    return None, display_title


def retag_audio_file(path: Path, display_title: str) -> Path:
    """Rewrite audio metadata so Telegram does not show the old messy yt-dlp title."""
    artist, song_title = split_artist_title(display_title)
    temp_path = path.with_name(f"{path.stem}.retag{path.suffix}")

    cmd = [
        "ffmpeg",
        "-y",
        "-i", str(path),
        "-map", "0",
        "-codec", "copy",
        "-metadata", f"title={song_title}",
    ]

    if artist:
        cmd.extend(["-metadata", f"artist={artist}"])

    cmd.append(str(temp_path))

    result = run_cmd(cmd)
    if result.returncode != 0 or not temp_path.exists():
        logging.warning("Metadata rewrite failed; using original file. Output: %s", result.stdout[-1000:])
        if temp_path.exists():
            temp_path.unlink(missing_ok=True)
        return path

    path.unlink(missing_ok=True)
    temp_path.rename(path)
    return path


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
    if is_url(input_text) and not is_spotify_url(input_text):
        return input_text

    return f"ytsearch1:{input_text}"


def download_audio(input_text: str) -> tuple[Path | None, str]:
    job_id = uuid.uuid4().hex[:8]
    workdir = DOWNLOAD_DIR / job_id
    workdir.mkdir(parents=True, exist_ok=True)

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

    result = run_cmd(cmd)

    if result.returncode != 0:
        logging.error(result.stdout)
        shutil.rmtree(workdir, ignore_errors=True)
        return None, result.stdout[-3500:]

    audio_file = find_audio_file(workdir)

    if not audio_file:
        shutil.rmtree(workdir, ignore_errors=True)
        return None, "Download finished but no audio file was found."

    cleaned_title = clean_title(audio_file.stem)
    final_file = unique_path(DOWNLOAD_DIR / f"{clean_name(cleaned_title)}{audio_file.suffix.lower()}")

    shutil.move(str(audio_file), str(final_file))
    final_file = retag_audio_file(final_file, cleaned_title)
    shutil.rmtree(workdir, ignore_errors=True)

    return final_file, "OK"


# ── Telegram Commands ────────────────────────────────────────

async def start_cmd(update: Update, context: ContextTypes.DEFAULT_TYPE):
    await help_cmd(update, context)


async def help_cmd(update: Update, context: ContextTypes.DEFAULT_TYPE):
    msg = (
        "🎵 MusicBot v1.0\n\n"
        "Commands:\n"
        "/music <url or search>\n"
        "/audio <url or search>\n"
        "/song <url or search>\n"
        "/id\n\n"
        "Examples:\n"
        "/music https://youtube.com/watch?v=...\n"
        "/music soundcloud link here\n"
        "/music artist - song title\n\n"
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

    notice = await update.message.reply_text("🎧 Working on it...")

    try:
        audio_file, status = await asyncio.to_thread(download_audio, query)

        if not audio_file:
            await notice.edit_text(f"Download failed:\n\n{status}")
            return

        size = file_size_mb(audio_file)

        if size > MAX_FILE_MB:
            await notice.edit_text(
                f"Downloaded, but file is too large for Telegram:\n"
                f"{audio_file.name}\n"
                f"{size:.1f} MB"
            )
            return

        await notice.edit_text("Uploading audio...")

        display_title = clean_title(audio_file.stem)
        display_artist, display_song = split_artist_title(display_title)

        with audio_file.open("rb") as f:
            await update.message.reply_audio(
                audio=f,
                filename=f"{display_title}{audio_file.suffix.lower()}",
                title=display_song[:64],
                performer=display_artist[:64] if display_artist else None,
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

    app = Application.builder().token(BOT_TOKEN).build()

    app.add_handler(CommandHandler("start", start_cmd))
    app.add_handler(CommandHandler("help", help_cmd))
    app.add_handler(CommandHandler("id", id_cmd))
    app.add_handler(CommandHandler("music", music_cmd))
    app.add_handler(CommandHandler("audio", music_cmd))
    app.add_handler(CommandHandler("song", music_cmd))

    logging.info("MusicBot started.")
    app.run_polling()


if __name__ == "__main__":
    main()

