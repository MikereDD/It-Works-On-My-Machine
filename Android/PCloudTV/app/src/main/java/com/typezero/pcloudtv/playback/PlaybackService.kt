package com.typezero.pcloudtv.playback

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.net.Uri
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
import com.typezero.pcloudtv.data.Session
import com.typezero.pcloudtv.data.SessionStore
import com.typezero.pcloudtv.data.MediaItem as Track
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.videolan.libvlc.LibVLC
import org.videolan.libvlc.Media
import org.videolan.libvlc.MediaPlayer

/**
 * Foreground media service AND Android Auto browser.
 *
 * - Owns a MediaSessionCompat and posts a MediaStyle notification so the lock
 *   screen, headset, Bluetooth, and the car show "now playing" and route the
 *   transport buttons.
 * - Exposes the pCloud tree to Android Auto via onLoadChildren so the app appears
 *   in Auto and the folders/playlists/tracks are browsable on the car screen.
 * - Owns a HEADLESS audio-only LibVLC player so a track picked in the car
 *   (onPlayFromMediaId) plays even when the Compose UI is not on screen (phone
 *   locked, app backgrounded — the normal Android Auto case).
 *
 * Two playback surfaces, one session: the in-app PlayerScreen owns its own LibVLC
 * player for the on-phone experience; this service owns a separate headless player
 * for Android Auto. They never play at once — whoever starts tells the other to
 * stop via [PlaybackBridge], and [PlaybackBridge.serviceOwnsPlayback] records who
 * is the current source of truth for the session state.
 */
class PlaybackService : MediaBrowserServiceCompat() {

    private lateinit var session: MediaSessionCompat
    private val client = PCloudClient()
    private val browseScope = CoroutineScope(Dispatchers.IO + SupervisorJob())

    // Headless audio player for Android Auto. Created on first car play, released
    // when the in-app player takes over or the service is destroyed.
    private var libVlc: LibVLC? = null
    private var player: MediaPlayer? = null

    // Audio focus — required for the car (and other media apps) to actually route
    // audio. Without it the clock advances but no sound comes out.
    private var audioManager: AudioManager? = null
    private var focusRequest: AudioFocusRequest? = null

    // The Auto-initiated queue.
    private var queue: List<Track> = emptyList()
    private var queueIndex: Int = 0
    private var pendingTitle: String = ""

    // Now-playing artwork shown in the car's media card. Embedded cover art is
    // extracted by VLC a beat after playback starts, so we re-read it for a few
    // ticks (like the in-app player) and fall back to a monochrome placeholder.
    @Volatile private var currentArt: Bitmap? = null
    private var artAttempts: Int = 0
    private var artFound: Boolean = false
    @Volatile private var artReading: Boolean = false
    private var placeholder: Bitmap? = null

    override fun onCreate() {
        super.onCreate()
        ensureChannel(this)
        session = MediaSessionCompat(this, "pCloudTV").apply {
            setCallback(object : MediaSessionCompat.Callback() {
                override fun onPlay() {
                    if (serviceOwns()) resumeService() else PlaybackBridge.onPlay?.invoke()
                }
                override fun onPause() {
                    if (serviceOwns()) pauseService() else PlaybackBridge.onPause?.invoke()
                }
                override fun onSkipToNext() {
                    if (serviceOwns()) skipService(+1) else PlaybackBridge.onNext?.invoke()
                }
                override fun onSkipToPrevious() {
                    if (serviceOwns()) skipService(-1) else PlaybackBridge.onPrev?.invoke()
                }
                override fun onSeekTo(pos: Long) {
                    if (serviceOwns()) player?.time = pos else PlaybackBridge.onSeekTo?.invoke(pos)
                }
                override fun onStop() {
                    if (serviceOwns()) {
                        releasePlayer()
                        PlaybackBridge.serviceOwnsPlayback = false
                    } else {
                        PlaybackBridge.onStop?.invoke()
                    }
                    stopForegroundCompat()
                    stopSelf()
                }
                override fun onPlayFromMediaId(mediaId: String?, extras: Bundle?) {
                    if (mediaId != null) startFromMediaId(mediaId)
                }
            })
            isActive = true
        }
        setSessionToken(session.sessionToken)

        // The in-app player asks the service to refresh the session/notification
        // after it pushes state; ignore those while the car owns playback.
        PlaybackBridge.onChanged = { if (!serviceOwns()) runCatching { refresh() } }
        // The in-app player calls this when the user starts playback on the phone,
        // so the headless car player yields cleanly.
        PlaybackBridge.onYieldToUi = { runCatching { releasePlayer() } }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        MediaButtonReceiver.handleIntent(session, intent)
        try {
            if (!serviceOwns()) refresh()
        } catch (e: Throwable) {
            runCatching { stopSelf() }
        }
        return START_STICKY
    }

    override fun onDestroy() {
        PlaybackBridge.onChanged = null
        PlaybackBridge.onYieldToUi = null
        runCatching { releasePlayer() }
        runCatching { browseScope.cancel() }
        runCatching {
            session.isActive = false
            session.release()
        }
        super.onDestroy()
    }

    private fun serviceOwns(): Boolean = PlaybackBridge.serviceOwnsPlayback

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
                if (res is ApiResult.Ok) addItems(out, res.value, "folder:0")
            }
            parentId.startsWith("folder:") -> {
                val id = parentId.removePrefix("folder:").toLongOrNull()
                if (id != null) {
                    val res = client.listFolder(acct, id)
                    if (res is ApiResult.Ok) addItems(out, res.value, parentId)
                }
            }
            parentId.startsWith("path:") -> {
                val path = parentId.removePrefix("path:")
                val res = client.listFolderByPath(acct, path)
                if (res is ApiResult.Ok) addItems(out, res.value, parentId)
            }
        }
        return out
    }

    /**
     * @param parentLocator the browse id of the folder these items live in
     *        ("folder:<id>" or "path:<p>"). Baked into playlist media ids so the
     *        service can re-list the folder at play time to resolve relative
     *        filename entries inside the .m3u.
     */
    private fun addItems(out: MutableList<MediaItem>, items: List<PItem>, parentLocator: String) {
        for (it in items) {
            when {
                it.isFolder && it.folderId != null ->
                    out += browsable(it.name, "folder:${it.folderId}")
                it.isPlaylist && it.fileId != null ->
                    out += playable(it.name, "playlist:${it.fileId}|$parentLocator")
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
    // Headless playback (Android Auto)
    // ---------------------------------------------------------------------------

    /**
     * Resolve a tapped browse id into a queue and start playing. Posts a BUFFERING
     * state immediately so Android Auto's "Getting your selection..." spinner is
     * replaced as soon as the user taps, rather than hanging until the link
     * resolves and the first frame decodes.
     */
    private fun startFromMediaId(mediaId: String) {
        // Take over from the in-app player (no-op if it isn't running / on screen).
        PlaybackBridge.serviceOwnsPlayback = true
        runCatching { PlaybackBridge.onStop?.invoke() }

        queue = emptyList()
        queueIndex = 0
        pendingTitle = ""
        postBuffering("Loading\u2026")

        browseScope.launch {
            val session = SessionStore(this@PlaybackService).load()
            if (session == null) {
                postError()
                return@launch
            }
            val built = runCatching { buildQueue(session, mediaId) }.getOrDefault(emptyList())
            if (built.isEmpty()) {
                postError()
                return@launch
            }
            queue = built
            queueIndex = 0
            withContext(Dispatchers.Main) { playCurrent() }
        }
    }

    private suspend fun buildQueue(session: Session, mediaId: String): List<Track> = when {
        mediaId.startsWith("file:") -> {
            val id = mediaId.removePrefix("file:").toLongOrNull()
            if (id != null) listOf(Track(title = "", fileId = id, directUrl = null)) else emptyList()
        }
        mediaId.startsWith("playlist:") -> {
            // playlist:<fileId>|<parentLocator>
            val rest = mediaId.removePrefix("playlist:")
            val fileId = rest.substringBefore('|').toLongOrNull()
            val parent = rest.substringAfter('|', "")
            if (fileId == null) emptyList() else {
                val folderItems = listFolderItems(session, parent)
                val pl = folderItems.firstOrNull { it.fileId == fileId }
                    ?: PItem(
                        name = "Playlist", isFolder = false, folderId = null,
                        fileId = fileId, contentType = "", category = 0, size = 0L
                    )
                when (val r = client.resolvePlaylist(session, pl, folderItems)) {
                    is ApiResult.Ok -> r.value
                    is ApiResult.Error -> emptyList()
                }
            }
        }
        else -> emptyList()
    }

    private suspend fun listFolderItems(session: Session, parentLocator: String): List<PItem> = when {
        parentLocator.startsWith("folder:") -> {
            val id = parentLocator.removePrefix("folder:").toLongOrNull()
            if (id == null) emptyList()
            else (client.listFolder(session, id) as? ApiResult.Ok)?.value ?: emptyList()
        }
        parentLocator.startsWith("path:") -> {
            val p = parentLocator.removePrefix("path:")
            (client.listFolderByPath(session, p) as? ApiResult.Ok)?.value ?: emptyList()
        }
        else -> emptyList()
    }

    /** Mirror of the in-app resolveUrl: direct URL, else pCloud path, else file id. */
    private suspend fun resolveUrl(session: Session, item: Track): String? = when {
        item.directUrl != null -> item.directUrl
        item.path != null -> (client.getStreamUrlByPath(session, item.path) as? ApiResult.Ok)?.value
        item.fileId != null -> (client.getStreamUrl(session, item.fileId) as? ApiResult.Ok)?.value
        else -> null
    }

    private fun ensureFocusRequest(): AudioFocusRequest {
        focusRequest?.let { return it }
        val fr = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN)
            .setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_MEDIA)
                    .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
                    .build()
            )
            .setOnAudioFocusChangeListener { change ->
                when (change) {
                    AudioManager.AUDIOFOCUS_LOSS,
                    AudioManager.AUDIOFOCUS_LOSS_TRANSIENT -> pauseService()
                    AudioManager.AUDIOFOCUS_GAIN -> if (serviceOwns()) player?.play()
                }
            }
            .build()
        focusRequest = fr
        return fr
    }

    private fun requestFocus() {
        val am = audioManager
            ?: (getSystemService(Context.AUDIO_SERVICE) as AudioManager).also { audioManager = it }
        runCatching { am.requestAudioFocus(ensureFocusRequest()) }
    }

    private fun abandonFocus() {
        val am = audioManager ?: return
        val fr = focusRequest ?: return
        runCatching { am.abandonAudioFocusRequest(fr) }
    }

    private fun ensurePlayer(): MediaPlayer {
        player?.let { return it }
        val vlc = LibVLC(
            this,
            arrayListOf(
                "--network-caching=1500",
                "--http-reconnect",
                "--no-video",
                "--aout=audiotrack"
            )
        )
        val mp = MediaPlayer(vlc)
        mp.setEventListener { e ->
            when (e.type) {
                MediaPlayer.Event.Playing -> { pushServiceState(playing = true); maybeReadArtwork() }
                MediaPlayer.Event.Paused -> pushServiceState(playing = false)
                MediaPlayer.Event.LengthChanged -> { pushServiceState(playing = mp.isPlaying); maybeReadArtwork() }
                MediaPlayer.Event.TimeChanged -> { pushPosition(playing = mp.isPlaying); maybeReadArtwork() }
                MediaPlayer.Event.EndReached -> skipService(+1)
                MediaPlayer.Event.EncounteredError -> postError()
            }
        }
        libVlc = vlc
        player = mp
        return mp
    }

    private fun playCurrent() {
        val item = queue.getOrNull(queueIndex) ?: run { postError(); return }
        pendingTitle = item.title
        currentArt = null
        artFound = false
        artAttempts = 0
        postBuffering(item.title.ifBlank { "Loading\u2026" })
        browseScope.launch {
            val session = SessionStore(this@PlaybackService).load() ?: run { postError(); return@launch }
            val url = resolveUrl(session, item) ?: run { postError(); return@launch }
            withContext(Dispatchers.Main) {
                val mp = ensurePlayer()
                val vlc = libVlc ?: return@withContext
                requestFocus()
                val media = Media(vlc, Uri.parse(url)).apply { setHWDecoderEnabled(false, false) }
                mp.media = media
                media.release()
                mp.play()
            }
        }
    }

    private fun resumeService() { requestFocus(); player?.play() }
    private fun pauseService() { player?.pause() }

    private fun skipService(delta: Int) {
        val next = queueIndex + delta
        if (next in queue.indices) {
            queueIndex = next
            playCurrent()
        } else if (delta > 0) {
            // End of queue.
            releasePlayer()
            PlaybackBridge.serviceOwnsPlayback = false
            stopForegroundCompat()
            stopSelf()
        }
    }

    private fun releasePlayer() {
        abandonFocus()
        runCatching { player?.stop() }
        runCatching { player?.release() }
        runCatching { libVlc?.release() }
        player = null
        libVlc = null
        queue = emptyList()
        queueIndex = 0
        currentArt = null
        artFound = false
        artAttempts = 0
    }

    private fun currentMeta(): MediaMetadataCompat {
        val mp = player
        var vlcTitle = ""
        var vlcArtist = ""
        var vlcAlbum = ""
        val m = runCatching { mp?.media }.getOrNull()
        if (m != null) {
            try {
                vlcTitle = m.getMeta(META_TITLE).orEmpty()
                vlcArtist = m.getMeta(META_ARTIST).orEmpty()
                vlcAlbum = m.getMeta(META_ALBUM).orEmpty()
            } finally {
                runCatching { m.release() }
            }
        }
        val title = pendingTitle.ifBlank { vlcTitle }.ifBlank { "pCloud TV" }
        val dur = (mp?.length ?: 0L).coerceAtLeast(0L)
        return MediaMetadataCompat.Builder()
            .putString(MediaMetadataCompat.METADATA_KEY_TITLE, title)
            .putString(MediaMetadataCompat.METADATA_KEY_ARTIST, vlcArtist)
            .putString(MediaMetadataCompat.METADATA_KEY_ALBUM, vlcAlbum)
            .putLong(MediaMetadataCompat.METADATA_KEY_DURATION, dur)
            .putBitmap(MediaMetadataCompat.METADATA_KEY_ALBUM_ART, currentArt ?: placeholderArt())
            .build()
    }

    /**
     * Read the current track's embedded cover art. VLC extracts it a beat after
     * playback starts, so this is retried for a few ticks until it lands (capped),
     * mirroring the in-app player. Same source/decode path as PlayerScreen.
     */
    private fun maybeReadArtwork() {
        if (artFound || artReading || artAttempts >= ART_MAX_ATTEMPTS) return
        artReading = true
        artAttempts++
        browseScope.launch {
            val bmp = runCatching { extractArtwork() }.getOrNull()
            if (bmp != null) {
                currentArt = bmp
                artFound = true
                withContext(Dispatchers.Main) {
                    pushServiceState(playing = player?.isPlaying == true)
                }
            }
            artReading = false
        }
    }

    private fun extractArtwork(): Bitmap? {
        val m = runCatching { player?.media }.getOrNull() ?: return null
        return try {
            val url = m.getMeta(META_ARTWORK_URL)?.trim()?.takeIf { it.isNotEmpty() } ?: return null
            val path = Uri.parse(url).path ?: url.removePrefix("file://")
            BitmapFactory.decodeFile(path)
        } finally {
            runCatching { m.release() }
        }
    }

    /**
     * Monochrome album-art fallback used when a track has no embedded cover —
     * a simple vinyl record, drawn once and cached. (This is the only image slot
     * Android Auto's now-playing screen gives an app; it shows the real cover when
     * one is embedded, otherwise this.)
     */
    private fun placeholderArt(): Bitmap {
        placeholder?.let { return it }
        val size = 512
        val bmp = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
        val c = Canvas(bmp)
        c.drawColor(Color.rgb(18, 18, 18))
        val cx = size / 2f
        val cy = size / 2f
        val p = Paint(Paint.ANTI_ALIAS_FLAG)
        // Record body.
        p.style = Paint.Style.FILL
        p.color = Color.rgb(38, 38, 38)
        c.drawCircle(cx, cy, size * 0.34f, p)
        // Grooves.
        p.style = Paint.Style.STROKE
        p.strokeWidth = size * 0.006f
        p.color = Color.rgb(72, 72, 72)
        c.drawCircle(cx, cy, size * 0.30f, p)
        c.drawCircle(cx, cy, size * 0.245f, p)
        c.drawCircle(cx, cy, size * 0.19f, p)
        // Label + center hole.
        p.style = Paint.Style.FILL
        p.color = Color.rgb(224, 224, 224)
        c.drawCircle(cx, cy, size * 0.11f, p)
        p.color = Color.rgb(18, 18, 18)
        c.drawCircle(cx, cy, size * 0.022f, p)
        placeholder = bmp
        return bmp
    }

    private val serviceActions = PlaybackStateCompat.ACTION_PLAY or
        PlaybackStateCompat.ACTION_PAUSE or
        PlaybackStateCompat.ACTION_PLAY_PAUSE or
        PlaybackStateCompat.ACTION_SKIP_TO_NEXT or
        PlaybackStateCompat.ACTION_SKIP_TO_PREVIOUS or
        PlaybackStateCompat.ACTION_SEEK_TO or
        PlaybackStateCompat.ACTION_STOP

    private fun postBuffering(title: String) {
        if (!serviceOwns()) return
        session.setMetadata(
            MediaMetadataCompat.Builder()
                .putString(MediaMetadataCompat.METADATA_KEY_TITLE, title)
                .putBitmap(MediaMetadataCompat.METADATA_KEY_ALBUM_ART, currentArt ?: placeholderArt())
                .build()
        )
        session.setPlaybackState(
            PlaybackStateCompat.Builder()
                .setActions(serviceActions)
                .setState(PlaybackStateCompat.STATE_BUFFERING, 0L, 1f)
                .build()
        )
        mirrorToBridge(isPlaying = false, title = title, position = 0L, duration = 0L)
        runCatching { startForeground(NOTIF_ID, buildNotification()) }
    }

    private fun postError() {
        if (!serviceOwns()) return
        session.setPlaybackState(
            PlaybackStateCompat.Builder()
                .setActions(serviceActions)
                .setState(PlaybackStateCompat.STATE_ERROR, 0L, 1f)
                .setErrorMessage(
                    PlaybackStateCompat.ERROR_CODE_APP_ERROR,
                    "Could not play this item"
                )
                .build()
        )
    }

    private fun pushServiceState(playing: Boolean) {
        if (!serviceOwns()) return
        val mp = player ?: return
        val meta = currentMeta()
        session.setMetadata(meta)
        session.setPlaybackState(
            PlaybackStateCompat.Builder()
                .setActions(serviceActions)
                .setState(
                    if (playing) PlaybackStateCompat.STATE_PLAYING
                    else PlaybackStateCompat.STATE_PAUSED,
                    mp.time.coerceAtLeast(0L),
                    1f
                )
                .build()
        )
        mirrorToBridge(
            isPlaying = playing,
            title = meta.getString(MediaMetadataCompat.METADATA_KEY_TITLE).orEmpty(),
            position = mp.time.coerceAtLeast(0L),
            duration = mp.length.coerceAtLeast(0L)
        )
        runCatching { startForeground(NOTIF_ID, buildNotification()) }
    }

    /** Lightweight position tick — no metadata rebuild, no notification churn. */
    private fun pushPosition(playing: Boolean) {
        if (!serviceOwns()) return
        val mp = player ?: return
        session.setPlaybackState(
            PlaybackStateCompat.Builder()
                .setActions(serviceActions)
                .setState(
                    if (playing) PlaybackStateCompat.STATE_PLAYING
                    else PlaybackStateCompat.STATE_PAUSED,
                    mp.time.coerceAtLeast(0L),
                    1f
                )
                .build()
        )
        PlaybackBridge.positionMs = mp.time.coerceAtLeast(0L)
    }

    /** Keep the shared now-playing snapshot in sync so buildNotification() works. */
    private fun mirrorToBridge(isPlaying: Boolean, title: String, position: Long, duration: Long) {
        PlaybackBridge.title = title
        PlaybackBridge.artist = null
        PlaybackBridge.album = null
        PlaybackBridge.art = currentArt ?: placeholderArt()
        PlaybackBridge.isPlaying = isPlaying
        PlaybackBridge.positionMs = position
        PlaybackBridge.durationMs = duration
        PlaybackBridge.hasNext = queueIndex < queue.size - 1
        PlaybackBridge.hasPrev = queueIndex > 0
    }

    // ---------------------------------------------------------------------------
    // Foreground playback notification + session state (in-app mirror)
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

        // libvlc_meta_t indices (stable ABI values used by VLC for getMeta()).
        private const val META_TITLE = 0
        private const val META_ARTIST = 1
        private const val META_ALBUM = 4
        private const val META_ARTWORK_URL = 15
        private const val ART_MAX_ATTEMPTS = 12

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
