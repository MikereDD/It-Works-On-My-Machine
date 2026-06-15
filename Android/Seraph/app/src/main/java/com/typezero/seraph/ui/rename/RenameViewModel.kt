package com.typezero.seraph.ui.rename

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.typezero.seraph.data.model.AudioFile
import com.typezero.seraph.data.rename.FilenameTemplate
import com.typezero.seraph.data.rename.RenamePlan
import com.typezero.seraph.data.rename.RenameService
import com.typezero.seraph.data.rename.RenameSource
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.receiveAsFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

data class RenameUiState(
    val template: String = FilenameTemplate.DEFAULT,
    val isLoading: Boolean = true,
    val plan: RenamePlan? = null,
    val isApplying: Boolean = false,
    val message: String? = null,
) {
    val changeCount: Int get() = plan?.changeCount ?: 0
}

class RenameViewModel(
    private val service: RenameService,
) : ViewModel() {

    private val _state = MutableStateFlow(RenameUiState())
    val state: StateFlow<RenameUiState> = _state.asStateFlow()

    // Signals the host to leave the screen and rescan once renames are applied.
    private val _applied = Channel<Unit>(Channel.BUFFERED)
    val applied = _applied.receiveAsFlow()

    private var sources: List<RenameSource> = emptyList()

    fun start(files: List<AudioFile>) {
        _state.value = RenameUiState(isLoading = true)
        viewModelScope.launch {
            sources = service.gather(files)
            reRender(_state.value.template)
            _state.update { it.copy(isLoading = false) }
        }
    }

    fun onTemplateChange(template: String) {
        _state.update { it.copy(template = template, message = null) }
        reRender(template)
    }

    fun resetTemplate() = onTemplateChange(FilenameTemplate.DEFAULT)

    private fun reRender(template: String) {
        if (sources.isEmpty()) return
        _state.update { it.copy(plan = service.render(sources, template)) }
    }

    fun apply() {
        val plan = _state.value.plan ?: return
        if (plan.changeCount == 0) return
        _state.update { it.copy(isApplying = true, message = null) }
        viewModelScope.launch {
            val result = service.apply(plan)
            if (result.failed == 0) {
                _applied.send(Unit)
            } else {
                _state.update {
                    it.copy(
                        isApplying = false,
                        message = "Renamed ${result.renamed}, ${result.failed} failed " +
                            "(provider may not allow renaming here).",
                    )
                }
            }
        }
    }
}
