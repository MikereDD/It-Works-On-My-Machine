# 🤖 Zaphkiel AI Bot v3.9

![Python](https://img.shields.io/badge/Python-3.10%2B-blue)
![Platform](https://img.shields.io/badge/Platform-Telegram-green)
![AI](https://img.shields.io/badge/AI-OpenAI-orange)
![Status](https://img.shields.io/badge/Status-Private-informational)
![License](https://img.shields.io/badge/License-Personal-lightgrey)

A private, self-hosted Telegram AI assistant built for real-world use — chat, image generation, image conversion, runtime reloads, and automation.

---

## ✨ Features

* 🧠 AI chat via OpenAI (`/ai`)
* 🎨 Tiered image generation (`/img`)
* 🖼️ Image conversion + style transfer (`/convert`)
* 🎨 Conversion style listing (`/styles`)
* 📊 Animated conversion progress display
* ⚡ Live config reloads (`/reload`)
* ♻️ Hot restart support (`/restart`)
* 💾 Automatic local image saving
* 🛡️ Built-in private access control
* 📊 Status + runtime info
* 🧾 File + console logging
* 🔄 Runtime configuration reloads
* 🖥️ tmux-friendly restart behavior
* 🔒 Config-driven admin + access control
* 💬 Telegram mention command support
* 👥 Optional group interaction mode
* 🔒 Private access (user ID restricted)

---

## 📦 Commands

### 🧠 AI Chat

```bash
/ai <message>
```

Ask the AI anything.

### 💬 Mention Examples

```bash
@YourBotUsername ask explain this Python error
```

```bash
@YourBotUsername img angel warrior --ultra --portrait
```

```bash
@YourBotUsername help
```

Mention commands support:
- AI chat
- image generation
- help
- status
- reload
- restart

Group support can be enabled through configuration.

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


### 🖼️ Image Conversion

Reply to an image with:

```bash
/convert <style>
```

Transforms an existing image into another artistic style using OpenAI image editing.

### Available Styles

| Style | Effect |
|---|---|
| `ghibli` | Studio Ghibli-inspired hand-painted animation |
| `cozy-anime` | Soft hand-painted fantasy animation |
| `comic` | Bold comic book illustration |
| `hyperreal` | Cinematic photorealism |
| `oilpaint` | Classical oil painting |
| `darkfantasy` | Dark fantasy movie-poster aesthetic |

### Examples

Reply to an image with:

```bash
/convert ghibli
```

```bash
/convert cozy-anime
```

```bash
/convert comic
```

```bash
/convert hyperreal
```

### List Available Styles

```bash
/styles
```

Converted images are automatically saved locally:

```text
G:\bots\images\converted
```

During conversion the bot displays a live animated progress bar and automatically removes the temporary conversion message after the final image uploads successfully.

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
* Mention identity
* Group access status
* Admin count

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
│   └── converted\
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

ADMIN_USERS = [
    ALLOWED_USER_ID,
]

ALLOW_GROUPS = False

BOT_USERNAME = "YourBotUsername"

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
* Image conversion activity
* Conversion progress events
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
* `/convert` supports reply-to-image style transfer workflows
* Animated progress indicators are shown during conversions
* Conversion progress messages auto-clean after successful uploads
* Built around tmux-based development workflows

---

## 🧠 v3.9 Highlights

* Config-driven mention identity
* Real Telegram username integration
* Mention command parsing
* Optional group support
* Multi-admin access model
* Shared ecosystem architecture direction
* Raziel-style operational polish
* Cleaner status/help visibility

---

## 🧠 Roadmap

* Streaming AI responses
* Inline bot interactions
* Additional conversion presets
* Cross-bot communication
* `/web` live search support
* Script/tool execution integration
* Multi-bot orchestration
* Shared bot dashboard
* True API-side progress tracking (future if supported)

---

## 🧾 License

**Personal / Private Use**

> “It works on my machine.” 😄
