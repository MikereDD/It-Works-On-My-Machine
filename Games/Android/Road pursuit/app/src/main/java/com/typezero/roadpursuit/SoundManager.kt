package com.typezero.roadpursuit

import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioTrack
import java.util.concurrent.Executors
import kotlin.math.PI
import kotlin.math.exp
import kotlin.math.sin

/**
 * Procedural sound effects. Every sound is generated as a short PCM buffer
 * at play time and pushed through a one-shot AudioTrack — no .wav/.ogg assets,
 * nothing copyrighted, nothing to bundle.
 */
class SoundManager {

    @Volatile var muted = false

    private val sr = 44100
    private val pool = Executors.newFixedThreadPool(6)

    companion object {
        const val SINE = 0
        const val SQUARE = 1
        const val SAW = 2
        const val TRI = 3
    }

    // ---- public sfx ----
    fun shoot()  = tone(720f, 420f, 0.06f, SQUARE, 0.10f)
    fun boom()   { noise(0.40f, 0.40f, 0.30f); tone(120f, 40f, 0.40f, SAW, 0.16f) }
    fun crash()  { noise(0.55f, 0.55f, 0.18f); tone(90f, 30f, 0.50f, SQUARE, 0.22f) }
    fun pickup() { tone(440f, 880f, 0.12f, SINE, 0.22f); tone(660f, 1320f, 0.14f, SINE, 0.16f) }
    fun slip()   = tone(300f, 140f, 0.30f, SINE, 0.20f)
    fun van()    { tone(330f, 520f, 0.10f, TRI, 0.22f); tone(520f, 780f, 0.12f, TRI, 0.20f); tone(780f, 1040f, 0.14f, TRI, 0.18f) }
    fun stage()  { tone(523f, 523f, 0.12f, SQUARE, 0.20f); tone(659f, 659f, 0.12f, SQUARE, 0.20f); tone(880f, 880f, 0.18f, SQUARE, 0.22f) }
    fun splash() = noise(0.50f, 0.32f, 0.65f)

    // ---- generators ----
    private fun tone(f0: Float, f1: Float, durSec: Float, type: Int, vol: Float) {
        if (muted) return
        submit { buildTone(f0, f1, durSec, type, vol) }
    }

    private fun noise(durSec: Float, vol: Float, cutoff: Float) {
        if (muted) return
        submit { buildNoise(durSec, vol, cutoff) }
    }

    private fun submit(build: () -> ShortArray) {
        try {
            pool.execute {
                try { play(build()) } catch (_: Throwable) { /* ignore audio hiccups */ }
            }
        } catch (_: Throwable) { /* pool rejected, drop the sound */ }
    }

    private fun buildTone(f0: Float, f1: Float, durSec: Float, type: Int, vol: Float): ShortArray {
        val n = (sr * durSec).toInt().coerceAtLeast(1)
        val buf = ShortArray(n)
        var phase = 0.0
        for (i in 0 until n) {
            val t = i.toFloat() / n
            val f = f0 + (f1 - f0) * t
            phase += 2.0 * PI * f / sr
            val ph = (phase / (2.0 * PI)) % 1.0
            val s = when (type) {
                SQUARE -> if (sin(phase) >= 0) 1.0 else -1.0
                SAW -> 2.0 * ph - 1.0
                TRI -> 2.0 * kotlin.math.abs(2.0 * ph - 1.0) - 1.0
                else -> sin(phase)
            }
            val env = exp(-3.0 * t)
            buf[i] = (s * env * vol * Short.MAX_VALUE).toInt()
                .coerceIn(-32768, 32767).toShort()
        }
        return buf
    }

    private fun buildNoise(durSec: Float, vol: Float, cutoff: Float): ShortArray {
        val n = (sr * durSec).toInt().coerceAtLeast(1)
        val buf = ShortArray(n)
        var last = 0.0
        val alpha = cutoff.toDouble().coerceIn(0.01, 1.0)
        for (i in 0 until n) {
            val t = i.toFloat() / n
            val white = Math.random() * 2.0 - 1.0
            last += alpha * (white - last)         // crude one-pole low-pass
            val env = exp(-3.0 * t)
            buf[i] = (last * env * vol * Short.MAX_VALUE).toInt()
                .coerceIn(-32768, 32767).toShort()
        }
        return buf
    }

    private fun play(buf: ShortArray) {
        val bytes = buf.size * 2
        val track = AudioTrack.Builder()
            .setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_GAME)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                    .build()
            )
            .setAudioFormat(
                AudioFormat.Builder()
                    .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                    .setSampleRate(sr)
                    .setChannelMask(AudioFormat.CHANNEL_OUT_MONO)
                    .build()
            )
            .setBufferSizeInBytes(bytes)
            .setTransferMode(AudioTrack.MODE_STATIC)
            .build()

        track.write(buf, 0, buf.size)
        track.play()
        val ms = (buf.size * 1000L) / sr + 80
        try { Thread.sleep(ms) } catch (_: InterruptedException) {}
        try { track.stop() } catch (_: Throwable) {}
        track.release()
    }

    fun release() {
        pool.shutdownNow()
    }
}
