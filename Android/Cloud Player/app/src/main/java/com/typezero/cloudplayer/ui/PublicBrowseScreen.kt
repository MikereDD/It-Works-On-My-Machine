package com.typezero.cloudplayer.ui

import androidx.activity.compose.BackHandler
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.focusable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ChevronRight
import androidx.compose.material.icons.filled.Folder
import androidx.compose.material.icons.filled.Logout
import androidx.compose.material.icons.filled.Movie
import androidx.compose.material.icons.filled.MusicNote
import androidx.compose.material.icons.filled.Description
import androidx.compose.material.icons.filled.Image
import androidx.compose.material.icons.filled.InsertDriveFile
import androidx.compose.material.icons.filled.QueueMusic
import androidx.compose.material.icons.rounded.CloudQueue
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.typezero.cloudplayer.data.MediaItem
import com.typezero.cloudplayer.data.PItem
import com.typezero.cloudplayer.data.Publink
import com.typezero.cloudplayer.data.PCloudClient
import com.typezero.cloudplayer.ui.theme.Brand

/**
 * Browse / play a pCloud public share link with no account. A file link plays
 * immediately; a folder link is browsed from the in-memory tree.
 */
@Composable
fun PublicBrowseScreen(
    link: Publink,
    client: PCloudClient,
    onPlayQueue: (List<MediaItem>) -> Unit,
    onClose: () -> Unit
) {
    // A single file link: just play it.
    LaunchedEffect(link) {
        if (!link.root.isFolder && link.root.fileId != null) {
            onPlayQueue(listOf(MediaItem(link.root.name, link.root.fileId, null)))
        }
    }
    if (!link.root.isFolder) {
        Box(Modifier.fillMaxSize().background(Brand.pageGradient), Alignment.Center) {
            CircularProgressIndicator(color = Brand.Accent)
        }
        return
    }

    // Folder link: navigate the tree held in link.children.
    val stack = remember {
        mutableStateListOf(link.root.folderId!! to (link.root.name.ifBlank { "Shared" }))
    }
    val current = stack.last()
    val items = link.children[current.first].orEmpty()
    var viewingDoc by remember { mutableStateOf<PItem?>(null) }

    BackHandler { if (stack.size > 1) stack.removeAt(stack.lastIndex) else onClose() }

    val firstRow = remember { FocusRequester() }

    BoxWithConstraints(modifier = Modifier.fillMaxSize().background(Brand.pageGradient)) {
        val compact = maxWidth < 600.dp
        val hPad = if (compact) 18.dp else 56.dp
        val vPad = if (compact) 18.dp else 40.dp
        val rowMax = if (compact) Modifier.fillMaxWidth() else Modifier.width(760.dp)

        Column(modifier = Modifier.fillMaxSize().padding(horizontal = hPad, vertical = vPad)) {
            Row(
                modifier = Modifier.fillMaxWidth().padding(bottom = if (compact) 14.dp else 22.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.SpaceBetween
            ) {
                Row(modifier = Modifier.weight(1f), verticalAlignment = Alignment.CenterVertically) {
                    Box(
                        modifier = Modifier.size(if (compact) 38.dp else 46.dp)
                            .clip(RoundedCornerShape(12.dp))
                            .background(Brand.Glow.copy(alpha = 0.16f)),
                        contentAlignment = Alignment.Center
                    ) {
                        Icon(Icons.Rounded.CloudQueue, contentDescription = null, tint = Brand.Glow,
                            modifier = Modifier.size(if (compact) 22.dp else 26.dp))
                    }
                    Spacer(Modifier.width(14.dp))
                    Column(modifier = Modifier.weight(1f)) {
                        Text(current.second, fontSize = if (compact) 22.sp else 30.sp,
                            fontWeight = FontWeight.Bold, color = Brand.TextHi, maxLines = 1)
                        Text("Shared link  ·  " + stack.joinToString("  ›  ") { it.second },
                            fontSize = 12.sp, color = Brand.TextLow, maxLines = 1)
                    }
                }
                Row(verticalAlignment = Alignment.CenterVertically) {
                    com.typezero.cloudplayer.cast.CastButton(modifier = Modifier.size(40.dp))
                    Spacer(Modifier.width(10.dp))
                    CloseButton(onClose)
                }
            }

            if (items.isEmpty()) {
                Box(Modifier.fillMaxSize(), Alignment.Center) {
                    Text("Nothing playable in this shared folder.",
                        color = Brand.TextLow, fontSize = 15.sp)
                }
            } else {
                LaunchedEffect(current.first) { runCatching { firstRow.requestFocus() } }
                LazyColumn(
                    modifier = Modifier.fillMaxSize(),
                    verticalArrangement = Arrangement.spacedBy(if (compact) 10.dp else 12.dp)
                ) {
                    itemsIndexed(items) { index, pItem ->
                        PublicRow(
                            item = pItem,
                            compact = compact,
                            modifier = rowMax.then(
                                if (index == 0) Modifier.focusRequester(firstRow) else Modifier
                            ),
                            onClick = {
                                when {
                                    pItem.isFolder && pItem.folderId != null ->
                                        stack.add(pItem.folderId to pItem.name)
                                    pItem.isPlaylist -> {
                                        // Build a queue from sibling files this playlist would list.
                                        val siblings = items.filter { !it.isFolder && it.isPlayable && it.fileId != null }
                                        if (siblings.isNotEmpty()) {
                                            onPlayQueue(siblings.map { MediaItem(it.name, it.fileId, null) })
                                        }
                                    }
                                    pItem.isViewableDoc -> viewingDoc = pItem
                                    pItem.isPlayable && pItem.fileId != null ->
                                        onPlayQueue(listOf(MediaItem(pItem.name, pItem.fileId, null)))
                                }
                            }
                        )
                    }
                }
            }
        }

        viewingDoc?.let { doc ->
            DocViewer(
                item = doc,
                onClose = { viewingDoc = null },
                fetchBytes = { id -> client.fetchPublinkDocument(link.apiHost, link.code, id) }
            )
        }
    }
}

@Composable
private fun PublicRow(
    item: PItem,
    compact: Boolean,
    modifier: Modifier = Modifier,
    onClick: () -> Unit
) {
    var focused by remember { mutableStateOf(false) }
    val interaction = remember { MutableInteractionSource() }
    val scale by animateFloatAsState(if (focused) 1.025f else 1f, label = "row")
    val accent = when {
        item.isFolder -> Brand.Folder
        item.isPlaylist -> Brand.Glow
        item.isVideo -> Brand.Video
        item.isImage -> Brand.Accent
        item.isViewableDoc -> Brand.Accent
        item.isAudio -> Brand.Audio
        else -> Brand.TextMid
    }
    val icon = when {
        item.isFolder -> Icons.Filled.Folder
        item.isPlaylist -> Icons.Filled.QueueMusic
        item.isVideo -> Icons.Filled.Movie
        item.isImage -> Icons.Filled.Image
        item.isViewableDoc -> Icons.Filled.Description
        item.isAudio -> Icons.Filled.MusicNote
        else -> Icons.Filled.InsertDriveFile
    }
    val subtitle = when {
        item.isFolder -> "Folder"
        item.isPlaylist -> "Playlist"
        item.isNfo -> "Info · ${humanSize(item.size)}"
        item.isHtmlDoc -> "Web page · ${humanSize(item.size)}"
        else -> humanSize(item.size)
    }
    Row(
        modifier = modifier
            .graphicsLayer { scaleX = scale; scaleY = scale }
            .shadow(if (focused) 14.dp else 0.dp, RoundedCornerShape(16.dp),
                ambientColor = accent, spotColor = accent)
            .clip(RoundedCornerShape(16.dp))
            .background(if (focused) Brand.SurfaceFocused else Brand.Surface)
            .border(if (focused) 1.5.dp else 1.dp, if (focused) accent else Brand.Stroke,
                RoundedCornerShape(16.dp))
            .onFocusChanged { focused = it.isFocused }
            .focusable(interactionSource = interaction)
            .clickable(interactionSource = interaction, indication = null, onClick = onClick)
            .padding(horizontal = if (compact) 14.dp else 18.dp, vertical = if (compact) 12.dp else 14.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Box(
            modifier = Modifier.size(if (compact) 40.dp else 46.dp)
                .clip(RoundedCornerShape(12.dp))
                .background(accent.copy(alpha = if (focused) 0.26f else 0.16f)),
            contentAlignment = Alignment.Center
        ) {
            Icon(icon, contentDescription = null, tint = accent,
                modifier = Modifier.size(if (compact) 22.dp else 26.dp))
        }
        Spacer(Modifier.width(14.dp))
        Column(modifier = Modifier.weight(1f)) {
            Text(item.name, color = Brand.TextHi, fontSize = if (compact) 16.sp else 18.sp,
                fontWeight = FontWeight.Medium, maxLines = 1)
            Text(subtitle, color = Brand.TextLow, fontSize = 12.sp, maxLines = 1)
        }
        if (item.isFolder) {
            Icon(Icons.Filled.ChevronRight, contentDescription = null,
                tint = if (focused) accent else Brand.TextLow, modifier = Modifier.size(24.dp))
        }
    }
}

@Composable
private fun CloseButton(onClose: () -> Unit) {
    var focused by remember { mutableStateOf(false) }
    val interaction = remember { MutableInteractionSource() }
    Row(
        modifier = Modifier
            .clip(RoundedCornerShape(12.dp))
            .background(if (focused) Brand.Accent else Brand.Surface)
            .border(1.dp, if (focused) Brand.Accent else Brand.Stroke, RoundedCornerShape(12.dp))
            .onFocusChanged { focused = it.isFocused }
            .focusable(interactionSource = interaction)
            .clickable(interactionSource = interaction, indication = null, onClick = onClose)
            .padding(horizontal = 16.dp, vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        val tint = if (focused) androidx.compose.material3.MaterialTheme.colorScheme.onPrimary else Brand.TextMid
        Icon(Icons.Filled.Logout, contentDescription = "Close", tint = tint, modifier = Modifier.size(18.dp))
        Spacer(Modifier.width(8.dp))
        Text("Exit", color = tint, fontSize = 14.sp)
    }
}

private fun humanSize(bytes: Long): String {
    if (bytes <= 0) return "—"
    val u = arrayOf("B", "KB", "MB", "GB", "TB")
    var v = bytes.toDouble(); var i = 0
    while (v >= 1024 && i < u.lastIndex) { v /= 1024; i++ }
    return if (i == 0) "$bytes B" else "%.1f %s".format(v, u[i])
}
