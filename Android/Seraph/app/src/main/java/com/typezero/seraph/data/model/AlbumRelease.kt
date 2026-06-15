package com.typezero.seraph.data.model

/** A release (album) candidate from a MusicBrainz release search. */
data class ReleaseCandidate(
    val mbid: String,
    val title: String,
    val artist: String,
    val date: String?,
    val trackCount: Int,
) {
    val year: String get() = date?.take(4)?.takeIf { it.length == 4 } ?: ""
}

/** One track on a release. [position] is sequential across all media (1..N). */
data class ReleaseTrack(
    val position: Int,
    val title: String,
    val artist: String,
)

/** A fetched release with its full tracklist. */
data class ReleaseDetail(
    val mbid: String,
    val title: String,
    val artist: String,
    val date: String?,
    val tracks: List<ReleaseTrack>,
) {
    val year: String get() = date?.take(4)?.takeIf { it.length == 4 } ?: ""
    val total: Int get() = tracks.size
}
