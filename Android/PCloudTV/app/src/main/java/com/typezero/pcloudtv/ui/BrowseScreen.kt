package com.typezero.pcloudtv.ui

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
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ChevronRight
import androidx.compose.material.icons.filled.Folder
import androidx.compose.material.icons.filled.Logout
import androidx.compose.material.icons.filled.MusicNote
import androidx.compose.material.icons.filled.Movie
import androidx.compose.material.icons.rounded.CloudQueue
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.typezero.pcloudtv.data.ApiResult
import com.typezero.pcloudtv.data.PCloudClient
import com.typezero.pcloudtv.data.PItem
import com.typezero.pcloudtv.data.Session
import com.typezero.pcloudtv.ui.theme.Brand

@Composable
fun BrowseScreen(
    client: PCloudClient,
    session: Session,
    onPlay: (PItem) -> Unit,
    onLogout: () -> Unit
) {
    val stack = remember { mutableStateListOf(0L to "pCloud") }
    val current = stack.last()

    var items by remember { mutableStateOf<List<PItem>>(emptyList()) }
    var loading by remember { mutableStateOf(true) }
    var error by remember { mutableStateOf<String?>(null) }

    LaunchedEffect(current.first) {
        loading = true
        error = null
        when (val r = client.listFolder(session, current.first)) {
            is ApiResult.Ok -> items = r.value
            is ApiResult.Error -> error = r.message
        }
        loading = false
    }

    BackHandler(enabled = stack.size > 1) { stack.removeAt(stack.lastIndex) }

    val firstRow = remember { FocusRequester() }

    BoxWithConstraints(
        modifier = Modifier.fillMaxSize().background(Brand.pageGradient)
    ) {
        val compact = maxWidth < 600.dp
        val hPad = if (compact) 18.dp else 56.dp
        val vPad = if (compact) 18.dp else 40.dp
        val titleSize = if (compact) 24.sp else 34.sp
        val rowMax = if (compact) Modifier.fillMaxWidth() else Modifier.width(760.dp)

        Column(modifier = Modifier.fillMaxSize().padding(horizontal = hPad, vertical = vPad)) {

            // Header
            Row(
                modifier = Modifier.fillMaxWidth().padding(bottom = if (compact) 14.dp else 22.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.SpaceBetween
            ) {
                Row(modifier = Modifier.weight(1f), verticalAlignment = Alignment.CenterVertically) {
                    Box(
                        modifier = Modifier
                            .size(if (compact) 38.dp else 46.dp)
                            .clip(RoundedCornerShape(12.dp))
                            .background(Brand.Accent.copy(alpha = 0.16f)),
                        contentAlignment = Alignment.Center
                    ) {
                        Icon(
                            Icons.Rounded.CloudQueue,
                            contentDescription = null,
                            tint = Brand.Accent,
                            modifier = Modifier.size(if (compact) 22.dp else 26.dp)
                        )
                    }
                    Spacer(Modifier.width(14.dp))
                    Column(modifier = Modifier.weight(1f)) {
                        Text(
                            current.second,
                            fontSize = titleSize,
                            fontWeight = FontWeight.Bold,
                            color = Brand.TextHi,
                            maxLines = 1
                        )
                        Text(
                            stack.joinToString("  ›  ") { it.second },
                            fontSize = 12.sp,
                            color = Brand.TextLow,
                            maxLines = 1
                        )
                    }
                }
                LogoutButton(onLogout)
            }

            when {
                loading -> Box(Modifier.fillMaxSize(), Alignment.Center) {
                    CircularProgressIndicator(color = Brand.Accent)
                }

                error != null -> Box(Modifier.fillMaxSize(), Alignment.Center) {
                    Text("Couldn't load this folder.\n$error",
                        color = Brand.TextMid, fontSize = 15.sp)
                }

                items.isEmpty() -> Box(Modifier.fillMaxSize(), Alignment.Center) {
                    Text("Nothing playable here yet.",
                        color = Brand.TextLow, fontSize = 15.sp)
                }

                else -> {
                    LaunchedEffect(items) { runCatching { firstRow.requestFocus() } }
                    LazyColumn(
                        modifier = Modifier.fillMaxSize(),
                        verticalArrangement = Arrangement.spacedBy(if (compact) 10.dp else 12.dp)
                    ) {
                        itemsIndexed(items) { index, pItem ->
                            ItemCard(
                                item = pItem,
                                compact = compact,
                                modifier = rowMax.then(
                                    if (index == 0) Modifier.focusRequester(firstRow) else Modifier
                                ),
                                onClick = {
                                    when {
                                        pItem.isFolder -> stack.add(pItem.folderId!! to pItem.name)
                                        pItem.isPlayable -> onPlay(pItem)
                                    }
                                }
                            )
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun ItemCard(
    item: PItem,
    compact: Boolean,
    modifier: Modifier = Modifier,
    onClick: () -> Unit
) {
    var focused by remember { mutableStateOf(false) }
    val interaction = remember { MutableInteractionSource() }
    val scale by animateFloatAsState(if (focused) 1.025f else 1f, label = "cardScale")

    val accent = when {
        item.isFolder -> Brand.Folder
        item.isVideo -> Brand.Video
        else -> Brand.Audio
    }
    val icon = when {
        item.isFolder -> Icons.Filled.Folder
        item.isVideo -> Icons.Filled.Movie
        else -> Icons.Filled.MusicNote
    }
    val subtitle = if (item.isFolder) "Folder" else humanSize(item.size)

    Row(
        modifier = modifier
            .graphicsLayer { scaleX = scale; scaleY = scale }
            .shadow(
                elevation = if (focused) 14.dp else 0.dp,
                shape = RoundedCornerShape(16.dp),
                ambientColor = accent,
                spotColor = accent
            )
            .clip(RoundedCornerShape(16.dp))
            .background(if (focused) Brand.SurfaceFocused else Brand.Surface)
            .border(
                width = if (focused) 1.5.dp else 1.dp,
                color = if (focused) accent else Brand.Stroke,
                shape = RoundedCornerShape(16.dp)
            )
            .onFocusChanged { focused = it.isFocused }
            .focusable(interactionSource = interaction)
            .clickable(interactionSource = interaction, indication = null, onClick = onClick)
            .padding(horizontal = if (compact) 14.dp else 18.dp, vertical = if (compact) 12.dp else 14.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Box(
            modifier = Modifier
                .size(if (compact) 40.dp else 46.dp)
                .clip(RoundedCornerShape(12.dp))
                .background(accent.copy(alpha = if (focused) 0.26f else 0.16f)),
            contentAlignment = Alignment.Center
        ) {
            Icon(icon, contentDescription = null, tint = accent,
                modifier = Modifier.size(if (compact) 22.dp else 26.dp))
        }
        Spacer(Modifier.width(14.dp))
        Column(modifier = Modifier.weight(1f)) {
            Text(
                item.name,
                color = Brand.TextHi,
                fontSize = if (compact) 16.sp else 18.sp,
                fontWeight = FontWeight.Medium,
                maxLines = 1
            )
            Text(subtitle, color = Brand.TextLow, fontSize = 12.sp, maxLines = 1)
        }
        if (item.isFolder) {
            Icon(
                Icons.Filled.ChevronRight,
                contentDescription = null,
                tint = if (focused) accent else Brand.TextLow,
                modifier = Modifier.size(24.dp)
            )
        }
    }
}

@Composable
private fun LogoutButton(onLogout: () -> Unit) {
    var focused by remember { mutableStateOf(false) }
    val interaction = remember { MutableInteractionSource() }
    Row(
        modifier = Modifier
            .clip(RoundedCornerShape(12.dp))
            .background(if (focused) Brand.Accent else Brand.Surface)
            .border(1.dp, if (focused) Brand.Accent else Brand.Stroke, RoundedCornerShape(12.dp))
            .onFocusChanged { focused = it.isFocused }
            .focusable(interactionSource = interaction)
            .clickable(interactionSource = interaction, indication = null, onClick = onLogout)
            .padding(horizontal = 16.dp, vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        val tint = if (focused) MaterialTheme.colorScheme.onPrimary else Brand.TextMid
        Icon(Icons.Filled.Logout, contentDescription = "Sign out", tint = tint,
            modifier = Modifier.size(18.dp))
        Spacer(Modifier.width(8.dp))
        Text("Sign out", color = tint, fontSize = 14.sp)
    }
}

private fun humanSize(bytes: Long): String {
    if (bytes <= 0) return "—"
    val u = arrayOf("B", "KB", "MB", "GB", "TB")
    var v = bytes.toDouble(); var i = 0
    while (v >= 1024 && i < u.lastIndex) { v /= 1024; i++ }
    return if (i == 0) "${bytes} B" else "%.1f %s".format(v, u[i])
}
