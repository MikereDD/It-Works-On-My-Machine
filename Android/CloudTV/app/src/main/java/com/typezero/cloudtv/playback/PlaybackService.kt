package com.typezero.cloudtv.playback

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.media.session.MediaSession
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat

/**
 * Minimal foreground service that keeps the process alive while AUDIO plays in
 * the background. It does not own the player — the VLC MediaPlayer keeps running;
 * this just prevents the system from killing the process.
 *
 * Deliberately plain: a basic ongoing notification (the v2.6 known-good build).
 * A richer MediaStyle notification was tried in v2.7 but destabilized audio
 * playback, so it was removed. The token param is accepted for call-site
 * compatibility but unused.
 */
class PlaybackService : Service() {

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val title = intent?.getStringExtra(EXTRA_TITLE) ?: "Playing audio"
        ensureChannel(this)
        try {
            startForeground(NOTIF_ID, buildNotification(title))
        } catch (e: Throwable) {
            // Never let a foreground-service failure crash playback.
            runCatching { stopSelf() }
        }
        return START_STICKY
    }

    private fun buildNotification(title: String): Notification =
        NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle(title)
            .setContentText("Cloud TV — playing in background")
            .setSmallIcon(android.R.drawable.ic_media_play)
            .setOngoing(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setCategory(Notification.CATEGORY_TRANSPORT)
            .build()

    companion object {
        const val CHANNEL_ID = "pcloudtv_playback"
        const val NOTIF_ID = 1001
        const val EXTRA_TITLE = "title"

        fun ensureChannel(ctx: Context) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                val nm = ctx.getSystemService(NotificationManager::class.java)
                if (nm.getNotificationChannel(CHANNEL_ID) == null) {
                    val ch = NotificationChannel(
                        CHANNEL_ID, "Background playback",
                        NotificationManager.IMPORTANCE_LOW
                    )
                    ch.setShowBadge(false)
                    nm.createNotificationChannel(ch)
                }
            }
        }

        fun start(ctx: Context, title: String, token: MediaSession.Token? = null) {
            // token currently unused — kept so the player call site stays valid.
            val i = Intent(ctx, PlaybackService::class.java).putExtra(EXTRA_TITLE, title)
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
