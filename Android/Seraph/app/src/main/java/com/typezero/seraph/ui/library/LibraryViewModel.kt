package com.typezero.seraph.ui.library

import android.net.Uri
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.typezero.seraph.data.model.AudioFile
import com.typezero.seraph.storage.FolderNode
import com.typezero.seraph.storage.SourceManager
import com.typezero.seraph.storage.StorageSource
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.receiveAsFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

data class LibraryUiState(
    val isLoading: Boolean = false,
    val activeSourceId: String = StorageSource.DEVICE,
    val hasSource: Boolean = false,
    val folders: List<FolderNode> = emptyList(),
    val files: List<AudioFile> = emptyList(),
    val breadcrumb: List<FolderNode> = emptyList(),
    val pcloudSignedIn: Boolean = false,
    val error: String? = null,
) {
    val atRoot: Boolean get() = breadcrumb.isEmpty()
    val currentName: String get() = breadcrumb.lastOrNull()?.name ?: "Seraph"
}

class LibraryViewModel(
    private val sources: SourceManager,
) : ViewModel() {

    private val _state = MutableStateFlow(LibraryUiState())
    val state: StateFlow<LibraryUiState> = _state.asStateFlow()

    init {
        // Reflect a persisted pCloud session (token survives restarts).
        _state.update { it.copy(pcloudSignedIn = sources.pcloud.signedIn) }
    }

    /** Sign out of pCloud and return to the source picker. */
    fun signOutPCloud() {
        sources.pcloud.signOut()
        sources.setActive(StorageSource.DEVICE)
        _state.value = LibraryUiState(pcloudSignedIn = false)
    }

    // One-shot requests for the host Activity to open pCloud's web login.
    private val _pcloudAuthRequests = Channel<Unit>(Channel.BUFFERED)
    val pcloudAuthRequests = _pcloudAuthRequests.receiveAsFlow()

    fun onFolderPicked(treeUri: Uri) {
        sources.device.setTree(treeUri)
        sources.setActive(StorageSource.DEVICE)
        loadFolder(emptyList())
    }

    fun selectPCloud() {
        viewModelScope.launch {
            if (sources.pcloud.isReady()) {
                sources.setActive(StorageSource.PCLOUD)
                loadFolder(emptyList())
            } else {
                _pcloudAuthRequests.send(Unit)
            }
        }
    }

    /** Called once the web login captures a token; binds its region, then loads root. */
    fun completePCloudAuth(token: String) {
        _state.update { it.copy(isLoading = true, hasSource = true, activeSourceId = StorageSource.PCLOUD, error = null) }
        viewModelScope.launch {
            val error = runCatching { sources.pcloud.signInWithToken(token) }
                .getOrElse { it.message ?: "Sign-in error." }
            if (error == null) {
                _state.update { it.copy(pcloudSignedIn = true) }
                sources.setActive(StorageSource.PCLOUD)
                loadFolder(emptyList())
            } else {
                pcloudAuthFailed(error)
            }
        }
    }

    fun pcloudAuthFailed(message: String) {
        _state.update {
            it.copy(isLoading = false, hasSource = true, activeSourceId = StorageSource.PCLOUD, folders = emptyList(), files = emptyList(), error = message)
        }
    }

    /** Descend into a subfolder. */
    fun openFolder(node: FolderNode) = loadFolder(_state.value.breadcrumb + node)

    /** Go up one level. Returns false if already at root (so the caller can pass Back through). */
    fun navigateUp(): Boolean {
        val crumb = _state.value.breadcrumb
        if (crumb.isEmpty()) return false
        loadFolder(crumb.dropLast(1))
        return true
    }

    /** Reload the current folder (e.g. after a rename changed names). */
    fun rescan() = loadFolder(_state.value.breadcrumb)

    private fun loadFolder(crumb: List<FolderNode>) {
        val source = sources.active
        val folderId = crumb.lastOrNull()?.id
        _state.update {
            it.copy(isLoading = true, hasSource = true, activeSourceId = source.id, breadcrumb = crumb, error = null)
        }
        viewModelScope.launch {
            runCatching { source.listChildren(folderId) }
                .onSuccess { listing ->
                    _state.update {
                        it.copy(
                            isLoading = false,
                            folders = listing.folders,
                            files = listing.files,
                            error = if (listing.folders.isEmpty() && listing.files.isEmpty()) "Nothing here." else null,
                        )
                    }
                }
                .onFailure { e ->
                    _state.update { it.copy(isLoading = false, folders = emptyList(), files = emptyList(), error = e.message ?: "Could not load this folder.") }
                }
        }
    }
}
