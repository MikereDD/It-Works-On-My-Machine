package com.typezero.seraph.data.tagging

import com.typezero.seraph.data.model.Tags
import org.jaudiotagger.audio.AudioFileIO
import org.jaudiotagger.tag.FieldKey
import org.jaudiotagger.tag.images.AndroidArtwork
import java.io.File

/** Pure jaudiotagger read/write against a local File. Storage-agnostic. */
class Tagger {

    fun read(file: File): Tags {
        val af = AudioFileIO.read(file)
        val tag = af.tagOrCreateAndSetDefault
        fun f(key: FieldKey) = runCatching { tag.getFirst(key) }.getOrDefault("")
        val art = runCatching { tag.firstArtwork?.binaryData }.getOrNull()
        return Tags(
            title = f(FieldKey.TITLE),
            artist = f(FieldKey.ARTIST),
            album = f(FieldKey.ALBUM),
            albumArtist = f(FieldKey.ALBUM_ARTIST),
            trackNumber = f(FieldKey.TRACK),
            trackTotal = f(FieldKey.TRACK_TOTAL),
            discNumber = f(FieldKey.DISC_NO),
            year = f(FieldKey.YEAR),
            genre = f(FieldKey.GENRE),
            comment = f(FieldKey.COMMENT),
            artwork = art,
        )
    }

    fun write(file: File, tags: Tags) {
        val af = AudioFileIO.read(file)
        val tag = af.tagOrCreateAndSetDefault
        fun set(key: FieldKey, value: String) {
            if (value.isBlank()) runCatching { tag.deleteField(key) } else tag.setField(key, value)
        }
        set(FieldKey.TITLE, tags.title)
        set(FieldKey.ARTIST, tags.artist)
        set(FieldKey.ALBUM, tags.album)
        set(FieldKey.ALBUM_ARTIST, tags.albumArtist)
        set(FieldKey.TRACK, tags.trackNumber)
        set(FieldKey.TRACK_TOTAL, tags.trackTotal)
        set(FieldKey.DISC_NO, tags.discNumber)
        set(FieldKey.YEAR, tags.year)
        set(FieldKey.GENRE, tags.genre)
        set(FieldKey.COMMENT, tags.comment)
        tags.artwork?.let { bytes ->
            runCatching {
                tag.deleteArtworkField()
                val art = AndroidArtwork().apply {
                    binaryData = bytes
                    mimeType = sniffMime(bytes)
                    pictureType = 3
                }
                tag.setField(tag.createField(art))
            }
        }
        af.commit()
    }

    private fun sniffMime(bytes: ByteArray): String = when {
        bytes.size > 3 && bytes[0] == 0xFF.toByte() && bytes[1] == 0xD8.toByte() -> "image/jpeg"
        bytes.size > 8 && bytes[0] == 0x89.toByte() && bytes[1] == 'P'.code.toByte() -> "image/png"
        else -> "image/jpeg"
    }

    companion object {
        val SUPPORTED_EXTENSIONS = setOf("mp3", "flac", "m4a", "mp4", "ogg", "opus", "wav", "aac", "wma")
    }
}
