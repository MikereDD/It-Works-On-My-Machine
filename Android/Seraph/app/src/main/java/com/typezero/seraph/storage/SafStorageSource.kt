package com.typezero.seraph.storage

import android.content.Context
import android.net.Uri
import android.provider.DocumentsContract
import androidx.documentfile.provider.DocumentFile
import com.typezero.seraph.data.model.AudioFile
import com.typezero.seraph.data.tagging.Tagger
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.File

/** Device storage via the Storage Access Framework. */
class SafStorageSource(private val context: Context) : StorageSource {

    override val id = StorageSource.DEVICE
    override val label = "This device"

    @Volatile private var treeUri: Uri? = null

    fun setTree(uri: Uri) { treeUri = uri }

    override suspend fun isReady() = treeUri != null

    override suspend fun listAudio(): List<AudioFile> = withContext(Dispatchers.IO) {
        val root = treeUri?.let { DocumentFile.fromTreeUri(context, it) } ?: return@withContext emptyList()
        val out = ArrayList<AudioFile>()
        walk(root, out)
        out.sortedBy { it.displayName.lowercase() }
    }

    private fun walk(dir: DocumentFile, out: MutableList<AudioFile>) {
        for (child in dir.listFiles()) {
            if (child.isDirectory) {
                walk(child, out)
            } else {
                val name = child.name ?: continue
                if (name.substringAfterLast('.', "").lowercase() in Tagger.SUPPORTED_EXTENSIONS) {
                    out += AudioFile(
                        sourceId = id,
                        id = child.uri.toString(),
                        displayName = name,
                        mimeType = child.type ?: "audio/*",
                        sizeBytes = child.length(),
                        parentId = dir.uri.toString(),
                        parentName = dir.name ?: "(folder)",
                    )
                }
            }
        }
    }

    override suspend fun listChildren(folderId: String?): FolderListing = withContext(Dispatchers.IO) {
        val dir = when {
            folderId != null -> DocumentFile.fromTreeUri(context, Uri.parse(folderId))
            else -> treeUri?.let { DocumentFile.fromTreeUri(context, it) }
        } ?: return@withContext FolderListing(emptyList(), emptyList())

        val folders = ArrayList<FolderNode>()
        val files = ArrayList<AudioFile>()
        for (child in dir.listFiles()) {
            if (child.isDirectory) {
                folders += FolderNode(child.uri.toString(), child.name ?: "(folder)")
            } else {
                val name = child.name ?: continue
                if (name.substringAfterLast('.', "").lowercase() in Tagger.SUPPORTED_EXTENSIONS) {
                    files += AudioFile(
                        sourceId = id,
                        id = child.uri.toString(),
                        displayName = name,
                        mimeType = child.type ?: "audio/*",
                        sizeBytes = child.length(),
                        parentId = dir.uri.toString(),
                        parentName = dir.name ?: "(folder)",
                    )
                }
            }
        }
        FolderListing(
            folders.sortedBy { it.name.lowercase() },
            files.sortedBy { it.displayName.lowercase() },
        )
    }

    override suspend fun readToCache(file: AudioFile): File = withContext(Dispatchers.IO) {
        val uri = Uri.parse(file.id)
        val ext = file.displayName.substringAfterLast('.', "tmp")
        val cache = File(context.cacheDir, "edit_${System.nanoTime()}.$ext")
        context.contentResolver.openInputStream(uri)?.use { input ->
            cache.outputStream().use { input.copyTo(it, DEFAULT_BUFFER_SIZE) }
        } ?: throw IllegalStateException("Could not open ${file.displayName}")
        cache
    }

    override suspend fun writeBack(file: AudioFile, cache: File): Unit = withContext(Dispatchers.IO) {
        val uri = Uri.parse(file.id)
        context.contentResolver.openOutputStream(uri, "wt")?.use { output ->
            cache.inputStream().use { it.copyTo(output, DEFAULT_BUFFER_SIZE) }
        } ?: throw IllegalStateException("Could not write ${file.displayName}")
    }

    override suspend fun rename(file: AudioFile, newName: String): AudioFile = withContext(Dispatchers.IO) {
        val newUri = DocumentsContract.renameDocument(context.contentResolver, Uri.parse(file.id), newName)
            ?: throw IllegalStateException("Rename not supported here")
        file.copy(id = newUri.toString(), displayName = newName)
    }
}
