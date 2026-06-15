package com.typezero.seraph.storage

import com.typezero.seraph.data.model.AudioFile
import java.io.File

/**
 * Abstraction over a place files live. The device source is backed by the
 * Storage Access Framework; the pCloud source is backed by the pCloud HTTP API.
 * Tagging and renaming are written against this interface so neither knows or
 * cares which backend is active.
 *
 * Both sources funnel content through a local cache File: jaudiotagger needs a
 * real file to read/write, so [readToCache] hands one back and [writeBack]
 * pushes the edited bytes home (a ContentResolver write for SAF, an upload for
 * pCloud). Renames are handled natively by each backend — a DocumentsContract
 * call for SAF, a single server-side renamefile for pCloud.
 */
interface StorageSource {
    val id: String
    val label: String

    suspend fun isReady(): Boolean
    suspend fun listAudio(): List<AudioFile>

    /**
     * List one folder's immediate children — subfolders and audio files — for
     * directory browsing. A null [folderId] means the source's root: for pCloud
     * that's the configured scan paths shown as top-level folders; for the device
     * it's the picked tree. [FolderNode.id] is opaque and fed back in to descend.
     */
    suspend fun listChildren(folderId: String?): FolderListing

    suspend fun readToCache(file: AudioFile): File
    suspend fun writeBack(file: AudioFile, cache: File)
    suspend fun rename(file: AudioFile, newName: String): AudioFile

    companion object {
        const val DEVICE = "device"
        const val PCLOUD = "pcloud"
    }
}

/** A browsable subfolder. [id] is opaque (pCloud folderid, or a SAF tree-doc uri). */
data class FolderNode(val id: String, val name: String)

/** One folder's immediate contents. */
data class FolderListing(
    val folders: List<FolderNode>,
    val files: List<AudioFile>,
)
