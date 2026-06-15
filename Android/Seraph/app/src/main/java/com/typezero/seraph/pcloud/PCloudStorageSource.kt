package com.typezero.seraph.pcloud

import android.content.Context
import com.typezero.seraph.data.model.AudioFile
import com.typezero.seraph.storage.FolderListing
import com.typezero.seraph.storage.StorageSource
import java.io.File

/** pCloud-backed storage source. Rename is server-side; tag edits download + re-upload. */
class PCloudStorageSource(
    context: Context,
    private val session: PCloudSession,
    private val client: PCloudClient,
) : StorageSource {

    private val cacheDir = context.applicationContext.cacheDir

    override val id = StorageSource.PCLOUD
    override val label = "pCloud"

    override suspend fun isReady() = session.isSignedIn

    /** Bind a token captured from the pCloud web login to its region and store it.
     *  Returns null on success, or an error message. */
    suspend fun signInWithToken(token: String): String? {
        val host = client.resolveHost(token)
            ?: return "pCloud didn't accept that sign-in. Please try again."
        session.save(token, host)
        return null
    }

    fun signOut() = session.clear()

    override suspend fun listAudio(): List<AudioFile> =
        client.listAudioFiles(PCloudConfig.SCAN_PATHS)

    override suspend fun listChildren(folderId: String?): FolderListing =
        if (folderId == null) {
            FolderListing(client.listRoots(PCloudConfig.SCAN_PATHS), emptyList())
        } else {
            client.listChildren(folderId)
        }

    override suspend fun readToCache(file: AudioFile): File =
        client.downloadToCache(file.id, file.displayName, cacheDir)

    override suspend fun writeBack(file: AudioFile, cache: File) =
        client.uploadOverwrite(file.parentId, file.displayName, cache)

    override suspend fun rename(file: AudioFile, newName: String): AudioFile {
        client.renameFile(file.id, newName)
        return file.copy(displayName = newName) // fileid is preserved across rename
    }
}
