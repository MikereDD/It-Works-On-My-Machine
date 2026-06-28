<p align="center">
  <img src="./icon.png" width="112" alt="Cloud Player icon">
</p>

<h1 align="center">Cloud Player</h1>

<p align="center"><strong>v1.6</strong></p>

<p align="center">
A provider-first <strong>Android / Android TV / Android Auto</strong> media player built with
<strong>Kotlin + Jetpack Compose</strong>. Browse your cloud libraries and stream your
<strong>video, music, audiobooks, and playlists</strong> through the <strong>VLC (LibVLC)</strong>
engine in a monochrome Material 3 interface.
</p>

<p align="center">
  <a href="https://github.com/MikereDD/It-Works-On-My-Machine/releases/download/cloudplayer-v1.6/cloudplayer-v1.6.apk"><strong>Download the APK (v1.6)</strong></a>
</p>

---

## v1.6 Connected Libraries

This release improves the multi-cloud hub. After pCloud or MEGA sign-in, Cloud Player returns to the Libraries screen and clearly marks the provider as logged in. Provider screens include a direct path back to Libraries so you can add or switch services without getting trapped inside one cloud provider.

## Install

1. Download **[cloudplayer-v1.6.apk](https://github.com/MikereDD/It-Works-On-My-Machine/releases/download/cloudplayer-v1.6/cloudplayer-v1.6.apk)** and copy it to your phone or Android TV device.
2. Open it with a file manager and install. You'll see Google **Play Protect**'s "unknown developer" notice — tap **More details -> Install anyway**. That's expected for a sideloaded personal build.
3. Launch **Cloud Player**, choose a provider, and add your library.

> On Android TV, sideload via a file manager or `adb install cloudplayer-v1.6.apk`.

---

## Features

- Provider-first home screen for cloud libraries.
- Logged-in status shown on the main Libraries screen for connected providers.
- Completed provider sign-in returns to Libraries so you can add the next service.
- pCloud account support carried forward from pCloudTV.
- Library hub for switching between connected cloud services.
- MEGA provider entry screen with web sign-in and shared-link paths.
- Browse folders on TV with D-pad or on phone with touch.
- VLC playback with wide codec support.
- Background audio for music and audiobooks.
- Android Auto support for audio playback.
- M3U / M3U8 playlist support.
- Shared link support for pCloud.
- Monochrome Material 3 theme.
- Audio visualizer for phone/TV when microphone permission is granted.

---

## Philosophy

> **Your media belongs to you — not your storage provider.**

Cloud Player is an experimental project inside **It Works On My Machine**. It started from pCloudTV and is becoming a provider-independent player for personal media stored across cloud services.

---

## Roadmap

### v1.6

- Library hub for multiple cloud services.
- pCloud account/library switching.
- Return-to-libraries action from the browser.
- MEGA remains staged for sign-in and shared-link support.

### Next

- MEGA shared-link browsing and streaming.
- Official MEGA SDK/JNI provider integration.
- MEGA account browsing.
- MEGA shared-link browsing and streaming.
- Multiple saved libraries.
- Provider manager.

---

## License

Personal project — do whatever you want with it.


- MEGA web login now detects completed sign-in/2FA, saves a MEGA logged-in marker, and shows the detected account email on Libraries when available.
### v1.6 MEGA login-status follow-up
- Improved MEGA WebView signed-in detection for hash-router URLs like `#fm`.
- Added broader MEGA account-state checks for Cloud Drive / account UI after 2FA.
- Added a manual Android TV fallback button: **I am logged in — show MEGA on Libraries**.
- MEGA now saves a visible connected-library marker even when MEGA does not expose the account email to the WebView.


### MEGA login status note
MEGA's web app can complete password and 2FA without a normal page reload. Cloud Player now probes MEGA's in-page account state and also provides a **Done — save MEGA login** button on the MEGA login screen. After sign-in, use that button if the Libraries screen does not return automatically.
