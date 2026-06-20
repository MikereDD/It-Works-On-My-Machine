# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.7.1] - 2026-06-19

### Added
- Post captions now include the post text in quotes — under the title line and
  above the link — so the words are selectable and searchable in Telegram (the
  card image isn't). Applies to X and Telegram posts; article captions are
  unchanged.

## [0.7.0] - 2026-06-19

### Added
- X quote-tweet support via the syndication endpoint
  (`cdn.syndication.twimg.com/tweet-result`): for X/Twitter links Gabriel now
  pulls the real author name, avatar, and verified badge, the quoted /
  replied-to tweet (rendered as a nested card with its own author, avatar,
  verified badge, and text), and post media.
- Verified badges — blue, gold (business), gray (government) — on post and
  quote cards.
- `render_quote_card`: nested quoted-tweet layout with a bordered inner box and
  an optional media thumbnail.

### Changed
- X posts prefer syndication data; if it's unavailable (rate-limited, deleted,
  or the endpoint changes) they fall back to the previous OG-based post card.
  Telegram (`t.me`) posts and non-social links are unchanged.

### Notes
- The syndication endpoint is unofficial and can change without notice; the OG
  fallback keeps Gabriel working if it does.

## [0.6.0] - 2026-06-18

### Added
- Color emoji rendering via Noto Color Emoji, RAQM-shaped so flag and ZWJ
  sequences render as single glyphs. Emoji now appear inline in titles,
  descriptions, post text, and author names instead of as tofu boxes. Falls
  back to plain text glyphs if no color-emoji font is installed.
- Telegram channel posts (`t.me` / `telegram.me`) now use the post layout —
  channel name as the byline, message text as the focus.

### Changed
- The redundant trailing `@handle` is stripped from post text (it already
  appears in the byline).

### Dependencies
- Adds `regex` (in `requirements.txt`) and needs a color-emoji font
  (`noto-fonts-emoji` on Arch). Pillow must be built with RAQM for flags and
  ZWJ sequences to shape correctly.

## [0.5.0] - 2026-06-18

### Added
- Post mode: X/Twitter links (and the fx/vx/fixupx mirrors) now render a
  tweet-style card — author + `@handle` byline with the avatar as a chip, and
  the post text as the focus — instead of the article card's inverted
  hierarchy (author-as-title, tweet-as-blurb).
- Social-post detection by host or the `(@handle) on X` title pattern; author
  and `@handle` parsed from `og:title`, with the handle recovered from the URL
  path as a fallback.

### Changed
- For posts, the `og:image` is treated as a media hero when large or the avatar
  chip when small, using the same size check as the article card.

## [0.4.0] - 2026-06-18

### Added
- Favicon source-chip: the site's icon (`apple-touch-icon` > `icon` link >
  `/favicon.ico`) is fetched and shown as a rounded chip next to the domain.

### Changed
- Redesigned card: the hero image now gradient-blends into the body (no hard
  seam), a subtle vertical background gradient adds depth, a cyan→teal accent
  runs as a top bar on text-only cards and a short bar under the source row,
  the domain is letter-spaced uppercase, and title/description spacing is
  tightened up.

## [0.3.0] - 2026-06-18

### Added
- Owner-only `/status` command: reports current log size, cache-dir contents,
  and the number of in-memory dedup entries.
- Owner-only `/clean` command: wipes the cache dir, truncates the log through
  the active logging handler (no sparse-file gap), and clears the dedup cache.
- `CACHE_DIR` (`Gabriel/cache`) as the single on-disk location for any future
  artifacts; normally empty, since cards are sent from memory.

## [0.2.0] - 2026-06-18

### Added
- `requirements.txt`.
- `/help` command (alias of `/start`).
- Lightweight in-memory dedup: the same link in the same chat is ignored if
  seen again within 30s, so a chatty group can't double-fire a card.

### Changed
- Titles and descriptions are whitespace-normalized (runs of spaces/newlines
  collapsed to single spaces) before rendering.
- Tracking parameters (`utm_*`, `fbclid`, `gclid`, `igshid`, `mc_cid`,
  `mc_eid`, `_ga`, `ref_src`) are stripped from the link shown in the caption;
  path and fragment are preserved.
- `fetch_html` validates the response is HTML before parsing.
- Hero downloads are size-capped and decoded up front so failures are caught
  cleanly rather than surfacing later during rendering.
- Build failures now stay silent in groups (logged only); private chats still
  get a short notice. The raw exception text is no longer sent to the chat.

### Fixed
- Tiny / low-resolution OG images (< 400px on the short side) are no longer
  upscaled into a blurry hero — the card falls back to the clean text layout.
- Over-long titles are truncated to keep the caption under Telegram's limit.

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

[Unreleased]: https://github.com/MikereDD/It-Works-On-My-Machine/compare/cardbot-v0.7.1...HEAD
[0.7.1]: https://github.com/MikereDD/It-Works-On-My-Machine/compare/cardbot-v0.7.0...cardbot-v0.7.1
[0.7.0]: https://github.com/MikereDD/It-Works-On-My-Machine/compare/cardbot-v0.6.0...cardbot-v0.7.0
[0.6.0]: https://github.com/MikereDD/It-Works-On-My-Machine/compare/cardbot-v0.5.0...cardbot-v0.6.0
[0.5.0]: https://github.com/MikereDD/It-Works-On-My-Machine/compare/cardbot-v0.4.0...cardbot-v0.5.0
[0.4.0]: https://github.com/MikereDD/It-Works-On-My-Machine/compare/cardbot-v0.3.0...cardbot-v0.4.0
[0.3.0]: https://github.com/MikereDD/It-Works-On-My-Machine/compare/cardbot-v0.2.0...cardbot-v0.3.0
[0.2.0]: https://github.com/MikereDD/It-Works-On-My-Machine/compare/cardbot-v0.1.0...cardbot-v0.2.0
[0.1.0]: https://github.com/MikereDD/It-Works-On-My-Machine/releases/tag/cardbot-v0.1.0
