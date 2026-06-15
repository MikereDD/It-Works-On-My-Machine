package com.typezero.seraph.data.model

/**
 * A taggable audio file from some storage source. [id] is opaque to the rest of
 * the app: for the device source it's a SAF document-uri string, for pCloud it's
 * the numeric fileid. The active [com.typezero.seraph.storage.StorageSource]
 * is the only thing that interprets it.
 */
data class AudioFile(
    val sourceId: String,
    val id: String,
    val displayName: String,
    val mimeType: String,
    val sizeBytes: Long,
    val parentId: String = "",
    val parentName: String = "",
) {
    val extension: String
        get() = displayName.substringAfterLast('.', "").lowercase()
}
