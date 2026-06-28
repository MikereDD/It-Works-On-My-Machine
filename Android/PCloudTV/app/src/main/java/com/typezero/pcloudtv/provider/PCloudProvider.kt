package com.typezero.pcloudtv.provider

import com.typezero.pcloudtv.data.ApiResult
import com.typezero.pcloudtv.data.MediaItem
import com.typezero.pcloudtv.data.PCloudClient
import com.typezero.pcloudtv.data.PItem
import com.typezero.pcloudtv.data.Session

/**
 * pCloud implementation of the v4.50 provider interface.
 *
 * This adapter is intentionally thin for now: existing screens still use
 * PCloudClient directly, while new v4.50 work can target CloudProvider.
 */
class PCloudProvider(
    private val session: Session,
    private val client: PCloudClient
) : CloudProvider {
    override val id: String = "pcloud"
    override val displayName: String = "pCloud"

    override suspend fun listFolder(folderRef: FolderRef): ApiResult<List<PItem>> {
        folderRef.path?.let { path ->
            if (path.isNotBlank() && path != "/") return client.listFolderByPath(session, path)
        }
        return client.listFolder(session, folderRef.id ?: 0L)
    }

    override suspend fun streamUrl(item: MediaItem): ApiResult<String> {
        item.directUrl?.let { return ApiResult.Ok(it) }
        item.path?.let { return client.getStreamUrlByPath(session, it) }
        val id = item.fileId ?: return ApiResult.Error("No stream source for ${item.title}")
        return client.getStreamUrl(session, id)
    }

    override suspend fun resolvePlaylist(
        playlist: PItem,
        parentFolderItems: List<PItem>
    ): ApiResult<List<MediaItem>> = client.resolvePlaylist(session, playlist, parentFolderItems)
}
