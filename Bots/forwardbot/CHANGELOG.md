# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Planned
- Media-group (album) batching, so multi-photo posts repost as a single album.

## [0.1.0] - 2026-06-24

### Added
- Initial release (internal name: Selaphiel).
- Forward a public channel post to the bot in a private chat; it reposts a
  cleaned copy to the target channel.
- **Attribution stripping** -- the post is reconstructed, so the "Forwarded from"
  header never appears.
- **Self-link removal** -- links, `@mentions`, and `tg://` deep-links pointing at
  the source channel are stripped; all other links are preserved.
- **Source link** to the original post, appended for public source channels.
- Allow-list of user IDs permitted to feed the bot (`ALLOWED_USER_IDS`).
- `EXTRA_BLOCKED` list to strip additional handles beyond the source channel.
- Post types supported: text, photo, video, animation, document, audio, voice.
- Configuration split into `forwardbotrc.py`.

### Known limitations
- Multi-photo albums repost as individual messages.
