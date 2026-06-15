package com.typezero.seraph.di

import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import com.typezero.seraph.ui.album.AlbumMatchViewModel
import com.typezero.seraph.ui.editor.TagEditorViewModel
import com.typezero.seraph.ui.library.LibraryViewModel
import com.typezero.seraph.ui.rename.RenameViewModel

/** Bridges the manual [AppContainer] into Compose's viewModel() lookup. */
class ViewModelFactory(private val container: AppContainer) : ViewModelProvider.Factory {
    @Suppress("UNCHECKED_CAST")
    override fun <T : ViewModel> create(modelClass: Class<T>): T = when {
        modelClass.isAssignableFrom(LibraryViewModel::class.java) ->
            LibraryViewModel(container.sourceManager) as T
        modelClass.isAssignableFrom(TagEditorViewModel::class.java) ->
            TagEditorViewModel(container.tagFileService, container.musicBrainz) as T
        modelClass.isAssignableFrom(RenameViewModel::class.java) ->
            RenameViewModel(container.renameService) as T
        modelClass.isAssignableFrom(AlbumMatchViewModel::class.java) ->
            AlbumMatchViewModel(container.albumMatchService, container.musicBrainz) as T
        else -> throw IllegalArgumentException("Unknown ViewModel: ${modelClass.name}")
    }
}
