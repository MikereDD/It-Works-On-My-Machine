#--------------------------------------------
# file: cardbot.py
# author: Mike Redd
# version: 0.3.0
# created: 2026-06-18
# updated: 2026-06-18
# desc: "Gabriel" - Telegram link-card bot.
#       Turns article/post URLs into clean
#       Open Graph preview cards with title,
#       blurb, hero image, and source link.
#--------------------------------------------

import asyncio
import html
import io
import logging
import os
import re
import sys
import time
from pathlib import Path
from urllib.parse import (
    parse_qsl,
    urlencode,
    urljoin,
    urlparse,
    urlsplit,
    urlunsplit,
)

# ── Branding ─────────────────────────────────────────────────
BOT_NAME = "Gabriel"
BOT_VERSION = "0.3.0"

import httpx
from bs4 import BeautifulSoup
from PIL import Image, ImageDraw, ImageFont

from telegram import Update
from telegram.constants import ChatAction, ParseMode
from telegram.ext import (
    ApplicationBuilder,
    CommandHandler,
    ContextTypes,
    MessageHandler,
    filters,
)
from telegram.request import HTTPXRequest

# ── Private Config ───────────────────────────────────────────
APP_DIR = Path(__file__).resolve().parent
ROOT_DIR = APP_DIR.parent
CONFIG_DIR = ROOT_DIR / "config"
CONFIG_FILE = CONFIG_DIR / "cardbotrc.py"

if not CONFIG_FILE.exists():
    raise RuntimeError(f"Missing config file: {CONFIG_FILE}")

sys.path.insert(0, str(CONFIG_DIR))
try:
    import cardbotrc
except Exception as e:
    raise RuntimeError(f"Failed to load config file {CONFIG_FILE}: {e}")

# Token may live in cardbotrc.py or the CARDBOT_TOKEN env var (env wins if rc blank).
BOT_TOKEN = getattr(cardbotrc, "BOT_TOKEN", "") or os.environ.get("CARDBOT_TOKEN", "")
OWNER_ID = getattr(cardbotrc, "ALLOWED_USER_ID", 0)
ADMIN_USERS = set(getattr(cardbotrc, "ADMIN_USERS", [OWNER_ID]) or [OWNER_ID])
ALLOWED_USERS = set(getattr(cardbotrc, "ALLOWED_USERS", [OWNER_ID]) or [OWNER_ID])
ALLOW_ALL_USERS = getattr(cardbotrc, "ALLOW_ALL_USERS", False)
AUTO_WATCH_DISABLED_CHAT_IDS = set(getattr(cardbotrc, "AUTO_WATCH_DISABLED_CHAT_IDS", []))
DEBUG_MODE = getattr(cardbotrc, "DEBUG_MODE", False)

_configured_base = getattr(cardbotrc, "BASE_DIR", ROOT_DIR)
BASE_DIR = Path(os.path.expandvars(os.path.expanduser(str(_configured_base)))).resolve()

if not BOT_TOKEN:
    raise RuntimeError(
        f"BOT_TOKEN is missing in {CONFIG_FILE} (or set CARDBOT_TOKEN env). "
        "Paste the token BotFather gave you."
    )
if not OWNER_ID:
    raise RuntimeError(
        f"ALLOWED_USER_ID is missing in {CONFIG_FILE}. "
        "Set the Telegram user ID that owns the bot."
    )

# ── Paths ────────────────────────────────────────────────────
LOG_DIR = BASE_DIR / "logs"
LOG_DIR.mkdir(parents=True, exist_ok=True)
LOG_FILE = LOG_DIR / "cardbot.log"

# Anything Gabriel ever writes to disk goes here (cards are sent from memory,
# so this is normally empty). /clean wipes it.
CACHE_DIR = APP_DIR / "cache"

# ── Logging ──────────────────────────────────────────────────
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s | %(levelname)s | %(name)s | %(message)s",
    handlers=[
        logging.FileHandler(LOG_FILE, encoding="utf-8"),
        logging.StreamHandler(sys.stdout),
    ],
)
log = logging.getLogger("cardbot")
log.setLevel(logging.INFO if DEBUG_MODE else logging.WARNING)

# ── Card layout / theme  (dark, cyan accent) ─────────────────
CARD_W = 1000
HERO_H = 520            # 1000x520 ~= 1.92:1, the standard OG image ratio
PAD = 48
LINE_GAP = 10

BG = (18, 18, 22)
FG_TITLE = (240, 240, 245)
FG_BODY = (165, 168, 180)
FG_META = (110, 200, 255)   # cyan
ACCENT = (110, 200, 255)

# ── Behaviour tunables ───────────────────────────────────────
MIN_HERO_PX = 400                      # short side; smaller -> text-only card
MAX_IMAGE_BYTES = 12 * 1024 * 1024     # skip oversized hero downloads
MAX_TITLE_CHARS = 250                  # keep caption under Telegram's 1024 limit
DEDUP_TTL = 30.0                       # seconds; suppress repeat link in a chat
HTTP_TIMEOUT = 15.0

# Tracking params stripped from the link shown in the caption.
TRACKING_PARAMS = {
    "utm_source", "utm_medium", "utm_campaign", "utm_term", "utm_content",
    "fbclid", "gclid", "igshid", "mc_cid", "mc_eid", "_ga", "ref_src",
}

USER_AGENT = (
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
    "(KHTML, like Gecko) Chrome/124.0 Safari/537.36"
)

URL_RE = re.compile(r"https?://\S+", re.IGNORECASE)

# Recent (chat_id, url) -> monotonic timestamp, for lightweight dedup.
_recent: dict[tuple[int, str], float] = {}

# ── Small helpers ────────────────────────────────────────────
def _clean_text(s: str | None) -> str | None:
    """Collapse runs of whitespace/newlines to single spaces."""
    if not s:
        return None
    s = re.sub(r"\s+", " ", s).strip()
    return s or None


def clean_url(u: str) -> str:
    """Drop known tracking query params; keep path and fragment intact."""
    try:
        parts = urlsplit(u)
        kept = [
            (k, v) for k, v in parse_qsl(parts.query, keep_blank_values=True)
            if k.lower() not in TRACKING_PARAMS
        ]
        return urlunsplit(
            (parts.scheme, parts.netloc, parts.path, urlencode(kept), parts.fragment)
        )
    except Exception:  # noqa: BLE001
        return u


def is_duplicate(chat_id: int, url: str) -> bool:
    """True if this (chat, url) was seen within DEDUP_TTL seconds."""
    now = time.monotonic()
    for key, ts in list(_recent.items()):
        if now - ts > DEDUP_TTL:
            _recent.pop(key, None)
    key = (chat_id, url)
    if key in _recent:
        return True
    _recent[key] = now
    return False


def _human_size(n: int) -> str:
    size = float(n)
    for unit in ("B", "KB", "MB", "GB", "TB"):
        if size < 1024 or unit == "TB":
            return f"{int(size)} {unit}" if unit == "B" else f"{size:.1f} {unit}"
        size /= 1024
    return f"{size:.1f} TB"


def _dir_stats(path: Path) -> tuple[int, int]:
    """(file_count, total_bytes) under path; (0, 0) if missing."""
    files = total = 0
    if path.exists():
        for p in path.rglob("*"):
            if p.is_file():
                files += 1
                total += p.stat().st_size
    return files, total


def _wipe_dir(path: Path) -> int:
    """Delete everything under path; return files removed."""
    removed = 0
    if not path.exists():
        return 0
    for p in sorted(path.rglob("*"), key=lambda x: len(x.parts), reverse=True):
        try:
            if p.is_file() or p.is_symlink():
                p.unlink()
                removed += 1
            elif p.is_dir():
                p.rmdir()
        except OSError as e:
            log.warning("clean: could not remove %s: %s", p, e)
    return removed


def _truncate_log() -> int:
    """Truncate the log through the active handler; return bytes freed."""
    size = LOG_FILE.stat().st_size if LOG_FILE.exists() else 0
    for h in logging.getLogger().handlers:
        if isinstance(h, logging.FileHandler):
            try:
                h.acquire()
                h.stream.seek(0)
                h.stream.truncate()
            except OSError as e:
                log.warning("clean: log truncate failed: %s", e)
            finally:
                h.release()
    return size

# ── Fonts / text helpers ─────────────────────────────────────
def _load_font(bold: bool, size: int) -> ImageFont.FreeTypeFont:
    bold_paths = [
        "/usr/share/fonts/TTF/DejaVuSans-Bold.ttf",            # Arch (arakiel)
        "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
        "C:/Windows/Fonts/segoeuib.ttf",
        "C:/Windows/Fonts/arialbd.ttf",
    ]
    reg_paths = [
        "/usr/share/fonts/TTF/DejaVuSans.ttf",
        "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
        "C:/Windows/Fonts/segoeui.ttf",
        "C:/Windows/Fonts/arial.ttf",
    ]
    for path in (bold_paths if bold else reg_paths):
        try:
            return ImageFont.truetype(path, size)
        except OSError:
            continue
    return ImageFont.load_default()


def _line_h(font: ImageFont.FreeTypeFont) -> int:
    asc, desc = font.getmetrics()
    return asc + desc


def _wrap(draw, text, font, max_w, max_lines):
    """Word-wrap to max_lines, appending an ellipsis if text is truncated."""
    words = (text or "").split()
    lines, cur, i = [], "", 0
    while i < len(words):
        trial = f"{cur} {words[i]}".strip()
        if draw.textlength(trial, font=font) <= max_w:
            cur, i = trial, i + 1
        else:
            if not cur:                     # one word longer than the line
                cur, i = words[i], i + 1
            lines.append(cur)
            cur = ""
            if len(lines) == max_lines:
                break
    if cur and len(lines) < max_lines:
        lines.append(cur)

    if i < len(words) and lines:            # truncated -> ellipsize last line
        last = lines[-1]
        while last and draw.textlength(last + " \u2026", font=font) > max_w:
            last = last.rsplit(" ", 1)[0] if " " in last else last[:-1]
        lines[-1] = (last + " \u2026").strip()
    return lines


def _cover(img: Image.Image, w: int, h: int) -> Image.Image:
    """Resize + center-crop to fill w x h (CSS object-fit: cover)."""
    img = img.convert("RGB")
    sw, sh = img.size
    scale = max(w / sw, h / sh)
    nw, nh = int(sw * scale + 0.5), int(sh * scale + 0.5)
    img = img.resize((nw, nh), Image.LANCZOS)
    left, top = (nw - w) // 2, (nh - h) // 2
    return img.crop((left, top, left + w, top + h))

# ── Card rendering ───────────────────────────────────────────
def render_card(title, description, domain, hero: Image.Image | None) -> bytes:
    title_font = _load_font(True, 46)
    body_font = _load_font(False, 30)
    meta_font = _load_font(True, 26)

    measure = ImageDraw.Draw(Image.new("RGB", (CARD_W, 10)))
    inner_w = CARD_W - 2 * PAD

    title_lines = _wrap(measure, title or "(untitled)", title_font, inner_w, 3)
    body_lines = _wrap(measure, description, body_font, inner_w, 4) if description else []

    th = len(title_lines) * _line_h(title_font) + LINE_GAP * (len(title_lines) - 1)
    bh = (len(body_lines) * _line_h(body_font) + LINE_GAP * (len(body_lines) - 1)) if body_lines else 0
    meta_h = _line_h(meta_font)

    top = HERO_H if hero is not None else 8
    content_h = meta_h + 18 + th + ((24 + bh) if bh else 0)
    card_h = top + PAD + content_h + PAD

    card = Image.new("RGB", (CARD_W, card_h), BG)
    draw = ImageDraw.Draw(card)

    if hero is not None:
        card.paste(_cover(hero, CARD_W, HERO_H), (0, 0))
    else:
        draw.rectangle([0, 0, CARD_W, 8], fill=ACCENT)   # accent band when no image

    y = top + PAD
    draw.text((PAD, y), domain.upper(), font=meta_font, fill=FG_META)
    y += meta_h + 18
    for ln in title_lines:
        draw.text((PAD, y), ln, font=title_font, fill=FG_TITLE)
        y += _line_h(title_font) + LINE_GAP
    if body_lines:
        y += 14
        for ln in body_lines:
            draw.text((PAD, y), ln, font=body_font, fill=FG_BODY)
            y += _line_h(body_font) + LINE_GAP

    buf = io.BytesIO()
    card.save(buf, format="PNG")
    return buf.getvalue()

# ── Fetch / metadata ─────────────────────────────────────────
async def fetch_html(url: str):
    async with httpx.AsyncClient(
        headers={"User-Agent": USER_AGENT}, follow_redirects=True, timeout=HTTP_TIMEOUT
    ) as client:
        r = await client.get(url)
        r.raise_for_status()
        ctype = r.headers.get("content-type", "").lower()
        if "html" not in ctype:
            raise ValueError(f"unsupported content-type: {ctype or 'unknown'}")
        return r.text, str(r.url)


def _meta(soup: BeautifulSoup, *names):
    for name in names:
        tag = soup.find("meta", property=name) or soup.find("meta", attrs={"name": name})
        if tag and tag.get("content"):
            return tag["content"].strip()
    return None


def extract_metadata(html_text: str, base_url: str) -> dict:
    soup = BeautifulSoup(html_text, "html.parser")
    title = _clean_text(_meta(soup, "og:title", "twitter:title")) or _clean_text(
        soup.title.string if soup.title and soup.title.string else None
    )
    desc = _clean_text(_meta(soup, "og:description", "twitter:description", "description"))
    img = _meta(soup, "og:image", "og:image:url", "twitter:image", "twitter:image:src")
    if img:
        img = urljoin(base_url, img.strip())
    domain = urlparse(base_url).netloc.replace("www.", "")
    return {"title": title, "description": desc, "image": img, "domain": domain}


async def fetch_image(url: str | None):
    if not url:
        return None
    try:
        async with httpx.AsyncClient(
            headers={"User-Agent": USER_AGENT}, follow_redirects=True, timeout=HTTP_TIMEOUT
        ) as client:
            r = await client.get(url)
            r.raise_for_status()
            if len(r.content) > MAX_IMAGE_BYTES:
                log.warning("hero too large (%d bytes), skipping", len(r.content))
                return None
            img = Image.open(io.BytesIO(r.content))
            img.load()                      # force decode now so errors land here
            return img
    except Exception as e:  # noqa: BLE001
        log.warning("hero image failed: %s", e)
        return None

# ── Access control  (mirrors ytbot's group auto-watch model) ─
def is_admin(user_id: int) -> bool:
    return user_id in ADMIN_USERS or user_id == OWNER_ID


def can_use_context(user_id: int, chat_id: int, chat_type: str) -> bool:
    """Groups/supergroups: anyone. Private: owner (or allow-listed). Else: no."""
    if chat_type in ("group", "supergroup"):
        return True
    if chat_type == "private":
        return ALLOW_ALL_USERS or user_id in ALLOWED_USERS or is_admin(user_id)
    return False


def auto_watch_disabled_for_chat(chat) -> bool:
    if not chat or getattr(chat, "type", None) not in ("group", "supergroup"):
        return False
    return int(chat.id) in AUTO_WATCH_DISABLED_CHAT_IDS


def message_has_native_media(message) -> bool:
    """Skip passive link-watch when the message already carries Telegram media."""
    if not message:
        return False
    attrs = ("photo", "video", "animation", "document", "audio", "voice", "video_note")
    return any(bool(getattr(message, a, None)) for a in attrs)

# ── Handlers ─────────────────────────────────────────────────
async def cmd_start(update: Update, context: ContextTypes.DEFAULT_TYPE):
    await update.effective_message.reply_text(
        f"I'm {BOT_NAME} (v{BOT_VERSION}). Send me a link and I'll reply with a "
        "preview card.\nWorks best on news and blog articles."
    )


async def cmd_status(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Owner-only: report what Gabriel currently has on disk / in memory."""
    user = update.effective_user
    if not user or not is_admin(user.id):
        return
    log_size = LOG_FILE.stat().st_size if LOG_FILE.exists() else 0
    files, total = _dir_stats(CACHE_DIR)
    await update.effective_message.reply_text(
        f"<b>{BOT_NAME} v{BOT_VERSION}</b>\n"
        f"log: {_human_size(log_size)}\n"
        f"cache: {files} file(s), {_human_size(total)}\n"
        f"dedup: {len(_recent)} in memory",
        parse_mode=ParseMode.HTML,
    )


async def cmd_clean(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Owner-only: wipe the cache dir, truncate the log, clear the dedup cache."""
    user = update.effective_user
    if not user or not is_admin(user.id):
        return
    _, cache_bytes = _dir_stats(CACHE_DIR)
    removed = _wipe_dir(CACHE_DIR)
    log_freed = _truncate_log()
    dedup = len(_recent)
    _recent.clear()
    await update.effective_message.reply_text(
        f"Cleaned.\n"
        f"cache: removed {removed} file(s) ({_human_size(cache_bytes)})\n"
        f"log: freed {_human_size(log_freed)}\n"
        f"dedup: cleared {dedup} entr{'y' if dedup == 1 else 'ies'}"
    )


def build_caption(title: str, url: str) -> str:
    title = (title or "").strip()
    if len(title) > MAX_TITLE_CHARS:
        title = title[: MAX_TITLE_CHARS - 1].rstrip() + "\u2026"
    return f"<b>{html.escape(title)}</b>\n{url}"


async def handle_url(update: Update, context: ContextTypes.DEFAULT_TYPE):
    msg = update.effective_message
    chat = update.effective_chat
    user = update.effective_user
    if not msg or not chat or not user or not msg.text:
        return
    if not can_use_context(user.id, chat.id, chat.type):
        return
    if auto_watch_disabled_for_chat(chat):
        return
    if message_has_native_media(msg):
        return

    m = URL_RE.search(msg.text)
    if not m:                       # silent in groups when there's no link
        return
    url = m.group(0).rstrip(").,]\"'")

    if is_duplicate(chat.id, clean_url(url)):
        return

    await context.bot.send_chat_action(msg.chat_id, ChatAction.UPLOAD_PHOTO)
    try:
        page_html, final = await fetch_html(url)
        meta = extract_metadata(page_html, final)
        hero = await fetch_image(meta["image"])
        if hero is not None and min(hero.size) < MIN_HERO_PX:
            hero = None             # too small -> clean text card, not a blurry upscale
        png = await asyncio.to_thread(
            render_card, meta["title"], meta["description"], meta["domain"], hero
        )
    except Exception as e:  # noqa: BLE001
        log.warning("card build failed for %s: %s", url, e)
        if chat.type == "private":  # stay quiet in groups; just notify in DMs
            await msg.reply_text("Couldn't build a card for that link.")
        return

    title = meta["title"] or meta["domain"]
    caption = build_caption(title, clean_url(final))
    await msg.reply_photo(photo=png, caption=caption, parse_mode=ParseMode.HTML)

# ── Main ─────────────────────────────────────────────────────
def main():
    request = HTTPXRequest(connect_timeout=20, read_timeout=40, write_timeout=60)
    app = ApplicationBuilder().token(BOT_TOKEN).request(request).build()
    app.add_handler(CommandHandler(["start", "help"], cmd_start))
    app.add_handler(CommandHandler("status", cmd_status))
    app.add_handler(CommandHandler("clean", cmd_clean))
    app.add_handler(MessageHandler(filters.TEXT & ~filters.COMMAND, handle_url))
    print(f"{BOT_NAME} v{BOT_VERSION} - starting (debug={DEBUG_MODE})")
    app.run_polling()


if __name__ == "__main__":
    main()
