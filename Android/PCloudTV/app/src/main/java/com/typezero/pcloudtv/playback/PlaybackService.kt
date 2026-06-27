package com.typezero.pcloudtv.playback

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.support.v4.media.MediaBrowserCompat.MediaItem
import android.support.v4.media.MediaDescriptionCompat
import android.support.v4.media.MediaMetadataCompat
import android.support.v4.media.session.MediaSessionCompat
import android.support.v4.media.session.PlaybackStateCompat
import androidx.core.app.NotificationCompat
import androidx.media.MediaBrowserServiceCompat
import androidx.media.app.NotificationCompat.MediaStyle
import androidx.media.session.MediaButtonReceiver
import com.typezero.pcloudtv.MainActivity
import com.typezero.pcloudtv.data.ApiResult
import com.typezero.pcloudtv.data.PCloudClient
import com.typezero.pcloudtv.data.PItem
import com.typezero.pcloudtv.data.SessionStore
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch

/**
 * Foreground media service AND Android Auto browser.
 *
 * - Owns a MediaSessionCompat and posts a MediaStyle notification so the lock
 *   screen, headset, Bluetooth, and the car show "now playing" and route the
 *   transport buttons (the session callback forwards to the UI via PlaybackBridge;
 *   the LibVLC player still lives in the UI for now).
 * - Exposes the pCloud tree to Android Auto via onLoadChildren so the app appears
 *   in Auto and the folders/playlists/tracks are browsable on the car screen.
 *
 * NOTE: playing a track picked in Android Auto (onPlayFromMediaId) is the next
 * step — this build makes the app appear + browsable.
 */
class PlaybackService : MediaBrowserServiceCompat() {

    private lateinit var session: MediaSessionCompat
    private val client = PCloudClient()
    private val browseScope = CoroutineScope(Dispatchers.IO + SupervisorJob())

    override fun onCreate() {
        super.onCreate()
        ensureChannel(this)
        session = MediaSessionCompat(this, "pCloudTV").apply {
            setCallback(object : MediaSessionCompat.Callback() {
                override fun onPlay() { PlaybackBridge.onPlay?.invoke() }
                override fun onPause() { PlaybackBridge.onPause?.invoke() }
                override fun onSkipToNext() { PlaybackBridge.onNext?.invoke() }
                override fun onSkipToPrevious() { PlaybackBridge.onPrev?.invoke() }
                override fun onSeekTo(pos: Long) { PlaybackBridge.onSeekTo?.invoke(pos) }
                override fun onStop() {
                    PlaybackBridge.onStop?.invoke()
                    stopForegroundCompat()
                    stopSelf()
                }
            })
            isActive = true
        }
        setSessionToken(session.sessionToken)
        PlaybackBridge.onChanged = { runCatching { refresh() } }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        MediaButtonReceiver.handleIntent(session, intent)
        try {
            refresh()
        } catch (e: Throwable) {
            runCatching { stopSelf() }
        }
        return START_STICKY
    }

    override fun onDestroy() {
        PlaybackBridge.onChanged = null
        runCatching { browseScope.cancel() }
        runCatching {
            session.isActive = false
            session.release()
        }
        super.onDestroy()
    }

    // ---------------------------------------------------------------------------
    // Android Auto browser
    // ---------------------------------------------------------------------------

    override fun onGetRoot(
        clientPackageName: String,
        clientUid: Int,
        rootHints: Bundle?
    ): BrowserRoot {
        // Personal app: allow any caller (Android Auto, the system media UI) to browse.
        return BrowserRoot(ROOT_ID, null)
    }

    override fun onLoadChildren(
        parentId: String,
        result: Result<MutableList<MediaItem>>
    ) {
        result.detach()
        browseScope.launch {
            val items = runCatching { loadChildren(parentId) }.getOrDefault(mutableListOf())
            runCatching { result.sendResult(items) }
        }
    }

    private suspend fun loadChildren(parentId: String): MutableList<MediaItem> {
        val out = mutableListOf<MediaItem>()
        val acct = SessionStore(this).load() ?: return out
        when {
            parentId == ROOT_ID -> {
                out += browsable("Playlists", "path:/Music/playlists")
                out += browsable("Audiobooks", "path:/Books/Audiobooks")
                val res = client.listFolder(acct, 0L)
                if (res is ApiResult.Ok) addItems(out, res.value)
            }
            parentId.startsWith("folder:") -> {
                val id = parentId.removePrefix("folder:").toLongOrNull()
                if (id != null) {
                    val res = client.listFolder(acct, id)
                    if (res is ApiResult.Ok) addItems(out, res.value)
                }
            }
            parentId.startsWith("path:") -> {
                val path = parentId.removePrefix("path:")
                val res = client.listFolderByPath(acct, path)
                if (res is ApiResult.Ok) addItems(out, res.value)
            }
        }
        return out
    }

    private fun addItems(out: MutableList<MediaItem>, items: List<PItem>) {
        for (it in items) {
            when {
                it.isFolder && it.folderId != null ->
                    out += browsable(it.name, "folder:${it.folderId}")
                it.isPlaylist && it.fileId != null ->
                    out += playable(it.name, "playlist:${it.fileId}")
                it.isPlayable && it.fileId != null ->
                    out += playable(it.name, "file:${it.fileId}")
            }
        }
    }

    private fun browsable(title: String, mediaId: String): MediaItem =
        MediaItem(
            MediaDescriptionCompat.Builder()
                .setMediaId(mediaId).setTitle(title).build(),
            MediaItem.FLAG_BROWSABLE
        )

    private fun playable(title: String, mediaId: String): MediaItem =
        MediaItem(
            MediaDescriptionCompat.Builder()
                .setMediaId(mediaId).setTitle(title).build(),
            MediaItem.FLAG_PLAYABLE
        )

    // ---------------------------------------------------------------------------
    // Foreground playback notification + session state
    // ---------------------------------------------------------------------------

    private fun stopForegroundCompat() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            stopForeground(STOP_FOREGROUND_REMOVE)
        } else {
            @Suppress("DEPRECATION") stopForeground(true)
        }
    }

    private fun refresh() {
        val b = PlaybackBridge

        session.setMetadata(
            MediaMetadataCompat.Builder()
                .putString(MediaMetadataCompat.METADATA_KEY_TITLE, b.title)
                .putString(MediaMetadataCompat.METADATA_KEY_ARTIST, b.artist ?: "")
                .putString(MediaMetadataCompat.METADATA_KEY_ALBUM, b.album ?: "")
                .putLong(
                    MediaMetadataCompat.METADATA_KEY_DURATION,
                    if (b.durationMs > 0) b.durationMs else 0L
                )
                .apply { b.art?.let { putBitmap(MediaMetadataCompat.METADATA_KEY_ALBUM_ART, it) } }
                .build()
        )

        val actions = PlaybackStateCompat.ACTION_PLAY or
            PlaybackStateCompat.ACTION_PAUSE or
            PlaybackStateCompat.ACTION_PLAY_PAUSE or
            PlaybackStateCompat.ACTION_SKIP_TO_NEXT or
            PlaybackStateCompat.ACTION_SKIP_TO_PREVIOUS or
            PlaybackStateCompat.ACTION_SEEK_TO or
            PlaybackStateCompat.ACTION_STOP
        session.setPlaybackState(
            PlaybackStateCompat.Builder()
                .setActions(actions)
                .setState(
                    if (b.isPlaying) PlaybackStateCompat.STATE_PLAYING
                    else PlaybackStateCompat.STATE_PAUSED,
                    b.positionMs,
                    1f
                )
                .build()
        )

        startForeground(NOTIF_ID, buildNotification())
    }

    private fun buildNotification(): Notification {
        val b = PlaybackBridge

        fun btn(action: Long): PendingIntent =
            MediaButtonReceiver.buildMediaButtonPendingIntent(this, action)

        val prev = NotificationCompat.Action(
            android.R.drawable.ic_media_previous, "Previous",
            btn(PlaybackStateCompat.ACTION_SKIP_TO_PREVIOUS)
        )
        val playPause = if (b.isPlaying)
            NotificationCompat.Action(
                android.R.drawable.ic_media_pause, "Pause",
                btn(PlaybackStateCompat.ACTION_PLAY_PAUSE)
            )
        else
            NotificationCompat.Action(
                android.R.drawable.ic_media_play, "Play",
                btn(PlaybackStateCompat.ACTION_PLAY_PAUSE)
            )
        val next = NotificationCompat.Action(
            android.R.drawable.ic_media_next, "Next",
            btn(PlaybackStateCompat.ACTION_SKIP_TO_NEXT)
        )

        val contentPI = PendingIntent.getActivity(
            this, 0,
            Intent(this, MainActivity::class.java)
                .addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )

        val subtitle = listOfNotNull(b.artist, b.album)
            .filter { it.isNotBlank() }.joinToString(" \u2014 ")

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle(b.title.ifBlank { "Playing audio" })
            .setContentText(subtitle.ifBlank { "pCloud TV" })
            .setSmallIcon(android.R.drawable.ic_media_play)
            .setLargeIcon(b.art)
            .setContentIntent(contentPI)
            .setDeleteIntent(btn(PlaybackStateCompat.ACTION_STOP))
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setCategory(Notification.CATEGORY_TRANSPORT)
            .setOnlyAlertOnce(true)
            .setOngoing(b.isPlaying)
            .addAction(prev)
            .addAction(playPause)
            .addAction(next)
            .setStyle(
                MediaStyle()
                    .setMediaSession(session.sessionToken)
                    .setShowActionsInCompactView(0, 1, 2)
            )
            .build()
    }

    companion object {
        const val CHANNEL_ID = "pcloudtv_playback"
        const val NOTIF_ID = 1001
        const val ROOT_ID = "__root__"

        fun ensureChannel(ctx: Context) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                val nm = ctx.getSystemService(NotificationManager::class.java)
                if (nm.getNotificationChannel(CHANNEL_ID) == null) {
                    val ch = NotificationChannel(
                        CHANNEL_ID, "Playback",
                        NotificationManager.IMPORTANCE_LOW
                    )
                    ch.setShowBadge(false)
                    nm.createNotificationChannel(ch)
                }
            }
        }

        fun start(ctx: Context) {
            val i = Intent(ctx, PlaybackService::class.java)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                ctx.startForegroundService(i)
            } else {
                ctx.startService(i)
            }
        }

        fun stop(ctx: Context) {
            ctx.stopService(Intent(ctx, PlaybackService::class.java))
        }
    }
}
