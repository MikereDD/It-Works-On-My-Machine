package com.typezero.siphon.engine

import android.content.Context
import android.util.Log
import com.typezero.siphon.data.model.ExtractRequest
import com.yausername.ffmpeg.FFmpeg
import com.yausername.youtubedl_android.YoutubeDL
import com.yausername.youtubedl_android.YoutubeDLRequest
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.File

/**
 * Thin wrapper around youtubedl-android. One engine extracts audio from local
 * files and links alike. Heavy work runs off the main thread.
 */
class YtdlpEngine(private val appContext: Context) {

    @Volatile private var ready = false

    /** Must be called once before any extraction. Safe to call repeatedly. */
    suspend fun ensureInit() = withContext(Dispatchers.IO) {
        if (ready) return@withContext
        try {
            YoutubeDL.getInstance().init(appContext)
            FFmpeg.getInstance().init(appContext)
            ready = true
        } catch (e: Exception) {
            Log.e(TAG, "init failed", e)
            throw EngineException("Failed to initialise extractor: ${e.message}", e)
        }
    }

    /** Pull the latest yt-dlp binary (optional; call from a settings action). */
    suspend fun updateBinary() = withContext(Dispatchers.IO) {
        ensureInit()
        runCatching {
            YoutubeDL.getInstance().updateYoutubeDL(appContext, YoutubeDL.UpdateChannel.STABLE)
        }
    }

    data class Result(val outputFile: File, val extension: String)

    /**
     * Runs one extraction. [onProgress] receives 0..1 (or -1 when indeterminate)
     * plus the latest output line. [processId] lets the caller cancel.
     */
    suspend fun extract(
        request: ExtractRequest,
        outputResolver: OutputResolver,
        processId: String,
        onProgress: (Float, String) -> Unit
    ): Result = withContext(Dispatchers.IO) {
        ensureInit()

        val dir = outputResolver.outputDir()
        val fallback = when (val s = request.source) {
            is ExtractRequest.Source.LocalFile -> File(s.displayName).nameWithoutExtension
            is ExtractRequest.Source.Link -> "audio_${System.currentTimeMillis()}"
        }
        val base = outputResolver.sanitize(request.outputName, fallback)

        val args = CommandFactory.build(request, dir.absolutePath, base)
        val token = CommandFactory.sourceToken(request)
        val ytRequest = YoutubeDLRequest(token).addCommands(args)

        Log.i(TAG, "yt-dlp ${(args + token).joinToString(" ")}")

        try {
            YoutubeDL.getInstance().execute(ytRequest, processId) { progress, _, line ->
                onProgress(if (progress < 0) -1f else progress / 100f, line)
            }
        } catch (e: Exception) {
            throw EngineException(friendly(e.message), e)
        }

        val produced = outputResolver.locateOutput(base)
            ?: throw EngineException("Extraction finished but no output file was found.")
        Result(produced, produced.extension)
    }

    fun cancel(processId: String): Boolean =
        runCatching { YoutubeDL.getInstance().destroyProcessById(processId) }.getOrDefault(false)

    private fun friendly(raw: String?): String {
        val msg = raw ?: "Unknown error"
        return when {
            msg.contains("Unsupported URL", true) -> "That link isn't supported."
            msg.contains("Video unavailable", true) -> "The source is unavailable or private."
            msg.contains("No such file", true) -> "The selected file could not be read."
            msg.contains("Requested format", true) -> "No matching audio stream for that format."
            else -> msg.lineSequence().lastOrNull { it.isNotBlank() } ?: msg
        }
    }

    class EngineException(message: String, cause: Throwable? = null) : Exception(message, cause)

    companion object { private const val TAG = "SiphonEngine" }
}
