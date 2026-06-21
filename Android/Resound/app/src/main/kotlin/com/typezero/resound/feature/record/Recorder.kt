/*
 * file:    Recorder.kt
 * author:  Mike Redd (typezero)
 * version: 0.4.0
 * desc:    Voice recorder. AndroidRecorder wraps MediaRecorder for one-tap
 *          capture to an AAC/m4a file. The recorded file is loaded straight
 *          back into the editor so it can be trimmed, set as a ringtone, etc.
 */
package com.typezero.resound.feature.record

import android.content.Context
import android.media.MediaRecorder
import android.os.Build
import java.io.File

interface Recorder {
    fun start(outputPath: String)
    fun stop(): String?   // returns the recorded file path, or null on failure
    val isRecording: Boolean
}

class AndroidRecorder(private val context: Context) : Recorder {

    private var recorder: MediaRecorder? = null
    private var outputFile: File? = null

    override var isRecording: Boolean = false
        private set

    override fun start(outputPath: String) {
        val file = File(outputPath)
        @Suppress("DEPRECATION")
        val r = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            MediaRecorder(context)
        } else {
            MediaRecorder()
        }
        r.setAudioSource(MediaRecorder.AudioSource.MIC)
        r.setOutputFormat(MediaRecorder.OutputFormat.MPEG_4)
        r.setAudioEncoder(MediaRecorder.AudioEncoder.AAC)
        r.setAudioEncodingBitRate(128_000)
        r.setAudioSamplingRate(44_100)
        r.setOutputFile(file.absolutePath)
        r.prepare()
        r.start()
        recorder = r
        outputFile = file
        isRecording = true
    }

    override fun stop(): String? {
        return try {
            recorder?.apply {
                stop()
                release()
            }
            outputFile?.absolutePath
        } catch (t: Throwable) {
            null
        } finally {
            recorder = null
            isRecording = false
        }
    }
}
