package com.typezero.cloudtv.data

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.OkHttpClient
import okhttp3.Request
import org.json.JSONObject

/**
 * OneDrive implementation of [CloudProvider] via Microsoft Graph.
 *
 * Browsing uses `/me/drive/.../children`; playback uses Graph's
 * `@microsoft.graph.downloadUrl`, a short-lived **pre-authenticated** URL — so
 * no proxy is needed (unlike Drive) and it casts to Chromecast fine.
 *
 * Decoupled from the auth wiring: [accessToken] supplies a fresh bearer token
 * (the login slice provides it via AppAuth). NOTE: untested until a real client
 * id + account exist.
 */
class OneDriveProvider(
    private val accessToken: suspend () -> String?,
    private val http: OkHttpClient = OkHttpClient()
) : CloudProvider {

    override val type = CloudProviderType.ONEDRIVE

    override suspend fun listFolder(folderId: String): ApiResult<List<CloudItem>> =
        withContext(Dispatchers.IO) {
            val token = accessToken()
                ?: return@withContext ApiResult.Error("Microsoft sign-in expired — sign in again.")
            val path = if (folderId.isBlank() || folderId == CloudProvider.ROOT)
                "/me/drive/root/children" else "/me/drive/items/$folderId/children"
            val url = "${MicrosoftConfig.GRAPH_BASE}$path" +
                "?\$select=id,name,folder,file,size&\$top=1000"
            try {
                val req = Request.Builder().url(url)
                    .header("Authorization", "Bearer $token").build()
                val json = http.newCall(req).execute().use {
                    JSONObject(it.body?.string().orEmpty())
                }
                if (json.has("error")) {
                    return@withContext ApiResult.Error(
                        json.optJSONObject("error")?.optString("message") ?: "OneDrive error"
                    )
                }
                val arr = json.optJSONArray("value") ?: return@withContext ApiResult.Ok(emptyList())
                val items = buildList {
                    for (i in 0 until arr.length()) add(arr.getJSONObject(i).toCloudItem())
                }
                ApiResult.Ok(items)
            } catch (e: Exception) {
                ApiResult.Error("Couldn't reach OneDrive: ${e.message}")
            }
        }

    override suspend fun streamSource(fileId: String): ApiResult<StreamSource> =
        withContext(Dispatchers.IO) {
            val token = accessToken()
                ?: return@withContext ApiResult.Error("Microsoft sign-in expired — sign in again.")
            // Fetch the item to get a fresh pre-authenticated download URL.
            val url = "${MicrosoftConfig.GRAPH_BASE}/me/drive/items/$fileId" +
                "?\$select=id,@microsoft.graph.downloadUrl"
            try {
                val req = Request.Builder().url(url)
                    .header("Authorization", "Bearer $token").build()
                val json = http.newCall(req).execute().use {
                    JSONObject(it.body?.string().orEmpty())
                }
                val dl = json.optString("@microsoft.graph.downloadUrl")
                if (dl.isNullOrBlank()) ApiResult.Error("No download URL for this file")
                else ApiResult.Ok(StreamSource(dl)) // pre-authenticated; no headers needed
            } catch (e: Exception) {
                ApiResult.Error("Couldn't resolve OneDrive file: ${e.message}")
            }
        }

    // Graph thumbnails need a separate call; skip for now (UI shows the type icon).
    override suspend fun thumbnail(fileId: String, size: String): String? = null

    private fun JSONObject.toCloudItem(): CloudItem {
        val name = optString("name")
        val isFolder = has("folder")
        val mime = optJSONObject("file")?.optString("mimeType").orEmpty()
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
            sizeBytes = if (has("size")) optLong("size") else null
        )
    }
}
