# Raziel Config v1.4 — Per-Chat Auto-Watch Overrides

## Overview

Raziel config v1.4 introduces per-chat auto-watch override controls.

This allows specific Telegram groups to disable automatic link ingestion while still allowing explicit user commands.

The feature is designed for noisier social/chat groups where users frequently paste:

* source links
* commentary links
* article links
* text-only X/Twitter posts
* reference URLs
* non-downloadable social posts

without intending Raziel to download them.

---

# 🧠 New Configuration

```python
AUTO_WATCH_DISABLED_CHAT_IDS = [
# -1001234567890,
]
```

---

# ✨ Behavior

If a group ID exists in:

```python
AUTO_WATCH_DISABLED_CHAT_IDS
```

Raziel will ignore:

* pasted links
* shared links
* forwarded links
* automatic media ingestion triggers

inside that specific group.

---

# ✅ Still Allowed

Explicit commands continue working normally.

Supported commands:

```text
/dl
/hd
/full
/audio
/clip
/ui

/rdl
/rhd
/rfull
/raudio
/rui
```

This creates an:

```text
only act when explicitly asked
```

workflow model for selected groups.

---

# 🎯 Use Cases

Useful for groups where users:

* discuss videos without wanting downloads
* paste source references
* share commentary threads
* share text-only posts
* post article links frequently
* use Telegram primarily for discussion instead of ingestion

---

# 🧹 UX Improvement

This significantly reduces:

* accidental queue creation
* failed downloads
* irrelevant processing
* queue clutter
* operational noise

while preserving Raziel’s intentional command workflows.

---

# ⚙️ Architecture Direction

Raziel now supports multiple operational group modes:

```text
Auto-watch groups
→ automatic ingestion enabled

Controlled groups
→ explicit commands only
```

This further evolves Raziel into a configurable Telegram-native media platform instead of a one-size-fits-all downloader.

---

# Version

Raziel Config v1.4
“The watcher of links.”
