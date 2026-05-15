## 🚀 Versions

### Core Development

* [v4.0](v4.0.md) — Queue-based core system
* [v4.1](v4.1.md) — yt-dlp + Telegram integration
* [v4.2](v4.2.md) — Pipeline features and automation

---

### Usability & Interface

* [v4.3](v4.3.md) — Interactive UI and major polish
* [v4.3.1](v4.3.1.md) — Config alignment and stability
* [v4.4](v4.4.md) — Usability and observability improvements
* [v4.5](v4.5.md) — Stability, compression improvements, and runtime hardening
* [v4.6](v4.6.md) — Access control overhaul and configuration improvements
* [v4.7](v4.7.md) — Metadata captions and source-aware upload behavior
* [v4.8](v4.8.md) — Role-aware help system and command visibility
* [v4.9](v4.9.md) — Threaded reply flow for shared and forwarded links

---

### Major Milestones

* [v5.0](v5.0.md) — Clip support and media workflow expansion
* [v5.1](v5.1.md) — Command pipeline refinements and early automation groundwork
* [v5.2](v5.2.md) — Reply threading polish and group noise reduction

---

### Platform Evolution

* [v5.3](v5.3.md) — Local Telegram Bot API integration and large file support (~2GB)
* [v5.3.1](v5.3.1.md) — Upload timeout fixes and pipeline stabilization
* [v5.3.2](v5.3.2.md) — Automatic group link ingestion (shared + forwarded link detection)
* [v5.3.3](v5.3.3.md) — Queue message cleanup (auto-delete “Added to queue” on upload start)
* [v5.3.4](v5.3.4.md) — Production log mode (DEBUG_MODE toggle and reduced log noise)

---

### Intelligence Layer

* [v5.4](v5.4.md) — Dedupe system (TTL + persistence) and smarter yt-dlp format selection
* [v5.4.1](v5.4.1.md) — Restrict pipeline to supported video sources (validation layer)
* [v5.4.2](v5.4.2.md) — Config-driven platform support (enable/disable platforms without code changes)
* [v5.4.3](v5.4.3.md) — Quality control commands (/dl 720p, /hd 1080p, /full best)
* [v5.4.4](v5.4.4.md) — Help UI branding and unified bot presentation
* [v5.4.5](v5.4.5.md) — Initial reply requeue prevention attempt
* [v5.4.6](v5.4.6.md) — Strict reply guard to prevent repost loops from replied uploads
* [v5.4.7](v5.4.7.md) — Finalized reply-loop protection system and stable repost prevention behavior
* [v5.4.8](v5.4.8.md) — Clip metadata captions, normalized timestamps, and duration display polish
* [v5.4.9](v5.4.9.md) — Runtime configuration reloading without process restart
* [v5.5](v5.5.md) — Runtime process restart control and tmux-safe self-restarting
* [v5.6](v5.6.md) — Live Telegram progress system with real-time download status updates
* [v5.7](v5.7.md) — Mention command layer and conversational inline interaction support
* [v5.8.2](v5.8.2.md) — Telegram inline mode and global inline utility interaction
* [v5.8.3](v5.8.3.md) — Queue cleanup consistency and DM upload UX polish
* [v5.8.4](v5.8.4.md) — Facebook platform registry validation fix
* [v5.8.5](v5.8.5.md) — BitChute platform registry and validation support
* [v5.9](v5.9.md) — Config-controlled validation policy and open yt-dlp compatibility mode
* [v5.9.1](v5.9.1.md) — Telegram inline UX cleanup, DM natural commands, and mention parser refinement