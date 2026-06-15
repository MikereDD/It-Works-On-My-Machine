package com.typezero.seraph.data.rename

/**
 * Renders a filename from a token template and a map of tag values.
 *
 * Supported tokens: {track} {total} {title} {artist} {album} {albumartist}
 * {year} {disc}. Empty tokens collapse the " - " separators around them, so a
 * missing album never leaves a dangling "01 - Foundring -  -". Output is
 * sanitized for both Android and Windows (pCloud syncs back to Windows), and the
 * original extension is preserved.
 *
 * Implemented without compiled regex on purpose: a static Regex field that fails
 * to compile on a given Android build would throw ExceptionInInitializerError
 * and take down the whole object the first time it's touched.
 */
object FilenameTemplate {

    const val DEFAULT = "{track} of {total} - {artist} - {title} - {album}"

    val TOKENS = listOf("track", "total", "title", "artist", "album", "albumartist", "year", "disc")

    // Characters Windows/Android forbid in filenames (slashes handled separately).
    private val ILLEGAL = setOf(':', '*', '?', '"', '<', '>', '|')

    private val RESERVED = setOf(
        "CON", "PRN", "AUX", "NUL",
        "COM1", "COM2", "COM3", "COM4", "COM5", "COM6", "COM7", "COM8", "COM9",
        "LPT1", "LPT2", "LPT3", "LPT4", "LPT5", "LPT6", "LPT7", "LPT8", "LPT9",
    )

    fun render(template: String, values: Map<String, String>, extension: String): String {
        var s = template
        for (token in TOKENS) {
            s = s.replace("{$token}", values[token]?.trim().orEmpty())
        }
        s = stripUnknownTokens(s)     // drop any leftover {tokens}
        s = sanitize(s)               // slashes -> '-', strip control + illegal chars
        s = collapseSeparatorRuns(s)  // "a -  - b" -> "a - b"
        s = collapseSpaces(s).trim()
        s = s.trim('-', ' ')          // no leading/trailing separators
        s = s.trimEnd('.', ' ')       // Windows hates trailing dots/spaces
        if (s.uppercase() in RESERVED) s = "_$s"
        if (s.isBlank()) s = "untitled"
        return if (extension.isBlank()) s else "$s.$extension"
    }

    private fun stripUnknownTokens(s: String): String {
        val sb = StringBuilder()
        var i = 0
        while (i < s.length) {
            val c = s[i]
            if (c == '{') {
                val close = s.indexOf('}', i + 1)
                if (close > i + 1 && (i + 1 until close).all { s[it].isLetter() }) {
                    i = close + 1
                    continue
                }
            }
            sb.append(c)
            i++
        }
        return sb.toString()
    }

    private fun sanitize(s: String): String = buildString {
        for (c in s) {
            when {
                c == '/' || c == '\\' -> append('-')  // AC/DC -> AC-DC (readable)
                c.code < 0x20 -> {}                    // control chars
                c in ILLEGAL -> {}                     // : * ? " < > |
                else -> append(c)
            }
        }
    }

    /** Collapse runs of two or more " - " separators (left by empty tokens) into one. */
    private fun collapseSeparatorRuns(s: String): String {
        val sb = StringBuilder()
        var i = 0
        val n = s.length
        while (i < n) {
            var j = i
            var dashes = 0
            while (j < n) {
                var k = j
                while (k < n && s[k].isWhitespace()) k++
                if (k < n && s[k] == '-') {
                    k++
                    while (k < n && s[k].isWhitespace()) k++
                    dashes++
                    j = k
                } else {
                    break
                }
            }
            when {
                dashes >= 2 -> { sb.append(" - "); i = j }
                dashes == 1 -> { sb.append(s, i, j); i = j }
                else -> { sb.append(s[i]); i++ }
            }
        }
        return sb.toString()
    }

    private fun collapseSpaces(s: String): String {
        val sb = StringBuilder()
        var prevSpace = false
        for (c in s) {
            if (c.isWhitespace()) {
                if (!prevSpace) sb.append(' ')
                prevSpace = true
            } else {
                sb.append(c)
                prevSpace = false
            }
        }
        return sb.toString()
    }
}
