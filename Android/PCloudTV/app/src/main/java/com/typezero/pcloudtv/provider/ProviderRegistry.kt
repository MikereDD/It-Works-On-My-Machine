package com.typezero.pcloudtv.provider

import com.typezero.pcloudtv.data.PCloudClient
import com.typezero.pcloudtv.data.Session

/**
 * Central place for provider availability.
 *
 * v4.50 keeps pCloud enabled and records the next providers as planned so the
 * app can grow into Cloud Player after the foundation is stable.
 */
object ProviderRegistry {
    const val PCLOUD = "pcloud"
    const val MEGA = "mega"
    const val GOOGLE_DRIVE = "google_drive"
    const val DROPBOX = "dropbox"
    const val ONEDRIVE = "onedrive"
    const val WEBDAV = "webdav"
    const val SMB = "smb"

    val plannedProviders = listOf(
        PCLOUD,
        MEGA,
        GOOGLE_DRIVE,
        DROPBOX,
        ONEDRIVE,
        WEBDAV,
        SMB
    )

    fun pCloud(session: Session, client: PCloudClient): CloudProvider =
        PCloudProvider(session, client)
}
