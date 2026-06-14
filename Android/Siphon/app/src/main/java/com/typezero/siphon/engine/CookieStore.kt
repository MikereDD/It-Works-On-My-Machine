package com.typezero.siphon.engine

import android.content.Context
import android.net.Uri
import java.io.File

/**
 * Holds an optional Netscape-format cookies.txt the user exports from a
 * logged-in browser. yt-dlp reads it via --cookies to get past YouTube's
 * "Sign in to confirm you're not a bot" wall. Stored in app filesDir so it
 * survives restarts; yt-dlp may rewrite it as cookies rotate.
 */
class CookieStore(private val appContext: Context) {

    private val file: File get() = File(appContext.filesDir, "cookies.txt")

    fun hasCookies(): Boolean = file.exists() && file.length() > 0
    fun path(): String? = if (hasCookies()) file.absolutePath else null

    /** Copy a picked file into app storage. Returns false if it isn't a cookie file. */
    fun importFrom(uri: Uri): Boolean {
        val bytes = appContext.contentResolver.openInputStream(uri)?.use { it.readBytes() }
            ?: return false
        if (!looksLikeCookies(bytes.toString(Charsets.UTF_8))) return false
        file.writeBytes(bytes)
        return true
    }

    fun clear() { file.delete() }

    private fun looksLikeCookies(s: String): Boolean {
        if (s.isBlank()) return false
        return s.contains("# Netscape", ignoreCase = true) ||
            s.contains("# HTTP Cookie", ignoreCase = true) ||
            s.lineSequence().any { line -> line.count { it == '\t' } >= 5 }
    }
}
