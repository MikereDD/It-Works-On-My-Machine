# 🎵 Sandalphon (MusicBot)

> A typezerø Project  
> Built to work. Refined to feel right.

![version](https://img.shields.io/badge/version-v3.2-blue)
![python](https://img.shields.io/badge/python-3.10+-blue)
![license](https://img.shields.io/badge/license-WTFPL-lightgrey)

---

## 🚀 Overview

Sandalphon is a Telegram music bot focused on reliable music downloads, playlist ingestion, metadata management, library organization, and long-term music collection maintenance.

### Features

- Audio downloads via yt-dlp
- Search and direct-link support
- Metadata tagging and album artwork
- Searchable local music library
- Artist and album browsing
- Playlist import and synchronization
- Audio and metadata caching
- Spotify metadata matching
- Queue processing and failure recovery
- Telegram administration controls
- Flask web dashboard
- Local Bot API support
- JSON export and statistics reporting

---

## 📦 Current Version

**v3.1.3**

Highlights:

- Spotify metadata matching
- Searchable music library
- Playlist ingestion and synchronization
- Smart artwork caching
- Failure recovery system
- Flask dashboard and JSON APIs
- Legacy library compatibility improvements

---

## 📚 Documentation

Full documentation, release notes, dashboard information, configuration details, and development history can be found in:

**[notes/README.md](notes/README.md)**

---

## 🧠 Core Flow

```text
Input
  ↓
Playlist Import / Sync
  ↓
Smart Queue Ordering
  ↓
Resolve Metadata
  ↓
Spotify Metadata Matching
  ↓
Cache Metadata
  ↓
Download Audio
  ↓
Failure Recovery
  ↓
Cache Audio
  ↓
Cache Artwork
  ↓
Library Index
  ↓
Tag (ID3 + Artwork)
  ↓
Deliver
```

---

## 🧰 Common Commands

```text
/music <url or search>

/library
/find <query>
/play <query>

/playlist <url>
/syncplaylist <url>

/status
/stats

/reload
/restart
/help
```

---

## 🌐 Dashboard

Default dashboard URL:

```text
http://<pi-ip>:8181
```

Available pages:

```text
/
/library
/playlists
/failed
```

JSON API endpoints:

```text
/stats.json
/library.json
/playlists.json
/failed.json
```

---

## 💬 Philosophy

Sandalphon is built around a simple principle:

> Build what is useful. Refine what feels wrong.

Priorities:

- Reliability over complexity
- Practical workflows over perfect architecture
- Long-term maintainability
- Real-world usability

---

## 🧾 License

WTFPL — Do What The Fuck You Want To Public License