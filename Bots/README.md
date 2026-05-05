🤖 Bots

«Raziel. Zaphkiel. Sandalphon.
Three bots. One workflow.»

---

🧠 Overview

This directory contains my personal Telegram bots.

They are built for real use, not polish.

- Minimal setup
- Maximum utility
- Designed to run unattended

---

⚔️ The Lineup

🔴 Raziel — YTBot

«YouTube download & media handler
📂 ""ytbot/"" (./ytbot/)»

---

🔵 Zaphkiel — AIBot

«AI assistant & automation brain
📂 ""aibot/"" (./aibot/)»

---

🟣 Sandalphon — MusicBot

«Music streaming & audio control
📂 ""musicbot/"" (./musicbot/)»

---

⚙️ Notes

- Bots are independent
- Each has its own config
- Tokens/keys are not stored here
- Expect to configure your own environment

---

🔐 Config

Each bot expects a config file (not included):

config.py / config.sh / environment variables

Typical values:

- API keys
- Telegram tokens
- Paths
- Cookies (ytbot)

---

🚀 Running

Each bot can be run manually or via tmux/systemd:

python ytbot.py
python aibot.py
python musicbot.py

Or your custom launcher (arakiel 👀).

---

📊 Logging (recommended)

logs/
  ytbot.log
  aibot.log
  musicbot.log

Keep logs centralized. It will save you time when debugging.

---

⚠️ Reality Check

- These are not polished projects
- They are not plug-and-play
- They will break if you don’t understand them

If something works:

«keep it»

If something breaks:

«now you know how it works»

---

🧩 Future

- Unified control panel (CLI first, maybe web later)
- Shared logging system
- Remote management via SSH
- Optional dashboard

---

🧠 Final

These bots exist because doing things manually is boring.

They automate what I actually use.

If they help you:
cool

If not:
they still work on my machine
