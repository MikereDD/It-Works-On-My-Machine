package com.typezero.seraph.pcloud

/**
 * pCloud settings.
 *
 * Sign-in opens pCloud's real web login in a WebView (so Google sign-in and 2FA
 * just work), and Seraph captures the account's auth token from that session.
 * No app key, OAuth app, or redirect to register.
 */
object PCloudConfig {
    // The only folders Seraph scans. Add/edit paths here — nothing else is touched.
    val SCAN_PATHS = listOf("/Music", "/Books/Audiobooks")
}
