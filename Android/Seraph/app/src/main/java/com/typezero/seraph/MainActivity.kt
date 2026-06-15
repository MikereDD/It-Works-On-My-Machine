package com.typezero.seraph

import android.content.Intent
import android.net.Uri
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.BackHandler
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.platform.LocalContext
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.compose.runtime.collectAsState
import com.typezero.seraph.data.model.AudioFile
import com.typezero.seraph.di.ViewModelFactory
import com.typezero.seraph.ui.editor.TagEditorScreen
import com.typezero.seraph.ui.editor.TagEditorViewModel
import com.typezero.seraph.ui.library.LibraryScreen
import com.typezero.seraph.ui.library.LibraryViewModel
import com.typezero.seraph.ui.login.PCloudWebLogin
import com.typezero.seraph.ui.rename.RenameScreen
import com.typezero.seraph.ui.rename.RenameViewModel
import com.typezero.seraph.ui.theme.SeraphTheme

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        val container = (application as SeraphApp).container
        val factory = ViewModelFactory(container)
        setContent {
            SeraphTheme {
                AppRoot(factory)
            }
        }
    }
}

/** State-based navigation: Library, Editor (a file is selected), or Rename. */
@Composable
private fun AppRoot(factory: ViewModelFactory) {
    val context = LocalContext.current
    val libraryVm: LibraryViewModel = viewModel(factory = factory)
    val editorVm: TagEditorViewModel = viewModel(factory = factory)
    val renameVm: RenameViewModel = viewModel(factory = factory)

    val libraryState by libraryVm.state.collectAsState()
    val editorState by editorVm.state.collectAsState()
    val renameState by renameVm.state.collectAsState()

    var selected by remember { mutableStateOf<AudioFile?>(null) }
    var showRename by remember { mutableStateOf(false) }

    // Leave the editor automatically once a save lands.
    LaunchedEffect(Unit) {
        editorVm.saved.collect { selected = null }
    }
    // After renames apply, leave the rename screen and rescan (URIs/ids changed).
    LaunchedEffect(Unit) {
        renameVm.applied.collect {
            showRename = false
            libraryVm.rescan()
        }
    }

    val folderPicker = rememberLauncherForActivityResult(
        ActivityResultContracts.OpenDocumentTree()
    ) { uri: Uri? ->
        if (uri != null) {
            // Persist read+write access so future launches can re-tag without re-picking.
            val flags = Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION
            runCatching { context.contentResolver.takePersistableUriPermission(uri, flags) }
            libraryVm.onFolderPicked(uri)
        }
    }

    // pCloud sign-in: open pCloud's real web login (Google + 2FA work there) and
    // capture the session's auth token.
    var showWebLogin by remember { mutableStateOf(false) }
    LaunchedEffect(Unit) {
        libraryVm.pcloudAuthRequests.collect { showWebLogin = true }
    }

    val current = selected
    // On the library screen, system Back climbs out of subfolders before exiting.
    if (current == null && !showRename && !showWebLogin && !libraryState.atRoot) {
        BackHandler { libraryVm.navigateUp() }
    }
    when {
        showWebLogin -> PCloudWebLogin(
            onResult = { token ->
                showWebLogin = false
                libraryVm.completePCloudAuth(token)
            },
            onCancel = { showWebLogin = false },
        )
        showRename -> RenameScreen(
            state = renameState,
            onBack = { showRename = false },
            onTemplateChange = { renameVm.onTemplateChange(it) },
            onReset = { renameVm.resetTemplate() },
            onApply = { renameVm.apply() },
        )
        current == null -> LibraryScreen(
            state = libraryState,
            onPickDevice = { folderPicker.launch(null) },
            onSelectPCloud = { libraryVm.selectPCloud() },
            onOpenFolder = { node -> libraryVm.openFolder(node) },
            onUp = { libraryVm.navigateUp() },
            onOpen = { file ->
                selected = file
                editorVm.load(file)
            },
            onRename = {
                renameVm.start(libraryState.files)
                showRename = true
            },
        )
        else -> TagEditorScreen(
            state = editorState,
            onBack = { selected = null },
            onEdit = { transform -> editorVm.edit(transform) },
            onLookup = { editorVm.lookup() },
            onApply = { c -> editorVm.applyCandidate(c) },
            onSave = { editorVm.save() },
        )
    }
}
