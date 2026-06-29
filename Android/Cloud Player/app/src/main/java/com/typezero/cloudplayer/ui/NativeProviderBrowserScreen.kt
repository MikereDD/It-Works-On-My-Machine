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
import androidx.compose.material.icons.rounded.InsertDriveFile
import androidx.compose.material.icons.rounded.Movie
import androidx.compose.material.icons.rounded.MusicNote
import androidx.compose.material.icons.rounded.Warning
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.typezero.cloudplayer.ui.theme.Brand

private data class NativeCloudItem(
    val name: String,
    val subtitle: String,
    val folder: Boolean = true,
    val playable: Boolean = false
)

/**
 * v2.1 native provider browser shell.
 *
 * This intentionally replaces the embedded Dropbox/Box/MEGA provider web headers
 * with one Cloud Player UI.  Provider websites remain login-only.  Until those
 * providers expose real API tokens to this app, this screen avoids the crowded
 * web dashboards and keeps navigation/playback behavior consistent.
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

    fun goBack() {
        if (stack.size > 1) stack.removeAt(stack.lastIndex) else onLibraries()
    }

    BackHandler { goBack() }

    val items = remember(providerId, currentPath) { nativeItems(providerId, currentPath) }

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

            NativeBackendNotice(providerName)

            LazyColumn(
                modifier = Modifier.fillMaxWidth().widthIn(max = 980.dp),
                verticalArrangement = Arrangement.spacedBy(10.dp)
            ) {
                items(items) { item ->
                    NativeCloudRow(item = item) {
                        if (item.folder) {
                            stack.add(if (currentPath == "/") "/${item.name}" else "$currentPath/${item.name}")
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun NativeBackendNotice(providerName: String) {
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
            text = "$providerName now uses Cloud Player's native browser shell. The provider website is no longer used for browsing headers. Full live file listing/playback comes next when the provider API token backend is connected.",
            color = Brand.TextMid,
            fontSize = 13.sp,
            lineHeight = 18.sp
        )
    }
}

@Composable
private fun NativeCloudRow(item: NativeCloudItem, onClick: () -> Unit) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(18.dp))
            .background(Brand.Surface.copy(alpha = 0.94f))
            .border(1.dp, Brand.Stroke, RoundedCornerShape(18.dp))
            .clickable(enabled = item.folder || item.playable) { onClick() }
            .padding(horizontal = 16.dp, vertical = 14.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(14.dp)
    ) {
        Icon(nativeIcon(item), contentDescription = null, tint = Brand.Accent, modifier = Modifier.size(30.dp))
        Column(modifier = Modifier.weight(1f)) {
            Text(item.name, color = Brand.TextHi, fontSize = 18.sp, fontWeight = FontWeight.Bold, maxLines = 1, overflow = TextOverflow.Ellipsis)
            Text(item.subtitle, color = Brand.TextMid, fontSize = 13.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
    }
}

private fun nativeIcon(item: NativeCloudItem): ImageVector = when {
    item.folder -> Icons.Rounded.Folder
    item.name.endsWith(".mp3", true) || item.name.endsWith(".flac", true) -> Icons.Rounded.MusicNote
    item.name.endsWith(".mp4", true) || item.name.endsWith(".mkv", true) -> Icons.Rounded.Movie
    else -> Icons.Rounded.InsertDriveFile
}

private fun nativeItems(providerId: String, path: String): List<NativeCloudItem> {
    if (path != "/") {
        return listOf(
            NativeCloudItem("No live items yet", "This folder is ready for the ${providerLabel(providerId)} API-backed listing pass.", folder = false),
            NativeCloudItem("Back", "Use remote/mobile Back to go up one directory at a time.", folder = false)
        )
    }

    return when (providerId.lowercase()) {
        "dropbox" -> listOf(
            NativeCloudItem("Apps", "Dropbox folder"),
            NativeCloudItem("Public", "Dropbox folder"),
            NativeCloudItem("Share", "Dropbox shared folder")
        )
        "box" -> listOf(
            NativeCloudItem("Private", "Box folder"),
            NativeCloudItem("Public", "Box folder"),
            NativeCloudItem("Share", "Box shared folder")
        )
        "mega" -> listOf(
            NativeCloudItem("Videos", "MEGA folder"),
            NativeCloudItem("Music", "MEGA folder"),
            NativeCloudItem("Documents", "MEGA folder")
        )
        else -> listOf(NativeCloudItem("Root", "Provider folder"))
    }
}

private fun providerLabel(providerId: String): String = when (providerId.lowercase()) {
    "dropbox" -> "Dropbox"
    "box" -> "Box"
    "mega" -> "MEGA"
    else -> providerId
}
