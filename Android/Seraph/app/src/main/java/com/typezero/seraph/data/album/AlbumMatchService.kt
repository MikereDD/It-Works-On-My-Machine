package com.typezero.seraph.data.album

import com.typezero.seraph.data.model.AudioFile
import com.typezero.seraph.data.model.ReleaseDetail
import com.typezero.seraph.data.model.ReleaseTrack
import com.typezero.seraph.data.model.Tags
import com.typezero.seraph.data.musicbrainz.MusicBrainzClient
import com.typezero.seraph.data.rename.FilenameTemplate
import com.typezero.seraph.data.rename.FolderGroup
import com.typezero.seraph.data.rename.RenameItem
import com.typezero.seraph.data.rename.RenamePlan
import com.typezero.seraph.data.rename.RenameService
import com.typezero.seraph.data.tagging.TagFileService
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/** A folder file paired with the release track it matched, plus the tags and new name to apply. */
data class AlbumPlanRow(
    val file: AudioFile,
    val position: Int,
    val title: String,
    val artist: String,
    val tags: Tags,
    val proposedName: String,
)

data class AlbumApplyResult(val tagged: Int, val renamed: Int, val failed: Int)

/**
 * Matches a folder's audio files to a MusicBrainz release's tracklist, then
 * applies the result: writes tags to every file and (optionally) renames them
 * from a template. Reuses [TagFileService] for writes and [RenameService] for
 * the safe two-pass rename, so this works the same on device and pCloud.
 */
class AlbumMatchService(
    private val mb: MusicBrainzClient,
    private val tagging: TagFileService,
    private val rename: RenameService,
) {
    // Leading track number in a filename: "01 - ", "(01) ", "1. ", "07_"…
    private val leadingNum = Regex("""^[\s(\[]*(\d{1,3})[)\].\s_-]""")

    fun plan(files: List<AudioFile>, release: ReleaseDetail, template: String): List<AlbumPlanRow> {
        val width = maxOf(2, release.total.toString().length)
        return matchFilesToTracks(files, release).map { (file, track) ->
            val values = mapOf(
                "track" to track.position.toString().padStart(width, '0'),
                "total" to release.total.toString().padStart(width, '0'),
                "title" to track.title,
                "artist" to track.artist,
                "album" to release.title,
                "albumartist" to release.artist,
                "year" to release.year,
                "disc" to "",
            )
            AlbumPlanRow(
                file = file,
                position = track.position,
                title = track.title,
                artist = track.artist,
                tags = Tags(
                    title = track.title,
                    artist = track.artist,
                    album = release.title,
                    albumArtist = release.artist,
                    trackNumber = track.position.toString(),
                    trackTotal = release.total.toString(),
                    year = release.year,
                ),
                proposedName = FilenameTemplate.render(template, values, file.extension),
            )
        }
    }

    /** Match by leading filename number when most files have one; otherwise by sorted order. */
    private fun matchFilesToTracks(
        files: List<AudioFile>,
        release: ReleaseDetail,
    ): List<Pair<AudioFile, ReleaseTrack>> {
        val sorted = files.sortedBy { it.displayName.lowercase() }
        val byNum = LinkedHashMap<Int, AudioFile>()
        for (f in sorted) {
            val n = leadingNum.find(f.displayName)?.groupValues?.get(1)?.toIntOrNull()
            if (n != null) byNum.putIfAbsent(n, f)
        }
        val coverage = release.tracks.count { byNum.containsKey(it.position) }
        val useNumbers = byNum.isNotEmpty() &&
            coverage >= (minOf(sorted.size, release.tracks.size) + 1) / 2
        return if (useNumbers) {
            release.tracks.mapNotNull { t -> byNum[t.position]?.let { it to t } }
        } else {
            sorted.zip(release.tracks)
        }
    }

    suspend fun apply(
        rows: List<AlbumPlanRow>,
        release: ReleaseDetail,
        folderName: String,
        doRename: Boolean,
        embedArt: Boolean,
    ): AlbumApplyResult = withContext(Dispatchers.IO) {
        val art = if (embedArt) runCatching { mb.frontCover(release.mbid) }.getOrNull() else null
        var tagged = 0
        var failed = 0
        for (row in rows) {
            val tags = if (art != null) row.tags.copy(artwork = art) else row.tags
            runCatching { tagging.write(row.file, tags) }
                .onSuccess { tagged++ }
                .onFailure { failed++ }
        }
        var renamed = 0
        if (doRename) {
            val items = rows.map { RenameItem(it.file, it.file.displayName, it.proposedName) }
            val result = rename.apply(RenamePlan(listOf(FolderGroup(folderName, items))))
            renamed = result.renamed
            failed += result.failed
        }
        AlbumApplyResult(tagged = tagged, renamed = renamed, failed = failed)
    }
}
