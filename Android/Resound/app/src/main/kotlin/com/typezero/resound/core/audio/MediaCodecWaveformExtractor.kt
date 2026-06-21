/*
 * file:    MediaCodecWaveformExtractor.kt
 * author:  Mike Redd (typezero)
 * version: 0.2.1
 * desc:    Real waveform extraction. Decodes the source to PCM with
 *          MediaExtractor + MediaCodec and folds the samples into
 *          targetBuckets (min, max) pairs as it streams — so memory stays flat
 *          regardless of file length. Falls back to the synthesised shape if
 *          decoding fails for any reason, so the editor is always usable.
 *
 *          Notes / limits (fine for v0.2.1, refine later):
 *            - Full-file decode; a 4-min track takes ~a second or two.
 *            - Handles 16-bit and float PCM output; collapses channels by
 *              taking the peak across channels per frame.
 */
package com.typezero.resound.core.audio

import android.content.Context
import android.media.AudioFormat
import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.nio.ByteBuffer
import java.nio.ByteOrder

class MediaCodecWaveformExtractor(
    private val context: Context,
    private val fallback: WaveformExtractor = FakeWaveformExtractor(),
) : WaveformExtractor {

    override suspend fun extract(file: AudioFile, targetBuckets: Int): Waveform =
        withContext(Dispatchers.Default) {
            runCatching { decode(file, targetBuckets.coerceAtLeast(1)) }
                .getOrElse { fallback.extract(file, targetBuckets) }
        }

    private fun decode(file: AudioFile, buckets: Int): Waveform {
        val extractor = MediaExtractor()
        val pfd = context.contentResolver.openFileDescriptor(file.uri, "r")
            ?: throw IllegalStateException("Cannot open ${file.uri}")
        var codec: MediaCodec? = null
        try {
            extractor.setDataSource(pfd.fileDescriptor)

            var trackIndex = -1
            var inFormat: MediaFormat? = null
            for (i in 0 until extractor.trackCount) {
                val f = extractor.getTrackFormat(i)
                if (f.getString(MediaFormat.KEY_MIME)?.startsWith("audio/") == true) {
                    trackIndex = i; inFormat = f; break
                }
            }
            val format = inFormat ?: throw IllegalStateException("No audio track")
            extractor.selectTrack(trackIndex)

            val sampleRate = format.intOr(MediaFormat.KEY_SAMPLE_RATE, file.sampleRate)
            var channels = format.intOr(MediaFormat.KEY_CHANNEL_COUNT, file.channels.coerceAtLeast(1))
            var pcmEncoding = format.intOr(MediaFormat.KEY_PCM_ENCODING, AudioFormat.ENCODING_PCM_16BIT)

            val mime = format.getString(MediaFormat.KEY_MIME)!!
            codec = MediaCodec.createDecoderByType(mime).apply {
                configure(format, null, null, 0)
                start()
            }

            // Estimate total frames so we can map frame index -> bucket as we go.
            val approxFrames = (file.durationMs / 1000.0 * sampleRate).toLong().coerceAtLeast(1)
            val framesPerBucket = (approxFrames / buckets).coerceAtLeast(1)

            val mins = FloatArray(buckets) { Float.POSITIVE_INFINITY }
            val maxs = FloatArray(buckets) { Float.NEGATIVE_INFINITY }
            var frame = 0L

            val info = MediaCodec.BufferInfo()
            var inputDone = false
            var outputDone = false

            fun bucketOf(f: Long) = (f / framesPerBucket).toInt().coerceIn(0, buckets - 1)

            while (!outputDone) {
                if (!inputDone) {
                    val inIdx = codec.dequeueInputBuffer(10_000)
                    if (inIdx >= 0) {
                        val inBuf = codec.getInputBuffer(inIdx)!!
                        val size = extractor.readSampleData(inBuf, 0)
                        if (size < 0) {
                            codec.queueInputBuffer(inIdx, 0, 0, 0, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
                            inputDone = true
                        } else {
                            codec.queueInputBuffer(inIdx, 0, size, extractor.sampleTime, 0)
                            extractor.advance()
                        }
                    }
                }

                val outIdx = codec.dequeueOutputBuffer(info, 10_000)
                when {
                    outIdx == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> {
                        val of = codec.outputFormat
                        channels = of.intOr(MediaFormat.KEY_CHANNEL_COUNT, channels)
                        pcmEncoding = of.intOr(MediaFormat.KEY_PCM_ENCODING, pcmEncoding)
                    }
                    outIdx >= 0 -> {
                        val outBuf = codec.getOutputBuffer(outIdx)
                        if (outBuf != null && info.size > 0) {
                            outBuf.position(info.offset)
                            outBuf.limit(info.offset + info.size)
                            frame = foldBuffer(outBuf, channels, pcmEncoding, frame, framesPerBucket, buckets, mins, maxs, ::bucketOf)
                        }
                        codec.releaseOutputBuffer(outIdx, false)
                        if (info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) outputDone = true
                    }
                }
            }

            // Empty buckets (silence / gaps) -> flat zero.
            for (b in 0 until buckets) {
                if (mins[b] > maxs[b]) { mins[b] = 0f; maxs[b] = 0f }
            }
            return Waveform(mins, maxs, file.durationMs)
        } finally {
            try { codec?.stop() } catch (_: Throwable) {}
            try { codec?.release() } catch (_: Throwable) {}
            extractor.release()
            pfd.close()
        }
    }

    /** Fold one PCM output buffer into the bucket arrays. Returns the new frame counter. */
    private fun foldBuffer(
        buf: ByteBuffer,
        channels: Int,
        pcmEncoding: Int,
        startFrame: Long,
        framesPerBucket: Long,
        buckets: Int,
        mins: FloatArray,
        maxs: FloatArray,
        bucketOf: (Long) -> Int,
    ): Long {
        var frame = startFrame
        val ch = channels.coerceAtLeast(1)
        buf.order(ByteOrder.LITTLE_ENDIAN)

        if (pcmEncoding == AudioFormat.ENCODING_PCM_FLOAT) {
            val fb = buf.asFloatBuffer()
            val n = fb.remaining()
            var i = 0
            while (i + ch <= n) {
                var peak = 0f
                for (c in 0 until ch) {
                    val v = fb.get(i + c)
                    if (kotlin.math.abs(v) > kotlin.math.abs(peak)) peak = v
                }
                val b = bucketOf(frame)
                if (peak < mins[b]) mins[b] = peak
                if (peak > maxs[b]) maxs[b] = peak
                frame++
                i += ch
            }
        } else {
            // Default / 16-bit PCM.
            val sb = buf.asShortBuffer()
            val n = sb.remaining()
            var i = 0
            while (i + ch <= n) {
                var peak = 0f
                for (c in 0 until ch) {
                    val v = sb.get(i + c) / 32768f
                    if (kotlin.math.abs(v) > kotlin.math.abs(peak)) peak = v
                }
                val b = bucketOf(frame)
                if (peak < mins[b]) mins[b] = peak
                if (peak > maxs[b]) maxs[b] = peak
                frame++
                i += ch
            }
        }
        return frame
    }

    private fun MediaFormat.intOr(key: String, default: Int): Int =
        if (containsKey(key)) getInteger(key) else default
}
