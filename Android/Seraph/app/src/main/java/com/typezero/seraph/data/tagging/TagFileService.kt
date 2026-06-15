package com.typezero.seraph.data.tagging

import com.typezero.seraph.data.model.AudioFile
import com.typezero.seraph.data.model.Tags
import com.typezero.seraph.storage.SourceManager
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/**
 * Reads and writes tags through whichever [StorageSource] is active: pull the
 * file to cache, run the [Tagger] on it, and (on write) push it back home.
 */
class TagFileService(
    private val sources: SourceManager,
    private val tagger: Tagger,
) {
    suspend fun read(file: AudioFile): Tags = withContext(Dispatchers.IO) {
        val source = sources.forFile(file)
        val cache = source.readToCache(file)
        try {
            tagger.read(cache)
        } finally {
            cache.delete()
        }
    }

    suspend fun write(file: AudioFile, tags: Tags): Unit = withContext(Dispatchers.IO) {
        val source = sources.forFile(file)
        val cache = source.readToCache(file)
        try {
            tagger.write(cache, tags)
            source.writeBack(file, cache)
        } finally {
            cache.delete()
        }
    }
}
