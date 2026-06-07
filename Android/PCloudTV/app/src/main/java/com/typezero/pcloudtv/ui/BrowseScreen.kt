package com.typezero.pcloudtv.ui

import androidx.compose.material.icons.filled.RadioButtonUnchecked
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Checklist
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material.icons.filled.PlaylistAdd
import kotlinx.coroutines.launch
import androidx.compose.foundation.layout.height
import androidx.compose.material.icons.filled.QueueMusic
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
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Info
import androidx.compose.ui.platform.LocalContext
import androidx.compose.material.icons.filled.ChevronRight
import androidx.compose.material.icons.filled.Folder
import androidx.compose.material.icons.filled.Logout
import androidx.compose.material.icons.filled.MusicNote
import androidx.compose.material.icons.filled.Movie
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Image
import androidx.compose.material.icons.filled.InsertDriveFile
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
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.typezero.pcloudtv.data.ApiResult
import com.typezero.pcloudtv.data.PCloudClient
import com.typezero.pcloudtv.data.PItem
import com.typezero.pcloudtv.data.Session
import com.typezero.pcloudtv.ui.theme.Brand

/** Built playlists (from a song selection) are saved here. */
private const val PLAYLIST_DIR = "/Music/playlists"

@Composable
fun BrowseScreen(
    client: PCloudClient,
    session: Session,
    onPlayQueue: (List<com.typezero.pcloudtv.data.MediaItem>, String?) -> Unit,
    onLogout: () -> Unit
) {
    val stack = remember { mutableStateListOf(0L to "pCloud") }
    val current = stack.last()

    // "Continue" — the most recent queue, loaded fresh each time we enter the browser.
    val browseContext = LocalContext.current
    val browseStore = remember { com.typezero.pcloudtv.data.SessionStore(browseContext) }
    val lastPlayed = remember { browseStore.getLastPlayed() }

    var items by remember { mutableStateOf<List<PItem>>(emptyList()) }
    var loading by remember { mutableStateOf(true) }
    var error by remember { mutableStateOf<String?>(null) }

    // Playlist resolution overlay state.
    val scope = androidx.compose.runtime.rememberCoroutineScope()
    var resolving by remember { mutableStateOf(false) }
    var resolveError by remember { mutableStateOf<String?>(null) }

    // Save-playlist state + a key to force a folder re-list after saving.
    var saving by remember { mutableStateOf(false) }
    var saveMessage by remember { mutableStateOf<String?>(null) }
    var reloadKey by remember { mutableStateOf(0) }
    var genDone by remember { mutableStateOf(0) }
    var genTotal by remember { mutableStateOf(0) }
    var genName by remember { mutableStateOf("") }
    var showGenDialog by remember { mutableStateOf(false) }
    var genPath by remember { mutableStateOf("/") }
    var genReplace by remember { mutableStateOf(true) }

    // Recursively generate a playlist in every audio folder under [path].
    fun generateUnder(path: String, replaceExisting: Boolean) {
        showGenDialog = false
        if (saving) return
        saving = true
        saveMessage = null
        genDone = 0; genTotal = 0; genName = ""
        scope.launch {
            // Optionally wipe every existing .m3u/.m3u8 under the path first.
            var removed = 0
            if (replaceExisting) {
                genName = "Removing old playlists…"
                when (val pls = client.collectPlaylistsByPath(session, path, excludePath = PLAYLIST_DIR)) {
                    is ApiResult.Ok -> {
                        for (pl in pls.value) {
                            pl.fileId?.let {
                                if (client.deleteFile(session, it) is ApiResult.Ok) removed++
                            }
                        }
                    }
                    is ApiResult.Error -> { /* non-fatal: continue to generate */ }
                }
            }
            val scan = client.collectAudioFoldersByPath(session, path)
            when (scan) {
                is ApiResult.Ok -> {
                    val folders = scan.value
                    genTotal = folders.size
                    var ok = 0
                    for ((i, fol) in folders.withIndex()) {
                        genName = fol.name
                        genDone = i + 1
                        val pname = (fol.name.ifBlank { "Playlist" }) + ".m3u"
                        if (client.savePlaylist(session, fol.folderId, pname, fol.files) is ApiResult.Ok) ok++
                    }
                    saving = false
                    val cleaned = if (replaceExisting) "Removed $removed old, " else ""
                    saveMessage = if (folders.isEmpty()) {
                        "${cleaned}no folders with audio found under \"$path\"."
                    } else {
                        "${cleaned}saved $ok playlist(s) across ${folders.size} folder(s)."
                    }
                    reloadKey++
                }
                is ApiResult.Error -> {
                    saving = false
                    saveMessage = "Couldn't scan: ${scan.message}"
                }
            }
        }
    }

    // Click-to-build playlist state (works across folders).
    var selecting by remember { mutableStateOf(false) }
    val selectedItems = remember { mutableStateListOf<com.typezero.pcloudtv.data.MediaItem>() }
    var showNameDialog by remember { mutableStateOf(false) }
    var showAbout by remember { mutableStateOf(false) }
    var playlistName by remember { mutableStateOf("") }

    fun currentPathPrefix(): String {
        // Build the absolute pCloud path of the folder you're currently in.
        val p = "/" + stack.drop(1).joinToString("/") { it.second }
        return if (p == "/") "" else p
    }

    fun toggleSelect(file: PItem) {
        val id = file.fileId ?: return
        val existing = selectedItems.indexOfFirst { it.fileId == id }
        if (existing >= 0) {
            selectedItems.removeAt(existing)
        } else {
            val path = currentPathPrefix() + "/" + file.name
            selectedItems.add(com.typezero.pcloudtv.data.MediaItem(file.name, id, null, path))
        }
    }

    fun saveSelected(name: String) {
        showNameDialog = false
        val entries = selectedItems.mapNotNull { mi -> mi.path?.let { mi.title to it } }
        if (entries.isEmpty()) { selecting = false; selectedItems.clear(); return }
        saving = true; saveMessage = null; genDone = 0; genTotal = 0; genName = ""
        scope.launch {
            val pname = (name.ifBlank { "Playlist" }).removeSuffix(".m3u") + ".m3u"
            // Built playlists always live in a dedicated /Music/playlists folder.
            when (val folder = client.ensureFolder(session, PLAYLIST_DIR)) {
                is ApiResult.Ok -> {
                    val res = client.savePlaylistAbsolute(session, folder.value, pname, entries)
                    saving = false
                    saveMessage = when (res) {
                        is ApiResult.Ok -> "Saved \"$pname\" to $PLAYLIST_DIR (${entries.size} tracks)"
                        is ApiResult.Error -> "Couldn't save: ${res.message}"
                    }
                }
                is ApiResult.Error -> {
                    saving = false
                    saveMessage = "Couldn't open $PLAYLIST_DIR: ${folder.message}"
                }
            }
            selecting = false
            selectedItems.clear()
            reloadKey++
        }
    }

    LaunchedEffect(current.first, reloadKey) {
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
        val rowMax = if (compact) Modifier.fillMaxWidth() else Modifier.width(760.dp)

        Column(modifier = Modifier.fillMaxSize().padding(horizontal = hPad, vertical = vPad)) {

            // Header — stacked on narrow/portrait screens so the title and the
            // action buttons never fight for space; single row when there's room.
            val breadcrumb = stack.joinToString("  ›  ") { it.second }
            if (compact) {
                Column(modifier = Modifier.fillMaxWidth().padding(bottom = 14.dp)) {
                    HeaderTitle(
                        compact = true,
                        name = current.second,
                        breadcrumb = breadcrumb,
                        modifier = Modifier.fillMaxWidth()
                    )
                    Spacer(Modifier.height(12.dp))
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.End
                    ) {
                        HeaderActions(
                            compact = true,
                            selecting = selecting,
                            selectedCount = selectedItems.size,
                            itemsNotEmpty = items.isNotEmpty(),
                            onStartSelect = { selecting = true; selectedItems.clear() },
                            onCancelSelect = { selecting = false; selectedItems.clear() },
                            onSaveSelected = {
                                if (selectedItems.isNotEmpty()) {
                                    playlistName = current.second
                                    showNameDialog = true
                                }
                            },
                            onGenerate = {
                                if (!saving) {
                                    genPath = "/" + stack.drop(1).joinToString("/") { it.second }
                                    if (genPath.isBlank()) genPath = "/"
                                    showGenDialog = true
                                }
                            },
                            onAbout = { showAbout = true },
                            onLogout = onLogout
                        )
                    }
                }
            } else {
                Row(
                    modifier = Modifier.fillMaxWidth().padding(bottom = 22.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.SpaceBetween
                ) {
                    HeaderTitle(
                        compact = false,
                        name = current.second,
                        breadcrumb = breadcrumb,
                        modifier = Modifier.weight(1f)
                    )
                    HeaderActions(
                        compact = false,
                        selecting = selecting,
                        selectedCount = selectedItems.size,
                        itemsNotEmpty = items.isNotEmpty(),
                        onStartSelect = { selecting = true; selectedItems.clear() },
                        onCancelSelect = { selecting = false; selectedItems.clear() },
                        onSaveSelected = {
                            if (selectedItems.isNotEmpty()) {
                                playlistName = current.second
                                showNameDialog = true
                            }
                        },
                        onGenerate = {
                            if (!saving) {
                                genPath = "/" + stack.drop(1).joinToString("/") { it.second }
                                if (genPath.isBlank()) genPath = "/"
                                showGenDialog = true
                            }
                        },
                        onAbout = { showAbout = true },
                        onLogout = onLogout
                    )
                }
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
                        if (stack.size == 1 && !selecting && lastPlayed != null) {
                            item {
                                ContinueCard(
                                    title = lastPlayed.title,
                                    compact = compact,
                                    modifier = rowMax,
                                    onClick = { onPlayQueue(lastPlayed.queue, lastPlayed.playlistKey) }
                                )
                            }
                        }
                        itemsIndexed(items) { index, pItem ->
                            ItemCard(
                                item = pItem,
                                compact = compact,
                                selecting = selecting,
                                selected = pItem.fileId != null && selectedItems.any { it.fileId == pItem.fileId },
                                modifier = rowMax.then(
                                    if (index == 0) Modifier.focusRequester(firstRow) else Modifier
                                ),
                                onClick = {
                                    if (selecting) {
                                        when {
                                            // Keep navigating folders while collecting tracks.
                                            pItem.isFolder ->
                                                stack.add(pItem.folderId!! to pItem.name)
                                            !pItem.isPlaylist && pItem.isPlayable && pItem.fileId != null ->
                                                toggleSelect(pItem)
                                        }
                                    } else {
                                        when {
                                            pItem.isFolder -> stack.add(pItem.folderId!! to pItem.name)
                                            pItem.isPlaylist -> {
                                                resolveError = null
                                                resolving = true
                                                scope.launch {
                                                    when (val r = client.resolvePlaylist(session, pItem, items)) {
                                                        is ApiResult.Ok -> {
                                                            resolving = false
                                                            onPlayQueue(r.value, "pl:${pItem.fileId}")
                                                        }
                                                        is ApiResult.Error -> {
                                                            resolving = false
                                                            resolveError = r.message
                                                        }
                                                    }
                                                }
                                            }
                                            pItem.isPlayable -> onPlayQueue(
                                                listOf(
                                                    com.typezero.pcloudtv.data.MediaItem(
                                                        pItem.name, pItem.fileId, null
                                                    )
                                                ),
                                                null
                                            )
                                        }
                                    }
                                }
                            )
                        }
                    }
                }
            }
        }

        if (resolving || saving) {
            Box(
                Modifier.fillMaxSize().background(Color(0xAA000000)),
                contentAlignment = Alignment.Center
            ) {
                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    CircularProgressIndicator(color = Brand.Accent)
                    Spacer(Modifier.height(12.dp))
                    val label = when {
                        resolving -> "Loading playlist…"
                        genTotal > 0 -> "Generating playlists… $genDone / $genTotal"
                        else -> "Scanning folders…"
                    }
                    Text(label, color = Brand.TextHi, fontSize = 14.sp)
                    if (saving && genName.isNotBlank()) {
                        Spacer(Modifier.height(4.dp))
                        Text(genName, color = Brand.TextLow, fontSize = 12.sp, maxLines = 1)
                    }
                }
            }
        }
        resolveError?.let { msg ->
            Box(
                Modifier.fillMaxSize().background(Color(0xAA000000))
                    .clickable { resolveError = null },
                contentAlignment = Alignment.Center
            ) {
                Text(msg, color = Brand.TextHi, fontSize = 14.sp,
                    modifier = Modifier.padding(32.dp))
            }
        }
        saveMessage?.let { msg ->
            Box(
                Modifier.fillMaxSize().background(Color(0xAA000000))
                    .clickable { saveMessage = null },
                contentAlignment = Alignment.Center
            ) {
                Text(msg, color = Brand.TextHi, fontSize = 14.sp,
                    modifier = Modifier.padding(32.dp))
            }
        }

        if (showGenDialog) {
            GeneratePlaylistsDialog(
                path = genPath,
                replaceExisting = genReplace,
                onPathChange = { genPath = it },
                onReplaceChange = { genReplace = it },
                onQuick = { genPath = it },
                onGenerate = { generateUnder(genPath, genReplace) },
                onCancel = { showGenDialog = false }
            )
        }

        if (showNameDialog) {
            NamePlaylistDialog(
                name = playlistName,
                count = selectedItems.size,
                onNameChange = { playlistName = it },
                onSave = { saveSelected(playlistName) },
                onCancel = { showNameDialog = false }
            )
        }

        if (showAbout) {
            AboutDialog(onClose = { showAbout = false })
        }
    }
}

@Composable
private fun AboutDialog(onClose: () -> Unit) {
    val context = LocalContext.current
    val version = com.typezero.pcloudtv.BuildConfig.VERSION_NAME
    val code = com.typezero.pcloudtv.BuildConfig.VERSION_CODE
    val changelogUrl =
        "https://github.com/MikereDD/It-Works-On-My-Machine/blob/main/Android/PCloudTV/CHANGELOG.md"

    fun open(url: String) {
        runCatching {
            context.startActivity(
                android.content.Intent(android.content.Intent.ACTION_VIEW, android.net.Uri.parse(url))
            )
        }
    }

    Box(
        Modifier.fillMaxSize().background(Color(0xCC000000)).clickable(onClick = onClose),
        contentAlignment = Alignment.Center
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth().widthIn(max = 460.dp)
                .padding(28.dp)
                .clip(RoundedCornerShape(20.dp))
                .background(Brand.Surface)
                .border(1.dp, Brand.Stroke, RoundedCornerShape(20.dp))
                .padding(24.dp)
        ) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Box(
                    modifier = Modifier
                        .size(44.dp)
                        .clip(RoundedCornerShape(12.dp))
                        .background(Brand.Accent.copy(alpha = 0.16f)),
                    contentAlignment = Alignment.Center
                ) {
                    Icon(Icons.Rounded.CloudQueue, null, tint = Brand.Accent,
                        modifier = Modifier.size(24.dp))
                }
                Spacer(Modifier.width(14.dp))
                Column {
                    Text("pCloud TV", color = Brand.TextHi, fontSize = 20.sp,
                        fontWeight = FontWeight.Bold)
                    Text("Version $version ($code)", color = Brand.TextMid, fontSize = 13.sp)
                }
            }
            Spacer(Modifier.height(16.dp))
            Text(
                "Stream your pCloud video and audio to Google TV, Android TV, or your phone " +
                    "— played through the VLC engine.",
                color = Brand.TextLow, fontSize = 13.sp
            )
            Spacer(Modifier.height(20.dp))
            Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.End) {
                HeaderButton(icon = null, label = "Close", onClick = onClose)
                Spacer(Modifier.width(10.dp))
                HeaderButton(
                    icon = Icons.Filled.QueueMusic,
                    label = "View changelog",
                    primary = true,
                    onClick = { open(changelogUrl) }
                )
            }
        }
    }
}

@Composable
private fun NamePlaylistDialog(
    name: String,
    count: Int,
    onNameChange: (String) -> Unit,
    onSave: () -> Unit,
    onCancel: () -> Unit
) {
    Box(
        Modifier.fillMaxSize().background(Color(0xCC000000)).clickable(onClick = onCancel),
        contentAlignment = Alignment.Center
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth().widthIn(max = 480.dp)
                .padding(28.dp)
                .clip(RoundedCornerShape(20.dp))
                .background(Brand.Surface)
                .border(1.dp, Brand.Stroke, RoundedCornerShape(20.dp))
                .padding(22.dp)
        ) {
            Text("Name your playlist", color = Brand.TextHi, fontSize = 18.sp,
                fontWeight = FontWeight.Bold)
            Spacer(Modifier.height(6.dp))
            Text("$count track(s) selected. Saved as an .m3u in $PLAYLIST_DIR.",
                color = Brand.TextLow, fontSize = 12.sp)
            Spacer(Modifier.height(14.dp))
            OutlinedTextField(
                value = name,
                onValueChange = onNameChange,
                singleLine = true,
                label = { Text("Playlist name") },
                shape = RoundedCornerShape(12.dp),
                colors = OutlinedTextFieldDefaults.colors(
                    focusedBorderColor = Brand.Accent,
                    unfocusedBorderColor = Brand.Stroke,
                    focusedLabelColor = Brand.Accent,
                    cursorColor = Brand.Accent
                ),
                modifier = Modifier.fillMaxWidth()
            )
            Spacer(Modifier.height(18.dp))
            Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.End) {
                HeaderButton(icon = null, label = "Cancel", onClick = onCancel)
                Spacer(Modifier.width(10.dp))
                HeaderButton(icon = Icons.Filled.PlaylistAdd, label = "Save",
                    primary = true, onClick = onSave)
            }
        }
    }
}

@Composable
private fun GeneratePlaylistsDialog(
    path: String,
    replaceExisting: Boolean,
    onPathChange: (String) -> Unit,
    onReplaceChange: (Boolean) -> Unit,
    onQuick: (String) -> Unit,
    onGenerate: () -> Unit,
    onCancel: () -> Unit
) {
    Box(
        Modifier.fillMaxSize().background(Color(0xCC000000)).clickable(onClick = onCancel),
        contentAlignment = Alignment.Center
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth().widthIn(max = 480.dp)
                .padding(28.dp)
                .clip(RoundedCornerShape(20.dp))
                .background(Brand.Surface)
                .border(1.dp, Brand.Stroke, RoundedCornerShape(20.dp))
                .padding(22.dp)
        ) {
            Text("Generate playlists", color = Brand.TextHi, fontSize = 18.sp,
                fontWeight = FontWeight.Bold)
            Spacer(Modifier.height(6.dp))
            Text(
                "Writes an .m3u into every folder with audio under this pCloud path " +
                    "(including subfolders).",
                color = Brand.TextLow, fontSize = 12.sp
            )
            Spacer(Modifier.height(14.dp))
            OutlinedTextField(
                value = path,
                onValueChange = onPathChange,
                singleLine = true,
                label = { Text("pCloud path") },
                shape = RoundedCornerShape(12.dp),
                colors = OutlinedTextFieldDefaults.colors(
                    focusedBorderColor = Brand.Accent,
                    unfocusedBorderColor = Brand.Stroke,
                    focusedLabelColor = Brand.Accent,
                    cursorColor = Brand.Accent
                ),
                modifier = Modifier.fillMaxWidth()
            )
            Spacer(Modifier.height(10.dp))
            Row {
                QuickChip("/Music") { onQuick("/Music") }
                Spacer(Modifier.width(8.dp))
                QuickChip("/Books/Audiobooks") { onQuick("/Books/Audiobooks") }
            }
            Spacer(Modifier.height(14.dp))
            Row(
                modifier = Modifier.fillMaxWidth().clip(RoundedCornerShape(10.dp))
                    .clickable { onReplaceChange(!replaceExisting) }
                    .padding(vertical = 4.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Icon(
                    if (replaceExisting) Icons.Filled.CheckCircle else Icons.Filled.RadioButtonUnchecked,
                    contentDescription = null,
                    tint = if (replaceExisting) Brand.Accent else Brand.TextLow,
                    modifier = Modifier.size(22.dp)
                )
                Spacer(Modifier.width(10.dp))
                Column(modifier = Modifier.weight(1f)) {
                    Text("Replace existing", color = Brand.TextHi, fontSize = 14.sp)
                    Text("Delete all .m3u / .m3u8 first, then write one per folder",
                        color = Brand.TextLow, fontSize = 11.sp)
                }
            }
            Spacer(Modifier.height(14.dp))
            Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.End) {
                HeaderButton(icon = null, label = "Cancel", onClick = onCancel)
                Spacer(Modifier.width(10.dp))
                HeaderButton(icon = Icons.Filled.PlaylistAdd, label = "Generate",
                    primary = true, onClick = onGenerate)
            }
        }
    }
}

@Composable
private fun QuickChip(text: String, onClick: () -> Unit) {
    var focused by remember { mutableStateOf(false) }
    val interaction = remember { MutableInteractionSource() }
    Box(
        modifier = Modifier
            .clip(RoundedCornerShape(20.dp))
            .background(if (focused) Brand.SurfaceFocused else Brand.BgElevated)
            .border(1.dp, if (focused) Brand.Accent else Brand.Stroke, RoundedCornerShape(20.dp))
            .onFocusChanged { focused = it.isFocused }
            .focusable(interactionSource = interaction)
            .clickable(interactionSource = interaction, indication = null, onClick = onClick)
            .padding(horizontal = 14.dp, vertical = 8.dp)
    ) {
        Text(text, color = Brand.TextHi, fontSize = 13.sp)
    }
}

@Composable
private fun ContinueCard(
    title: String,
    compact: Boolean,
    modifier: Modifier = Modifier,
    onClick: () -> Unit
) {
    val interaction = remember { MutableInteractionSource() }
    var focused by remember { mutableStateOf(false) }
    Row(
        modifier = modifier
            .clip(RoundedCornerShape(16.dp))
            .background(if (focused) Brand.SurfaceFocused else Brand.Surface)
            .border(
                1.5.dp,
                if (focused) Brand.Accent else Brand.Stroke,
                RoundedCornerShape(16.dp)
            )
            .onFocusChanged { focused = it.isFocused }
            .clickable(interactionSource = interaction, indication = null, onClick = onClick)
            .padding(14.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Box(
            modifier = Modifier
                .size(if (compact) 44.dp else 52.dp)
                .clip(RoundedCornerShape(12.dp))
                .background(Brand.Accent.copy(alpha = 0.18f)),
            contentAlignment = Alignment.Center
        ) {
            Icon(
                Icons.Filled.PlayArrow,
                contentDescription = null,
                tint = Brand.Accent,
                modifier = Modifier.size(if (compact) 24.dp else 28.dp)
            )
        }
        Spacer(Modifier.width(14.dp))
        Column(modifier = Modifier.weight(1f)) {
            Text("Continue", color = Brand.Accent, fontSize = 12.sp, fontWeight = FontWeight.Bold)
            Text(
                title,
                color = Brand.TextHi,
                fontSize = if (compact) 16.sp else 18.sp,
                fontWeight = FontWeight.SemiBold,
                maxLines = 1,
                softWrap = false,
                overflow = TextOverflow.Ellipsis
            )
        }
    }
}

@Composable
private fun ItemCard(
    item: PItem,
    compact: Boolean,
    selecting: Boolean = false,
    selected: Boolean = false,
    modifier: Modifier = Modifier,
    onClick: () -> Unit
) {
    var focused by remember { mutableStateOf(false) }
    val interaction = remember { MutableInteractionSource() }
    val scale by animateFloatAsState(if (focused) 1.025f else 1f, label = "cardScale")

    val accent = when {
        item.isFolder -> Brand.Folder
        item.isPlaylist -> Brand.Glow
        item.isVideo -> Brand.Video
        item.isAudio -> Brand.Audio
        item.isImage -> Brand.Accent
        else -> Brand.TextMid
    }
    val icon = when {
        item.isFolder -> Icons.Filled.Folder
        item.isPlaylist -> Icons.Filled.QueueMusic
        item.isVideo -> Icons.Filled.Movie
        item.isAudio -> Icons.Filled.MusicNote
        item.isImage -> Icons.Filled.Image
        else -> Icons.Filled.InsertDriveFile
    }
    val subtitle = when { item.isFolder -> "Folder"; item.isPlaylist -> "Playlist"; else -> humanSize(item.size) }

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
        if (selecting && !item.isFolder && item.isPlayable) {
            Icon(
                if (selected) Icons.Filled.CheckCircle else Icons.Filled.RadioButtonUnchecked,
                contentDescription = if (selected) "Selected" else "Not selected",
                tint = if (selected) Brand.Accent else Brand.TextLow,
                modifier = Modifier.size(24.dp)
            )
        } else if (item.isFolder) {
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
private fun HeaderTitle(
    compact: Boolean,
    name: String,
    breadcrumb: String,
    modifier: Modifier = Modifier
) {
    Row(modifier = modifier, verticalAlignment = Alignment.CenterVertically) {
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
                name,
                fontSize = if (compact) 22.sp else 26.sp,
                fontWeight = FontWeight.Bold,
                color = Brand.TextHi,
                maxLines = 1,
                softWrap = false,
                overflow = TextOverflow.Ellipsis
            )
            Text(
                breadcrumb,
                fontSize = 12.sp,
                color = Brand.TextLow,
                maxLines = 1,
                softWrap = false,
                overflow = TextOverflow.Ellipsis
            )
        }
    }
}

@Composable
private fun HeaderActions(
    compact: Boolean,
    selecting: Boolean,
    selectedCount: Int,
    itemsNotEmpty: Boolean,
    onStartSelect: () -> Unit,
    onCancelSelect: () -> Unit,
    onSaveSelected: () -> Unit,
    onGenerate: () -> Unit,
    onAbout: () -> Unit,
    onLogout: () -> Unit
) {
    Row(verticalAlignment = Alignment.CenterVertically) {
        if (selecting) {
            Text("$selectedCount selected", color = Brand.TextMid, fontSize = 14.sp)
            Spacer(Modifier.width(10.dp))
            HeaderButton(
                icon = Icons.Filled.PlaylistAdd,
                label = if (compact) null else "Save",
                primary = selectedCount > 0,
                onClick = onSaveSelected
            )
            Spacer(Modifier.width(8.dp))
            HeaderButton(icon = Icons.Filled.Close, label = null, onClick = onCancelSelect)
        } else {
            if (itemsNotEmpty) {
                HeaderButton(
                    icon = Icons.Filled.Checklist,
                    label = if (compact) null else "Select",
                    onClick = onStartSelect
                )
                Spacer(Modifier.width(8.dp))
                HeaderButton(
                    icon = Icons.Filled.PlaylistAdd,
                    label = if (compact) null else "Save .m3u",
                    onClick = onGenerate
                )
                Spacer(Modifier.width(10.dp))
            }
            com.typezero.pcloudtv.cast.CastButton(modifier = Modifier.size(40.dp))
            Spacer(Modifier.width(10.dp))
            HeaderButton(icon = Icons.Outlined.Info, label = null, onClick = onAbout)
            Spacer(Modifier.width(10.dp))
            LogoutButton(onLogout)
        }
    }
}

@Composable
private fun HeaderButton(
    icon: androidx.compose.ui.graphics.vector.ImageVector?,
    label: String?,
    primary: Boolean = false,
    onClick: () -> Unit
) {
    var focused by remember { mutableStateOf(false) }
    val interaction = remember { MutableInteractionSource() }
    val active = focused || primary
    Row(
        modifier = Modifier
            .clip(RoundedCornerShape(12.dp))
            .background(if (active) Brand.Accent else Brand.Surface)
            .border(1.dp, if (active) Brand.Accent else Brand.Stroke, RoundedCornerShape(12.dp))
            .onFocusChanged { focused = it.isFocused }
            .focusable(interactionSource = interaction)
            .clickable(interactionSource = interaction, indication = null, onClick = onClick)
            .padding(horizontal = if (label == null) 12.dp else 16.dp, vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        val tint = if (active) MaterialTheme.colorScheme.onPrimary else Brand.TextMid
        if (icon != null) {
            Icon(icon, contentDescription = label ?: "Save playlist", tint = tint,
                modifier = Modifier.size(18.dp))
            if (label != null) Spacer(Modifier.width(8.dp))
        }
        if (label != null) {
            Text(label, color = tint, fontSize = 14.sp)
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
