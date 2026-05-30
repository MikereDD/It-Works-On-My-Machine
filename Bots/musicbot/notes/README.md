# Sandalphon Documentation

Additional documentation, release notes, and development history for Sandalphon MusicBot.

---

## Release Notes

### v1 Series

- [v1.0-v1.7.md](v1.0-v1.7.md)
  - Foundation releases
  - Core Telegram integration
  - Download, tagging, caching, and queue systems

- [v1.9.md](v1.9.md)
  - Spotify metadata matching
  - Improved search accuracy
  - Metadata-driven track resolution

---

### v2 Series

- [v2.0-v2.9.md](v2.0-v2.9.md)
  - Library mode
  - Playlist ingestion
  - Artist and album browsing
  - Artwork caching
  - Failure recovery
  - Playlist synchronization

---

### v3 Series

- [v3.0-v3.1.3.md](v3.0-v3.1.3.md)
  - Dashboard foundation
  - Flask web dashboard
  - JSON API endpoints
  - Dashboard stability improvements
  - Legacy library compatibility

- [v3.2.md](v3.2.md)
  - Metadata title cleanup
  - Duplicate artist removal
  - Improved title normalization
  - Cleaner Telegram audio cards
  - Consistent Artist - Song formatting

---

## Current Feature Areas

### Library System

- Searchable local music library
- Artist and album browsing
- Fuzzy matching
- Instant playback from cache

### Playlist Management

- Playlist importing
- Library-only ingestion
- Playlist synchronization
- Playlist history tracking

### Metadata

- ID3 tagging
- Spotify metadata matching
- Album artwork support
- Metadata caching
- Metadata normalization
- Clean Artist - Song formatting

### Dashboard

- Browser-based library access
- Statistics reporting
- JSON API endpoints
- Failed queue monitoring

### Administration

- `/reload`
- `/restart`
- Status reporting
- Runtime statistics

---

## Philosophy

Sandalphon is designed around a simple goal:

> Build what is useful. Refine what feels wrong.

The project prioritizes:

- Reliability over complexity
- Practical workflows over perfect architecture
- Long-term maintainability
- Real-world usability

---

## License

WTFPL