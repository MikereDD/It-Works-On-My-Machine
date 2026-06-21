/*
 * file:    AppContainer.kt
 * author:  Mike Redd (typezero)
 * version: 0.3.1
 * desc:    Manual DI container (no Hilt/Koin per repo convention). Holds the
 *          shared singletons feature screens pull from.
 */
package com.typezero.resound.di

import android.content.Context
import com.typezero.resound.core.audio.MediaCodecWaveformExtractor
import com.typezero.resound.core.audio.WaveformExtractor
import com.typezero.resound.core.ffmpeg.FFmpegKitRunner
import com.typezero.resound.core.ffmpeg.FFmpegRunner
import com.typezero.resound.feature.record.AndroidRecorder
import com.typezero.resound.feature.record.Recorder

class AppContainer(private val appContext: Context) {
    // Real engine — the ffmpeg-kit AAR now resolves from Maven Central.
    val ffmpeg: FFmpegRunner by lazy { FFmpegKitRunner() }

    // Real MediaCodec PCM decode; falls back to the synthesised shape on error.
    val waveformExtractor: WaveformExtractor by lazy {
        MediaCodecWaveformExtractor(appContext)
    }

    val recorder: Recorder by lazy { AndroidRecorder(appContext) }
}
