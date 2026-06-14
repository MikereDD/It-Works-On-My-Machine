package com.typezero.siphon.data.model

/**
 * User-supplied metadata written to the extracted file. Empty fields are skipped.
 * [embedSourceMetadata] pulls title/uploader/etc. from the source (links);
 * explicit fields below override it.
 */
data class Tags(
    val title: String = "",
    val artist: String = "",
    val album: String = "",
    val albumArtist: String = "",
    val genre: String = "",
    val year: String = "",
    val track: String = "",
    val comment: String = "",
    val embedSourceMetadata: Boolean = true,
    /** Embed source thumbnail as cover art (links only; ignored for local files). */
    val embedThumbnail: Boolean = false
) {
    fun hasAnyExplicit(): Boolean =
        listOf(title, artist, album, albumArtist, genre, year, track, comment)
            .any { it.isNotBlank() }
}
