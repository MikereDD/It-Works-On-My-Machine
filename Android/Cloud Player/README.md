<p align="center">
  <img src="./icon.png" width="112" alt="pCloud TV icon">
</p>

# Cloud Player v2.2

<p align="center"><strong>v2.2 / Native Provider API Foundation</strong></p>

<p align="center">
A native multi-cloud media player for <strong>Android / Android TV / Android Auto</strong>.
Cloud Player is built to browse, play, and cast your own video and music from connected cloud services through one consistent Cloud Player interface.
</p>

<p align="center">
  <a href="https://github.com/MikereDD/It-Works-On-My-Machine/releases/download/cloudplayer-v2.2/cloudplayer-v2.2.apk"><strong>Download the APK (v2.2)</strong></a>
</p>

---

## What Cloud Player Is

Cloud Player treats cloud services as storage backends, not as the player UI.

Provider websites are only used for:

- Login
- Two-factor authentication
- Permission approval

Browsing, playback, casting, and navigation belong inside Cloud Player.

> **One interface. One player. Every cloud.**

---

## v2.2 / Native Provider API Foundation

v2.2 starts the real provider-backend architecture.

This release adds the provider-neutral native API layer that all cloud services will plug into:

- Shared `CloudItem` model for folders, video, audio, images, playlists, and files
- Shared `NativeProviderBackend` boundary for provider API implementations
- Shared native browser shell driven by provider data instead of provider web headers
- Provider-neutral folder result model with breadcrumbs, status, and item metadata
- Staged native entries for pCloud, MEGA, Dropbox, and Box while live token-backed APIs are wired in

This is the groundwork for replacing provider web browsing with true native API-backed listings.

---

## Supported Providers

Current connected providers:

- pCloud
- MEGA
- Dropbox
- Box

Planned providers:

- Google Drive
- OneDrive
- WebDAV
- SMB
- FTP/SFTP

---

## Features

- Android TV focused interface
- Connected Libraries dashboard
- Per-provider login state
- pCloud account support
- MEGA web sign-in and shared-link handling
- Dropbox web sign-in with 2FA-friendly flow
- Box web sign-in with 2FA-friendly flow
- Shared native provider browser shell
- Native playback core using LibVLC
- Shared-link entry from Libraries
- Cast access from Cloud Player-owned screens
- Folder-by-folder Back navigation
- Monochrome Material 3 theme
- Android Auto support for audio playback

---

## Install

1. Download **[cloudplayer-v2.2.apk](https://github.com/MikereDD/It-Works-On-My-Machine/releases/download/cloudplayer-v2.2/cloudplayer-v2.2.apk)** and copy it to your phone or Android TV device.
2. Open it with a file manager and install. Google Play Protect may show an unknown developer warning because this is a sideloaded personal build.
3. Launch **Cloud Player**, choose a provider, and add your library.

> On Android TV, sideload with a file manager or run `adb install cloudplayer-v2.2.apk`.

---

## Navigation

Cloud Player uses the same navigation idea for every provider:

```text
Libraries
  -> Provider
      -> Folder
          -> Media
```

Back behavior:

```text
Folder
  -> Parent Folder
      -> Provider Root
          -> Libraries
              -> Exit App
```

---

## Current Status

### v2.2

- Native provider API foundation added.
- Shared provider-neutral file model added.
- Shared native provider backend boundary added.
- Native browser shell now reads provider-style folder results instead of hard-coded provider screens.
- Live provider token/API listing is staged as the next backend pass.

### v2.1

- Unified native provider browser shell introduced.
- Provider web headers removed from Dropbox, Box, and MEGA browsing routes.
- Cast moved into Cloud Player UI.

### v2.0

- Native Playback Core introduced.
- Cloud Player begins routing supported media into its own player instead of provider preview pages.

---

## Roadmap

Next development pass:

- Connect Dropbox API folder listing
- Connect Box API folder listing
- Continue pCloud native browsing improvements
- Integrate official MEGA decrypting backend/SDK
- Open provider files directly in the native LibVLC player
- Add universal search across connected providers
- Add resume playback and Continue Watching
- Add media metadata, posters, and music library views

---

## Philosophy

> **Your media belongs to you — not your storage provider.**

Cloud Player is an experimental project inside **It Works On My Machine**. It started from pCloud TV and is becoming a provider-independent player for personal media stored across cloud services.

## License

Personal project — do whatever you want with it.
