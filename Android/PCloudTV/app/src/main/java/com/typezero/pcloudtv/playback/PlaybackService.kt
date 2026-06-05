package com.typezero.pcloudtv.playback

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat

/**
 * A minimal foreground service whose only job is to keep the app's process
 * alive while AUDIO is playing, so playback continues when the user leaves the
 * app. It does not own the player — the existing VLC MediaPlayer keeps running;
 * this just prevents the system from killing the process in the background.
 */
class PlaybackService : Service() {

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val title = intent?.getStringExtra(EXTRA_TITLE) ?: "Playing audio"
        ensureChannel(this)
        startForeground(NOTIF_ID, buildNotification(title))
        return START_STICKY
    }

    private fun buildNotification(title: String): Notification =
        NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle(title)
            .setContentText("pCloud TV — playing in background")
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

        fun start(ctx: Context, title: String) {
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
