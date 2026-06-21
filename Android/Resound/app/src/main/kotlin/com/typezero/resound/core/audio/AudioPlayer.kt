/*
 * file:    AudioPlayer.kt
 * author:  Mike Redd (typezero)
 * version: 0.4.1
 * desc:    Lightweight MediaPlayer wrapper for in-app preview of the loaded
 *          file. Plays from a given position; the editor polls currentMs to
 *          drive the playhead and stops at the end of the selection.
 */
package com.typezero.resound.core.audio

import android.content.Context
import android.media.MediaPlayer
import android.net.Uri
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

class AudioPlayer {

    private var player: MediaPlayer? = null

    val isPlaying: Boolean get() = runCatching { player?.isPlaying == true }.getOrDefault(false)
    val currentMs: Long get() = runCatching { player?.currentPosition?.toLong() ?: 0L }.getOrDefault(0L)

    /** (Re)load [uri]. Blocking prepare runs off the main thread. */
    suspend fun prepare(context: Context, uri: Uri) = withContext(Dispatchers.IO) {
        release()
        player = MediaPlayer().apply {
            setDataSource(context, uri)
            prepare()
        }
    }

    fun play(fromMs: Long? = null) {
        val p = player ?: return
        if (fromMs != null) p.seekTo(fromMs.toInt())
        p.start()
    }

    fun pause() {
        runCatching { player?.pause() }
    }

    fun seekTo(ms: Long) {
        runCatching { player?.seekTo(ms.toInt()) }
    }

    fun release() {
        runCatching { player?.release() }
        player = null
    }
}
