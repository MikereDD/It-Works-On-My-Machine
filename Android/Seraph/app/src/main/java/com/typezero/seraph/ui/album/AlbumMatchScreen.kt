package com.typezero.seraph.ui.album

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.ArrowBack
import androidx.compose.material.icons.rounded.Search
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.typezero.seraph.data.album.AlbumPlanRow
import com.typezero.seraph.data.model.ReleaseCandidate
import com.typezero.seraph.data.model.ReleaseDetail

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AlbumMatchScreen(
    state: AlbumUiState,
    onQueryChange: (String) -> Unit,
    onSearch: () -> Unit,
    onPick: (ReleaseCandidate) -> Unit,
    onToggleRename: () -> Unit,
    onToggleArt: () -> Unit,
    onApply: () -> Unit,
    onBackToPick: () -> Unit,
    onBack: () -> Unit,
) {
    Scaffold(
        topBar = {
            TopAppBar(
                title = {
                    Column {
                        Text("Album match", maxLines = 1, overflow = TextOverflow.Ellipsis)
                        if (state.folderName.isNotBlank()) {
                            Text(
                                state.folderName,
                                style = MaterialTheme.typography.labelSmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                                maxLines = 1,
                                overflow = TextOverflow.Ellipsis,
                            )
                        }
                    }
                },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Rounded.ArrowBack, contentDescription = "Back")
                    }
                },
            )
        },
    ) { pad ->
        Column(Modifier.fillMaxSize().padding(pad)) {
            when (state.stage) {
                AlbumStage.Searching -> Busy("Searching MusicBrainz…")
                AlbumStage.Applying -> Busy("Applying tags…")
                AlbumStage.Pick -> PickStage(state, onQueryChange, onSearch, onPick)
                AlbumStage.Review -> ReviewStage(
                    state, onToggleRename, onToggleArt, onApply, onBackToPick,
                )
            }
        }
    }
}

@Composable
private fun Busy(label: String) {
    Column(
        Modifier.fillMaxSize(),
        verticalArrangement = Arrangement.Center,
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        CircularProgressIndicator()
        Spacer(Modifier.height(16.dp))
        Text(label, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun PickStage(
    state: AlbumUiState,
    onQueryChange: (String) -> Unit,
    onSearch: () -> Unit,
    onPick: (ReleaseCandidate) -> Unit,
) {
    OutlinedTextField(
        value = state.query,
        onValueChange = onQueryChange,
        modifier = Modifier.fillMaxWidth().padding(16.dp, 8.dp),
        label = { Text("Album search") },
        singleLine = true,
        trailingIcon = {
            IconButton(onClick = onSearch) { Icon(Icons.Rounded.Search, contentDescription = "Search") }
        },
        keyboardActions = androidx.compose.foundation.text.KeyboardActions(onSearch = { onSearch() }),
        keyboardOptions = androidx.compose.foundation.text.KeyboardOptions(imeAction = ImeAction.Search),
    )
    state.message?.let { Hint(it) }
    LazyColumn(Modifier.fillMaxSize()) {
        items(state.candidates) { c ->
            Column(
                Modifier.fillMaxWidth().clickable { onPick(c) }.padding(16.dp, 12.dp),
            ) {
                Text(c.title, style = MaterialTheme.typography.titleMedium, maxLines = 1, overflow = TextOverflow.Ellipsis)
                Text(
                    buildString {
                        append(c.artist.ifBlank { "Unknown artist" })
                        if (c.year.isNotBlank()) append(" · ${c.year}")
                        if (c.trackCount > 0) append(" · ${c.trackCount} tracks")
                    },
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
            }
            HorizontalDivider(color = MaterialTheme.colorScheme.outline.copy(alpha = 0.15f))
        }
    }
}

@Composable
private fun ReviewStage(
    state: AlbumUiState,
    onToggleRename: () -> Unit,
    onToggleArt: () -> Unit,
    onApply: () -> Unit,
    onBackToPick: () -> Unit,
) {
    val release: ReleaseDetail? = state.release
    LazyColumn(Modifier.fillMaxSize()) {
        item {
            Column(Modifier.fillMaxWidth().padding(16.dp, 12.dp)) {
                Text(
                    release?.title ?: "",
                    style = MaterialTheme.typography.titleLarge,
                    maxLines = 2,
                    overflow = TextOverflow.Ellipsis,
                )
                Text(
                    buildString {
                        append(release?.artist?.ifBlank { "Unknown artist" } ?: "")
                        val yr = release?.year.orEmpty()
                        if (yr.isNotBlank()) append(" · $yr")
                        append(" · matched ${state.rows.size} of ${release?.total ?: 0}")
                    },
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                Spacer(Modifier.height(4.dp))
                TextButton(onClick = onBackToPick) { Text("Choose a different release") }
            }
            HorizontalDivider(color = MaterialTheme.colorScheme.outline.copy(alpha = 0.2f))
            ToggleRow("Rename files to match", state.rename, onToggleRename)
            ToggleRow("Embed album cover art", state.embedArt, onToggleArt)
            HorizontalDivider(color = MaterialTheme.colorScheme.outline.copy(alpha = 0.2f))
            state.message?.let { Hint(it) }
        }
        itemsIndexed(state.rows) { _, row -> RowItem(row, state.rename) }
        item {
            Column(Modifier.fillMaxWidth().padding(16.dp)) {
                Button(
                    onClick = onApply,
                    modifier = Modifier.fillMaxWidth(),
                    enabled = state.rows.isNotEmpty() && !state.busy,
                ) {
                    Text(
                        if (state.rename) "Tag & rename ${state.rows.size} files"
                        else "Tag ${state.rows.size} files",
                    )
                }
            }
        }
    }
}

@Composable
private fun ToggleRow(label: String, checked: Boolean, onToggle: () -> Unit) {
    Row(
        Modifier.fillMaxWidth().clickable { onToggle() }.padding(16.dp, 10.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(label, style = MaterialTheme.typography.bodyLarge, modifier = Modifier.weight(1f))
        Switch(checked = checked, onCheckedChange = { onToggle() })
    }
}

@Composable
private fun RowItem(row: AlbumPlanRow, showRename: Boolean) {
    Row(Modifier.fillMaxWidth().padding(16.dp, 8.dp), verticalAlignment = Alignment.Top) {
        Text(
            row.position.toString().padStart(2, '0'),
            style = MaterialTheme.typography.titleSmall,
            color = MaterialTheme.colorScheme.primary,
            modifier = Modifier.width(28.dp),
        )
        Spacer(Modifier.width(8.dp))
        Column(Modifier.weight(1f)) {
            Text(
                row.title.ifBlank { "(untitled)" },
                style = MaterialTheme.typography.bodyLarge,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
            Text(
                "was: ${row.file.displayName}",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
            if (showRename) {
                Text(
                    "→ ${row.proposedName}",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.primary,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
            }
        }
    }
    HorizontalDivider(color = MaterialTheme.colorScheme.outline.copy(alpha = 0.12f))
}

@Composable
private fun Hint(text: String) {
    Text(
        text,
        style = MaterialTheme.typography.bodySmall,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
        modifier = Modifier.padding(16.dp, 4.dp),
    )
}
