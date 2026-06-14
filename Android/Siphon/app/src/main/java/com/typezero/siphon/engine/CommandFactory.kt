package com.typezero.siphon.engine

import com.typezero.siphon.data.model.AudioFormat
import com.typezero.siphon.data.model.ExtractRequest
import com.typezero.siphon.data.model.Tags

/**
 * Pure builder that turns an [ExtractRequest] into the yt-dlp argument list
 * (everything except the python/yt-dlp executable, which the library prepends).
 *
 * The same pipeline serves BOTH sources: a local file path and a remote URL are
 * just the final positional token yt-dlp consumes. yt-dlp's generic extractor
 * accepts a local media path and runs the audio post-processors on it, so we get
 * identical format / quality / tagging behaviour for files and links.
 *
 * No Android dependencies here on purpose — unit-test it on the JVM.
 */
object CommandFactory {

    /** ffmpeg metadata keys mapped from our [Tags] fields. */
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

    /** Single-quote a value for yt-dlp's shlex parsing of --postprocessor-args. */
    private fun shQuote(v: String): String = "'" + v.replace("'", "'\\''") + "'"

    /**
     * Builds the "ExtractAudio:" postprocessor argument string that injects the
     * user's tags into the ffmpeg call that produces the audio. Returns null if
     * there is nothing explicit to write.
     */
    fun buildMetadataPpArg(tags: Tags): String? {
        val pairs = metadataPairs(tags)
        if (pairs.isEmpty()) return null
        val body = pairs.joinToString(" ") { (k, v) -> "-metadata ${k}=${shQuote(v)}" }
        return "ExtractAudio:$body"
    }

    /**
     * @param outputDir absolute directory the app owns and can write to.
     * @param baseName  output file stem (no extension); already sanitised.
     */
    fun build(
        request: ExtractRequest,
        outputDir: String,
        baseName: String
    ): List<String> = buildList {
        val fmt = request.format
        val isLink = request.source is ExtractRequest.Source.Link

        // --- extraction core ---
        add("--extract-audio")
        add("--audio-format"); add(fmt.ytdlpAudioFormat)          // best/mp3/m4a/opus/flac/wav
        if (fmt.lossy) { add("--audio-quality"); add(request.quality.ytdlpValue) }

        // --- output location & naming ---
        add("-o"); add("$outputDir/$baseName.%(ext)s")
        add("--no-playlist")
        add("--no-mtime")
        add("--force-overwrites")

        // --- metadata / tagging (applies to local files and links alike) ---
        if (request.tags.embedSourceMetadata) add("--embed-metadata")
        if (isLink && request.tags.embedThumbnail) {
            add("--embed-thumbnail")
            add("--convert-thumbnails"); add("jpg")
        }
        buildMetadataPpArg(request.tags)?.let { ppArg ->
            add("--postprocessor-args"); add(ppArg)
        }

        // --- robustness for links ---
        if (isLink) {
            add("--retries"); add("5")
            add("--fragment-retries"); add("5")
            add("--no-warnings")
        }
    }

    /** The final positional token yt-dlp consumes (file path or URL). */
    fun sourceToken(request: ExtractRequest): String = when (val s = request.source) {
        is ExtractRequest.Source.LocalFile -> (s.path ?: s.uri)
        is ExtractRequest.Source.Link -> s.url
    }

    /** Predicted output extension (yt-dlp may pick a different one for "best"). */
    fun expectedExtension(fmt: AudioFormat): String = fmt.extension
}
