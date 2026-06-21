/*
 * file:    Outputs.kt
 * author:  Mike Redd (typezero)
 * version: 0.3.2
 * desc:    Where edited files land. FFmpeg writes to a temp file in cache, then
 *          we publish it into the shared Music/Resound library so it's
 *          browsable in any file manager and survives uninstall.
 *            - API 29+: MediaStore insert with RELATIVE_PATH (no permission).
 *            - API 26-28: direct write to public Music/Resound (needs
 *              WRITE_EXTERNAL_STORAGE).
 */
package com.typezero.resound.core.io

import android.content.ContentValues
import android.content.Context
import android.media.MediaScannerConnection
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import java.io.File

object Outputs {
    const val SUBDIR = "Resound"

    data class Published(val uri: Uri, val displayPath: String)

    fun mimeFor(ext: String): String = when (ext.lowercase()) {
        "mp3" -> "audio/mpeg"
        "m4a" -> "audio/mp4"
        "aac" -> "audio/aac"
        "wav" -> "audio/x-wav"
        "flac" -> "audio/flac"
        "ogg" -> "audio/ogg"
        else -> "audio/*"
    }

    /** Temp file in cache for FFmpeg to write to before publishing. */
    fun newTempFile(context: Context, baseName: String, ext: String): File {
        val dir = File(context.cacheDir, "out").apply { mkdirs() }
        return File(dir, "${baseName}_${System.currentTimeMillis()}.$ext")
    }

    /**
     * Move [temp] into the shared Music/Resound library. Returns a user-facing
     * path like "Music/Resound/trim_….mp3". Deletes [temp] on success.
     */
    fun publishToMusic(context: Context, temp: File, displayName: String, ext: String): Published {
        val mime = mimeFor(ext)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val resolver = context.contentResolver
            val collection = MediaStore.Audio.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
            val values = ContentValues().apply {
                put(MediaStore.Audio.Media.DISPLAY_NAME, displayName)
                put(MediaStore.Audio.Media.MIME_TYPE, mime)
                put(MediaStore.Audio.Media.RELATIVE_PATH, "${Environment.DIRECTORY_MUSIC}/$SUBDIR")
                put(MediaStore.Audio.Media.IS_PENDING, 1)
            }
            val uri = resolver.insert(collection, values)
                ?: throw IllegalStateException("MediaStore insert failed")
            resolver.openOutputStream(uri).use { out ->
                requireNotNull(out) { "Could not open output stream" }
                temp.inputStream().use { it.copyTo(out) }
            }
            values.clear()
            values.put(MediaStore.Audio.Media.IS_PENDING, 0)
            resolver.update(uri, values, null, null)
            temp.delete()
            return Published(uri, "Music/$SUBDIR/$displayName")
        } else {
            @Suppress("DEPRECATION")
            val dir = File(Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_MUSIC), SUBDIR)
            dir.mkdirs()
            val dest = File(dir, displayName)
            temp.copyTo(dest, overwrite = true)
            temp.delete()
            MediaScannerConnection.scanFile(context, arrayOf(dest.absolutePath), arrayOf(mime), null)
            return Published(Uri.fromFile(dest), "Music/$SUBDIR/$displayName")
        }
    }
}
