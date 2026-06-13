package com.typezero.pcloudtv.ui

import com.typezero.pcloudtv.data.MediaItem
import androidx.compose.material.icons.filled.SkipPrevious
import androidx.compose.material.icons.filled.SkipNext
import androidx.compose.material.icons.filled.RadioButtonUnchecked
import androidx.compose.material.icons.filled.RadioButtonChecked
import androidx.compose.material.icons.filled.ClosedCaption
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.border
import com.typezero.pcloudtv.ui.theme.Brand
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.draw.clip
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.clickable
import android.media.MediaMetadata
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.media.session.MediaSession
import android.media.session.PlaybackState
import android.net.Uri
import androidx.activity.compose.BackHandler
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.foundation.background
import androidx.compose.foundation.Image
import androidx.compose.foundation.focusable
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Forward10
import androidx.compose.material.icons.filled.MusicNote
import androidx.compose.material.icons.filled.Pause
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Replay10
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Slider
import androidx.compose.material3.SliderDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.input.key.Key
import androidx.compose.ui.input.key.KeyEventType
import androidx.compose.ui.input.key.key
import androidx.compose.ui.input.key.onKeyEvent
import androidx.compose.ui.input.key.type
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsControllerCompat
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.viewinterop.AndroidView
import com.typezero.pcloudtv.data.ApiResult
import kotlinx.coroutines.delay
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.coroutines.launch
import org.videolan.libvlc.LibVLC
import org.videolan.libvlc.Media
import org.videolan.libvlc.MediaPlayer
import org.videolan.libvlc.util.VLCVideoLayout

// libvlc_meta_t indices (stable ABI values used by VLC for getMeta()).
private const val META_TITLE = 0
private const val META_ARTIST = 1
private const val META_ALBUM = 4
private const val META_ARTWORK_URL = 15

@Composable
fun PlayerScreen(
    queue: List<MediaItem>,
    resolveUrl: suspend (MediaItem) -> ApiResult<String>,
    startIndex: Int = 0,
    playlistKey: String? = null,
    onExit: () -> Unit
) {
    BackHandler { onExit() }
    if (queue.isEmpty()) {
        Box(
            modifier = Modifier.fillMaxSize().background(Color.Black),
            contentAlignment = Alignment.Center
        ) {
            Text("Nothing to play", color = Color.White)
        }
        return
    }
    // Immersive fullscreen: hide the status + navigation bars while the player
    // is open so video isn't framed by the system UI on phones. Swiping from an
    // edge reveals them transiently; they're restored when the player closes.
    val activityContext = LocalContext.current
    DisposableEffect(Unit) {
        val window = activityContext.findActivity()?.window
        val controller = window?.let { WindowInsetsControllerCompat(it, it.decorView) }
        controller?.apply {
            systemBarsBehavior =
                WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
            hide(WindowInsetsCompat.Type.systemBars())
        }
        onDispose {
            controller?.show(WindowInsetsCompat.Type.systemBars())
        }
    }

    // The player instance is kept mounted for the whole queue; advancing the
    // index just swaps the media so playback never tears down between tracks.
    VlcPlayer(
        queue = queue,
        resolveUrl = resolveUrl,
        startIndex = startIndex.coerceIn(0, queue.size - 1),
        playlistKey = playlistKey,
        onExit = onExit
    )
}

private fun android.content.Context.findActivity(): android.app.Activity? {
    var c: android.content.Context = this
    while (c is android.content.ContextWrapper) {
        if (c is android.app.Activity) return c
        c = c.baseContext
    }
    return null
}

private fun guessContentType(name: String): String {
    val n = name.lowercase()
    return when {
        n.endsWith(".mp3") -> "audio/mpeg"
        n.endsWith(".m4a") || n.endsWith(".aac") || n.endsWith(".m4b") -> "audio/mp4"
        n.endsWith(".flac") -> "audio/flac"
        n.endsWith(".ogg") || n.endsWith(".oga") -> "audio/ogg"
        n.endsWith(".opus") -> "audio/opus"
        n.endsWith(".wav") -> "audio/wav"
        n.endsWith(".m4v") || n.endsWith(".mp4") -> "video/mp4"
        n.endsWith(".webm") -> "video/webm"
        n.endsWith(".mkv") -> "video/x-matroska"
        else -> "video/mp4"
    }
}

@Composable
private fun VlcPlayer(
    queue: List<com.typezero.pcloudtv.data.MediaItem>,
    resolveUrl: suspend (com.typezero.pcloudtv.data.MediaItem) -> ApiResult<String>,
    startIndex: Int,
    playlistKey: String? = null,
    onExit: () -> Unit
) {
    val context = LocalContext.current
    val store = remember { com.typezero.pcloudtv.data.SessionStore(context) }

    // For a playlist, resume at the track we left off on; otherwise honor startIndex.
    var index by remember {
        mutableStateOf(
            if (playlistKey != null && queue.isNotEmpty())
                store.getPlaylistIndex(playlistKey).coerceIn(0, queue.size - 1)
            else startIndex
        )
    }
    val current = queue.getOrNull(index)
    val title = current?.title ?: ""
    val queuePos = index + 1
    val queueCount = queue.size
    val hasPrev = index > 0
    val hasNext = index < queue.size - 1
    fun onPrev() { if (index > 0) index-- }
    fun onNext() { if (index < queue.size - 1) index++ }
    fun onEnded() {
        if (index < queue.size - 1) index++
        else {
            playlistKey?.let { store.clearPlaylistIndex(it) }  // finished the playlist → start fresh next time
            onExit()
        }
    }

    var loadError by remember { mutableStateOf<String?>(null) }

    val libVlc = remember {
        LibVLC(
            context,
            arrayListOf(
                "--network-caching=1500",
                "--http-reconnect",
                "--no-drop-late-frames",
                "--no-skip-frames",
                // Prefer English by language metadata (ISO codes), not display name.
                "--audio-language=eng,en,english",
                "--sub-language=eng,en,english"
            )
        )
    }
    val player = remember { MediaPlayer(libVlc) }

    var controlsVisible by remember { mutableStateOf(true) }
    var isPlaying by remember { mutableStateOf(true) }
    var positionMs by remember { mutableStateOf(0L) }
    var durationMs by remember { mutableStateOf(0L) }
    var interactionTick by remember { mutableStateOf(0) }
    var hasVideo by remember { mutableStateOf(false) }
    // True once VLC has reported whether the current track has a video track, so
    // the audio now-playing UI only appears for genuinely audio-only media (not
    // during the initial buffering of a video, when hasVideo is still false).
    var videoKnown by remember { mutableStateOf(false) }
    var resumed by remember { mutableStateOf(false) }
    var lastSavedAt by remember { mutableStateOf(0L) }
    var buffering by remember { mutableStateOf(true) }

    // Embedded metadata (ID3/tags) read live from the playing media. When present
    // these are shown on the audio now-playing screen in place of the raw
    // filename; ArtworkURL points VLC's extracted embedded cover art (a file://).
    var metaTitle by remember { mutableStateOf<String?>(null) }
    var metaArtist by remember { mutableStateOf<String?>(null) }
    var metaAlbum by remember { mutableStateOf<String?>(null) }
    var metaArtPath by remember { mutableStateOf<String?>(null) }
    var metaAttempts by remember { mutableStateOf(0) }

    // The event listener below is registered once, so anything it needs about the
    // CURRENT track must be read live (index is state-backed, so this is current).
    fun currentKey(): Long? = queue.getOrNull(index)?.fileId

    // Pull embedded tags off the currently-playing media. getMedia() hands back a
    // ref we must release. Only overwrite with non-blank values, so a later read
    // that momentarily returns null doesn't wipe a good tag we already captured.
    fun readMeta() {
        metaAttempts++
        val m = runCatching { player.media }.getOrNull() ?: return
        try {
            m.getMeta(META_TITLE)?.trim()?.takeIf { it.isNotEmpty() }?.let { metaTitle = it }
            m.getMeta(META_ARTIST)?.trim()?.takeIf { it.isNotEmpty() }?.let { metaArtist = it }
            m.getMeta(META_ALBUM)?.trim()?.takeIf { it.isNotEmpty() }?.let { metaAlbum = it }
            m.getMeta(META_ARTWORK_URL)?.trim()?.takeIf { it.isNotEmpty() }?.let { metaArtPath = it }
        } finally {
            runCatching { m.release() }
        }
    }

    // Persist resume position for the current file (audio or video on pCloud).
    fun persistPosition() {
        val key = currentKey() ?: return
        val pos = positionMs
        val dur = durationMs
        when {
            dur > 0 && pos > dur - 10_000 -> store.clearPosition(key)  // basically finished
            pos > 3_000 -> store.savePosition(key, pos)
            else -> store.clearPosition(key)
        }
    }

    // Seek to the saved position once, shortly after playback starts.
    fun resumeIfNeeded() {
        if (resumed) return
        resumed = true
        val key = currentKey() ?: return
        val saved = store.getPosition(key)
        if (saved > 3_000) player.time = saved
    }

    // Track picker state. Each entry is (id, label).
    var showTracks by remember { mutableStateOf(false) }
    var audioOptions by remember { mutableStateOf<List<Pair<Int, String>>>(emptyList()) }
    var subOptions by remember { mutableStateOf<List<Pair<Int, String>>>(emptyList()) }
    var currentAudio by remember { mutableStateOf(-1) }
    var currentSub by remember { mutableStateOf(-1) }

    fun refreshTrackLists() {
        audioOptions = player.audioTracks
            ?.filter { it.id != -1 }
            ?.map { it.id to (it.name ?: "Audio ${it.id}") }
            ?: emptyList()
        // Subtitles always offer an explicit "Off".
        subOptions = buildList {
            add(-1 to "Off")
            player.spuTracks?.filter { it.id != -1 }?.forEach {
                add(it.id to (it.name ?: "Subtitle ${it.id}"))
            }
        }
        currentAudio = player.audioTrack
        currentSub = player.spuTrack
    }

    val cast = com.typezero.pcloudtv.cast.rememberCastController()
    var resolvedUrl by remember { mutableStateOf<String?>(null) }
    val scope = rememberCoroutineScope()
    var lastCastReloadAt by remember { mutableStateOf(0L) }

    // Re-resolve a fresh pCloud URL and reload it on the cast device at the last
    // known position. pCloud stream URLs are time-limited, so after a pause the old
    // URL can be stale — a plain play() then fails. This recovers seamlessly.
    fun castReload() {
        val now = System.currentTimeMillis()
        if (now - lastCastReloadAt < 4_000) return  // debounce
        lastCastReloadAt = now
        val item = queue.getOrNull(index) ?: return
        val resumeAt = when {
            cast.positionMs > 3_000 -> cast.positionMs
            else -> currentKey()?.let { store.getPosition(it) } ?: 0L
        }
        scope.launch {
            when (val r = resolveUrl(item)) {
                is ApiResult.Ok -> cast.loadUrl(r.value, title, guessContentType(title), resumeAt)
                is ApiResult.Error -> loadError = r.message
            }
        }
    }

    fun reveal() {
        controlsVisible = true
        interactionTick++
    }

    fun togglePlay() {
        if (cast.isCasting) {
            when {
                cast.isRemotePlaying -> cast.pause()
                cast.canResume -> cast.play()           // still paused with media → simple resume
                else -> castReload()                    // media dropped/expired → reload fresh
            }
            reveal()
            return
        }
        if (player.isPlaying) player.pause() else player.play()
        reveal()
    }

    fun seekBy(deltaMs: Long) {
        if (cast.isCasting) { reveal(); return }  // seek handled on the TV's own controls
        val len = durationMs
        val target = (positionMs + deltaMs).coerceAtLeast(0L)
            .let { if (len > 0) it.coerceAtMost(len) else it }
        player.time = target
        positionMs = target
        reveal()
    }

    // --- Headset / Bluetooth media-button support ---
    // A MediaSession lets earbud and Bluetooth transport buttons (play/pause,
    // next, previous) drive playback even with the screen off. The callback is
    // created once, so it calls through these always-current lambdas.
    val onToggle = rememberUpdatedState<() -> Unit> { togglePlay() }
    val onNextBtn = rememberUpdatedState<() -> Unit> { onNext(); reveal() }
    val onPrevBtn = rememberUpdatedState<() -> Unit> { onPrev(); reveal() }
    var mediaSession by remember { mutableStateOf<MediaSession?>(null) }

    DisposableEffect(Unit) {
        val session = MediaSession(context, "pCloudTV").apply {
            setCallback(object : MediaSession.Callback() {
                override fun onPlay() { onToggle.value() }
                override fun onPause() { onToggle.value() }
                override fun onSkipToNext() { onNextBtn.value() }
                override fun onSkipToPrevious() { onPrevBtn.value() }
                override fun onSeekTo(pos: Long) { seekBy(pos - positionMs) }
            })
            isActive = true
        }
        mediaSession = session
        onDispose {
            session.isActive = false
            session.release()
            mediaSession = null
        }
    }

    // Keep the session's state/metadata in sync so the system routes buttons here
    // and shows the right title + play/pause on the lock screen / headset.
    LaunchedEffect(isPlaying, positionMs, durationMs, title, cast.isCasting, cast.isRemotePlaying) {
        val s = mediaSession ?: return@LaunchedEffect
        val playing = if (cast.isCasting) cast.isRemotePlaying else isPlaying
        s.setPlaybackState(
            PlaybackState.Builder()
                .setActions(
                    PlaybackState.ACTION_PLAY or PlaybackState.ACTION_PAUSE or
                        PlaybackState.ACTION_PLAY_PAUSE or
                        PlaybackState.ACTION_SKIP_TO_NEXT or
                        PlaybackState.ACTION_SKIP_TO_PREVIOUS or
                        PlaybackState.ACTION_SEEK_TO
                )
                .setState(
                    if (playing) PlaybackState.STATE_PLAYING else PlaybackState.STATE_PAUSED,
                    positionMs,
                    1f
                )
                .build()
        )
        s.setMetadata(
            MediaMetadata.Builder()
                .putString(MediaMetadata.METADATA_KEY_TITLE, title)
                .putLong(MediaMetadata.METADATA_KEY_DURATION, if (durationMs > 0) durationMs else 0L)
                .build()
        )
    }

    // Prefer English audio + English subtitles when the file has multiple tracks,
    // UNLESS the user has manually chosen a track this session — then that choice
    // sticks across tracks (e.g. binge a series in Spanish, or keep subs off).
    var tracksChosen by remember { mutableStateOf(false) }
    var prefAudioName by remember { mutableStateOf<String?>(null) }
    var prefSubName by remember { mutableStateOf<String?>(null) } // null=auto, "OFF"=subs off, else a track name
    fun selectEnglishTracks() {
        if (tracksChosen) return
        fun isEnglish(name: String?): Boolean {
            val n = name?.lowercase() ?: return false
            return n.contains("eng") || n.contains("english") ||
                Regex("\\b(en|eng)\\b").containsMatchIn(n)
        }
        // Audio: honor a manual choice (by track name) if set; else first English.
        val tracks = player.audioTracks
        val pa = prefAudioName
        if (pa != null && tracks != null) {
            val match = tracks.firstOrNull { it.name == pa }
                ?: tracks.firstOrNull { (it.name ?: "").contains(pa, ignoreCase = true) }
            if (match != null) player.audioTrack = match.id
            else tracks.firstOrNull { isEnglish(it.name) }?.let { player.audioTrack = it.id }
        } else {
            tracks?.firstOrNull { isEnglish(it.name) }?.let { player.audioTrack = it.id }
        }
        // Subtitles: honor a manual choice (a name, or "OFF"); else first English, else off.
        val subs = player.spuTracks
        if (subs != null && subs.isNotEmpty()) {
            val ps = prefSubName
            player.spuTrack = when {
                ps == "OFF" -> -1
                ps != null -> (subs.firstOrNull { it.name == ps }
                    ?: subs.firstOrNull { (it.name ?: "").contains(ps, ignoreCase = true) })?.id
                    ?: (subs.firstOrNull { isEnglish(it.name) }?.id ?: -1)
                else -> subs.firstOrNull { isEnglish(it.name) }?.id ?: -1
            }
        }
        // Mark done once tracks are actually available (lists non-null & populated).
        if ((player.audioTracks?.isNotEmpty() == true) ||
            (player.spuTracks?.isNotEmpty() == true)
        ) {
            tracksChosen = true
            refreshTrackLists()
        }
    }

    // VLC playback events → Compose state.
    DisposableEffect(player) {
        player.setEventListener { e ->
            when (e.type) {
                MediaPlayer.Event.Playing -> {
                    isPlaying = true
                    buffering = false
                    hasVideo = player.videoTracksCount > 0
                    videoKnown = true
                    resumeIfNeeded()
                    selectEnglishTracks()
                    readMeta()
                }
                MediaPlayer.Event.Buffering -> {
                    // e.buffering is 0..100; treat <100 as still buffering.
                    buffering = e.buffering < 100f
                }
                MediaPlayer.Event.Paused -> {
                    isPlaying = false
                    persistPosition()
                }
                MediaPlayer.Event.TimeChanged -> {
                    positionMs = e.timeChanged
                    if (!resumed) resumeIfNeeded()
                    if (!tracksChosen) selectEnglishTracks()
                    if (!hasVideo) hasVideo = player.videoTracksCount > 0
                    videoKnown = true
                    // Embedded cover art is often extracted a beat after playback
                    // starts, so keep re-reading early until we have it (capped).
                    if (metaArtPath == null && metaAttempts < 12) readMeta()
                    // Throttle resume-position saves to ~once every 5s.
                    val now = System.currentTimeMillis()
                    if (now - lastSavedAt > 5_000) {
                        lastSavedAt = now
                        persistPosition()
                    }
                }
                MediaPlayer.Event.LengthChanged -> { durationMs = e.lengthChanged; readMeta() }
                MediaPlayer.Event.ESAdded -> { selectEnglishTracks(); readMeta() }
                MediaPlayer.Event.EndReached -> {
                    currentKey()?.let { store.clearPosition(it) }  // finished → start fresh next time
                    onEnded()
                }
            }
        }
        onDispose { player.setEventListener(null) }
    }

    // Resolve the current track's URL and swap it onto the persistent player
    // whenever the index changes. This is what makes a queue work: advancing the
    // index swaps media on the SAME player — no teardown, so background audio and
    // the foreground service survive track changes.
    LaunchedEffect(index) {
        tracksChosen = false
        resumed = false
        hasVideo = false
        videoKnown = false
        buffering = true
        metaTitle = null
        metaArtist = null
        metaAlbum = null
        metaArtPath = null
        metaAttempts = 0
        // Remember which track of the playlist we're on (within-track position is
        // saved separately per file), so reopening the playlist resumes here.
        playlistKey?.let { store.savePlaylistIndex(it, index) }
        store.addRecent(queue.getOrNull(index)?.title ?: "", playlistKey, queue)
        currentAudio = -1
        currentSub = -1
        audioOptions = emptyList()
        subOptions = emptyList()
        positionMs = 0L
        durationMs = 0L
        loadError = null
        resolvedUrl = null
        val item = queue.getOrNull(index)
        if (item == null) {
            loadError = "Nothing to play"
            return@LaunchedEffect
        }
        when (val r = resolveUrl(item)) {
            is ApiResult.Ok -> resolvedUrl = r.value
            is ApiResult.Error -> loadError = r.message
        }
    }

    // Route the resolved URL to the active sink: the Chromecast if a Cast session
    // is up, otherwise the local VLC player. Re-runs if casting starts/stops, so
    // playback hands off cleanly in either direction.
    LaunchedEffect(resolvedUrl, cast.isCasting) {
        val url = resolvedUrl ?: return@LaunchedEffect
        if (cast.isCasting) {
            runCatching { if (player.isPlaying) player.pause() }
            buffering = false
            isPlaying = true
            val startMs = currentKey()?.let { store.getPosition(it) } ?: 0L
            cast.loadUrl(url, title, guessContentType(title), startMs)
        } else {
            val media = Media(libVlc, Uri.parse(url)).apply {
                setHWDecoderEnabled(true, false)
            }
            player.media = media
            media.release()
            player.play()
            isPlaying = true
        }
    }

    // When the Chromecast finishes an item, advance the queue (same as local end).
    // If it drops out with an error (e.g. a stale stream URL), reload a fresh one.
    LaunchedEffect(cast) {
        cast.onEnded = { onEnded() }
        cast.onNeedsReload = { castReload() }
    }

    // While casting, VLC's events don't fire, so mirror the remote position into our
    // state and persist it periodically — this is what lets video/music resume where
    // it left off even when playback happened on the TV.
    LaunchedEffect(cast.isCasting) {
        if (!cast.isCasting) return@LaunchedEffect
        while (true) {
            if (cast.positionMs > 0) {
                positionMs = cast.positionMs
                if (cast.durationMs > 0) durationMs = cast.durationMs
                persistPosition()
            }
            delay(5_000)
        }
    }

    // Release everything when leaving — and save the resume position first.
    DisposableEffect(Unit) {
        onDispose {
            persistPosition()
            player.stop()
            player.detachViews()
            player.release()
            libVlc.release()
        }
    }

    // Playback power management:
    //  - Hold a PARTIAL wake lock while playing so AUDIO keeps going with the
    //    screen off (music / audiobooks).
    //  - Only force the screen to stay on when there's VIDEO to watch.
    val activity = context as? android.app.Activity
    val wakeLock = remember {
        val pm = context.getSystemService(android.content.Context.POWER_SERVICE) as android.os.PowerManager
        pm.newWakeLock(android.os.PowerManager.PARTIAL_WAKE_LOCK, "pcloudtv:playback")
    }
    DisposableEffect(isPlaying, hasVideo, cast.isCasting) {
        val window = activity?.window
        if (isPlaying && !cast.isCasting) {
            if (!wakeLock.isHeld) wakeLock.acquire()
            if (hasVideo) {
                window?.addFlags(android.view.WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                // Video: don't keep the process alive in the background.
                com.typezero.pcloudtv.playback.PlaybackService.stop(context)
            } else {
                window?.clearFlags(android.view.WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                // Audio: keep the process alive so playback continues in the background.
                com.typezero.pcloudtv.playback.PlaybackService.start(context, title)
            }
        } else {
            // Paused, or casting (the Chromecast is doing the playing).
            if (wakeLock.isHeld) wakeLock.release()
            window?.clearFlags(android.view.WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
            com.typezero.pcloudtv.playback.PlaybackService.stop(context)
        }
        onDispose {
            if (wakeLock.isHeld) wakeLock.release()
            window?.clearFlags(android.view.WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
            com.typezero.pcloudtv.playback.PlaybackService.stop(context)
        }
    }

    // Leaving the app: VIDEO stops, but AUDIO keeps playing in the background
    // (the foreground service keeps the process alive). Casting is exempt — the
    // TV keeps playing either way.
    val lifecycleOwner = androidx.compose.ui.platform.LocalLifecycleOwner.current
    DisposableEffect(lifecycleOwner, hasVideo) {
        val obs = androidx.lifecycle.LifecycleEventObserver { _, event ->
            if (event == androidx.lifecycle.Lifecycle.Event.ON_STOP && !cast.isCasting && hasVideo) {
                runCatching { if (player.isPlaying) player.pause() }
                isPlaying = false
            }
        }
        lifecycleOwner.lifecycle.addObserver(obs)
        onDispose { lifecycleOwner.lifecycle.removeObserver(obs) }
    }

    // Audio focus: pause when a phone call or another media app takes over.
    val audioManager = remember {
        context.getSystemService(android.content.Context.AUDIO_SERVICE) as AudioManager
    }
    val focusRequest = remember {
        AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN)
            .setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_MEDIA)
                    .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
                    .build()
            )
            .setOnAudioFocusChangeListener { change ->
                if (change == AudioManager.AUDIOFOCUS_LOSS ||
                    change == AudioManager.AUDIOFOCUS_LOSS_TRANSIENT
                ) {
                    runCatching { if (player.isPlaying) player.pause() }
                    isPlaying = false
                }
            }
            .build()
    }
    DisposableEffect(isPlaying, cast.isCasting) {
        if (isPlaying && !cast.isCasting) {
            runCatching { audioManager.requestAudioFocus(focusRequest) }
        } else {
            runCatching { audioManager.abandonAudioFocusRequest(focusRequest) }
        }
        onDispose { runCatching { audioManager.abandonAudioFocusRequest(focusRequest) } }
    }

    // Auto-hide controls after inactivity (only while playing VIDEO — the audio
    // now-playing screen keeps its transport visible like a music app).
    LaunchedEffect(controlsVisible, interactionTick, isPlaying, hasVideo) {
        if (controlsVisible && isPlaying && hasVideo) {
            delay(4000)
            controlsVisible = false
        }
    }

    val focus = remember { FocusRequester() }
    // Return focus to the player surface whenever the picker is closed.
    LaunchedEffect(showTracks) { if (!showTracks) runCatching { focus.requestFocus() } }

    Box(
        modifier = Modifier
            .fillMaxSize()
            .focusRequester(focus)
            .focusable()
            .onKeyEvent { e ->
                if (e.type != KeyEventType.KeyUp) return@onKeyEvent false
                // While the track picker is open, let the dialog handle navigation.
                if (showTracks) return@onKeyEvent false
                if (!controlsVisible) {
                    reveal(); return@onKeyEvent true
                }
                when (e.key) {
                    Key.DirectionCenter, Key.Enter, Key.Spacebar, Key.MediaPlayPause -> {
                        togglePlay(); true
                    }
                    Key.DirectionLeft, Key.MediaRewind -> {
                        seekBy(-10_000); true
                    }
                    Key.DirectionRight, Key.MediaFastForward -> {
                        seekBy(10_000); true
                    }
                    // Up (or the Menu/options key) opens audio + subtitle selection.
                    Key.DirectionUp, Key.Menu -> {
                        refreshTrackLists(); showTracks = true; true
                    }
                    Key.DirectionDown -> {
                        reveal(); true
                    }
                    Key.MediaNext -> {
                        if (hasNext) onNext(); true
                    }
                    Key.MediaPrevious -> {
                        if (hasPrev) onPrev(); true
                    }
                    else -> false
                }
            }
            .pointerInput(Unit) {
                detectTapGestures(onTap = { if (controlsVisible) controlsVisible = false else reveal() })
            }
    ) {
        AndroidView(
            modifier = Modifier.fillMaxSize(),
            factory = { ctx ->
                VLCVideoLayout(ctx).also { layout ->
                    player.attachViews(layout, null, false, false)
                }
            }
        )

        // Audio-only track → a proper now-playing screen instead of a black
        // surface. This Compose UI also survives rotation and app-switching, so
        // audio no longer drops to a black void when you come back to it.
        val showAudioUi = videoKnown && !hasVideo && !cast.isCasting && loadError == null
        if (showAudioUi) {
            // Prefer embedded tags; fall back to a cleaned-up filename.
            val displayTitle = metaTitle ?: prettifyName(title)
            val displaySubtitle = listOfNotNull(metaArtist, metaAlbum)
                .distinct().joinToString(" • ").ifBlank { null }
            AudioNowPlaying(
                title = displayTitle,
                subtitle = displaySubtitle,
                artPath = metaArtPath,
                queuePos = queuePos,
                queueCount = queueCount,
                isPlaying = isPlaying,
                positionMs = positionMs,
                durationMs = durationMs,
                hasPrev = hasPrev,
                hasNext = hasNext,
                buffering = buffering,
                onPrev = { onPrev() },
                onNext = { onNext() },
                onTogglePlay = { togglePlay() },
                onSeekBack = { seekBy(-10_000) },
                onSeekForward = { seekBy(10_000) },
                onScrub = { fraction ->
                    if (durationMs > 0) {
                        val t = (fraction * durationMs).toLong()
                        player.time = t
                        positionMs = t
                        reveal()
                    }
                }
            )
        }

        // Buffering spinner while the stream is loading/stalled.
        if (loadError != null) {
            Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                Text(
                    "Couldn't play \"$title\": $loadError",
                    color = MaterialTheme.colorScheme.error,
                    modifier = Modifier.padding(40.dp)
                )
            }
        } else if (cast.isCasting) {
            Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                Text(
                    "Casting to ${cast.deviceName ?: "your TV"}",
                    color = Brand.TextHi,
                    fontSize = 16.sp,
                    modifier = Modifier.padding(40.dp)
                )
            }
        } else if (buffering && !showAudioUi) {
            Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                CircularProgressIndicator(color = Brand.Accent)
            }
        }

        // Cast button for the AUDIO now-playing screen only — the video controls
        // embed their own Cast button in the top bar. Audio art is centred, so the
        // top-right corner is free here.
        if (cast.isAvailable) {
            androidx.compose.animation.AnimatedVisibility(
                visible = controlsVisible && !showTracks && !hasVideo,
                enter = fadeIn(),
                exit = fadeOut(),
                modifier = Modifier.align(Alignment.TopEnd)
            ) {
                com.typezero.pcloudtv.cast.CastButton(
                    modifier = Modifier.padding(20.dp).size(40.dp)
                )
            }
        }

        AnimatedVisibility(
            visible = controlsVisible && !showTracks && hasVideo,
            enter = fadeIn(),
            exit = fadeOut()
        ) {
            Controls(
                title = title,
                castAvailable = cast.isAvailable,
                queuePos = queuePos,
                queueCount = queueCount,
                isPlaying = if (cast.isCasting) cast.isRemotePlaying else isPlaying,
                positionMs = positionMs,
                durationMs = durationMs,
                hasPrev = hasPrev,
                hasNext = hasNext,
                onPrev = { onPrev() },
                onNext = { onNext() },
                onTogglePlay = { togglePlay() },
                onSeekBack = { seekBy(-10_000) },
                onSeekForward = { seekBy(10_000) },
                onTracks = {
                    refreshTrackLists()
                    showTracks = true
                },
                onScrub = { fraction ->
                    if (durationMs > 0) {
                        val t = (fraction * durationMs).toLong()
                        player.time = t
                        positionMs = t
                        reveal()
                    }
                }
            )
        }

        AnimatedVisibility(
            visible = showTracks,
            enter = fadeIn(),
            exit = fadeOut()
        ) {
            TrackPicker(
                audio = audioOptions,
                subs = subOptions,
                currentAudio = currentAudio,
                currentSub = currentSub,
                onPickAudio = { id ->
                    player.audioTrack = id
                    currentAudio = id
                    prefAudioName = audioOptions.firstOrNull { it.first == id }?.second
                },
                onPickSub = { id ->
                    player.spuTrack = id
                    currentSub = id
                    prefSubName = if (id == -1) "OFF"
                    else subOptions.firstOrNull { it.first == id }?.second
                },
                onClose = { showTracks = false; reveal() }
            )
        }
    }
}

@Composable
private fun Controls(
    title: String,
    castAvailable: Boolean,
    queuePos: Int,
    queueCount: Int,
    isPlaying: Boolean,
    positionMs: Long,
    durationMs: Long,
    hasPrev: Boolean,
    hasNext: Boolean,
    onPrev: () -> Unit,
    onNext: () -> Unit,
    onTogglePlay: () -> Unit,
    onSeekBack: () -> Unit,
    onSeekForward: () -> Unit,
    onTracks: () -> Unit,
    onScrub: (Float) -> Unit
) {
    Box(modifier = Modifier.fillMaxSize().background(Brand.controlScrim)) {

        // Top header: title on its own full-width line (so long filenames show in
        // full before truncating), with the Cast + Tracks buttons grouped on a row
        // directly beneath it.
        Column(
            modifier = Modifier
                .align(Alignment.TopStart)
                .fillMaxWidth()
                .padding(start = 20.dp, end = 20.dp, top = 14.dp)
        ) {
            if (queueCount > 1) {
                Text(
                    "TRACK $queuePos / $queueCount",
                    color = Brand.Accent,
                    fontSize = 11.sp,
                    fontWeight = FontWeight.Bold
                )
                Spacer(Modifier.height(2.dp))
            }
            Text(
                title,
                color = Color.White,
                fontSize = 18.sp,
                fontWeight = FontWeight.SemiBold,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis
            )

            Spacer(Modifier.height(12.dp))

            Row(verticalAlignment = Alignment.CenterVertically) {
                if (castAvailable) {
                    com.typezero.pcloudtv.cast.CastButton(modifier = Modifier.size(40.dp))
                    Spacer(Modifier.width(12.dp))
                }

                // Audio / subtitle track selector.
                Box(
                    modifier = Modifier
                        .clip(RoundedCornerShape(12.dp))
                        .background(Color(0x33FFFFFF))
                        .clickable(onClick = onTracks)
                        .padding(horizontal = 14.dp, vertical = 10.dp),
                    contentAlignment = Alignment.Center
                ) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Icon(Icons.Filled.ClosedCaption, contentDescription = "Audio & subtitles",
                            tint = Color.White, modifier = Modifier.size(22.dp))
                        Spacer(Modifier.width(8.dp))
                        Text("Tracks", color = Color.White, fontSize = 14.sp)
                    }
                }
            }
        }

        Column(
            modifier = Modifier
                .align(Alignment.BottomCenter)
                .fillMaxWidth()
                .padding(horizontal = 24.dp, vertical = 22.dp)
        ) {
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.Center,
                modifier = Modifier.fillMaxWidth()
            ) {
                if (hasPrev || hasNext) {
                    IconButton(onClick = onPrev, enabled = hasPrev) {
                        Icon(
                            Icons.Filled.SkipPrevious, contentDescription = "Previous",
                            tint = if (hasPrev) Color.White else Color(0x55FFFFFF),
                            modifier = Modifier.size(34.dp)
                        )
                    }
                    Spacer(Modifier.width(16.dp))
                }
                IconButton(onClick = onSeekBack) {
                    Icon(
                        Icons.Filled.Replay10, contentDescription = "Back 10s",
                        tint = Color.White, modifier = Modifier.size(38.dp)
                    )
                }
                Spacer(Modifier.width(28.dp))
                Box(
                    modifier = Modifier
                        .size(64.dp)
                        .clip(CircleShape)
                        .background(Brand.Accent)
                        .clickable(onClick = onTogglePlay),
                    contentAlignment = Alignment.Center
                ) {
                    Icon(
                        if (isPlaying) Icons.Filled.Pause else Icons.Filled.PlayArrow,
                        contentDescription = if (isPlaying) "Pause" else "Play",
                        tint = MaterialTheme.colorScheme.onPrimary,
                        modifier = Modifier.size(36.dp)
                    )
                }
                Spacer(Modifier.width(28.dp))
                IconButton(onClick = onSeekForward) {
                    Icon(
                        Icons.Filled.Forward10, contentDescription = "Forward 10s",
                        tint = Color.White, modifier = Modifier.size(38.dp)
                    )
                }
                if (hasPrev || hasNext) {
                    Spacer(Modifier.width(16.dp))
                    IconButton(onClick = onNext, enabled = hasNext) {
                        Icon(
                            Icons.Filled.SkipNext, contentDescription = "Next",
                            tint = if (hasNext) Color.White else Color(0x55FFFFFF),
                            modifier = Modifier.size(34.dp)
                        )
                    }
                }
            }

            Spacer(Modifier.height(6.dp))
            Row(
                verticalAlignment = Alignment.CenterVertically,
                modifier = Modifier.fillMaxWidth()
            ) {
                Text(formatTime(positionMs), color = Color.White, fontSize = 13.sp)
                Slider(
                    value = if (durationMs > 0) (positionMs.toFloat() / durationMs) else 0f,
                    onValueChange = onScrub,
                    enabled = durationMs > 0,
                    colors = SliderDefaults.colors(
                        thumbColor = Brand.Accent,
                        activeTrackColor = Brand.Accent,
                        inactiveTrackColor = Color(0x55FFFFFF)
                    ),
                    modifier = Modifier.weight(1f).padding(horizontal = 14.dp)
                )
                Text(formatTime(durationMs), color = Color.White, fontSize = 13.sp)
            }
        }
    }
}

@Composable
private fun AudioNowPlaying(
    title: String,
    subtitle: String?,
    artPath: String?,
    queuePos: Int,
    queueCount: Int,
    isPlaying: Boolean,
    positionMs: Long,
    durationMs: Long,
    hasPrev: Boolean,
    hasNext: Boolean,
    buffering: Boolean,
    onPrev: () -> Unit,
    onNext: () -> Unit,
    onTogglePlay: () -> Unit,
    onSeekBack: () -> Unit,
    onSeekForward: () -> Unit,
    onScrub: (Float) -> Unit
) {
    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(Brush.verticalGradient(listOf(Brand.Surface, Brand.Bg)))
    ) {
        // Hero: album-art placeholder + title, centered.
        Column(
            modifier = Modifier.align(Alignment.Center).padding(horizontal = 32.dp),
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            // Decode embedded cover art off the main thread; null → placeholder.
            val artBitmap by produceState<android.graphics.Bitmap?>(null, artPath) {
                value = artPath?.let { p ->
                    withContext(Dispatchers.IO) {
                        runCatching {
                            val path = Uri.parse(p).path ?: p.removePrefix("file://")
                            android.graphics.BitmapFactory.decodeFile(path)
                        }.getOrNull()
                    }
                }
            }
            Box(
                modifier = Modifier
                    .size(200.dp)
                    .clip(RoundedCornerShape(28.dp))
                    .background(Brand.Bg)
                    .border(1.dp, Brand.Stroke, RoundedCornerShape(28.dp)),
                contentAlignment = Alignment.Center
            ) {
                val bmp = artBitmap
                when {
                    bmp != null -> Image(
                        bitmap = bmp.asImageBitmap(),
                        contentDescription = null,
                        contentScale = ContentScale.Crop,
                        modifier = Modifier.fillMaxSize().clip(RoundedCornerShape(28.dp))
                    )
                    buffering -> CircularProgressIndicator(color = Brand.Accent)
                    else -> Icon(
                        Icons.Filled.MusicNote,
                        contentDescription = null,
                        tint = Brand.Accent,
                        modifier = Modifier.size(96.dp)
                    )
                }
            }
            Spacer(Modifier.height(28.dp))
            if (queueCount > 1) {
                Text(
                    "TRACK $queuePos / $queueCount",
                    color = Brand.Accent,
                    fontSize = 12.sp,
                    fontWeight = FontWeight.Bold
                )
                Spacer(Modifier.height(6.dp))
            }
            Text(
                title,
                color = Brand.TextHi,
                fontSize = 20.sp,
                fontWeight = FontWeight.SemiBold,
                maxLines = 2,
                textAlign = TextAlign.Center
            )
            if (subtitle != null) {
                Spacer(Modifier.height(6.dp))
                Text(
                    subtitle,
                    color = Brand.TextMid,
                    fontSize = 14.sp,
                    maxLines = 1,
                    textAlign = TextAlign.Center
                )
            }
        }

        // Transport + scrubber, pinned to the bottom and always visible.
        Column(
            modifier = Modifier
                .align(Alignment.BottomCenter)
                .fillMaxWidth()
                .padding(horizontal = 24.dp, vertical = 22.dp)
        ) {
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.Center,
                modifier = Modifier.fillMaxWidth()
            ) {
                if (hasPrev || hasNext) {
                    IconButton(onClick = onPrev, enabled = hasPrev) {
                        Icon(
                            Icons.Filled.SkipPrevious, contentDescription = "Previous",
                            tint = if (hasPrev) Color.White else Color(0x55FFFFFF),
                            modifier = Modifier.size(34.dp)
                        )
                    }
                    Spacer(Modifier.width(16.dp))
                }
                IconButton(onClick = onSeekBack) {
                    Icon(
                        Icons.Filled.Replay10, contentDescription = "Back 10s",
                        tint = Color.White, modifier = Modifier.size(38.dp)
                    )
                }
                Spacer(Modifier.width(28.dp))
                Box(
                    modifier = Modifier
                        .size(64.dp)
                        .clip(CircleShape)
                        .background(Brand.Accent)
                        .clickable(onClick = onTogglePlay),
                    contentAlignment = Alignment.Center
                ) {
                    Icon(
                        if (isPlaying) Icons.Filled.Pause else Icons.Filled.PlayArrow,
                        contentDescription = if (isPlaying) "Pause" else "Play",
                        tint = MaterialTheme.colorScheme.onPrimary,
                        modifier = Modifier.size(36.dp)
                    )
                }
                Spacer(Modifier.width(28.dp))
                IconButton(onClick = onSeekForward) {
                    Icon(
                        Icons.Filled.Forward10, contentDescription = "Forward 10s",
                        tint = Color.White, modifier = Modifier.size(38.dp)
                    )
                }
                if (hasPrev || hasNext) {
                    Spacer(Modifier.width(16.dp))
                    IconButton(onClick = onNext, enabled = hasNext) {
                        Icon(
                            Icons.Filled.SkipNext, contentDescription = "Next",
                            tint = if (hasNext) Color.White else Color(0x55FFFFFF),
                            modifier = Modifier.size(34.dp)
                        )
                    }
                }
            }

            Spacer(Modifier.height(6.dp))
            Row(
                verticalAlignment = Alignment.CenterVertically,
                modifier = Modifier.fillMaxWidth()
            ) {
                Text(formatTime(positionMs), color = Color.White, fontSize = 13.sp)
                Slider(
                    value = if (durationMs > 0) (positionMs.toFloat() / durationMs) else 0f,
                    onValueChange = onScrub,
                    enabled = durationMs > 0,
                    colors = SliderDefaults.colors(
                        thumbColor = Brand.Accent,
                        activeTrackColor = Brand.Accent,
                        inactiveTrackColor = Color(0x55FFFFFF)
                    ),
                    modifier = Modifier.weight(1f).padding(horizontal = 14.dp)
                )
                Text(formatTime(durationMs), color = Color.White, fontSize = 13.sp)
            }
        }
    }
}

private fun prettifyName(raw: String): String {
    // Drop a trailing audio extension, a leading track number, turn separators
    // into spaces (artist–title dash → em dash), and title-case each word.
    var s = raw.replace(
        Regex("\\.(mp3|m4a|aac|flac|ogg|oga|opus|wav|m4b|wma)$", RegexOption.IGNORE_CASE), ""
    )
    s = s.replace(Regex("^\\s*\\d{1,3}\\s*[-_.]\\s*"), "")
    s = s.replace('_', ' ')
    s = s.replace(Regex("\\s*-\\s*"), " — ")
    s = s.replace(Regex("\\s+"), " ").trim()
    if (s.isBlank()) return raw
    return s.split(' ').joinToString(" ") { w ->
        if (w == "—") w else w.replaceFirstChar { c -> c.uppercaseChar() }
    }
}

private fun formatTime(ms: Long): String {
    if (ms <= 0) return "0:00"
    val totalSec = ms / 1000
    val h = totalSec / 3600
    val m = (totalSec % 3600) / 60
    val s = totalSec % 60
    return if (h > 0) "%d:%02d:%02d".format(h, m, s) else "%d:%02d".format(m, s)
}

@Composable
private fun TrackPicker(
    audio: List<Pair<Int, String>>,
    subs: List<Pair<Int, String>>,
    currentAudio: Int,
    currentSub: Int,
    onPickAudio: (Int) -> Unit,
    onPickSub: (Int) -> Unit,
    onClose: () -> Unit
) {
    BackHandler { onClose() }

    val firstFocus = remember { FocusRequester() }
    LaunchedEffect(Unit) { runCatching { firstFocus.requestFocus() } }
    val audioEmpty = audio.isEmpty()

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(Color(0xCC000000))
            .clickable(onClick = onClose),
        contentAlignment = Alignment.Center
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .widthIn(max = 560.dp)
                .padding(28.dp)
                .clip(RoundedCornerShape(20.dp))
                .background(Brand.Surface)
                .border(1.dp, Brand.Stroke, RoundedCornerShape(20.dp))
                .padding(22.dp)
                .verticalScroll(rememberScrollState())
        ) {
            Text("Audio", color = Brand.Accent, fontSize = 14.sp,
                fontWeight = FontWeight.SemiBold)
            Spacer(Modifier.height(8.dp))
            if (audioEmpty) {
                Text("No selectable audio tracks", color = Brand.TextLow, fontSize = 13.sp)
            } else {
                audio.forEachIndexed { i, (id, label) ->
                    TrackRow(
                        label, id == currentAudio,
                        modifier = if (i == 0) Modifier.focusRequester(firstFocus) else Modifier
                    ) { onPickAudio(id) }
                }
            }

            Spacer(Modifier.height(18.dp))
            Text("Subtitles", color = Brand.Accent, fontSize = 14.sp,
                fontWeight = FontWeight.SemiBold)
            Spacer(Modifier.height(8.dp))
            subs.forEachIndexed { i, (id, label) ->
                TrackRow(
                    label, id == currentSub,
                    modifier = if (audioEmpty && i == 0) Modifier.focusRequester(firstFocus)
                    else Modifier
                ) { onPickSub(id) }
            }

            Spacer(Modifier.height(20.dp))
            TrackRow("Close", selected = false, accent = true) { onClose() }
        }
    }
}

@Composable
private fun TrackRow(
    label: String,
    selected: Boolean,
    modifier: Modifier = Modifier,
    accent: Boolean = false,
    onClick: () -> Unit
) {
    var focused by remember { mutableStateOf(false) }
    val interaction = remember { MutableInteractionSource() }
    val bg = when {
        focused -> Brand.SurfaceFocused
        selected -> Brand.Accent.copy(alpha = 0.14f)
        else -> Color.Transparent
    }
    Row(
        modifier = modifier
            .fillMaxWidth()
            .padding(vertical = 3.dp)
            .clip(RoundedCornerShape(10.dp))
            .background(bg)
            .border(
                width = if (focused) 1.5.dp else 0.dp,
                color = if (focused) Brand.Accent else Color.Transparent,
                shape = RoundedCornerShape(10.dp)
            )
            .onFocusChanged { focused = it.isFocused }
            .focusable(interactionSource = interaction)
            .clickable(interactionSource = interaction, indication = null, onClick = onClick)
            .padding(horizontal = 16.dp, vertical = 13.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Icon(
            if (selected) Icons.Filled.RadioButtonChecked else Icons.Filled.RadioButtonUnchecked,
            contentDescription = null,
            tint = if (selected || accent) Brand.Accent else Brand.TextLow,
            modifier = Modifier.size(18.dp)
        )
        Spacer(Modifier.width(12.dp))
        Text(
            label,
            color = if (accent) Brand.Accent else Brand.TextHi,
            fontSize = 15.sp,
            fontWeight = if (selected) FontWeight.SemiBold else FontWeight.Normal
        )
    }
}
