package com.typezero.cloudplayer.playback

import android.graphics.Bitmap

/**
 * Decouples the foreground [PlaybackService] (which owns the MediaSessionCompat and
 * the MediaStyle notification) from the player UI (which owns the LibVLC player).
 *
 * The UI registers control callbacks and pushes the current now-playing state; the
 * service reads that state to build the session metadata / playback-state and the
 * notification, and the session callback invokes the control callbacks. This keeps
 * the LibVLC player in the UI for now while still exposing a proper media session
 * to the lock screen, Bluetooth, and the car.
 */
object PlaybackBridge {

    // --- Controls: set by the player UI, invoked by the session callback. ---
    @Volatile var onPlay: (() -> Unit)? = null
    @Volatile var onPause: (() -> Unit)? = null
    @Volatile var onNext: (() -> Unit)? = null
    @Volatile var onPrev: (() -> Unit)? = null
    @Volatile var onSeekTo: ((Long) -> Unit)? = null
    @Volatile var onStop: (() -> Unit)? = null

    // --- State: pushed by the player UI, read by the service. ---
    @Volatile var title: String = ""
    @Volatile var artist: String? = null
    @Volatile var album: String? = null
    @Volatile var art: Bitmap? = null
    @Volatile var durationMs: Long = 0L
    @Volatile var positionMs: Long = 0L
    @Volatile var isPlaying: Boolean = false
    @Volatile var hasNext: Boolean = false
    @Volatile var hasPrev: Boolean = false

    /** The service installs this so the UI can ask it to refresh after a state push. */
    @Volatile var onChanged: (() -> Unit)? = null

    /**
     * True while Android Auto's headless player (in [PlaybackService]) owns
     * playback and is the source of truth for the media session. The in-app player
     * must set this false (and call [onYieldToUi]) before it starts playing.
     */
    @Volatile var serviceOwnsPlayback: Boolean = false

    /**
     * Installed by the service; invoked by the in-app player right before it starts
     * playback so the headless car player stops and releases cleanly.
     */
    @Volatile var onYieldToUi: (() -> Unit)? = null

    fun notifyChanged() {
        onChanged?.invoke()
    }

    fun clearControls() {
        onPlay = null; onPause = null; onNext = null
        onPrev = null; onSeekTo = null; onStop = null
    }
}
