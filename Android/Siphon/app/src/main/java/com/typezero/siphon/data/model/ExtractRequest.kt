package com.typezero.siphon.data.model

/** Everything needed to run one extraction, from either a local file or a URL. */
data class ExtractRequest(
    val source: Source,
    val format: AudioFormat,
    val quality: AudioQuality,
    val tags: Tags,
    /** Base output file name (no extension). Blank = derive from source. */
    val outputName: String,
    /** YouTube player client override (links only); null = yt-dlp default. */
    val extractorClient: String? = null,
    /** Path to a Netscape cookies.txt (links only); null = no cookies. */
    val cookiesPath: String? = null
) {
    sealed interface Source {
        /**
         * A local video. [path] is the MediaStore DATA path (used directly when
         * readable); [uri] is the content:// fallback used to copy the file into
         * cache when the raw path isn't accessible under scoped storage.
         */
        data class LocalFile(
            val path: String?,
            val uri: String,
            val displayName: String,
            val durationMs: Long = 0L
        ) : Source

        data class Link(val url: String) : Source
    }
}
