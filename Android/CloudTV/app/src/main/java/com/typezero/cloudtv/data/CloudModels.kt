package com.typezero.cloudtv.data

/** Which cloud backend an account belongs to. */
enum class CloudProviderType(val displayName: String) {
    PCLOUD("pCloud"),
    GDRIVE("Google Drive"),
    ONEDRIVE("OneDrive")
    // MEGA("MEGA") — later
}

/** Provider-agnostic media classification (replaces pCloud's numeric category). */
enum class MediaKind { VIDEO, AUDIO, IMAGE, PLAYLIST, FOLDER, OTHER }

/**
 * A provider-agnostic browse entry.
 *
 * [id] is a String so it fits every backend (pCloud's numeric ids are
 * stringified; Drive/OneDrive ids are already strings). [ref] optionally
 * carries the provider's native object so provider-specific features
 * (e.g. pCloud's playlist tools) can recover their original data.
 */
data class CloudItem(
    val id: String,
    val name: String,
    val isFolder: Boolean,
    val kind: MediaKind,
    val sizeBytes: Long?,
    val ref: Any? = null
) {
    val isVideo: Boolean get() = kind == MediaKind.VIDEO
    val isAudio: Boolean get() = kind == MediaKind.AUDIO
    val isImage: Boolean get() = kind == MediaKind.IMAGE
    val isPlaylist: Boolean get() = kind == MediaKind.PLAYLIST
    val isPlayable: Boolean get() = isVideo || isAudio
    val isOpenable: Boolean get() = isPlayable || isPlaylist
}

/**
 * A resolved, playable source: a direct URL plus any HTTP headers the player
 * must send with it. pCloud and OneDrive need no headers (their URLs are
 * pre-authenticated); Google Drive will carry an Authorization header here.
 */
data class StreamSource(
    val url: String,
    val headers: Map<String, String> = emptyMap()
)
