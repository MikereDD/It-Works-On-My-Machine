# 🎬 Raziel v6.3

> A typezerø Project
> Built for real-world use, not perfection.

![Version](https://img.shields.io/badge/version-v6.3-blue)
![Python](https://img.shields.io/badge/python-3.10+-blue)
![License](https://img.shields.io/badge/license-WTFPL-lightgrey)

---

## 🚀 Overview

**Raziel v6.3** is a full media pipeline bot with:

* **automatic group link ingestion**
* **clean chat behavior**
* **production-ready logging**
* **large file support via local Telegram Bot API**
* **intelligent dedupe + smarter downloads**
* **strict video-source validation**
* **config-driven platform support**
* **user-controlled quality selection**
* **reply-loop protection**
* **enhanced clip metadata captions**
* **runtime configuration reloading**
* **runtime process restart control**
* **live Telegram progress updates**
* **mention-driven conversational interaction**
* **Telegram inline mode support**
* **consistent DM queue cleanup behavior**
* **Facebook platform validation support**
* **BitChute platform validation support**
* **config-controlled validation policy**
* **open yt-dlp compatibility mode**
* **metadata-aware uploads with full source context**
* **platform-aware upload branding and visual caption polish**
* **expandable source-context preservation**
* **meaningful metadata detection**
* **low-value metadata filtering**
* **clean non-reply context presentation**

It accepts input from:

* Telegram (commands, messages, shared links, forwarded links)
* Filesystem (watch folder)
* CLI (direct execution)

Pipeline:

Input → Validate → Queue → Download → Process → Upload → Route → Archive

---

## ✨ Features

### 🧠 Core System

* Persistent queue-based architecture
* Single worker (safe processing)
* Job tracking (queue, history, failures)
* Access control (owner / users / groups)

---

### 🤖 Automatic Group Link Detection

* Watches **all groups the bot is in**

* Detects:

  * pasted links
  * shared previews
  * forwarded messages

* Automatically queues downloads

👉 No commands required

---

### 🧹 Clean Chat Behavior

* Queue messages are **temporary**
* “Added to queue” is auto-deleted when processing starts
* Keeps group chats clean and readable

---

### 🔧 Production Log Mode

* `DEBUG_MODE` toggle
* Development → full logs
* Production → minimal logs

```python
DEBUG_MODE = False
```

---

## 🧠 Intelligence Layer

### 🔁 Dedupe System (v5.4)

* Prevents duplicate downloads
* Uses normalized URLs + persistent cache + TTL

---

### ⚙️ Config-Controlled Validation Policy (v5.9)

Raziel now supports configurable validation behavior through:

```python
STRICT_PLATFORM_VALIDATION = False
```

Raziel can now operate in two modes:

#### Strict Mode

```python
STRICT_PLATFORM_VALIDATION = True
```

Behavior:
- only configured platforms allowed
- preset/domain validation enforced
- unsupported domains rejected

#### Open yt-dlp Mode

```python
STRICT_PLATFORM_VALIDATION = False
```

Behavior:
- allows any valid HTTP/HTTPS URL
- yt-dlp determines extractor compatibility
- removes the need for endless preset additions
- automatically benefits from new yt-dlp extractors

This significantly reduces long-term maintenance overhead while
expanding compatibility across supported yt-dlp platforms.

### 🌐 Telegram UX & Mention Refinement (v5.9.1)

Raziel now includes refined Telegram mention behavior and cleaner
direct-message interaction handling.

Private chats now support natural commands without requiring mentions.

Examples:

```text
weather Houston
forecast Tokyo
queue
status
help
```

Groups still safely require:
- slash commands
- real bot mentions

Examples:

```text
@Razi3l_bot weather Houston
@Razi3l_bot forecast Tokyo
```

Improvements:
- standardized real Telegram username usage
- removed misleading fake clickable aliases
- improved mention parser consistency
- improved Telegram inline UX
- corrected underscore rendering in help output
- wrapped inline examples using backticks
- improved DM conversational behavior
- preserved safer group interaction behavior

This finalizes the inline/mention cleanup introduced during
the v5.8.x → v5.9 transition.

---

### 🎞️ Metadata-Aware Uploads (v6.0)

Raziel now preserves and embeds source context directly into uploaded
Telegram media.

Uploads are no longer simple file transfers —
they now function as self-contained media archives.

Supported metadata sources include:
- X/Twitter post text
- YouTube descriptions
- Instagram captions
- TikTok captions
- Reddit post text
- Facebook descriptions (when exposed)
- BitChute descriptions

Raziel now intelligently builds upload captions using:
- title
- uploader
- source/about text
- platform label
- duration
- clip metadata
- original source URL

Example upload structure:

```text
🎞️ Media Title

Original source text...

👤 Uploader
🌐 Platform
⏱️ Duration

🔗 Source URL
```

New internal helpers:
- `build_upload_caption()`
- `clean_metadata_text()`
- `platform_label()`
- `first_nonempty()`

Features:
- cleaner Telegram presentation
- self-documenting uploads
- preserved source context
- improved archival quality
- improved forwarding readability
- smarter metadata trimming
- Telegram caption-limit awareness

This marks the beginning of Raziel's transition toward:
- richer metadata handling
- self-contained media archives
- intelligent caption processing
- future AI-assisted metadata refinement

---

### 🧠 Meaningful Context Filtering (v6.3)

Raziel now intelligently evaluates whether source metadata is actually
worth displaying before sending expandable context blocks.

v6.3 introduced heuristic-based filtering to suppress:

* social link dumps
* sponsor blocks
* promo codes
* merch funnels
* repeated URLs
* timestamp spam
* tour-date lists
* low-information creator infrastructure

while preserving:

* creator commentary
* meaningful descriptions
* contextual source information
* actual post content

New internal systems:

* `is_meaningful_source_context()`
* `strip_context_line_noise()`

Config additions:

```python
CAPTION_SKIP_LOW_VALUE_CONTEXT = True
CAPTION_CONTEXT_MIN_MEANINGFUL_CHARS = 60
```

Benefits:

* reduced metadata spam
* cleaner Telegram UX
* better signal-to-noise ratio
* smarter context preservation
* more intentional expandable metadata

This evolves Raziel from:

* raw metadata dumping

into:

* intelligent metadata presentation

### 📖 Expandable Source Context System (v6.2)

Raziel now supports expandable source-context preservation using
Telegram expandable blockquotes.

Instead of aggressively stripping metadata, Raziel now preserves:
- creator commentary
- source descriptions
- post context
- attached social text

while keeping uploads visually clean.

Final upload structure:

1. Clean media upload bubble
2. Separate expandable source-context message

This architecture avoids:
- Telegram caption parser instability
- malformed caption entities
- inconsistent media-caption rendering
- reply-thread clutter

Expandable source context uses Telegram HTML formatting:

```html
<blockquote expandable>
...
</blockquote>
```

Benefits:

* cleaner Telegram scrolling
* preserved archival metadata
* optional context expansion
* reduced visual noise
* improved forwarding readability

This established the foundation for:

* intelligent metadata handling
* expandable archival context
* smarter future metadata presentation systems

---

### 🎨 Platform-Aware Upload Branding (v6.1)

Raziel now visually brands uploads using platform-aware caption icons
and cleaner Telegram presentation formatting.

Supported platform displays now include:

```text
▶ YouTube
𝕏 Twitter
◎ Instagram
♫ TikTok
ⓕ Facebook
⬡ Reddit
◉ BitChute
```

This replaces the older generic:

```text
🌐 Platform
```

presentation style.

Uploads now follow a cleaner media presentation format:

```text
🎞️ Media Title

Source text...

◉ Uploader
𝕏 Twitter
◷ 1m 37s

⤷ Source URL
```

Benefits:
- improved Telegram readability
- cleaner mobile presentation
- faster platform recognition
- reduced emoji clutter
- improved archival presentation quality
- visually consistent uploads

Internal additions:
- `PLATFORM_ICONS`
- `platform_display()`

Additional improvements:
- cleaner X/Twitter rendering behavior
- improved Telegram font compatibility
- refined platform-aware caption formatting
- improved media scanning usability

This continues Raziel's transition toward:
- polished media archival behavior
- visually organized uploads
- cleaner Telegram-native presentation
- configurable future caption themes

---

Architecture evolution:

```text
config
→ validation policy
→ yt-dlp
```

instead of:

```text
config
→ preset registry
→ validation allow-list
→ yt-dlp
```

Benefits:
- simpler maintenance
- future extractor compatibility
- optional strict operational control
- improved deployment flexibility

---

### ⚙️ Config-Driven Platforms (v5.4.2)

Control platforms via config (no code edits):

```python
ENABLED_VIDEO_PLATFORMS = (
    "youtube",
    "instagram",
)
```

Available presets:

* youtube
* instagram
* reddit
* tiktok
* twitter

Custom domains:

```python
EXTRA_VIDEO_DOMAINS = ()
```

---

### 🎯 Quality Control (v5.4.3)

Users can choose download quality:

| Command | Behavior       |
| ------- | -------------- |
| `/dl`   | 720p (default) |
| `/hd`   | 1080p          |
| `/full` | Best available |

Config:

```python
DEFAULT_VIDEO_HEIGHT = 720
HD_VIDEO_HEIGHT = 1080
```

---

### 🎛️ Interactive UI

`/ui <url>`

Now supports:

* 🎬 720p
* 🎬 HD
* 🎬 Full
* 🎵 Audio

---

### ✂️ Clip Support (v5.4.8)

```text
/clip <url> <start> <end>
```

* ffmpeg-powered
* Supports MM:SS / HH:MM:SS
* Validates ranges
* Shows normalized timestamps
* Displays calculated clip duration
* Adds clip metadata to:
  * queue messages
  * clipping status
  * upload captions

Example:

```text
⏱️ Clip: 00:25:00 → 00:26:52 (1m 52s)
```

---

### ♻️ Runtime Reloading (v5.4.9)

Raziel now supports live runtime configuration reloading.

```text
/reload
```

Reloads:
- debug mode
- platform settings
- quality settings
- access control
- timeout configuration
- archive/watch settings

without restarting:
- queue workers
- active jobs
- Telegram application
- persistence state

This enables safer live tuning and faster development iteration.

---

### 🔄 Runtime Restart Control (v5.5)

Raziel now supports safe runtime process restarting directly from Telegram.

```text
/restart
```

Raziel:
1. validates restart safety
2. checks for active jobs
3. prevents interruption during processing
4. sends restart confirmation
5. safely replaces its own process
6. reconnects automatically

Uses:

```python
os.execv(sys.executable, [sys.executable] + sys.argv)
```

Benefits:
- tmux-safe restarting
- virtualenv preservation
- no shell intervention required
- same process environment retained
- safer operational control

Protected operations:
- active downloads
- uploads
- ffmpeg clip jobs
- queued processing

---

### 📊 Live Progress System (v5.6)

Raziel now supports live Telegram progress updates during downloads.

Live status messages now display:
- progress bars
- percentage completion
- download size
- transfer speed
- ETA estimates

Example:

```text
🎞️ Example Video

⬇️ Downloading video (720p)…
████████░░░░ 82.4%

📦 842 MB / 1.1 GB
⚡ 7.2 MB/s
⏱️ ETA: 00:12
```

Features:
- yt-dlp progress hooks
- live Telegram message editing
- throttled status updates
- cleaner operational UX
- reduced chat spam

This creates a significantly more interactive and responsive
download experience.

---

### 💬 Mention & Inline Intelligence Layer (v5.7)

Raziel now supports conversational mention commands directly inside chats.

Examples:

```text
@Raziel weather Houston
@Raziel forecast Tokyo
@Raziel queue
@Raziel help
```

Administrative examples:

```text
@Raziel status
@Raziel stats
@Raziel reload
@Raziel restart
```

Features:
- mention detection
- conversational command parsing
- inline operational requests
- queue visibility
- weather utilities
- admin runtime control

Behavior:
- ignores unrelated chat noise
- avoids unknown-command spam
- preserves clean group UX

This establishes the foundation for:
- operational assistant behavior
- cross-bot orchestration
- conversational AI integration
- remote Pi management
- dashboard ecosystem integration

---

### 🌐 Telegram Inline Mode (v5.8.2)

Raziel now supports Telegram inline queries.

Users can now type:

```text
@Razi3l_bot weather Houston
@Razi3l_bot forecast Tokyo
```

inside:
- group chats
- private chats
- channels
- chats where Raziel is not a member

Features:
- Telegram `InlineQueryHandler`
- inline weather lookup
- inline forecast lookup
- inline Markdown responses
- inline help system
- lightweight cached inline results

Behavior:
- ignores unsupported inline queries
- avoids inline spam behavior
- safely throttles inline responses
- preserves clean Telegram UX

This significantly expands Raziel from:
- a group-based utility bot
into:
- a globally accessible Telegram assistant platform

---

### 🧹 Queue Cleanup Consistency (v5.8.3)

Raziel now consistently removes temporary queue confirmation messages
across:
- direct messages
- private chats
- groups
- operational channels

Improved behavior:
- queue confirmations are tracked per job
- temporary enqueue notices are auto-removed
- upload UX remains clean during processing
- DM behavior now matches group behavior

Typical flow:

```text
/dl <url>
→ Added to queue
→ Live progress
→ Final upload
→ Queue message removed
```

This keeps chats cleaner while preserving operational visibility.

---

### 📘 Facebook Platform Registry Fix (v5.8.4)

Raziel now properly validates and accepts Facebook video URLs when
Facebook support is enabled in configuration.

Supported Facebook domains now include:

```python
"facebook": (
    "facebook.com",
    "m.facebook.com",
    "www.facebook.com",
    "fb.watch",
)
```

This restores compatibility with:
- Facebook reels
- Facebook video URLs
- fb.watch links
- mobile Facebook links

Fixes:
- validation layer mismatch
- unsupported source rejection
- preset/config inconsistency

This ensures Facebook behaves consistently with all other
config-driven platform presets.

---

### 📺 BitChute Platform Support (v5.8.5)

Raziel now supports BitChute URLs through the native validation and
platform registry system.

Supported domains:

```python
"bitchute": (
    "bitchute.com",
    "www.bitchute.com",
)
```

BitChute can now be enabled directly through:

```python
ENABLED_VIDEO_PLATFORMS = (
    "bitchute",
)
```

This allows:
- BitChute video links
- native validation support
- config-driven enablement
- standard yt-dlp routing behavior

without requiring custom domain overrides.

---


### 📥 Media Handling

* YouTube, Instagram (default enabled)
* yt-dlp backend
* MP4-friendly formats
* Audio extraction

---

### 📦 Smart Upload System

* Uploads up to **~2GB**
* No forced compression
* No multi-part spam
* Extended Telegram upload timeout
* Clean single upload output

---

### 🧵 Reply Behavior

* Replies stay attached to original message
* `/dl`, `/hd`, `/full`, `/audio`, `/clip`, `/ui` all threaded
* Auto-detected links reply to source message

---

### 🛡️ Reply Requeue Protection (v5.4.7)

* Prevents reply loops from reposting uploaded videos
* Replies without a fresh/direct URL are ignored
* Raw Telegram reply payloads are sanitized before fallback scanning
* Stops accidental duplicate reposts when users casually reply to uploads

Ignored:

* reply + text
* reply + emoji
* reply + sticker

Allowed:

* reply + new video URL

---

### 🔇 Clean Group Mode

* Minimal noise output
* `/queue` for visibility

---

### 📁 File Routing

```text
G:\bots\done\video\
G:\bots\done\audio\
G:\bots\done\failed\
```

---

### 📡 Automation

* Watch folder: `G:\bots\watch`

CLI:

```text
python ytbot.py --url "<link>"
python ytbot.py --audio "<link>"
```

---

### 📊 Observability

* `/stats`
* `/status`
* `/failures`
* `/retrylast`

---

## 🧠 Version History

### v6.3 (Current)

* Added meaningful source-context detection
* Added low-value metadata filtering
* Added sponsor/promo noise suppression
* Added social-link dump filtering
* Added expandable context relevance heuristics
* Reduced unnecessary metadata expansion spam
* Improved Telegram readability and scroll cleanliness
* Preserved meaningful creator commentary
* Added intelligent context presentation behavior

---

### v6.2

* Added expandable source-context system
* Added Telegram expandable blockquote support
* Added clean non-reply context presentation
* Added metadata preservation architecture
* Improved Telegram metadata readability
* Reduced media-caption parsing instability
* Preserved archival source context
* Established expandable metadata pipeline foundation

---

### v6.1

* Added DM natural command support
* Improved mention parser behavior
* Standardized real Telegram username usage
* Removed misleading clickable alias examples
* Improved inline/mention help formatting
* Fixed underscore rendering in Telegram help output
* Improved private chat conversational UX
* Preserved safer group mention behavior

---

### v5.9

* Added config-controlled validation policy
* Added STRICT_PLATFORM_VALIDATION
* Added open yt-dlp compatibility mode
* Added dynamic extractor compatibility behavior
* Reduced long-term preset maintenance overhead
* Preserved strict allow-list operational mode
* Improved future yt-dlp compatibility architecture

---

### v5.8.5

* Added BitChute platform validation support
* Added BitChute preset registry domains
* Added config-driven BitChute enablement
* Expanded native platform registry coverage
* Improved validation layer compatibility

---

### v5.8.4

* Fixed Facebook platform validation support
* Added Facebook preset registry domains
* Fixed config/preset mismatch behavior
* Restored Facebook reel compatibility
* Fixed unsupported-source rejection for Facebook links

---

### v5.8.3

* Fixed queue cleanup behavior in DMs
* Added consistent queue message tracking
* Improved temporary enqueue cleanup logic
* Unified DM and group upload UX
* Reduced stale queue message clutter

---

### v5.8.2

* Added Telegram inline mode support
* Added inline weather and forecast utilities
* Added InlineQueryHandler integration
* Added inline article/result generation
* Added global Telegram utility access
* Expanded Raziel beyond joined-group interaction

---

### v5.7

* Added conversational mention command system
* Added inline weather and forecast utilities
* Added queue visibility via mentions
* Added mention parsing and command routing
* Added conversational operational interaction
* Established assistant ecosystem foundation

---

### v5.6

* Added live Telegram download progress updates
* Added yt-dlp progress hook integration
* Added progress bars and ETA tracking
* Added live speed and transfer statistics
* Added throttled Telegram status editing
* Improved operational visibility during downloads

---

### v5.5

* Added `/restart` runtime process control
* Added tmux-safe self-restarting
* Added active job restart protection
* Added virtualenv-preserving restart architecture
* Added safe operational runtime process replacement

---

### v5.4.9

* Runtime-safe `/reload` command
* Live configuration reloading
* No process restart required
* Preserves queue workers and active jobs
* Faster development and operational tuning

---

### v5.4.8

* Added normalized clip timestamp formatting
* Added clip duration calculation
* Added clip metadata to queue messages
* Added clip metadata to clipping status messages
* Added clip metadata to upload captions
* Improved `/clip` UX consistency across the entire pipeline

---

### v5.4.7

* Finalized reply-loop protection system
* Hardened reply payload filtering
* Stable repost prevention behavior
* Documentation and release cleanup

---

### v5.4.6

* Strict reply guard to prevent repost loops
* Ignore replies without a fresh/direct URL
* Sanitize `reply_to_message` payloads before fallback scanning

---

### v5.4.5

* Initial reply requeue prevention attempt

---

### v5.4.4

* Unified help branding and bot presentation
* Raziel identity integration

---

### v5.4.3

* Quality control commands (`/dl`, `/hd`, `/full`)
* Per-job quality handling
* UI quality selection

---

### v5.4.2

* Config-driven platform support

---

### v5.4.1

* Validation layer (supported video sources only)

---

### v5.4

* Dedupe system (persistent + TTL)
* Smarter format selection

---

### v5.3.4

* Production log mode (`DEBUG_MODE`)

---

### v5.3.3

* Queue message cleanup

---

### v5.3.2

* Automatic group link detection

---

## 📌 Philosophy

Make it work → Make it better → Make it clean → Make it smart → Make it disciplined → **Give control**

---

## 🧑‍💻 Author

Mike Redd
typezerø Projects

---

## 📜 License

WTFPL

