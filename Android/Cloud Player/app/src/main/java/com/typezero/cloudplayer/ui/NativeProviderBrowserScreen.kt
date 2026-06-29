package com.typezero.cloudplayer.ui

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.ArrowBack
import androidx.compose.material.icons.rounded.CloudQueue
import androidx.compose.material.icons.rounded.Folder
import androidx.compose.material.icons.rounded.Image
import androidx.compose.material.icons.rounded.InsertDriveFile
import androidx.compose.material.icons.rounded.Movie
import androidx.compose.material.icons.rounded.MusicNote
import androidx.compose.material.icons.rounded.PlayArrow
import androidx.compose.material.icons.rounded.Warning
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
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.typezero.cloudplayer.provider.CloudFolderResult
import com.typezero.cloudplayer.provider.CloudItem
import com.typezero.cloudplayer.provider.CloudItemType
import com.typezero.cloudplayer.provider.NativeProviderBackends
import com.typezero.cloudplayer.ui.theme.Brand

/**
 * v2.2 native provider API browser foundation.
 *
 * Every provider now enters the same Cloud Player browser shell and the UI talks
 * through a provider-neutral backend boundary. Provider websites are login-only;
 * live API-token-backed listings are connected provider by provider after this.
 */
@Composable
fun NativeProviderBrowserScreen(
    providerId: String,
    providerName: String,
    accountLabel: String?,
    onLibraries: () -> Unit
) {
    val stack = remember(providerId) { mutableStateListOf("/") }
    val currentPath = stack.last()
    val backend = remember(providerId, providerName) { NativeProviderBackends.forProvider(providerId, providerName) }
    var folderResult by remember(providerId) { mutableStateOf<CloudFolderResult?>(null) }
    var loading by remember(providerId) { mutableStateOf(true) }

    fun goBack() {
        if (stack.size > 1) stack.removeAt(stack.lastIndex) else onLibraries()
    }

    BackHandler { goBack() }

    LaunchedEffect(providerId, currentPath) {
        loading = true
        folderResult = backend.listFolder(currentPath)
        loading = false
    }

    val result = folderResult
    val items = result?.items.orEmpty()

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(Brand.pageGradient)
    ) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(horizontal = 22.dp, vertical = 28.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp)
        ) {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .widthIn(max = 980.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.SpaceBetween
            ) {
                Row(
                    modifier = Modifier
                        .clip(RoundedCornerShape(999.dp))
                        .background(Brand.Surface.copy(alpha = 0.96f))
                        .border(1.dp, Brand.Stroke, RoundedCornerShape(999.dp))
                        .clickable { onLibraries() }
                        .padding(horizontal = 14.dp, vertical = 10.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Icon(Icons.Rounded.CloudQueue, contentDescription = null, tint = Brand.TextHi, modifier = Modifier.size(20.dp))
                    Spacer(Modifier.size(8.dp))
                    Text("Libraries", color = Brand.TextHi, fontSize = 17.sp, fontWeight = FontWeight.Bold)
                    Spacer(Modifier.size(10.dp))
                    Icon(Icons.Rounded.ArrowBack, contentDescription = null, tint = Brand.TextMid, modifier = Modifier.size(18.dp))
                    Spacer(Modifier.size(8.dp))
                    Text(providerName, color = Brand.TextHi, fontSize = 17.sp, fontWeight = FontWeight.Bold)
                }

                com.typezero.cloudplayer.cast.CastButton(modifier = Modifier.size(44.dp))
            }

            Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Text(
                    text = providerName,
                    color = Brand.TextHi,
                    fontSize = 32.sp,
                    fontWeight = FontWeight.Bold
                )
                Text(
                    text = listOfNotNull(accountLabel, currentPath.takeUnless { it == "/" } ?: "Root").joinToString("  •  "),
                    color = Brand.TextMid,
                    fontSize = 14.sp,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis
                )
            }

            result?.statusMessage?.let { NativeBackendNotice(it) }

            LazyColumn(
                modifier = Modifier.fillMaxWidth().widthIn(max = 980.dp),
                verticalArrangement = Arrangement.spacedBy(10.dp)
            ) {
                if (loading) {
                    item { NativeStatusRow("Loading", "Reading $providerName through the native provider boundary.") }
                } else if (items.isEmpty()) {
                    item { NativeStatusRow("Empty folder", "No folders or media were returned for this path.") }
                } else {
                    items(items) { item ->
                        NativeCloudRow(item = item) {
                            if (item.isFolder) {
                                stack.add(item.path.ifBlank { if (currentPath == "/") "/${item.name}" else "$currentPath/${item.name}" })
                            }
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun NativeBackendNotice(message: String) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .widthIn(max = 980.dp)
            .clip(RoundedCornerShape(18.dp))
            .background(Brand.Surface.copy(alpha = 0.82f))
            .border(1.dp, Brand.Stroke, RoundedCornerShape(18.dp))
            .padding(14.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        Icon(Icons.Rounded.Warning, contentDescription = null, tint = Brand.TextMid, modifier = Modifier.size(22.dp))
        Text(
            text = message,
            color = Brand.TextMid,
            fontSize = 13.sp,
            lineHeight = 18.sp
        )
    }
}

@Composable
private fun NativeStatusRow(title: String, subtitle: String) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(18.dp))
            .background(Brand.Surface.copy(alpha = 0.9f))
            .border(1.dp, Brand.Stroke, RoundedCornerShape(18.dp))
            .padding(horizontal = 16.dp, vertical = 14.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(14.dp)
    ) {
        Icon(Icons.Rounded.CloudQueue, contentDescription = null, tint = Brand.Accent, modifier = Modifier.size(30.dp))
        Column(modifier = Modifier.weight(1f)) {
            Text(title, color = Brand.TextHi, fontSize = 18.sp, fontWeight = FontWeight.Bold)
            Text(subtitle, color = Brand.TextMid, fontSize = 13.sp, maxLines = 2, overflow = TextOverflow.Ellipsis)
        }
    }
}

@Composable
private fun NativeCloudRow(item: CloudItem, onClick: () -> Unit) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(18.dp))
            .background(Brand.Surface.copy(alpha = 0.94f))
            .border(1.dp, Brand.Stroke, RoundedCornerShape(18.dp))
            .clickable(enabled = item.isFolder || item.isPlayable) { onClick() }
            .padding(horizontal = 16.dp, vertical = 14.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(14.dp)
    ) {
        Icon(nativeIcon(item), contentDescription = null, tint = Brand.Accent, modifier = Modifier.size(30.dp))
        Column(modifier = Modifier.weight(1f)) {
            Text(item.name, color = Brand.TextHi, fontSize = 18.sp, fontWeight = FontWeight.Bold, maxLines = 1, overflow = TextOverflow.Ellipsis)
            Text(nativeSubtitle(item), color = Brand.TextMid, fontSize = 13.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
        if (item.isPlayable) {
            Icon(Icons.Rounded.PlayArrow, contentDescription = null, tint = Brand.TextHi, modifier = Modifier.size(26.dp))
        }
    }
}

private fun nativeIcon(item: CloudItem): ImageVector = when (item.type) {
    CloudItemType.FOLDER -> Icons.Rounded.Folder
    CloudItemType.AUDIO -> Icons.Rounded.MusicNote
    CloudItemType.VIDEO -> Icons.Rounded.Movie
    CloudItemType.IMAGE -> Icons.Rounded.Image
    else -> Icons.Rounded.InsertDriveFile
}

private fun nativeSubtitle(item: CloudItem): String {
    if (item.isFolder) return "Folder"
    val details = listOfNotNull(item.mimeType, item.modifiedLabel, item.sizeBytes?.takeIf { it > 0 }?.let { formatSize(it) })
    return details.ifEmpty { listOf("Media file") }.joinToString("  •  ")
}

private fun formatSize(bytes: Long): String {
    val units = listOf("B", "KB", "MB", "GB", "TB")
    var value = bytes.toDouble()
    var unit = 0
    while (value >= 1024.0 && unit < units.lastIndex) {
        value /= 1024.0
        unit++
    }
    return if (unit == 0) "${bytes} B" else "%.1f %s".format(value, units[unit])
}
