package com.typezero.siphon.engine

import com.typezero.siphon.data.model.*
import org.junit.Assert.*
import org.junit.Test

/** CommandFactory now drives the yt-dlp (link) path only. */
class CommandFactoryTest {

    private fun linkReq(
        format: AudioFormat = AudioFormat.MP3,
        quality: AudioQuality = AudioQuality.K320,
        tags: Tags = Tags(),
        name: String = ""
    ) = ExtractRequest(ExtractRequest.Source.Link("https://x/y"), format, quality, tags, name)

    @Test fun mp3_includes_format_and_bitrate() {
        val args = CommandFactory.build(linkReq(), "/out", "song")
        assertTrue(args.containsInOrder("--audio-format", "mp3"))
        assertTrue(args.containsInOrder("--audio-quality", "320K"))
        assertTrue(args.contains("--extract-audio"))
    }

    @Test fun copy_uses_best_and_no_bitrate() {
        val args = CommandFactory.build(linkReq(format = AudioFormat.COPY), "/out", "a")
        assertTrue(args.containsInOrder("--audio-format", "best"))
        assertFalse(args.contains("--audio-quality"))
    }

    @Test fun thumbnail_embeds_for_links() {
        val args = CommandFactory.build(linkReq(tags = Tags(embedThumbnail = true)), "/out", "a")
        assertTrue(args.contains("--embed-thumbnail"))
    }

    @Test fun explicit_tags_become_quoted_metadata_args() {
        val pp = CommandFactory.buildMetadataPpArg(Tags(title = "My Song", artist = "O'Hara"))!!
        assertTrue(pp.startsWith("ExtractAudio:"))
        assertTrue(pp.contains("-metadata title='My Song'"))
        assertTrue(pp.contains("artist='O'\\''Hara'"))   // single quote escaped
    }

    @Test fun no_explicit_tags_yields_null_pp() {
        assertNull(CommandFactory.buildMetadataPpArg(Tags()))
    }

    private fun List<String>.containsInOrder(a: String, b: String): Boolean {
        val i = indexOf(a); return i >= 0 && i + 1 < size && this[i + 1] == b
    }
}
