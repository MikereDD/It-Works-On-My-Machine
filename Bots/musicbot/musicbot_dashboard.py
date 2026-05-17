#!/usr/bin/env python3
# ------------------------------------------------------------
# file:     musicbot_dashboard.py
# author:   Mike Redd
# version:  3.1.3
# created:  2026-05-17
# updated:  2026-05-17
# desc:     Sandalphon dashboard foundation with library display fallback
# ------------------------------------------------------------

from pathlib import Path
import json
import time
from html import escape

from flask import Flask, jsonify, render_template_string, request

# ── Config ───────────────────────────────────────────────────
CACHE_DIR = Path("/mnt/nvme1/work/bots/cache/musicbot")

CACHE_INDEX_FILE = CACHE_DIR / "index.json"
METADATA_CACHE_FILE = CACHE_DIR / "metadata.json"
LIBRARY_INDEX_FILE = CACHE_DIR / "library.json"
ART_INDEX_FILE = CACHE_DIR / "art.json"
PLAYLIST_INDEX_FILE = CACHE_DIR / "playlists.json"
FAILED_INDEX_FILE = CACHE_DIR / "failed.json"

BOT_NAME = "Sandalphon"
BOT_VERSION = "3.1.3"

# IMPORTANT:
# Flask app must exist BEFORE any @app.route decorators.
app = Flask(__name__)

# ── Helpers ──────────────────────────────────────────────────
def read_json(path):
    if not path.exists():
        return {}

    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except Exception:
        return {}


def load_cache():
    return read_json(CACHE_INDEX_FILE)


def load_metadata():
    return read_json(METADATA_CACHE_FILE)


def load_library():
    return read_json(LIBRARY_INDEX_FILE)


def load_art():
    return read_json(ART_INDEX_FILE)


def load_playlists():
    return read_json(PLAYLIST_INDEX_FILE)


def load_failed():
    return read_json(FAILED_INDEX_FILE)


def cache_size_mb():
    total = 0

    audio_dir = CACHE_DIR / "audio"

    if not audio_dir.exists():
        return 0

    for path in audio_dir.glob("*"):
        if path.is_file():
            total += path.stat().st_size

    return round(total / (1024 * 1024), 2)


def split_display(display):
    display = (display or "").strip()

    if " - " in display:
        artist, title = display.split(" - ", 1)
        return artist.strip(), title.strip()

    return "", display


def fallback_track_fields(item):
    display = (item.get("display") or "").strip()
    path = Path(item.get("path", ""))

    if not display and path.name:
        display = path.stem

    parsed_artist, parsed_title = split_display(display)

    artist = (item.get("artist") or "").strip() or parsed_artist
    title = (item.get("title") or "").strip() or parsed_title or display
    album = (item.get("album") or "").strip()
    plays = item.get("plays", 0)

    return artist, title, album, plays


def dashboard_stats():
    return {
        "bot": BOT_NAME,
        "version": BOT_VERSION,
        "tracks": len(load_cache()),
        "metadata": len(load_metadata()),
        "library": len(load_library()),
        "art": len(load_art()),
        "playlists": len(load_playlists()),
        "failed": len(load_failed()),
        "cache_size_mb": cache_size_mb(),
        "generated": int(time.time()),
    }


BASE_TEMPLATE = """
<!DOCTYPE html>
<html>
<head>
    <title>{{ title }}</title>
    <meta charset="utf-8">

    <style>
        body {
            background: #0f1117;
            color: #d7dde8;
            font-family: monospace;
            margin: 0;
            padding: 24px;
        }

        h1, h2 {
            color: #7cc7ff;
        }

        a {
            color: #8be9fd;
            text-decoration: none;
        }

        a:hover {
            text-decoration: underline;
        }

        .nav {
            margin-bottom: 24px;
        }

        .nav a {
            margin-right: 18px;
        }

        .grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(220px, 1fr));
            gap: 16px;
        }

        .card {
            background: #171b24;
            border: 1px solid #2b3242;
            border-radius: 10px;
            padding: 16px;
        }

        .value {
            font-size: 28px;
            color: #50fa7b;
            margin-top: 8px;
        }

        table {
            width: 100%;
            border-collapse: collapse;
            margin-top: 16px;
        }

        th, td {
            border-bottom: 1px solid #2b3242;
            text-align: left;
            padding: 10px;
        }

        tr:hover {
            background: #1c2230;
        }

        input {
            background: #171b24;
            color: white;
            border: 1px solid #2b3242;
            border-radius: 8px;
            padding: 10px;
            width: 320px;
        }

        .muted {
            color: #7a8399;
        }
    </style>
</head>

<body>

<div class="nav">
    <a href="/">Dashboard</a>
    <a href="/library">Library</a>
    <a href="/playlists">Playlists</a>
    <a href="/failed">Failed</a>
    <a href="/stats.json">stats.json</a>
</div>

{{ content|safe }}

</body>
</html>
"""

# ── Dashboard ────────────────────────────────────────────────
@app.route("/")
def home():
    stats = dashboard_stats()

    content = f"""
    <h1>🎵 {BOT_NAME} v{BOT_VERSION}</h1>
    <p class='muted'>Read-only dashboard foundation</p>

    <div class="grid">

        <div class="card">
            <div>Tracks</div>
            <div class="value">{stats['tracks']}</div>
        </div>

        <div class="card">
            <div>Library</div>
            <div class="value">{stats['library']}</div>
        </div>

        <div class="card">
            <div>Playlists</div>
            <div class="value">{stats['playlists']}</div>
        </div>

        <div class="card">
            <div>Failed</div>
            <div class="value">{stats['failed']}</div>
        </div>

        <div class="card">
            <div>Artwork</div>
            <div class="value">{stats['art']}</div>
        </div>

        <div class="card">
            <div>Cache Size</div>
            <div class="value">{stats['cache_size_mb']} MB</div>
        </div>

    </div>
    """

    return render_template_string(
        BASE_TEMPLATE,
        title="Sandalphon Dashboard",
        content=content,
    )


# ── Library ──────────────────────────────────────────────────
@app.route("/library")
def library():
    term = request.args.get("q", "").lower().strip()

    library_data = load_library()

    items = []

    for item in library_data.values():
        artist, title, album, plays = fallback_track_fields(item)

        if term:
            haystack = " ".join([
                artist,
                title,
                album,
                item.get("display", ""),
                item.get("path", ""),
            ]).lower()

            if term not in haystack:
                continue

        item["_dashboard_artist"] = artist
        item["_dashboard_title"] = title
        item["_dashboard_album"] = album
        item["_dashboard_plays"] = plays
        items.append(item)

    items.sort(
        key=lambda x: (
            x.get("_dashboard_artist", "").lower(),
            x.get("_dashboard_title", "").lower(),
        )
    )

    rows = []

    for item in items[:500]:
        artist = escape(str(item.get("_dashboard_artist", "")))
        title = escape(str(item.get("_dashboard_title", "")))
        album = escape(str(item.get("_dashboard_album", "")))
        plays = escape(str(item.get("_dashboard_plays", 0)))

        rows.append(f"""
        <tr>
            <td>{artist}</td>
            <td>{title}</td>
            <td>{album}</td>
            <td>{plays}</td>
        </tr>
        """)

    content = f"""
    <h1>📚 Library</h1>

    <form>
        <input type="text" name="q" value="{term}" placeholder="Search library...">
    </form>

    <table>
        <tr>
            <th>Artist</th>
            <th>Title</th>
            <th>Album</th>
            <th>Plays</th>
        </tr>

        {''.join(rows)}
    </table>
    """

    return render_template_string(
        BASE_TEMPLATE,
        title="Library",
        content=content,
    )


# ── Playlists ────────────────────────────────────────────────
@app.route("/playlists")
def playlists():
    playlists_data = load_playlists()

    rows = []

    for item in sorted(
        playlists_data.values(),
        key=lambda x: x.get("imported", 0),
        reverse=True,
    ):
        rows.append(f"""
        <tr>
            <td>{item.get('url', '')}</td>
            <td>{item.get('total', 0)}</td>
            <td>{item.get('queued', 0)}</td>
            <td>{item.get('syncs', 0)}</td>
            <td>{item.get('mode', 'import')}</td>
        </tr>
        """)

    content = f"""
    <h1>🎵 Playlists</h1>

    <table>
        <tr>
            <th>Playlist</th>
            <th>Total</th>
            <th>Queued</th>
            <th>Syncs</th>
            <th>Mode</th>
        </tr>

        {''.join(rows)}
    </table>
    """

    return render_template_string(
        BASE_TEMPLATE,
        title="Playlists",
        content=content,
    )


# ── Failed ───────────────────────────────────────────────────
@app.route("/failed")
def failed():
    failed_data = load_failed()

    rows = []

    for item in sorted(
        failed_data.values(),
        key=lambda x: x.get("last_failed", 0),
        reverse=True,
    ):
        rows.append(f"""
        <tr>
            <td>{item.get('query', '')}</td>
            <td>{item.get('reason', '')}</td>
            <td>{item.get('attempts', 0)}</td>
        </tr>
        """)

    content = f"""
    <h1>❌ Failed Queue</h1>

    <table>
        <tr>
            <th>Query</th>
            <th>Reason</th>
            <th>Attempts</th>
        </tr>

        {''.join(rows)}
    </table>
    """

    return render_template_string(
        BASE_TEMPLATE,
        title="Failed",
        content=content,
    )


# ── JSON API ─────────────────────────────────────────────────
@app.route("/stats.json")
def stats_json():
    return jsonify(dashboard_stats())


@app.route("/library.json")
def library_json():
    return jsonify(load_library())


@app.route("/playlists.json")
def playlists_json():
    return jsonify(load_playlists())


@app.route("/failed.json")
def failed_json():
    return jsonify(load_failed())


# ── Main ─────────────────────────────────────────────────────
if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8181, debug=False)
