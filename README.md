# 🧰 It-Works-On-My-Machine

> Everything in here works. On my machine.

A personal archive of scripts, projects, and experiments across Windows, Linux, Android, and a Raspberry Pi. Each side is independent — no attempt is made to keep them in sync.

## 📁 Projects

### 🪟 [Windows/](https://github.com/MikereDD/It-Works-On-My-Machine/blob/main/Windows) — PowerShell
Media & encoding: **media-encoder-gui**, **BRencoder** (+ GUI), **dvd-ripper-encoder** (+ GUI), **web-ripper**, **clip-video**, **generate-playlists**, **minfocreate**, `imdbdump` / `imdbthumbgrab`
Audio: **Cadence** (Material 3 audio player), `cd-tracks-flac` / `cd-image-flac` / `cd-ripper-gui`
Utilities: **AtomicClock** (SNTP clock + weather), `bluray-backup` / `bluray-trackdump`, `speedtest-menu`, `weatherfetch-menu`
Admin: **admin-menu-gui** + console menus (disk, events, logs, network, power, procs, services, systeminfo, updates, watch), `tool-menu` dispatcher

### 🐧 [Linux/](https://github.com/MikereDD/It-Works-On-My-Machine/blob/main/Linux) — Bash (arakiel · Raspberry Pi 5)
Pi & system: `pi-fan`, `pi-power`, `pi-throttle`, `pi-overclock`, `pi-eeprom`, `pi-fw`, `nvme-health`, `rp5-systeminfo`, `system-info`, `backup`, `disk-cleanup`, `update-manager`
Network & security: `net-monitor`, `open-ports`, `login-audit`, `logview`, `vpn-menu`, `wifi-menu`
Media: `bluray-backup` / `bluray-trackdump`, `brencoder`, `dvd-ripper-encoder`, `minfocreate`, `imdbdump`, `transcode-queue`
Shell: `tool-menu.sh`, `arakiel-tmux.sh`, dotfiles (`vimrc`, `tmux.conf`, `bashrc`, `Xresources`)

### 🤖 [Android/](https://github.com/MikereDD/It-Works-On-My-Machine/blob/main/Android) — Kotlin / Jetpack Compose
* **pCloud TV** — streams pCloud video & audio to Google TV / Android via LibVLC. Plays **MKV** and virtually any format LibVLC handles; recursive search, per-folder & custom playlists, in-app `.nfo` / `.htm` viewer, and an audio-reactive visualizer.
* **CloudTV** — M3U / IPTV live-TV player (Media3 / ExoPlayer) with background DVR.
* **AtomicClock** — RFC 4330 SNTP clock with Open-Meteo weather and a home-screen widget.
* **Resound** — multitrack audio editor / mixer (FFmpeg) with per-clip trim and voice recording.
* **Seraph** — MusicBrainz audio tagger with album-level matching.
* **Siphon** — audio extractor for local video files and remote links.

### 🔌 [Bots/](https://github.com/MikereDD/It-Works-On-My-Machine/blob/main/Bots) — Telegram (arakiel)
`ytbot`, `musicbot`, `aibot`, `cardbot` (URL → preview cards), `forwardbot`

### 🎮 [Games/](https://github.com/MikereDD/It-Works-On-My-Machine/blob/main/Games)
Android: **Road Pursuit**, **TacoBros**, **TetBlockRis**
PowerShell terminal: `2048`, `breakout`, `minesweeper`, `pacman`, `pong`, `snake`, `tetris`

### 🧊 [3D-Printing/](https://github.com/MikereDD/It-Works-On-My-Machine/blob/main/3D-Printing)
OpenSCAD projects, STL files, and prototypes — desktop hardware stands, Poop Tray.

## 📜 License

[WTFPL](./LICENSE) — do what the fuck you want.
