package com.typezero.seraph.di

import android.content.Context
import com.typezero.seraph.data.album.AlbumMatchService
import com.typezero.seraph.data.musicbrainz.MusicBrainzClient
import com.typezero.seraph.data.rename.RenameService
import com.typezero.seraph.data.tagging.TagFileService
import com.typezero.seraph.data.tagging.Tagger
import com.typezero.seraph.pcloud.PCloudClient
import com.typezero.seraph.pcloud.PCloudSession
import com.typezero.seraph.pcloud.PCloudStorageSource
import com.typezero.seraph.storage.SafStorageSource
import com.typezero.seraph.storage.SourceManager

/**
 * Manual dependency container (project convention: no Hilt/Dagger). Built once in
 * [com.typezero.seraph.SeraphApp]; everything is stateless or holds only
 * an app-context reference.
 */
class AppContainer(context: Context) {
    private val appContext = context.applicationContext

    val pcloudSession: PCloudSession by lazy { PCloudSession(appContext) }
    private val pcloudClient: PCloudClient by lazy { PCloudClient(pcloudSession) }

    private val deviceSource: SafStorageSource by lazy { SafStorageSource(appContext) }
    private val pcloudSource: PCloudStorageSource by lazy {
        PCloudStorageSource(appContext, pcloudSession, pcloudClient)
    }

    val sourceManager: SourceManager by lazy { SourceManager(deviceSource, pcloudSource) }

    private val tagger: Tagger by lazy { Tagger() }
    val tagFileService: TagFileService by lazy { TagFileService(sourceManager, tagger) }
    val renameService: RenameService by lazy { RenameService(sourceManager, tagFileService) }
    val musicBrainz: MusicBrainzClient by lazy { MusicBrainzClient() }
    val albumMatchService: AlbumMatchService by lazy {
        AlbumMatchService(musicBrainz, tagFileService, renameService)
    }
}
