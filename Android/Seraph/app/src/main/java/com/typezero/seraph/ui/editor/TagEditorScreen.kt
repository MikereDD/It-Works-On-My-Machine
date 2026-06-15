package com.typezero.seraph.ui.editor

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
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.ArrowBack
import androidx.compose.material.icons.rounded.Search
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.typezero.seraph.data.model.MusicBrainzResult
import com.typezero.seraph.data.model.Tags
import com.typezero.seraph.ui.components.Artwork
import com.typezero.seraph.ui.components.TagField

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun TagEditorScreen(
    state: EditorUiState,
    onBack: () -> Unit,
    onEdit: ((Tags) -> Tags) -> Unit,
    onLookup: () -> Unit,
    onApply: (MusicBrainzResult) -> Unit,
    onSave: () -> Unit,
) {
    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(state.fileName, maxLines = 1, overflow = TextOverflow.Ellipsis) },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Rounded.ArrowBack, contentDescription = "Back")
                    }
                },
            )
        },
    ) { pad ->
        if (state.isLoading) {
            Column(Modifier.fillMaxSize().padding(pad), Arrangement.Center, Alignment.CenterHorizontally) {
                CircularProgressIndicator()
            }
            return@Scaffold
        }

        val t = state.tags
        Column(
            modifier = Modifier.fillMaxSize().padding(pad).verticalScroll(rememberScrollState()).padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(16.dp)) {
                Artwork(t.artwork, size = 96.dp)
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Button(onClick = onLookup, enabled = !state.isSearching, modifier = Modifier.fillMaxWidth()) {
                        if (state.isSearching) {
                            CircularProgressIndicator(Modifier.size(16.dp), strokeWidth = 2.dp, color = MaterialTheme.colorScheme.onPrimary)
                        } else {
                            Icon(Icons.Rounded.Search, null, Modifier.size(18.dp))
                        }
                        Spacer(Modifier.size(8.dp))
                        Text("MusicBrainz lookup")
                    }
                    Text(
                        "Suggestions fill the fields — you stay in control of every value.",
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }

            if (state.candidates.isNotEmpty()) {
                Text("Matches", style = MaterialTheme.typography.labelLarge, color = MaterialTheme.colorScheme.primary)
                state.candidates.forEach { c -> CandidateCard(c, onApply = { onApply(c) }) }
            }

            TagField("Title", t.title, { v -> onEdit { it.copy(title = v) } }, Modifier.fillMaxWidth())
            TagField("Artist", t.artist, { v -> onEdit { it.copy(artist = v) } }, Modifier.fillMaxWidth())
            TagField("Album", t.album, { v -> onEdit { it.copy(album = v) } }, Modifier.fillMaxWidth())
            TagField("Album artist", t.albumArtist, { v -> onEdit { it.copy(albumArtist = v) } }, Modifier.fillMaxWidth())
            Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                TagField("Track", t.trackNumber, { v -> onEdit { it.copy(trackNumber = v) } }, Modifier.weight(1f), numeric = true)
                TagField("of", t.trackTotal, { v -> onEdit { it.copy(trackTotal = v) } }, Modifier.weight(1f), numeric = true)
                TagField("Disc", t.discNumber, { v -> onEdit { it.copy(discNumber = v) } }, Modifier.weight(1f), numeric = true)
            }
            Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                TagField("Year", t.year, { v -> onEdit { it.copy(year = v) } }, Modifier.weight(1f), numeric = true)
                TagField("Genre", t.genre, { v -> onEdit { it.copy(genre = v) } }, Modifier.weight(2f))
            }
            TagField("Comment", t.comment, { v -> onEdit { it.copy(comment = v) } }, Modifier.fillMaxWidth())

            state.message?.let {
                Text(it, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.tertiary)
            }

            Spacer(Modifier.height(4.dp))
            Button(
                onClick = onSave,
                enabled = state.dirty && !state.isSaving,
                modifier = Modifier.fillMaxWidth(),
            ) {
                if (state.isSaving) {
                    CircularProgressIndicator(Modifier.size(16.dp), strokeWidth = 2.dp, color = MaterialTheme.colorScheme.onPrimary)
                    Spacer(Modifier.size(8.dp))
                }
                Text(if (state.dirty) "Save tags" else "Saved")
            }
            Spacer(Modifier.height(24.dp))
        }
    }
}

@Composable
private fun CandidateCard(c: MusicBrainzResult, onApply: () -> Unit) {
    Surface(
        modifier = Modifier.fillMaxWidth().clickable(onClick = onApply),
        color = MaterialTheme.colorScheme.surfaceVariant,
        shape = MaterialTheme.shapes.medium,
    ) {
        Row(Modifier.padding(12.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            Column(Modifier.weight(1f)) {
                Text(c.title.ifBlank { "(untitled)" }, style = MaterialTheme.typography.titleMedium, maxLines = 1, overflow = TextOverflow.Ellipsis)
                Text(
                    buildString {
                        append(c.artist.ifBlank { "Unknown artist" })
                        if (c.album.isNotBlank()) append(" — ${c.album}")
                        if (c.year.isNotBlank()) append(" (${c.year})")
                    },
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
            }
            Text("${c.score}%", style = MaterialTheme.typography.labelSmall, fontWeight = FontWeight.Bold, color = scoreColor(c.score))
            OutlinedButton(onClick = onApply) { Text("Apply") }
        }
    }
}

@Composable
private fun scoreColor(score: Int) = when {
    score >= 90 -> MaterialTheme.colorScheme.primary
    score >= 70 -> MaterialTheme.colorScheme.tertiary
    else -> MaterialTheme.colorScheme.onSurfaceVariant
}
