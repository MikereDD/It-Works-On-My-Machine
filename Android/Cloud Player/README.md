# Cloud Player v2.1

Android TV cloud media player based on pCloud TV v4.51, now moving into a connected-libraries multi-cloud layout.

</p>

<h1 align="center">Cloud Player</h1>

<p align="center"><strong>v2.0 / Native Playback Core</strong></p>

<p align="center">
A provider-first <strong>Android / Android TV / Android Auto</strong> media player built with
<strong>Kotlin + Jetpack Compose</strong>. Browse your cloud libraries and stream your
<strong>video, music, audiobooks, and playlists</strong> through the <strong>VLC (LibVLC)</strong>
engine in a monochrome Material 3 interface.
</p>

<p align="center">
  <a href="https://github.com/MikereDD/It-Works-On-My-Machine/releases/download/cloudplayer-v2.0/cloudplayer-v2.0.apk"><strong>Download the APK (v2.0)</strong></a>
</p>

---



## v2.1 / Native Provider Browser

- Moves Dropbox, Box, and MEGA browsing away from crowded provider web headers.
- Adds a shared Cloud Player native browser shell for connected providers.
- Keeps provider websites focused on login, 2FA, and permission approval only.
- Keeps Cast inside Cloud Player UI instead of injecting it into Dropbox/Box headers.
- Back navigation now belongs to Cloud Player: folder -> parent folder -> Libraries.
- Stages live provider API token backends as the next pass for true native listing and playback.

## v2.0 / Native Playback Core

Cloud Player is now aimed at its real purpose: cloud services are sources, but playback belongs inside Cloud Player. Provider websites are only for login, 2FA, permission approval, and temporary provider browsing while the native APIs are connected.

- Native LibVLC playback remains the main playback target for video and music.
- pCloud account files and pCloud shared links continue to play inside Cloud Player.
- Direct media URLs can now open straight into Cloud Player's native player.
- Supported Dropbox shared media links are normalized for direct playback where possible.
- Cast remains an app-level feature instead of being tied to one provider.
- MEGA shared links still preserve the full `#decryption_key`; full native MEGA playback requires the MEGA decrypting backend/SDK next.

## v1.9.4 / MEGA Shared-Link Key Parser

- Cast is now exposed from every provider path: pCloud, MEGA, Dropbox, and Box.
- Cast is also exposed while browsing public shared links, so free shared-link playback and logged-in account playback use the same player/cast pipeline.
- Libraries now includes an **Open Shared Link** card so shared links remain available after accounts are connected.
- Current working shared-link implementation is pCloud public links; MEGA, Dropbox, and Box shared-link API support remains staged for later native provider passes.

## v1.9.2 / v1.9 Phase 3 — Provider Browser Navigation

- Phase 3 folds the provider Back-navigation hotfix into the main v1.9 line.
- Back / mobile swipe-back now moves up one folder/page at a time while browsing Box, Dropbox, or MEGA.
- At the provider root, Back returns to the Libraries screen instead of quitting Cloud Player.
- pCloud keeps the same behavior: Back moves up folders, then returns to Libraries at root.
- The provider browser header stays small so it does not cover the folder list.

## v1.9 Box Phase 2

This release adds Box folder access after the Phase 1 login work. Box sign-in still uses a WebView so Box can handle email/password, verification prompts, and 2FA/security-code steps directly. After completing Box login, Cloud Player returns to Libraries and shows Box as a logged-in service with the saved account label.

Phase 2 makes logged-in Box accounts open into the Box Files view from Libraries, with the same Cloud Player header and Back behavior used by the other provider browsers. The provider website is still a temporary bridge while the full Box API browser/streaming layer is built, but the app now lets you get into Box folders instead of stopping at login.

## Install

1. Download **[cloudplayer-v2.0.apk](https://github.com/MikereDD/It-Works-On-My-Machine/releases/download/cloudplayer-v2.0/cloudplayer-v2.0.apk)** and copy it to your phone or Android TV device.
2. Open it with a file manager and install. You'll see Google **Play Protect**'s "unknown developer" notice — tap **More details -> Install anyway**. That's expected for a sideloaded personal build.
3. Launch **Cloud Player**, choose a provider, and add your library.

> On Android TV, sideload via a file manager or `adb install cloudplayer-v2.0.apk`.

---

## Features

- Provider-first home screen for cloud libraries.
- Logged-in status shown on the main Libraries screen for connected providers.
- Completed provider sign-in returns to Libraries so you can add the next service.
- pCloud account support carried forward from pCloudTV.
- Library hub for switching between connected cloud services.
- MEGA provider entry screen with web sign-in and shared-link paths.
- Dropbox provider entry screen with WebView sign-in, 2FA/security-code support, manual save after 2FA, Libraries status, and logged-in folder browsing.
- Box provider entry screen with WebView sign-in, 2FA/security-code support, manual save after 2FA, Libraries status, remove-account support, and logged-in folder browsing.
- Browse pCloud folders natively, and browse logged-in MEGA / Dropbox / Box folders through the Phase 3 provider browser bridge with one-level-at-a-time Back navigation.
- VLC playback with wide codec support.
- Background audio for music and audiobooks.
- Android Auto support for audio playback.
- M3U / M3U8 playlist support.
- Shared link support from Libraries, including pCloud public links, direct media URLs, and supported Dropbox media links.
- Cast button is available across logged-in provider browsing and shared-link/native playback paths.
- Monochrome Material 3 theme.
- Audio visualizer for phone/TV when microphone permission is granted.

---

## Philosophy

> **Your media belongs to you — not your storage provider.**

Cloud Player is an experimental project inside **It Works On My Machine**. It started from pCloudTV and is becoming a provider-independent player for personal media stored across cloud services.

---

## Current Status

### v1.9.5

- MEGA shared links with `#key` now open in the official MEGA web viewer instead of only showing a normalized-link message.
- Full MEGA links and separate link + decryption key text are supported.

### v1.9.4

- Universal Cast entry point added across logged-in provider browsing and pCloud public shared-link browsing.
- Open Shared Link is available from Libraries.

### v1.9 Phase 3

- Box Phase 1 login and Phase 2 folder access are included.
- Provider Back navigation is now folded into Phase 3: folder/page Back first, then Libraries at provider root.
- MEGA, Dropbox, and Box still use provider web sessions as a temporary bridge until full OAuth/API folder listing and streaming are wired in.
- pCloud remains the native fully working provider.

### v1.9

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
- Box added as a Phase 1 connected account provider.
- Box login supports Box-hosted 2FA/security-code flows in WebView.
- Box shows as Logged in on Libraries after saving the session marker.

### Next

- Native Dropbox OAuth/API file browsing and streaming.
- MEGA shared-link browsing and streaming.
- Official MEGA SDK/JNI provider integration.
- Google Drive and OneDrive provider passes.
- Native Box API browsing and streaming.
- Multiple saved libraries per provider.
- Provider manager / account actions.

## License

Personal project — do whatever you want with it.

### v1.8.1 Hotfix

- Back from the pCloud root now returns to the Libraries screen instead of quitting the app.
- Dropbox browsing cleanup was relaxed so folders and files remain visible.
- The provider header can be selected to return to Libraries.



### MEGA shared-link parsing

MEGA shared links now preserve the decryption key after `#`. Cloud Player accepts:

```text
https://mega.nz/file/<id>#<decryption_key>
https://mega.nz/folder/<id>#<decryption_key>
```

It also accepts separate MEGA link and key text, such as:

```text
https://mega.nz/file/<id>
Decryption key:
<decryption_key>
```

This change is scoped to MEGA only.
