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
    private val extension = Regex("""\.[A-Za-z0-9]{1,5}$""")
    private val nonAlnum = Regex("""[^a-z0-9]+""")

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

    /**
     * Match files to tracks. Tries, in order: leading filename number == track
     * position; title similarity (filenames usually contain the song title);
     * then plain sorted order as a last resort.
     */
    private fun matchFilesToTracks(
        files: List<AudioFile>,
        release: ReleaseDetail,
    ): List<Pair<AudioFile, ReleaseTrack>> {
        val sorted = files.sortedBy { it.displayName.lowercase() }
        if (sorted.isEmpty() || release.tracks.isEmpty()) return emptyList()
        val half = (minOf(sorted.size, release.tracks.size) + 1) / 2

        val byNum = LinkedHashMap<Int, AudioFile>()
        for (f in sorted) {
            val n = leadingNum.find(f.displayName)?.groupValues?.getOrNull(1)?.toIntOrNull()
            if (n != null) byNum.putIfAbsent(n, f)
        }
        val numbered = release.tracks.mapNotNull { t -> byNum[t.position]?.let { it to t } }
        if (numbered.size >= half) return numbered

        val byTitle = matchByTitle(sorted, release.tracks)
        if (byTitle.size >= half) return byTitle

        return when {
            byTitle.size >= numbered.size && byTitle.isNotEmpty() -> byTitle
            numbered.isNotEmpty() -> numbered
            else -> sorted.zip(release.tracks)
        }
    }

    /** Greedily pair each track with the unused file whose name best covers its title. */
    private fun matchByTitle(
        files: List<AudioFile>,
        tracks: List<ReleaseTrack>,
    ): List<Pair<AudioFile, ReleaseTrack>> {
        val fileTokens = files.associateWith { tokenize(it.displayName) }
        val used = HashSet<String>()
        val out = ArrayList<Pair<AudioFile, ReleaseTrack>>()
        for (track in tracks) {
            val tt = tokenize(track.title)
            if (tt.isEmpty()) continue
            var best: AudioFile? = null
            var bestScore = 0.0
            for (f in files) {
                if (f.id in used) continue
                val ft = fileTokens[f] ?: continue
                val score = tt.count { it in ft }.toDouble() / tt.size
                if (score > bestScore) {
                    bestScore = score
                    best = f
                }
            }
            val b = best
            if (b != null && bestScore >= 0.6) {
                used += b.id
                out += b to track
            }
        }
        return out
    }

    private fun tokenize(name: String): Set<String> {
        var s = name.lowercase()
        s = extension.replace(s, "")
        s = leadingNum.replace(s, "")
        s = nonAlnum.replace(s, " ")
        return s.split(' ').filter { it.length >= 2 }.toSet()
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
