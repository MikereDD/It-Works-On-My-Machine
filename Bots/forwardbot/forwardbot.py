#!/usr/bin/env python3
# file:    forwardbot.py
# author:  typezero
# version: 0.1.0
# desc:    DM a forwarded channel post to this bot. It reconstructs the post
#          (dropping the "Forwarded from" header), strips links/@mentions that
#          point at the SOURCE channel, keeps every other link, appends a
#          "Source" link to the original post, and reposts to a channel.
#
# requires: python-telegram-bot >= 21   ->  pip install "python-telegram-bot>=21"
# config:   edit forwardbotrc.py (token, target channel, allowed users, etc.)
# run:      python3 forwardbot.py   (on arakiel)

import re
import logging

from telegram import Update, MessageOriginChannel, LinkPreviewOptions
from telegram.constants import ParseMode
from telegram.ext import Application, MessageHandler, ContextTypes, filters

try:
    from forwardbotrc import (
        BOT_TOKEN, TARGET_CHANNEL, ALLOWED_USER_IDS,
        SOURCE_LABEL, DISABLE_PREVIEWS, EXTRA_BLOCKED,
    )
except ImportError as e:
    raise SystemExit(
        "Missing or broken forwardbotrc.py - copy it next to forwardbot.py "
        f"and fill in your values. ({e})"
    )

logging.basicConfig(
    format="%(asctime)s %(levelname)s %(name)s | %(message)s", level=logging.INFO
)
log = logging.getLogger("forwardbot")


def strip_self_links(html: str, blocked: set) -> str:
    """Remove anchors / @mentions / bare t.me URLs that point at the source
    channel (or any EXTRA_BLOCKED handle). All other links are left untouched."""
    if not html:
        return html

    handles = {u.lstrip("@").lower() for u in blocked if u}

    def is_self_href(href: str) -> bool:
        h = href.lower().strip()
        for u in handles:
            if re.search(rf'(?:t|telegram)\.me/{re.escape(u)}(?:/|\b)', h):
                return True
            if re.search(rf'tg://resolve\?domain={re.escape(u)}\b', h):
                return True
        return False

    # drop whole <a ...>...</a> blocks whose href is a self link
    def anchor_sub(m: re.Match) -> str:
        return "" if is_self_href(m.group(1)) else m.group(0)

    html = re.sub(r'<a\s+href="([^"]*)"[^>]*>.*?</a>', anchor_sub, html,
                  flags=re.IGNORECASE | re.DOTALL)

    # drop bare @mentions and bare t.me/<user> URLs of blocked handles
    for u in handles:
        html = re.sub(rf'(?<![\w@])@{re.escape(u)}\b', "", html, flags=re.IGNORECASE)
        html = re.sub(rf'https?://(?:t|telegram)\.me/{re.escape(u)}\b[^\s<]*', "",
                      html, flags=re.IGNORECASE)

    # tidy leftover whitespace / blank lines
    html = re.sub(r'[ \t]{2,}', ' ', html)
    html = re.sub(r'\n{3,}', '\n\n', html)
    return html.strip()


async def handle_forward(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    msg, user = update.effective_message, update.effective_user

    if ALLOWED_USER_IDS and (user is None or user.id not in ALLOWED_USER_IDS):
        return  # silently ignore strangers

    origin = msg.forward_origin
    if not isinstance(origin, MessageOriginChannel):
        await msg.reply_text("I can only repost posts forwarded from a channel.")
        return

    src_user = (origin.chat.username or "").lower()
    src_id   = origin.message_id

    blocked = set(EXTRA_BLOCKED)
    if src_user:
        blocked.add(src_user)

    # body = text message OR media caption, as HTML so entities survive
    body = strip_self_links(msg.text_html or msg.caption_html or "", blocked)

    # attribution link to the original (public channels only)
    if src_user:
        attribution = f'\U0001F517 <a href="https://t.me/{src_user}/{src_id}">{SOURCE_LABEL}</a>'
    else:
        attribution = ""  # private channel -> no public permalink

    final = "\n\n".join(p for p in (body, attribution) if p)
    preview = LinkPreviewOptions(is_disabled=DISABLE_PREVIEWS)

    try:
        if msg.photo:
            await context.bot.send_photo(TARGET_CHANNEL, msg.photo[-1].file_id,
                                         caption=final or None, parse_mode=ParseMode.HTML)
        elif msg.video:
            await context.bot.send_video(TARGET_CHANNEL, msg.video.file_id,
                                         caption=final or None, parse_mode=ParseMode.HTML)
        elif msg.animation:
            await context.bot.send_animation(TARGET_CHANNEL, msg.animation.file_id,
                                             caption=final or None, parse_mode=ParseMode.HTML)
        elif msg.document:
            await context.bot.send_document(TARGET_CHANNEL, msg.document.file_id,
                                            caption=final or None, parse_mode=ParseMode.HTML)
        elif msg.audio:
            await context.bot.send_audio(TARGET_CHANNEL, msg.audio.file_id,
                                         caption=final or None, parse_mode=ParseMode.HTML)
        elif msg.voice:
            await context.bot.send_voice(TARGET_CHANNEL, msg.voice.file_id,
                                         caption=final or None, parse_mode=ParseMode.HTML)
        elif final:
            await context.bot.send_message(TARGET_CHANNEL, final,
                                           parse_mode=ParseMode.HTML,
                                           link_preview_options=preview)
        else:
            await msg.reply_text("Nothing to repost after cleaning.")
            return
    except Exception as e:                       # noqa: BLE001
        log.exception("repost failed")
        await msg.reply_text(f"Repost failed: {e}")
        return

    await msg.reply_text("\u2713 Reposted.")


def main() -> None:
    app = Application.builder().token(BOT_TOKEN).build()
    app.add_handler(MessageHandler(
        filters.FORWARDED & filters.ChatType.PRIVATE, handle_forward))
    log.info("forwardbot up; waiting for forwarded posts\u2026")
    app.run_polling(allowed_updates=Update.ALL_TYPES)


if __name__ == "__main__":
    main()
