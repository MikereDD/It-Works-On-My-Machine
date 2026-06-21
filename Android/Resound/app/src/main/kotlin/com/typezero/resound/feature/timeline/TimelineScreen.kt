/*
 * file:    TimelineScreen.kt
 * author:  Mike Redd (typezero)
 * version: 0.6.0
 * desc:    Multitrack timeline. Track lanes share one zoomable, scrollable time
 *          axis. Drag a clip's body to move it; drag its left/right edge to trim
 *          the source in/out. Mute per track. Export a mixdown (atrim+adelay+
 *          amix) to Music/Resound. Restyled to the Resound dark identity.
 */
package com.typezero.resound.feature.timeline

import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.gestures.detectDragGestures
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import com.typezero.resound.core.audio.AudioFiles
import com.typezero.resound.core.audio.WaveformExtractor
import com.typezero.resound.core.ffmpeg.FFmpegRunner
import com.typezero.resound.core.io.Outputs
import com.typezero.resound.feature.effects.Effects
import com.typezero.resound.ui.theme.Amber
import com.typezero.resound.ui.theme.Line
import com.typezero.resound.ui.theme.Panel
import com.typezero.resound.ui.theme.PanelHi
import com.typezero.resound.ui.theme.Signal
import com.typezero.resound.ui.theme.SignalDeep
import com.typezero.resound.ui.theme.TextLo
import kotlinx.coroutines.launch
import kotlin.math.max
import kotlin.math.roundToInt

private const val MIN_CLIP_MS = 200L
private const val LANE_H = 84

@Composable
fun TimelineScreen(
    waveformExtractor: WaveformExtractor,
    ffmpeg: FFmpegRunner,
    onBack: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val ctx = LocalContext.current
    val scope = rememberCoroutineScope()
    val density = LocalDensity.current

    var tracks by remember { mutableStateOf(listOf<Track>()) }
    var idCounter by remember { mutableLongStateOf(1L) }
    var selectedClip by remember { mutableStateOf<Long?>(null) }
    var addTrackId by remember { mutableStateOf<Long?>(null) }
    var busy by remember { mutableStateOf(false) }
    var status by remember { mutableStateOf("Add a track, then add clips to it.") }
    var pxPerSec by remember { mutableFloatStateOf(24f) }

    fun nextId(): Long = idCounter++
    fun updateTrack(id: Long, f: (Track) -> Track) { tracks = tracks.map { if (it.id == id) f(it) else it } }
    fun updateClip(trackId: Long, clipId: Long, f: (Clip) -> Clip) {
        updateTrack(trackId) { t -> t.copy(clips = t.clips.map { if (it.id == clipId) f(it) else it }) }
    }

    val timeline = Timeline(tracks)
    val displayDuration = max(timeline.durationMs, 30_000L)
    val pxPerMs = pxPerSec / 1000f

    val clipPicker = rememberLauncherForActivityResult(
        ActivityResultContracts.OpenDocument()
    ) { uri ->
        val tId = addTrackId
        addTrackId = null
        if (uri == null || tId == null) return@rememberLauncherForActivityResult
        scope.launch {
            try {
                busy = true
                status = "Adding clip…"
                val af = AudioFiles.readMetadata(ctx, uri)
                val wf = waveformExtractor.extract(af, targetBuckets = 600)
                val clip = Clip(nextId(), af, wf, startMs = 0L)
                updateTrack(tId) { it.copy(clips = it.clips + clip) }
                status = "Added ${af.displayName}"
            } catch (t: Throwable) {
                status = "Couldn't add clip: ${t.message}"
            } finally {
                busy = false
            }
        }
    }

    fun exportMix() {
        scope.launch {
            try {
                busy = true
                status = "Mixing…"
                val pairs = tracks.flatMap { tr -> if (tr.muted) emptyList() else tr.clips.map { tr to it } }
                if (pairs.isEmpty()) { status = "Add a clip to an unmuted track first."; return@launch }
                val specs = pairs.map { (tr, c) ->
                    Effects.TimelineInput(
                        path = AudioFiles.resolveToCache(ctx, c.source).absolutePath,
                        startMs = c.startMs,
                        inMs = c.sourceInMs,
                        outMs = c.sourceOutMs,
                        volume = tr.volume,
                    )
                }
                val temp = Outputs.newTempFile(ctx, "mix", "m4a")
                val res = ffmpeg.run(Effects.mixTimeline(specs, temp.absolutePath))
                status = if (res.isSuccess) {
                    val pub = Outputs.publishToMusic(ctx, temp, temp.name, "m4a")
                    "Mixed to ${pub.displayPath}"
                } else {
                    "Mix failed (rc=${res.returnCode})"
                }
            } catch (t: Throwable) {
                status = "Mix failed: ${t.message}"
            } finally {
                busy = false
            }
        }
    }

    val hScroll = rememberScrollState()

    Surface(modifier = modifier.fillMaxSize(), color = MaterialTheme.colorScheme.background) {
        Column(modifier = Modifier.fillMaxSize().safeDrawingPadding().padding(horizontal = 16.dp)) {

            Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.padding(top = 8.dp)) {
                TextButton(onClick = onBack) { Text("‹ Editor") }
                Spacer(Modifier.width(4.dp))
                Column {
                    Text("Multitrack", style = MaterialTheme.typography.headlineSmall)
                    Text("arrange · trim · mix", style = MaterialTheme.typography.bodySmall)
                }
            }

            Row(
                modifier = Modifier.padding(top = 12.dp),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Button(onClick = { tracks = tracks + Track(nextId(), "Track ${tracks.size + 1}") }, enabled = !busy) {
                    Text("Add track")
                }
                FilledTonalButton(
                    onClick = { exportMix() },
                    enabled = !busy && tracks.any { it.clips.isNotEmpty() },
                ) { Text("Export mix") }
            }

            // Zoom control
            Row(
                modifier = Modifier.padding(top = 10.dp),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text("Zoom", style = MaterialTheme.typography.bodySmall)
                OutlinedButton(
                    onClick = { pxPerSec = (pxPerSec / 1.4f).coerceAtLeast(6f) },
                    contentPadding = ButtonDefaults.TextButtonContentPadding,
                ) { Text("−") }
                OutlinedButton(
                    onClick = { pxPerSec = (pxPerSec * 1.4f).coerceAtMost(240f) },
                    contentPadding = ButtonDefaults.TextButtonContentPadding,
                ) { Text("+") }
            }

            Text(
                status,
                style = MaterialTheme.typography.bodySmall,
                modifier = Modifier.padding(top = 10.dp, bottom = 6.dp),
            )

            BoxWithConstraints(modifier = Modifier.fillMaxWidth()) {
                val availPx = with(density) { maxWidth.toPx() }
                val contentPx = max(availPx, displayDuration * pxPerMs)
                val contentDp = with(density) { contentPx.toDp() }

                Column(
                    modifier = Modifier.fillMaxWidth().verticalScroll(rememberScrollState()),
                    verticalArrangement = Arrangement.spacedBy(12.dp),
                ) {
                    if (tracks.isEmpty()) {
                        Text(
                            "No tracks yet. Tap “Add track” to start a mix.",
                            style = MaterialTheme.typography.bodyMedium,
                            color = TextLo,
                            modifier = Modifier.padding(top = 24.dp),
                        )
                    }
                    tracks.forEach { track ->
                        TrackCard(
                            track = track,
                            contentDp = contentDp,
                            pxPerMs = pxPerMs,
                            hScroll = hScroll,
                            selectedClip = selectedClip,
                            enabled = !busy,
                            onAddClip = {
                                addTrackId = track.id
                                clipPicker.launch(arrayOf("audio/*", "video/*"))
                            },
                            onToggleMute = { updateTrack(track.id) { it.copy(muted = !it.muted) } },
                            onSelectClip = { selectedClip = it },
                            onMove = { clipId, d ->
                                updateClip(track.id, clipId) { it.copy(startMs = (it.startMs + d).coerceAtLeast(0L)) }
                            },
                            onTrimIn = { clipId, d ->
                                updateClip(track.id, clipId) { c ->
                                    val newIn = (c.sourceInMs + d).coerceIn(0L, c.sourceOutMs - MIN_CLIP_MS)
                                    val ad = newIn - c.sourceInMs
                                    c.copy(sourceInMs = newIn, startMs = (c.startMs + ad).coerceAtLeast(0L))
                                }
                            },
                            onTrimOut = { clipId, d ->
                                updateClip(track.id, clipId) { c ->
                                    c.copy(sourceOutMs = (c.sourceOutMs + d).coerceIn(c.sourceInMs + MIN_CLIP_MS, c.source.durationMs))
                                }
                            },
                        )
                    }
                    Spacer(Modifier.height(32.dp))
                }
            }
        }
    }
}

@Composable
private fun TrackCard(
    track: Track,
    contentDp: androidx.compose.ui.unit.Dp,
    pxPerMs: Float,
    hScroll: androidx.compose.foundation.ScrollState,
    selectedClip: Long?,
    enabled: Boolean,
    onAddClip: () -> Unit,
    onToggleMute: () -> Unit,
    onSelectClip: (Long) -> Unit,
    onMove: (Long, Long) -> Unit,
    onTrimIn: (Long, Long) -> Unit,
    onTrimOut: (Long, Long) -> Unit,
) {
    Card(
        colors = CardDefaults.cardColors(containerColor = Panel),
        shape = RoundedCornerShape(14.dp),
    ) {
        Column(modifier = Modifier.padding(12.dp)) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(
                    track.name,
                    style = MaterialTheme.typography.titleMedium,
                    color = if (track.muted) TextLo else MaterialTheme.colorScheme.onSurface,
                    modifier = Modifier.width(72.dp),
                )
                OutlinedButton(onClick = onAddClip, enabled = enabled) { Text("Add clip") }
                if (track.muted) {
                    Button(
                        onClick = onToggleMute,
                        enabled = enabled,
                        colors = ButtonDefaults.buttonColors(containerColor = Amber, contentColor = Color.Black),
                    ) { Text("Muted") }
                } else {
                    OutlinedButton(onClick = onToggleMute, enabled = enabled) { Text("Mute") }
                }
            }

            Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(top = 10.dp)
                    .height(LANE_H.dp)
                    .clip(RoundedCornerShape(8.dp))
                    .horizontalScroll(hScroll),
            ) {
                Box(modifier = Modifier.width(contentDp).height(LANE_H.dp)) {
                    track.clips.forEach { clip ->
                        ClipBox(
                            clip = clip,
                            pxPerMs = pxPerMs,
                            muted = track.muted,
                            selected = selectedClip == clip.id,
                            onSelect = { onSelectClip(clip.id) },
                            onMove = { d -> onMove(clip.id, d) },
                            onTrimIn = { d -> onTrimIn(clip.id, d) },
                            onTrimOut = { d -> onTrimOut(clip.id, d) },
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun ClipBox(
    clip: Clip,
    pxPerMs: Float,
    muted: Boolean,
    selected: Boolean,
    onSelect: () -> Unit,
    onMove: (Long) -> Unit,
    onTrimIn: (Long) -> Unit,
    onTrimOut: (Long) -> Unit,
) {
    val density = LocalDensity.current
    val scale = rememberUpdatedState(pxPerMs)
    val cbMove = rememberUpdatedState(onMove)
    val cbIn = rememberUpdatedState(onTrimIn)
    val cbOut = rememberUpdatedState(onTrimOut)
    val cbSel = rememberUpdatedState(onSelect)
    var mode by remember { mutableStateOf(0) } // 0 move, 1 trim-in, 2 trim-out

    val xPx = (clip.startMs * pxPerMs).roundToInt()
    val widthDp = with(density) { (clip.lengthMs * pxPerMs).coerceAtLeast(2f).toDp() }

    val fillTop = if (muted) Color(0xFF3A4A56) else Signal
    val fillBot = if (muted) Color(0xFF2A3640) else SignalDeep

    Box(
        modifier = Modifier
            .offset { IntOffset(xPx, 0) }
            .width(widthDp)
            .height(LANE_H.dp)
            .clip(RoundedCornerShape(8.dp))
            .pointerInput(clip.id) {
                val edge = 20.dp.toPx()
                detectDragGestures(
                    onDragStart = { pos ->
                        cbSel.value()
                        mode = when {
                            pos.x < edge -> 1
                            pos.x > size.width - edge -> 2
                            else -> 0
                        }
                    },
                ) { change, drag ->
                    change.consume()
                    val s = scale.value
                    if (s > 0f) {
                        val d = (drag.x / s).toLong()
                        when (mode) {
                            1 -> cbIn.value(d)
                            2 -> cbOut.value(d)
                            else -> cbMove.value(d)
                        }
                    }
                }
            },
    ) {
        Canvas(modifier = Modifier.fillMaxSize()) {
            // clip body
            drawRect(color = PanelHi)
            val wf = clip.waveform
            val n = wf.bucketCount
            val durMs = clip.source.durationMs
            if (n > 0 && durMs > 0) {
                val i0 = ((clip.sourceInMs.toFloat() / durMs) * n).toInt().coerceIn(0, n)
                val i1 = ((clip.sourceOutMs.toFloat() / durMs) * n).toInt().coerceIn(i0, n)
                val count = (i1 - i0).coerceAtLeast(1)
                val w = size.width
                val h = size.height
                val midY = h / 2f
                val step = w / count
                val path = Path().apply {
                    moveTo(0f, midY)
                    for (k in 0 until count) lineTo(k * step, midY - wf.maxs[i0 + k] * midY)
                    for (k in count - 1 downTo 0) lineTo(k * step, midY - wf.mins[i0 + k] * midY)
                    close()
                }
                drawPath(path, brush = Brush.verticalGradient(listOf(fillTop, fillBot), 0f, h))
            }
            // selection edges / trim handles
            val border = if (selected) Signal else Line
            drawRect(
                color = border,
                topLeft = Offset(0f, 0f),
                size = androidx.compose.ui.geometry.Size(size.width, size.height),
                style = androidx.compose.ui.graphics.drawscope.Stroke(width = if (selected) 4f else 2f),
            )
            if (selected) {
                val gripW = 5f
                drawRect(Signal, Offset(0f, 0f), androidx.compose.ui.geometry.Size(gripW, size.height))
                drawRect(Signal, Offset(size.width - gripW, 0f), androidx.compose.ui.geometry.Size(gripW, size.height))
            }
        }
    }
}
