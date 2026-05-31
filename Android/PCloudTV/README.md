# pCloud TV

A minimal **Google TV / Android TV** app (Kotlin + Jetpack Compose) that signs into
your pCloud account, browses your folders, and streams the **video and audio** files
straight from pCloud's servers using Media3 / ExoPlayer.

## What it does

- Sign in with your pCloud **email + password** (region auto-detected: US `api.pcloud.com` or EU `eapi.pcloud.com`).
- Browse folders with the D-pad (root → sub-folders → back with the Back button).
- Shows folders + audio/video files only.
- Selecting a file resolves a direct stream URL via pCloud's `getfilelink` and plays it full-screen.

## How auth works (and what's stored)

The app calls `userinfo?getauth=1`, which exchanges your credentials for an **auth token**.
Your password is sent only to pCloud over HTTPS and is **never stored** — only the returned
token + which region it belongs to are saved in the app's private `SharedPreferences`, so you
log in once. "Sign out" clears it.

## Build & run

1. Open the `PCloudTV` folder in **Android Studio** (Hedgehog/Iguana or newer).
2. On first open, let it sync. If it asks to set up the Gradle wrapper, accept it — or from a
   terminal in the project run: `gradle wrapper --gradle-version 8.4`.
   (The project pins Gradle 8.4 / AGP 8.2.2 / Kotlin 1.9.22, matching a stable, known-good set.)
3. Pick an **Android TV emulator** (Tools → Device Manager → create a *TV* device, API 30+) or a
   real Google TV / Android TV device with USB/ADB debugging.
4. Press **Run**. The app appears in the TV launcher's apps row (it also has a normal launcher
   icon so it runs on a phone/emulator for quick testing).

## Toolchain versions

| Component | Version |
|---|---|
| Gradle | 8.4 |
| Android Gradle Plugin | 8.2.2 |
| Kotlin | 1.9.22 |
| Compose Compiler ext | 1.5.10 |
| Compose BOM | 2024.02.00 |
| Media3 (ExoPlayer) | 1.2.1 |
| min / target SDK | 26 / 34 |

## Notes & possible next steps

- `getfilelink` URLs are bound to the requesting device's IP, so the app fetches the link
  immediately before playback on the same device. That's handled for you.
- For audio files the player shows a black surface with transport controls (D-pad to seek/pause).
  A "now playing" overlay shows the file name. You could swap in album-art/metadata later.
- pCloud also offers `getvideolink` / `gethlslink` for **transcoded/adaptive** streaming if you
  hit a codec the TV can't decode natively — `PCloudClient` is the place to add that.
- Token storage is plain app-private prefs. If you want it encrypted, wrap it with
  `EncryptedSharedPreferences` (`androidx.security:security-crypto`).

## Project layout

```
app/src/main/java/com/typezero/pcloudtv/
├─ MainActivity.kt
├─ data/
│  ├─ Models.kt          # PItem, Session, ApiResult
│  ├─ PCloudClient.kt    # login / listFolder / getStreamUrl (OkHttp + org.json)
│  └─ SessionStore.kt    # token persistence (no password)
└─ ui/
   ├─ App.kt             # login → browse → player routing
   ├─ AppViewModel.kt    # session state
   ├─ LoginScreen.kt
   ├─ BrowseScreen.kt    # folder stack + focusable list
   ├─ PlayerScreen.kt    # ExoPlayer / PlayerView
   └─ theme/Theme.kt
```
