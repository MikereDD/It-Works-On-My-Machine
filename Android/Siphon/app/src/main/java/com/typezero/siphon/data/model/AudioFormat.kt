package com.typezero.siphon.data.model

/**
 * Output audio formats Siphon can produce.
 *
 * COPY is the "best quality" default: it asks yt-dlp to keep the source audio
 * stream and only re-encodes if the container demands it, so for most files the
 * original audio is extracted losslessly with zero generation loss.
 */
enum class AudioFormat(
    val id: String,
    val label: String,
    /** yt-dlp --audio-format value; "best" keeps the source codec when possible. */
    val ytdlpAudioFormat: String,
    val extension: String,
    /** true when the format is lossy and a bitrate selector is meaningful. */
    val lossy: Boolean
) {
    COPY("copy", "Best quality (keep original)", "best", "m4a", false),
    MP3("mp3", "MP3", "mp3", "mp3", true),
    M4A("m4a", "M4A / AAC", "m4a", "m4a", true),
    OPUS("opus", "Opus", "opus", "opus", true),
    FLAC("flac", "FLAC (lossless)", "flac", "flac", false),
    WAV("wav", "WAV (uncompressed)", "wav", "wav", false);

    companion object {
        fun fromId(id: String): AudioFormat = entries.firstOrNull { it.id == id } ?: COPY
    }
}
