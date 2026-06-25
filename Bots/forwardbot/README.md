# forwardbot

> Manual Telegram aggregator bot -- forward a post in, get a clean repost out.

![version](https://img.shields.io/badge/version-0.1.0-blue)
![python](https://img.shields.io/badge/python-3.9%2B-blue)
![ptb](https://img.shields.io/badge/python--telegram--bot-%3E%3D21-26A5E4)

Internal name: **Selaphiel** -- the conduit angel.

Forward a public channel post to the bot in a private chat and it reposts a
cleaned copy to your channel. No "Forwarded from" header, no links back to the
source channel -- but every *other* link is preserved, and a **Source** link to
the original post is appended so credit stays with the author.

---

## What it does

| Stage | Behaviour |
|-------|-----------|
| Attribution | Reconstructs the post, so the "Forwarded from" header never appears |
| Self-links  | Strips links / `@mentions` / `tg://` deep-links pointing at the source channel |
| Other links | Left completely untouched |
| Source      | Appends a `Source` link to the original post (public channels only) |
| Media       | Re-sends by `file_id` -- nothing is downloaded or re-uploaded |

Supported post types: text, photo, video, animation (gif), document, audio, voice.

---

## Requirements

- Python 3.9+
- [`python-telegram-bot`](https://python-telegram-bot.org/) >= 21

```bash
pip install -r requirements.txt
```

## Setup

```bash
cp forwardbotrc.example.py forwardbotrc.py   # then edit it
python3 forwardbot.py
```

1. Get a bot token from [@BotFather](https://t.me/BotFather).
2. Fill in `forwardbotrc.py`: token, target channel, allowed user IDs.
3. Add the bot as an **admin** of the target channel so it can post.
4. Run it, then DM the bot a forwarded channel post.

> [!NOTE]
> `forwardbotrc.py` holds your real token -- keep it gitignored. Only
> `forwardbotrc.example.py` is committed.

## Configuration

| Key | Purpose |
|-----|---------|
| `BOT_TOKEN`        | Bot token from @BotFather |
| `TARGET_CHANNEL`   | `@username` or numeric `-100...` id of the channel to post to |
| `ALLOWED_USER_IDS` | User IDs allowed to feed the bot (empty set = anyone) |
| `SOURCE_LABEL`     | Text of the appended attribution link |
| `DISABLE_PREVIEWS` | Suppress link previews on text posts |
| `EXTRA_BLOCKED`    | Extra handles to always strip, beyond the source channel |

## Limitations

- Posts from **private** source channels repost without a Source link (no public
  permalink exists).
- Multi-photo **albums** currently repost as individual messages; media-group
  batching is planned for 0.2.0.

## Changelog

Latest: **0.1.0**. Full history in
[CHANGELOG.md](https://github.com/MikereDD/It-Works-On-My-Machine/blob/main/Bots/forwardbot/CHANGELOG.md).
