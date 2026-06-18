<p align="center">
  <img src="./icon.png" width="112" alt="pCloud TV icon">
</p>

<h1 align="center">pCloud TV</h1>

<p align="center"><strong>v4.14</strong></p>

<p align="center">
A minimal <strong>Google TV / Android TV</strong> app (also runs on phones), built with
<strong>Kotlin + Jetpack Compose</strong>. Sign into pCloud, browse your folders with the remote,
and stream your <strong>video and audio</strong> straight from pCloud — played through the
<strong>VLC (LibVLC)</strong> engine for wide codec support.
</p>

<p align="center">
  <a href="https://github.com/MikereDD/It-Works-On-My-Machine/releases/download/pCloudTV-v4.14/pCloudTV-v4.14.apk"><strong>Download the APK (v4.14)</strong></a>
</p>

---

## Install

1. Download **[pCloudTV-v4.14.apk](https://github.com/MikereDD/It-Works-On-My-Machine/releases/download/pCloudTV-v4.14/pCloudTV-v4.14.apk)** and copy it to your phone or Android TV device.
2. Open it with a file manager and install. You'll see Google **Play Protect**'s "unknown developer" notice — tap **More details -> Install anyway**. That's expected for a sideloaded personal build.
3. Launch **pCloud TV**, tap **Sign in with pCloud**, and log in (two-factor authentication is handled on pCloud's own page).

> On Android TV, sideload via a file manager (e.g. "Downloader") or `adb install PCloudTV.apk`.

---

## Screenshots

<p align="center">
  <img src="./screenshots/screenshot-1.jpg" width="24%">
  <img src="./screenshots/screenshot-2.jpg" width="24%">
  <img src="./screenshots/screenshot-3.jpg" width="24%">
</p>
<p align="center">
  <img src="./screenshots/screenshot-4.jpg" width="24%">
  <img src="./screenshots/screenshot-5.jpg" width="24%">
  <img src="./screenshots/screenshot-6.jpg" width="24%">
</p>
<p align="center">
  <img src="./screenshots/screenshot-7.jpg" width="60%">
</p>


---

## Features

- Sign in through pCloud's own web login (**two-factor authentication supported**); token stored until sign-out.
- Browse folders on TV (D-pad) or phone (touch), with file-type icons and sizes.
- **VLC playback** with wide codec support; auto-hiding controls (play/pause, +/-10s, scrub bar).
- Auto-selects **English audio + subtitles** with a manual **Tracks** picker; resume where you stopped.
- **Background audio** — music/audiobooks keep playing with the screen off or when you leave the app; video stops on leave.
- **Playlists** — play `.m3u`/`.m3u8` as a queue (auto-advance, skip, HLS), build one by tapping tracks across folders (saved to `/Music/playlists`), or bulk-generate one per folder under a path.
- **Shared links** — open a pCloud public link (file or folder) with no account.
- **Chromecast** — cast to a Chromecast / Google TV (audio + MP4/H.264; MKV/HEVC not supported by the stock receiver).

See the **[changelog](https://github.com/MikereDD/It-Works-On-My-Machine/blob/main/Android/PCloudTV/CHANGELOG.md)** for the full, version-by-version release history.

---

## Controls

**Player (TV remote):** **OK** play/pause - **Left / Right** seek +/-10s - **Up / Menu** audio & subtitle tracks - **Down** wake controls - **Back** exit.

**Player (touch):** tap to show/hide controls, tap the buttons, drag the seek bar, tap **Tracks** (top-right) for audio/subtitles.

---

## How sign-in works

pCloud has **disabled new OAuth app registration**, and its API does **not** support password login on accounts with **two-factor authentication**. So the app signs in via pCloud's own web login:

1. Tap **Sign in with pCloud** — the app opens **my.pcloud.com** in an in-app WebView.
2. Log in with your email + password + 2FA (all handled by pCloud).
3. The app captures the account's **access token** from the authenticated session, validates it against both regions (US `api.pcloud.com` / EU `eapi.pcloud.com`), and stores it.

The token is kept until you **Sign out** (which also clears the WebView session). Your **password is never seen or stored** — only the token. A manual *paste-a-token* field is included as a fallback.

---

## Build from source

1. Open the **PCloudTV** folder in **Android Studio** (Hedgehog/Iguana or newer): *File -> Open* -> select the folder containing `settings.gradle.kts`.
2. Let Gradle **sync** (first sync downloads Gradle 8.4 + dependencies, including the LibVLC native libraries — give it a few minutes).
3. **Build -> Generate App Bundles or APKs -> Build APK(s)** -> output at `app/build/outputs/apk/debug/app-debug.apk`.

> **APK size:** the build ships **arm64-v8a + armeabi-v7a** native libs (set in `app/build.gradle.kts` → `defaultConfig` → `ndk { abiFilters += listOf("arm64-v8a", "armeabi-v7a") }`), so it installs on modern phones, Android TVs, **and 32-bit ARM devices like the Chromecast with Google TV**. This makes the APK roughly **~110 MB**. To trim it for a single known device, drop the ABI you don't need. If you need an **x86_64 emulator**, comment out the `abiFilters` block and rebuild.

### Toolchain

| Component | Version |
|---|---|
| Gradle | 8.4 |
| Android Gradle Plugin | 8.2.2 |
| Kotlin | 1.9.22 |
| Compose Compiler extension | 1.5.10 |
| Compose BOM | 2024.02.00 |
| LibVLC (`org.videolan.android:libvlc-all`) | 3.6.0 |
| OkHttp | 4.12.0 |
| min / target SDK | 26 / 34 |
| JDK (Gradle) | 17 |

---

## Project layout

```
app/src/main/java/com/typezero/pcloudtv/
+- MainActivity.kt          # hosts the Compose UI
+- data/
|  +- Models.kt             # PItem, Session, ApiResult
|  +- PCloudClient.kt       # listFolder / getStreamUrl / token validate (OkHttp + org.json)
|  +- SessionStore.kt       # token + region persistence (never the password)
+- ui/
   +- App.kt                # routing: login -> web login -> browse -> player
   +- AppViewModel.kt       # session state
   +- LoginScreen.kt        # "Sign in with pCloud" + token fallback
   +- WebLoginScreen.kt     # pCloud web login in a WebView (captures the token)
   +- BrowseScreen.kt       # folder stack + focusable cards
   +- PlayerScreen.kt       # LibVLC playback, controls, track picker
   +- theme/Theme.kt        # palette + design tokens
```

---

## Troubleshooting

- **`Unsupported class file major version` / JVM target mismatch** — set the Gradle JDK to **17**: *Settings -> Build, Execution, Deployment -> Build Tools -> Gradle -> Gradle JDK* (the bundled `jbr-17` works), then re-sync.
- **Gradle can't resolve `libvlc-all:3.6.0`** — that exact version may not be on Maven Central; open the LibVLC page on Maven Central and bump to the latest `3.6.x`. (Avoid the `4.0.0-eap` builds; the API differs.)
- **Subtitles show the wrong language** — open **Tracks** (Up/Menu on TV, or the top-right button on touch) and pick the track you want, or set subtitles to **Off**.
- **Video won't decode** — LibVLC handles most formats; if one misbehaves, try toggling hardware decoding in `PlayerScreen.kt` (`setHWDecoderEnabled`).
- **"Directory does not contain a Gradle build"** — you opened the wrong folder; open the one that directly contains `settings.gradle.kts` and `app/`.

---

## Notes

- Stream URLs from `getfilelink` are bound to the requesting device's IP, so the app resolves them immediately before playback on the same device.
- Token storage is plain app-private prefs. For encryption, wrap `SessionStore` with `EncryptedSharedPreferences` (`androidx.security:security-crypto`).
- pCloud also offers `getvideolink` / `gethlslink` for transcoded/adaptive streaming if you ever need it — `PCloudClient` is where to add it.

---

## License

Personal project — do whatever you want with it.
