package com.typezero.siphon.data

import android.content.ContentUris
import android.content.Context
import android.provider.MediaStore
import com.typezero.siphon.data.model.VideoItem
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/** Queries MediaStore for on-device videos that feed the searchable picker. */
class MediaStoreVideoRepository(private val context: Context) {

    suspend fun loadVideos(): List<VideoItem> = withContext(Dispatchers.IO) {
        val collection = MediaStore.Video.Media.EXTERNAL_CONTENT_URI
        val projection = arrayOf(
            MediaStore.Video.Media._ID,
            MediaStore.Video.Media.DISPLAY_NAME,
            MediaStore.Video.Media.DATA,
            MediaStore.Video.Media.DURATION,
            MediaStore.Video.Media.SIZE,
            MediaStore.Video.Media.MIME_TYPE,
            MediaStore.Video.Media.DATE_ADDED
        )
        val sort = "${MediaStore.Video.Media.DATE_ADDED} DESC"
        val out = ArrayList<VideoItem>()

        context.contentResolver.query(collection, projection, null, null, sort)?.use { c ->
            val idCol = c.getColumnIndexOrThrow(MediaStore.Video.Media._ID)
            val nameCol = c.getColumnIndexOrThrow(MediaStore.Video.Media.DISPLAY_NAME)
            val dataCol = c.getColumnIndexOrThrow(MediaStore.Video.Media.DATA)
            val durCol = c.getColumnIndexOrThrow(MediaStore.Video.Media.DURATION)
            val sizeCol = c.getColumnIndexOrThrow(MediaStore.Video.Media.SIZE)
            val mimeCol = c.getColumnIndexOrThrow(MediaStore.Video.Media.MIME_TYPE)
            val addedCol = c.getColumnIndexOrThrow(MediaStore.Video.Media.DATE_ADDED)

            while (c.moveToNext()) {
                val id = c.getLong(idCol)
                val path = c.getString(dataCol)
                out += VideoItem(
                    id = id,
                    displayName = c.getString(nameCol) ?: "video_$id",
                    uri = ContentUris.withAppendedId(collection, id),
                    filePath = path,
                    durationMs = c.getLong(durCol),
                    sizeBytes = c.getLong(sizeCol),
                    mimeType = c.getString(mimeCol),
                    dateAddedSec = c.getLong(addedCol)
                )
            }
        }
        out
    }

    /** Case-insensitive substring search over display names. */
    fun filter(items: List<VideoItem>, query: String): List<VideoItem> {
        val q = query.trim()
        if (q.isEmpty()) return items
        return items.filter { it.displayName.contains(q, ignoreCase = true) }
    }
}
