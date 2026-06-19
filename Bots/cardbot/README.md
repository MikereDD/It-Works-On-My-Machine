# Gabriel

`cardbot.py` — a Telegram bot that turns any article or post URL into a clean
preview **card**. Send it a link; it pulls the page's Open Graph metadata
(title, description, hero image), renders a card with Pillow, and replies with
the card plus the original link. Drop it into a group and it watches passively
for links, same as `ytbot`.

**Version:** 0.2.0 — see the [changelog](https://github.com/MikereDD/It-Works-On-My-Machine/blob/main/Bots/cardbot/CHANGELOG.md).

## Features

- OG / Twitter Card extraction with `<title>` + meta-description fallbacks;
  titles and blurbs are whitespace-normalized before rendering.
- Pillow card renderer: dark theme, cyan accent, hero cover-crop, wrapped
  title/blurb with ellipsis. Tiny or missing images fall back to a clean
  text-only card instead of a blurry upscale.
- Tracking params (`utm_*`, `fbclid`, `gclid`, …) stripped from the shown link.
- Group auto-watch: groups open, private chats owner-only, per-chat opt-out,
  ignores messages that already carry Telegram media, and de-dupes repeat links
  within 30s. Failures stay silent in groups (logged), notified in DMs.
- Token from `cardbotrc.py` or the `CARDBOT_TOKEN` env var.
- File + stream logging; rendering runs off the event loop.

## Requirements

- Python 3.10+
- See `requirements.txt`: `python-telegram-bot`, `httpx`, `beautifulsoup4`, `pillow`
- A DejaVu font for rendering (`ttf-dejavu` on Arch); falls back to a basic
  bitmap font if absent.

## Install (Arch / Raspberry Pi)

Three deps are in the official repo; `python-telegram-bot` is AUR-only. The
cleanest option for a long-running service is a venv:

```sh
python -m venv venv
venv/bin/pip install -r requirements.txt
sudo pacman -S ttf-dejavu
```

Or system packages: `sudo pacman -S python-pillow python-beautifulsoup4 python-httpx ttf-dejavu`
and `paru -S python-telegram-bot`.

## Configuration

1. Get a token from [@BotFather](https://t.me/BotFather): `/newbot`.
2. For group link-watching, run `/setprivacy` → **Disable** so the bot can see
   group messages (otherwise it only sees commands and replies/mentions).
3. Copy the example config and fill it in:

```sh
cp cardbotrc.example.py ../config/cardbotrc.py   # -> Bots/config/cardbotrc.py
```

Set `BOT_TOKEN` and `ALLOWED_USER_ID` (your numeric Telegram user ID — DM
[@userinfobot](https://t.me/userinfobot) to find it). The token can instead be
supplied via the `CARDBOT_TOKEN` env var, leaving `BOT_TOKEN` blank.

## Running

```sh
venv/bin/python cardbot.py
```

Then DM the bot a link, or add it to a group and paste one.

## Repo layout

```
Bots/cardbot/cardbot.py
Bots/cardbot/cardbotrc.example.py
Bots/cardbot/requirements.txt
Bots/config/cardbotrc.py      # live config (gitignored), copied from the example
```

## Notes

- News and blog articles work well. **Social posts are the hard case** — X/IG
  are login-walled and return little or no OG data, the same bot-detection wall
  `siphon` hits. Per-platform oEmbed is the path for those if needed.
- Paywalled sites usually expose only their teaser OG image/text, which is the
  "top portion" you'd want anyway.
