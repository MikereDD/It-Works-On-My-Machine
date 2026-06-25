# forwardbot

A manual Telegram aggregator bot (internal name: **Selaphiel**). Forward a public
channel post to it in a private chat and it reposts a cleaned copy to your
channel: the "Forwarded from" header is dropped, links and @mentions back to the
source channel are stripped, every other link is kept, and a Source link to the
original post is appended.

**Current version: 0.1.0** - see the
[CHANGELOG](https://github.com/MikereDD/It-Works-On-My-Machine/blob/main/Bots/forwardbot/CHANGELOG.md).

## Requirements

- Python 3.9+
- python-telegram-bot >= 21 (`pip install -r requirements.txt`)

## Setup

1. `cp forwardbotrc.example.py forwardbotrc.py`
2. Edit `forwardbotrc.py`: bot token (from @BotFather), target channel, and the
   user IDs allowed to feed the bot.
3. Add the bot as an **admin** of the target channel so it can post.
4. `python3 forwardbot.py`

## Usage

Forward any public channel post to the bot in a private DM. It reconstructs and
cleans the post, then reposts it to the target channel. Posts forwarded from
private channels are reposted without a Source link, since no public permalink
exists for them.

## Notes

- `forwardbotrc.py` holds your real token - keep it gitignored. Only
  `forwardbotrc.example.py` is committed.
- Multi-photo albums currently repost as individual messages (batching planned
  for 0.2.0).
