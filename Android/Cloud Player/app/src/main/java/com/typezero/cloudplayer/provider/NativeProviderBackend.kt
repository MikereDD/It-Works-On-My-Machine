package com.typezero.cloudplayer.provider

/**
 * v2.2 native provider API foundation.
 *
 * Providers should implement this boundary with their real APIs. The UI should
 * depend only on this interface so adding Google Drive, OneDrive, SMB, or WebDAV
 * does not require another provider-specific browser screen.
 */
interface NativeProviderBackend {
    val providerId: String
    val providerName: String

    suspend fun listFolder(path: String): CloudFolderResult

    suspend fun stream(item: CloudItem): String? = item.directUrl
}

object NativeProviderBackends {
    fun forProvider(providerId: String, providerName: String): NativeProviderBackend =
        StagedNativeProviderBackend(providerId = providerId, providerName = providerName)
}

private class StagedNativeProviderBackend(
    override val providerId: String,
    override val providerName: String
) : NativeProviderBackend {
    override suspend fun listFolder(path: String): CloudFolderResult {
        val normalized = path.ifBlank { "/" }
        val items = stagedItems(providerId, normalized)
        return CloudFolderResult(
            providerId = providerId,
            providerName = providerName,
            path = normalized,
            breadcrumb = normalized.split('/').filter { it.isNotBlank() },
            items = items,
            liveApiBacked = false,
            statusMessage = "$providerName is using the v2.2 native provider API shell. Live token-backed listing is the next backend pass."
        )
    }
}

private fun stagedItems(providerId: String, path: String): List<CloudItem> {
    val provider = providerId.lowercase()
    if (path != "/") {
        val safe = path.trim('/').ifBlank { "Root" }
        return listOf(
            CloudItem(
                id = "$provider:$path:sample-video",
                name = "$safe sample video.mkv",
                type = CloudItemType.VIDEO,
                providerId = providerId,
                path = "$path/$safe sample video.mkv",
                sizeBytes = 0,
                mimeType = "video/x-matroska",
                modifiedLabel = "Staged"
            ),
            CloudItem(
                id = "$provider:$path:sample-audio",
                name = "$safe sample audio.flac",
                type = CloudItemType.AUDIO,
                providerId = providerId,
                path = "$path/$safe sample audio.flac",
                sizeBytes = 0,
                mimeType = "audio/flac",
                modifiedLabel = "Staged"
            )
        )
    }

    return when (provider) {
        "dropbox" -> listOf(
            folder(providerId, "Movies", "/Movies"),
            folder(providerId, "TV Shows", "/TV Shows"),
            folder(providerId, "Music", "/Music")
        )
        "box" -> listOf(
            folder(providerId, "Movies", "/Movies"),
            folder(providerId, "TV Shows", "/TV Shows"),
            folder(providerId, "Music", "/Music")
        )
        "mega" -> listOf(
            folder(providerId, "Videos", "/Videos"),
            folder(providerId, "Music", "/Music"),
            folder(providerId, "Shared", "/Shared")
        )
        else -> listOf(
            folder(providerId, "Movies", "/Movies"),
            folder(providerId, "TV Shows", "/TV Shows"),
            folder(providerId, "Music", "/Music")
        )
    }
}

private fun folder(providerId: String, name: String, path: String): CloudItem = CloudItem(
    id = "${providerId.lowercase()}:$path",
    name = name,
    type = CloudItemType.FOLDER,
    providerId = providerId,
    path = path
)
