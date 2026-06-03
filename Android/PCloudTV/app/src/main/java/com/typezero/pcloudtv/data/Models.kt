package com.typezero.pcloudtv.data

/** A single entry returned by listfolder: either a folder or a file. */
data class PItem(
    val name: String,
    val isFolder: Boolean,
    val folderId: Long?,   // set when isFolder == true
    val fileId: Long?,     // set when isFolder == false
    val contentType: String,
    val category: Int,     // pCloud category: 1=image, 2=video, 3=audio, 4=document, 5=archive
    val size: Long
) {
    val isVideo: Boolean get() = category == 2 || contentType.startsWith("video/")
    val isAudio: Boolean get() = category == 3 || contentType.startsWith("audio/")
    val isPlaylist: Boolean get() =
        name.endsWith(".m3u", true) || name.endsWith(".m3u8", true)
    val isPlayable: Boolean get() = isVideo || isAudio
    /** Things the user can tap to start playback (files or playlists). */
    val isOpenable: Boolean get() = isPlayable || isPlaylist
}

/** One item in the player's queue: a pCloud file (resolve on demand) or a direct URL. */
data class MediaItem(
    val title: String,
    val fileId: Long?,      // resolve via getfilelink when about to play
    val directUrl: String?  // already an absolute URL (e.g. http entry in a playlist)
)

/** A folder that contains playable files, used by the recursive playlist generator. */
data class AudioFolder(
    val folderId: Long,
    val name: String,
    val files: List<PItem>
)

/** Result of authenticating against pCloud. */
data class Session(
    val authToken: String,
    val apiHost: String   // "api.pcloud.com" (US) or "eapi.pcloud.com" (EU)
)

sealed interface ApiResult<out T> {
    data class Ok<T>(val value: T) : ApiResult<T>
    data class Error(val message: String) : ApiResult<Nothing>
}
