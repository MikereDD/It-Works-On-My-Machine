package com.typezero.seraph.ui.album

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.typezero.seraph.data.album.AlbumMatchService
import com.typezero.seraph.data.album.AlbumPlanRow
import com.typezero.seraph.data.model.AudioFile
import com.typezero.seraph.data.model.ReleaseCandidate
import com.typezero.seraph.data.model.ReleaseDetail
import com.typezero.seraph.data.musicbrainz.MusicBrainzClient
import com.typezero.seraph.data.rename.FilenameTemplate
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.receiveAsFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

enum class AlbumStage { Searching, Pick, Review, Applying }

data class AlbumUiState(
    val folderName: String = "",
    val query: String = "",
    val stage: AlbumStage = AlbumStage.Searching,
    val candidates: List<ReleaseCandidate> = emptyList(),
    val release: ReleaseDetail? = null,
    val rows: List<AlbumPlanRow> = emptyList(),
    val rename: Boolean = true,
    val embedArt: Boolean = true,
    val busy: Boolean = false,
    val message: String? = null,
)

class AlbumMatchViewModel(
    private val service: AlbumMatchService,
    private val mb: MusicBrainzClient,
) : ViewModel() {

    private val _state = MutableStateFlow(AlbumUiState())
    val state: StateFlow<AlbumUiState> = _state.asStateFlow()

    // Signals the host to leave the screen and rescan once changes land.
    private val _applied = Channel<Unit>(Channel.BUFFERED)
    val applied = _applied.receiveAsFlow()

    private var files: List<AudioFile> = emptyList()
    private val template = FilenameTemplate.DEFAULT

    fun start(folderName: String, folderFiles: List<AudioFile>) {
        files = folderFiles
        _state.value = AlbumUiState(folderName = folderName, query = folderName, busy = true)
        search(folderName)
    }

    fun onQueryChange(q: String) = _state.update { it.copy(query = q) }

    fun search(q: String = _state.value.query) {
        _state.update { it.copy(stage = AlbumStage.Searching, busy = true, message = null) }
        viewModelScope.launch {
            val results = runCatching { mb.searchReleases(q) }.getOrDefault(emptyList())
            _state.update {
                it.copy(
                    stage = AlbumStage.Pick,
                    busy = false,
                    candidates = results,
                    message = if (results.isEmpty()) "No releases found — try a different search." else null,
                )
            }
        }
    }

    fun pick(candidate: ReleaseCandidate) {
        _state.update { it.copy(busy = true, message = null) }
        viewModelScope.launch {
            val release = runCatching { mb.getRelease(candidate.mbid) }.getOrNull()
            if (release == null) {
                _state.update { it.copy(busy = false, message = "Couldn't load that release — try another.") }
                return@launch
            }
            val planResult = runCatching { service.plan(files, release, template) }
            val rows = planResult.getOrDefault(emptyList())
            val err = planResult.exceptionOrNull()
            _state.update {
                it.copy(
                    stage = AlbumStage.Review,
                    busy = false,
                    release = release,
                    rows = rows,
                    message = when {
                        err != null -> "Match error: ${err.javaClass.simpleName}: ${err.message}"
                        rows.isEmpty() -> "No tracks matched (${files.size} files, ${release.total} tracks)."
                        else -> null
                    },
                )
            }
        }
    }

    fun backToPick() = _state.update {
        it.copy(stage = AlbumStage.Pick, release = null, rows = emptyList(), message = null)
    }

    fun toggleRename() = _state.update { it.copy(rename = !it.rename) }
    fun toggleArt() = _state.update { it.copy(embedArt = !it.embedArt) }

    fun apply() {
        val st = _state.value
        val release = st.release ?: return
        if (st.rows.isEmpty()) return
        _state.update { it.copy(stage = AlbumStage.Applying, busy = true, message = null) }
        viewModelScope.launch {
            val res = runCatching {
                service.apply(st.rows, release, st.folderName, st.rename, st.embedArt)
            }.getOrElse { com.typezero.seraph.data.album.AlbumApplyResult(0, 0, st.rows.size) }
            if (res.failed == 0) {
                _applied.send(Unit)
            } else {
                _state.update {
                    it.copy(
                        stage = AlbumStage.Review,
                        busy = false,
                        message = "Tagged ${res.tagged}, renamed ${res.renamed}, ${res.failed} failed.",
                    )
                }
            }
        }
    }
}
