package com.typezero.siphon.ui

import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import com.typezero.siphon.di.AppContainer
import com.typezero.siphon.data.model.*
import com.typezero.siphon.engine.OutputResolver
import com.typezero.siphon.engine.YtdlpEngine
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import java.util.UUID

enum class Tab { LOCAL, LINK }

data class SiphonUiState(
    val tab: Tab = Tab.LOCAL,
    val hasMediaPermission: Boolean = false,
    val videosLoading: Boolean = false,
    val allVideos: List<VideoItem> = emptyList(),
    val searchQuery: String = "",
    val linkUrl: String = "",
    val linkClient: YouTubeClient = YouTubeClient.DEFAULT,
    // options sheet
    val sheetOpen: Boolean = false,
    val pendingSource: ExtractRequest.Source? = null,
    val format: AudioFormat = AudioFormat.COPY,
    val quality: AudioQuality = AudioQuality.lossyDefault,
    val tags: Tags = Tags(),
    val outputName: String = "",
    // jobs
    val activeJob: JobState? = null,
    val history: List<JobState> = emptyList(),
    val extractorUpdating: Boolean = false,
    val snackbar: String? = null
) {
    val visibleVideos: List<VideoItem>
        get() = if (searchQuery.isBlank()) allVideos
        else allVideos.filter { it.displayName.contains(searchQuery.trim(), ignoreCase = true) }
}

class SiphonViewModel(private val container: AppContainer) : ViewModel() {

    private val _state = MutableStateFlow(SiphonUiState())
    val state: StateFlow<SiphonUiState> = _state.asStateFlow()

    private var currentProcessId: String? = null

    // ---- navigation / input ----
    fun selectTab(tab: Tab) = _state.update { it.copy(tab = tab) }
    fun setSearch(q: String) = _state.update { it.copy(searchQuery = q) }
    fun setLinkUrl(url: String) = _state.update { it.copy(linkUrl = url) }
    fun setLinkClient(client: YouTubeClient) = _state.update { it.copy(linkClient = client) }

    fun onPermissionResult(granted: Boolean) {
        _state.update { it.copy(hasMediaPermission = granted) }
        if (granted) loadVideos()
    }

    fun updateExtractor(nightly: Boolean) {
        if (_state.value.extractorUpdating) return
        _state.update { it.copy(extractorUpdating = true) }
        viewModelScope.launch {
            val msg = try {
                container.engine.updateBinary(nightly)
            } catch (e: Exception) {
                e.message ?: "Update failed"
            }
            _state.update { it.copy(extractorUpdating = false, snackbar = msg) }
        }
    }

    fun consumeSnackbar() = _state.update { it.copy(snackbar = null) }

    fun loadVideos() {
        _state.update { it.copy(videosLoading = true) }
        viewModelScope.launch {
            val vids = runCatching { container.videoRepository.loadVideos() }.getOrDefault(emptyList())
            _state.update { it.copy(allVideos = vids, videosLoading = false) }
        }
    }

    // ---- opening the options sheet ----
    fun openSheetForVideo(video: VideoItem) {
        _state.update {
            it.copy(
                sheetOpen = true,
                pendingSource = ExtractRequest.Source.LocalFile(
                    path = video.filePath,
                    uri = video.uri.toString(),
                    displayName = video.displayName,
                    durationMs = video.durationMs
                ),
                outputName = video.displayName.substringBeforeLast('.'),
                tags = it.tags.copy(embedThumbnail = false)
            )
        }
    }

    fun openSheetForLink() {
        val url = _state.value.linkUrl.trim()
        if (url.isBlank()) return
        _state.update {
            it.copy(
                sheetOpen = true,
                pendingSource = ExtractRequest.Source.Link(url),
                outputName = "",
                tags = it.tags.copy(embedThumbnail = true)
            )
        }
    }

    fun closeSheet() = _state.update { it.copy(sheetOpen = false, pendingSource = null) }

    // ---- option setters ----
    fun setFormat(f: AudioFormat) = _state.update { it.copy(format = f) }
    fun setQuality(q: AudioQuality) = _state.update { it.copy(quality = q) }
    fun setOutputName(n: String) = _state.update { it.copy(outputName = n) }
    fun updateTags(transform: (Tags) -> Tags) = _state.update { it.copy(tags = transform(it.tags)) }

    // ---- run ----
    fun startExtraction() {
        val s = _state.value
        val source = s.pendingSource ?: return
        val extractorClient = (source as? ExtractRequest.Source.Link)?.let { s.linkClient.value }
        val request = ExtractRequest(source, s.format, s.quality, s.tags, s.outputName, extractorClient)
        val id = UUID.randomUUID().toString()
        currentProcessId = id
        val title = when (source) {
            is ExtractRequest.Source.LocalFile -> source.displayName
            is ExtractRequest.Source.Link -> s.outputName.ifBlank { source.url }
        }
        _state.update {
            it.copy(
                sheetOpen = false,
                activeJob = JobState(id, title, JobState.Status.RUNNING, progress = -1f)
            )
        }
        viewModelScope.launch {
            try {
                val onProgress: (Float, String) -> Unit = { progress, line ->
                    _state.update { st ->
                        st.activeJob?.takeIf { it.id == id }?.let { job ->
                            st.copy(activeJob = job.copy(progress = progress, line = line))
                        } ?: st
                    }
                }
                val result = when (source) {
                    is ExtractRequest.Source.LocalFile -> container.localExtractor.extract(
                        request, source, container.outputResolver, id, onProgress
                    )
                    is ExtractRequest.Source.Link -> container.engine.extract(
                        request, container.outputResolver, id, onProgress
                    )
                }
                val mime = OutputResolver.mimeFor(result.extension)
                val exported = container.outputResolver.exportToMusic(result.outputFile, mime)
                finishDone(id, title, exported ?: result.outputFile.absolutePath)
            } catch (e: YtdlpEngine.EngineException) {
                pushFailedJob(id, title, e.message ?: "Extraction failed")
            } catch (e: Exception) {
                pushFailedJob(id, title, e.message ?: "Unexpected error")
            } finally {
                currentProcessId = null
            }
        }
    }

    fun cancelActive() {
        val id = currentProcessId ?: return
        viewModelScope.launch {
            container.engine.cancel(id)
            container.localExtractor.cancel(id)
        }
        _state.update { st ->
            val job = st.activeJob?.copy(status = JobState.Status.CANCELLED)
            st.copy(activeJob = null, history = listOfNotNull(job) + st.history)
        }
    }

    private fun finishDone(id: String, title: String, location: String) {
        val done = JobState(id, title, JobState.Status.DONE, progress = 1f, outputPath = location)
        _state.update { it.copy(activeJob = null, history = listOf(done) + it.history) }
    }

    private fun pushFailedJob(id: String, title: String, error: String) {
        val failed = JobState(id, title, JobState.Status.FAILED, error = error)
        _state.update { it.copy(activeJob = null, history = listOf(failed) + it.history) }
    }

    private fun pushFailed(title: String, error: String) {
        val failed = JobState(UUID.randomUUID().toString(), title, JobState.Status.FAILED, error = error)
        _state.update { it.copy(history = listOf(failed) + it.history) }
    }

    class Factory(private val container: AppContainer) : ViewModelProvider.Factory {
        @Suppress("UNCHECKED_CAST")
        override fun <T : ViewModel> create(modelClass: Class<T>): T =
            SiphonViewModel(container) as T
    }
}
