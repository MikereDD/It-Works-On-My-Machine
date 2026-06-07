# Changelog

All notable changes to **Cloud TV**. Newest first.

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
