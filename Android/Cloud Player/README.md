# Cloud Player v1.8

Android TV cloud media player based on pCloud TV v4.51, now moving into a connected-libraries multi-cloud layout.

</p>

<h1 align="center">Cloud Player</h1>

<p align="center"><strong>v1.8</strong></p>

<p align="center">
A provider-first <strong>Android / Android TV / Android Auto</strong> media player built with
<strong>Kotlin + Jetpack Compose</strong>. Browse your cloud libraries and stream your
<strong>video, music, audiobooks, and playlists</strong> through the <strong>VLC (LibVLC)</strong>
engine in a monochrome Material 3 interface.
</p>

<p align="center">
  <a href="https://github.com/MikereDD/It-Works-On-My-Machine/releases/download/cloudplayer-v1.8.1/cloudplayer-v1.8.1.apk"><strong>Download the APK (v1.8)</strong></a>
</p>

---

## v1.8 Dropbox Connected Library

This release adds Dropbox to the Connected Libraries hub and fixes provider switching so logged-in services are useful from the main page. Dropbox sign-in supports the normal browser-based flow, including the 2FA/security-code step. After pCloud, MEGA, or Dropbox sign-in, Cloud Player returns to Libraries and clearly marks the provider as logged in. Selecting a logged-in MEGA or Dropbox account now opens that provider's cloud folder view.

This hotfix also cleans up MEGA / Dropbox browsing: the oversized instructional overlay is gone, Back returns directly to Libraries, and Dropbox upgrade / promo distractions are hidden where possible so the folder list is easier to see.

## Install

1. Download **[https://github.com/MikereDD/It-Works-On-My-Machine/releases/download/cloudplayer-v1.8.1/cloudplayer-v1.8.1.apk)** and copy it to your phone or Android TV device.
2. Open it with a file manager and install. You'll see Google **Play Protect**'s "unknown developer" notice — tap **More details -> Install anyway**. That's expected for a sideloaded personal build.
3. Launch **Cloud Player**, choose a provider, and add your library.

> On Android TV, sideload via a file manager or `adb install cloudplayer-v1.8.apk`.

---

## Features

- Provider-first home screen for cloud libraries.
- Logged-in status shown on the main Libraries screen for connected providers.
- Completed provider sign-in returns to Libraries so you can add the next service.
- pCloud account support carried forward from pCloudTV.
- Library hub for switching between connected cloud services.
- MEGA provider entry screen with web sign-in and shared-link paths.
- Dropbox provider entry screen with WebView sign-in, 2FA/security-code support, manual save after 2FA, Libraries status, and logged-in folder browsing.
- Browse pCloud folders natively, and browse logged-in MEGA / Dropbox folders through a cleaned provider web view on TV with D-pad or on phone with touch.
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

## Current Status

### v1.8

- Connected Libraries hub for multiple cloud services.
- pCloud account status shown on Libraries.
- MEGA login status shown on Libraries after sign-in / 2FA.
- Dropbox added as a connected-library provider.
- Dropbox WebView login supports the normal Dropbox 2FA/security-code step.
- Dropbox login screen includes **Done — save Dropbox after 2FA** for Android TV testing.
- Logged-in MEGA cards open MEGA Cloud Drive folder browsing.
- Logged-in Dropbox cards open Dropbox Home folder browsing.
- MEGA and Dropbox browser views use a small header chip, hide common web distractions where possible, and send Back directly to Libraries.
- Provider screens include a direct path back to Libraries.

### Next

- Native Dropbox OAuth/API file browsing and streaming.
- MEGA shared-link browsing and streaming.
- Official MEGA SDK/JNI provider integration.
- Google Drive, OneDrive, and Box provider passes.
- Multiple saved libraries per provider.
- Provider manager / account actions.

## License

Personal project — do whatever you want with it.

### v1.8.1 Hotfix

- Back from the pCloud root now returns to the Libraries screen instead of quitting the app.
- Dropbox browsing cleanup was relaxed so folders and files remain visible.
- The provider header can be selected to return to Libraries.

