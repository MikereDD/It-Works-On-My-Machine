package com.typezero.siphon.ui.screens

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.GraphicEq
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import com.typezero.siphon.data.model.*
import com.typezero.siphon.ui.SiphonUiState
import com.typezero.siphon.ui.SiphonViewModel
import com.typezero.siphon.ui.components.ChipRow

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ExtractSheet(state: SiphonUiState, vm: SiphonViewModel) {
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    val isLink = state.pendingSource is ExtractRequest.Source.Link

    ModalBottomSheet(onDismissRequest = vm::closeSheet, sheetState = sheetState) {
        Column(
            Modifier
                .fillMaxWidth()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 20.dp)
                .padding(bottom = 28.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp)
        ) {
            Row(verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                Icon(Icons.Default.GraphicEq, contentDescription = null,
                    tint = MaterialTheme.colorScheme.primary)
                Text("Extract audio", style = MaterialTheme.typography.titleLarge,
                    fontWeight = FontWeight.SemiBold)
            }

            SectionLabel("Format")
            ChipRow(
                options = AudioFormat.entries,
                selected = state.format,
                label = { it.label },
                onSelect = vm::setFormat
            )

            if (state.format.lossy) {
                SectionLabel("Bitrate")
                ChipRow(
                    options = AudioQuality.entries,
                    selected = state.quality,
                    label = { it.label },
                    onSelect = vm::setQuality
                )
            } else {
                AssistChipNote(
                    if (state.format == AudioFormat.COPY)
                        "Keeps the original audio stream — no re-encoding, no quality loss."
                    else "Lossless format — bitrate not applicable."
                )
            }

            SectionLabel("File name")
            OutlinedTextField(
                value = state.outputName,
                onValueChange = vm::setOutputName,
                placeholder = { Text(if (isLink) "Leave blank to use source title" else "Output name") },
                singleLine = true,
                modifier = Modifier.fillMaxWidth()
            )

            HorizontalDivider()
            SectionLabel("Tags")

            val t = state.tags
            TagField("Title", t.title) { v -> vm.updateTags { it.copy(title = v) } }
            TagField("Artist", t.artist) { v -> vm.updateTags { it.copy(artist = v) } }
            TagField("Album", t.album) { v -> vm.updateTags { it.copy(album = v) } }
            TagField("Album artist", t.albumArtist) { v -> vm.updateTags { it.copy(albumArtist = v) } }
            Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                TagField("Genre", t.genre, Modifier.weight(1f)) { v -> vm.updateTags { it.copy(genre = v) } }
                TagField("Year", t.year, Modifier.weight(1f), KeyboardType.Number) { v ->
                    vm.updateTags { it.copy(year = v.filter(Char::isDigit).take(4)) }
                }
            }
            TagField("Track #", t.track, keyboard = KeyboardType.Number) { v ->
                vm.updateTags { it.copy(track = v.filter(Char::isDigit)) }
            }
            TagField("Comment", t.comment) { v -> vm.updateTags { it.copy(comment = v) } }

            SwitchRow("Embed source metadata", t.embedSourceMetadata) { on ->
                vm.updateTags { it.copy(embedSourceMetadata = on) }
            }
            if (isLink) {
                SwitchRow("Embed thumbnail as cover art", t.embedThumbnail) { on ->
                    vm.updateTags { it.copy(embedThumbnail = on) }
                }
            }

            Spacer(Modifier.height(4.dp))
            Button(
                onClick = vm::startExtraction,
                modifier = Modifier.fillMaxWidth().height(52.dp)
            ) { Text("Extract", style = MaterialTheme.typography.titleMedium) }
        }
    }
}

@Composable
private fun SectionLabel(text: String) =
    Text(text, style = MaterialTheme.typography.labelLarge,
        color = MaterialTheme.colorScheme.primary, fontWeight = FontWeight.SemiBold)

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun AssistChipNote(text: String) =
    AssistChip(onClick = {}, label = { Text(text, style = MaterialTheme.typography.bodySmall) })

@Composable
private fun TagField(
    label: String,
    value: String,
    modifier: Modifier = Modifier,
    keyboard: KeyboardType = KeyboardType.Text,
    onChange: (String) -> Unit
) {
    OutlinedTextField(
        value = value,
        onValueChange = onChange,
        label = { Text(label) },
        singleLine = true,
        keyboardOptions = KeyboardOptions(keyboardType = keyboard),
        modifier = modifier.then(if (modifier == Modifier) Modifier.fillMaxWidth() else Modifier)
    )
}

@Composable
private fun SwitchRow(label: String, checked: Boolean, onChange: (Boolean) -> Unit) {
    Row(
        Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically
    ) {
        Text(label, style = MaterialTheme.typography.bodyMedium)
        Switch(checked = checked, onCheckedChange = onChange)
    }
}
