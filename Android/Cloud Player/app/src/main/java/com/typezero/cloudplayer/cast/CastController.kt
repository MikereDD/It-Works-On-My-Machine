package com.typezero.cloudplayer.cast

import android.content.Context
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.viewinterop.AndroidView
import com.google.android.gms.cast.MediaInfo
import com.google.android.gms.cast.MediaLoadRequestData
import com.google.android.gms.cast.MediaMetadata
import com.google.android.gms.cast.MediaSeekOptions
import com.google.android.gms.cast.MediaStatus
import com.google.android.gms.cast.framework.CastButtonFactory
import com.google.android.gms.cast.framework.CastContext
import com.google.android.gms.cast.framework.CastSession
import com.google.android.gms.cast.framework.SessionManagerListener
import com.google.android.gms.cast.framework.media.RemoteMediaClient

/**
 * Thin, defensive wrapper around the Cast framework. If Play Services / Cast is
 * unavailable, [isAvailable] is false and every method is a no-op — local
 * playback is never affected.
 */
class CastController(context: Context) {

    private val castContext: CastContext? = try {
        CastContext.getSharedInstance(context.applicationContext)
    } catch (t: Throwable) {
        null
    }

    val isAvailable: Boolean get() = castContext != null

    var isCasting by mutableStateOf(false)
        private set
    var isRemotePlaying by mutableStateOf(false)
        private set
    var deviceName by mutableStateOf<String?>(null)
        private set
    var playerState by mutableStateOf(MediaStatus.PLAYER_STATE_UNKNOWN)
        private set
    var positionMs by mutableStateOf(0L)
        private set
    var durationMs by mutableStateOf(0L)
        private set

    /** True when the remote is paused with media still loaded — a plain play() will resume. */
    val canResume: Boolean get() = playerState == MediaStatus.PLAYER_STATE_PAUSED

    /** Invoked when the remote player finishes the current item. */
    var onEnded: (() -> Unit)? = null

    /** Invoked when the remote player drops out with an error (e.g. the stream URL
     *  expired). The host should re-resolve a fresh URL and reload at the last position. */
    var onNeedsReload: (() -> Unit)? = null

    private val session: CastSession? get() = castContext?.sessionManager?.currentCastSession
    private val remote: RemoteMediaClient? get() = session?.remoteMediaClient

    private val progressListener = RemoteMediaClient.ProgressListener { progress, duration ->
        if (progress >= 0) positionMs = progress
        if (duration > 0) durationMs = duration
    }

    private val remoteCallback = object : RemoteMediaClient.Callback() {
        override fun onStatusUpdated() {
            val r = remote ?: return
            isRemotePlaying = r.isPlaying
            playerState = r.playerState
            if (r.playerState == MediaStatus.PLAYER_STATE_IDLE) {
                when (r.idleReason) {
                    MediaStatus.IDLE_REASON_FINISHED -> onEnded?.invoke()
                    MediaStatus.IDLE_REASON_ERROR -> onNeedsReload?.invoke()
                }
            }
        }
    }

    private val sessionListener = object : SessionManagerListener<CastSession> {
        override fun onSessionStarted(s: CastSession, sessionId: String) = attach(s)
        override fun onSessionResumed(s: CastSession, wasSuspended: Boolean) = attach(s)
        override fun onSessionStartFailed(s: CastSession, error: Int) = detach()
        override fun onSessionEnded(s: CastSession, error: Int) = detach()
        override fun onSessionResumeFailed(s: CastSession, error: Int) = detach()
        override fun onSessionStarting(s: CastSession) {}
        override fun onSessionEnding(s: CastSession) {}
        override fun onSessionResuming(s: CastSession, sessionId: String) {}
        override fun onSessionSuspended(s: CastSession, reason: Int) {}
    }

    private fun attach(s: CastSession) {
        deviceName = try { s.castDevice?.friendlyName } catch (t: Throwable) { null }
        isCasting = true
        s.remoteMediaClient?.registerCallback(remoteCallback)
        try { s.remoteMediaClient?.addProgressListener(progressListener, 1000) } catch (_: Throwable) {}
    }

    private fun detach() {
        try { session?.remoteMediaClient?.unregisterCallback(remoteCallback) } catch (_: Throwable) {}
        try { session?.remoteMediaClient?.removeProgressListener(progressListener) } catch (_: Throwable) {}
        isCasting = false
        isRemotePlaying = false
        deviceName = null
        playerState = MediaStatus.PLAYER_STATE_UNKNOWN
        positionMs = 0L
        durationMs = 0L
    }

    fun start() {
        val sm = castContext?.sessionManager ?: return
        try {
            sm.addSessionManagerListener(sessionListener, CastSession::class.java)
            sm.currentCastSession?.let { if (it.isConnected) attach(it) }
        } catch (_: Throwable) {}
    }

    fun stopListening() {
        try {
            castContext?.sessionManager
                ?.removeSessionManagerListener(sessionListener, CastSession::class.java)
            session?.remoteMediaClient?.unregisterCallback(remoteCallback)
            session?.remoteMediaClient?.removeProgressListener(progressListener)
        } catch (_: Throwable) {}
    }

    fun loadUrl(url: String, title: String, contentType: String, startMs: Long) {
        val r = remote ?: return
        try {
            val meta = MediaMetadata(
                if (contentType.startsWith("audio")) MediaMetadata.MEDIA_TYPE_MUSIC_TRACK
                else MediaMetadata.MEDIA_TYPE_MOVIE
            )
            meta.putString(MediaMetadata.KEY_TITLE, title)
            val info = MediaInfo.Builder(url)
                .setStreamType(MediaInfo.STREAM_TYPE_BUFFERED)
                .setContentType(contentType)
                .setMetadata(meta)
                .build()
            val req = MediaLoadRequestData.Builder()
                .setMediaInfo(info)
                .setAutoplay(true)
                .setCurrentTime(startMs.coerceAtLeast(0))
                .build()
            r.load(req)
        } catch (_: Throwable) {}
    }

    fun play() { try { remote?.play() } catch (_: Throwable) {} }
    fun pause() { try { remote?.pause() } catch (_: Throwable) {} }
    fun stop() { try { remote?.stop() } catch (_: Throwable) {} }
    fun seekTo(ms: Long) {
        try {
            remote?.seek(MediaSeekOptions.Builder().setPosition(ms.coerceAtLeast(0)).build())
        } catch (_: Throwable) {}
    }
}

@Composable
fun rememberCastController(): CastController {
    val context = LocalContext.current
    val controller = remember { CastController(context) }
    DisposableEffect(Unit) {
        controller.start()
        onDispose { controller.stopListening() }
    }
    return controller
}

/** The standard Cast button (device picker). No-op visual if Cast is unavailable. */
@Composable
fun CastButton(modifier: Modifier = Modifier) {
    AndroidView(
        modifier = modifier,
        factory = { ctx ->
            val themed = androidx.appcompat.view.ContextThemeWrapper(
                ctx, androidx.appcompat.R.style.Theme_AppCompat_NoActionBar
            )
            val btn = androidx.mediarouter.app.MediaRouteButton(themed)
            try {
                CastButtonFactory.setUpMediaRouteButton(ctx.applicationContext, btn)
            } catch (_: Throwable) {
            }
            btn
        }
    )
}
