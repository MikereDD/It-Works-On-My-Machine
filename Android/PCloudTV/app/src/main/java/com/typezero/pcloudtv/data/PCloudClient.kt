package com.typezero.pcloudtv.data

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.FormBody
import okhttp3.HttpUrl.Companion.toHttpUrl
import okhttp3.MediaType.Companion.toMediaTypeOrNull
import okhttp3.MultipartBody
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody
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
    suspend fun login(
        username: String,
        password: String,
        code: String = ""
    ): ApiResult<Session> =
        withContext(Dispatchers.IO) {
            var lastError = "Login failed"
            for (host in HOSTS) {
                try {
                    val body = FormBody.Builder()
                        .add("getauth", "1")
                        .add("logout", "1")
                        .add("username", username)
                        .add("password", password)
                        .apply {
                            // Sent only when the account requires a 2FA / verification
                            // code. pCloud asks for this on 2FA-enabled accounts.
                            if (code.isNotBlank()) {
                                add("code", code.trim())
                                add("trustdevice", "1")
                            }
                        }
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
                        val apiErr = json.optString("error", "Invalid email or password")
                        // Make the 2FA case obvious to the user.
                        lastError = if (apiErr.contains("code", ignoreCase = true)) {
                            "This account has 2FA enabled — enter your authenticator " +
                                "or SMS code in the 2FA field and sign in again."
                        } else {
                            apiErr
                        }
                    }
                } catch (e: Exception) {
                    lastError = e.message ?: "Network error"
                }
            }
            ApiResult.Error(lastError)
        }

    /**
     * Validate a pre-obtained access token (e.g. pulled from a logged-in
     * pCloud web session) by calling userinfo on each region. Returns a
     * Session bound to whichever host accepts it.
     */
    suspend fun loginWithToken(token: String): ApiResult<Session> =
        withContext(Dispatchers.IO) {
            for (host in HOSTS) {
                try {
                    val url = "https://$host/userinfo".toHttpUrl().newBuilder()
                        .addQueryParameter("auth", token)
                        .build()
                    val json = http.newCall(Request.Builder().url(url).build()).execute()
                        .use { JSONObject(it.body?.string().orEmpty()) }
                    if (json.optInt("result", -1) == 0) {
                        return@withContext ApiResult.Ok(Session(token, host))
                    }
                } catch (_: Exception) {
                    // try the other region
                }
            }
            ApiResult.Error(
                "That token wasn't accepted on either pCloud region. " +
                    "Make sure you copied the whole value."
            )
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

    /**
     * Resolve an .m3u / .m3u8 playlist into a playable queue.
     *
     * - If the file is an HLS manifest (contains #EXT-X- tags), it's handed to
     *   the player as a single direct URL (VLC plays HLS natively).
     * - Otherwise each entry is matched: absolute http(s) URLs are used as-is;
     *   bare filenames are matched (by name) against files in the same folder.
     *   Entries that can't be matched in this folder are skipped.
     *
     * @param folderItems the contents of the folder the playlist lives in,
     *        used to resolve relative filename entries.
     */
    suspend fun resolvePlaylist(
        session: Session,
        playlist: PItem,
        folderItems: List<PItem>
    ): ApiResult<List<MediaItem>> = withContext(Dispatchers.IO) {
        val linkRes = getStreamUrl(session, playlist.fileId ?: return@withContext ApiResult.Error("Bad playlist file"))
        val m3uUrl = when (linkRes) {
            is ApiResult.Ok -> linkRes.value
            is ApiResult.Error -> return@withContext ApiResult.Error(linkRes.message)
        }

        val text = try {
            http.newCall(Request.Builder().url(m3uUrl).build()).execute()
                .use { it.body?.string().orEmpty() }
        } catch (e: Exception) {
            return@withContext ApiResult.Error(e.message ?: "Could not read playlist")
        }

        val lines = text.lines()

        // HLS manifest -> let VLC handle the whole thing as one stream.
        if (lines.any { it.trimStart().startsWith("#EXT-X-", ignoreCase = true) }) {
            return@withContext ApiResult.Ok(listOf(MediaItem(playlist.name, null, m3uUrl)))
        }

        val byName = folderItems
            .filter { !it.isFolder && it.fileId != null }
            .associateBy { it.name.lowercase() }

        val out = mutableListOf<MediaItem>()
        var pendingTitle: String? = null
        for (raw in lines) {
            val line = raw.trim()
            if (line.isEmpty()) continue
            if (line.startsWith("#")) {
                if (line.startsWith("#EXTINF", ignoreCase = true)) {
                    pendingTitle = line.substringAfter(",", "").trim().ifBlank { null }
                }
                continue
            }
            if (line.startsWith("http://", true) || line.startsWith("https://", true)) {
                out += MediaItem(
                    pendingTitle ?: line.substringAfterLast('/').ifBlank { line },
                    null, line
                )
            } else {
                val base = line.replace('\\', '/').substringAfterLast('/').lowercase()
                val match = byName[base]
                if (match?.fileId != null) {
                    out += MediaItem(pendingTitle ?: match.name, match.fileId, null)
                }
            }
            pendingTitle = null
        }

        if (out.isEmpty()) {
            ApiResult.Error("No playable entries in this playlist were found in this folder.")
        } else {
            ApiResult.Ok(out)
        }
    }

    /**
     * Generate a simple .m3u from the given files and upload it into [folderId].
     * Entries are bare filenames (resolved against the same folder on playback),
     * so the generated playlist always matches what's actually there.
     */
    suspend fun savePlaylist(
        session: Session,
        folderId: Long,
        fileName: String,
        files: List<PItem>
    ): ApiResult<Unit> = withContext(Dispatchers.IO) {
        try {
            val content = buildString {
                append("#EXTM3U\n")
                for (f in files) {
                    val title = f.name.substringBeforeLast('.', f.name)
                    append("#EXTINF:-1,").append(title).append('\n')
                    append(f.name).append('\n')
                }
            }
            val url = "https://${session.apiHost}/uploadfile".toHttpUrl().newBuilder()
                .addQueryParameter("auth", session.authToken)
                .addQueryParameter("folderid", folderId.toString())
                .addQueryParameter("nopartial", "1")
                .build()
            val part = RequestBody.create(
                "audio/x-mpegurl".toMediaTypeOrNull(), content
            )
            val body = MultipartBody.Builder()
                .setType(MultipartBody.FORM)
                .addFormDataPart("file", fileName, part)
                .build()
            val req = Request.Builder().url(url).post(body).build()
            val json = http.newCall(req).execute().use { resp ->
                JSONObject(resp.body?.string().orEmpty())
            }
            if (json.optInt("result", -1) == 0) {
                ApiResult.Ok(Unit)
            } else {
                ApiResult.Error(
                    json.optString("error", "Upload failed (code ${json.optInt("result")})")
                )
            }
        } catch (e: Exception) {
            ApiResult.Error(e.message ?: "Network error")
        }
    }
}
