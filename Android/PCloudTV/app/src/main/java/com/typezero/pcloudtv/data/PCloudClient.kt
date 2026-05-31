package com.typezero.pcloudtv.data

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.FormBody
import okhttp3.HttpUrl.Companion.toHttpUrl
import okhttp3.OkHttpClient
import okhttp3.Request
import org.json.JSONObject
import java.util.concurrent.TimeUnit

/**
 * Minimal pCloud HTTP JSON API client.
 *
 * Docs: https://docs.pcloud.com
 *  - userinfo?getauth=1   -> obtain an auth token from username/password
 *  - listfolder           -> browse folders/files
 *  - getfilelink          -> obtain a direct streaming URL (hosts[] + path)
 *
 * pCloud accounts live in one of two regions and you must hit the matching host:
 *   US -> api.pcloud.com     EU -> eapi.pcloud.com
 * We auto-detect the correct one at login by trying both.
 */
class PCloudClient {

    private val http = OkHttpClient.Builder()
        .connectTimeout(20, TimeUnit.SECONDS)
        .readTimeout(30, TimeUnit.SECONDS)
        .build()

    companion object {
        private val HOSTS = listOf("eapi.pcloud.com", "api.pcloud.com")
    }

    /** Try both regions; return a Session for whichever accepts the credentials. */
    suspend fun login(username: String, password: String): ApiResult<Session> =
        withContext(Dispatchers.IO) {
            var lastError = "Login failed"
            for (host in HOSTS) {
                try {
                    val body = FormBody.Builder()
                        .add("getauth", "1")
                        .add("logout", "1")
                        .add("username", username)
                        .add("password", password)
                        .build()
                    val req = Request.Builder()
                        .url("https://$host/userinfo")
                        .post(body)
                        .build()
                    val json = http.newCall(req).execute().use { resp ->
                        JSONObject(resp.body?.string().orEmpty())
                    }
                    if (json.optInt("result", -1) == 0 && json.has("auth")) {
                        return@withContext ApiResult.Ok(
                            Session(authToken = json.getString("auth"), apiHost = host)
                        )
                    } else {
                        lastError = json.optString("error", "Invalid email or password")
                    }
                } catch (e: Exception) {
                    lastError = e.message ?: "Network error"
                }
            }
            ApiResult.Error(lastError)
        }

    /** List a folder. Pass folderId = 0 for the account root. */
    suspend fun listFolder(session: Session, folderId: Long): ApiResult<List<PItem>> =
        withContext(Dispatchers.IO) {
            try {
                val url = "https://${session.apiHost}/listfolder".toHttpUrl().newBuilder()
                    .addQueryParameter("auth", session.authToken)
                    .addQueryParameter("folderid", folderId.toString())
                    .build()
                val req = Request.Builder().url(url).build()
                val json = http.newCall(req).execute().use { resp ->
                    JSONObject(resp.body?.string().orEmpty())
                }
                if (json.optInt("result", -1) != 0) {
                    return@withContext ApiResult.Error(
                        json.optString("error", "Could not load folder (code ${json.optInt("result")})")
                    )
                }
                val contents = json.getJSONObject("metadata").optJSONArray("contents")
                val items = buildList {
                    if (contents != null) {
                        for (i in 0 until contents.length()) {
                            val o = contents.getJSONObject(i)
                            val isFolder = o.optBoolean("isfolder", false)
                            add(
                                PItem(
                                    name = o.optString("name"),
                                    isFolder = isFolder,
                                    folderId = if (isFolder) o.optLong("folderid") else null,
                                    fileId = if (!isFolder) o.optLong("fileid") else null,
                                    contentType = o.optString("contenttype", ""),
                                    category = o.optInt("category", 0),
                                    size = o.optLong("size", 0L)
                                )
                            )
                        }
                    }
                }
                // Folders first, then files, each alphabetically.
                ApiResult.Ok(
                    items.sortedWith(
                        compareByDescending<PItem> { it.isFolder }
                            .thenBy { it.name.lowercase() }
                    )
                )
            } catch (e: Exception) {
                ApiResult.Error(e.message ?: "Network error")
            }
        }

    /**
     * Resolve a direct, streamable HTTPS URL for a file.
     * The link is bound to the requesting device's IP, so we fetch it
     * immediately before playback on the same device.
     */
    suspend fun getStreamUrl(session: Session, fileId: Long): ApiResult<String> =
        withContext(Dispatchers.IO) {
            try {
                val url = "https://${session.apiHost}/getfilelink".toHttpUrl().newBuilder()
                    .addQueryParameter("auth", session.authToken)
                    .addQueryParameter("fileid", fileId.toString())
                    .addQueryParameter("forcedownload", "0")
                    .build()
                val req = Request.Builder().url(url).build()
                val json = http.newCall(req).execute().use { resp ->
                    JSONObject(resp.body?.string().orEmpty())
                }
                if (json.optInt("result", -1) != 0) {
                    return@withContext ApiResult.Error(
                        json.optString("error", "Could not get file link")
                    )
                }
                val hosts = json.getJSONArray("hosts")
                val path = json.getString("path")
                if (hosts.length() == 0) return@withContext ApiResult.Error("No hosts returned")
                ApiResult.Ok("https://${hosts.getString(0)}$path")
            } catch (e: Exception) {
                ApiResult.Error(e.message ?: "Network error")
            }
        }
}
