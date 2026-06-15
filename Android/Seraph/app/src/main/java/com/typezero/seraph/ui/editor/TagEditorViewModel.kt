package com.typezero.seraph.ui.editor

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.typezero.seraph.data.model.AudioFile
import com.typezero.seraph.data.model.MusicBrainzResult
import com.typezero.seraph.data.model.Tags
import com.typezero.seraph.data.musicbrainz.MusicBrainzClient
import com.typezero.seraph.data.tagging.TagFileService
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.receiveAsFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

data class EditorUiState(
    val isLoading: Boolean = true,
    val fileName: String = "",
    val tags: Tags = Tags(),
    val original: Tags = Tags(),
    val candidates: List<MusicBrainzResult> = emptyList(),
    val isSearching: Boolean = false,
    val isSaving: Boolean = false,
    val message: String? = null,
) {
    val dirty: Boolean get() = tags != original
}

/**
 * Owns the edit session for one file. Lookup populates candidate suggestions
 * from MusicBrainz; applying one fills the fields (and pulls cover art) but the
 * user keeps full manual control of every field before saving.
 */
class TagEditorViewModel(
    private val tagging: TagFileService,
    private val musicBrainz: MusicBrainzClient,
) : ViewModel() {

    private val _state = MutableStateFlow(EditorUiState())
    val state: StateFlow<EditorUiState> = _state.asStateFlow()

    // One-shot signal: a successful save should pop the editor back to the library.
    private val _saved = Channel<Unit>(Channel.BUFFERED)
    val saved = _saved.receiveAsFlow()

    private var current: AudioFile? = null

    fun load(file: AudioFile) {
        current = file
        _state.value = EditorUiState(isLoading = true, fileName = file.displayName)
        viewModelScope.launch {
            runCatching { tagging.read(file) }
                .onSuccess { tags ->
                    _state.update { it.copy(isLoading = false, tags = tags, original = tags) }
                }
                .onFailure { e ->
                    _state.update { it.copy(isLoading = false, message = "Could not read tags: ${e.message}") }
                }
        }
    }

    fun edit(transform: (Tags) -> Tags) {
        _state.update { it.copy(tags = transform(it.tags), message = null) }
    }

    fun lookup() {
        val t = _state.value.tags
        _state.update { it.copy(isSearching = true, candidates = emptyList(), message = null) }
        viewModelScope.launch {
            val results = runCatching {
                musicBrainz.searchRecordings(
                    title = t.title.ifBlank { fileNameAsTitle() },
                    artist = t.artist,
                    album = t.album,
                )
            }.getOrElse { emptyList() }
            _state.update {
                it.copy(
                    isSearching = false,
                    candidates = results,
                    message = if (results.isEmpty()) "No MusicBrainz matches found." else null,
                )
            }
        }
    }

    fun applyCandidate(c: MusicBrainzResult, fetchArtwork: Boolean = true) {
        edit { current ->
            current.copy(
                title = c.title.ifBlank { current.title },
                artist = c.artist.ifBlank { current.artist },
                album = c.album.ifBlank { current.album },
                albumArtist = c.artist.ifBlank { current.albumArtist },
                trackNumber = c.trackNumber ?: current.trackNumber,
                trackTotal = c.trackTotal ?: current.trackTotal,
                year = c.year.ifBlank { current.year },
            )
        }
        if (fetchArtwork && c.releaseMbid != null) {
            viewModelScope.launch {
                val art = runCatching { musicBrainz.frontCover(c.releaseMbid) }.getOrNull()
                if (art != null) edit { it.copy(artwork = art) }
            }
        }
    }

    fun save() {
        val file = current ?: return
        _state.update { it.copy(isSaving = true, message = null) }
        viewModelScope.launch {
            runCatching { tagging.write(file, _state.value.tags) }
                .onSuccess {
                    _state.update { it.copy(isSaving = false, original = it.tags, message = "Saved.") }
                    _saved.send(Unit)
                }
                .onFailure { e ->
                    _state.update { it.copy(isSaving = false, message = "Save failed: ${e.message}") }
                }
        }
    }

    private fun fileNameAsTitle(): String =
        _state.value.fileName.substringBeforeLast('.').replace('_', ' ').trim()
}
