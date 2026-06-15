package com.typezero.seraph.ui.library

import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.ArrowBack
import androidx.compose.material.icons.rounded.Album
import androidx.compose.material.icons.rounded.CheckCircle
import androidx.compose.material.icons.rounded.ChevronRight
import androidx.compose.material.icons.rounded.Close
import androidx.compose.material.icons.rounded.Cloud
import androidx.compose.material.icons.rounded.DoneAll
import androidx.compose.material.icons.rounded.DriveFileRenameOutline
import androidx.compose.material.icons.rounded.Folder
import androidx.compose.material.icons.rounded.Info
import androidx.compose.material.icons.rounded.MusicNote
import androidx.compose.material.icons.rounded.PhoneAndroid
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.typezero.seraph.data.model.AudioFile
import com.typezero.seraph.storage.FolderNode
import com.typezero.seraph.storage.StorageSource

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun LibraryScreen(
    state: LibraryUiState,
    onPickDevice: () -> Unit,
    onSelectPCloud: () -> Unit,
    onOpenFolder: (FolderNode) -> Unit,
    onUp: () -> Unit,
    onOpen: (AudioFile) -> Unit,
    onRename: () -> Unit,
    onAlbumMatch: () -> Unit,
    onToggleSelect: (AudioFile) -> Unit,
    onSelectAll: () -> Unit,
    onClearSelection: () -> Unit,
    onAbout: () -> Unit,
) {
    Scaffold(
        topBar = {
            if (state.selectionMode) {
                TopAppBar(
                    title = { Text("${state.selection.size} selected") },
                    navigationIcon = {
                        IconButton(onClick = onClearSelection) {
                            Icon(Icons.Rounded.Close, contentDescription = "Clear selection")
                        }
                    },
                    actions = {
                        IconButton(onClick = onSelectAll) {
                            Icon(Icons.Rounded.DoneAll, contentDescription = if (state.allSelected) "Deselect all" else "Select all")
                        }
                        IconButton(onClick = onAlbumMatch) {
                            Icon(Icons.Rounded.Album, contentDescription = "Match album with MusicBrainz")
                        }
                        IconButton(onClick = onRename) {
                            Icon(Icons.Rounded.DriveFileRenameOutline, contentDescription = "Rename selected")
                        }
                    },
                )
            } else {
                TopAppBar(
                    title = { Text(state.currentName, maxLines = 1, overflow = TextOverflow.Ellipsis) },
                    navigationIcon = {
                        if (!state.atRoot) {
                            IconButton(onClick = onUp) {
                                Icon(Icons.AutoMirrored.Rounded.ArrowBack, contentDescription = "Up a folder")
                            }
                        }
                    },
                    actions = {
                        if (state.files.isNotEmpty()) {
                            IconButton(onClick = onAlbumMatch) {
                                Icon(Icons.Rounded.Album, contentDescription = "Match album with MusicBrainz")
                            }
                            IconButton(onClick = onRename) {
                                Icon(Icons.Rounded.DriveFileRenameOutline, contentDescription = "Rename files in this folder")
                            }
                        }
                        IconButton(onClick = onAbout) {
                            Icon(Icons.Rounded.Info, contentDescription = "About")
                        }
                    },
                )
            }
        },
    ) { pad ->
        Column(Modifier.fillMaxSize().padding(pad)) {
            Row(
                Modifier.fillMaxWidth().padding(16.dp, 12.dp),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                FilterChip(
                    selected = state.activeSourceId == StorageSource.DEVICE,
                    onClick = onPickDevice,
                    label = { Text("Device") },
                    leadingIcon = { Icon(Icons.Rounded.PhoneAndroid, null, Modifier.size(18.dp)) },
                )
                FilterChip(
                    selected = state.activeSourceId == StorageSource.PCLOUD,
                    onClick = onSelectPCloud,
                    label = { Text("pCloud") },
                    leadingIcon = { Icon(Icons.Rounded.Cloud, null, Modifier.size(18.dp)) },
                )
            }
            HorizontalDivider(color = MaterialTheme.colorScheme.outline.copy(alpha = 0.3f))

            when {
                state.isLoading -> Centered { CircularProgressIndicator() }
                !state.hasSource -> Centered {
                    Column(horizontalAlignment = Alignment.CenterHorizontally) {
                        Text("Choose a source to begin.", style = MaterialTheme.typography.bodyMedium)
                        Spacer(Modifier.height(4.dp))
                        Text(
                            "Device picks a folder; pCloud signs in and lists /Music and /Books/Audiobooks.",
                            style = MaterialTheme.typography.labelSmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                }
                else -> LazyColumn(modifier = Modifier.fillMaxSize(), contentPadding = PaddingValues(vertical = 8.dp)) {
                    state.error?.let { item { Notice(it) } }
                    items(state.folders, key = { "d:" + it.id }) { folder ->
                        FolderRow(folder.name, onClick = { onOpenFolder(folder) })
                        HorizontalDivider(color = MaterialTheme.colorScheme.outline.copy(alpha = 0.3f))
                    }
                    items(state.files, key = { "f:" + it.id }) { file ->
                        FileRow(
                            file = file,
                            selected = file.id in state.selection,
                            selectionMode = state.selectionMode,
                            onOpen = { onOpen(file) },
                            onToggle = { onToggleSelect(file) },
                        )
                        HorizontalDivider(color = MaterialTheme.colorScheme.outline.copy(alpha = 0.3f))
                    }
                }
            }
        }
    }
}

@Composable
private fun FolderRow(name: String, onClick: () -> Unit) {
    Row(
        modifier = Modifier.fillMaxWidth().clickable(onClick = onClick).padding(16.dp, 14.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Icon(Icons.Rounded.Folder, null, tint = MaterialTheme.colorScheme.secondary)
        Text(name, Modifier.weight(1f), maxLines = 1, overflow = TextOverflow.Ellipsis, style = MaterialTheme.typography.titleMedium)
        Icon(Icons.Rounded.ChevronRight, null, tint = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun FileRow(
    file: AudioFile,
    selected: Boolean,
    selectionMode: Boolean,
    onOpen: () -> Unit,
    onToggle: () -> Unit,
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .combinedClickable(
                onClick = { if (selectionMode) onToggle() else onOpen() },
                onLongClick = onToggle,
            )
            .background(
                if (selected) MaterialTheme.colorScheme.primary.copy(alpha = 0.12f) else Color.Transparent
            )
            .padding(16.dp, 12.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Icon(
            if (selected) Icons.Rounded.CheckCircle else Icons.Rounded.MusicNote,
            contentDescription = if (selected) "Selected" else null,
            tint = MaterialTheme.colorScheme.primary,
        )
        Column(Modifier.weight(1f)) {
            Text(file.displayName, maxLines = 1, overflow = TextOverflow.Ellipsis, style = MaterialTheme.typography.titleMedium)
            Text(
                "${file.extension.uppercase()} · ${humanSize(file.sizeBytes)}",
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}

@Composable
private fun Notice(text: String) {
    Text(
        text,
        modifier = Modifier.fillMaxWidth().padding(16.dp, 8.dp),
        style = MaterialTheme.typography.bodyMedium,
        color = MaterialTheme.colorScheme.tertiary,
    )
}

@Composable
private fun Centered(content: @Composable () -> Unit) {
    Column(
        modifier = Modifier.fillMaxSize().padding(24.dp),
        verticalArrangement = Arrangement.Center,
        horizontalAlignment = Alignment.CenterHorizontally,
    ) { content() }
}

private fun humanSize(bytes: Long): String {
    if (bytes <= 0) return "—"
    val units = arrayOf("B", "KB", "MB", "GB")
    var v = bytes.toDouble(); var i = 0
    while (v >= 1024 && i < units.lastIndex) { v /= 1024; i++ }
    return "%.1f %s".format(v, units[i])
}
