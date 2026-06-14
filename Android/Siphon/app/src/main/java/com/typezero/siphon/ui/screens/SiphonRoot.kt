package com.typezero.siphon.ui.screens

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.typezero.siphon.data.model.JobState
import com.typezero.siphon.ui.Tab as SourceTab
import com.typezero.siphon.ui.SiphonViewModel

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SiphonRoot(vm: SiphonViewModel, onRequestPermission: () -> Unit) {
    val state by vm.state.collectAsStateWithLifecycle()
    val snackbarHostState = remember { SnackbarHostState() }
    var menuOpen by remember { mutableStateOf(false) }

    LaunchedEffect(state.snackbar) {
        state.snackbar?.let {
            snackbarHostState.showSnackbar(it)
            vm.consumeSnackbar()
        }
    }

    Scaffold(
        snackbarHost = { SnackbarHost(snackbarHostState) },
        topBar = {
            CenterAlignedTopAppBar(
                title = { Text("Siphon", fontWeight = FontWeight.Bold) },
                actions = {
                    if (state.extractorUpdating) {
                        CircularProgressIndicator(
                            modifier = Modifier.size(22.dp),
                            strokeWidth = 2.dp
                        )
                        Spacer(Modifier.width(8.dp))
                    }
                    IconButton(onClick = { menuOpen = true }) {
                        Icon(Icons.Default.MoreVert, contentDescription = "Menu")
                    }
                    DropdownMenu(expanded = menuOpen, onDismissRequest = { menuOpen = false }) {
                        DropdownMenuItem(
                            text = { Text("Update extractor") },
                            leadingIcon = { Icon(Icons.Default.Update, null) },
                            enabled = !state.extractorUpdating,
                            onClick = { menuOpen = false; vm.updateExtractor(nightly = false) }
                        )
                        DropdownMenuItem(
                            text = { Text("Update extractor (nightly)") },
                            leadingIcon = { Icon(Icons.Default.Bolt, null) },
                            enabled = !state.extractorUpdating,
                            onClick = { menuOpen = false; vm.updateExtractor(nightly = true) }
                        )
                    }
                }
            )
        }
    ) { padding ->
        Column(Modifier.fillMaxSize().padding(padding)) {
            TabRow(selectedTabIndex = state.tab.ordinal) {
                Tab(selected = state.tab == SourceTab.LOCAL, onClick = { vm.selectTab(SourceTab.LOCAL) },
                    text = { Text("Local video") },
                    icon = { Icon(Icons.Default.VideoLibrary, null) })
                Tab(selected = state.tab == SourceTab.LINK, onClick = { vm.selectTab(SourceTab.LINK) },
                    text = { Text("Link") },
                    icon = { Icon(Icons.Default.Link, null) })
            }

            Box(Modifier.weight(1f)) {
                when (state.tab) {
                    SourceTab.LOCAL -> LocalVideosScreen(state, vm, onRequestPermission)
                    SourceTab.LINK -> LinkScreen(state, vm)
                }
            }

            state.activeJob?.let { ActiveJobBar(it, onCancel = vm::cancelActive) }
            if (state.history.isNotEmpty()) HistorySection(state.history)
        }
    }

    if (state.sheetOpen && state.pendingSource != null) ExtractSheet(state, vm)
}

@Composable
private fun ActiveJobBar(job: JobState, onCancel: () -> Unit) {
    Surface(tonalElevation = 3.dp, color = MaterialTheme.colorScheme.surfaceVariant) {
        Column(Modifier.fillMaxWidth().padding(16.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(job.title, Modifier.weight(1f), maxLines = 1,
                    overflow = TextOverflow.Ellipsis, style = MaterialTheme.typography.bodyMedium,
                    fontWeight = FontWeight.Medium)
                TextButton(onClick = onCancel) { Text("Cancel") }
            }
            Spacer(Modifier.height(8.dp))
            if (job.progress < 0f) LinearProgressIndicator(Modifier.fillMaxWidth())
            else LinearProgressIndicator(progress = { job.progress }, modifier = Modifier.fillMaxWidth())
            if (job.line.isNotBlank()) {
                Spacer(Modifier.height(6.dp))
                Text(job.line, style = MaterialTheme.typography.bodySmall, maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                    color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
    }
}

@Composable
private fun HistorySection(history: List<JobState>) {
    Surface(tonalElevation = 1.dp) {
        Column(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp)) {
            Text("Recent", style = MaterialTheme.typography.labelLarge,
                color = MaterialTheme.colorScheme.primary)
            LazyColumn(Modifier.heightIn(max = 180.dp),
                verticalArrangement = Arrangement.spacedBy(4.dp)) {
                items(history, key = { it.id }) { job -> HistoryRow(job) }
            }
        }
    }
}

@Composable
private fun HistoryRow(job: JobState) {
    val (icon, tint) = when (job.status) {
        JobState.Status.DONE -> Icons.Default.CheckCircle to MaterialTheme.colorScheme.primary
        JobState.Status.FAILED -> Icons.Default.Error to MaterialTheme.colorScheme.error
        JobState.Status.CANCELLED -> Icons.Default.Cancel to MaterialTheme.colorScheme.onSurfaceVariant
        else -> Icons.Default.HourglassEmpty to MaterialTheme.colorScheme.onSurfaceVariant
    }
    Row(Modifier.fillMaxWidth().padding(vertical = 6.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(10.dp)) {
        Icon(icon as ImageVector, null, tint = tint, modifier = Modifier.size(20.dp))
        Column(Modifier.weight(1f)) {
            Text(job.title, style = MaterialTheme.typography.bodyMedium, maxLines = 1,
                overflow = TextOverflow.Ellipsis)
            val sub = job.error ?: job.outputPath ?: ""
            if (sub.isNotBlank()) Text(sub, style = MaterialTheme.typography.bodySmall,
                maxLines = 1, overflow = TextOverflow.Ellipsis,
                color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}
