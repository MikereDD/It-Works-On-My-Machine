package com.typezero.siphon.data.model

import android.net.Uri

/** A local video discovered via MediaStore, shown in the searchable picker. */
data class VideoItem(
    val id: Long,
    val displayName: String,
    val uri: Uri,
    /** Real filesystem path when resolvable (yt-dlp needs a path, not a content uri). */
    val filePath: String?,
    val durationMs: Long,
    val sizeBytes: Long,
    val mimeType: String?,
    val dateAddedSec: Long
)
