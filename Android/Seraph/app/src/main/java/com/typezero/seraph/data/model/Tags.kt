package com.typezero.seraph.data.model

/**
 * Editable metadata for a single audio file. All fields are plain strings so the
 * editor can treat blank == "clear this tag". [artwork] is the embedded front
 * cover as raw bytes (jpeg/png), or null if none.
 */
data class Tags(
    val title: String = "",
    val artist: String = "",
    val album: String = "",
    val albumArtist: String = "",
    val trackNumber: String = "",
    val trackTotal: String = "",
    val discNumber: String = "",
    val year: String = "",
    val genre: String = "",
    val comment: String = "",
    val artwork: ByteArray? = null,
) {
    // data class with a ByteArray needs manual equals/hashCode to behave.
    override fun equals(other: Any?): Boolean {
        if (this === other) return true
        if (other !is Tags) return false
        return title == other.title && artist == other.artist && album == other.album &&
            albumArtist == other.albumArtist && trackNumber == other.trackNumber &&
            trackTotal == other.trackTotal && discNumber == other.discNumber &&
            year == other.year && genre == other.genre && comment == other.comment &&
            (artwork?.contentEquals(other.artwork) ?: (other.artwork == null))
    }

    override fun hashCode(): Int {
        var result = title.hashCode()
        result = 31 * result + artist.hashCode()
        result = 31 * result + album.hashCode()
        result = 31 * result + albumArtist.hashCode()
        result = 31 * result + trackNumber.hashCode()
        result = 31 * result + trackTotal.hashCode()
        result = 31 * result + discNumber.hashCode()
        result = 31 * result + year.hashCode()
        result = 31 * result + genre.hashCode()
        result = 31 * result + comment.hashCode()
        result = 31 * result + (artwork?.contentHashCode() ?: 0)
        return result
    }
}
