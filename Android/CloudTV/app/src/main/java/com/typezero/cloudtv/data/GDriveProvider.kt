package com.typezero.cloudtv.data

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.HttpUrl.Companion.toHttpUrl
import okhttp3.OkHttpClient
import okhttp3.Request
import org.json.JSONObject

/**
 * Google Drive implementation of [CloudProvider].
 *
 * Browsing uses the Drive v3 `files.list` API; playback returns a loopback
 * proxy URL (see [DriveStreamProxy]) because Drive's media endpoint needs an
 * Authorization header LibVLC can't send. Bound to one signed-in account via
 * its stored AuthState ([authStateJson]).
 *
 * NOTE: untested until a real client id + account are available.
 */
class GDriveProvider(
    private val auth: GoogleAuth,
    private val authStateJson: String,
    private val proxy: DriveStreamProxy,
    private val http: OkHttpClient = OkHttpClient()
) : CloudProvider {

    override val type = CloudProviderType.GDRIVE

    private val folderMime = "application/vnd.google-apps.folder"

    override suspend fun listFolder(folderId: String): ApiResult<List<CloudItem>> =
        withContext(Dispatchers.IO) {
            val token = auth.freshToken(authStateJson)
                ?: return@withContext ApiResult.Error("Google sign-in expired — sign in again.")
            val parent = if (folderId.isBlank() || folderId == CloudProvider.ROOT) "root" else folderId
            val url = "https://www.googleapis.com/drive/v3/files".toHttpUrl().newBuilder()
                .addQueryParameter("q", "'$parent' in parents and trashed = false")
                .addQueryParameter("fields", "files(id,name,mimeType,size)")
                .addQueryParameter("orderBy", "folder,name")
                .addQueryParameter("pageSize", "1000")
                .addQueryParameter("supportsAllDrives", "true")
                .addQueryParameter("includeItemsFromAllDrives", "true")
                .build()
            try {
                val req = Request.Builder().url(url)
                    .header("Authorization", "Bearer $token").build()
                val json = http.newCall(req).execute().use {
                    JSONObject(it.body?.string().orEmpty())
                }
                if (json.has("error")) {
                    return@withContext ApiResult.Error(
                        json.optJSONObject("error")?.optString("message") ?: "Drive error"
                    )
                }
                val files = json.optJSONArray("files") ?: return@withContext ApiResult.Ok(emptyList())
                val items = buildList {
                    for (i in 0 until files.length()) {
                        val o = files.getJSONObject(i)
                        add(o.toCloudItem())
                    }
                }
                ApiResult.Ok(items)
            } catch (e: Exception) {
                ApiResult.Error("Couldn't reach Google Drive: ${e.message}")
            }
        }

    override suspend fun streamSource(fileId: String): ApiResult<StreamSource> =
        withContext(Dispatchers.IO) {
            val token = auth.freshToken(authStateJson)
                ?: return@withContext ApiResult.Error("Google sign-in expired — sign in again.")
            ApiResult.Ok(StreamSource(proxy.urlFor(fileId, token)))
        }

    // Drive thumbnails also require auth; skip for now and let the UI show the
    // type icon. (Could be proxied later the same way as the stream.)
    override suspend fun thumbnail(fileId: String, size: String): String? = null

    private fun JSONObject.toCloudItem(): CloudItem {
        val mime = optString("mimeType")
        val name = optString("name")
        val isFolder = mime == folderMime
        val kind = when {
            isFolder -> MediaKind.FOLDER
            name.endsWith(".m3u", true) || name.endsWith(".m3u8", true) -> MediaKind.PLAYLIST
            mime.startsWith("video/") -> MediaKind.VIDEO
            mime.startsWith("audio/") -> MediaKind.AUDIO
            mime.startsWith("image/") -> MediaKind.IMAGE
            else -> MediaKind.OTHER
        }
        return CloudItem(
            id = optString("id"),
            name = name,
            isFolder = isFolder,
            kind = kind,
            sizeBytes = optString("size").toLongOrNull()
        )
    }
}
