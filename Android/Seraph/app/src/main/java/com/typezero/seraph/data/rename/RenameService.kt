package com.typezero.seraph.data.rename

import com.typezero.seraph.data.model.AudioFile
import com.typezero.seraph.data.tagging.TagFileService
import com.typezero.seraph.storage.SourceManager
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/** A file plus the resolved token values for it (tags read once, up front). */
data class RenameSource(
    val file: AudioFile,
    val parentId: String,
    val parentName: String,
    val values: Map<String, String>,
)

data class RenameItem(val file: AudioFile, val currentName: String, val proposedName: String) {
    val changed: Boolean get() = proposedName != currentName
}

data class FolderGroup(val name: String, val items: List<RenameItem>)

data class RenamePlan(val groups: List<FolderGroup>) {
    val changeCount: Int get() = groups.sumOf { g -> g.items.count { it.changed } }
}

data class RenameResult(val renamed: Int, val failed: Int, val failures: List<String>)

/**
 * Builds and applies a per-directory rename plan against whichever storage source
 * each file belongs to. Token values come from the tags (MusicBrainz data once
 * looked up, or the user's manual edits); the track number falls back to
 * sequential folder order, the total to the folder's file count.
 *
 * Tags are read once in [gather]; [render] is pure so editing the template
 * re-previews instantly. Applying uses a two-pass rename so a target name can
 * never clobber a sibling — works the same whether the backend rename is a SAF
 * DocumentsContract call or pCloud's server-side renamefile.
 */
class RenameService(
    private val sources: SourceManager,
    private val tagging: TagFileService,
) {

    suspend fun gather(files: List<AudioFile>): List<RenameSource> = withContext(Dispatchers.IO) {
        files.groupBy { it.parentId }.flatMap { (parentId, groupFiles) ->
            val ordered = groupFiles.sortedBy { it.displayName.lowercase() }
            val folderTotal = ordered.size
            ordered.mapIndexed { index, file ->
                val tags = runCatching { tagging.read(file) }.getOrNull()
                val trackNum = tags?.trackNumber?.trim()?.toIntOrNull() ?: (index + 1)
                val totalNum = tags?.trackTotal?.trim()?.toIntOrNull() ?: folderTotal
                val width = maxOf(2, totalNum.toString().length)
                RenameSource(
                    file = file,
                    parentId = parentId,
                    parentName = file.parentName.ifBlank { "(folder)" },
                    values = mapOf(
                        "track" to trackNum.toString().padStart(width, '0'),
                        "total" to totalNum.toString().padStart(width, '0'),
                        "title" to (tags?.title ?: ""),
                        "artist" to (tags?.artist ?: ""),
                        "album" to (tags?.album ?: ""),
                        "albumartist" to (tags?.albumArtist ?: ""),
                        "year" to (tags?.year ?: ""),
                        "disc" to (tags?.discNumber ?: ""),
                    ),
                )
            }
        }
    }

    fun render(srcs: List<RenameSource>, template: String): RenamePlan {
        val groups = srcs.groupBy { it.parentId }.map { (_, list) ->
            val items = list.map { src ->
                RenameItem(src.file, src.file.displayName, FilenameTemplate.render(template, src.values, src.file.extension))
            }
            FolderGroup(name = list.first().parentName, items = deduplicate(items))
        }
        return RenamePlan(groups.sortedBy { it.name.lowercase() })
    }

    private fun deduplicate(items: List<RenameItem>): List<RenameItem> {
        val seen = HashMap<String, Int>()
        return items.map { item ->
            val key = item.proposedName.lowercase()
            val count = seen.getOrDefault(key, 0)
            seen[key] = count + 1
            if (count == 0) item else item.copy(proposedName = suffix(item.proposedName, count + 1))
        }
    }

    private fun suffix(name: String, n: Int): String {
        val dot = name.lastIndexOf('.')
        return if (dot <= 0) "$name ($n)" else "${name.substring(0, dot)} ($n)${name.substring(dot)}"
    }

    suspend fun apply(plan: RenamePlan): RenameResult = withContext(Dispatchers.IO) {
        var renamed = 0
        var failed = 0
        val failures = ArrayList<String>()

        for (group in plan.groups) {
            val changes = group.items.filter { it.changed }
            if (changes.isEmpty()) continue

            // Phase 1: everything to a unique temp name.
            val staged = ArrayList<Pair<AudioFile, String>>() // temp ref -> final name
            changes.forEachIndexed { i, item ->
                val source = sources.forFile(item.file)
                val ext = item.file.extension
                val temp = "att_tmp_${i}_${System.nanoTime()}" + if (ext.isBlank()) "" else ".$ext"
                val ref = runCatching { source.rename(item.file, temp) }.getOrNull()
                if (ref == null) { failed++; failures += item.currentName } else staged += ref to item.proposedName
            }
            // Phase 2: temp -> final.
            for ((ref, finalName) in staged) {
                val ok = runCatching { sources.forFile(ref).rename(ref, finalName) }.isSuccess
                if (ok) renamed++ else { failed++; failures += finalName }
            }
        }
        RenameResult(renamed, failed, failures)
    }
}
