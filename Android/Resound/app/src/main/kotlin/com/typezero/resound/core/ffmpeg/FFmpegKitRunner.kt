/*
 * file:    FFmpegKitRunner.kt
 * author:  Mike Redd (typezero)
 * version: 0.2.0
 * desc:    Real FFmpegRunner backed by the ffmpeg-kit wrapper API. ffmpeg-kit
 *          itself is retired, but the wrapper API is stable — the AAR is just
 *          sourced from app/libs/ instead of Maven (see README). This file
 *          only compiles once that AAR is present on the classpath.
 *
 *          Maps ffmpeg-kit's async callback model onto a single suspending
 *          call: completion -> FFmpegResult, statistics -> FFmpegProgress.
 */
package com.typezero.resound.core.ffmpeg

import com.arthenica.ffmpegkit.FFmpegKit
import com.arthenica.ffmpegkit.ReturnCode
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlin.coroutines.resume

class FFmpegKitRunner : FFmpegRunner {

    override suspend fun run(
        args: List<String>,
        totalMs: Long,
        progress: FFmpegProgress?,
    ): FFmpegResult = suspendCancellableCoroutine { cont ->
        val session = FFmpegKit.executeWithArgumentsAsync(
            args.toTypedArray(),
            { completed ->
                val rc = completed.returnCode
                val result = FFmpegResult(
                    returnCode = if (rc != null) rc.value else -1,
                    logTail = completed.allLogsAsString?.takeLast(4000).orEmpty(),
                )
                if (cont.isActive) cont.resume(result)
            },
            { /* log callback — wire to a logger if needed */ },
            { stats ->
                if (progress != null) {
                    val outMs = stats.time.toLong() // ms processed so far
                    val ratio = if (totalMs > 0) (outMs.toFloat() / totalMs).coerceIn(0f, 1f) else null
                    progress.onProgress(ratio, outMs)
                }
            },
        )

        // If the coroutine is cancelled, cancel the underlying FFmpeg session.
        cont.invokeOnCancellation {
            FFmpegKit.cancel(session.sessionId)
        }
    }

    @Suppress("unused")
    private fun ReturnCode?.ok(): Boolean = ReturnCode.isSuccess(this)
}
