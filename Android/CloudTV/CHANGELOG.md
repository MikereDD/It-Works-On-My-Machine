# Changelog

All notable changes to **Cloud TV**. Newest first.

---

## v0.4.0 — OneDrive engine (data layer)

- Added `OneDriveProvider` (Microsoft Graph) behind the `CloudProvider`
  interface: `/me/drive` folder browsing and stream resolution via Graph's
  pre-authenticated `@microsoft.graph.downloadUrl` — so OneDrive needs **no
  proxy** and **casts fine** (unlike Drive).
- Added `MicrosoftConfig` (v2.0 `/common` endpoints, Files.Read scope) and a
  `MICROSOFT_CLIENT_ID` build config (REPLACE_ME placeholder).
- One multi-tenant registration serves all users; no paid audit. Untested until
  a real client id is in. Next: AppAuth sign-in routing, the add-account
  provider picker, and the browse-screen generalization — tested live.

---

## v0.3.0 — Google Drive engine

- Added the Google Drive backend behind the `CloudProvider` interface:
  `GDriveProvider` (Drive v3 `files.list` browsing + `streamSource`),
  `GoogleAuth` (auth-code + PKCE via AppAuth / Chrome Custom Tabs — Google
  blocks embedded WebViews), and `DriveStreamProxy` (a loopback proxy that adds
  the Authorization header and forwards Range requests, since LibVLC can't).
- Added the AppAuth dependency and a `GOOGLE_CLIENT_ID` build config (currently
  a REPLACE_ME placeholder).
- Not yet wired into the UI and untested until a real client id + SHA-1 are
  registered. Next: the add-account provider picker, Custom-Tab sign-in
  routing, and the browse-screen generalization so Drive folders are browsable.

---

## v0.2.0 — Provider abstraction (foundation)

- Added the `CloudProvider` interface plus provider-agnostic models
  (`CloudItem` with String ids, `MediaKind`, `StreamSource`) — the contract every
  cloud backend implements.
- `PCloudProvider` implements it over the existing pCloud client (numeric ids
  mapped to strings, `PItem` -> `CloudItem`).
- Accounts are now tagged with a `CloudProviderType` (existing logins migrate to
  pCloud automatically); the ViewModel exposes the active account's provider.
- No behaviour change — pCloud works exactly as before. This is the seam Google
  Drive plugs into next.

---

## v0.1.0 — Forked from pCloud TV

- New app: **Cloud TV** (`com.typezero.cloudtv`), forked from pCloud TV v3.0 to become a
  multi-cloud media player.
- Renamed throughout (the app is now "Cloud TV"); pCloud remains the sign-in provider for now.
- Carries over everything from pCloud TV: VLC playback, playlists, resume, recently-played,
  background audio, Chromecast, multiple accounts + quick switch, and the clean ⋮ header.
- No functional change yet — this is the foundation. Next: the `CloudProvider` abstraction,
  then OneDrive.
