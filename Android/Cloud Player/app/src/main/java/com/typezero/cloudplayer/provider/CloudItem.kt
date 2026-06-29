package com.typezero.cloudplayer.provider

import com.typezero.cloudplayer.data.MediaItem

/**
 * v2.2 provider-neutral file model.
 *
 * Every cloud backend converts its native API objects into CloudItem so the
 * browser, player, cast menu, and future unified library do not care whether
 * an entry came from pCloud, MEGA, Dropbox, Box, or another provider.
 */
data class CloudItem(
    val id: String,
    val name: String,
    val type: CloudItemType,
    val providerId: String,
    val path: String = "/",
    val sizeBytes: Long? = null,
    val mimeType: String? = null,
    val modifiedLabel: String? = null,
    val thumbnailUrl: String? = null,
    val directUrl: String? = null
) {
    val isFolder: Boolean get() = type == CloudItemType.FOLDER
    val isVideo: Boolean get() = type == CloudItemType.VIDEO
    val isAudio: Boolean get() = type == CloudItemType.AUDIO
    val isPlayable: Boolean get() = isVideo || isAudio || directUrl != null

    fun toMediaItem(): MediaItem = MediaItem(
        title = name,
        fileId = null,
        directUrl = directUrl,
        path = path.takeIf { it.isNotBlank() }
    )
}

enum class CloudItemType {
    FOLDER,
    VIDEO,
    AUDIO,
    IMAGE,
    PLAYLIST,
    DOCUMENT,
    FILE
}

data class CloudFolderResult(
    val providerId: String,
    val providerName: String,
    val path: String,
    val breadcrumb: List<String>,
    val items: List<CloudItem>,
    val liveApiBacked: Boolean = false,
    val statusMessage: String? = null
)
