package com.typezero.cloudplayer.data

import java.net.URI
import java.net.URLDecoder

/**
 * Recognizes shared links that can be handed directly to Cloud Player's native
 * LibVLC player. This is intentionally conservative: provider links that still
 * need an API/decryption backend are left to their provider-specific flows.
 */
object SharedMediaLinkParser {
    private val mediaExts = setOf(
        "mp4", "mkv", "m4v", "mov", "webm", "avi", "ts", "m2ts", "mpg", "mpeg", "wmv",
        "mp3", "flac", "m4a", "aac", "ogg", "opus", "wav", "wma", "m3u", "m3u8"
    )

    data class Parsed(
        val provider: String,
        val title: String,
        val playbackUrl: String
    )

    fun parse(input: String): Parsed? {
        val firstUrl = Regex("https?://\\S+", RegexOption.IGNORE_CASE)
            .find(input.trim())?.value?.trim()?.trimEnd(',', ')', ']', '}') ?: return null
        val lower = firstUrl.lowercase()

        if (lower.contains("mega.nz/")) return null // MEGA needs its decrypting backend.

        if (lower.contains("dropbox.com/")) {
            return Parsed(
                provider = "Dropbox",
                title = guessTitle(firstUrl).ifBlank { "Dropbox media" },
                playbackUrl = normalizeDropbox(firstUrl)
            )
        }

        if (lower.contains("box.com/") || lower.contains("app.box.com/")) {
            // Box public pages are not always raw media URLs, but keeping the route here
            // allows links that already resolve directly to be opened by LibVLC.
            return Parsed("Box", guessTitle(firstUrl).ifBlank { "Box media" }, firstUrl)
        }

        if (lower.startsWith("http://") || lower.startsWith("https://")) {
            val title = guessTitle(firstUrl)
            if (looksPlayable(firstUrl) || lower.contains("dl=1") || lower.contains("raw=1")) {
                return Parsed("Direct Link", title.ifBlank { "Shared media" }, firstUrl)
            }
        }

        return null
    }

    private fun looksPlayable(url: String): Boolean {
        val clean = url.substringBefore('?').substringBefore('#')
        val ext = clean.substringAfterLast('.', "").lowercase()
        return ext in mediaExts
    }

    private fun normalizeDropbox(url: String): String {
        var out = url.replace("www.dropbox.com", "dl.dropboxusercontent.com")
        out = out.replace("dropbox.com", "dl.dropboxusercontent.com")
        out = out.replace(Regex("[?&]dl=0"), "")
        out = out.replace(Regex("[?&]raw=1"), "")
        val sep = if (out.contains('?')) "&" else "?"
        return out + sep + "dl=1"
    }

    private fun guessTitle(url: String): String {
        return runCatching {
            val path = URI(url).path ?: return@runCatching ""
            URLDecoder.decode(path.substringAfterLast('/'), "UTF-8")
        }.getOrDefault("").ifBlank {
            url.substringBefore('?').substringBefore('#').substringAfterLast('/').ifBlank { "Shared media" }
        }
    }
}
