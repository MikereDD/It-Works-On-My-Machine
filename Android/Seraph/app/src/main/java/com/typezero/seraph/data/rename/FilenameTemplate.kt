package com.typezero.seraph.data.rename

/**
 * Renders a filename from a token template and a map of tag values.
 *
 * Supported tokens: {track} {total} {title} {artist} {album} {albumartist}
 * {year} {disc}. Empty tokens collapse the " - " separators around them, so a
 * missing album never leaves a dangling "01 - Foundring -  -". Output is
 * sanitized for both Android and Windows (pCloud syncs back to Windows), and the
 * original extension is preserved.
 */
object FilenameTemplate {

    const val DEFAULT = "{track} of {total} - {artist} - {title} - {album}"

    val TOKENS = listOf("track", "total", "title", "artist", "album", "albumartist", "year", "disc")

    private val ANY_TOKEN = Regex("\\{[a-zA-Z]+}")
    private val SEPARATOR_RUN = Regex("(\\s*-\\s*){2,}")
    private val MULTISPACE = Regex("\\s{2,}")
    private val REMOVE_CHARS = Regex("[:*?\"<>|\\x00-\\x1F]")
    private val SLASHES = Regex("[/\\\\]")
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
        s = ANY_TOKEN.replace(s, "")          // drop any unknown tokens
        s = SLASHES.replace(s, "-")           // AC/DC -> AC-DC (keep it readable)
        s = REMOVE_CHARS.replace(s, "")       // strip the rest of the illegal set
        s = SEPARATOR_RUN.replace(s, " - ")   // collapse separators left by empty tokens
        s = MULTISPACE.replace(s, " ").trim()
        s = s.trim('-', ' ')                  // no leading/trailing separators
        s = s.trimEnd('.', ' ')               // Windows hates trailing dots/spaces
        if (s.uppercase() in RESERVED) s = "_$s"
        if (s.isBlank()) s = "untitled"
        return if (extension.isBlank()) s else "$s.$extension"
    }
}
