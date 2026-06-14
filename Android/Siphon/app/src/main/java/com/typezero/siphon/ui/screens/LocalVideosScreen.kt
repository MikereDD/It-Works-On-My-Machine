package com.typezero.siphon.ui.screens

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.filled.VideoLibrary
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.typezero.siphon.data.model.VideoItem
import com.typezero.siphon.ui.SiphonUiState
import com.typezero.siphon.ui.SiphonViewModel
import com.typezero.siphon.ui.components.formatDuration
import com.typezero.siphon.ui.components.formatSize

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun LocalVideosScreen(
    state: SiphonUiState,
    vm: SiphonViewModel,
    onRequestPermission: () -> Unit
) {
    Column(Modifier.fillMaxSize()) {
        if (!state.hasMediaPermission) {
            PermissionPrompt(onRequestPermission); return
        }

        OutlinedTextField(
            value = state.searchQuery,
            onValueChange = vm::setSearch,
            placeholder = { Text("Search videos") },
            leadingIcon = { Icon(Icons.Default.Search, null) },
            singleLine = true,
            modifier = Modifier.fillMaxWidth().padding(16.dp)
        )

        when {
            state.videosLoading -> Box(Modifier.fillMaxSize(), Alignment.Center) { CircularProgressIndicator() }
            state.visibleVideos.isEmpty() -> EmptyState(
                if (state.searchQuery.isBlank()) "No videos found on this device."
                else "No videos match \"${state.searchQuery}\"."
            )
            else -> LazyColumn(
                Modifier.fillMaxSize(),
                contentPadding = PaddingValues(horizontal = 12.dp, vertical = 4.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                items(state.visibleVideos, key = { it.id }) { v ->
                    VideoRow(v) { vm.openSheetForVideo(v) }
                }
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun VideoRow(video: VideoItem, onClick: () -> Unit) {
    ElevatedCard(onClick = onClick, modifier = Modifier.fillMaxWidth()) {
        Row(
            Modifier.padding(14.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            Icon(Icons.Default.VideoLibrary, null, tint = MaterialTheme.colorScheme.primary)
            Column(Modifier.weight(1f)) {
                Text(video.displayName, style = MaterialTheme.typography.bodyLarge,
                    fontWeight = FontWeight.Medium, maxLines = 1, overflow = TextOverflow.Ellipsis)
                val meta = buildString {
                    append(formatDuration(video.durationMs))
                    formatSize(video.sizeBytes).takeIf { it.isNotEmpty() }?.let { append("  •  $it") }
                }
                Text(meta, style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
    }
}

@Composable
private fun PermissionPrompt(onRequest: () -> Unit) {
    Column(Modifier.fillMaxSize().padding(32.dp), verticalArrangement = Arrangement.Center,
        horizontalAlignment = Alignment.CenterHorizontally) {
        Icon(Icons.Default.VideoLibrary, null, modifier = Modifier.size(48.dp),
            tint = MaterialTheme.colorScheme.primary)
        Spacer(Modifier.height(16.dp))
        Text("Siphon needs access to your videos to list them here.",
            style = MaterialTheme.typography.bodyLarge)
        Spacer(Modifier.height(20.dp))
        Button(onClick = onRequest) { Text("Grant access") }
    }
}

@Composable
private fun EmptyState(message: String) {
    Box(Modifier.fillMaxSize().padding(32.dp), Alignment.Center) {
        Text(message, style = MaterialTheme.typography.bodyLarge,
            color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}
