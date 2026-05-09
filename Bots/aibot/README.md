# 🤖 Zaphkiel AI Bot

![Python](https://img.shields.io/badge/Python-3.10%2B-blue)
![Platform](https://img.shields.io/badge/Platform-Telegram-green)
![AI](https://img.shields.io/badge/AI-OpenAI-orange)
![Status](https://img.shields.io/badge/Status-Private-informational)
![License](https://img.shields.io/badge/License-Personal-lightgrey)

A private, self-hosted Telegram AI assistant built for real-world use — chat, image generation, runtime reloads, and automation.

---

## ✨ Features

* 🧠 AI chat via OpenAI (`/ai`)
* 🎨 Tiered image generation (`/img`)
* ⚡ Live config reloads (`/reload`)
* ♻️ Hot restart support (`/restart`)
* 💾 Automatic local image saving
* 🛡️ Built-in private access control
* 📊 Status + runtime info
* 🧾 File + console logging
* 🔄 Runtime configuration reloads
* 🖥️ tmux-friendly restart behavior
* 🔒 Private access (user ID restricted)

---

## 📦 Commands

### 🧠 AI Chat

```bash
/ai <message>
```

Ask the AI anything.

---

### 🎨 Image Generation

```bash
/img <prompt> [flags]
```

## Quality Flags

| Flag | Effect |
|------|--------|
| `--low` | Cartoon / fast / low detail |
| `--med` | Balanced semi-realistic |
| `--high` | Detailed realistic |
| `--ultra` | Hyper-realistic cinematic quality |

## Size Flags

| Flag | Resolution |
|------|------------|
| `--square` | 1024x1024 |
| `--portrait` | 1024x1536 |
| `--landscape` | 1536x1024 |

## Examples

```bash
/img angel warrior --low
/img zaphkiel white gold armor --ultra --portrait
/img dark fantasy throne room --high --landscape
```

---

### 📊 Status

```bash
/status
```

Displays:

* Active text model
* Active image model
* Default image tier
* Image settings
* Config path
* Image save directory
* Log file location

---

### 🔄 Reload Config

```bash
/reload
```

Reloads `aibotrc.py` live without restarting the bot.

Useful for testing:

* Model changes
* Image quality settings
* Default image tier
* Timeouts
* Paths

Perfect for rapid testing during development.

---

### ♻️ Restart Bot

```bash
/restart
```

Restarts the running bot process without killing the tmux pane.

Useful after editing:

* `aibot.py`
* command handlers
* runtime logic
* image systems

Designed specifically for tmux-based workflows.

---

### 🔄 Reset Memory

```bash
/reset
```

---

### ❓ Help

```bash
/help
```

---

## 🖼️ Example Output

```text
/img hyper realistic angelic AI avatar named Zaphkiel, white-gold armor, blue eyes --ultra --portrait
```

➡️ Generates and sends image + saves locally

---

## 📁 Project Structure

```text
G:\bots\
├── aibot\
│   └── aibot.py
├── config\
│   └── aibotrc.py
├── images\
├── logs\
```

---

## ⚙️ Configuration

Edit:

```text
G:\bots\config\aibotrc.py
```

Example:

```python
BOT_TOKEN = "..."
OPENAI_API_KEY = "..."
ALLOWED_USER_ID = 123456789

MODEL = "gpt-5.4-mini"
IMAGE_MODEL = "gpt-image-1"

DEFAULT_IMAGE_TIER = "high"
IMAGE_SIZE = "1024x1536"
IMAGE_QUALITY = "high"
```

---

## 💾 Image Storage

All generated images are saved locally:

```text
G:\bots\images
```

File naming:

```text
prompt-based-name_YYYY-MM-DD_HH-MM-SS.png
```

---

## 📊 Logging

Logs are written to:

```text
G:\bots\logs\aibot.log
```

Includes:

* AI requests
* Image generation activity
* Reload events
* Restart events
* Errors and exceptions

---

## 🚀 Setup

### 1. Install dependencies

```bash
pip install -U openai python-telegram-bot
```

---

### 2. Create Telegram bot

* Use **@BotFather**
* Copy bot token

---

### 3. Configure

Edit:

```text
G:\bots\config\aibotrc.py
```

---

### 4. Run

```bash
python aibot.py
```

---

## ⚠️ Notes

* This bot is **private-use only** (restricted by Telegram user ID)
* Uses **OpenAI API (pay-as-you-go)**
* Some prompts may be blocked due to API safety rules
* Image generation speed depends on API + network
* `/reload` reloads configuration live
* `/restart` performs an in-place Python restart using `os.execv()`
* Built around tmux-based development workflows

---

## 🧠 Roadmap

* Streaming AI responses
* Telegram mention support
* Inline bot interactions
* Cross-bot communication
* `/web` live search support
* Script/tool execution integration
* Multi-bot orchestration
* Shared bot dashboard

---

## 🧾 License

**Personal / Private Use**

> “It works on my machine.” 😄
