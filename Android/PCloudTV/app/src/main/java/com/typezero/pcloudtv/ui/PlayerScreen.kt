package com.typezero.pcloudtv.ui

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
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
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.media3.common.MediaItem
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.ui.PlayerView
import com.typezero.pcloudtv.data.ApiResult
import com.typezero.pcloudtv.data.PCloudClient
import com.typezero.pcloudtv.data.PItem
import com.typezero.pcloudtv.data.Session

@Composable
fun PlayerScreen(
    client: PCloudClient,
    session: Session,
    item: PItem,
    onExit: () -> Unit
) {
    var streamUrl by remember(item) { mutableStateOf<String?>(null) }
    var error by remember(item) { mutableStateOf<String?>(null) }

    BackHandler { onExit() }

    LaunchedEffect(item) {
        when (val r = client.getStreamUrl(session, item.fileId!!)) {
            is ApiResult.Ok -> streamUrl = r.value
            is ApiResult.Error -> error = r.message
        }
    }

    Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
        val url = streamUrl
        when {
            error != null -> Text(
                "Could not play \"${item.name}\": $error",
                color = MaterialTheme.colorScheme.error,
                modifier = Modifier.padding(40.dp)
            )

            url == null -> CircularProgressIndicator(color = MaterialTheme.colorScheme.primary)

            else -> Player(url = url, title = item.name)
        }
    }
}

@Composable
private fun Player(url: String, title: String) {
    val context = LocalContext.current

    val exo = remember(url) {
        ExoPlayer.Builder(context).build().apply {
            setMediaItem(MediaItem.fromUri(url))
            prepare()
            playWhenReady = true
        }
    }

    DisposableEffect(exo) {
        onDispose { exo.release() }
    }

    AndroidView(
        modifier = Modifier.fillMaxSize(),
        factory = { ctx ->
            PlayerView(ctx).apply {
                player = exo
                setShowBuffering(PlayerView.SHOW_BUFFERING_ALWAYS)
                setBackgroundColor(android.graphics.Color.BLACK)
                requestFocus()
            }
        }
    )

    // Show the file name briefly via the player's content description (helps audio files).
    Box(modifier = Modifier.fillMaxSize()) {
        Text(
            title,
            color = Color(0xCCFFFFFF),
            modifier = Modifier
                .align(Alignment.TopStart)
                .padding(32.dp)
        )
    }
}
