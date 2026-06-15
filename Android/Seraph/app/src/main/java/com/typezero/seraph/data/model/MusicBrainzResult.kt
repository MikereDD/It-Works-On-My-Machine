package com.typezero.seraph.data.model

/** A single recording candidate returned from a MusicBrainz search. */
data class MusicBrainzResult(
    val recordingMbid: String,
    val title: String,
    val artist: String,
    val album: String,
    val releaseMbid: String?,
    val date: String?,        // release date, may be just a year
    val trackNumber: String?,
    val trackTotal: String?,
    val score: Int,           // MB match confidence 0..100
) {
    val year: String get() = date?.take(4)?.takeIf { it.length == 4 } ?: ""
}
