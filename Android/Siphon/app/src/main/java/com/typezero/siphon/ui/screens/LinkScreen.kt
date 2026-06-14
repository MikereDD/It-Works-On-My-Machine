package com.typezero.siphon.ui.screens

import androidx.compose.foundation.layout.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ContentPaste
import androidx.compose.material.icons.filled.Link
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.typezero.siphon.ui.SiphonUiState
import com.typezero.siphon.ui.SiphonViewModel
import com.typezero.siphon.ui.components.ChipRow
import com.typezero.siphon.data.model.YouTubeClient

@Composable
fun LinkScreen(state: SiphonUiState, vm: SiphonViewModel) {
    val clipboard = LocalClipboardManager.current
    Column(
        Modifier.fillMaxSize().padding(20.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp)
    ) {
        Text("Audio from a link", style = MaterialTheme.typography.titleLarge,
            fontWeight = FontWeight.SemiBold)
        Text("Paste a video or audio URL. Siphon downloads the stream and extracts the audio in your chosen format.",
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant)

        OutlinedTextField(
            value = state.linkUrl,
            onValueChange = vm::setLinkUrl,
            label = { Text("URL") },
            leadingIcon = { Icon(Icons.Default.Link, null) },
            trailingIcon = {
                IconButton(onClick = {
                    clipboard.getText()?.text?.let(vm::setLinkUrl)
                }) { Icon(Icons.Default.ContentPaste, contentDescription = "Paste") }
            },
            singleLine = true,
            modifier = Modifier.fillMaxWidth()
        )

        Button(
            onClick = vm::openSheetForLink,
            enabled = state.linkUrl.isNotBlank(),
            modifier = Modifier.fillMaxWidth().height(52.dp)
        ) { Text("Choose format & tags") }

        Text(
            "If a YouTube link is blocked (\"403\"), try a different player and extract again:",
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
        ChipRow(
            options = YouTubeClient.entries,
            selected = state.linkClient,
            label = { it.label },
            onSelect = vm::setLinkClient
        )

        AssistChip(onClick = {}, label = {
            Text("Only extract content you own or have the right to use.",
                style = MaterialTheme.typography.bodySmall)
        })
    }
}
