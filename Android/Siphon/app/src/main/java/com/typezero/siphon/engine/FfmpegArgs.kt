package com.typezero.siphon.engine

import com.typezero.siphon.data.model.AudioFormat
import com.typezero.siphon.data.model.AudioQuality
import com.typezero.siphon.data.model.Tags

/**
 * Builds the argument list for the bundled FFmpeg binary to extract audio from a
 * LOCAL file. Unlike the yt-dlp path, args go straight to ProcessBuilder, so each
 * token is a separate list element — no shell quoting needed for tag values.
 *
 * Pure / JVM-only so it can be unit-tested.
 */
object FfmpegArgs {

    private fun metadataPairs(t: Tags): List<Pair<String, String>> = buildList {
        if (t.title.isNotBlank())       add("title" to t.title)
        if (t.artist.isNotBlank())      add("artist" to t.artist)
        if (t.album.isNotBlank())       add("album" to t.album)
        if (t.albumArtist.isNotBlank()) add("album_artist" to t.albumArtist)
        if (t.genre.isNotBlank())       add("genre" to t.genre)
        if (t.year.isNotBlank())        add("date" to t.year)
        if (t.track.isNotBlank())       add("track" to t.track)
        if (t.comment.isNotBlank())     add("comment" to t.comment)
    }

    /** "320K" -> "320k"; VBR index "0" handled by caller. */
    private fun cbr(q: AudioQuality): String = q.ytdlpValue.lowercase()

    fun build(
        format: AudioFormat,
        quality: AudioQuality,
        inputPath: String,
        outputPath: String,
        tags: Tags
    ): List<String> = buildList {
        add("-hide_banner"); add("-nostdin"); add("-y")
        add("-i"); add(inputPath)
        add("-vn")                       // no video
        add("-map"); add("0:a:0")        // first audio stream only

        when (format) {
            AudioFormat.COPY -> { add("-c:a"); add("copy") }
            AudioFormat.FLAC -> { add("-c:a"); add("flac") }
            AudioFormat.WAV  -> { add("-c:a"); add("pcm_s16le") }
            AudioFormat.MP3 -> {
                add("-c:a"); add("libmp3lame")
                if (quality == AudioQuality.BEST) { add("-q:a"); add("0") }
                else { add("-b:a"); add(cbr(quality)) }
            }
            AudioFormat.M4A -> {
                add("-c:a"); add("aac")
                add("-b:a"); add(if (quality == AudioQuality.BEST) "256k" else cbr(quality))
            }
            AudioFormat.OPUS -> {
                add("-c:a"); add("libopus")
                add("-b:a"); add(if (quality == AudioQuality.BEST) "256k" else cbr(quality))
            }
        }

        metadataPairs(tags).forEach { (k, v) -> add("-metadata"); add("$k=$v") }
        add(outputPath)
    }

    /**
     * Output extension for the chosen format. For COPY the container depends on
     * the source codec; [sourceAudioMime] (from MediaExtractor) picks a matching
     * container, falling back to Matroska (.mka), which accepts any codec.
     */
    fun outputExtension(format: AudioFormat, sourceAudioMime: String?): String =
        if (format != AudioFormat.COPY) format.extension
        else when (sourceAudioMime?.lowercase()) {
            "audio/mp4a-latm", "audio/aac" -> "m4a"
            "audio/mpeg" -> "mp3"
            "audio/opus" -> "opus"
            "audio/vorbis" -> "ogg"
            "audio/flac" -> "flac"
            "audio/raw" -> "wav"
            else -> "mka"   // ac3/eac3/dts/etc. — Matroska copies anything
        }
}
