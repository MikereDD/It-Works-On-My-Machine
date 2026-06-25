#!/usr/bin/env python3
# file:    forwardbotrc.py
# author:  typezero
# version: 0.1.0
# desc:    Config for forwardbot (Selaphiel). Edit these. If BOT_TOKEN holds a
#          real token, gitignore this file (commit a *.example copy instead).

# Telegram bot token from @BotFather
BOT_TOKEN = "PUT-YOUR-BOT-TOKEN-HERE"

# Where cleaned posts are sent. "@channelusername" or numeric -100... id.
# The bot must be an admin of this channel so it can post.
TARGET_CHANNEL = "@your_target_channel"

# User IDs allowed to feed the bot. Empty set = anyone may use it.
ALLOWED_USER_IDS = {123456789}

# Text of the appended attribution link.
SOURCE_LABEL = "Source"

# Suppress link previews on text posts for a cleaner aggregation look.
DISABLE_PREVIEWS = True

# Extra handles (no @) to always strip, beyond the auto-detected source channel.
# e.g. {"promohandle", "somespamchannel"}
EXTRA_BLOCKED = set()
