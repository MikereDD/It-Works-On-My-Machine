package com.typezero.cloudplayer.ui

import com.typezero.cloudplayer.data.MediaItem
import androidx.compose.material.icons.filled.SkipPrevious
import androidx.compose.material.icons.filled.SkipNext
import androidx.compose.material.icons.filled.FirstPage
import androidx.compose.material.icons.filled.LastPage
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
import com.typezero.cloudplayer.ui.theme.Brand
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.draw.clip
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.clickable
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.net.Uri
import androidx.activity.compose.BackHandler
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.animation.AnimatedVisibilityScope
import androidx.compose.animation.ExperimentalAnimationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.Image
import androidx.compose.foundation.focusable
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.fillMaxHeight
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
import androidx.compose.material3.ExperimentalMaterial3Api
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
import androidx.compose.foundation.Canvas
import androidx.compose.runtime.withFrameNanos
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import kotlin.math.PI
import kotlin.math.sin
import kotlin.math.sqrt
import android.Manifest
import android.media.audiofx.Visualizer
import android.os.SystemClock
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.core.content.ContextCompat
import android.content.pm.PackageManager
import android.content.Context
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.input.key.Key
import androidx.compose.ui.input.key.KeyEventType
import androidx.compose.ui.input.key.key
import androidx.compose.ui.input.key.onKeyEvent
import androidx.compose.ui.input.key.onPreviewKeyEvent
import androidx.compose.ui.input.key.type
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsControllerCompat
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.viewinterop.AndroidView
import com.typezero.cloudplayer.data.ApiResult
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
    fetchArt: suspend (String) -> ByteArray? = { null },
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
        fetchArt = fetchArt,
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
    queue: List<com.typezero.cloudplayer.data.MediaItem>,
    resolveUrl: suspend (com.typezero.cloudplayer.data.MediaItem) -> ApiResult<String>,
    startIndex: Int,
    playlistKey: String? = null,
    fetchArt: suspend (String) -> ByteArray? = { null },
    onExit: () -> Unit
) {
    val context = LocalContext.current
    val store = remember { com.typezero.cloudplayer.data.SessionStore(context) }

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

    // Generate an audio session id and make LibVLC create its AudioTrack in it,
    // so the spectrum Visualizer can attach to exactly this app's output. (Same
    // mechanism the official VLC-Android app uses for its equalizer/visualizer.)
    val audioSessionId = remember {
        runCatching {
            val am = context.getSystemService(Context.AUDIO_SERVICE) as android.media.AudioManager
            am.generateAudioSessionId()
        }.getOrDefault(0).also { VizSession.id = it }
    }

    val libVlc = remember {
        LibVLC(
            context,
            arrayListOf(
                "--network-caching=1500",
                "--http-reconnect",
                // Allow VLC to drop late frames to stay in sync. Forcing every frame
                // (--no-drop-late-frames/--no-skip-frames) makes 2160p stutter badly
                // whenever decode or network can't keep pace.
                // Prefer English by language metadata (ISO codes), not display name.
                "--audio-language=eng,en,english",
                "--sub-language=eng,en,english",
                // Route audio through AudioTrack in our session so the visualizer can
                // tap it (the session-id option only applies to the audiotrack output).
                "--aout=audiotrack",
                "--audiotrack-session-id=$audioSessionId"
            )
        )
    }
    val player = remember { MediaPlayer(libVlc) }
    val isTvDevice = remember {
        context.packageManager.hasSystemFeature(PackageManager.FEATURE_LEANBACK)
    }

    // Android TV uses the visible VLC player screen as the single playback owner.
    // The Android Auto / foreground audio MediaSession layer can receive stale
    // media-button, focus, or lifecycle callbacks after switching items and pause
    // the TV player. Keep that layer fully disabled on TV; phones, tablets,
    // Bluetooth, lock screen, and Android Auto still use it normally.
    LaunchedEffect(isTvDevice) {
        if (isTvDevice) {
            com.typezero.cloudplayer.playback.PlaybackBridge.clearControls()
            com.typezero.cloudplayer.playback.PlaybackBridge.serviceOwnsPlayback = false
            com.typezero.cloudplayer.playback.PlaybackService.stop(context)
        }
    }

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
        // Single files always resume. Named playlists also resume within the
        // saved track; ad-hoc folder queues still start each new file fresh.
        if (queue.size > 1 && playlistKey == null) return
        val key = currentKey() ?: return
        val saved = store.getPosition(key)
        if (saved > 3_000) player.time = saved
    }

    // Track picker state. Each entry is (id, label).
    var showTracks by remember { mutableStateOf(false) }

    // Video decoding: hardware by default on phone, software by default on TV (this
    // class of MediaTek TV decoder fails its OMX output-buffer/surface setup for both
    // H.264 and HEVC, so HW is unusable there). Persisted once the user picks. Toggling
    // reloads the current file; pendingSeekMs carries the position across the reload.
    var swDecode by remember {
        val tv = context.packageManager.hasSystemFeature(PackageManager.FEATURE_LEANBACK)
        mutableStateOf(store.getSoftwareDecode(defaultValue = tv))
    }
    var pendingSeekMs by remember { mutableStateOf(0L) }
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

    val cast = com.typezero.cloudplayer.cast.rememberCastController()
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

    fun playLocal() {
        if (cast.isCasting) {
            when {
                cast.isRemotePlaying -> Unit
                cast.canResume -> cast.play()           // still paused with media → simple resume
                else -> castReload()                    // media dropped/expired → reload fresh
            }
            reveal()
            return
        }
        if (!player.isPlaying) {
            player.play()
            isPlaying = true
        }
        reveal()
    }

    fun pauseLocal() {
        if (cast.isCasting) {
            if (cast.isRemotePlaying) cast.pause()
            reveal()
            return
        }
        if (player.isPlaying) {
            player.pause()
            isPlaying = false
        }
        reveal()
    }

    fun togglePlay() {
        if (cast.isCasting) {
            if (cast.isRemotePlaying) pauseLocal() else playLocal()
            return
        }
        if (player.isPlaying) pauseLocal() else playLocal()
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

    // --- Media session lives in the foreground PlaybackService (it owns the
    // MediaSessionCompat + MediaStyle notification). Here we expose always-current
    // controls and push now-playing state through the bridge, so the lock screen,
    // Bluetooth, and the car can show "now playing" and drive the transport. ---
    val onPlayCmd = rememberUpdatedState<() -> Unit> { playLocal() }
    val onPauseCmd = rememberUpdatedState<() -> Unit> { pauseLocal() }
    val onNextBtn = rememberUpdatedState<() -> Unit> { onNext(); reveal() }
    val onPrevBtn = rememberUpdatedState<() -> Unit> { onPrev(); reveal() }
    val onSeekToMs = rememberUpdatedState<(Long) -> Unit> { pos -> seekBy(pos - positionMs) }
    val onStopCmd = rememberUpdatedState<() -> Unit> { pauseLocal() }

    DisposableEffect(isTvDevice) {
        if (!isTvDevice) {
            com.typezero.cloudplayer.playback.PlaybackBridge.apply {
                onPlay = { onPlayCmd.value() }
                onPause = { onPauseCmd.value() }
                onNext = { onNextBtn.value() }
                onPrev = { onPrevBtn.value() }
                onSeekTo = { p -> onSeekToMs.value(p) }
                onStop = { onStopCmd.value() }
            }
        } else {
            com.typezero.cloudplayer.playback.PlaybackBridge.clearControls()
            com.typezero.cloudplayer.playback.PlaybackBridge.serviceOwnsPlayback = false
            com.typezero.cloudplayer.playback.PlaybackService.stop(context)
        }
        onDispose {
            com.typezero.cloudplayer.playback.PlaybackBridge.clearControls()
            if (isTvDevice) com.typezero.cloudplayer.playback.PlaybackService.stop(context)
        }
    }

    // Decode embedded cover art (if any) for the lock-screen / Bluetooth / car art.
    val sessionArt by produceState<android.graphics.Bitmap?>(null, metaArtPath) {
        value = metaArtPath?.let { p ->
            withContext(Dispatchers.IO) {
                runCatching {
                    val path = Uri.parse(p).path ?: p.removePrefix("file://")
                    android.graphics.BitmapFactory.decodeFile(path)
                }.getOrNull()
            }
        }
    }

    // Push now-playing state to the service. Deliberately NOT keyed on positionMs
    // (which ticks constantly) — the system interpolates position from the playback
    // state's 1x speed, so we refresh only on real changes to avoid notification churn.
    LaunchedEffect(
        title, metaArtist, metaAlbum, sessionArt, isPlaying,
        hasNext, hasPrev, durationMs, cast.isCasting, cast.isRemotePlaying
    ) {
        val b = com.typezero.cloudplayer.playback.PlaybackBridge
        b.title = title
        b.artist = metaArtist
        b.album = metaAlbum
        b.art = sessionArt
        b.durationMs = if (durationMs > 0) durationMs else 0L
        b.positionMs = positionMs
        b.isPlaying = if (cast.isCasting) cast.isRemotePlaying else isPlaying
        b.hasNext = hasNext
        b.hasPrev = hasPrev
        b.notifyChanged()
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

    // Embedded cover art. LibVLC rarely surfaces it for network streams, so pull
    // the ID3v2 APIC ourselves, cache it to a file, and feed that into the same
    // metaArtPath the rest of the UI (and the notification via the bridge) reads.
    // Skipped on Android TV: the extra connection to the IP-bound pCloud stream URL
    // can disrupt LibVLC's playback there, and the cover is barely visible from the
    // couch anyway — the TV falls back to the placeholder.
    LaunchedEffect(resolvedUrl) {
        if (isTvDevice) return@LaunchedEffect
        val url = resolvedUrl ?: return@LaunchedEffect
        val bytes = runCatching { fetchArt(url) }.getOrNull() ?: return@LaunchedEffect
        runCatching {
            val f = java.io.File(context.cacheDir, "cover-${url.hashCode()}.img")
            f.writeBytes(bytes)
            metaArtPath = f.absolutePath
        }
    }

    // Route the resolved URL to the active sink: the Chromecast if a Cast session
    // is up, otherwise the local VLC player. Re-runs if casting starts/stops, so
    // playback hands off cleanly in either direction.
    LaunchedEffect(resolvedUrl, cast.isCasting, swDecode) {
        val url = resolvedUrl ?: return@LaunchedEffect
        // Reclaim playback from the Android Auto headless player (if it was active)
        // and tell the service to stop its player so the two never overlap.
        com.typezero.cloudplayer.playback.PlaybackBridge.serviceOwnsPlayback = false
        com.typezero.cloudplayer.playback.PlaybackBridge.onYieldToUi?.invoke()
        if (cast.isCasting) {
            runCatching { if (player.isPlaying) player.pause() }
            buffering = false
            isPlaying = true
            val startMs = currentKey()?.let { store.getPosition(it) } ?: 0L
            cast.loadUrl(url, title, guessContentType(title), startMs)
        } else {
            val media = Media(libVlc, Uri.parse(url)).apply {
                if (swDecode) {
                    // Force software: the second arg (force) must be true, or LibVLC
                    // may still hand the stream to the (broken) MediaCodec path.
                    setHWDecoderEnabled(false, true)
                    addOption(":avcodec-hw=none")
                    // Force OpenSL ES audio output. This TV's firmware rejects LibVLC's
                    // default Java AudioTrack module ("audio output: module not functional"),
                    // which stalls playback entirely (LibVLC won't advance video without a
                    // working audio sink to sync to). OpenSL ES bypasses that layer.
                    addOption(":aout=opensles")
                    // Increase network buffer to 5 s. Default 1000 ms matches the ~1-second
                    // auto-pause seen on this TV — buffer drains, LibVLC pauses waiting for
                    // data. 5 s gives the CPU-heavy software decode enough headroom.
                    addOption(":network-caching=5000")
                    addOption(":http-caching=5000")
                } else {
                    setHWDecoderEnabled(true, false)
                }
            }
            player.media = media
            media.release()
            player.play()
            isPlaying = true
            // Restore position after a decode-mode reload.
            if (pendingSeekMs > 0) {
                val seekTo = pendingSeekMs
                pendingSeekMs = 0L
                repeat(30) {
                    delay(150)
                    if (player.isSeekable) {
                        player.time = seekTo
                        return@LaunchedEffect
                    }
                }
            }
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
        pm.newWakeLock(android.os.PowerManager.PARTIAL_WAKE_LOCK, "cloudplayer:playback")
    }
    DisposableEffect(isPlaying, hasVideo, cast.isCasting) {
        val window = activity?.window
        if (isPlaying && !cast.isCasting) {
            if (!wakeLock.isHeld) wakeLock.acquire()
            if (hasVideo) {
                window?.addFlags(android.view.WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
            } else {
                window?.clearFlags(android.view.WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
            }
        } else {
            // Paused, or casting (the Chromecast is doing the playing).
            if (wakeLock.isHeld) wakeLock.release()
            window?.clearFlags(android.view.WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        }
        onDispose {
            if (wakeLock.isHeld) wakeLock.release()
            window?.clearFlags(android.view.WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        }
    }
    // Audio: run the media-session foreground service for the whole audio session,
    // kept alive across pause so the now-playing card + transport controls persist
    // (lock screen / Bluetooth / car). Video and casting don't use it.
    DisposableEffect(isTvDevice, videoKnown, hasVideo, cast.isCasting) {
        // Do not start the foreground media service until VLC has actually told us
        // this item is audio-only. Android TV is intentionally excluded because
        // the Android Auto / audio MediaSession layer can send pause/focus events
        // back into the visible TV player after switching files.
        if (!isTvDevice && videoKnown && !hasVideo && !cast.isCasting) {
            com.typezero.cloudplayer.playback.PlaybackService.start(context)
        } else {
            com.typezero.cloudplayer.playback.PlaybackService.stop(context)
        }
        onDispose { com.typezero.cloudplayer.playback.PlaybackService.stop(context) }
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
    DisposableEffect(isTvDevice, isPlaying, cast.isCasting) {
        if (!isTvDevice && isPlaying && !cast.isCasting) {
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
    val transportFocus = remember { FocusRequester() }
    // Keep the player surface focused so the remote's D-pad keys reach the handler.
    LaunchedEffect(showTracks) {
        if (showTracks) return@LaunchedEffect
        delay(60)
        runCatching { focus.requestFocus() }
    }

    // TV: the D-pad moves a selection highlight across the transport buttons and OK
    // presses the highlighted one. (Phones use touch, so no highlight is shown.)
    val isTv = remember {
        context.packageManager.hasSystemFeature(
            android.content.pm.PackageManager.FEATURE_LEANBACK
        )
    }
    val controlIds = remember(hasPrev, hasNext) {
        buildList {
            if (hasPrev) add("prev")
            add("start"); add("back"); add("play"); add("fwd"); add("end")
            if (hasNext) add("next")
        }
    }
    var selIdx by remember { mutableStateOf(controlIds.indexOf("play").coerceAtLeast(0)) }
    // When true, the time/scrub bar is selected (Left/Right scrub it).
    var onBar by remember { mutableStateOf(false) }
    LaunchedEffect(controlIds) { selIdx = selIdx.coerceIn(0, controlIds.lastIndex) }
    // Land back on play/pause each time the controls reappear.
    LaunchedEffect(controlsVisible) {
        if (controlsVisible) {
            selIdx = controlIds.indexOf("play").coerceAtLeast(0)
            onBar = false
        }
    }
    val selectedId =
        if (isTv && controlsVisible && !onBar) controlIds.getOrNull(selIdx) else null
    val barSelected = isTv && controlsVisible && onBar

    fun dispatchControl(id: String) {
        when (id) {
            "prev" -> if (hasPrev) onPrev()
            "start" -> { player.time = 0; positionMs = 0; reveal() }
            "back" -> seekBy(-10_000)
            "play" -> togglePlay()
            "fwd" -> seekBy(10_000)
            "end" -> {
                if (durationMs > 0) {
                    val t = (durationMs - 1500).coerceAtLeast(0L)
                    player.time = t; positionMs = t
                }
                reveal()
            }
            "next" -> if (hasNext) onNext()
        }
    }

    Box(
        modifier = Modifier
            .fillMaxSize()
            .focusRequester(focus)
            .focusable()
            .onPreviewKeyEvent { e ->
                // While the track picker is open, let the dialog handle navigation.
                if (showTracks) return@onPreviewKeyEvent false

                // Hardware media keys + the options/Menu key act directly (on key-up).
                val direct = when (e.key) {
                    Key.MediaPlayPause, Key.MediaRewind, Key.MediaFastForward,
                    Key.MediaNext, Key.MediaPrevious, Key.Menu -> true
                    else -> false
                }
                if (direct) {
                    if (e.type != KeyEventType.KeyUp) return@onPreviewKeyEvent true
                    when (e.key) {
                        Key.MediaPlayPause -> togglePlay()
                        Key.MediaRewind -> seekBy(-10_000)
                        Key.MediaFastForward -> seekBy(10_000)
                        Key.MediaNext -> if (hasNext) onNext()
                        Key.MediaPrevious -> if (hasPrev) onPrev()
                        Key.Menu -> { refreshTrackLists(); showTracks = true }
                    }
                    return@onPreviewKeyEvent true
                }

                val isLeft = e.key == Key.DirectionLeft
                val isRight = e.key == Key.DirectionRight
                val isCenter = e.key == Key.DirectionCenter ||
                    e.key == Key.Enter || e.key == Key.Spacebar
                val isUp = e.key == Key.DirectionUp
                val isDown = e.key == Key.DirectionDown
                if (!(isLeft || isRight || isCenter || isUp || isDown))
                    return@onPreviewKeyEvent false

                // Controls hidden: the first press only wakes them.
                if (!controlsVisible) {
                    if (e.type == KeyEventType.KeyDown) reveal()
                    return@onPreviewKeyEvent true
                }

                if (onBar) {
                    // Scrub mode: Left/Right move the playhead; Up returns to buttons.
                    val step = (durationMs / 30).coerceAtLeast(5_000L)
                    when {
                        isLeft -> if (e.type == KeyEventType.KeyDown) { seekBy(-step); reveal() }
                        isRight -> if (e.type == KeyEventType.KeyDown) { seekBy(step); reveal() }
                        isUp -> if (e.type == KeyEventType.KeyDown) { onBar = false; reveal() }
                        isDown -> if (e.type == KeyEventType.KeyDown) reveal()
                        isCenter -> if (e.type == KeyEventType.KeyUp) { togglePlay(); reveal() }
                    }
                } else {
                    when {
                        // OK / Enter -> press the highlighted button.
                        isCenter -> if (e.type == KeyEventType.KeyUp) {
                            dispatchControl(controlIds.getOrNull(selIdx) ?: "play")
                            reveal()
                        }
                        // Up -> audio/subtitle picker. Down -> drop onto the scrub bar.
                        isUp -> if (e.type == KeyEventType.KeyUp) {
                            refreshTrackLists(); showTracks = true
                        }
                        isDown -> if (e.type == KeyEventType.KeyDown) { onBar = true; reveal() }
                        // Left/Right -> move the selection highlight across the buttons.
                        isLeft -> if (e.type == KeyEventType.KeyDown) {
                            selIdx = (selIdx - 1).coerceAtLeast(0); reveal()
                        }
                        isRight -> if (e.type == KeyEventType.KeyDown) {
                            selIdx = (selIdx + 1).coerceAtMost(controlIds.lastIndex); reveal()
                        }
                    }
                }
                true
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
                onSeekToStart = {
                    player.time = 0
                    positionMs = 0
                    reveal()
                },
                onSeekToEnd = {
                    if (durationMs > 0) {
                        val t = (durationMs - 1500).coerceAtLeast(0L)
                        player.time = t
                        positionMs = t
                        reveal()
                    }
                },
                playFocus = transportFocus,
                selectedId = selectedId,
                barSelected = barSelected,
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
                com.typezero.cloudplayer.cast.CastButton(
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
                onSeekToStart = {
                    player.time = 0
                    positionMs = 0
                    reveal()
                },
                onSeekToEnd = {
                    if (durationMs > 0) {
                        val t = (durationMs - 1500).coerceAtLeast(0L)
                        player.time = t
                        positionMs = t
                        reveal()
                    }
                },
                onTracks = {
                    refreshTrackLists()
                    showTracks = true
                },
                playFocus = transportFocus,
                selectedId = selectedId,
                barSelected = barSelected,
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
                softwareDecode = swDecode,
                onToggleDecode = {
                    pendingSeekMs = positionMs
                    swDecode = !swDecode
                    store.setSoftwareDecode(swDecode)
                    showTracks = false
                    reveal()
                },
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

@OptIn(ExperimentalAnimationApi::class, ExperimentalMaterial3Api::class)
@Composable
private fun AnimatedVisibilityScope.Controls(
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
    onSeekToStart: () -> Unit,
    onSeekToEnd: () -> Unit,
    onTracks: () -> Unit,
    playFocus: FocusRequester,
    selectedId: String?,
    barSelected: Boolean,
    onScrub: (Float) -> Unit
) {
    Box(modifier = Modifier.fillMaxSize()) {

        // Scrims only at the top and bottom edges (behind the controls), leaving the
        // middle of the picture clear and bright instead of dimming the whole frame.
        Box(
            modifier = Modifier
                .align(Alignment.TopCenter)
                .fillMaxWidth()
                .fillMaxHeight(0.32f)
                .background(
                    Brush.verticalGradient(listOf(Color(0xB3000000), Color.Transparent))
                )
        )
        Box(
            modifier = Modifier
                .align(Alignment.BottomCenter)
                .fillMaxWidth()
                .fillMaxHeight(0.40f)
                .background(
                    Brush.verticalGradient(listOf(Color.Transparent, Color(0xCC000000)))
                )
        )

        // Top header: title on its own full-width line (so long filenames show in
        // full before truncating), with the Cast + Tracks buttons grouped on a row
        // directly beneath it.
        Column(
            modifier = Modifier
                .align(Alignment.TopStart)
                .animateEnterExit(
                    enter = slideInVertically { -it / 3 },
                    exit = slideOutVertically { -it / 3 }
                )
                .fillMaxWidth()
                .padding(start = 20.dp, end = 20.dp, top = 14.dp)
        ) {
            if (queueCount > 1) {
                Text(
                    "TRACK $queuePos / $queueCount",
                    color = CadTextMid,
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
                    Box(
                        modifier = Modifier
                            .clip(RoundedCornerShape(12.dp))
                            .background(Color(0x33FFFFFF)),
                        contentAlignment = Alignment.Center
                    ) {
                        com.typezero.cloudplayer.cast.CastButton(modifier = Modifier.size(42.dp))
                    }
                    Spacer(Modifier.width(10.dp))
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
                .animateEnterExit(
                    enter = slideInVertically { it / 3 },
                    exit = slideOutVertically { it / 3 }
                )
                .fillMaxWidth()
                .padding(horizontal = 24.dp, vertical = 22.dp)
        ) {
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.Center,
                modifier = Modifier.fillMaxWidth()
            ) {
                if (hasPrev || hasNext) {
                    SelBox(selected = selectedId == "prev") {
                        IconButton(onClick = onPrev, enabled = hasPrev) {
                            Icon(
                                Icons.Filled.SkipPrevious, contentDescription = "Previous",
                                tint = if (hasPrev) Color.White else Color(0x55FFFFFF),
                                modifier = Modifier.size(34.dp)
                            )
                        }
                    }
                    Spacer(Modifier.width(8.dp))
                }
                SelBox(selected = selectedId == "start") {
                    IconButton(onClick = onSeekToStart) {
                        Icon(
                            Icons.Filled.FirstPage, contentDescription = "Start from beginning",
                            tint = Color.White, modifier = Modifier.size(32.dp)
                        )
                    }
                }
                Spacer(Modifier.width(8.dp))
                SelBox(selected = selectedId == "back") {
                    IconButton(onClick = onSeekBack) {
                        Icon(
                            Icons.Filled.Replay10, contentDescription = "Back 10s",
                            tint = Color.White, modifier = Modifier.size(38.dp)
                        )
                    }
                }
                Spacer(Modifier.width(16.dp))
                Box(
                    modifier = Modifier
                        .size(64.dp)
                        .shadow(
                            elevation = 14.dp,
                            shape = CircleShape,
                            ambientColor = Brand.Accent,
                            spotColor = Brand.Accent
                        )
                        .clip(CircleShape)
                        .background(Brand.Accent)
                        .border(
                            width = if (selectedId == "play") 3.dp else 0.dp,
                            color = if (selectedId == "play") Color.White else Color.Transparent,
                            shape = CircleShape
                        )
                        .focusRequester(playFocus)
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
                Spacer(Modifier.width(16.dp))
                SelBox(selected = selectedId == "fwd") {
                    IconButton(onClick = onSeekForward) {
                        Icon(
                            Icons.Filled.Forward10, contentDescription = "Forward 10s",
                            tint = Color.White, modifier = Modifier.size(38.dp)
                        )
                    }
                }
                Spacer(Modifier.width(8.dp))
                SelBox(selected = selectedId == "end") {
                    IconButton(onClick = onSeekToEnd) {
                        Icon(
                            Icons.Filled.LastPage, contentDescription = "Skip to end",
                            tint = Color.White, modifier = Modifier.size(32.dp)
                        )
                    }
                }
                if (hasPrev || hasNext) {
                    Spacer(Modifier.width(8.dp))
                    SelBox(selected = selectedId == "next") {
                        IconButton(onClick = onNext, enabled = hasNext) {
                            Icon(
                                Icons.Filled.SkipNext, contentDescription = "Next",
                                tint = if (hasNext) Color.White else Color(0x55FFFFFF),
                                modifier = Modifier.size(34.dp)
                            )
                        }
                    }
                }
            }

            Spacer(Modifier.height(6.dp))
            Row(
                verticalAlignment = Alignment.CenterVertically,
                modifier = Modifier
                    .fillMaxWidth()
                    .clip(RoundedCornerShape(12.dp))
                    .then(
                        if (barSelected) Modifier
                            .background(Color(0x22FFFFFF))
                            .border(2.dp, Brand.Accent, RoundedCornerShape(12.dp))
                        else Modifier
                    )
                    .padding(horizontal = 8.dp, vertical = 4.dp)
            ) {
                Text(
                    formatTime(positionMs),
                    color = Brand.TextHi,
                    fontSize = 13.sp,
                    style = TextStyle(fontFeatureSettings = "tnum")
                )
                Slider(
                    value = if (durationMs > 0) (positionMs.toFloat() / durationMs) else 0f,
                    onValueChange = onScrub,
                    enabled = durationMs > 0,
                    colors = SliderDefaults.colors(
                        thumbColor = Brand.Accent,
                        activeTrackColor = Brand.Accent,
                        inactiveTrackColor = Color(0x33FFFFFF)
                    ),
                    thumb = {
                        Box(
                            modifier = Modifier
                                .size(10.dp)
                                .clip(CircleShape)
                                .background(Brand.Accent)
                        )
                    },
                    modifier = Modifier.weight(1f).padding(horizontal = 12.dp)
                )
                Text(
                    formatTime(durationMs),
                    color = Brand.TextMid,
                    fontSize = 13.sp,
                    style = TextStyle(fontFeatureSettings = "tnum")
                )
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
// ---- Cadence-style monochrome palette (audio now-playing screen only) ----
private val CadBgTop = Color(0xFF17181C)
private val CadBgBot = Color(0xFF0A0A0C)
private val CadStroke = Color(0xFF2B2C32)
private val CadTextHi = Color(0xFFF3F3F6)
private val CadTextMid = Color(0xFF97979F)
private val CadAccent = Color(0xFFEAEAEE)
private val CadBarLo = Color(0xFF4C4D55)
private val CadBarHi = Color(0xFFE9E9EF)
private val CadCap = Color(0xFFFFFFFF)
private val CadTrackInactive = Color(0x22FFFFFF)

/** Holds the LibVLC AudioTrack session id so the visualizer can tap it. */
private object VizSession {
    @Volatile var id: Int = 0
    // Whether we've already auto-requested RECORD_AUDIO this process, so the real
    // FFT tap engages without a tap (incl. on TV) but we never re-prompt-spam.
    @Volatile var asked: Boolean = false
}

/** Collapse an 8-bit FFT (real/imag interleaved) into [out.size] log-spaced bands. */
private fun fftToBands(fft: ByteArray, out: FloatArray) {
    val points = fft.size / 2          // complex points (0..Fs/2)
    if (points < 4) return
    val bands = out.size
    val minBin = 1
    val maxBin = points - 1
    val ratio = maxBin.toDouble() / minBin
    for (b in 0 until bands) {
        val lo = (minBin * Math.pow(ratio, b.toDouble() / bands)).toInt().coerceIn(minBin, maxBin)
        val hi = (minBin * Math.pow(ratio, (b + 1.0) / bands)).toInt().coerceIn(lo + 1, maxBin)
        var mag = 0f
        var k = lo
        while (k < hi) {
            val re = fft[2 * k].toFloat()
            val im = fft[2 * k + 1].toFloat()
            val m = sqrt(re * re + im * im)
            if (m > mag) mag = m
            k++
        }
        // Compress the range (sqrt) so quiet detail still moves the bars.
        out[b] = sqrt((mag / 110f)).coerceIn(0f, 1f)
    }
}

/**
 * Cadence-style spectrum bars with falling peak-hold caps. When the mic
 * permission is granted and a device returns data, the bars follow the real
 * audio FFT (android.media.audiofx.Visualizer on LibVLC's AudioTrack session);
 * otherwise they fall back to a smoothed synthetic envelope so they never look
 * dead. Either way they run while playing and settle flat on pause.
 */
@Composable
private fun AudioVisualizer(isPlaying: Boolean, modifier: Modifier = Modifier) {
    val barCount = 28
    val levels = remember { FloatArray(barCount) }
    val caps = remember { FloatArray(barCount) }
    val targets = remember { FloatArray(barCount) }   // latest real FFT bands
    val lastFftAt = remember { longArrayOf(0L) }       // when real data last arrived
    var frame by remember { mutableStateOf(0) }
    val context = LocalContext.current
    val isTv = remember {
        context.packageManager.hasSystemFeature(PackageManager.FEATURE_LEANBACK)
    }
    var hasMic by remember {
        mutableStateOf(
            ContextCompat.checkSelfPermission(context, Manifest.permission.RECORD_AUDIO) ==
                PackageManager.PERMISSION_GRANTED
        )
    }
    val askMic = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestPermission()
    ) { granted -> hasMic = granted }

    // Make the real audio-reactive spectrum the default on phone: auto-request the
    // mic permission once per launch. NOT on TV — there the permission dialog pops
    // over the player and forces it to pause the instant playback starts. On TV the
    // spectrum uses synthetic motion unless RECORD_AUDIO is granted manually (TV
    // Settings -> Apps -> Cloud Player -> Permissions), in which case it goes real with
    // no disruptive prompt. Denial falls back to synthetic motion.
    LaunchedEffect(Unit) {
        if (!hasMic && !VizSession.asked && !isTv) {
            VizSession.asked = true
            askMic.launch(Manifest.permission.RECORD_AUDIO)
        }
    }

    // Attach/detach the real spectrum tap as permission/session availability changes.
    DisposableEffect(hasMic, VizSession.id) {
        var viz: Visualizer? = null
        if (hasMic && VizSession.id != 0) {
            viz = runCatching {
                Visualizer(VizSession.id).apply {
                    captureSize = Visualizer.getCaptureSizeRange()[1]
                    setDataCaptureListener(
                        object : Visualizer.OnDataCaptureListener {
                            override fun onWaveFormDataCapture(v: Visualizer?, w: ByteArray?, r: Int) {}
                            override fun onFftDataCapture(v: Visualizer?, data: ByteArray?, rate: Int) {
                                if (data != null) {
                                    fftToBands(data, targets)
                                    lastFftAt[0] = SystemClock.uptimeMillis()
                                }
                            }
                        },
                        Visualizer.getMaxCaptureRate(), false, true   // FFT only
                    )
                    enabled = true
                }
            }.getOrNull()
        }
        onDispose { viz?.let { runCatching { it.enabled = false; it.release() } } }
    }

    LaunchedEffect(isPlaying) {
        var t = 0f
        var last = 0L
        while (true) {
            withFrameNanos { now ->
                val dt = if (last == 0L) 0.016f
                         else ((now - last) / 1_000_000_000f).coerceIn(0f, 0.05f)
                last = now
                t += dt
                val real = isPlaying && (SystemClock.uptimeMillis() - lastFftAt[0]) < 400
                for (i in 0 until barCount) {
                    val target = when {
                        real -> targets[i]
                        isPlaying -> {
                            val a = 0.5f + 0.5f * sin(t * (2.1f + i * 0.13f) + i)
                            val b = 0.5f + 0.5f * sin(t * (3.7f - i * 0.05f) + i * 0.5f)
                            val env = 0.45f + 0.55f * sin((i.toFloat() / barCount) * PI.toFloat())
                            (0.12f + 0.88f * (a * 0.6f + b * 0.4f)) * env
                        }
                        else -> 0f
                    }
                    val speed = if (target > levels[i]) 0.6f else 0.2f  // fast attack, slow decay
                    levels[i] += (target - levels[i]) * speed
                    caps[i] = maxOf(caps[i] - dt * 0.9f, levels[i])
                }
                frame++
            }
            if (!isPlaying && (0 until barCount).all { levels[it] < 0.002f && caps[it] < 0.002f }) break
        }
    }

    Box(modifier) {
        Canvas(Modifier.fillMaxSize()) {
            if (frame < 0) return@Canvas  // read `frame` so each tick re-runs the draw
            val n = barCount
            val gap = size.width * 0.012f
            val bw = ((size.width - gap * (n - 1)) / n).coerceAtLeast(1f)
            val maxH = size.height
            val capH = bw * 0.18f
            for (i in 0 until n) {
                val x = i * (bw + gap)
                val lvl = levels[i].coerceIn(0f, 1f)
                val h = lvl * maxH
                val top = maxH - h
                if (h > 0.5f) {
                    drawRoundRect(
                        brush = Brush.verticalGradient(listOf(CadBarHi, CadBarLo), startY = top, endY = maxH),
                        topLeft = Offset(x, top),
                        size = Size(bw, h),
                        cornerRadius = CornerRadius(bw * 0.4f, bw * 0.4f)
                    )
                }
                val capY = (maxH - caps[i].coerceIn(0f, 1f) * maxH - capH).coerceIn(0f, maxH - capH)
                drawRoundRect(
                    color = CadCap,
                    topLeft = Offset(x, capY),
                    size = Size(bw, capH),
                    cornerRadius = CornerRadius(capH, capH)
                )
            }
        }
        // We auto-request the mic once on open (see above), so this is just a
        // manual retry on phones where it was denied. Touch-only, so it never
        // shows on a TV — there the one-time auto-request is the path to real audio.
        if (!hasMic && !isTv) {
            Box(
                modifier = Modifier
                    .align(Alignment.Center)
                    .clip(RoundedCornerShape(20.dp))
                    .background(Color(0x66000000))
                    .clickable { askMic.launch(Manifest.permission.RECORD_AUDIO) }
                    .padding(horizontal = 14.dp, vertical = 6.dp)
            ) {
                Text(
                    "Tap to sync to audio",
                    color = CadTextHi,
                    fontSize = 12.sp,
                    fontWeight = FontWeight.Medium
                )
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
    onSeekToStart: () -> Unit,
    onSeekToEnd: () -> Unit,
    playFocus: FocusRequester,
    selectedId: String?,
    barSelected: Boolean,
    onScrub: (Float) -> Unit
) {
    // Decode embedded cover art off the main thread; null -> placeholder.
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

    BoxWithConstraints(
        modifier = Modifier
            .fillMaxSize()
            .background(Brush.verticalGradient(listOf(CadBgTop, CadBgBot)))
    ) {
        if (maxWidth > maxHeight) {
            // Landscape: art on the left, info + controls on the right, so nothing
            // stacks on top of the title the way the centred portrait layout would.
            val artSize = (maxHeight * 0.66f).coerceIn(120.dp, 240.dp)
            Row(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(horizontal = 48.dp, vertical = 28.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(44.dp)
            ) {
                AudioArt(
                    art = artBitmap,
                    buffering = buffering,
                    modifier = Modifier.size(artSize)
                )
                Column(
                    modifier = Modifier.weight(1f),
                    verticalArrangement = Arrangement.Center
                ) {
                    if (queueCount > 1) {
                        Text(
                            "TRACK $queuePos / $queueCount",
                            color = CadTextMid,
                            fontSize = 12.sp,
                            fontWeight = FontWeight.Bold
                        )
                        Spacer(Modifier.height(6.dp))
                    }
                    Text(
                        title,
                        color = CadTextHi,
                        fontSize = 20.sp,
                        fontWeight = FontWeight.SemiBold,
                        maxLines = 2,
                        overflow = TextOverflow.Ellipsis
                    )
                    if (subtitle != null) {
                        Spacer(Modifier.height(6.dp))
                        Text(
                            subtitle,
                            color = CadTextMid,
                            fontSize = 14.sp,
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis
                        )
                    }
                    Spacer(Modifier.height(18.dp))
                    AudioVisualizer(
                        isPlaying = isPlaying,
                        modifier = Modifier.fillMaxWidth().height(44.dp)
                    )
                    Spacer(Modifier.height(18.dp))
                    AudioTransport(
                        isPlaying = isPlaying,
                        hasPrev = hasPrev,
                        hasNext = hasNext,
                        onPrev = onPrev,
                        onNext = onNext,
                        onTogglePlay = onTogglePlay,
                        onSeekBack = onSeekBack,
                        onSeekForward = onSeekForward,
                        onSeekToStart = onSeekToStart,
                        onSeekToEnd = onSeekToEnd,
                        playFocus = playFocus,
                        selectedId = selectedId,
                        modifier = Modifier.fillMaxWidth()
                    )
                    Spacer(Modifier.height(8.dp))
                    AudioSeekbar(
                        positionMs = positionMs,
                        durationMs = durationMs,
                        onScrub = onScrub,
                        barSelected = barSelected,
                        modifier = Modifier.fillMaxWidth()
                    )
                }
            }
        } else {
            // Portrait: centred hero with the transport pinned to the bottom.
            Column(
                modifier = Modifier.align(Alignment.Center).padding(horizontal = 32.dp),
                horizontalAlignment = Alignment.CenterHorizontally
            ) {
                AudioArt(
                    art = artBitmap,
                    buffering = buffering,
                    modifier = Modifier.size(220.dp)
                )
                Spacer(Modifier.height(28.dp))
                if (queueCount > 1) {
                    Text(
                        "TRACK $queuePos / $queueCount",
                        color = CadTextMid,
                        fontSize = 12.sp,
                        fontWeight = FontWeight.Bold
                    )
                    Spacer(Modifier.height(6.dp))
                }
                Text(
                    title,
                    color = CadTextHi,
                    fontSize = 20.sp,
                    fontWeight = FontWeight.SemiBold,
                    maxLines = 2,
                    textAlign = TextAlign.Center,
                    overflow = TextOverflow.Ellipsis
                )
                if (subtitle != null) {
                    Spacer(Modifier.height(6.dp))
                    Text(
                        subtitle,
                        color = CadTextMid,
                        fontSize = 14.sp,
                        maxLines = 1,
                        textAlign = TextAlign.Center,
                        overflow = TextOverflow.Ellipsis
                    )
                }
            }

            Column(
                modifier = Modifier
                    .align(Alignment.BottomCenter)
                    .fillMaxWidth()
                    .padding(horizontal = 24.dp, vertical = 22.dp)
            ) {
                AudioVisualizer(
                    isPlaying = isPlaying,
                    modifier = Modifier.fillMaxWidth().height(60.dp)
                )
                Spacer(Modifier.height(18.dp))
                AudioTransport(
                    isPlaying = isPlaying,
                    hasPrev = hasPrev,
                    hasNext = hasNext,
                    onPrev = onPrev,
                    onNext = onNext,
                    onTogglePlay = onTogglePlay,
                    onSeekBack = onSeekBack,
                    onSeekForward = onSeekForward,
                    onSeekToStart = onSeekToStart,
                    onSeekToEnd = onSeekToEnd,
                    playFocus = playFocus,
                    selectedId = selectedId,
                    modifier = Modifier.fillMaxWidth()
                )
                Spacer(Modifier.height(6.dp))
                AudioSeekbar(
                    positionMs = positionMs,
                    durationMs = durationMs,
                    onScrub = onScrub,
                    barSelected = barSelected,
                    modifier = Modifier.fillMaxWidth()
                )
            }
        }
    }
}

@Composable
private fun AudioArt(
    art: android.graphics.Bitmap?,
    buffering: Boolean,
    modifier: Modifier = Modifier
) {
    Box(
        modifier = modifier
            .clip(RoundedCornerShape(28.dp))
            .background(CadBgBot)
            .border(1.dp, CadStroke, RoundedCornerShape(28.dp)),
        contentAlignment = Alignment.Center
    ) {
        when {
            art != null -> Image(
                bitmap = art.asImageBitmap(),
                contentDescription = null,
                contentScale = ContentScale.Crop,
                modifier = Modifier.fillMaxSize().clip(RoundedCornerShape(28.dp))
            )
            buffering -> CircularProgressIndicator(color = CadAccent)
            else -> Icon(
                Icons.Filled.MusicNote,
                contentDescription = null,
                tint = CadTextMid,
                modifier = Modifier.fillMaxSize(0.46f)
            )
        }
    }
}

@Composable
private fun SelBox(selected: Boolean, content: @Composable () -> Unit) {
    Box(
        modifier = Modifier
            .clip(CircleShape)
            .background(if (selected) Color(0x40FFFFFF) else Color.Transparent)
            .border(
                width = if (selected) 2.dp else 0.dp,
                color = if (selected) Brand.Accent else Color.Transparent,
                shape = CircleShape
            ),
        contentAlignment = Alignment.Center
    ) { content() }
}

@Composable
private fun AudioTransport(
    isPlaying: Boolean,
    hasPrev: Boolean,
    hasNext: Boolean,
    onPrev: () -> Unit,
    onNext: () -> Unit,
    onTogglePlay: () -> Unit,
    onSeekBack: () -> Unit,
    onSeekForward: () -> Unit,
    onSeekToStart: () -> Unit,
    onSeekToEnd: () -> Unit,
    playFocus: FocusRequester,
    selectedId: String?,
    modifier: Modifier = Modifier
) {
    Row(
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.Center,
        modifier = modifier
    ) {
        if (hasPrev || hasNext) {
            SelBox(selected = selectedId == "prev") {
                IconButton(onClick = onPrev, enabled = hasPrev) {
                    Icon(
                        Icons.Filled.SkipPrevious, contentDescription = "Previous",
                        tint = if (hasPrev) Color.White else Color(0x55FFFFFF),
                        modifier = Modifier.size(34.dp)
                    )
                }
            }
            Spacer(Modifier.width(8.dp))
        }
        SelBox(selected = selectedId == "start") {
            IconButton(onClick = onSeekToStart) {
                Icon(
                    Icons.Filled.FirstPage, contentDescription = "Start from beginning",
                    tint = Color.White, modifier = Modifier.size(32.dp)
                )
            }
        }
        Spacer(Modifier.width(8.dp))
        SelBox(selected = selectedId == "back") {
            IconButton(onClick = onSeekBack) {
                Icon(
                    Icons.Filled.Replay10, contentDescription = "Back 10s",
                    tint = Color.White, modifier = Modifier.size(38.dp)
                )
            }
        }
        Spacer(Modifier.width(16.dp))
        Box(
            modifier = Modifier
                .size(64.dp)
                .shadow(
                    elevation = 14.dp,
                    shape = CircleShape,
                    ambientColor = CadAccent,
                    spotColor = CadAccent
                )
                .clip(CircleShape)
                .background(CadAccent)
                .border(
                    width = if (selectedId == "play") 3.dp else 0.dp,
                    color = if (selectedId == "play") Color.White else Color.Transparent,
                    shape = CircleShape
                )
                .focusRequester(playFocus)
                .clickable(onClick = onTogglePlay),
            contentAlignment = Alignment.Center
        ) {
            Icon(
                if (isPlaying) Icons.Filled.Pause else Icons.Filled.PlayArrow,
                contentDescription = if (isPlaying) "Pause" else "Play",
                tint = CadBgBot,
                modifier = Modifier.size(36.dp)
            )
        }
        Spacer(Modifier.width(16.dp))
        SelBox(selected = selectedId == "fwd") {
            IconButton(onClick = onSeekForward) {
                Icon(
                    Icons.Filled.Forward10, contentDescription = "Forward 10s",
                    tint = Color.White, modifier = Modifier.size(38.dp)
                )
            }
        }
        Spacer(Modifier.width(8.dp))
        SelBox(selected = selectedId == "end") {
            IconButton(onClick = onSeekToEnd) {
                Icon(
                    Icons.Filled.LastPage, contentDescription = "Skip to end",
                    tint = Color.White, modifier = Modifier.size(32.dp)
                )
            }
        }
        if (hasPrev || hasNext) {
            Spacer(Modifier.width(8.dp))
            SelBox(selected = selectedId == "next") {
                IconButton(onClick = onNext, enabled = hasNext) {
                    Icon(
                        Icons.Filled.SkipNext, contentDescription = "Next",
                        tint = if (hasNext) Color.White else Color(0x55FFFFFF),
                        modifier = Modifier.size(34.dp)
                    )
                }
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun AudioSeekbar(
    positionMs: Long,
    durationMs: Long,
    onScrub: (Float) -> Unit,
    barSelected: Boolean = false,
    modifier: Modifier = Modifier
) {
    Row(
        verticalAlignment = Alignment.CenterVertically,
        modifier = modifier
            .clip(RoundedCornerShape(12.dp))
            .then(
                if (barSelected) Modifier
                    .background(Color(0x22FFFFFF))
                    .border(2.dp, CadAccent, RoundedCornerShape(12.dp))
                else Modifier
            )
            .padding(horizontal = 8.dp, vertical = 4.dp)
    ) {
        Text(
            formatTime(positionMs),
            color = CadTextHi,
            fontSize = 13.sp,
            style = TextStyle(fontFeatureSettings = "tnum")
        )
        Slider(
            value = if (durationMs > 0) (positionMs.toFloat() / durationMs) else 0f,
            onValueChange = onScrub,
            enabled = durationMs > 0,
            colors = SliderDefaults.colors(
                thumbColor = CadAccent,
                activeTrackColor = CadAccent,
                inactiveTrackColor = CadTrackInactive
            ),
            thumb = {
                Box(
                    modifier = Modifier
                        .size(10.dp)
                        .clip(CircleShape)
                        .background(CadAccent)
                )
            },
            modifier = Modifier.weight(1f).padding(horizontal = 12.dp)
        )
        Text(
            formatTime(durationMs),
            color = CadTextMid,
            fontSize = 13.sp,
            style = TextStyle(fontFeatureSettings = "tnum")
        )
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
    softwareDecode: Boolean,
    onToggleDecode: () -> Unit,
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

            Spacer(Modifier.height(18.dp))
            Text("Decoding", color = Brand.Accent, fontSize = 14.sp,
                fontWeight = FontWeight.SemiBold)
            Spacer(Modifier.height(8.dp))
            TrackRow(
                if (softwareDecode) "Software (compatibility)" else "Hardware (default)",
                selected = softwareDecode
            ) { onToggleDecode() }
            Text(
                "Switch to Software if video won't play (e.g. 10-bit HEVC on some TVs).",
                color = Brand.TextLow, fontSize = 11.sp,
                modifier = Modifier.padding(top = 4.dp, start = 2.dp)
            )

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
