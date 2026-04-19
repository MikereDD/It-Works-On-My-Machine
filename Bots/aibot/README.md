# 🤖 Zaphkiel AI Bot

![Python](https://img.shields.io/badge/Python-3.10%2B-blue)
![Platform](https://img.shields.io/badge/Platform-Telegram-green)
![AI](https://img.shields.io/badge/AI-OpenAI-orange)
![Status](https://img.shields.io/badge/Status-Private-informational)
![License](https://img.shields.io/badge/License-Personal-lightgrey)

A private, self-hosted Telegram AI assistant built for real-world use — chat, image generation, vision analysis, and automation.

---

## ✨ Features

* 🧠 AI chat via OpenAI (`/ai`)
* 🎨 Image generation (`/img`)
* ⚡ Prompt presets (`/imgz`)
* 👁️ Vision (analyze images) (`/vision`)
* 💾 Automatic local image saving
* 🛡️ Built-in rate limiting
* 📊 Status + usage tracking
* 🧾 File + console logging
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

**Flags:**

| Flag              | Effect          |
| ----------------- | --------------- |
| `--square`        | 1024x1024       |
| `--portrait`      | 1024x1536       |
| `--landscape`     | 1536x1024       |
| `--hd` / `--high` | High quality    |
| `--medium`        | Medium quality  |
| `--low`           | Low quality     |
| `--auto`          | Default quality |

**Examples:**

```bash
/img white-gold angel warrior --portrait --hd
/img cyberpunk skyline at night --landscape --high
```

---

### ⚡ Preset Image Generation

```bash
/imgz <preset> [extra prompt]
```

**Presets:**

* `angel`
* `zaphkiel`
* `icon`
* `wallpaper`
* `portrait`
* `darkfantasy`

**Examples:**

```bash
/imgz zaphkiel holding a glowing sword
/imgz wallpaper celestial throne room
```

---

### 📜 List Presets

```bash
/presets
```

---

### 👁️ Vision (Image Analysis)

Reply to an image:

```bash
/vision <question>
```

Or send an image with a `/vision` caption:

```bash
/vision describe this image
```

> You can also send a photo directly with `/vision <question>` as the caption — no need to reply to an existing message.

---

### 📊 Status

```bash
/status
```

Displays:

* Active models
* Memory usage
* Image usage limits
* Save directory
* Log location

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
/img hyper realistic angelic AI avatar named Zaphkiel, white-gold armor, blue eyes
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

MODEL = "gpt-4.1-mini"
IMAGE_MODEL = "gpt-image-1"

MAX_IMAGES_PER_DAY = 25
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

## 🛡️ Limits

| Type                   | Limit      |
| ---------------------- | ---------- |
| Request cooldown       | 5 seconds  |
| Images per minute      | 3          |
| Images per day         | 25         |
| Max input length       | 2000 chars |

All configurable in `aibotrc.py`.

---

## 📊 Logging

Logs are written to:

```text
G:\bots\logs\aibot.log
```

Includes:

* Requests
* Errors
* Image generation activity

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

---

## 🧠 Roadmap

* `/imgfile` → send original file download
* `/history` → show prompt history
* `/web` → fetch live data
* Script integration (trigger local tools)
* Multi-user support

---

## 🧾 License

**Personal / Private Use**

> “It works on my machine.” 😄
