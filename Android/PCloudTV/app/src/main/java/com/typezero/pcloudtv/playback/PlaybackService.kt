package com.typezero.pcloudtv.playback

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.IBinder
import android.support.v4.media.MediaMetadataCompat
import android.support.v4.media.session.MediaSessionCompat
import android.support.v4.media.session.PlaybackStateCompat
import androidx.core.app.NotificationCompat
import androidx.media.app.NotificationCompat.MediaStyle
import androidx.media.session.MediaButtonReceiver
import com.typezero.pcloudtv.MainActivity

/**
 * Foreground media service. Owns a MediaSessionCompat and posts a MediaStyle
 * notification so the lock screen, headset, Bluetooth, and the car show "now
 * playing" and route the transport buttons (play/pause, skip, seek) to the
 * session. The session callback forwards to the player UI via [PlaybackBridge];
 * the LibVLC player itself still lives in the UI.
 */
class PlaybackService : android.app.Service() {

    private lateinit var session: MediaSessionCompat

    override fun onBind(intent: Intent?): IBinder? = null

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
        // When the UI pushes new state, refresh the session + notification.
        PlaybackBridge.onChanged = { runCatching { refresh() } }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        // Route hardware / Bluetooth / notification-action media buttons.
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
        runCatching {
            session.isActive = false
            session.release()
        }
        super.onDestroy()
    }

    private fun stopForegroundCompat() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            stopForeground(STOP_FOREGROUND_REMOVE)
        } else {
            @Suppress("DEPRECATION") stopForeground(true)
        }
    }

    /** Push current bridge state into the session, then (re)post the notification. */
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
