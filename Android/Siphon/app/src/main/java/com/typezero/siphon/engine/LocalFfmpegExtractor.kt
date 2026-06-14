package com.typezero.siphon.engine

import android.content.Context
import android.media.MediaExtractor
import android.media.MediaFormat
import android.net.Uri
import android.util.Log
import com.typezero.siphon.data.model.AudioFormat
import com.typezero.siphon.data.model.ExtractRequest
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.BufferedReader
import java.io.File
import java.io.InputStreamReader
import java.util.Collections

/**
 * Extracts audio from a LOCAL file by invoking the bundled FFmpeg binary directly
 * (youtubedl-android ships it at <nativeLibDir>/libffmpeg.so with its shared libs
 * under noBackupFilesDir/youtubedl-android/packages/.../usr/lib).
 *
 * yt-dlp is only for URLs — handing it a local path makes its generic extractor
 * fail with "[generic] ... is not a valid URL", which is the bug this replaces.
 */
class LocalFfmpegExtractor(
    private val appContext: Context,
    private val engine: YtdlpEngine
) {
    private val processes = Collections.synchronizedMap(HashMap<String, Process>())

    private val ffmpegBinary: String
        get() = File(appContext.applicationInfo.nativeLibraryDir, "libffmpeg.so").absolutePath

    private val libraryPath: String
        get() {
            val packages = File(File(appContext.noBackupFilesDir, "youtubedl-android"), "packages")
            return listOf("python", "ffmpeg", "aria2c")
                .joinToString(":") { File(packages, "$it/usr/lib").absolutePath }
        }

    suspend fun extract(
        request: ExtractRequest,
        source: ExtractRequest.Source.LocalFile,
        outputResolver: OutputResolver,
        processId: String,
        onProgress: (Float, String) -> Unit
    ): YtdlpEngine.Result = withContext(Dispatchers.IO) {
        // Ensures python+ffmpeg packages are unzipped (libs the binary needs).
        engine.ensureInit()

        val (inputPath, tempFile) = resolveInput(source)
        try {
            val mime = if (request.format == AudioFormat.COPY) probeAudioMime(inputPath) else null
            val ext = FfmpegArgs.outputExtension(request.format, mime)
            val base = outputResolver.sanitize(
                request.outputName, File(source.displayName).nameWithoutExtension
            )
            val outFile = File(outputResolver.outputDir(), "$base.$ext")

            val args = FfmpegArgs.build(
                request.format, request.quality, inputPath, outFile.absolutePath, request.tags
            )
            runFfmpeg(args, processId, source.durationMs, onProgress)

            if (!outFile.exists() || outFile.length() == 0L)
                throw YtdlpEngine.EngineException("FFmpeg produced no output.")
            YtdlpEngine.Result(outFile, ext)
        } finally {
            tempFile?.delete()
            processes.remove(processId)
        }
    }

    fun cancel(processId: String): Boolean =
        processes[processId]?.let { runCatching { it.destroy() }.isSuccess } ?: false

    /** Use the raw path when readable, else copy the content uri into cache. */
    private fun resolveInput(source: ExtractRequest.Source.LocalFile): Pair<String, File?> {
        val direct = source.path?.let(::File)
        if (direct != null && direct.canRead()) return direct.absolutePath to null

        val temp = File.createTempFile("siphon_in_", ".tmp", appContext.cacheDir)
        appContext.contentResolver.openInputStream(Uri.parse(source.uri)).use { input ->
            requireNotNull(input) { "Could not open the selected video." }
            temp.outputStream().use { input.copyTo(it) }
        }
        return temp.absolutePath to temp
    }

    private fun probeAudioMime(path: String): String? = runCatching {
        val extractor = MediaExtractor()
        try {
            extractor.setDataSource(path)
            for (i in 0 until extractor.trackCount) {
                val mime = extractor.getTrackFormat(i).getString(MediaFormat.KEY_MIME)
                if (mime != null && mime.startsWith("audio/")) return mime
            }
            null
        } finally { extractor.release() }
    }.getOrNull()

    private fun runFfmpeg(
        args: List<String>,
        processId: String,
        durationMs: Long,
        onProgress: (Float, String) -> Unit
    ) {
        val pb = ProcessBuilder(listOf(ffmpegBinary) + args).redirectErrorStream(true)
        pb.environment().apply {
            put("LD_LIBRARY_PATH", libraryPath)
            put("TMPDIR", appContext.cacheDir.absolutePath)
        }
        Log.i(TAG, "ffmpeg ${args.joinToString(" ")}")

        val process = pb.start()
        processes[processId] = process

        val tail = ArrayDeque<String>()
        BufferedReader(InputStreamReader(process.errorStream)).use { reader ->
            reader.forEachLine { line ->
                if (tail.size >= 12) tail.removeFirst()
                tail.addLast(line)
                parseProgress(line, durationMs)?.let { onProgress(it, line) }
            }
        }
        val exit = process.waitFor()
        if (exit != 0) {
            val msg = tail.lastOrNull { it.contains("Error", true) || it.contains("Invalid", true) }
                ?: tail.lastOrNull().orEmpty()
            throw YtdlpEngine.EngineException(
                if (msg.isBlank()) "FFmpeg failed (exit $exit)." else msg.trim()
            )
        }
    }

    private val timeRegex = Regex("""time=(\d+):(\d+):(\d+(?:\.\d+)?)""")
    private fun parseProgress(line: String, durationMs: Long): Float? {
        if (durationMs <= 0) return null
        val m = timeRegex.find(line) ?: return null
        val (h, min, s) = m.destructured
        val sec = h.toLong() * 3600 + min.toLong() * 60 + s.toDouble()
        return (sec * 1000.0 / durationMs).coerceIn(0.0, 1.0).toFloat()
    }

    companion object { private const val TAG = "SiphonLocal" }
}
