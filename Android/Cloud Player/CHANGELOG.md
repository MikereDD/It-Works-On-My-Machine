# v2.0 / Native Playback Core

- Bump Cloud Player to v2.0 for the Native Playback Core milestone.
- Clarify the app architecture: provider websites are for login/2FA/permission approval, while video and music playback should happen inside Cloud Player.
- Add a native shared-media playback route backed by the existing LibVLC player.
- Direct media URLs can now open directly in Cloud Player instead of staying in a provider preview page.
- Supported Dropbox shared media links are normalized for direct playback where possible.
- Keep pCloud account files and pCloud shared links on the native player path.
- Keep MEGA shared-link `#decryption_key` handling intact; true native MEGA playback still needs the decrypting backend/SDK.
- Update Libraries and shared-link copy around native playback/casting.

# Changelog

## v1.9.5 - MEGA Shared-Link Loader

- Bumped Cloud Player to v1.9.5.
- Fixed MEGA shared links so they open instead of stopping after parser validation.
- Preserved the full `#decryption_key` when launching the official MEGA web viewer.
- Kept support for separate MEGA link + separate decryption key text.
- Scoped the loading fix only to MEGA shared links; pCloud, Dropbox, and Box behavior is unchanged.
- Kept native MEGA SDK/decryption-backed browsing and streaming staged for a later provider-backend pass.

## v1.9.4 - MEGA Shared-Link Key Parser

- Fixed MEGA shared-link parsing so the decryption key after `#` is preserved.
- Added support for modern MEGA file and folder links: `https://mega.nz/file/<id>#<key>` and `https://mega.nz/folder/<id>#<key>`.
- Added support for legacy MEGA links using `!` separators.
- Added support for separate MEGA link plus separate decryption key text.
- Scoped this parser only to MEGA shared links; pCloud, Dropbox, and Box parsing are unchanged.


## v1.9.3 - Universal cast access

- Bumped Cloud Player to v1.9.3.
- Added Cast access to provider browsing so MEGA, Dropbox, and Box expose the same Cast entry point as pCloud.
- Added Cast access to public shared-link browsing so free shared links and logged-in libraries use the same playback/cast path.
- Added an Open Shared Link card to Libraries so shared links are available even after cloud accounts are logged in.
- Kept pCloud native browsing and public pCloud shared-link playback as the first working shared-link implementation while MEGA/Dropbox/Box native shared-link APIs remain staged.

## v1.9.2 - v1.9 Phase 3 provider browser navigation

- Bumped Cloud Player to v1.9.2.
- Folded the provider Back-navigation hotfix into v1.9 Phase 3.
- Back / mobile swipe-back now moves up one folder/page at a time in Box, Dropbox, and MEGA.
- At the provider root, Back returns to Libraries instead of quitting Cloud Player.
- Kept pCloud navigation aligned with the same rule: folder Back first, Libraries at root.
- Kept the small provider header so folder lists are easier to see while the full native provider API browser is being built.

## v1.9.1 - Provider back navigation hotfix

- Bumped Cloud Player to v1.9.1.
- Changed provider browser Back handling so mobile gestures and Android TV remote Back move up one folder/page at a time.
- Return to Libraries only when the provider browser is already at its root.
- Keeps pCloud, MEGA, Dropbox, and Box navigation behavior consistent.

## v1.9 - Box connected-library phase 2

- Added Box folder browsing entry for logged-in Box accounts.
- Logged-in Box cards now open the Box Files view instead of stopping at account management.
- Added Box-specific provider-browser cleanup for common upgrade/trial/modal distractions.
- Kept Android Back behavior consistent: provider root returns to Libraries instead of quitting the app.
- Updated README to describe Box Phase 2 folder access.

## v1.9 - Box connected-library phase 1

- Bumped Cloud Player to v1.9.
- Added Box to the Connected Libraries dashboard.
- Added Box connect screen with account status and remove action.
- Added Box WebView login screen so Box handles password, 2FA, verification code, and account security prompts.
- Added **Done — save Box after 2FA** fallback for Android TV testing.
- Libraries now shows Box as Logged in with the saved account label.
- Add Cloud Service now includes Box as a selectable provider.
- Kept native Box API folder browsing and streaming staged for the next provider pass.


## v1.8.1 - Provider navigation and Dropbox visibility hotfix

- Fixed pCloud root Back behavior so it returns to Libraries instead of closing the app.
- Relaxed Dropbox browser cleanup so the folder/file list stays visible.
- Made the provider header clickable/tappable to return to Libraries.
- Kept provider web browsing as a temporary bridge while native API browsing is built out.


## v1.8 — Provider Browser Cleanup

- Cleaned up MEGA and Dropbox provider browsing so the app no longer shows the large instructional overlay over folder lists.
- Changed Android Back from MEGA / Dropbox provider browsing to return directly to the Cloud Player Libraries page instead of walking website history or quitting the app.
- Added a small header chip showing `Libraries ← Provider` without blocking the folder view.
- Added Dropbox page cleanup injection to hide common upgrade, promo, modal, and iframe distractions while browsing folders.
- Kept provider websites for login/session browsing only until real provider API folder browsing is wired in.

## v1.8 — Dropbox Connected Library

- Added WebView folder browsing for logged-in MEGA accounts via MEGA's own cloud drive.
- Added WebView folder browsing for logged-in Dropbox accounts via Dropbox Home.
- Logged-in MEGA and Dropbox cards now open their cloud folder views instead of only account-management screens.
- Added persistent Libraries navigation inside MEGA and Dropbox web browsers.
- Bumped Cloud Player to v1.8.
- Added Dropbox to the Connected Libraries dashboard.
- Added Dropbox connect screen with account status and remove action.
- Added Dropbox WebView sign-in marker for Android TV testing.
- Added Dropbox 2FA/security-code flow support so the login screen does not save too early.
- Added **Done — save Dropbox after 2FA** fallback for Android TV testing.
- Libraries now shows Dropbox as Logged in with the saved account label.
- Add Cloud Service now opens Dropbox instead of leaving it as coming soon.
- Kept native Dropbox API streaming staged for a later OAuth/API provider pass; v1.8 uses the provider web app so folders are visible now.

## v1.6 — Connected Libraries

- Bumped Cloud Player to v1.6.
- Logged-in providers now stay visible from the Libraries hub.
- pCloud login now returns to Libraries instead of dropping straight into the pCloud browser.
- MEGA web sign-in now records a connected-library marker and returns to Libraries.
- Added direct Libraries navigation from provider connection screens.
- Added MEGA remove/disconnect action for the staged web-session marker.
- Improved provider switching foundation so multiple cloud services can live side-by-side.

## v1.4 — MEGA Web Sign-in

- Bumped Cloud Player to v1.4.
- Replaced the custom MEGA email/password form with a MEGA WebView sign-in path.
- Allows MEGA to handle password entry, two-factor authentication, CAPTCHA, and account-security changes directly.
- Added Android TV D-pad pointer support to the MEGA login WebView.
- Kept the MEGA shared-link entry path available.
- Clarified that full MEGA account browsing still requires the official MEGA SDK/decryption provider layer.

## v1.3 — Library Manager Foundation

- Bumped Cloud Player to v1.3.
- Added a Libraries hub for switching between connected cloud services.
- Show saved pCloud accounts as selectable libraries.
- Keep MEGA available from the same provider hub for sign-in and shared-link staging.
- Added a Libraries action in the pCloud browser menu so the app no longer feels locked to one main provider.
- Prepared the UI flow for multiple providers to coexist side-by-side.

## v1.2 — MEGA Sign-in Foundation

- Bumped Cloud Player to v1.2.
- Added initial MEGA sign-in screen.
- Added a MEGA authentication repository boundary.
- Kept MEGA shared-link validation path available.
- Documented that real MEGA account browsing requires the official MEGA SDK/JNI provider layer.

All notable changes to **Cloud Player**.


## v1.1 — MEGA Provider Foundation

- Bumped Cloud Player to v1.1.
- Enabled MEGA as the first additional provider path on the start screen.
- Added a dedicated MEGA connection screen.
- Added account-login and shared-link entry points for MEGA.
- Added MEGA shared-link validation for file and folder links.
- Documented that MEGA streaming requires the next decrypting provider layer.

## v1.0 — Initial Cloud Player Release

### Added

- Created Cloud Player as its own provider-neutral project.
- Reset versioning to v1.0.
- Added new Cloud Player app name and branding.
- Added new monochrome cloud/play app icon.
- Updated Android package identity to `com.typezero.cloudplayer`.
- Preserved pCloud as the first working provider.
- Preserved the provider foundation for future cloud services.

### Preserved from pCloudTV foundation

- Android playback support.
- Android TV playback support.
- Android Auto audio support.
- pCloud browsing and streaming.
- Video, music, playlist, and audiobook playback.
- Queue and resume behavior.
- TV playback isolation improvements.
- Real-time visualizer support when Microphone permission is granted.

### Planned

- MEGA provider support.
- Library manager.
- Provider-neutral home screen.
- Unified search across providers.
- Additional providers: Google Drive, Dropbox, OneDrive, SMB, WebDAV, Nextcloud.

## v1.1 — MEGA Provider Foundation

- Bumped Cloud Player to v1.1.
- Enabled MEGA as the first additional provider path on the start screen.
- Added a dedicated MEGA connection screen.
- Added account-login and shared-link entry points for MEGA.
- Added MEGA shared-link validation for file and folder links.
- Documented that MEGA streaming requires the next decrypting provider layer.

## v1.0-provider-start

- Added a provider-first start screen for Cloud Player.
- pCloud is now presented as the first available library provider.
- Added placeholder provider cards for MEGA, Google Drive, Dropbox, OneDrive, SMB, and WebDAV.
- Kept future providers disabled until their integrations are implemented.
- Clarified that Cloud Player is library/provider driven rather than pCloud-only.



- MEGA web login now detects completed sign-in/2FA, saves a MEGA logged-in marker, and shows the detected account email on Libraries when available.
### v1.6 MEGA login-status follow-up
- Improved MEGA WebView signed-in detection for hash-router URLs like `#fm`.
- Added broader MEGA account-state checks for Cloud Drive / account UI after 2FA.
- Added a manual Android TV fallback button: **I am logged in — show MEGA on Libraries**.
- MEGA now saves a visible connected-library marker even when MEGA does not expose the account email to the WebView.


## v1.6 MEGA login status hotfix 2
- Improved MEGA WebView sign-in detection for MEGA's single-page app after 2FA.
- Checks MEGA web app globals such as `u_type`, `u_handle`, and `u_attr.email` instead of relying only on URL changes.
- Keeps a visible Done button so the user can explicitly save the MEGA login marker when MEGA hides state from WebView probing.