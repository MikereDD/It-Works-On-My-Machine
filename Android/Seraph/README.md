<p align="center">
  <img src="docs/icon.png" width="112" alt="Seraph icon">
</p>

<h1 align="center">Seraph</h1>

<p align="center"><strong>v0.2.0</strong></p>

<p align="center">
A <strong>Material 3 + Jetpack Compose</strong> audio <strong>tagger</strong> for Android — the tagging
companion to the video-to-audio extractor. Browse your music on your <strong>device or pCloud</strong>,
edit tags and embedded cover art, auto-fill from <strong>MusicBrainz</strong>, and batch-rename whole
folders from a template.
</p>

<p align="center">
  <a href="https://github.com/MikereDD/It-Works-On-My-Machine/raw/main/Android/Seraph/releases/Seraph-v0.2.0.apk"><strong>Download the APK (v0.2.0)</strong></a>
</p>

---

## Install

1. Download **[Seraph-v0.2.0.apk](https://github.com/MikereDD/It-Works-On-My-Machine/raw/main/Android/Seraph/releases/Seraph-v0.2.0.apk)** and copy it to your phone.
2. Open it with a file manager and install. You'll see Google **Play Protect**'s "unknown developer" notice — tap **More details -> Install anyway**. That's expected for a sideloaded personal build.
3. Launch **Seraph**, then pick a source: **Device** to choose a folder, or **pCloud** to sign in (Google sign-in and two-factor are handled on pCloud's own page).

---

## Features

- **Two sources, one app** — device (**Storage Access Framework**, persisted read/write) and **pCloud** (HTTP API), switchable from the library.
- **Browse by directory** — drill into albums, **Back** or the up arrow climbs out. pCloud is scoped to just `/Music` and `/Books/Audiobooks` (edit `PCloudConfig.SCAN_PATHS`).
- **Read & write tags** for MP3, FLAC, M4A/MP4, Ogg, Opus, WAV, AAC, WMA via **jaudiotagger**, including embedded front-cover art.
- **MusicBrainz lookup** + Cover Art Archive covers — suggestions fill the fields, but **every value stays hand-editable**.
- **Per-folder batch rename** from a token template (`{track} of {total} - {artist} - {title}` …), with a live preview and Android/Windows-safe names.
- **pCloud sign-in via pCloud's own web login** (**2FA supported**) — only the resulting token is stored, never your password.

See the **[changelog](https://github.com/MikereDD/It-Works-On-My-Machine/blob/main/Android/Seraph/CHANGELOG.md)** for the full, version-by-version history.

---

## How pCloud sign-in works

pCloud has **disabled new OAuth app registration**, and its API does **not** support password login on accounts with **two-factor authentication**. So Seraph signs in the same way the **pCloud TV** app does — through pCloud's own web login:

1. Tap the **pCloud** chip — Seraph opens **my.pcloud.com** in an in-app WebView.
2. Log in with your email + password + 2FA, or Google — all handled by pCloud.
3. Seraph captures the account's **auth token** from the authenticated session, validates it against both regions (US `api.pcloud.com` / EU `eapi.pcloud.com`), stores it, and lists your folders.

Your **password is never seen or stored** — only the token, kept until you sign out.

---

## Build from source

1. Open the **Seraph** folder in **Android Studio** (Ladybug or newer): *File -> Open* -> select the folder containing `settings.gradle.kts`.
2. Let Gradle **sync** (the first sync downloads Gradle 8.9 + dependencies).
3. **Build -> Build APK(s)** -> output at `app/build/outputs/apk/debug/app-debug.apk`. For a release build, run `./gradlew :app:assembleRelease`.

> No native libraries — Seraph is pure Kotlin/Java (tagging via the jaudiotagger Android fork), so the APK is small and architecture-independent.

### Toolchain

| Component | Version |
|---|---|
| Gradle | 8.9 |
| Android Gradle Plugin | 8.7.2 |
| Kotlin | 2.0.21 |
| Compose BOM | 2024.10.01 |
| Audio tags (`com.github.Adonai:jaudiotagger`) | 2.3.15 |
| min / target SDK | 26 / 35 |
| JDK (Gradle) | 17 |

---

## Project layout

```
app/src/main/java/com/typezero/seraph/
├─ SeraphApp.kt              # Application; builds the manual-DI container
├─ MainActivity.kt           # Compose host + state-based navigation
├─ di/                       # AppContainer, ViewModelFactory (manual DI, no Hilt)
├─ data/
│  ├─ model/                 # AudioFile, Tags, MusicBrainzResult
│  ├─ tagging/               # Tagger (jaudiotagger), TagFileService
│  ├─ musicbrainz/           # MusicBrainzClient (search + Cover Art Archive)
│  └─ rename/                # FilenameTemplate, RenameService
├─ storage/                  # StorageSource abstraction, SafStorageSource, SourceManager
├─ pcloud/                   # PCloudClient, PCloudSession, PCloudStorageSource, PCloudConfig
└─ ui/
   ├─ library/               # browse folders + files, source switch
   ├─ editor/                # tag editor + MusicBrainz lookup
   ├─ rename/                # per-folder batch rename (live preview)
   ├─ login/                 # PCloudWebLogin — pCloud web login in a WebView
   ├─ components/            # shared composables
   └─ theme/                 # palette + design tokens
```

---

## Notes

- jaudiotagger needs a real file, so every edit routes through a local cache file: a `ContentResolver` read/write for SAF, a download + re-upload for pCloud. Renames are native — a `DocumentsContract` call for SAF, a single server-side `renamefile` for pCloud.
- The pCloud token lives in plain app-private prefs. For encryption, wrap `PCloudSession` with `EncryptedSharedPreferences` (`androidx.security:security-crypto`).
- Which folders Seraph touches is set in one place — `PCloudConfig.SCAN_PATHS`.

---

## License

Personal project — do whatever you want with it.
