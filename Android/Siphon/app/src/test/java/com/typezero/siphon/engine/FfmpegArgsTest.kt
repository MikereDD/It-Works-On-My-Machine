package com.typezero.siphon.engine

import com.typezero.siphon.data.model.AudioFormat
import com.typezero.siphon.data.model.AudioQuality
import com.typezero.siphon.data.model.Tags
import org.junit.Assert.*
import org.junit.Test

/** Local extraction args go straight to ffmpeg via ProcessBuilder (no shell). */
class FfmpegArgsTest {

    @Test fun mp3_uses_lame_and_cbr_lowercased() {
        val a = FfmpegArgs.build(AudioFormat.MP3, AudioQuality.K320, "/in.mp4", "/out.mp3", Tags())
        assertTrue(a.containsInOrder("-c:a", "libmp3lame"))
        assertTrue(a.containsInOrder("-b:a", "320k"))
        assertEquals("/out.mp3", a.last())
    }

    @Test fun mp3_best_uses_vbr_q0() {
        val a = FfmpegArgs.build(AudioFormat.MP3, AudioQuality.BEST, "/in.mp4", "/out.mp3", Tags())
        assertTrue(a.containsInOrder("-q:a", "0"))
        assertFalse(a.contains("-b:a"))
    }

    @Test fun copy_uses_stream_copy() {
        val a = FfmpegArgs.build(AudioFormat.COPY, AudioQuality.BEST, "/in.mkv", "/out.mka", Tags())
        assertTrue(a.containsInOrder("-c:a", "copy"))
    }

    @Test fun tags_are_separate_unquoted_tokens() {
        val a = FfmpegArgs.build(
            AudioFormat.M4A, AudioQuality.K256, "/in.mp4", "/out.m4a",
            Tags(title = "My Song", albumArtist = "Some One")
        )
        // value with a space is a single argv token, no quoting
        val ti = a.indexOf("title=My Song")
        assertTrue(ti > 0 && a[ti - 1] == "-metadata")
        assertTrue(a.contains("album_artist=Some One"))
    }

    @Test fun copy_extension_maps_from_source_mime() {
        assertEquals("m4a", FfmpegArgs.outputExtension(AudioFormat.COPY, "audio/mp4a-latm"))
        assertEquals("opus", FfmpegArgs.outputExtension(AudioFormat.COPY, "audio/opus"))
        assertEquals("mka", FfmpegArgs.outputExtension(AudioFormat.COPY, "audio/ac3"))
        assertEquals("mp3", FfmpegArgs.outputExtension(AudioFormat.MP3, null))
    }

    private fun List<String>.containsInOrder(a: String, b: String): Boolean {
        val i = indexOf(a); return i >= 0 && i + 1 < size && this[i + 1] == b
    }
}
