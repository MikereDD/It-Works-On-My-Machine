# Changelog

All notable changes to **Cloud Player**.

## v2.2 / Native Provider API Foundation

- Bump Cloud Player to v2.2.
- Add provider-neutral `CloudItem` model for folders, video, audio, images, playlists, documents, and files.
- Add shared `CloudFolderResult` model with provider id, path, breadcrumbs, items, API-backed status, and status message.
- Add `NativeProviderBackend` boundary so provider APIs can plug into one browser and playback pipeline.
- Add staged native provider backend entries for pCloud, MEGA, Dropbox, and Box.
- Update the native provider browser to read provider-style folder results instead of hard-coded provider-specific rows.
- Keep provider websites limited to login, 2FA, and permission approval.
- Keep Cast inside Cloud Player-owned screens.
- Preserve folder-by-folder Back behavior: folder -> parent -> provider root -> Libraries.
- Stage live token-backed provider listing and streaming as the next backend pass.

## v2.1 / Unified Native Provider Browser

- Bump Cloud Player to v2.1.
- Replace Dropbox, Box, and MEGA provider web browsing routes with a shared Cloud Player native browser shell.
- Remove injected Cast/provider controls from crowded Dropbox and Box web headers.
- Keep provider websites limited to login, 2FA, and permission approval flows.
- Keep Cast inside Cloud Player-owned screens.
- Preserve one-folder-at-a-time Back behavior, returning to Libraries at provider root.
- Stage live API-token backed native listing/playback for the next provider-backend pass.

## v2.0 / Native Playback Core

- Bump Cloud Player to v2.0 for the Native Playback Core milestone.
- Clarify the app architecture: provider websites are for login/2FA/permission approval, while video and music playback should happen inside Cloud Player.
- Add a native shared-media playback route backed by the existing LibVLC player.
- Direct media URLs can now open directly in Cloud Player instead of staying in a provider preview page.
- Supported Dropbox shared media links are normalized for direct playback where possible.
- Keep pCloud account files and pCloud shared links on the native player path.
- Keep MEGA shared-link `#decryption_key` handling intact; true native MEGA playback still needs the decrypting backend/SDK.
- Update Libraries and shared-link copy around native playback/casting.

## v1.9.6 / pCloud Login Hotfix

- Added pCloud login route fallbacks.
- Handle `ERR_CONNECTION_RESET` by trying the next pCloud login route.
- Raised Gradle memory settings for packaging stability.

## v1.9.5 / MEGA Shared-Link Loader

- Fixed MEGA shared links so they open instead of stopping after parser validation.
- Preserved the full `#decryption_key` when launching the official MEGA web viewer.
- Kept support for separate MEGA link + separate decryption key text.
- Scoped the loading fix only to MEGA shared links.

## v1.9.4 / MEGA Shared-Link Key Parser

- Fixed MEGA shared-link parsing so the decryption key after `#` is preserved.
- Added support for modern MEGA file and folder links.
- Added support for legacy MEGA links using `!` separators.
- Added support for separate MEGA link plus separate decryption key text.

## v1.9.3 / Universal Cast and Shared Links

- Added Cast access to provider browsing across pCloud, MEGA, Dropbox, and Box.
- Added Cast access to public shared-link browsing.
- Added an Open Shared Link card to Libraries.

## v1.9.2 / Phase 3 Provider Browser Navigation

- Folded provider Back-navigation hotfix into v1.9 Phase 3.
- Back moves up one folder/page at a time in Box, Dropbox, and MEGA.
- Provider root returns to Libraries instead of quitting Cloud Player.

## v1.9.1 / Provider Back Navigation Hotfix

- Changed provider browser Back handling for mobile gestures and Android TV remotes.
- Return to Libraries only when already at provider root.

## v1.9 / Box Connected Library

- Added Box provider card.
- Added Box WebView login with 2FA-friendly flow.
- Added Box account status, remove account action, and folder browsing entry.

## v1.8.1 / Provider Navigation and Dropbox Visibility Hotfix

- Fixed pCloud root Back behavior so it returns to Libraries instead of closing the app.
- Restored Dropbox folder and file visibility.
- Made provider header selectable to return to Libraries.

## v1.8 / Provider Browser Cleanup and Dropbox Connected Library

- Added Dropbox as a connected-library provider.
- Added Dropbox WebView login with 2FA-friendly flow.
- Added logged-in Dropbox folder browsing bridge.
- Cleaned up provider browsing overlays.
- Moved Back from provider browsing toward Libraries behavior.

## v1.6 / Connected Libraries

- Added Connected Libraries dashboard.
- Logged-in providers stay visible from the Libraries hub.
- pCloud and MEGA login return to Libraries after sign-in.
- Added provider switching foundation.

## v1.4 / MEGA Web Sign-in

- Replaced custom MEGA login form with MEGA WebView sign-in.
- Allows MEGA to handle password, 2FA, CAPTCHA, and account security prompts.

## v1.3 / Library Manager Foundation

- Added Libraries hub for switching between connected cloud services.
- Prepared the UI flow for multiple providers.

## v1.2 / MEGA Sign-in Foundation

- Added initial MEGA sign-in screen.
- Added MEGA authentication repository boundary.

## v1.1 / MEGA Provider Foundation

- Enabled MEGA as the first additional provider path.
- Added MEGA connection screen and shared-link entry points.

## v1.0 / Initial Cloud Player Release

- Created Cloud Player as its own provider-neutral project.
- Reset versioning to v1.0.
- Added new Cloud Player app name, branding, package identity, and icon.
- Preserved pCloud as the first working provider from the pCloud TV foundation.
