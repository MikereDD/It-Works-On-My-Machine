/*
 * file:    EditScreen.kt
 * author:  Mike Redd (typezero)
 * version: 0.4.0
 * desc:    Editor screen. Adds (0.4.0) a voice recorder (record -> load into the
 *          editor + save a copy to Music/Resound) and a "Set as Ringtone"
 *          action. Edit ops still run through the shared Effects -> FFmpeg ->
 *          publish path; outputs land in the shared Music/Resound library.
 */
package com.typezero.resound.feature.edit

import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.layout.wrapContentHeight
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.core.content.ContextCompat
import com.typezero.resound.core.audio.AudioFile
import com.typezero.resound.core.audio.AudioFiles
import com.typezero.resound.core.audio.AudioPlayer
import com.typezero.resound.core.audio.Waveform
import com.typezero.resound.core.audio.WaveformExtractor
import com.typezero.resound.core.ffmpeg.FFmpegRunner
import com.typezero.resound.core.io.Outputs
import com.typezero.resound.core.io.Ringtones
import com.typezero.resound.feature.about.AboutDialog
import com.typezero.resound.feature.effects.Effects
import com.typezero.resound.feature.record.Recorder
import com.typezero.resound.ui.theme.Amber
import com.typezero.resound.ui.theme.Panel
import com.typezero.resound.ui.theme.Signal
import com.typezero.resound.ui.theme.TimecodeStyle
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import java.io.File

private fun fmt(ms: Long): String {
    val totalSec = ms / 1000
    val m = totalSec / 60
    val s = totalSec % 60
    return "%d:%02d".format(m, s)
}

@Composable
fun EditScreen(
    waveformExtractor: WaveformExtractor,
    ffmpeg: FFmpegRunner,
    recorder: Recorder,
    onOpenTimeline: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()

    // API 26-28 needs WRITE_EXTERNAL_STORAGE to publish into public Music.
    // 29+ uses MediaStore and needs nothing — this is a no-op there.
    val writePerm = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestPermission()
    ) { }
    LaunchedEffect(Unit) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            writePerm.launch(android.Manifest.permission.WRITE_EXTERNAL_STORAGE)
        }
    }

    var current by remember { mutableStateOf<AudioFile?>(null) }
    var waveform by remember { mutableStateOf<Waveform?>(null) }
    var selStart by remember { mutableLongStateOf(0L) }
    var selEnd by remember { mutableLongStateOf(0L) }
    var playhead by remember { mutableLongStateOf(0L) }
    var status by remember { mutableStateOf("Open a file or record to begin.") }
    var busy by remember { mutableStateOf(false) }
    var pendingOp by remember { mutableStateOf<EditOp?>(null) }
    var pendingMulti by remember { mutableStateOf<EditOp?>(null) }
    var showAbout by remember { mutableStateOf(false) }

    val player = remember { AudioPlayer() }
    var playing by remember { mutableStateOf(false) }
    DisposableEffect(Unit) { onDispose { player.release() } }

    // While playing, advance the playhead and stop at the end of the selection.
    LaunchedEffect(playing) {
        while (playing) {
            delay(50)
            playhead = player.currentMs
            if (!player.isPlaying || playhead >= selEnd) {
                player.pause()
                playing = false
            }
        }
    }

    var recording by remember { mutableStateOf(false) }
    var recordElapsed by remember { mutableLongStateOf(0L) } // seconds
    var recordFile by remember { mutableStateOf<File?>(null) }

    LaunchedEffect(recording) {
        while (recording) {
            delay(1000)
            recordElapsed += 1
        }
    }

    fun srcExt(): String =
        current?.displayName?.substringAfterLast('.', "m4a")?.ifEmpty { "m4a" } ?: "m4a"

    fun loadInto(uri: Uri, doneMsg: (AudioFile) -> String) {
        scope.launch {
            try {
                busy = true
                status = "Loading…"
                playing = false
                playhead = 0L
                val af = AudioFiles.readMetadata(context, uri)
                current = af
                selStart = 0L
                selEnd = af.durationMs
                status = "Decoding waveform…"
                waveform = waveformExtractor.extract(af, targetBuckets = 1200)
                runCatching { player.prepare(context, uri) }
                status = doneMsg(af)
            } catch (t: Throwable) {
                status = "Load failed: ${t.message}"
            } finally {
                busy = false
            }
        }
    }

    // Shared single-file run path: resolve source -> build args -> FFmpeg -> save.
    fun runSingle(
        label: String,
        outExt: String,
        totalMs: Long = current?.durationMs ?: 0L,
        makeArgs: (src: String, out: String) -> List<String>,
    ) {
        val af = current ?: return
        scope.launch {
            try {
                busy = true
                status = "$label…"
                val src = AudioFiles.resolveToCache(context, af)
                val temp = Outputs.newTempFile(context, label.lowercase().replace(" ", "-"), outExt)
                val args = makeArgs(src.absolutePath, temp.absolutePath)
                val res = ffmpeg.run(args, totalMs) { ratio, _ ->
                    if (ratio != null) status = "$label… ${(ratio * 100).toInt()}%"
                }
                status = if (res.isSuccess) {
                    val pub = Outputs.publishToMusic(context, temp, temp.name, outExt)
                    "Saved to ${pub.displayPath}"
                } else {
                    "FFmpeg failed (rc=${res.returnCode})"
                }
            } catch (t: Throwable) {
                status = "$label failed: ${t.message}"
            } finally {
                busy = false
            }
        }
    }

    // Two-file run path for Mix / Concat.
    fun runDual(
        label: String,
        outExt: String,
        secondUri: Uri,
        makeArgs: (a: String, b: String, out: String) -> List<String>,
    ) {
        val af = current ?: return
        scope.launch {
            try {
                busy = true
                status = "$label…"
                val a = AudioFiles.resolveToCache(context, af)
                val secondAf = AudioFiles.readMetadata(context, secondUri)
                val b = AudioFiles.resolveToCache(context, secondAf)
                val temp = Outputs.newTempFile(context, label.lowercase(), outExt)
                val args = makeArgs(a.absolutePath, b.absolutePath, temp.absolutePath)
                val res = ffmpeg.run(args)
                status = if (res.isSuccess) {
                    val pub = Outputs.publishToMusic(context, temp, temp.name, outExt)
                    "Saved to ${pub.displayPath}"
                } else {
                    "FFmpeg failed (rc=${res.returnCode})"
                }
            } catch (t: Throwable) {
                status = "$label failed: ${t.message}"
            } finally {
                busy = false
            }
        }
    }

    fun onParams(op: EditOp, p: OpParams) {
        val af = current ?: return
        when (op) {
            EditOp.VOLUME -> runSingle("Volume", srcExt()) { s, o ->
                Effects.volume(s, o, (p as OpParams.Volume).factor)
            }
            EditOp.SPEED -> runSingle("Speed", srcExt()) { s, o ->
                Effects.speed(s, o, (p as OpParams.Speed).factor)
            }
            EditOp.PITCH -> runSingle("Pitch", srcExt()) { s, o ->
                Effects.pitchSemitones(s, o, (p as OpParams.Pitch).semitones, af.sampleRate)
            }
            EditOp.FADE -> runSingle("Fade", srcExt()) { s, o ->
                Effects.fade(s, o, af.durationMs, (p as OpParams.Fade).fadeMs)
            }
            EditOp.EQ -> runSingle("EQ", srcExt()) { s, o ->
                val e = p as OpParams.Eq; Effects.equalizerBand(s, o, e.freq, e.gainDb)
            }
            EditOp.CONVERT -> {
                val e = p as OpParams.Convert
                runSingle("Convert", e.ext) { s, o -> Effects.convert(s, o) }
            }
            EditOp.COMPRESS -> {
                val e = p as OpParams.Compress
                runSingle("Compress", srcExt()) { s, o ->
                    Effects.compress(s, o, e.bitrateKbps, af.sampleRate, af.channels)
                }
            }
            else -> {}
        }
    }

    fun startRecording() {
        try {
            val f = Outputs.newTempFile(context, "recording", "m4a")
            recordFile = f
            recorder.start(f.absolutePath)
            recordElapsed = 0L
            recording = true
            status = "Recording…"
        } catch (t: Throwable) {
            recording = false
            status = "Record failed: ${t.message}"
        }
    }

    fun stopRecording() {
        val path = recorder.stop()
        recording = false
        if (path == null) {
            status = "Recording failed."
            return
        }
        scope.launch {
            try {
                busy = true
                val recFile = File(path)
                val af = AudioFiles.readMetadata(context, Uri.fromFile(recFile))
                current = af
                selStart = 0L
                selEnd = af.durationMs
                playing = false
                playhead = 0L
                status = "Decoding waveform…"
                waveform = waveformExtractor.extract(af, targetBuckets = 1200)
                runCatching { player.prepare(context, Uri.fromFile(recFile)) }
                // Save a copy to the shared library (publish consumes its temp).
                val copy = Outputs.newTempFile(context, "recording", "m4a")
                recFile.copyTo(copy, overwrite = true)
                val pub = Outputs.publishToMusic(context, copy, copy.name, "m4a")
                status = "Recorded & saved to ${pub.displayPath}"
            } catch (t: Throwable) {
                status = "Recording load failed: ${t.message}"
            } finally {
                busy = false
            }
        }
    }

    val recordPerm = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestPermission()
    ) { granted ->
        if (granted) startRecording() else status = "Microphone permission denied."
    }

    fun onRecordTap() {
        if (recording) {
            stopRecording()
        } else {
            val granted = ContextCompat.checkSelfPermission(
                context, android.Manifest.permission.RECORD_AUDIO
            ) == PackageManager.PERMISSION_GRANTED
            if (granted) startRecording() else recordPerm.launch(android.Manifest.permission.RECORD_AUDIO)
        }
    }

    fun onPlayPause() {
        if (playing) {
            player.pause()
            playing = false
        } else {
            if (current == null) return
            val from = if (playhead in selStart until selEnd) playhead else selStart
            player.play(from)
            playing = true
        }
    }

    fun onRingtone() {
        val af = current ?: return
        if (!Ringtones.canWrite(context)) {
            context.startActivity(Ringtones.manageWriteSettingsIntent(context))
            status = "Grant 'Modify system settings', then tap Ringtone again."
            return
        }
        scope.launch {
            try {
                busy = true
                status = "Setting ringtone…"
                val src = AudioFiles.resolveToCache(context, af)
                when (val r = Ringtones.setAsDefault(context, src, af.displayName, srcExt())) {
                    is Ringtones.Result.Ok -> status = "Ringtone set: ${r.name}"
                    is Ringtones.Result.NeedsPermission -> status = "Permission needed to set ringtone."
                    is Ringtones.Result.Error -> status = "Ringtone failed: ${r.message}"
                }
            } catch (t: Throwable) {
                status = "Ringtone failed: ${t.message}"
            } finally {
                busy = false
            }
        }
    }

    val picker = rememberLauncherForActivityResult(
        ActivityResultContracts.OpenDocument()
    ) { uri ->
        if (uri == null) return@rememberLauncherForActivityResult
        loadInto(uri) { af -> "Loaded ${af.displayName} • ${fmt(af.durationMs)} • ${af.sampleRate} Hz" }
    }

    val secondPicker = rememberLauncherForActivityResult(
        ActivityResultContracts.OpenDocument()
    ) { uri ->
        val op = pendingMulti
        pendingMulti = null
        if (uri == null || op == null) return@rememberLauncherForActivityResult
        when (op) {
            EditOp.MIX -> runDual("Mix", srcExt(), uri) { a, b, o -> Effects.mix(listOf(a, b), o) }
            EditOp.CONCAT -> runDual("Concat", srcExt(), uri) { a, b, o -> Effects.concat(listOf(a, b), o) }
            else -> {}
        }
    }

    fun onTap(op: EditOp) {
        when {
            op == EditOp.TRIM -> runSingle("Trim", srcExt(), totalMs = selEnd - selStart) { s, o ->
                Effects.trimEncode(s, o, selStart, selEnd)
            }
            op == EditOp.VOCAL -> runSingle("Vocal Remove", srcExt()) { s, o ->
                Effects.vocalRemoveCenter(s, o)
            }
            op.needsSecondFile -> {
                pendingMulti = op
                secondPicker.launch(arrayOf("audio/*", "video/*"))
            }
            op.needsParams -> pendingOp = op
        }
    }

    Surface(modifier = modifier.fillMaxSize(), color = MaterialTheme.colorScheme.background) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .safeDrawingPadding()
                .verticalScroll(rememberScrollState())
                .padding(16.dp)
        ) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.Top,
            ) {
                Column {
                    Text("Resound", style = MaterialTheme.typography.headlineSmall)
                    Text(
                        current?.displayName ?: "No file loaded",
                        style = MaterialTheme.typography.bodySmall,
                    )
                }
                TextButton(onClick = { showAbout = true }) { Text("About") }
            }

            Row(
                modifier = Modifier.fillMaxWidth().padding(top = 12.dp),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                Button(
                    onClick = { picker.launch(arrayOf("audio/*", "video/*")) },
                    enabled = !busy && !recording,
                    modifier = Modifier.weight(1f),
                ) { Text("Open") }
                if (recording) {
                    Button(
                        onClick = { onRecordTap() },
                        colors = ButtonDefaults.buttonColors(containerColor = Amber, contentColor = Color.Black),
                        modifier = Modifier.weight(1f),
                    ) { Text("Stop ${fmt(recordElapsed * 1000)}") }
                } else {
                    FilledTonalButton(
                        onClick = { onRecordTap() },
                        enabled = !busy,
                        modifier = Modifier.weight(1f),
                    ) { Text("Record") }
                }
                OutlinedButton(
                    onClick = { onPlayPause() },
                    enabled = current != null && !busy && !recording,
                    modifier = Modifier.weight(1f),
                ) { Text(if (playing) "Pause" else "Play") }
            }

            val wf = waveform
            if (wf != null) {
                Surface(
                    color = Panel,
                    shape = RoundedCornerShape(14.dp),
                    modifier = Modifier.fillMaxWidth().padding(top = 14.dp),
                ) {
                    Column(modifier = Modifier.padding(12.dp)) {
                        WaveformView(
                            waveform = wf,
                            selStartMs = selStart,
                            selEndMs = selEnd,
                            playheadMs = playhead,
                            onSelectionChange = { s, e -> selStart = s; selEnd = e },
                        )
                        Text(
                            "${fmt(selStart)} – ${fmt(selEnd)}   ·   ${fmt(selEnd - selStart)}",
                            style = TimecodeStyle,
                            color = Signal,
                            modifier = Modifier.padding(top = 10.dp),
                        )
                    }
                }
            }

            Text(status, modifier = Modifier.padding(top = 10.dp), style = MaterialTheme.typography.bodySmall)

            val hasFile = current != null

            Column(
                modifier = Modifier.fillMaxWidth().wrapContentHeight().padding(top = 16.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                EditOp.ALL.chunked(3).forEach { rowItems ->
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                    ) {
                        rowItems.forEach { op ->
                            FilledTonalButton(
                                onClick = { onTap(op) },
                                enabled = hasFile && !busy && !recording,
                                modifier = Modifier.weight(1f),
                            ) { Text(op.label) }
                        }
                        repeat(3 - rowItems.size) { Spacer(Modifier.weight(1f)) }
                    }
                }
            }

            Row(
                modifier = Modifier.fillMaxWidth().padding(top = 16.dp),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                if (hasFile) {
                    OutlinedButton(
                        onClick = { onRingtone() },
                        enabled = !busy && !recording,
                        modifier = Modifier.weight(1f),
                    ) { Text("Ringtone") }
                }
                OutlinedButton(
                    onClick = onOpenTimeline,
                    enabled = !busy && !recording,
                    modifier = Modifier.weight(1f),
                ) { Text("Multitrack ▸") }
            }
        }
    }

    val op = pendingOp
    if (op != null) {
        OpDialog(
            op = op,
            onDismiss = { pendingOp = null },
        ) { params ->
            pendingOp = null
            onParams(op, params)
        }
    }

    if (showAbout) {
        AboutDialog(onDismiss = { showAbout = false })
    }
}
