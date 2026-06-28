# Changelog

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