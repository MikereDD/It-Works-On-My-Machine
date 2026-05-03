#!/usr/bin/env python3
# ------------------------------------------------------------
# file:     musicbot.py
# author:   Mike Redd
# version:  1.3
# desc:     Sandalphon - Queue system added
# ------------------------------------------------------------

import asyncio
import logging
import re
import shutil
import subprocess
import sys
import uuid
from pathlib import Path
from collections import deque

from telegram import Update
from telegram.ext import Application, CommandHandler, ContextTypes

# ── Branding ─────────────────────────────────────────────────
BOT_NAME = "Sandalphon"
BOT_VERSION = "1.3"

# ── Config ───────────────────────────────────────────────────
sys.path.insert(0, str(Path.home() / "bots/config"))
import musicbotrc as cfg

BOT_TOKEN = cfg.BOT_TOKEN
DOWNLOAD_DIR = Path(cfg.DOWNLOAD_DIR)
DOWNLOAD_DIR.mkdir(parents=True, exist_ok=True)

MAX_FILE_MB = int(getattr(cfg, "MAX_FILE_MB", 49))

# ── Queue System ─────────────────────────────────────────────
QUEUE = deque()
PROCESSING = False

# ── Helpers ──────────────────────────────────────────────────
def run_cmd(cmd):
    return subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE)

def file_size_mb(path):
    return path.stat().st_size / (1024 * 1024)

def clean_title(title):
    title = title.replace("_", " ")
    title = re.sub(r"\(.*?\)|\[.*?\]", "", title)
    title = re.sub(r"\s+", " ", title).strip()
    return title

def download_audio(query):
    job = DOWNLOAD_DIR / uuid.uuid4().hex
    job.mkdir(parents=True, exist_ok=True)

    target = f"ytsearch1:{query}" if not query.startswith("http") else query

    cmd = [
        "yt-dlp",
        "-x",
        "--audio-format", "mp3",
        "-o", str(job / "%(title)s.%(ext)s"),
        target,
    ]

    run_cmd(cmd)

    files = list(job.glob("*.mp3"))
    if not files:
        return None

    file = files[0]
    final = DOWNLOAD_DIR / file.name
    shutil.move(file, final)
    shutil.rmtree(job, ignore_errors=True)

    return final

# ── Queue Processor ──────────────────────────────────────────
async def process_queue(app):
    global PROCESSING

    if PROCESSING:
        return

    PROCESSING = True

    while QUEUE:
        update, query = QUEUE.popleft()
        chat_id = update.effective_chat.id

        try:
            msg = await app.bot.send_message(chat_id, f"🎶 Processing: {query}")

            audio = await asyncio.to_thread(download_audio, query)

            if not audio:
                await msg.edit_text("❌ Failed")
                continue

            size = file_size_mb(audio)
            title = clean_title(audio.stem)

            if size > MAX_FILE_MB:
                await msg.edit_text("📦 Too large")
                continue

            await msg.edit_text("⬆️ Sending...")

            with audio.open("rb") as f:
                await app.bot.send_audio(chat_id, audio=f, title=title)

            await msg.delete()

        except Exception as e:
            logging.exception("Queue error")

    PROCESSING = False

# ── Commands ─────────────────────────────────────────────────
async def music(update: Update, context: ContextTypes.DEFAULT_TYPE):
    query = " ".join(context.args)

    QUEUE.append((update, query))

    await update.message.reply_text(f"➕ Added to queue ({len(QUEUE)})")

    asyncio.create_task(process_queue(context.application))

async def queue_cmd(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if not QUEUE:
        await update.message.reply_text("Queue empty")
        return

    text = "\n".join([f"{i+1}. {q}" for i, (_, q) in enumerate(QUEUE)])
    await update.message.reply_text(text)

# ── Main ─────────────────────────────────────────────────────
def main():
    app = Application.builder().token(BOT_TOKEN).build()

    app.add_handler(CommandHandler("music", music))
    app.add_handler(CommandHandler("queue", queue_cmd))

    app.run_polling()

if __name__ == "__main__":
    main()
