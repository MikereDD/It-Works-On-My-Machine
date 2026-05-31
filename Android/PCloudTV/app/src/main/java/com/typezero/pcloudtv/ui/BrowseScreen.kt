package com.typezero.pcloudtv.ui

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.focusable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Folder
import androidx.compose.material.icons.filled.Logout
import androidx.compose.material.icons.filled.MusicNote
import androidx.compose.material.icons.filled.Movie
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.typezero.pcloudtv.data.ApiResult
import com.typezero.pcloudtv.data.PCloudClient
import com.typezero.pcloudtv.data.PItem
import com.typezero.pcloudtv.data.Session

@Composable
fun BrowseScreen(
    client: PCloudClient,
    session: Session,
    onPlay: (PItem) -> Unit,
    onLogout: () -> Unit
) {
    // Breadcrumb stack of (folderId, displayName); root is folderid 0.
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

    // Back button goes up one folder; at root it falls through to exit the app.
    BackHandler(enabled = stack.size > 1) { stack.removeAt(stack.lastIndex) }

    val firstRow = remember { FocusRequester() }

    Column(modifier = Modifier.fillMaxSize().padding(40.dp)) {

        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.SpaceBetween
        ) {
            Column {
                Text(
                    current.second,
                    fontSize = 30.sp,
                    fontWeight = FontWeight.Bold,
                    color = MaterialTheme.colorScheme.onBackground
                )
                Text(
                    stack.joinToString("  ›  ") { it.second },
                    fontSize = 13.sp,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
            FocusRow(
                modifier = Modifier.width(150.dp),
                onClick = onLogout
            ) {
                Icon(Icons.Filled.Logout, contentDescription = null, tint = it)
                Text("  Sign out", color = it)
            }
        }

        when {
            loading -> Box(Modifier.fillMaxSize(), Alignment.Center) {
                CircularProgressIndicator(color = MaterialTheme.colorScheme.primary)
            }

            error != null -> Box(Modifier.fillMaxSize(), Alignment.Center) {
                Text("Error: $error", color = MaterialTheme.colorScheme.error)
            }

            items.isEmpty() -> Box(Modifier.fillMaxSize(), Alignment.Center) {
                Text(
                    "This folder has no playable media or sub-folders.",
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }

            else -> {
                LaunchedEffect(items) {
                    runCatching { firstRow.requestFocus() }
                }
                LazyColumn(
                    modifier = Modifier.fillMaxSize().padding(top = 16.dp),
                    verticalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    itemsIndexed(items) { index, pItem ->
                        FileRow(
                            item = pItem,
                            modifier = if (index == 0) Modifier.focusRequester(firstRow)
                            else Modifier,
                            onClick = {
                                when {
                                    pItem.isFolder ->
                                        stack.add(pItem.folderId!! to pItem.name)
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

@Composable
private fun FileRow(
    item: PItem,
    modifier: Modifier = Modifier,
    onClick: () -> Unit
) {
    FocusRow(modifier = modifier.fillMaxWidth(), onClick = onClick) { tint ->
        val icon = when {
            item.isFolder -> Icons.Filled.Folder
            item.isVideo -> Icons.Filled.Movie
            else -> Icons.Filled.MusicNote
        }
        Icon(icon, contentDescription = null, tint = tint, modifier = Modifier.size(26.dp))
        Text(
            "   ${item.name}",
            color = tint,
            fontSize = 18.sp,
            maxLines = 1
        )
    }
}

/**
 * A focusable, clickable row that highlights on D-pad focus.
 * The content lambda receives the appropriate content tint color.
 */
@Composable
private fun FocusRow(
    modifier: Modifier = Modifier,
    onClick: () -> Unit,
    content: @Composable (tint: Color) -> Unit
) {
    var focused by remember { mutableStateOf(false) }
    val bg = if (focused) MaterialTheme.colorScheme.primary
    else MaterialTheme.colorScheme.surface
    val tint = if (focused) MaterialTheme.colorScheme.onPrimary
    else MaterialTheme.colorScheme.onSurface

    Row(
        modifier = modifier
            .background(bg, RoundedCornerShape(10.dp))
            .border(
                width = if (focused) 2.dp else 0.dp,
                color = if (focused) MaterialTheme.colorScheme.secondary else Color.Transparent,
                shape = RoundedCornerShape(10.dp)
            )
            .onFocusChanged { focused = it.isFocused }
            .focusable()
            .clickable(onClick = onClick)
            .padding(horizontal = 18.dp, vertical = 14.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        content(tint)
    }
}
