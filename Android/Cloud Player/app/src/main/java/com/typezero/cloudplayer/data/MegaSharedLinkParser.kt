package com.typezero.cloudplayer.data

/**
 * MEGA shared links are special because the value after '#' is the
 * decryption key, not a disposable URL fragment. Never parse these with
 * Uri.getFragment() and then rebuild without the key.
 */
data class MegaSharedLink(
    val type: MegaSharedLinkType,
    val id: String,
    val key: String,
    val normalizedUrl: String
)

enum class MegaSharedLinkType { FILE, FOLDER }

object MegaSharedLinkParser {
    private val modern = Regex(
        pattern = "https?://(?:www\\.)?mega(?:\\.co)?\\.nz/(file|folder)/([A-Za-z0-9_-]+)(?:#([A-Za-z0-9_-]+))?",
        option = RegexOption.IGNORE_CASE
    )
    private val legacyFile = Regex(
        pattern = "https?://(?:www\\.)?mega(?:\\.co)?\\.nz/#!([A-Za-z0-9_-]+)!([A-Za-z0-9_-]+)",
        option = RegexOption.IGNORE_CASE
    )
    private val legacyFolder = Regex(
        pattern = "https?://(?:www\\.)?mega(?:\\.co)?\\.nz/#F!([A-Za-z0-9_-]+)!([A-Za-z0-9_-]+)",
        option = RegexOption.IGNORE_CASE
    )
    private val keyLine = Regex(
        pattern = "(?im)^(?:decryption\\s*key|key)\\s*:?\\s*([A-Za-z0-9_-]{8,})\\s*$"
    )
    private val bareKey = Regex("^[A-Za-z0-9_-]{8,}$")

    fun parse(rawInput: String): MegaSharedLink? {
        val input = rawInput.trim()
        if (input.isBlank()) return null

        legacyFolder.find(input)?.let { m ->
            val id = m.groupValues[1]
            val key = m.groupValues[2]
            return MegaSharedLink(
                type = MegaSharedLinkType.FOLDER,
                id = id,
                key = key,
                normalizedUrl = "https://mega.nz/folder/$id#$key"
            )
        }

        legacyFile.find(input)?.let { m ->
            val id = m.groupValues[1]
            val key = m.groupValues[2]
            return MegaSharedLink(
                type = MegaSharedLinkType.FILE,
                id = id,
                key = key,
                normalizedUrl = "https://mega.nz/file/$id#$key"
            )
        }

        modern.find(input)?.let { m ->
            val typeText = m.groupValues[1].lowercase()
            val id = m.groupValues[2]
            val inlineKey = m.groupValues.getOrNull(3).orEmpty()
            val key = inlineKey.ifBlank { findSeparateKey(input) }.orEmpty()
            if (key.isBlank()) return null
            val type = if (typeText == "folder") MegaSharedLinkType.FOLDER else MegaSharedLinkType.FILE
            val path = if (type == MegaSharedLinkType.FOLDER) "folder" else "file"
            return MegaSharedLink(
                type = type,
                id = id,
                key = key,
                normalizedUrl = "https://mega.nz/$path/$id#$key"
            )
        }

        return null
    }

    fun looksLikeMegaLink(rawInput: String): Boolean {
        val lower = rawInput.lowercase()
        return lower.contains("mega.nz/file/") ||
            lower.contains("mega.nz/folder/") ||
            lower.contains("mega.co.nz/#!") ||
            lower.contains("mega.nz/#!") ||
            lower.contains("mega.nz/#f!") ||
            lower.contains("mega.co.nz/#f!")
    }

    private fun findSeparateKey(input: String): String? {
        keyLine.find(input)?.let { return it.groupValues[1].trim() }
        val lines = input.lines().map { it.trim() }.filter { it.isNotBlank() }
        val linkIndex = lines.indexOfFirst { looksLikeMegaLink(it) }
        if (linkIndex >= 0) {
            lines.drop(linkIndex + 1).firstOrNull { bareKey.matches(it) }?.let { return it }
        }
        return lines.firstOrNull { bareKey.matches(it) && !looksLikeMegaLink(it) }
    }
}
