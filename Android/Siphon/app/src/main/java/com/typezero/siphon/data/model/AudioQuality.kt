package com.typezero.siphon.data.model

/**
 * Bitrate / quality presets for lossy formats. yt-dlp's --audio-quality accepts
 * a VBR index (0 best .. 10 worst) or an explicit bitrate like "320K".
 */
enum class AudioQuality(val label: String, val ytdlpValue: String) {
    BEST("Best (VBR)", "0"),
    K320("320 kbps", "320K"),
    K256("256 kbps", "256K"),
    K192("192 kbps", "192K"),
    K128("128 kbps", "128K"),
    K96("96 kbps", "96K");

    companion object { val lossyDefault = K320 }
}
