# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0] - 2026-06-24

### Added
- Initial release (internal name: Selaphiel).
- Forward a channel post to the bot in a private chat and it reposts a cleaned
  copy to the target channel: the "Forwarded from" header is dropped (the post is
  reconstructed, not forwarded), links and @mentions pointing back at the source
  channel are stripped, every other link is kept, and a Source link to the
  original post is appended.
- Source links are built for public source channels only; private channels repost
  without one (no public permalink exists).
- Allow-list of user IDs permitted to feed the bot (`ALLOWED_USER_IDS`).
- `EXTRA_BLOCKED` list to always strip additional handles beyond the source.
- Supports text, photo, video, animation, document, audio, and voice posts.
- Configuration split into `forwardbotrc.py`.

### Known limitations
- Multi-photo albums repost as individual messages; media-group batching is
  planned for 0.2.0.
