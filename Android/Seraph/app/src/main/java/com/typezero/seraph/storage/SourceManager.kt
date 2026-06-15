package com.typezero.seraph.storage

import com.typezero.seraph.data.model.AudioFile
import com.typezero.seraph.pcloud.PCloudStorageSource
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/**
 * Holds the available storage sources and which one is active. UI flips the
 * active source; tagging/rename resolve the right source for a given file by its
 * [AudioFile.sourceId] so a file always goes home to where it came from.
 */
class SourceManager(
    val device: SafStorageSource,
    val pcloud: PCloudStorageSource,
) {
    private val byId = mapOf(device.id to device, pcloud.id to pcloud)

    private val _activeId = MutableStateFlow(StorageSource.DEVICE)
    val activeId: StateFlow<String> = _activeId.asStateFlow()

    val active: StorageSource get() = byId.getValue(_activeId.value)

    fun setActive(id: String) {
        if (id in byId) _activeId.value = id
    }

    fun forFile(file: AudioFile): StorageSource = byId[file.sourceId] ?: active
}
