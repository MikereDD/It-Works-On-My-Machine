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
import androidx.compose.ui.draw.clip
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.clickable
import android.net.Uri
import androidx.activity.compose.BackHandler
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.foundation.background
import androidx.compose.foundation.focusable
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Forward10
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
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.key.Key
import androidx.compose.ui.input.key.KeyEventType
import androidx.compose.ui.input.key.key
import androidx.compose.ui.input.key.onKeyEvent
import androidx.compose.ui.input.key.type
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.viewinterop.AndroidView
import com.typezero.pcloudtv.data.ApiResult
import kotlinx.coroutines.delay
import org.videolan.libvlc.LibVLC
import org.videolan.libvlc.Media
import org.videolan.libvlc.MediaPlayer
import org.videolan.libvlc.util.VLCVideoLayout

@Composable
fun PlayerScreen(
    queue: List<MediaItem>,
    resolveUrl: suspend (MediaItem) -> ApiResult<String>,
    startIndex: Int = 0,
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
    // The player instance is kept mounted for the whole queue; advancing the
    // index just swaps the media so playback never tears down between tracks.
    VlcPlayer(
        queue = queue,
        resolveUrl = resolveUrl,
        startIndex = startIndex.coerceIn(0, queue.size - 1),
        onExit = onExit
    )
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
    onExit: () -> Unit
) {
    val context = LocalContext.current
    val store = remember { com.typezero.pcloudtv.data.SessionStore(context) }

    var index by remember { mutableStateOf(startIndex) }
    val current = queue.getOrNull(index)
    val title = current?.title ?: ""
    val queuePos = index + 1
    val queueCount = queue.size
    val hasPrev = index > 0
    val hasNext = index < queue.size - 1
    fun onPrev() { if (index > 0) index-- }
    fun onNext() { if (index < queue.size - 1) index++ }
    fun onEnded() { if (index < queue.size - 1) index++ else onExit() }

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
    var resumed by remember { mutableStateOf(false) }
    var lastSavedAt by remember { mutableStateOf(0L) }
    var buffering by remember { mutableStateOf(true) }

    // The event listener below is registered once, so anything it needs about the
    // CURRENT track must be read live (index is state-backed, so this is current).
    fun currentKey(): Long? = queue.getOrNull(index)?.fileId

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

    fun reveal() {
        controlsVisible = true
        interactionTick++
    }

    fun togglePlay() {
        if (cast.isCasting) {
            if (cast.isRemotePlaying) cast.pause() else cast.play()
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

    // Prefer English audio + English subtitles when the file has multiple tracks.
    var tracksChosen by remember { mutableStateOf(false) }
    fun selectEnglishTracks() {
        if (tracksChosen) return
        fun isEnglish(name: String?): Boolean {
            val n = name?.lowercase() ?: return false
            return n.contains("eng") || n.contains("english") ||
                Regex("\\b(en|eng)\\b").containsMatchIn(n)
        }
        // Audio: switch to the first English track if one exists; else leave default.
        player.audioTracks?.firstOrNull { isEnglish(it.name) }?.let {
            player.audioTrack = it.id
        }
        // Subtitles: enable the first English track if one exists; otherwise turn
        // subtitles OFF so VLC can't fall back to a non-English track (e.g. Spanish).
        val subs = player.spuTracks
        if (subs != null && subs.isNotEmpty()) {
            val eng = subs.firstOrNull { isEnglish(it.name) }
            // spuTrack id -1 disables subtitles in LibVLC.
            player.spuTrack = eng?.id ?: -1
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
                    resumeIfNeeded()
                    selectEnglishTracks()
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
                    // Throttle resume-position saves to ~once every 5s.
                    val now = System.currentTimeMillis()
                    if (now - lastSavedAt > 5_000) {
                        lastSavedAt = now
                        persistPosition()
                    }
                }
                MediaPlayer.Event.LengthChanged -> durationMs = e.lengthChanged
                MediaPlayer.Event.ESAdded -> selectEnglishTracks()
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
        buffering = true
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
    LaunchedEffect(cast) { cast.onEnded = { onEnded() } }

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
                // Audio: keep playing when the app is left/backgrounded.
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

    // Auto-hide controls after inactivity (only while playing).
    LaunchedEffect(controlsVisible, interactionTick, isPlaying) {
        if (controlsVisible && isPlaying) {
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
        } else if (buffering) {
            Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                CircularProgressIndicator(color = Brand.Accent)
            }
        }

        // Cast device-picker button (only if Cast is available on this device).
        if (cast.isAvailable) {
            androidx.compose.animation.AnimatedVisibility(
                visible = controlsVisible && !showTracks,
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
            visible = controlsVisible && !showTracks,
            enter = fadeIn(),
            exit = fadeOut()
        ) {
            Controls(
                title = title,
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
                },
                onPickSub = { id ->
                    player.spuTrack = id
                    currentSub = id
                },
                onClose = { showTracks = false; reveal() }
            )
        }
    }
}

@Composable
private fun Controls(
    title: String,
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

        Column(modifier = Modifier.align(Alignment.TopStart).padding(24.dp)) {
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
                maxLines = 1
            )
        }

        // Audio / subtitle track selector.
        Box(
            modifier = Modifier
                .align(Alignment.TopEnd)
                .padding(16.dp)
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
