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
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.interaction.collectIsPressedAsState
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
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Info
import androidx.compose.ui.platform.LocalContext
import androidx.compose.material.icons.filled.ChevronRight
import androidx.compose.material.icons.filled.Folder
import androidx.compose.material.icons.filled.Description
import androidx.compose.ui.viewinterop.AndroidView
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.Font
import androidx.compose.foundation.verticalScroll
import androidx.compose.ui.input.key.onKeyEvent
import androidx.compose.ui.input.key.Key
import androidx.compose.ui.input.key.key
import androidx.compose.ui.input.key.type
import androidx.compose.ui.input.key.KeyEventType
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.material.icons.filled.Logout
import androidx.compose.material.icons.filled.MusicNote
import androidx.compose.material.icons.filled.Movie
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Image
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material.icons.filled.AccountCircle
import androidx.compose.material.icons.filled.PersonAdd
import androidx.compose.material.icons.filled.Check
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
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
import coil.compose.AsyncImage
import androidx.compose.ui.layout.ContentScale
import com.typezero.pcloudtv.data.PItem
import com.typezero.pcloudtv.data.LastPlayed
import com.typezero.pcloudtv.data.Session
import com.typezero.pcloudtv.ui.theme.Brand

/** Built playlists (from a song selection) are saved here. */
private const val PLAYLIST_DIR = "/Music/playlists"

/** Only these top-level folders are shown at the pCloud root (lowercased). */
private val ROOT_FOLDERS = setOf("music", "video")

// Synthetic "Recently-Played" tree. Negative ids never collide with real pCloud
// folder ids, so these ride the normal folder navigation without hitting the API.
private const val RP_ROOT = -100L
private const val RP_AUDIO = -101L
private const val RP_VIDEO = -102L

// Synthetic node for the saved-playlists view at the pCloud root. Its contents
// are the .m3u files in PLAYLIST_DIR, resolved on entry.
private const val PLAYLISTS_ROOT = -200L

// Synthetic node surfacing the audiobooks library (a grandchild of root) as a
// top-level shortcut.
private const val AUDIOBOOKS_ROOT = -201L
private const val AUDIOBOOKS_DIR = "/Books/Audiobooks"

private val VIDEO_EXTS = setOf(
    "mp4", "mkv", "avi", "mov", "webm", "m4v", "ts", "m2ts", "flv", "wmv", "mpg", "mpeg", "3gp"
)

/** Classify a past session as video by the file type of its first track (else audio). */
private fun LastPlayed.looksVideo(): Boolean {
    val item = queue.firstOrNull() ?: return false
    return listOfNotNull(item.path, item.title, item.directUrl).any { c ->
        c.substringBefore('?').substringAfterLast('.', "").lowercase() in VIDEO_EXTS
    }
}

@Composable
fun BrowseScreen(
    client: PCloudClient,
    session: Session,
    accounts: List<com.typezero.pcloudtv.data.Account>,
    activeAccountId: String?,
    onPlayQueue: (List<com.typezero.pcloudtv.data.MediaItem>, String?) -> Unit,
    onSwitchAccount: (String) -> Unit,
    onAddAccount: () -> Unit,
    onLogout: () -> Unit
) {
    val stack = remember { mutableStateListOf(0L to "pCloud") }
    val current = stack.last()

    // "Continue" — the most recent queue, loaded fresh each time we enter the browser.
    val browseContext = LocalContext.current
    val browseStore = remember { com.typezero.pcloudtv.data.SessionStore(browseContext) }
    var recents by remember { mutableStateOf(browseStore.getRecents()) }

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
                    // All generated playlists land in the central /Music/playlists
                    // folder (so they show up under Playlists), with absolute track
                    // paths since the .m3u no longer sits beside the audio.
                    val dir = client.ensureFolder(session, PLAYLIST_DIR)
                    if (dir is ApiResult.Error) {
                        saving = false
                        saveMessage = "Couldn't open $PLAYLIST_DIR: ${dir.message}"
                        return@launch
                    }
                    val dirId = (dir as ApiResult.Ok).value
                    val rootRel = ("/" + path.trim().trim('/'))
                    genTotal = folders.size
                    var ok = 0
                    for ((i, fol) in folders.withIndex()) {
                        genName = fol.name
                        genDone = i + 1
                        val entries = fol.files.map { f ->
                            f.name to (fol.path.trimEnd('/') + "/" + f.name)
                        }
                        // Name by the folder's path under the scan root so playlists
                        // from same-named folders don't collide in one directory.
                        val under = fol.path.removePrefix(rootRel).trim('/')
                        val label = if (under.isBlank()) fol.name.ifBlank { "Playlist" }
                                    else under.replace("/", " - ")
                        val pname = "$label.m3u"
                        if (client.savePlaylistAbsolute(session, dirId, pname, entries) is ApiResult.Ok) ok++
                    }
                    saving = false
                    val cleaned = if (replaceExisting) "Removed $removed old, " else ""
                    saveMessage = if (folders.isEmpty()) {
                        "${cleaned}no folders with audio found under \"$path\"."
                    } else {
                        "${cleaned}saved $ok playlist(s) to $PLAYLIST_DIR from ${folders.size} folder(s)."
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
    var query by remember { mutableStateOf("") }

    // Recursive ("deep") search of the current folder's whole subtree. The plain
    // `visible` filter only sees the current folder's immediate children, so a
    // match nested in a subfolder (e.g. Music/Rock/Helmet searched from Music)
    // would otherwise show "no matches". Active only inside a real pCloud folder
    // (current.first >= 0); the synthetic roots use the local filter.
    var deepResults by remember { mutableStateOf<List<com.typezero.pcloudtv.data.SearchHit>>(emptyList()) }
    var deepSearching by remember { mutableStateOf(false) }

    LaunchedEffect(query, current.first) {
        val q = query.trim()
        if (q.length < 2 || current.first < 0L) {
            deepResults = emptyList()
            deepSearching = false
            return@LaunchedEffect
        }
        deepSearching = true
        kotlinx.coroutines.delay(350)   // debounce keystrokes before hitting the API
        when (val r = client.searchFolder(session, current.first, q)) {
            is ApiResult.Ok -> deepResults = r.value
            is ApiResult.Error -> deepResults = emptyList()
        }
        deepSearching = false
    }

    // Saved-playlist management (inside the synthetic Playlists folder).
    var playlistsFolderId by remember { mutableStateOf<Long?>(null) }
    var managePlaylist by remember { mutableStateOf<PItem?>(null) }

    // The .nfo / .htm document currently open in the built-in viewer, if any.
    var viewingDoc by remember { mutableStateOf<PItem?>(null) }

    fun currentPathPrefix(): String {
        // Build the absolute pCloud path of the folder you're currently in.
        // The synthetic Audiobooks node stands in for /Books/Audiobooks, so map
        // its crumb back to the real path (keeps saved playlists pointing right).
        if (stack.size >= 2 && stack[1].first == AUDIOBOOKS_ROOT) {
            return AUDIOBOOKS_DIR + stack.drop(2).joinToString("") { "/" + it.second }
        }
        val p = "/" + stack.drop(1).joinToString("/") { it.second }
        return if (p == "/") "" else p
    }

    fun goToCrumb(index: Int) {
        // Pop the folder stack back to the tapped breadcrumb segment.
        while (stack.size > index + 1) stack.removeAt(stack.lastIndex)
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

    // Open / play an item (folder navigation, playlist resolve, or playback).
    // Shared by the vertical list and the row layout. Selection mode is handled
    // separately at the call site.
    fun openItem(pItem: PItem) {
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
            pItem.isViewableDoc -> viewingDoc = pItem
            pItem.isPlayable -> onPlayQueue(
                listOf(com.typezero.pcloudtv.data.MediaItem(pItem.name, pItem.fileId, null)),
                null
            )
        }
    }

    // Open a deep-search hit. For a folder we append its ancestor chain plus the
    // folder itself onto the stack so the breadcrumb stays accurate; for a file
    // we just play it. Clearing the query drops us back into normal browsing.
    fun openHit(hit: com.typezero.pcloudtv.data.SearchHit) {
        val node = hit.item
        when {
            node.isFolder && node.folderId != null -> {
                hit.ancestors.forEach { stack.add(it) }
                stack.add(node.folderId!! to node.name)
                query = ""
            }
            node.isViewableDoc -> viewingDoc = node
            node.isPlayable -> onPlayQueue(
                listOf(com.typezero.pcloudtv.data.MediaItem(node.name, node.fileId, null)),
                null
            )
        }
    }

    LaunchedEffect(current.first, reloadKey) {
        loading = true
        error = null
        query = ""
        when (current.first) {
            RP_ROOT -> items = listOf(
                PItem("Audio", true, RP_AUDIO, null, "", 0, 0L),
                PItem("Video", true, RP_VIDEO, null, "", 0, 0L)
            )
            // Leaves render the recents list directly (see body), not pCloud items.
            RP_AUDIO, RP_VIDEO -> items = emptyList()
            PLAYLISTS_ROOT -> when (val f = client.ensureFolder(session, PLAYLIST_DIR)) {
                is ApiResult.Ok -> {
                    playlistsFolderId = f.value
                    when (val r = client.listFolder(session, f.value)) {
                        is ApiResult.Ok -> items = r.value.filter { it.isPlaylist }
                        is ApiResult.Error -> error = r.message
                    }
                }
                is ApiResult.Error -> error = f.message
            }
            AUDIOBOOKS_ROOT -> when (val r = client.listFolderByPath(session, AUDIOBOOKS_DIR)) {
                is ApiResult.Ok -> items = r.value
                is ApiResult.Error -> error = r.message
            }
            else -> when (val r = client.listFolder(session, current.first)) {
                is ApiResult.Ok -> items = r.value
                is ApiResult.Error -> error = r.message
            }
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
            if (compact) {
                Column(modifier = Modifier.fillMaxWidth().padding(bottom = 14.dp)) {
                    HeaderTitle(
                        compact = true,
                        name = current.second,
                        crumbs = stack.map { it.second },
                        onCrumbClick = { goToCrumb(it) },
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
                            accounts = accounts,
                            activeAccountId = activeAccountId,
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
                            onSwitchAccount = onSwitchAccount,
                            onAddAccount = onAddAccount,
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
                        crumbs = stack.map { it.second },
                        onCrumbClick = { goToCrumb(it) },
                        modifier = Modifier.weight(1f)
                    )
                    HeaderActions(
                        compact = false,
                        selecting = selecting,
                        selectedCount = selectedItems.size,
                        itemsNotEmpty = items.isNotEmpty(),
                        accounts = accounts,
                        activeAccountId = activeAccountId,
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
                        onSwitchAccount = onSwitchAccount,
                        onAddAccount = onAddAccount,
                        onAbout = { showAbout = true },
                        onLogout = onLogout
                    )
                }
            }

            val inRpLeaf = current.first == RP_AUDIO || current.first == RP_VIDEO
            when {
                loading -> Box(Modifier.fillMaxSize(), Alignment.Center) {
                    CircularProgressIndicator(color = Brand.Accent)
                }

                error != null -> Box(Modifier.fillMaxSize(), Alignment.Center) {
                    Text("Couldn't load this folder.\n$error",
                        color = Brand.TextMid, fontSize = 15.sp)
                }

                inRpLeaf -> {
                    val wantVideo = current.first == RP_VIDEO
                    val list = remember(recents, wantVideo) {
                        recents.filter { it.looksVideo() == wantVideo }
                    }
                    if (list.isEmpty()) {
                        Box(Modifier.fillMaxSize(), Alignment.Center) {
                            Text(
                                "No recently played ${if (wantVideo) "video" else "audio"} yet.",
                                color = Brand.TextLow, fontSize = 15.sp
                            )
                        }
                    } else {
                        LaunchedEffect(list) { runCatching { firstRow.requestFocus() } }
                        LazyColumn(
                            modifier = Modifier.fillMaxSize(),
                            verticalArrangement = Arrangement.spacedBy(if (compact) 10.dp else 12.dp)
                        ) {
                            item {
                                Row(
                                    modifier = rowMax.padding(horizontal = 4.dp, vertical = 2.dp),
                                    verticalAlignment = Alignment.CenterVertically
                                ) {
                                    Text(
                                        "${list.size} saved",
                                        color = Brand.TextMid,
                                        fontSize = 13.sp,
                                        modifier = Modifier.weight(1f)
                                    )
                                    Text(
                                        "Clear all",
                                        color = Brand.Accent,
                                        fontSize = 13.sp,
                                        fontWeight = FontWeight.Bold,
                                        modifier = Modifier
                                            .clip(RoundedCornerShape(8.dp))
                                            .clickable {
                                                browseStore.clearRecents()
                                                recents = browseStore.getRecents()
                                            }
                                            .padding(horizontal = 10.dp, vertical = 6.dp)
                                    )
                                }
                            }
                            itemsIndexed(list) { index, r ->
                                ContinueCard(
                                    title = r.title,
                                    compact = compact,
                                    modifier = rowMax.then(
                                        if (index == 0) Modifier.focusRequester(firstRow) else Modifier
                                    ),
                                    label = null,
                                    onDelete = {
                                        browseStore.removeRecent(r.title, r.playlistKey)
                                        recents = browseStore.getRecents()
                                    },
                                    onClick = { onPlayQueue(r.queue, r.playlistKey) }
                                )
                            }
                        }
                    }
                }

                items.isEmpty() -> Box(Modifier.fillMaxSize(), Alignment.Center) {
                    Text("Nothing playable here yet.",
                        color = Brand.TextLow, fontSize = 15.sp)
                }

                else -> {
                    val atRoot = stack.size == 1
                    val visible = remember(items, query, atRoot, recents) {
                        // At the pCloud root, show the synthetic Recently-Played
                        // folder plus the curated top-level folders (Music / Video);
                        // everything else is hidden.
                        val base =
                            if (atRoot) {
                                val real = items.filter {
                                    it.isFolder && it.name.trim().lowercase() in ROOT_FOLDERS
                                }
                                val rp = if (recents.isNotEmpty())
                                    listOf(PItem("Recently-Played", true, RP_ROOT, null, "", 0, 0L))
                                else emptyList()
                                val pl = listOf(
                                    PItem("Playlists", true, PLAYLISTS_ROOT, null, "", 0, 0L)
                                )
                                val ab = listOf(
                                    PItem("Audiobooks", true, AUDIOBOOKS_ROOT, null, "", 0, 0L)
                                )
                                rp + pl + real + ab
                            } else items
                        val q = query.trim()
                        if (q.isBlank()) base
                        else base.filter { it.name.contains(q, ignoreCase = true) }
                    }
                    LaunchedEffect(items) { runCatching { firstRow.requestFocus() } }
                    LazyColumn(
                        modifier = Modifier.fillMaxSize(),
                        verticalArrangement = Arrangement.spacedBy(if (compact) 10.dp else 12.dp)
                    ) {
                        if (!selecting) {
                            item {
                                SearchField(
                                    query = query,
                                    onQueryChange = { query = it },
                                    modifier = rowMax
                                )
                            }
                        }
                        if (query.isBlank() && stack.size == 1 && !selecting && visible.isEmpty()) {
                            item {
                                Text(
                                    "Nothing here yet.",
                                    color = Brand.TextLow, fontSize = 14.sp,
                                    modifier = Modifier.padding(vertical = 24.dp)
                                )
                            }
                        }
                        val deepActive =
                            query.trim().length >= 2 && current.first >= 0L && !selecting
                        if (deepActive) {
                            // Recursive results across this folder and all subfolders.
                            if (deepResults.isEmpty() && deepSearching) {
                                item {
                                    Row(
                                        verticalAlignment = Alignment.CenterVertically,
                                        modifier = Modifier.padding(vertical = 24.dp)
                                    ) {
                                        CircularProgressIndicator(
                                            color = Brand.Accent, strokeWidth = 2.dp,
                                            modifier = Modifier.size(18.dp)
                                        )
                                        Spacer(Modifier.width(12.dp))
                                        Text(
                                            "Searching \u201C${query.trim()}\u201D\u2026",
                                            color = Brand.TextLow, fontSize = 14.sp
                                        )
                                    }
                                }
                            } else if (deepResults.isEmpty()) {
                                item {
                                    Text(
                                        "No matches for \u201C${query.trim()}\u201D",
                                        color = Brand.TextLow, fontSize = 14.sp,
                                        modifier = Modifier.padding(vertical = 24.dp)
                                    )
                                }
                            } else {
                                if (deepSearching) {
                                    item {
                                        Text(
                                            "Searching\u2026",
                                            color = Brand.TextLow, fontSize = 12.sp,
                                            modifier = Modifier.padding(bottom = 2.dp)
                                        )
                                    }
                                }
                                itemsIndexed(deepResults) { index, hit ->
                                    ItemCard(
                                        item = hit.item,
                                        compact = compact,
                                        client = client,
                                        session = session,
                                        modifier = rowMax.then(
                                            if (index == 0) Modifier.focusRequester(firstRow) else Modifier
                                        ),
                                        subtitleOverride = if (hit.parentLabel.isBlank())
                                            (if (hit.item.isFolder) "Folder · here" else "here")
                                        else "in ${hit.parentLabel}",
                                        onClick = { openHit(hit) }
                                    )
                                }
                            }
                        } else {
                            if (visible.isEmpty() && query.isNotBlank()) {
                                item {
                                    Text(
                                        "No matches for \u201C${query.trim()}\u201D",
                                        color = Brand.TextLow, fontSize = 14.sp,
                                        modifier = Modifier.padding(vertical = 24.dp)
                                    )
                                }
                            }
                            // Vertical list — folders and files, the layout in the app.
                            itemsIndexed(visible) { index, pItem ->
                                ItemCard(
                                    item = pItem,
                                    compact = compact,
                                    client = client,
                                    session = session,
                                    selecting = selecting,
                                    selected = pItem.fileId != null && selectedItems.any { it.fileId == pItem.fileId },
                                    modifier = rowMax.then(
                                        if (index == 0) Modifier.focusRequester(firstRow) else Modifier
                                    ),
                                    onManage = if (current.first == PLAYLISTS_ROOT && pItem.isPlaylist) {
                                        { managePlaylist = pItem }
                                    } else null,
                                    onClick = {
                                        if (selecting) {
                                            when {
                                                pItem.isFolder ->
                                                    stack.add(pItem.folderId!! to pItem.name)
                                                !pItem.isPlaylist && pItem.isPlayable && pItem.fileId != null ->
                                                    toggleSelect(pItem)
                                            }
                                        } else openItem(pItem)
                                    }
                                )
                            }
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

        managePlaylist?.let { pl ->
            PlaylistManager(
                playlist = pl,
                playlistsFolderId = playlistsFolderId,
                client = client,
                session = session,
                compact = compact,
                onPlay = {
                    managePlaylist = null
                    resolveError = null
                    resolving = true
                    scope.launch {
                        when (val r = client.resolvePlaylist(session, pl, items)) {
                            is ApiResult.Ok -> { resolving = false; onPlayQueue(r.value, "pl:${pl.fileId}") }
                            is ApiResult.Error -> { resolving = false; resolveError = r.message }
                        }
                    }
                },
                onChanged = { reloadKey++ },
                onDismiss = { managePlaylist = null }
            )
        }

        viewingDoc?.let { doc ->
            DocViewer(
                item = doc,
                client = client,
                session = session,
                onClose = { viewingDoc = null }
            )
        }
    }
}

@Composable
private fun DocViewer(
    item: PItem,
    client: PCloudClient,
    session: Session,
    onClose: () -> Unit
) {
    // Intercept Back (phone gesture / TV remote) so it closes the viewer instead
    // of falling through to the folder navigation behind the overlay.
    BackHandler { onClose() }

    var loading by remember { mutableStateOf(true) }
    var error by remember { mutableStateOf<String?>(null) }
    var text by remember { mutableStateOf("") }            // .nfo / plain text
    var html by remember { mutableStateOf<String?>(null) } // .htm / .html

    LaunchedEffect(item.fileId) {
        loading = true; error = null
        val id = item.fileId
        if (id == null) { error = "No file id"; loading = false; return@LaunchedEffect }
        when (val r = client.fetchDocument(session, id)) {
            is ApiResult.Ok -> {
                val bytes = r.value
                if (item.isHtmlDoc) {
                    html = String(bytes, Charsets.UTF_8)
                } else {
                    val u = String(bytes, Charsets.UTF_8)
                    // NFOs are usually UTF-8; if that yields replacement chars,
                    // fall back to CP437 for legacy ASCII-art releases.
                    text = if (u.contains('\uFFFD'))
                        runCatching { String(bytes, charset("IBM437")) }.getOrDefault(u)
                    else u
                }
            }
            is ApiResult.Error -> error = r.message
        }
        loading = false
    }

    Box(
        Modifier.fillMaxSize().background(Color(0xCC000000)).clickable(onClick = onClose),
        contentAlignment = Alignment.Center
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth(0.94f)
                .fillMaxHeight(0.9f)
                .clip(RoundedCornerShape(16.dp))
                .background(Brand.Surface)
                .border(1.dp, Brand.Stroke, RoundedCornerShape(16.dp))
                .clickable(
                    interactionSource = remember { MutableInteractionSource() },
                    indication = null
                ) { /* swallow taps so the body doesn't dismiss */ }
                .padding(16.dp)
        ) {
            Row(
                verticalAlignment = Alignment.CenterVertically,
                modifier = Modifier.fillMaxWidth()
            ) {
                Icon(Icons.Filled.Description, null, tint = Brand.Accent,
                    modifier = Modifier.size(22.dp))
                Spacer(Modifier.width(10.dp))
                Text(
                    item.name,
                    color = Brand.TextHi, fontSize = 16.sp, fontWeight = FontWeight.Medium,
                    maxLines = 1, overflow = TextOverflow.Ellipsis,
                    modifier = Modifier.weight(1f)
                )
                Spacer(Modifier.width(10.dp))
                HeaderButton(icon = null, label = "Close", onClick = onClose)
            }
            Spacer(Modifier.height(12.dp))
            when {
                loading -> Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                    CircularProgressIndicator(color = Brand.Accent)
                }
                error != null -> Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                    Text(error!!, color = Brand.TextLow, fontSize = 14.sp)
                }
                html != null -> AndroidView(
                    factory = { ctx ->
                        android.webkit.WebView(ctx).apply {
                            settings.javaScriptEnabled = false
                            settings.loadWithOverviewMode = true
                            settings.useWideViewPort = true
                            setBackgroundColor(android.graphics.Color.TRANSPARENT)
                            // Let a TV remote drive the page scroll.
                            isFocusable = true
                            isFocusableInTouchMode = true
                        }
                    },
                    update = { wv ->
                        wv.loadDataWithBaseURL(null, html!!, "text/html", "UTF-8", null)
                        wv.requestFocus()
                    },
                    modifier = Modifier.fillMaxSize().clip(RoundedCornerShape(10.dp))
                )
                else -> {
                    val vScroll = rememberScrollState()
                    val hScroll = rememberScrollState()
                    val scope = androidx.compose.runtime.rememberCoroutineScope()
                    val docFocus = remember { FocusRequester() }
                    val stepPx = with(LocalDensity.current) { 96.dp.roundToPx() }
                    // Bundled DejaVu Sans Mono covers box-drawing/block glyphs at a
                    // uniform cell width, so the ASCII-art columns line up (the system
                    // monospace font falls back per-glyph and drifts).
                    val nfoFont = remember {
                        FontFamily(Font(com.typezero.pcloudtv.R.font.dejavu_sans_mono))
                    }
                    Box(
                        Modifier
                            .fillMaxSize()
                            .focusRequester(docFocus)
                            .focusable()
                            .onKeyEvent { e ->
                                if (e.type != KeyEventType.KeyDown) return@onKeyEvent false
                                when (e.key) {
                                    Key.DirectionDown -> {
                                        scope.launch { vScroll.animateScrollTo(vScroll.value + stepPx) }; true
                                    }
                                    Key.DirectionUp -> {
                                        // At the very top, let focus escape upward (to Close).
                                        if (vScroll.value == 0) false
                                        else {
                                            scope.launch { vScroll.animateScrollTo(vScroll.value - stepPx) }; true
                                        }
                                    }
                                    Key.DirectionRight -> {
                                        scope.launch { hScroll.animateScrollTo(hScroll.value + stepPx) }; true
                                    }
                                    Key.DirectionLeft -> {
                                        scope.launch { hScroll.animateScrollTo(hScroll.value - stepPx) }; true
                                    }
                                    else -> false
                                }
                            }
                    ) {
                        Text(
                            text,
                            color = Brand.TextMid,
                            fontSize = 11.sp,
                            lineHeight = 13.sp,
                            letterSpacing = 0.sp,
                            fontFamily = nfoFont,
                            softWrap = false,
                            style = androidx.compose.ui.text.TextStyle(
                                platformStyle = androidx.compose.ui.text.PlatformTextStyle(
                                    includeFontPadding = false
                                )
                            ),
                            modifier = Modifier
                                .fillMaxSize()
                                .verticalScroll(vScroll)
                                .horizontalScroll(hScroll)
                        )
                    }
                    LaunchedEffect(text) {
                        if (text.isNotEmpty()) runCatching { docFocus.requestFocus() }
                    }
                }
            }
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
                "For every folder with audio under this pCloud path (including " +
                    "subfolders), writes one .m3u into /Music/playlists.",
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
private fun RecentPosterCard(
    entry: com.typezero.pcloudtv.data.LastPlayed,
    compact: Boolean,
    client: PCloudClient,
    session: Session,
    onClick: () -> Unit
) {
    var focused by remember { mutableStateOf(false) }
    val interaction = remember { MutableInteractionSource() }
    val scale by animateFloatAsState(if (focused) 1.06f else 1f, label = "posterScale")

    val fileId = entry.queue.firstOrNull()?.fileId
    var thumbUrl by remember(fileId) { mutableStateOf<String?>(null) }
    if (fileId != null) {
        LaunchedEffect(fileId) {
            when (val r = client.getThumbLink(session, fileId, "320x180")) {
                is ApiResult.Ok -> thumbUrl = r.value
                is ApiResult.Error -> {}
            }
        }
    }

    val posterW = if (compact) 150.dp else 184.dp
    val posterH = if (compact) 88.dp else 104.dp
    Column(
        modifier = Modifier
            .width(posterW)
            .graphicsLayer { scaleX = scale; scaleY = scale }
            .onFocusChanged { focused = it.isFocused }
            .focusable(interactionSource = interaction)
            .clickable(interactionSource = interaction, indication = null, onClick = onClick)
    ) {
        Box(
            modifier = Modifier
                .width(posterW)
                .height(posterH)
                .shadow(
                    elevation = if (focused) 16.dp else 0.dp,
                    shape = RoundedCornerShape(14.dp),
                    ambientColor = Brand.Accent,
                    spotColor = Brand.Accent
                )
                .clip(RoundedCornerShape(14.dp))
                .background(Brand.Surface)
                .border(
                    width = if (focused) 2.dp else 1.dp,
                    color = if (focused) Brand.Accent else Brand.Stroke,
                    shape = RoundedCornerShape(14.dp)
                ),
            contentAlignment = Alignment.Center
        ) {
            Icon(
                Icons.Filled.PlayArrow,
                contentDescription = null,
                tint = Brand.Accent.copy(alpha = 0.7f),
                modifier = Modifier.size(34.dp)
            )
            if (thumbUrl != null) {
                AsyncImage(
                    model = thumbUrl,
                    contentDescription = null,
                    contentScale = ContentScale.Crop,
                    modifier = Modifier
                        .matchParentSize()
                        .clip(RoundedCornerShape(14.dp))
                )
            }
        }
        Spacer(Modifier.height(6.dp))
        Text(
            entry.title,
            color = if (focused) Brand.TextHi else Brand.TextMid,
            fontSize = 12.sp,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
            modifier = Modifier.width(posterW)
        )
    }
}

@Composable
private fun PosterCard(
    item: PItem,
    compact: Boolean,
    client: PCloudClient,
    session: Session,
    modifier: Modifier = Modifier,
    onClick: () -> Unit
) {
    var focused by remember { mutableStateOf(false) }
    val interaction = remember { MutableInteractionSource() }
    val scale by animateFloatAsState(if (focused) 1.06f else 1f, label = "posterScale")

    val accent = when {
        item.isFolder -> Brand.Folder
        item.isPlaylist -> Brand.Glow
        item.isVideo -> Brand.Video
        item.isAudio -> Brand.Audio
        item.isImage -> Brand.Accent
        item.isViewableDoc -> Brand.Accent
        else -> Brand.TextMid
    }
    val icon = when {
        item.isFolder -> Icons.Filled.Folder
        item.isPlaylist -> Icons.Filled.QueueMusic
        item.isVideo -> Icons.Filled.Movie
        item.isAudio -> Icons.Filled.MusicNote
        item.isImage -> Icons.Filled.Image
        item.isViewableDoc -> Icons.Filled.Description
        else -> Icons.Filled.InsertDriveFile
    }

    var thumbUrl by remember(item.fileId) { mutableStateOf<String?>(null) }
    if (item.fileId != null && (item.isVideo || item.isImage)) {
        LaunchedEffect(item.fileId) {
            when (val r = client.getThumbLink(session, item.fileId, "320x180")) {
                is ApiResult.Ok -> thumbUrl = r.value
                is ApiResult.Error -> {}
            }
        }
    }

    val posterW = if (compact) 140.dp else 168.dp
    val posterH = if (compact) 84.dp else 98.dp
    Column(
        modifier = modifier
            .width(posterW)
            .graphicsLayer { scaleX = scale; scaleY = scale }
            .onFocusChanged { focused = it.isFocused }
            .focusable(interactionSource = interaction)
            .clickable(interactionSource = interaction, indication = null, onClick = onClick)
    ) {
        Box(
            modifier = Modifier
                .width(posterW)
                .height(posterH)
                .shadow(
                    elevation = if (focused) 16.dp else 0.dp,
                    shape = RoundedCornerShape(14.dp),
                    ambientColor = accent, spotColor = accent
                )
                .clip(RoundedCornerShape(14.dp))
                .background(accent.copy(alpha = if (focused) 0.22f else 0.13f))
                .border(
                    width = if (focused) 2.dp else 1.dp,
                    color = if (focused) accent else Brand.Stroke,
                    shape = RoundedCornerShape(14.dp)
                ),
            contentAlignment = Alignment.Center
        ) {
            Icon(icon, contentDescription = null, tint = accent, modifier = Modifier.size(30.dp))
            if (thumbUrl != null) {
                AsyncImage(
                    model = thumbUrl,
                    contentDescription = null,
                    contentScale = ContentScale.Crop,
                    modifier = Modifier.matchParentSize().clip(RoundedCornerShape(14.dp))
                )
            }
        }
        Spacer(Modifier.height(6.dp))
        Text(
            item.name,
            color = if (focused) Brand.TextHi else Brand.TextMid,
            fontSize = 12.sp,
            maxLines = 2,
            overflow = TextOverflow.Ellipsis,
            modifier = Modifier.width(posterW)
        )
    }
}

@Composable
private fun SearchField(
    query: String,
    onQueryChange: (String) -> Unit,
    modifier: Modifier = Modifier
) {
    // On a TV the on-screen keyboard doesn't pop just from D-pad focus the way a
    // touch tap does, so request it explicitly when the field gains focus.
    val keyboard = androidx.compose.ui.platform.LocalSoftwareKeyboardController.current
    OutlinedTextField(
        value = query,
        onValueChange = onQueryChange,
        singleLine = true,
        placeholder = { Text("Search this folder", color = Brand.TextLow) },
        leadingIcon = { Icon(Icons.Filled.Search, contentDescription = null, tint = Brand.TextMid) },
        trailingIcon = {
            if (query.isNotEmpty()) {
                Icon(
                    Icons.Filled.Close,
                    contentDescription = "Clear search",
                    tint = Brand.TextMid,
                    modifier = Modifier.clickable { onQueryChange("") }
                )
            }
        },
        shape = RoundedCornerShape(12.dp),
        keyboardOptions = androidx.compose.foundation.text.KeyboardOptions(
            imeAction = androidx.compose.ui.text.input.ImeAction.Search
        ),
        keyboardActions = androidx.compose.foundation.text.KeyboardActions(
            onSearch = { keyboard?.hide() }
        ),
        colors = OutlinedTextFieldDefaults.colors(
            focusedBorderColor = Brand.Accent,
            unfocusedBorderColor = Brand.Stroke,
            cursorColor = Brand.Accent,
            focusedTextColor = Brand.TextHi,
            unfocusedTextColor = Brand.TextHi
        ),
        modifier = modifier
            .fillMaxWidth()
            .onFocusChanged { if (it.isFocused) keyboard?.show() }
    )
}

@Composable
private fun ContinueCard(
    title: String,
    compact: Boolean,
    modifier: Modifier = Modifier,
    label: String? = "Continue",
    onDelete: (() -> Unit)? = null,
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
            if (label != null) {
                Text(label, color = Brand.Accent, fontSize = 12.sp, fontWeight = FontWeight.Bold)
            }
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
        if (onDelete != null) {
            Spacer(Modifier.width(10.dp))
            Box(
                modifier = Modifier
                    .size(36.dp)
                    .clip(RoundedCornerShape(10.dp))
                    .background(Brand.Bg.copy(alpha = 0.6f))
                    .clickable(onClick = onDelete),
                contentAlignment = Alignment.Center
            ) {
                Icon(
                    Icons.Filled.Close,
                    contentDescription = "Remove from recently played",
                    tint = Brand.TextMid,
                    modifier = Modifier.size(20.dp)
                )
            }
        }
    }
}

@Composable
private fun ItemCard(
    item: PItem,
    compact: Boolean,
    client: PCloudClient,
    session: Session,
    selecting: Boolean = false,
    selected: Boolean = false,
    modifier: Modifier = Modifier,
    onManage: (() -> Unit)? = null,
    subtitleOverride: String? = null,
    onClick: () -> Unit
) {
    var focused by remember { mutableStateOf(false) }
    val interaction = remember { MutableInteractionSource() }
    val pressed by interaction.collectIsPressedAsState()
    val scale by animateFloatAsState(
        targetValue = when {
            pressed -> 0.97f
            focused -> 1.03f
            else -> 1f
        },
        label = "cardScale"
    )

    // pCloud generates thumbnails for images and videos. Resolve lazily; if it
    // fails or isn't available, the type icon stays as the fallback.
    var thumbUrl by remember(item.fileId) { mutableStateOf<String?>(null) }
    if (item.fileId != null && (item.isVideo || item.isImage)) {
        LaunchedEffect(item.fileId) {
            when (val r = client.getThumbLink(session, item.fileId, "128x128")) {
                is ApiResult.Ok -> thumbUrl = r.value
                is ApiResult.Error -> {}
            }
        }
    }

    val accent = when {
        item.isFolder -> Brand.Folder
        item.isPlaylist -> Brand.Glow
        item.isVideo -> Brand.Video
        item.isAudio -> Brand.Audio
        item.isImage -> Brand.Accent
        item.isViewableDoc -> Brand.Accent
        else -> Brand.TextMid
    }
    val icon = when {
        item.isFolder -> Icons.Filled.Folder
        item.isPlaylist -> Icons.Filled.QueueMusic
        item.isVideo -> Icons.Filled.Movie
        item.isAudio -> Icons.Filled.MusicNote
        item.isImage -> Icons.Filled.Image
        item.isViewableDoc -> Icons.Filled.Description
        else -> Icons.Filled.InsertDriveFile
    }
    val subtitle = subtitleOverride ?: when {
        item.isFolder -> "Folder"
        item.isPlaylist -> "Playlist"
        item.isVideo -> "Video · ${humanSize(item.size)}"
        item.isAudio -> "Audio · ${humanSize(item.size)}"
        item.isImage -> "Image · ${humanSize(item.size)}"
        item.isNfo -> "Info · ${humanSize(item.size)}"
        item.isHtmlDoc -> "Web page · ${humanSize(item.size)}"
        else -> humanSize(item.size)
    }

    Row(
        modifier = modifier
            .graphicsLayer { scaleX = scale; scaleY = scale }
            .shadow(
                elevation = if (focused) 18.dp else 0.dp,
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
            .padding(horizontal = if (compact) 14.dp else 16.dp, vertical = if (compact) 9.dp else 11.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Box(
            modifier = Modifier
                .size(if (compact) 38.dp else 42.dp)
                .clip(RoundedCornerShape(12.dp))
                .background(accent.copy(alpha = if (focused) 0.26f else 0.16f)),
            contentAlignment = Alignment.Center
        ) {
            Icon(icon, contentDescription = null, tint = accent,
                modifier = Modifier.size(if (compact) 20.dp else 24.dp))
            if (thumbUrl != null) {
                AsyncImage(
                    model = thumbUrl,
                    contentDescription = null,
                    contentScale = ContentScale.Crop,
                    modifier = Modifier
                        .matchParentSize()
                        .clip(RoundedCornerShape(12.dp))
                )
            }
        }
        Spacer(Modifier.width(12.dp))
        Column(modifier = Modifier.weight(1f)) {
            Text(
                item.name,
                color = Brand.TextHi,
                fontSize = if (compact) 15.sp else 17.sp,
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
        if (onManage != null && !selecting) {
            Spacer(Modifier.width(6.dp))
            Box(
                modifier = Modifier
                    .size(36.dp)
                    .clip(RoundedCornerShape(10.dp))
                    .background(Brand.Bg.copy(alpha = 0.6f))
                    .clickable(onClick = onManage),
                contentAlignment = Alignment.Center
            ) {
                Icon(
                    Icons.Filled.MoreVert,
                    contentDescription = "Manage playlist",
                    tint = Brand.TextMid,
                    modifier = Modifier.size(20.dp)
                )
            }
        }
    }
}

@Composable
private fun HeaderTitle(
    compact: Boolean,
    name: String,
    crumbs: List<String>,
    onCrumbClick: (Int) -> Unit,
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
            Row(
                modifier = Modifier.horizontalScroll(rememberScrollState()),
                verticalAlignment = Alignment.CenterVertically
            ) {
                crumbs.forEachIndexed { i, crumb ->
                    val isLast = i == crumbs.lastIndex
                    Text(
                        crumb,
                        fontSize = 12.sp,
                        color = if (isLast) Brand.TextMid else Brand.Accent,
                        maxLines = 1,
                        softWrap = false,
                        modifier = if (isLast) Modifier
                        else Modifier
                            .clip(RoundedCornerShape(6.dp))
                            .clickable { onCrumbClick(i) }
                            .padding(horizontal = 2.dp, vertical = 1.dp)
                    )
                    if (!isLast) {
                        Text(
                            "  ›  ",
                            fontSize = 12.sp,
                            color = Brand.TextLow,
                            maxLines = 1,
                            softWrap = false
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun HeaderActions(
    compact: Boolean,
    selecting: Boolean,
    selectedCount: Int,
    itemsNotEmpty: Boolean,
    accounts: List<com.typezero.pcloudtv.data.Account>,
    activeAccountId: String?,
    onStartSelect: () -> Unit,
    onCancelSelect: () -> Unit,
    onSaveSelected: () -> Unit,
    onGenerate: () -> Unit,
    onSwitchAccount: (String) -> Unit,
    onAddAccount: () -> Unit,
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
            Text(
                "v" + com.typezero.pcloudtv.BuildConfig.VERSION_NAME,
                color = Brand.TextLow,
                fontSize = 11.sp
            )
            Spacer(Modifier.width(10.dp))
            com.typezero.pcloudtv.cast.CastButton(modifier = Modifier.size(40.dp))
            Spacer(Modifier.width(10.dp))
            var menuOpen by remember { mutableStateOf(false) }
            Box {
                HeaderButton(
                    icon = Icons.Filled.MoreVert,
                    label = null,
                    onClick = { menuOpen = true }
                )
                DropdownMenu(
                    expanded = menuOpen,
                    onDismissRequest = { menuOpen = false }
                ) {
                    if (itemsNotEmpty) {
                        DropdownMenuItem(
                            text = { Text("Select") },
                            leadingIcon = { Icon(Icons.Filled.Checklist, null) },
                            onClick = { menuOpen = false; onStartSelect() }
                        )
                        DropdownMenuItem(
                            text = { Text("Save .m3u") },
                            leadingIcon = { Icon(Icons.Filled.PlaylistAdd, null) },
                            onClick = { menuOpen = false; onGenerate() }
                        )
                    }
                    accounts.forEach { acc ->
                        DropdownMenuItem(
                            text = { Text(acc.label, maxLines = 1) },
                            leadingIcon = {
                                Icon(
                                    if (acc.id == activeAccountId) Icons.Filled.Check
                                    else Icons.Filled.AccountCircle,
                                    contentDescription = null,
                                    tint = if (acc.id == activeAccountId) Brand.Accent else Brand.TextMid
                                )
                            },
                            onClick = {
                                menuOpen = false
                                if (acc.id != activeAccountId) onSwitchAccount(acc.id)
                            }
                        )
                    }
                    DropdownMenuItem(
                        text = { Text("Add account") },
                        leadingIcon = { Icon(Icons.Filled.PersonAdd, null) },
                        onClick = { menuOpen = false; onAddAccount() }
                    )
                    DropdownMenuItem(
                        text = { Text("About") },
                        leadingIcon = { Icon(Icons.Outlined.Info, null) },
                        onClick = { menuOpen = false; onAbout() }
                    )
                    DropdownMenuItem(
                        text = { Text("Sign out") },
                        leadingIcon = { Icon(Icons.Filled.Logout, null) },
                        onClick = { menuOpen = false; onLogout() }
                    )
                }
            }
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

@Composable
private fun PlaylistManager(
    playlist: PItem,
    playlistsFolderId: Long?,
    client: PCloudClient,
    session: Session,
    compact: Boolean,
    onPlay: () -> Unit,
    onChanged: () -> Unit,
    onDismiss: () -> Unit
) {
    val scope = androidx.compose.runtime.rememberCoroutineScope()
    val tracks = remember { mutableStateListOf<Pair<String, String>>() }
    var loaded by remember { mutableStateOf(false) }
    var busy by remember { mutableStateOf(false) }
    var message by remember { mutableStateOf<String?>(null) }
    var dirty by remember { mutableStateOf(false) }
    var renaming by remember { mutableStateOf(false) }
    var nameField by remember {
        mutableStateOf(playlist.name.removeSuffix(".m3u8").removeSuffix(".m3u"))
    }
    var confirmDelete by remember { mutableStateOf(false) }
    var picking by remember { mutableStateOf(false) }

    LaunchedEffect(playlist.fileId) {
        val fid = playlist.fileId
        if (fid == null) { loaded = true; return@LaunchedEffect }
        when (val r = client.readPlaylistEntries(session, fid)) {
            is ApiResult.Ok -> { tracks.clear(); tracks.addAll(r.value); loaded = true }
            is ApiResult.Error -> { message = r.message; loaded = true }
        }
    }

    fun saveTracks() {
        val fid = playlistsFolderId
        if (fid == null) { message = "Playlists folder isn't ready yet."; return }
        busy = true; message = null
        scope.launch {
            val res = client.savePlaylistAbsolute(session, fid, playlist.name, tracks.toList())
            busy = false
            when (res) {
                is ApiResult.Ok -> { dirty = false; message = "Saved."; onChanged() }
                is ApiResult.Error -> message = "Couldn't save: ${res.message}"
            }
        }
    }

    BackHandler {
        when {
            picking -> picking = false
            renaming -> renaming = false
            confirmDelete -> confirmDelete = false
            else -> onDismiss()
        }
    }

    Box(
        Modifier.fillMaxSize().background(Color(0xE6000000)),
        contentAlignment = Alignment.Center
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth().widthIn(max = 560.dp)
                .fillMaxHeight(0.92f)
                .padding(if (compact) 12.dp else 24.dp)
                .clip(RoundedCornerShape(20.dp))
                .background(Brand.Surface)
                .border(1.dp, Brand.Stroke, RoundedCornerShape(20.dp))
                .padding(18.dp)
        ) {
            Text(
                playlist.name,
                color = Brand.TextHi, fontSize = 18.sp, fontWeight = FontWeight.Bold,
                maxLines = 2, overflow = TextOverflow.Ellipsis
            )
            Spacer(Modifier.height(4.dp))
            Text(
                if (picking) "Tap a track to add it" else "${tracks.size} track(s)",
                color = Brand.TextLow, fontSize = 12.sp
            )
            Spacer(Modifier.height(14.dp))

            if (!loaded) {
                Box(Modifier.fillMaxWidth().weight(1f), contentAlignment = Alignment.Center) {
                    CircularProgressIndicator(color = Brand.Accent)
                }
            } else if (picking) {
                PlaylistAddPicker(
                    client = client,
                    session = session,
                    modifier = Modifier.weight(1f),
                    onAdd = { title, path -> tracks.add(title to path); dirty = true }
                )
            } else {
                LazyColumn(
                    modifier = Modifier.weight(1f),
                    verticalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    if (tracks.isEmpty()) {
                        item {
                            Text(
                                "This playlist is empty. Use \"Add tracks\" below.",
                                color = Brand.TextLow, fontSize = 13.sp,
                                modifier = Modifier.padding(vertical = 12.dp)
                            )
                        }
                    }
                    itemsIndexed(tracks) { index, t ->
                        Row(
                            modifier = Modifier
                                .fillMaxWidth()
                                .clip(RoundedCornerShape(12.dp))
                                .background(Brand.Bg)
                                .border(1.dp, Brand.Stroke, RoundedCornerShape(12.dp))
                                .padding(horizontal = 12.dp, vertical = 10.dp),
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            Text(
                                "${index + 1}.",
                                color = Brand.TextLow, fontSize = 13.sp,
                                modifier = Modifier.padding(end = 10.dp)
                            )
                            Text(
                                t.first,
                                color = Brand.TextHi, fontSize = 14.sp,
                                maxLines = 1, overflow = TextOverflow.Ellipsis,
                                modifier = Modifier.weight(1f)
                            )
                            Box(
                                modifier = Modifier
                                    .size(34.dp)
                                    .clip(RoundedCornerShape(9.dp))
                                    .clickable { tracks.removeAt(index); dirty = true },
                                contentAlignment = Alignment.Center
                            ) {
                                Icon(
                                    Icons.Filled.Close, contentDescription = "Remove track",
                                    tint = Brand.TextMid, modifier = Modifier.size(18.dp)
                                )
                            }
                        }
                    }
                }
            }

            message?.let {
                Spacer(Modifier.height(8.dp))
                Text(it, color = Brand.Accent, fontSize = 12.sp)
            }

            Spacer(Modifier.height(12.dp))

            if (picking) {
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.End) {
                    HeaderButton(
                        icon = Icons.Filled.Check, label = "Done adding", primary = true,
                        onClick = { picking = false }
                    )
                }
            } else {
                Row(Modifier.fillMaxWidth()) {
                    HeaderButton(icon = Icons.Filled.PlayArrow, label = "Play", onClick = onPlay)
                    Spacer(Modifier.width(8.dp))
                    HeaderButton(
                        icon = Icons.Filled.PlaylistAdd, label = "Add tracks",
                        onClick = { message = null; picking = true }
                    )
                }
                Spacer(Modifier.height(8.dp))
                Row(Modifier.fillMaxWidth()) {
                    HeaderButton(icon = null, label = "Rename", onClick = { renaming = true })
                    Spacer(Modifier.width(8.dp))
                    HeaderButton(icon = null, label = "Delete", onClick = { confirmDelete = true })
                }
                Spacer(Modifier.height(12.dp))
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.End) {
                    HeaderButton(icon = null, label = "Close", onClick = onDismiss)
                    Spacer(Modifier.width(8.dp))
                    HeaderButton(
                        icon = Icons.Filled.Check,
                        label = if (dirty) "Save changes" else "Saved",
                        primary = dirty,
                        onClick = { if (dirty) saveTracks() }
                    )
                }
            }
        }

        if (busy) {
            Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                CircularProgressIndicator(color = Brand.Accent)
            }
        }
    }

    if (renaming) {
        Box(
            Modifier.fillMaxSize().background(Color(0xCC000000)).clickable { renaming = false },
            contentAlignment = Alignment.Center
        ) {
            Column(
                modifier = Modifier
                    .fillMaxWidth().widthIn(max = 460.dp).padding(28.dp)
                    .clip(RoundedCornerShape(20.dp)).background(Brand.Surface)
                    .border(1.dp, Brand.Stroke, RoundedCornerShape(20.dp)).padding(22.dp)
            ) {
                Text("Rename playlist", color = Brand.TextHi, fontSize = 18.sp,
                    fontWeight = FontWeight.Bold)
                Spacer(Modifier.height(14.dp))
                OutlinedTextField(
                    value = nameField,
                    onValueChange = { nameField = it },
                    singleLine = true,
                    label = { Text("Name") },
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
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.End) {
                    HeaderButton(icon = null, label = "Cancel", onClick = { renaming = false })
                    Spacer(Modifier.width(10.dp))
                    HeaderButton(
                        icon = Icons.Filled.Check, label = "Rename", primary = true,
                        onClick = {
                            val fid = playlist.fileId
                            val clean = nameField.trim().removeSuffix(".m3u8").removeSuffix(".m3u")
                            if (fid != null && clean.isNotBlank()) {
                                busy = true
                                scope.launch {
                                    val res = client.renameFile(session, fid, "$clean.m3u")
                                    busy = false; renaming = false
                                    when (res) {
                                        is ApiResult.Ok -> { onChanged(); onDismiss() }
                                        is ApiResult.Error -> message = "Couldn't rename: ${res.message}"
                                    }
                                }
                            } else {
                                renaming = false
                            }
                        }
                    )
                }
            }
        }
    }

    if (confirmDelete) {
        Box(
            Modifier.fillMaxSize().background(Color(0xCC000000)).clickable { confirmDelete = false },
            contentAlignment = Alignment.Center
        ) {
            Column(
                modifier = Modifier
                    .fillMaxWidth().widthIn(max = 460.dp).padding(28.dp)
                    .clip(RoundedCornerShape(20.dp)).background(Brand.Surface)
                    .border(1.dp, Brand.Stroke, RoundedCornerShape(20.dp)).padding(22.dp)
            ) {
                Text("Delete playlist?", color = Brand.TextHi, fontSize = 18.sp,
                    fontWeight = FontWeight.Bold)
                Spacer(Modifier.height(8.dp))
                Text(
                    "\"${playlist.name}\" will be permanently removed from $PLAYLIST_DIR.",
                    color = Brand.TextLow, fontSize = 13.sp
                )
                Spacer(Modifier.height(18.dp))
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.End) {
                    HeaderButton(icon = null, label = "Cancel", onClick = { confirmDelete = false })
                    Spacer(Modifier.width(10.dp))
                    HeaderButton(
                        icon = null, label = "Delete", primary = true,
                        onClick = {
                            val fid = playlist.fileId
                            if (fid != null) {
                                busy = true
                                scope.launch {
                                    val res = client.deleteFile(session, fid)
                                    busy = false; confirmDelete = false
                                    when (res) {
                                        is ApiResult.Ok -> { onChanged(); onDismiss() }
                                        is ApiResult.Error -> message = "Couldn't delete: ${res.message}"
                                    }
                                }
                            } else {
                                confirmDelete = false
                            }
                        }
                    )
                }
            }
        }
    }
}

@Composable
private fun PlaylistAddPicker(
    client: PCloudClient,
    session: Session,
    modifier: Modifier = Modifier,
    onAdd: (String, String) -> Unit
) {
    val crumbs = remember { mutableStateListOf(0L to "") }
    var entries by remember { mutableStateOf<List<PItem>>(emptyList()) }
    var loading by remember { mutableStateOf(false) }
    val added = remember { mutableStateListOf<String>() }

    LaunchedEffect(crumbs.last().first) {
        loading = true
        when (val r = client.listFolder(session, crumbs.last().first)) {
            is ApiResult.Ok -> entries = r.value
            is ApiResult.Error -> entries = emptyList()
        }
        loading = false
    }

    fun pathOf(name: String): String {
        val p = "/" + crumbs.drop(1).joinToString("/") { it.second }
        return (if (p == "/") "" else p) + "/" + name
    }

    Column(modifier = modifier) {
        Row(
            modifier = Modifier.fillMaxWidth().padding(bottom = 8.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            if (crumbs.size > 1) {
                Box(
                    modifier = Modifier
                        .clip(RoundedCornerShape(8.dp))
                        .clickable { crumbs.removeAt(crumbs.lastIndex) }
                        .padding(horizontal = 8.dp, vertical = 6.dp)
                ) {
                    Text("\u2039 Back", color = Brand.Accent, fontSize = 13.sp,
                        fontWeight = FontWeight.Bold)
                }
                Spacer(Modifier.width(8.dp))
            }
            Text(
                "/" + crumbs.drop(1).joinToString("/") { it.second },
                color = Brand.TextMid, fontSize = 12.sp, maxLines = 1,
                overflow = TextOverflow.Ellipsis
            )
        }
        if (loading) {
            Box(Modifier.fillMaxWidth().weight(1f), contentAlignment = Alignment.Center) {
                CircularProgressIndicator(color = Brand.Accent)
            }
        } else {
            LazyColumn(
                modifier = Modifier.weight(1f),
                verticalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                itemsIndexed(entries) { _, e ->
                    val isAudio = !e.isFolder && e.isPlayable && !e.isPlaylist
                    if (e.isFolder || isAudio) {
                        val path = if (isAudio) pathOf(e.name) else ""
                        val alreadyAdded = isAudio && added.contains(path)
                        Row(
                            modifier = Modifier
                                .fillMaxWidth()
                                .clip(RoundedCornerShape(12.dp))
                                .background(Brand.Bg)
                                .border(1.dp, Brand.Stroke, RoundedCornerShape(12.dp))
                                .clickable {
                                    if (e.isFolder) {
                                        crumbs.add(e.folderId!! to e.name)
                                    } else if (!alreadyAdded) {
                                        onAdd(e.name, path); added.add(path)
                                    }
                                }
                                .padding(horizontal = 12.dp, vertical = 10.dp),
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            Icon(
                                if (e.isFolder) Icons.Filled.Folder else Icons.Filled.MusicNote,
                                contentDescription = null,
                                tint = if (e.isFolder) Brand.Accent else Brand.TextMid,
                                modifier = Modifier.size(22.dp)
                            )
                            Spacer(Modifier.width(12.dp))
                            Text(
                                e.name,
                                color = if (alreadyAdded) Brand.TextLow else Brand.TextHi,
                                fontSize = 14.sp, maxLines = 1, overflow = TextOverflow.Ellipsis,
                                modifier = Modifier.weight(1f)
                            )
                            if (alreadyAdded) {
                                Icon(Icons.Filled.Check, contentDescription = "Added",
                                    tint = Brand.Accent, modifier = Modifier.size(18.dp))
                            } else if (!e.isFolder) {
                                Icon(Icons.Filled.PlaylistAdd, contentDescription = "Add",
                                    tint = Brand.Accent, modifier = Modifier.size(18.dp))
                            }
                        }
                    }
                }
            }
        }
    }
}
