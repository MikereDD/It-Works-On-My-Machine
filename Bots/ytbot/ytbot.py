#--------------------------------------------
# file:     ytbot.py
# author:   Mike Redd
# version:  3.4
# created:  2026-04-18
# updated:  2026-04-19
# desc:     Telegram yt-dlp bot for Windows
#           link-only downloader with validation
#--------------------------------------------

import asyncio
import json
import logging
import re
import shutil
import subprocess
import sys
import time
from pathlib import Path
from urllib.parse import urlencode
from urllib.request import urlopen

import yt_dlp
from telegram import Update
from telegram.constants import ParseMode
from telegram.ext import (
    ApplicationBuilder,
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

BOT_TOKEN       = getattr(ytbotrc, "BOT_TOKEN",       "")
ALLOWED_USER_ID = getattr(ytbotrc, "ALLOWED_USER_ID", 0)

# ── Optional config overrides in ytbotrc.py ─────────────────────────────────────
# ALLOW_ALL_USERS = True   → anyone can use the bot (default: False, owner-only)
# DOWNLOAD_TIMEOUT = 300   → seconds before a download is cancelled (default: 300)
ALLOW_ALL_USERS  = getattr(ytbotrc, "ALLOW_ALL_USERS",  False)
DOWNLOAD_TIMEOUT = getattr(ytbotrc, "DOWNLOAD_TIMEOUT", 300)

if not BOT_TOKEN:
    raise RuntimeError("BOT_TOKEN is missing in ytbotrc.py")

if not ALLOWED_USER_ID:
    raise RuntimeError("ALLOWED_USER_ID is missing in ytbotrc.py")

# ── Paths ───────────────────────────────────────────────────────────────────────
BASE_DIR               = Path("G:/bots")
DOWNLOAD_DIR           = BASE_DIR / "downloads"
LOG_DIR                = BASE_DIR / "logs"
LOG_FILE               = LOG_DIR  / "ytbot.log"
KNOWN_CHATS_FILE       = BASE_DIR / "known_chats.json"
COOKIES_DIR            = BASE_DIR / "cookies"
YOUTUBE_COOKIES_FILE   = COOKIES_DIR / "youtube_cookies.txt"

DELETE_AFTER_SEND      = True
MAX_UPLOAD_BYTES       = 49 * 1024 * 1024   # 49 MB — Telegram bot cap
MIN_VALID_VIDEO_BYTES  = 100 * 1024         # reject suspiciously tiny files

URL_RE = re.compile(r"https?://\S+", re.IGNORECASE)

for d in (DOWNLOAD_DIR, LOG_DIR, COOKIES_DIR):
    d.mkdir(parents=True, exist_ok=True)

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s | %(levelname)s | %(name)s | %(message)s",
    handlers=[
        logging.FileHandler(LOG_FILE, encoding="utf-8"),
        logging.StreamHandler(sys.stdout),
    ],
)
log = logging.getLogger("ytbot")


# ── Known-chats store ───────────────────────────────────────────────────────────
def load_known_chats() -> dict:
    if not KNOWN_CHATS_FILE.exists():
        return {}
    try:
        return json.loads(KNOWN_CHATS_FILE.read_text(encoding="utf-8"))
    except Exception as e:
        log.warning("Failed to load known chats: %s", e)
        return {}

def save_known_chats(chats: dict) -> None:
    KNOWN_CHATS_FILE.write_text(
        json.dumps(chats, indent=2, ensure_ascii=False),
        encoding="utf-8",
    )

KNOWN_CHATS = load_known_chats()


# ── Helpers ─────────────────────────────────────────────────────────────────────
def is_allowed(update: Update) -> bool:
    user = update.effective_user
    return bool(user and user.id == ALLOWED_USER_ID)

def can_download(update: Update) -> bool:
    if ALLOW_ALL_USERS:
        return True
    return is_allowed(update)

def format_size(num_bytes: int) -> str:
    size = float(num_bytes)
    for unit in ("B", "KB", "MB", "GB", "TB"):
        if size < 1024:
            return f"{size:.2f} {unit}"
        size /= 1024
    return f"{num_bytes} B"

def format_duration(seconds: float) -> str:
    seconds = int(seconds)
    h, rem = divmod(seconds, 3600)
    m, s   = divmod(rem, 60)
    if h:
        return f"{h}h {m}m {s}s"
    if m:
        return f"{m}m {s}s"
    return f"{s}s"

def get_download_count() -> int:
    return sum(1 for p in DOWNLOAD_DIR.iterdir() if p.is_file())

def get_total_download_size() -> int:
    return sum(p.stat().st_size for p in DOWNLOAD_DIR.iterdir() if p.is_file())

def cleanup_downloads() -> tuple[int, int]:
    deleted = freed = 0
    for p in DOWNLOAD_DIR.iterdir():
        if p.is_file():
            try:
                freed += p.stat().st_size
                p.unlink()
                deleted += 1
            except Exception as e:
                log.warning("Failed to delete %s: %s", p, e)
    return deleted, freed

def remember_chat(chat) -> None:
    if not chat or chat.type not in ("group", "supergroup", "channel"):
        return
    chat_id    = str(chat.id)
    chat_title = getattr(chat, "title", None) or getattr(chat, "full_name", None) or "Unknown"
    KNOWN_CHATS[chat_id] = {"id": chat.id, "title": chat_title, "type": chat.type}
    save_known_chats(KNOWN_CHATS)
    log.info("Remembered chat %s (%s)", chat_title, chat.id)

def forget_chat(chat_id: int) -> None:
    removed = KNOWN_CHATS.pop(str(chat_id), None)
    if removed is not None:
        save_known_chats(KNOWN_CHATS)
        log.info("Forgot chat %s", chat_id)

def extract_url(text: str) -> str | None:
    if not text:
        return None
    m = URL_RE.search(text.strip())
    return m.group(0) if m else None

def ffmpeg_exists()  -> bool: return shutil.which("ffmpeg")  is not None
def ffprobe_exists() -> bool: return shutil.which("ffprobe") is not None

def is_youtube_url(url: str) -> bool:
    l = url.lower()
    return "youtube.com/" in l or "youtu.be/" in l or "m.youtube.com/" in l

def is_instagram_url(url: str) -> bool:
    return "instagram.com/" in url.lower()

def get_cookiefile_for_url(url: str) -> str | None:
    if is_youtube_url(url) and YOUTUBE_COOKIES_FILE.exists():
        return str(YOUTUBE_COOKIES_FILE)
    return None

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

def build_ydl_opts(url: str, outtmpl: str, format_selector: str, audio_only: bool = False) -> dict:
    opts: dict = {
        "outtmpl":           outtmpl,
        "format":            format_selector,
        "noplaylist":        True,
        "quiet":             True,
        "no_warnings":       True,
        "restrictfilenames": False,
        "compat_opts":       ["no-certifi"],
    }

    if audio_only:
        opts["postprocessors"] = [{
            "key": "FFmpegExtractAudio",
            "preferredcodec": "mp3",
            "preferredquality": "192",
        }]

    cookiefile = get_cookiefile_for_url(url)
    if cookiefile:
        opts["cookiefile"] = cookiefile

    if is_instagram_url(url):
        opts["nocheckcertificate"] = True
    else:
        opts["merge_output_format"] = "mp4"

    return opts

def clear_download_dir() -> None:
    for old in DOWNLOAD_DIR.iterdir():
        if old.is_file():
            try:
                old.unlink()
            except Exception as e:
                log.warning("Failed to delete old file %s: %s", old, e)

def get_candidate_files() -> list[Path]:
    return [p for p in DOWNLOAD_DIR.iterdir() if p.is_file()]

def get_best_valid_file() -> Path | None:
    files = sorted(get_candidate_files(), key=lambda p: p.stat().st_size, reverse=True)
    for f in files:
        if is_valid_video_file(f):
            return f
    return None


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
    full_url = f"{url}?{query}"
    with urlopen(full_url, timeout=15) as resp:
        return json.loads(resp.read().decode("utf-8"))

def weather_code_to_display(code: int | None) -> str:
    if code is None:
        return "❓ Unknown"
    icon, text = WEATHER_CODE_MAP.get(code, ("❓", f"Code {code}"))
    return f"{icon} {text}"

def weather_code_to_icon(code: int | None) -> str:
    if code is None:
        return "❓"
    icon, _ = WEATHER_CODE_MAP.get(code, ("❓", f"Code {code}"))
    return icon

def geocode_location(name: str) -> dict:
    data = http_get_json(
        OPEN_METEO_GEOCODE_URL,
        {
            "name": name,
            "count": 1,
            "language": "en",
            "format": "json",
        },
    )
    results = data.get("results") or []
    if not results:
        raise RuntimeError(f"No location found for: {name}")
    return results[0]

def build_place_label(loc: dict, fallback_name: str) -> str:
    place_name = loc.get("name", fallback_name)
    admin1 = loc.get("admin1")
    country = loc.get("country")

    label_parts = [place_name]
    if admin1:
        label_parts.append(admin1)
    if country:
        label_parts.append(country)
    return ", ".join(label_parts)

def get_current_weather_for_location(name: str) -> str:
    loc = geocode_location(name)

    latitude = loc["latitude"]
    longitude = loc["longitude"]
    place_label = build_place_label(loc, name)

    data = http_get_json(
        OPEN_METEO_FORECAST_URL,
        {
            "latitude": latitude,
            "longitude": longitude,
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
    code = current.get("weather_code")

    temp_unit = units.get("temperature_2m", "°F")
    humidity_unit = units.get("relative_humidity_2m", "%")
    wind_unit = units.get("wind_speed_10m", "mph")
    condition = weather_code_to_display(code)

    if temp is None:
        raise RuntimeError("Weather response did not include temperature.")

    lines = [
        f"🌤️ *Weather for {place_label}*",
        "",
        f"🌡️ *Temp:* {temp}{temp_unit}",
        f"🫧 *Humidity:* {humidity}{humidity_unit}" if humidity is not None else None,
        f"💨 *Wind:* {wind} {wind_unit}" if wind is not None else None,
        f"🛰️ *Condition:* {condition}",
    ]

    return "\n".join(line for line in lines if line is not None)

def get_5day_forecast_for_location(name: str) -> str:
    loc = geocode_location(name)

    latitude = loc["latitude"]
    longitude = loc["longitude"]
    place_label = build_place_label(loc, name)

    data = http_get_json(
        OPEN_METEO_FORECAST_URL,
        {
            "latitude": latitude,
            "longitude": longitude,
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
    precip = daily.get("precipitation_sum") or []

    temp_unit_max = units.get("temperature_2m_max", "°F")
    temp_unit_min = units.get("temperature_2m_min", "°F")
    precip_unit = units.get("precipitation_sum", "in")

    if not times:
        raise RuntimeError("Forecast response did not include daily forecast data.")

    lines = [
        f"🗓️ *5-Day Forecast for {place_label}*",
        ""
    ]

    from datetime import datetime

    for i, day_str in enumerate(times):
        try:
            dt = datetime.fromisoformat(day_str)
            day_name = dt.strftime("%a")
        except Exception:
            day_name = day_str

        code = codes[i] if i < len(codes) else None
        high = highs[i] if i < len(highs) else None
        low = lows[i] if i < len(lows) else None
        rain = precip[i] if i < len(precip) else None

        icon = weather_code_to_icon(code)
        _, text = WEATHER_CODE_MAP.get(code, ("❓", f"Code {code}")) if code is not None else ("❓", "Unknown")
        day_banner = WEEKDAY_EMOJI.get(i % 7, "📅")

        line_parts = [
            f"{day_banner} *{day_name}* — {icon} {text}",
            f"   🔺 {high}{temp_unit_max}" if high is not None else None,
            f"   🔻 {low}{temp_unit_min}" if low is not None else None,
            f"   🌧️ {rain} {precip_unit}" if rain is not None else None,
        ]

        lines.extend(part for part in line_parts if part is not None)
        if i != len(times) - 1:
            lines.append("")

    return "\n".join(lines)


# ── Progress-aware download ──────────────────────────────────────────────────────
class ProgressTracker:
    """Collects yt-dlp progress hook data for live status updates."""

    def __init__(self) -> None:
        self.filename: str | None = None
        self.percent:  float      = 0.0
        self.speed:    str        = ""
        self.eta:      str        = ""
        self._last_update: float  = 0.0

    def __call__(self, data: dict) -> None:
        status = data.get("status")
        if status == "finished":
            self.filename = data.get("filename")
            self.percent  = 100.0
        elif status == "downloading":
            total      = data.get("total_bytes") or data.get("total_bytes_estimate") or 0
            downloaded = data.get("downloaded_bytes", 0)
            if total:
                self.percent = downloaded / total * 100
            speed_raw = data.get("speed")
            if speed_raw:
                self.speed = format_size(int(speed_raw)) + "/s"
            eta_raw = data.get("eta")
            if eta_raw:
                self.eta = f"{int(eta_raw)}s"
            self._last_update = time.monotonic()


def download_video(url: str, tracker: ProgressTracker, audio_only: bool = False) -> Path:
    clear_download_dir()

    ext_hint = "%(ext)s" if not audio_only else "mp3"
    outtmpl = str(DOWNLOAD_DIR / f"%(title).200s [%(id)s].{ext_hint}")

    if audio_only:
        format_attempts = ["bestaudio/best"]
    elif is_instagram_url(url):
        format_attempts = ["best", "b", "worst", "bv*+ba/best"]
    else:
        format_attempts = ["bv*+ba/best", "best", "b", "worst"]

    last_error = None

    for fmt in format_attempts:
        try:
            clear_download_dir()
            ydl_opts = build_ydl_opts(url, outtmpl, fmt, audio_only=audio_only)
            ydl_opts["progress_hooks"] = [tracker]

            with yt_dlp.YoutubeDL(ydl_opts) as ydl:
                ydl.download([url])

            if tracker.filename:
                hooked = Path(tracker.filename)
                if audio_only and hooked.exists():
                    return hooked
                if is_valid_video_file(hooked):
                    return hooked

            detected = get_best_valid_file()
            if detected:
                return detected

            bad = get_candidate_files()
            if bad:
                log.warning(
                    "Download produced files but none were valid: %s",
                    [f.name for f in bad],
                )
        except Exception as e:
            last_error = e
            log.warning("Download attempt failed with format '%s': %s", fmt, e)
            if is_instagram_url(url) and (
                "postprocessing" in str(e).lower()
                or "invalid data found when processing input" in str(e).lower()
            ):
                continue

    if last_error:
        raise last_error
    raise RuntimeError("Download finished but no valid video file was detected.")


def compress_to_fit(input_path: Path, max_bytes: int) -> Path:
    if input_path.stat().st_size <= max_bytes:
        return input_path

    if not ffmpeg_exists():
        raise RuntimeError(
            "File is too large for Telegram and ffmpeg is not installed or not in PATH."
        )

    duration = get_duration_seconds(input_path)
    if duration <= 0:
        raise RuntimeError("Could not determine video duration for compression.")

    target_total_bps = int((max_bytes * 8) / duration * 0.92)
    target_audio_bps = 64_000
    target_video_bps = max(target_total_bps - target_audio_bps, 120_000)

    attempts = [
        ("480:-2", target_video_bps),
        ("360:-2", max(int(target_video_bps * 0.75), 100_000)),
        ("240:-2", max(int(target_video_bps * 0.55),  80_000)),
    ]

    stem = input_path.stem

    for idx, (scale, video_bps) in enumerate(attempts, start=1):
        output_path = input_path.with_name(f"{stem}.tgfit{idx}.mp4")
        cmd = [
            "ffmpeg", "-y", "-i", str(input_path),
            "-vf",      f"scale={scale}",
            "-c:v",     "libx264",
            "-b:v",     str(video_bps),
            "-maxrate", str(int(video_bps * 1.3)),
            "-bufsize", str(int(video_bps * 2)),
            "-preset",  "medium",
            "-movflags", "+faststart",
            "-c:a",     "aac",
            "-b:a",     str(target_audio_bps),
            str(output_path),
        ]
        log.info("Compress attempt %s: scale=%s video_bps=%s", idx, scale, video_bps)
        subprocess.run(cmd, capture_output=True, text=True, check=True)

        if output_path.exists() and is_valid_video_file(output_path):
            out_size = output_path.stat().st_size
            log.info("Compressed output size: %s", format_size(out_size))
            if out_size <= max_bytes:
                return output_path

    raise RuntimeError(
        f"Could not produce a file small enough for Telegram. Limit: {format_size(max_bytes)}"
    )


# ── Shared download logic ────────────────────────────────────────────────────────
async def run_download(
    update: Update,
    url: str,
    audio_only: bool = False,
) -> None:
    """Full download → (compress) → send flow, shared by /dl, /audio, and URL messages."""
    message    = update.message
    tracker    = ProgressTracker()
    mode_label = "🎵 audio" if audio_only else "🎬 video"

    status_msg = await message.reply_text(
        f"⏳ Fetching {mode_label}…",
        parse_mode=ParseMode.MARKDOWN,
    )

    async def update_progress() -> None:
        last_text = ""
        while True:
            await asyncio.sleep(3)
            pct   = tracker.percent
            speed = tracker.speed
            eta   = tracker.eta
            text  = (
                f"📥 Downloading {mode_label}… {pct:.0f}%"
                + (f"  •  {speed}" if speed else "")
                + (f"  •  ETA {eta}" if eta else "")
            )
            if text != last_text:
                try:
                    await status_msg.edit_text(text)
                    last_text = text
                except Exception:
                    pass

    progress_task = asyncio.create_task(update_progress())
    download_path = None
    send_path     = None

    try:
        download_path = await asyncio.wait_for(
            asyncio.to_thread(download_video, url, tracker, audio_only),
            timeout=DOWNLOAD_TIMEOUT,
        )

        progress_task.cancel()

        if not audio_only and download_path.stat().st_size > MAX_UPLOAD_BYTES:
            await status_msg.edit_text(
                f"📦 Compressing to fit Telegram…\n"
                f"Original: {format_size(download_path.stat().st_size)}"
            )
            send_path = await asyncio.to_thread(compress_to_fit, download_path, MAX_UPLOAD_BYTES)
        else:
            send_path = download_path

        size_str = format_size(send_path.stat().st_size)
        await status_msg.edit_text(f"📤 Uploading… ({size_str})")

        with send_path.open("rb") as f:
            if audio_only:
                await message.reply_audio(
                    audio=f,
                    filename=send_path.name,
                )
            else:
                await message.reply_video(
                    video=f,
                    filename=send_path.name,
                    supports_streaming=True,
                )

        await status_msg.delete()
        log.info("Sent file: %s (%s)", send_path.name, size_str)

    except asyncio.TimeoutError:
        progress_task.cancel()
        await status_msg.edit_text(
            f"⏱️ Download timed out after {DOWNLOAD_TIMEOUT}s.\n"
            "The video may be too long or the server too slow."
        )

    except Exception as e:
        progress_task.cancel()
        err       = str(e)
        err_lower = err.lower()

        if "sign in to confirm you're not a bot" in err_lower:
            msg = (
                "🔒 This site blocked anonymous access.\n"
                f"Add a YouTube cookie file here to bypass it:\n`{YOUTUBE_COOKIES_FILE}`"
            )
        elif "requested content is not available" in err_lower or "rate-limit" in err_lower:
            msg = "🚫 Instagram blocked this request. It may require login or you've been rate-limited."
        elif "no valid video file was detected" in err_lower:
            msg = "⚠️ The site responded but no playable video was produced."
        elif "invalid data found when processing input" in err_lower or "postprocessing" in err_lower:
            msg = "⚠️ The downloaded data wasn't a valid video file."
        elif "certificate_verify_failed" in err_lower or "unable to get local issuer certificate" in err_lower:
            msg = "🔐 SSL certificate verification failed for that site."
        elif "ffmpeg is not installed" in err_lower or "ffprobe is not installed" in err_lower:
            msg = f"⚠️ {err}"
        elif "could not produce a file small enough" in err_lower:
            msg = f"📏 {err}"
        elif "request entity too large" in err_lower:
            msg = f"📏 Telegram rejected the upload — file exceeded {format_size(MAX_UPLOAD_BYTES)}."
        else:
            msg = f"❌ Error: {err}"
            log.exception("Unhandled error while handling URL")

        await status_msg.edit_text(msg, parse_mode=ParseMode.MARKDOWN)

    finally:
        if DELETE_AFTER_SEND:
            for path in {download_path, send_path} - {None}:  # type: ignore[operator]
                if path and path.exists():
                    try:
                        path.unlink()
                    except Exception as e:
                        log.warning("Failed to delete %s: %s", path, e)


# ── Command handlers ─────────────────────────────────────────────────────────────
COMMAND_LIST = (
    "/start       — welcome & command list\n"
    "/help        — usage instructions\n"
    "/dl <url>    — download video explicitly\n"
    "/audio <url> — download audio only (MP3)\n"
    "/weather <place> — current weather\n"
    "/forecast <place> — 5-day forecast\n"
    "/status      — bot & system status *(owner)*\n"
    "/groups      — list remembered groups *(owner)*\n"
    "/cleanup     — delete leftover files *(owner)*\n"
    "/leave       — leave current group *(owner)*\n"
    "/leavechat   — leave a group by ID *(owner)*\n"
    "/shutdown    — stop the bot *(owner)*"
)

async def start_cmd(update: Update, _ctx: ContextTypes.DEFAULT_TYPE) -> None:
    remember_chat(update.effective_chat)
    await update.message.reply_text(
        "👋 *YT-DLP Bot*\n\n"
        "Send me a video link, or use a command:\n\n"
        + COMMAND_LIST,
        parse_mode=ParseMode.MARKDOWN,
    )

async def help_cmd(update: Update, _ctx: ContextTypes.DEFAULT_TYPE) -> None:
    remember_chat(update.effective_chat)
    await update.message.reply_text(
        "📖 *Help*\n\n"
        "Just paste a video URL and I'll download and send it.\n"
        "Supports YouTube, Twitter/X, TikTok, Instagram, Reddit, and 1000+ more sites.\n\n"
        "*Commands:*\n"
        + COMMAND_LIST + "\n\n"
        + (
            "ℹ️ Anyone can use this bot."
            if ALLOW_ALL_USERS else
            "🔒 Download commands are restricted to the bot owner."
        ),
        parse_mode=ParseMode.MARKDOWN,
    )

async def dl_cmd(update: Update, ctx: ContextTypes.DEFAULT_TYPE) -> None:
    remember_chat(update.effective_chat)
    if not can_download(update):
        return
    url = extract_url(" ".join(ctx.args)) if ctx.args else None
    if not url:
        await update.message.reply_text("Usage: `/dl <url>`", parse_mode=ParseMode.MARKDOWN)
        return
    await run_download(update, url, audio_only=False)

async def audio_cmd(update: Update, ctx: ContextTypes.DEFAULT_TYPE) -> None:
    remember_chat(update.effective_chat)
    if not can_download(update):
        return
    url = extract_url(" ".join(ctx.args)) if ctx.args else None
    if not url:
        await update.message.reply_text("Usage: `/audio <url>`", parse_mode=ParseMode.MARKDOWN)
        return
    if not ffmpeg_exists():
        await update.message.reply_text("⚠️ ffmpeg is required for audio extraction but was not found.")
        return
    await run_download(update, url, audio_only=True)

async def weather_cmd(update: Update, ctx: ContextTypes.DEFAULT_TYPE) -> None:
    remember_chat(update.effective_chat)

    if not ctx.args:
        await update.message.reply_text("Usage: `/weather <city or place>`", parse_mode=ParseMode.MARKDOWN)
        return

    location = " ".join(ctx.args).strip()

    try:
        result = await asyncio.to_thread(get_current_weather_for_location, location)
        await update.message.reply_text(result, parse_mode=ParseMode.MARKDOWN)
    except Exception as e:
        log.warning("Weather fetch failed for '%s': %s", location, e)
        await update.message.reply_text(f"Weather error: {e}")

async def forecast_cmd(update: Update, ctx: ContextTypes.DEFAULT_TYPE) -> None:
    remember_chat(update.effective_chat)

    if not ctx.args:
        await update.message.reply_text("Usage: `/forecast <city or place>`", parse_mode=ParseMode.MARKDOWN)
        return

    location = " ".join(ctx.args).strip()

    try:
        result = await asyncio.to_thread(get_5day_forecast_for_location, location)
        await update.message.reply_text(result, parse_mode=ParseMode.MARKDOWN)
    except Exception as e:
        log.warning("Forecast fetch failed for '%s': %s", location, e)
        await update.message.reply_text(f"Forecast error: {e}")

async def status_cmd(update: Update, _ctx: ContextTypes.DEFAULT_TYPE) -> None:
    remember_chat(update.effective_chat)
    if not is_allowed(update):
        return
    count      = get_download_count()
    total_size = get_total_download_size()
    cookie_str = f"file: `{YOUTUBE_COOKIES_FILE}`" if YOUTUBE_COOKIES_FILE.exists() else "none"
    chat       = update.effective_chat
    chat_type  = chat.type if chat else "unknown"
    chat_title = getattr(chat, "title", None) or getattr(chat, "full_name", None) or "private"
    await update.message.reply_text(
        f"*Bot status:* online\n"
        f"*Chat:* {chat_title} ({chat_type})\n"
        f"*Downloads folder:* `{DOWNLOAD_DIR}`\n"
        f"*Files in downloads:* {count}\n"
        f"*Total size:* {format_size(total_size)}\n"
        f"*Delete after send:* {DELETE_AFTER_SEND}\n"
        f"*Upload cap:* {format_size(MAX_UPLOAD_BYTES)}\n"
        f"*Download timeout:* {DOWNLOAD_TIMEOUT}s\n"
        f"*Allow all users:* {ALLOW_ALL_USERS}\n"
        f"*Min valid video:* {format_size(MIN_VALID_VIDEO_BYTES)}\n"
        f"*ffmpeg:* {ffmpeg_exists()}\n"
        f"*YouTube cookie:* {cookie_str}\n"
        f"*Known groups/channels:* {len(KNOWN_CHATS)}",
        parse_mode=ParseMode.MARKDOWN,
    )

async def groups_cmd(update: Update, _ctx: ContextTypes.DEFAULT_TYPE) -> None:
    remember_chat(update.effective_chat)
    if not is_allowed(update):
        return
    if update.effective_chat and update.effective_chat.type != "private":
        await update.message.reply_text("Use /groups from private chat with me.")
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
    remember_chat(update.effective_chat)
    if not is_allowed(update):
        return
    deleted, freed = cleanup_downloads()
    await update.message.reply_text(
        f"🧹 Cleanup complete.\n"
        f"Deleted: {deleted} file(s)\n"
        f"Freed: {format_size(freed)}"
    )

async def leave_cmd(update: Update, ctx: ContextTypes.DEFAULT_TYPE) -> None:
    remember_chat(update.effective_chat)
    if not is_allowed(update):
        return
    chat = update.effective_chat
    if not chat:
        return
    if chat.type == "private":
        await update.message.reply_text(
            "Use /groups to list groups, then `/leavechat <chat_id>` from private chat.",
            parse_mode=ParseMode.MARKDOWN,
        )
        return
    await update.message.reply_text("Leaving current group…")
    await ctx.bot.leave_chat(chat.id)
    forget_chat(chat.id)

async def leavechat_cmd(update: Update, ctx: ContextTypes.DEFAULT_TYPE) -> None:
    remember_chat(update.effective_chat)
    if not is_allowed(update):
        return
    if update.effective_chat and update.effective_chat.type != "private":
        await update.message.reply_text("Use /leavechat only from private chat with me.")
        return
    if not ctx.args:
        await update.message.reply_text("Usage: `/leavechat <chat_id>`", parse_mode=ParseMode.MARKDOWN)
        return
    try:
        target_id = int(ctx.args[0])
    except ValueError:
        await update.message.reply_text("Chat ID must be numeric.")
        return
    if str(target_id) not in KNOWN_CHATS:
        await update.message.reply_text("That chat ID isn't in my list. Use /groups first.")
        return
    chat_info = KNOWN_CHATS[str(target_id)]
    try:
        await update.message.reply_text(f'Leaving: {chat_info["title"]} (`{target_id}`)', parse_mode=ParseMode.MARKDOWN)
        await ctx.bot.leave_chat(target_id)
        forget_chat(target_id)
    except Exception as e:
        log.exception("Failed to leave chat %s", target_id)
        await update.message.reply_text(f"Failed to leave chat: {e}")

async def shutdown_cmd(update: Update, ctx: ContextTypes.DEFAULT_TYPE) -> None:
    remember_chat(update.effective_chat)
    if not is_allowed(update):
        return
    await update.message.reply_text("🛑 Shutting down…")
    log.info("Shutdown requested by owner (ID %s)", ALLOWED_USER_ID)
    await ctx.application.stop()


# ── Chat-member tracking ─────────────────────────────────────────────────────────
async def track_chat_member(update: Update, _ctx: ContextTypes.DEFAULT_TYPE) -> None:
    cmu = update.my_chat_member
    if not cmu:
        return
    new_status = cmu.new_chat_member.status
    if new_status in ("member", "administrator"):
        remember_chat(cmu.chat)
    elif new_status in ("left", "kicked"):
        forget_chat(cmu.chat.id)


# ── URL message handler ──────────────────────────────────────────────────────────
async def handle_url(update: Update, _ctx: ContextTypes.DEFAULT_TYPE) -> None:
    message = update.message
    if not message or not message.text:
        return

    remember_chat(update.effective_chat)

    if not can_download(update):
        return

    url = extract_url(message.text)
    if not url:
        return

    log.info(
        "Download requested by user %s in chat %s: %s",
        update.effective_user.id if update.effective_user else "unknown",
        update.effective_chat.id if update.effective_chat else "unknown",
        url,
    )
    await run_download(update, url, audio_only=False)


# ── Entry point ──────────────────────────────────────────────────────────────────
def main() -> None:
    app = ApplicationBuilder().token(BOT_TOKEN).build()

    app.add_handler(CommandHandler("start",     start_cmd))
    app.add_handler(CommandHandler("help",      help_cmd))
    app.add_handler(CommandHandler("dl",        dl_cmd))
    app.add_handler(CommandHandler("audio",     audio_cmd))
    app.add_handler(CommandHandler("weather",   weather_cmd))
    app.add_handler(CommandHandler("forecast",  forecast_cmd))
    app.add_handler(CommandHandler("status",    status_cmd))
    app.add_handler(CommandHandler("groups",    groups_cmd))
    app.add_handler(CommandHandler("cleanup",   cleanup_cmd))
    app.add_handler(CommandHandler("leave",     leave_cmd))
    app.add_handler(CommandHandler("leavechat", leavechat_cmd))
    app.add_handler(CommandHandler("shutdown",  shutdown_cmd))

    app.add_handler(ChatMemberHandler(track_chat_member, ChatMemberHandler.MY_CHAT_MEMBER))
    app.add_handler(MessageHandler(filters.TEXT & ~filters.COMMAND, handle_url))

    log.info("Bot starting… (owner ID: %s | allow_all: %s)", ALLOWED_USER_ID, ALLOW_ALL_USERS)
    app.run_polling()


if __name__ == "__main__":
    main()