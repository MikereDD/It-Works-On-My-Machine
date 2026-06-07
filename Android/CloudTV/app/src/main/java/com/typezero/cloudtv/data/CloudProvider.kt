package com.typezero.cloudtv.data

/**
 * One cloud backend (pCloud, Google Drive, …).
 *
 * The browse/stream layer talks to this interface so new providers can be
 * added without touching the UI. Each instance is bound to a single signed-in
 * account, so calls don't need to pass a session/token around.
 */
interface CloudProvider {

    val type: CloudProviderType

    /** List a folder's contents. Pass [ROOT] for the account's top level. */
    suspend fun listFolder(folderId: String): ApiResult<List<CloudItem>>

    /** Resolve a playable source (URL + any required headers) for a file id. */
    suspend fun streamSource(fileId: String): ApiResult<StreamSource>

    /** A thumbnail URL for a file, or null if the provider has none. */
    suspend fun thumbnail(fileId: String, size: String): String?

    companion object {
        /** Conventional id of a provider's root folder. */
        const val ROOT = "0"
    }
}
