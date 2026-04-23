#--------------------------------------------
# file:     ytbot.py
# author:   Mike Redd
# version:  5.0
# created:  2026-04-18
# updated:  2026-04-22
# desc:     Queue-based Telegram media bot
#           with interactive UI, weather,
#           forecast, routing, archive send,
#           watch folder, CLI mode,
#           and clip support
#--------------------------------------------

import argparse
import asyncio
from datetime import datetime
import json
import logging
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

import yt_dlp
from telegram import (
    InlineKeyboardButton,
    InlineKeyboardMarkup,
    Update,
)
from telegram.constants import ParseMode
from telegram.ext import (
    ApplicationBuilder,
    CallbackQueryHandler,
    ChatMemberHandler,
    CommandHandler,
    ContextTypes,
    MessageHandler,
    filters,
)

# ── Private Config ──────────────────────────────────────────────────────────────
CONFIG_DIR = Path("G:/bots/config")
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

BASE_DIR = Path(getattr(ytbotrc, "BASE_DIR", "G:/bots"))

ADMIN_USERS = set(getattr(ytbotrc, "ADMIN_USERS", [OWNER_ID]) or [OWNER_ID])
ALLOWED_USERS = set(getattr(ytbotrc, "ALLOWED_USERS", [OWNER_ID]) or [OWNER_ID])
ALLOW_ALL_USERS = getattr(ytbotrc, "ALLOW_ALL_USERS", False)

DOWNLOAD_TIMEOUT = getattr(ytbotrc, "DOWNLOAD_TIMEOUT", 900)
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
LOG_FILE = LOG_DIR / "ytbot.log"

for d in [
    STATE_DIR, DOWNLOAD_DIR, LOG_DIR, DONE_VIDEO_DIR,
    DONE_AUDIO_DIR, FAILED_DIR, WATCH_DIR, COOKIES_DIR
]:
    d.mkdir(parents=True, exist_ok=True)

# ── Limits ──────────────────────────────────────────────────────────────────────
DELETE_AFTER_SEND      = False
MAX_UPLOAD_BYTES       = 49 * 1024 * 1024
MIN_VALID_VIDEO_BYTES  = 100 * 1024
MIN_VALID_AUDIO_BYTES  = 100 * 1024
MAX_HISTORY_ENTRIES    = 500

# ── Globals ─────────────────────────────────────────────────────────────────────
URL_RE = re.compile(r"https?://\S+", re.IGNORECASE)
QUEUE: list[dict] = []
HISTORY: list[dict] = []
FAILURES: list[dict] = []
KNOWN_CHATS: dict = {}
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


# ── Helpers ─────────────────────────────────────────────────────────────────────
def is_admin(user_id: int) -> bool:
    return user_id in ADMIN_USERS or user_id == OWNER_ID

def can_use(user_id: int) -> bool:
    return ALLOW_ALL_USERS or user_id in ALLOWED_USERS or is_admin(user_id)

def can_use_context(user_id: int, chat_id: int, chat_type: str) -> bool:
    allowed_chat_ids = set(getattr(ytbotrc, "ALLOWED_CHAT_IDS", []))

    if chat_type in ("group", "supergroup"):
        return chat_id in allowed_chat_ids

    if chat_type == "private":
        return user_id == OWNER_ID

    return False

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

def read_last_log_lines(max_lines: int = 500) -> list[str]:
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

    lines = [f"🗓️ *5-Day Forecast for {label}*", ""]

    for i, day_str in enumerate(times):
        try:
            day_name = datetime.fromisoformat(day_str).strftime("%a")
        except Exception:
            day_name = day_str

        code = codes[i] if i < len(codes) else None
        icon = weather_code_to_icon(code)
        _, text = WEATHER_CODE_MAP.get(code, ("❓", "Unknown")) if code is not None else ("❓", "Unknown")

        try:
            weekday_idx = datetime.fromisoformat(day_str).weekday()
        except Exception:
            weekday_idx = i % 7
        lines.append(f"{WEEKDAY_EMOJI.get(weekday_idx, '📅')} *{day_name}* — {icon} {text}")
        if i < len(highs):
            lines.append(f"   🔺 {highs[i]}{units.get('temperature_2m_max', '°F')}")
        if i < len(lows):
            lines.append(f"   🔻 {lows[i]}{units.get('temperature_2m_min', '°F')}")
        if i < len(rains):
            lines.append(f"   🌧️ {rains[i]} {units.get('precipitation_sum', 'in')}")
        if i != len(times) - 1:
            lines.append("")

    return "\n".join(lines)


# ── Media metadata / download ───────────────────────────────────────────────────
def is_youtube_url(url: str) -> bool:
    lower = url.lower()
    return "youtube.com/" in lower or "youtu.be/" in lower or "m.youtube.com/" in lower

def is_instagram_url(url: str) -> bool:
    return "instagram.com/" in url.lower()

def get_cookiefile_for_url(url: str) -> str | None:
    if is_youtube_url(url) and YOUTUBE_COOKIES_FILE.exists():
        return str(YOUTUBE_COOKIES_FILE)
    return None

def get_media_info(url: str) -> dict:
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

    return {
        "title": info.get("title", "Unknown title"),
        "duration": info.get("duration"),
        "uploader": info.get("uploader", "Unknown uploader"),
        "webpage_url": info.get("webpage_url", url),
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

def build_ydl_opts(url: str, outtmpl: str, mode: str) -> dict:
    opts: dict = {
        "outtmpl": outtmpl,
        "noplaylist": True,
        "quiet": True,
        "no_warnings": True,
        "restrictfilenames": False,
        "compat_opts": ["no-certifi"],
    }

    if mode == "audio":
        opts["format"] = "bestaudio/best"
        opts["postprocessors"] = [{
            "key": "FFmpegExtractAudio",
            "preferredcodec": "mp3",
            "preferredquality": "192",
        }]
    else:
        if is_instagram_url(url):
            opts["format"] = "best/b/worst/bv*+ba"
            opts["nocheckcertificate"] = True
        else:
            opts["format"] = "bv*+ba/b"
            opts["merge_output_format"] = "mp4"

    cookiefile = get_cookiefile_for_url(url)
    if cookiefile:
        opts["cookiefile"] = cookiefile

    return opts

def download_media(url: str, mode: str) -> Path:
    clear_download_dir()

    ext_hint = "%(ext)s" if mode != "audio" else "mp3"
    outtmpl = str(DOWNLOAD_DIR / f"%(title).100s [%(id)s].{ext_hint}")

    opts = build_ydl_opts(url, outtmpl, mode)

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
        if job.get("source") in ("ui", "dl", "audio", "clip"):
            caption_lines = [
                f"🎞️ {meta['title']}",
                f"👤 {meta['uploader']}",
                f"🔗 {meta['webpage_url']}",
            ]
            if mode == "clip" and clip_start and clip_end:
                caption_lines.append(f"✂️ {clip_start} → {clip_end}")
            caption = "\n".join(caption_lines)[:1000]

        await status_msg.edit_text(
            f"🎞️ {meta['title']}\n"
            f"👤 {meta['uploader']}\n"
            f"⏱️ {format_duration(meta['duration'])}\n\n"
            f"⬇️ Downloading {mode}…"
        )

        download_mode = "audio" if mode == "audio" else "video"

        downloaded_file = await asyncio.wait_for(
            asyncio.to_thread(download_media, url, download_mode),
            timeout=DOWNLOAD_TIMEOUT,
        )
        sent_file = downloaded_file

        if mode == "clip":
            if not clip_start or not clip_end:
                raise RuntimeError("Clip job is missing start or end time.")
            await status_msg.edit_text(
                f"🎞️ {meta['title']}\n"
                f"👤 {meta['uploader']}\n"
                f"✂️ Clipping {clip_start} → {clip_end}…"
            )
            clipped = await asyncio.to_thread(clip_video, sent_file, clip_start, clip_end)
            if sent_file.exists():
                sent_file.unlink()
            sent_file = clipped

        if mode in ("video", "clip"):
            size_mb = sent_file.stat().st_size / (1024 * 1024)
            if size_mb > 49:
                await status_msg.edit_text(f"📦 Large file ({size_mb:.1f} MB)\nProcessing…")
                compressed = await asyncio.to_thread(compress_to_telegram, sent_file)
                if sent_file.exists():
                    sent_file.unlink()
                sent_file = compressed

        size_str = format_size(sent_file.stat().st_size)
        await status_msg.edit_text(f"📤 Uploading… ({size_str})")

        with sent_file.open("rb") as f:
            if mode == "audio":
                await app.bot.send_audio(
                    chat_id,
                    f,
                    filename=sent_file.name,
                    caption=caption,
                    reply_to_message_id=reply_to_message_id
                )
            else:
                try:
                    await app.bot.send_video(
                        chat_id,
                        f,
                        filename=sent_file.name,
                        supports_streaming=True,
                        caption=caption,
                        reply_to_message_id=reply_to_message_id
                    )
                except Exception:
                    f.seek(0)
                    await app.bot.send_document(
                        chat_id,
                        f,
                        filename=sent_file.name,
                        caption=caption,
                        reply_to_message_id=reply_to_message_id
                    )

        if ARCHIVE_CHAT_ID:
            with sent_file.open("rb") as f:
                if mode == "audio":
                    await app.bot.send_audio(
                        ARCHIVE_CHAT_ID,
                        f,
                        filename=sent_file.name,
                        caption=caption
                    )
                else:
                    try:
                        await app.bot.send_video(
                            ARCHIVE_CHAT_ID,
                            f,
                            filename=sent_file.name,
                            supports_streaming=True,
                            caption=caption
                        )
                    except Exception:
                        f.seek(0)
                        await app.bot.send_document(
                            ARCHIVE_CHAT_ID,
                            f,
                            filename=sent_file.name,
                            caption=caption
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
                urls = [
                    line.strip()
                    for line in txt_file.read_text(encoding="utf-8").splitlines()
                    if extract_url(line.strip())
                ]
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
                InlineKeyboardButton("🎬 Video", callback_data=f"dl|video|{short_id}"),
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

    mode = action
    url = pending["url"]

    job = create_job(user.id, chat.id, url, mode=mode, source="ui")
    QUEUE.append(job)
    save_queue_state()

    pos = get_queue_position()
    await query.edit_message_text(
        f"✅ Added to queue\n"
        f"🔢 Position: {pos}\n"
        f"{'🎬' if mode == 'video' else '🎵'} Mode: {mode}",
        parse_mode=ParseMode.MARKDOWN,
    )


# ── Commands ────────────────────────────────────────────────────────────────────
USER_COMMAND_LIST = (
    "/start         — welcome & command list\n"
    "/help          — usage instructions\n"
    "/dl <url>      — queue video download\n"
    "/audio <url>   — queue audio download\n"
    "/clip <url> <start> <end> — queue clipped video\n"
    "/ui <url>      — preview with buttons\n"
    "/queue         — show queue\n"
    "/weather <p>   — current weather\n"
    "/forecast <p>  — 5-day forecast\n"
    "/whoami        — show your Telegram/chat IDs"
)

ADMIN_COMMAND_LIST = (
    "/lastusers     — recent users seen in logs\n"
    "/stats         — usage summary\n"
    "/status        — bot status\n"
    "/groups        — list remembered groups\n"
    "/cleanup       — clear downloads folder\n"
    "/failures      — recent failures\n"
    "/retrylast     — retry last failure\n"
    "/clearqueue    — clear queue\n"
    "/leave         — leave current group\n"
    "/leavechat     — leave a group by ID\n"
    "/shutdown      — stop the bot"
)

async def start_cmd(update: Update, _ctx: ContextTypes.DEFAULT_TYPE) -> None:
    remember_chat(update.effective_chat)

    user = update.effective_user
    chat = update.effective_chat

    lines = [
        "👋 *YT Bot v5.0*",
        "",
        "Send me a link or use a command:",
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
        "📖 *Help*",
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

async def dl_cmd(update: Update, ctx: ContextTypes.DEFAULT_TYPE) -> None:
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
            "/dl https://example.com/video"
        )
        return

    QUEUE.append(create_job(
        update.effective_user.id,
        update.effective_chat.id,
        url,
        mode="video",
        source="dl"
    ))
    save_queue_state()
    pos = get_queue_position()
    await update.message.reply_text(
        f"📥 Added to queue\n"
        f"🔢 Position: {pos}\n"
        f"🎬 Mode: video"
    )

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

    if not ffmpeg_exists():
        await update.message.reply_text("ffmpeg is required for audio extraction.")
        return

    QUEUE.append(create_job(
        update.effective_user.id,
        update.effective_chat.id,
        url,
        mode="audio",
        source="audio"
    ))
    save_queue_state()
    pos = get_queue_position()
    await update.message.reply_text(
        f"📥 Added to queue\n"
        f"🔢 Position: {pos}\n"
        f"🎵 Mode: audio"
    )

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

    QUEUE.append(create_job(
        update.effective_user.id,
        update.effective_chat.id,
        url,
        mode="clip",
        source="clip",
        reply_to_message_id=update.message.message_id if update.message else None,
        clip_start=clip_start,
        clip_end=clip_end,
    ))
    save_queue_state()

    pos = get_queue_position()
    await update.message.reply_text(
        f"✂️ Clip added to queue\n"
        f"🔢 Position: {pos}\n"
        f"🕒 {clip_start} → {clip_end}"
    )

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
        ])

    if QUEUE:
        lines.extend(["", "*Pending:*"])
        for idx, job in enumerate(QUEUE[:10], start=1):
            lines.append(f"{idx}. `{job['url']}` [{job.get('mode', 'video')}]")

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
        await update.message.reply_text(result, parse_mode=ParseMode.MARKDOWN)
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
        await update.message.reply_text(result, parse_mode=ParseMode.MARKDOWN)
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

    await update.message.reply_text(
        f"*Bot Status:* online\n"
        f"*Current Job:* {'yes' if CURRENT_JOB else 'no'}\n"
        f"*Queue Length:* {len(QUEUE)}\n"
        f"*Archive Chat:* {ARCHIVE_CHAT_ID if ARCHIVE_CHAT_ID else 'none'}\n"
        f"*Watch Folder:* {WATCH_FOLDER_ENABLED}\n"
        f"*Download Timeout:* {DOWNLOAD_TIMEOUT}s\n"
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


# ── Message handler for raw URLs ────────────────────────────────────────────────
async def handle_url(update: Update, _ctx: ContextTypes.DEFAULT_TYPE) -> None:
    message = update.message
    if not message or not message.text:
        return

    remember_chat(update.effective_chat)

    if not can_use_context(
        update.effective_user.id,
        update.effective_chat.id,
        update.effective_chat.type,
    ):
        return

    url = extract_url(message.text)
    if not url:
        return

    QUEUE.append(create_job(
        update.effective_user.id,
        update.effective_chat.id,
        url,
        mode="video",
        source="raw_url",
        reply_to_message_id=message.message_id
    ))
    save_queue_state()

    pos = get_queue_position()
    await message.reply_text(
        f"📥 Added to queue\n"
        f"🔢 Position: {pos}\n"
        f"🎬 Mode: video"
    )


# ── CLI mode ────────────────────────────────────────────────────────────────────
def run_cli(url: str, mode: str = "video") -> None:
    print(f"Downloading {mode}: {url}")
    path = download_media(url, mode)
    print(f"Downloaded: {path}")
    routed = route_file(path, "audio" if mode == "audio" else "video")
    print(f"Saved to: {routed}")


# ── Main ────────────────────────────────────────────────────────────────────────
def build_app():
    app = ApplicationBuilder().token(BOT_TOKEN).build()

    app.add_handler(CommandHandler("start", start_cmd))
    app.add_handler(CommandHandler("help", help_cmd))
    app.add_handler(CommandHandler("dl", dl_cmd))
    app.add_handler(CommandHandler("audio", audio_cmd))
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
    app.add_handler(CommandHandler("clearqueue", clearqueue_cmd))
    app.add_handler(CommandHandler("leave", leave_cmd))
    app.add_handler(CommandHandler("leavechat", leavechat_cmd))
    app.add_handler(CommandHandler("shutdown", shutdown_cmd))

    app.add_handler(CallbackQueryHandler(ui_button_cb, pattern=r"^dl\|"))
    app.add_handler(ChatMemberHandler(track_chat_member, ChatMemberHandler.MY_CHAT_MEMBER))
    app.add_handler(MessageHandler(filters.TEXT & ~filters.COMMAND, handle_url))

    async def on_start(app_instance):
        asyncio.create_task(queue_worker(app_instance))
        asyncio.create_task(watch_folder_worker())

    app.post_init = on_start
    return app

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
    log_startup_checks()
    app.run_polling()

if __name__ == "__main__":
    main()