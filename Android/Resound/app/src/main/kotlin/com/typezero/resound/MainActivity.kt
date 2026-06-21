/*
 * file:    MainActivity.kt
 * author:  Mike Redd (typezero)
 * version: 0.5.0
 * desc:    Single-activity host. Switches between the single-file editor and the
 *          multitrack timeline.
 */
package com.typezero.resound

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import com.typezero.resound.di.AppContainer
import com.typezero.resound.feature.edit.EditScreen
import com.typezero.resound.feature.timeline.TimelineScreen
import com.typezero.resound.ui.theme.ResoundTheme

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        val container = (application as ResoundApp).container
        setContent {
            ResoundTheme {
                Root(container)
            }
        }
    }
}

private enum class Screen { Edit, Timeline }

@Composable
private fun Root(container: AppContainer) {
    var screen by remember { mutableStateOf(Screen.Edit) }
    when (screen) {
        Screen.Edit -> EditScreen(
            waveformExtractor = container.waveformExtractor,
            ffmpeg = container.ffmpeg,
            recorder = container.recorder,
            onOpenTimeline = { screen = Screen.Timeline },
        )
        Screen.Timeline -> TimelineScreen(
            waveformExtractor = container.waveformExtractor,
            ffmpeg = container.ffmpeg,
            onBack = { screen = Screen.Edit },
        )
    }
}
