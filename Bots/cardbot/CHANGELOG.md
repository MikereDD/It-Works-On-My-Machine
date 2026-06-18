# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.0] - 2026-06-18

### Added
- Initial release of **Gabriel** (`cardbot.py`), a Telegram bot that turns
  article/post URLs into clean Open Graph preview cards.
- Open Graph / Twitter Card metadata extraction (title, description, hero
  image) with `<title>` and `<meta name="description">` fallbacks; relative
  image URLs resolved against the final (post-redirect) page URL.
- Pillow card renderer: dark theme with cyan accent, hero image cover-crop to
  the standard 1.92:1 OG ratio, title wrapping (max 3 lines) and description
  wrapping (max 4 lines) with ellipsis on overflow, and a text-only fallback
  card with an accent band when no hero image is available.
- Cross-platform font resolution (DejaVu on Arch/Linux, Segoe/Arial on Windows)
  with a graceful default-font fallback.
- Group auto-watch access model mirroring `ytbot`: groups/supergroups open,
  private chats owner-only (or allow-listed), per-chat opt-out via
  `AUTO_WATCH_DISABLED_CHAT_IDS`, and passive watch skipped on messages that
  already carry native Telegram media.
- `cardbotrc.py` config loader (shared `Bots/config/` dir) with a
  `CARDBOT_TOKEN` environment-variable fallback for the token.
- File + stream logging at the standard `asctime | levelname | name | message`
  format; log level follows `DEBUG_MODE`.
- Card rendering runs in a worker thread to avoid blocking the event loop;
  `HTTPXRequest` timeouts configured for Telegram I/O.

[Unreleased]: https://github.com/MikereDD/It-Works-On-My-Machine/compare/cardbot-v0.1.0...HEAD
[0.1.0]: https://github.com/MikereDD/It-Works-On-My-Machine/releases/tag/cardbot-v0.1.0
