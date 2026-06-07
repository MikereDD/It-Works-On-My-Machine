package com.typezero.cloudtv.data

/**
 * pCloud implementation of [CloudProvider], wrapping the existing
 * [PCloudClient]. pCloud's numeric ids are mapped to/from Strings, and
 * [PItem]s are mapped to provider-agnostic [CloudItem]s (keeping the original
 * PItem in [CloudItem.ref] so pCloud-only features can recover it).
 */
class PCloudProvider(
    private val client: PCloudClient,
    private val session: Session
) : CloudProvider {

    override val type = CloudProviderType.PCLOUD

    override suspend fun listFolder(folderId: String): ApiResult<List<CloudItem>> {
        val id = folderId.toLongOrNull() ?: 0L
        return when (val r = client.listFolder(session, id)) {
            is ApiResult.Ok -> ApiResult.Ok(r.value.map { it.toCloudItem() })
            is ApiResult.Error -> r
        }
    }

    override suspend fun streamSource(fileId: String): ApiResult<StreamSource> {
        val id = fileId.toLongOrNull() ?: return ApiResult.Error("Bad file id")
        return when (val r = client.getStreamUrl(session, id)) {
            is ApiResult.Ok -> ApiResult.Ok(StreamSource(r.value))
            is ApiResult.Error -> r
        }
    }

    override suspend fun thumbnail(fileId: String, size: String): String? {
        val id = fileId.toLongOrNull() ?: return null
        return when (val r = client.getThumbLink(session, id, size)) {
            is ApiResult.Ok -> r.value
            is ApiResult.Error -> null
        }
    }
}

/** Map a pCloud [PItem] to a provider-agnostic [CloudItem]. */
fun PItem.toCloudItem(): CloudItem {
    val kind = when {
        isFolder -> MediaKind.FOLDER
        isPlaylist -> MediaKind.PLAYLIST
        isVideo -> MediaKind.VIDEO
        isAudio -> MediaKind.AUDIO
        isImage -> MediaKind.IMAGE
        else -> MediaKind.OTHER
    }
    val id = (if (isFolder) folderId else fileId)?.toString() ?: ""
    return CloudItem(
        id = id,
        name = name,
        isFolder = isFolder,
        kind = kind,
        sizeBytes = size,
        ref = this
    )
}
