package com.typezero.siphon.engine

import android.content.ContentValues
import android.content.Context
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import java.io.File

/** Owns Siphon's output directory and exports finished files to the Music library. */
class OutputResolver(private val context: Context) {

    /** App-private but user-visible dir: /Android/data/<pkg>/files/Siphon */
    fun outputDir(): File {
        val dir = File(context.getExternalFilesDir(Environment.DIRECTORY_MUSIC), "Siphon")
        if (!dir.exists()) dir.mkdirs()
        return dir
    }

    /** Sanitise a user-entered name into a safe file stem. */
    fun sanitize(name: String, fallback: String): String {
        val cleaned = name.trim().replace(Regex("[\\\\/:*?\"<>|]"), "_").trim('.', ' ')
        return cleaned.ifBlank { fallback }.take(120)
    }

    /** Find the produced file given the stem yt-dlp was told to use. */
    fun locateOutput(baseName: String): File? =
        outputDir().listFiles()
            ?.filter { it.isFile && it.nameWithoutExtension == baseName }
            ?.maxByOrNull { it.lastModified() }

    /**
     * Copy a finished file into the shared Music collection so it shows up in
     * music players. Returns the display location string, or null on failure.
     */
    fun exportToMusic(file: File, mime: String): String? = runCatching {
        val resolver = context.contentResolver
        val values = ContentValues().apply {
            put(MediaStore.Audio.Media.DISPLAY_NAME, file.name)
            put(MediaStore.Audio.Media.MIME_TYPE, mime)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                put(MediaStore.Audio.Media.RELATIVE_PATH, "${Environment.DIRECTORY_MUSIC}/Siphon")
                put(MediaStore.Audio.Media.IS_PENDING, 1)
            }
        }
        val collection = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q)
            MediaStore.Audio.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
        else MediaStore.Audio.Media.EXTERNAL_CONTENT_URI

        val uri = resolver.insert(collection, values) ?: return null
        resolver.openOutputStream(uri)?.use { out -> file.inputStream().use { it.copyTo(out) } }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            values.clear(); values.put(MediaStore.Audio.Media.IS_PENDING, 0)
            resolver.update(uri, values, null, null)
        }
        "Music/Siphon/${file.name}"
    }.getOrNull()

    companion object {
        fun mimeFor(ext: String): String = when (ext.lowercase()) {
            "mp3" -> "audio/mpeg"
            "m4a", "aac" -> "audio/mp4"
            "opus" -> "audio/opus"
            "flac" -> "audio/flac"
            "wav" -> "audio/x-wav"
            "ogg" -> "audio/ogg"
            else -> "audio/*"
        }
    }
}
