package com.typezero.cloudplayer.provider

import com.typezero.cloudplayer.data.ApiResult
import com.typezero.cloudplayer.data.MediaItem
import com.typezero.cloudplayer.data.PItem

/**
 * v1.0 foundation API for storage backends.
 *
 * The player/browser should gradually move toward this interface so pCloud,
 * MEGA, Google Drive, WebDAV, SMB, and local storage can all expose the same
 * basic media operations without leaking provider-specific details into UI code.
 */
interface CloudProvider {
    val id: String
    val displayName: String

    suspend fun listFolder(folderRef: FolderRef): ApiResult<List<PItem>>
    suspend fun streamUrl(item: MediaItem): ApiResult<String>
    suspend fun resolvePlaylist(
        playlist: PItem,
        parentFolderItems: List<PItem>
    ): ApiResult<List<MediaItem>>
}

/** Stable pointer to a provider folder. Providers may use ids, paths, or both. */
data class FolderRef(
    val id: Long? = null,
    val path: String? = null,
    val label: String = path ?: id?.toString() ?: "/"
)

/** A saved library shown to the user. v1.0 keeps pCloud as the active backend. */
data class CloudLibrary(
    val id: String,
    val providerId: String,
    val label: String,
    val root: FolderRef = FolderRef(id = 0L, path = "/", label = "/")
)
