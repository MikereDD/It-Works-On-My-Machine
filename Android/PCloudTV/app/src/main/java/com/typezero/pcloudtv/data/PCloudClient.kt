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
import java.net.URLDecoder
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
                        val email = if (json.has("email")) json.optString("email", null) else null
                        return@withContext ApiResult.Ok(Session(token, host, email))
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

    /** List a folder addressed by a pCloud path such as "/Books/Audiobooks". */
    suspend fun listFolderByPath(session: Session, path: String): ApiResult<List<PItem>> =
        withContext(Dispatchers.IO) {
            try {
                val clean = ("/" + path.trim().trim('/')).ifBlank { "/" }
                val url = "https://${session.apiHost}/listfolder".toHttpUrl().newBuilder()
                    .addQueryParameter("auth", session.authToken)
                    .addQueryParameter("path", clean)
                    .build()
                val req = Request.Builder().url(url).build()
                val json = http.newCall(req).execute().use { resp ->
                    JSONObject(resp.body?.string().orEmpty())
                }
                if (json.optInt("result", -1) != 0) {
                    return@withContext ApiResult.Error(
                        json.optString("error", "Could not load \"$clean\" (code ${json.optInt("result")})")
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
     * Recursively search a folder and everything beneath it for items whose
     * name contains [query] (case-insensitive). One `listfolder?recursive=1`
     * call walks the whole subtree; each hit carries the folder chain from
     * [folderId] (exclusive) down to its parent so the browser can navigate to
     * it with a correct breadcrumb. Matching folders and playable files are
     * returned; other file types are ignored.
     */
    suspend fun searchFolder(
        session: Session,
        folderId: Long,
        query: String
    ): ApiResult<List<SearchHit>> =
        withContext(Dispatchers.IO) {
            try {
                val q = query.trim()
                if (q.isBlank()) return@withContext ApiResult.Ok(emptyList())
                val url = "https://${session.apiHost}/listfolder".toHttpUrl().newBuilder()
                    .addQueryParameter("auth", session.authToken)
                    .addQueryParameter("folderid", folderId.toString())
                    .addQueryParameter("recursive", "1")
                    .build()
                val json = http.newCall(Request.Builder().url(url).build()).execute()
                    .use { JSONObject(it.body?.string().orEmpty()) }
                if (json.optInt("result", -1) != 0) {
                    return@withContext ApiResult.Error(
                        json.optString("error", "Search failed (code ${json.optInt("result")})")
                    )
                }

                val hits = mutableListOf<SearchHit>()

                fun parseItem(o: JSONObject): PItem {
                    val isFolder = o.optBoolean("isfolder", false)
                    return PItem(
                        name = o.optString("name"),
                        isFolder = isFolder,
                        folderId = if (isFolder) o.optLong("folderid") else null,
                        fileId = if (!isFolder) o.optLong("fileid") else null,
                        contentType = o.optString("contenttype", ""),
                        category = o.optInt("category", 0),
                        size = o.optLong("size", 0L)
                    )
                }

                // [ancestors] is the chain from the search root (exclusive) to the
                // folder whose contents we're currently scanning (inclusive).
                fun walk(meta: JSONObject, ancestors: List<Pair<Long, String>>) {
                    val contents = meta.optJSONArray("contents") ?: return
                    for (i in 0 until contents.length()) {
                        val o = contents.getJSONObject(i)
                        val item = parseItem(o)
                        if (item.name.contains(q, ignoreCase = true) &&
                            (item.isFolder || item.isPlayable || item.isViewableDoc)
                        ) {
                            hits.add(
                                SearchHit(
                                    item = item,
                                    parentLabel = ancestors.joinToString(" / ") { it.second },
                                    ancestors = ancestors
                                )
                            )
                        }
                        if (item.isFolder && item.folderId != null) {
                            walk(o, ancestors + (item.folderId to item.name))
                        }
                    }
                }

                walk(json.getJSONObject("metadata"), emptyList())
                ApiResult.Ok(
                    hits.sortedWith(
                        compareByDescending<SearchHit> { it.item.isFolder }
                            .thenBy { it.item.name.lowercase() }
                    )
                )
            } catch (e: Exception) {
                ApiResult.Error(e.message ?: "Network error")
            }
        }

    /**
     * Download a small text/HTML document's raw bytes (for the .nfo / .htm
     * viewer). Resolves a streamable link via getfilelink, then GETs it.
     */
    suspend fun fetchDocument(session: Session, fileId: Long): ApiResult<ByteArray> =
        withContext(Dispatchers.IO) {
            try {
                when (val link = getStreamUrl(session, fileId)) {
                    is ApiResult.Error -> ApiResult.Error(link.message)
                    is ApiResult.Ok -> {
                        val req = Request.Builder().url(link.value).build()
                        http.newCall(req).execute().use { resp ->
                            if (!resp.isSuccessful) {
                                ApiResult.Error("Could not load file (HTTP ${resp.code})")
                            } else {
                                ApiResult.Ok(resp.body?.bytes() ?: ByteArray(0))
                            }
                        }
                    }
                }
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
     * Fetch embedded cover art (ID3v2 APIC) for a track by reading just the tag at
     * the front of a resolved stream [url]. Returns raw image bytes, or null if the
     * file has no embedded art / isn't an MP3. Reliable for network streams where
     * LibVLC doesn't surface the art.
     */
    suspend fun fetchEmbeddedArt(url: String): ByteArray? = Id3Art.fetch(http, url)

    /** Stream URL by absolute pCloud path (used by cross-folder playlists). */
    suspend fun getStreamUrlByPath(session: Session, filePath: String): ApiResult<String> =
        withContext(Dispatchers.IO) {
            try {
                val url = "https://${session.apiHost}/getfilelink".toHttpUrl().newBuilder()
                    .addQueryParameter("auth", session.authToken)
                    .addQueryParameter("path", filePath)
                    .addQueryParameter("forcedownload", "0")
                    .build()
                val json = http.newCall(Request.Builder().url(url).build()).execute()
                    .use { JSONObject(it.body?.string().orEmpty()) }
                if (json.optInt("result", -1) != 0) {
                    return@withContext ApiResult.Error(
                        json.optString("error", "Couldn't open \"$filePath\"")
                    )
                }
                val hosts = json.getJSONArray("hosts")
                val p = json.getString("path")
                if (hosts.length() == 0) return@withContext ApiResult.Error("No hosts returned")
                ApiResult.Ok("https://${hosts.getString(0)}$p")
            } catch (e: Exception) {
                ApiResult.Error(e.message ?: "Network error")
            }
        }

    /**
     * A time-limited link to a thumbnail for a file (images and videos only —
     * pCloud generates these server-side). Used to show poster thumbnails in
     * the browser. Returns Error for anything without a thumbnail.
     */
    suspend fun getThumbLink(
        session: Session,
        fileId: Long,
        size: String = "128x128"
    ): ApiResult<String> = withContext(Dispatchers.IO) {
        try {
            val url = "https://${session.apiHost}/getthumblink".toHttpUrl().newBuilder()
                .addQueryParameter("auth", session.authToken)
                .addQueryParameter("fileid", fileId.toString())
                .addQueryParameter("size", size)
                .addQueryParameter("crop", "1")
                .build()
            val json = http.newCall(Request.Builder().url(url).build()).execute()
                .use { JSONObject(it.body?.string().orEmpty()) }
            if (json.optInt("result", -1) != 0) {
                return@withContext ApiResult.Error(json.optString("error", "No thumbnail"))
            }
            val hosts = json.getJSONArray("hosts")
            val path = json.getString("path")
            if (hosts.length() == 0) return@withContext ApiResult.Error("No thumbnail host")
            ApiResult.Ok("https://${hosts.getString(0)}$path")
        } catch (e: Exception) {
            ApiResult.Error(e.message ?: "Thumbnail error")
        }
    }

    /**
     * Resolve an .m3u / .m3u8 playlist into a playable queue.
     *
     * - HLS manifests (#EXT-X-) are handed to VLC as one direct stream.
     * - pCloud playlists generated by the app prefer #PCLOUDID entries, so
     *   playback survives renames and cross-folder moves.
     * - Normal M3U entries are normalized before matching: BOMs, quotes,
     *   file:// prefixes, Windows slashes, URL-encoded spaces, and query
     *   strings are cleaned up.
     * - Absolute http(s) URLs and absolute pCloud paths are preserved.
     * - Relative paths fall back to basename matching against the playlist's
     *   containing folder, so "Album/01 Song.mp3" still matches "01 Song.mp3".
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

        fun decodeLoose(value: String): String = runCatching {
            URLDecoder.decode(value, Charsets.UTF_8.name())
        }.getOrDefault(value)

        fun cleanEntry(raw: String): String {
            var line = raw.trim().trim('\uFEFF').trim()
            if (line.length >= 2 &&
                ((line.first() == '"' && line.last() == '"') ||
                    (line.first() == '\'' && line.last() == '\''))) {
                line = line.substring(1, line.length - 1).trim()
            }
            if (line.startsWith("file://", ignoreCase = true)) {
                line = line.removePrefix("file://").removePrefix("FILE://")
            }
            line = line.replace('\\', '/')
            if (!line.startsWith("http://", true) && !line.startsWith("https://", true)) {
                line = decodeLoose(line).substringBefore('?').substringBefore('#').trim()
            }
            return line
        }

        fun matchKeys(name: String): List<String> {
            val clean = cleanEntry(name)
            val base = clean.substringAfterLast('/')
            return listOf(clean, base, decodeLoose(clean), decodeLoose(base))
                .map { it.trim().lowercase() }
                .filter { it.isNotEmpty() }
                .distinct()
        }

        val byName = mutableMapOf<String, PItem>()
        folderItems.filter { !it.isFolder && it.fileId != null }.forEach { item ->
            matchKeys(item.name).forEach { key -> byName.putIfAbsent(key, item) }
        }

        val out = mutableListOf<MediaItem>()
        val seen = mutableSetOf<String>()
        var pendingTitle: String? = null
        var pendingId: Long? = null
        var skipped = 0

        fun addItem(item: MediaItem) {
            val key = item.fileId?.let { "id:$it" } ?: item.path?.let { "path:$it" } ?: "url:${item.directUrl}"
            if (seen.add(key)) out += item
        }

        for (raw in lines) {
            val line = cleanEntry(raw)
            if (line.isEmpty()) continue
            if (line.startsWith("#")) {
                if (line.startsWith("#EXTINF", ignoreCase = true)) {
                    pendingTitle = line.substringAfter(",", "").trim().ifBlank { null }
                } else if (line.startsWith("#PCLOUDID:", ignoreCase = true)) {
                    pendingId = line.substringAfter(":").trim().toLongOrNull()
                }
                continue
            }

            if (pendingId != null) {
                // Embedded pCloud fileid — the reliable path, immune to renames/moves.
                addItem(MediaItem(pendingTitle ?: line.substringAfterLast('/'), pendingId, null))
            } else if (line.startsWith("http://", true) || line.startsWith("https://", true)) {
                addItem(
                    MediaItem(
                        pendingTitle ?: line.substringBefore('?').substringAfterLast('/').ifBlank { line },
                        null, line
                    )
                )
            } else if (line.startsWith("/")) {
                // Absolute pCloud path (cross-folder playlist) — resolve at play time.
                addItem(
                    MediaItem(
                        pendingTitle ?: line.substringAfterLast('/'),
                        fileId = null, directUrl = null, path = line
                    )
                )
            } else {
                val match = matchKeys(line).firstNotNullOfOrNull { byName[it] }
                if (match?.fileId != null) {
                    addItem(MediaItem(pendingTitle ?: match.name, match.fileId, null))
                } else {
                    skipped++
                }
            }
            pendingTitle = null
            pendingId = null
        }

        if (out.isEmpty()) {
            val extra = if (skipped > 0) " ($skipped unmatched entr${if (skipped == 1) "y" else "ies"})" else ""
            ApiResult.Error("No playable entries in this playlist were found$extra.")
        } else {
            ApiResult.Ok(out)
        }
    }

    /** Create [path] if it doesn't exist; returns its folderid. */
    suspend fun ensureFolder(session: Session, path: String): ApiResult<Long> =
        withContext(Dispatchers.IO) {
            try {
                val url = "https://${session.apiHost}/createfolderifnotexists".toHttpUrl().newBuilder()
                    .addQueryParameter("auth", session.authToken)
                    .addQueryParameter("path", path)
                    .build()
                val json = http.newCall(Request.Builder().url(url).build()).execute()
                    .use { JSONObject(it.body?.string().orEmpty()) }
                if (json.optInt("result", -1) == 0) {
                    val fid = json.optJSONObject("metadata")?.optLong("folderid")
                    if (fid != null) ApiResult.Ok(fid)
                    else ApiResult.Error("No folder id returned")
                } else {
                    val code = json.optInt("result")
                    ApiResult.Error(
                        if (code == 2002) "Parent folder of \"$path\" doesn't exist."
                        else json.optString("error", "Couldn't create folder (code $code)")
                    )
                }
            } catch (e: Exception) {
                ApiResult.Error(e.message ?: "Network error")
            }
        }

    /**
     * Save a playlist whose entries are ABSOLUTE pCloud paths (cross-folder).
     * [entries] is a list of (title, absolutePath).
     */
    suspend fun savePlaylistAbsolute(
        session: Session,
        folderId: Long,
        fileName: String,
        entries: List<Pair<String, String>>
    ): ApiResult<Unit> = withContext(Dispatchers.IO) {
        if (entries.isEmpty()) return@withContext ApiResult.Error("No tracks selected")
        try {
            val content = buildString {
                append("#EXTM3U\n")
                for ((title, path) in entries) {
                    append("#EXTINF:-1,").append(title).append('\n')
                    append(path).append('\n')
                }
            }
            val url = "https://${session.apiHost}/uploadfile".toHttpUrl().newBuilder()
                .addQueryParameter("auth", session.authToken)
                .addQueryParameter("folderid", folderId.toString())
                .addQueryParameter("nopartial", "1")
                .build()
            val part = RequestBody.create("audio/x-mpegurl".toMediaTypeOrNull(), content)
            val body = MultipartBody.Builder()
                .setType(MultipartBody.FORM)
                .addFormDataPart("file", fileName, part)
                .build()
            val json = http.newCall(Request.Builder().url(url).post(body).build()).execute()
                .use { JSONObject(it.body?.string().orEmpty()) }
            if (json.optInt("result", -1) == 0) ApiResult.Ok(Unit)
            else ApiResult.Error(json.optString("error", "Upload failed (code ${json.optInt("result")})"))
        } catch (e: Exception) {
            ApiResult.Error(e.message ?: "Network error")
        }
    }

    /**
     * Save a cross-folder playlist from in-app items, embedding each track's
     * pCloud fileid as a `#PCLOUDID:` comment alongside its absolute path. On
     * playback we prefer the fileid (stable, immune to path-reconstruction
     * mistakes); the path line keeps the .m3u valid for other players.
     */
    suspend fun savePlaylistFromItems(
        session: Session,
        folderId: Long,
        fileName: String,
        items: List<MediaItem>
    ): ApiResult<Unit> = withContext(Dispatchers.IO) {
        if (items.isEmpty()) return@withContext ApiResult.Error("No tracks selected")
        try {
            val content = buildString {
                append("#EXTM3U\n")
                for (mi in items) {
                    append("#EXTINF:-1,").append(mi.title).append('\n')
                    mi.fileId?.let { id -> append("#PCLOUDID:").append(id).append('\n') }
                    append(mi.path ?: mi.title).append('\n')
                }
            }
            val url = "https://${session.apiHost}/uploadfile".toHttpUrl().newBuilder()
                .addQueryParameter("auth", session.authToken)
                .addQueryParameter("folderid", folderId.toString())
                .addQueryParameter("nopartial", "1")
                .build()
            val part = RequestBody.create("audio/x-mpegurl".toMediaTypeOrNull(), content)
            val body = MultipartBody.Builder()
                .setType(MultipartBody.FORM)
                .addFormDataPart("file", fileName, part)
                .build()
            val json = http.newCall(Request.Builder().url(url).post(body).build()).execute()
                .use { JSONObject(it.body?.string().orEmpty()) }
            if (json.optInt("result", -1) == 0) ApiResult.Ok(Unit)
            else ApiResult.Error(json.optString("error", "Upload failed (code ${json.optInt("result")})"))
        } catch (e: Exception) {
            ApiResult.Error(e.message ?: "Network error")
        }
    }

    /**
     * Recursively collect every folder under [rootFolderId] that directly
     * contains playable files (one recursive listfolder call).
     */
    suspend fun collectAudioFolders(
        session: Session,
        rootFolderId: Long
    ): ApiResult<List<AudioFolder>> = withContext(Dispatchers.IO) {
        val url = "https://${session.apiHost}/listfolder".toHttpUrl().newBuilder()
            .addQueryParameter("auth", session.authToken)
            .addQueryParameter("folderid", rootFolderId.toString())
            .addQueryParameter("recursive", "1")
            .build()
        scanAudioFolders(url, "")
    }

    /**
     * Same, but addressed by a pCloud path such as "/Music" or "/Books/Audiobooks".
     */
    suspend fun collectAudioFoldersByPath(
        session: Session,
        path: String
    ): ApiResult<List<AudioFolder>> = withContext(Dispatchers.IO) {
        val clean = ("/" + path.trim().trim('/')).ifBlank { "/" }
        val url = "https://${session.apiHost}/listfolder".toHttpUrl().newBuilder()
            .addQueryParameter("auth", session.authToken)
            .addQueryParameter("path", clean)
            .addQueryParameter("recursive", "1")
            .build()
        scanAudioFolders(url, clean)
    }

    private fun scanAudioFolders(url: okhttp3.HttpUrl, basePath: String): ApiResult<List<AudioFolder>> {
        return try {
            val json = http.newCall(Request.Builder().url(url).build()).execute()
                .use { JSONObject(it.body?.string().orEmpty()) }
            if (json.optInt("result", -1) != 0) {
                val code = json.optInt("result")
                val msg = when (code) {
                    2005 -> "That folder path wasn't found."
                    else -> json.optString("error", "Could not scan folder (code $code)")
                }
                return ApiResult.Error(msg)
            }

            val out = mutableListOf<AudioFolder>()

            fun parseItem(o: JSONObject): PItem {
                val isFolder = o.optBoolean("isfolder", false)
                return PItem(
                    name = o.optString("name"),
                    isFolder = isFolder,
                    folderId = if (isFolder) o.optLong("folderid") else null,
                    fileId = if (!isFolder) o.optLong("fileid") else null,
                    contentType = o.optString("contenttype", ""),
                    category = o.optInt("category", 0),
                    size = o.optLong("size", 0L)
                )
            }

            fun walk(meta: JSONObject, folderPath: String) {
                val fid = meta.optLong("folderid")
                val fname = meta.optString("name")
                val contents = meta.optJSONArray("contents") ?: return
                val files = mutableListOf<PItem>()
                for (i in 0 until contents.length()) {
                    val item = parseItem(contents.getJSONObject(i))
                    if (!item.isFolder && item.isPlayable) files.add(item)
                }
                if (files.isNotEmpty()) {
                    out.add(AudioFolder(fid, fname, folderPath, files.sortedBy { naturalKey(it.name) }))
                }
                for (i in 0 until contents.length()) {
                    val o = contents.getJSONObject(i)
                    if (o.optBoolean("isfolder", false)) {
                        walk(o, folderPath.trimEnd('/') + "/" + o.optString("name"))
                    }
                }
            }

            walk(json.getJSONObject("metadata"), if (basePath.isBlank()) "/" else basePath)
            ApiResult.Ok(out)
        } catch (e: Exception) {
            ApiResult.Error(e.message ?: "Network error")
        }
    }

    /**
     * Every existing .m3u/.m3u8 file under a pCloud path (for clean regeneration).
     * Any folder whose absolute path equals [excludePath] is skipped entirely, so
     * curated playlists living there are never deleted.
     */
    suspend fun collectPlaylistsByPath(
        session: Session,
        path: String,
        excludePath: String? = null
    ): ApiResult<List<PItem>> = withContext(Dispatchers.IO) {
        val clean = ("/" + path.trim().trim('/')).ifBlank { "/" }
        val exclude = excludePath?.let { "/" + it.trim().trim('/') }?.lowercase()
        val url = "https://${session.apiHost}/listfolder".toHttpUrl().newBuilder()
            .addQueryParameter("auth", session.authToken)
            .addQueryParameter("path", clean)
            .addQueryParameter("recursive", "1")
            .build()
        try {
            val json = http.newCall(Request.Builder().url(url).build()).execute()
                .use { JSONObject(it.body?.string().orEmpty()) }
            if (json.optInt("result", -1) != 0) {
                val code = json.optInt("result")
                return@withContext ApiResult.Error(
                    if (code == 2005) "That folder path wasn't found."
                    else json.optString("error", "Could not scan folder (code $code)")
                )
            }
            val out = mutableListOf<PItem>()
            fun walk(meta: JSONObject, folderPath: String) {
                // Never descend into (or collect from) the protected folder.
                if (exclude != null && folderPath.lowercase() == exclude) return
                val contents = meta.optJSONArray("contents") ?: return
                for (i in 0 until contents.length()) {
                    val o = contents.getJSONObject(i)
                    if (o.optBoolean("isfolder", false)) {
                        val name = o.optString("name")
                        walk(o, folderPath.trimEnd('/') + "/" + name)
                    } else {
                        val name = o.optString("name")
                        if (name.endsWith(".m3u", true) || name.endsWith(".m3u8", true)) {
                            out.add(PItem(name = name, isFolder = false,
                                folderId = null, fileId = o.optLong("fileid"),
                                contentType = "", category = 0, size = o.optLong("size", 0L)))
                        }
                    }
                }
            }
            walk(json.getJSONObject("metadata"), clean)
            ApiResult.Ok(out)
        } catch (e: Exception) {
            ApiResult.Error(e.message ?: "Network error")
        }
    }

    /** Delete a file by id. */
    suspend fun deleteFile(session: Session, fileId: Long): ApiResult<Unit> =
        withContext(Dispatchers.IO) {
            try {
                val url = "https://${session.apiHost}/deletefile".toHttpUrl().newBuilder()
                    .addQueryParameter("auth", session.authToken)
                    .addQueryParameter("fileid", fileId.toString())
                    .build()
                val json = http.newCall(Request.Builder().url(url).build()).execute()
                    .use { JSONObject(it.body?.string().orEmpty()) }
                if (json.optInt("result", -1) == 0) ApiResult.Ok(Unit)
                else ApiResult.Error(json.optString("error", "Delete failed"))
            } catch (e: Exception) {
                ApiResult.Error(e.message ?: "Network error")
            }
        }

    /** Rename a file in place. [newName] is the bare file name (with extension). */
    suspend fun renameFile(session: Session, fileId: Long, newName: String): ApiResult<Unit> =
        withContext(Dispatchers.IO) {
            try {
                val url = "https://${session.apiHost}/renamefile".toHttpUrl().newBuilder()
                    .addQueryParameter("auth", session.authToken)
                    .addQueryParameter("fileid", fileId.toString())
                    .addQueryParameter("toname", newName)
                    .build()
                val json = http.newCall(Request.Builder().url(url).build()).execute()
                    .use { JSONObject(it.body?.string().orEmpty()) }
                if (json.optInt("result", -1) == 0) ApiResult.Ok(Unit)
                else ApiResult.Error(json.optString("error", "Rename failed (code ${json.optInt("result")})"))
            } catch (e: Exception) {
                ApiResult.Error(e.message ?: "Network error")
            }
        }

    /**
     * Read an .m3u's raw entries as (title, target) pairs, preserving each target
     * line verbatim (absolute pCloud path or http URL). Used by the playlist editor
     * so edits can be written straight back with [savePlaylistAbsolute].
     */
    suspend fun readPlaylistEntries(
        session: Session,
        fileId: Long
    ): ApiResult<List<Pair<String, String>>> = withContext(Dispatchers.IO) {
        val linkRes = getStreamUrl(session, fileId)
        val url = when (linkRes) {
            is ApiResult.Ok -> linkRes.value
            is ApiResult.Error -> return@withContext ApiResult.Error(linkRes.message)
        }
        val text = try {
            http.newCall(Request.Builder().url(url).build()).execute()
                .use { it.body?.string().orEmpty() }
        } catch (e: Exception) {
            return@withContext ApiResult.Error(e.message ?: "Could not read playlist")
        }
        val out = mutableListOf<Pair<String, String>>()
        var pendingTitle: String? = null
        for (raw in text.lines()) {
            val line = raw.trim()
            if (line.isEmpty()) continue
            if (line.startsWith("#")) {
                if (line.startsWith("#EXTINF", ignoreCase = true)) {
                    pendingTitle = line.substringAfter(",", "").trim().ifBlank { null }
                }
                continue
            }
            out += (pendingTitle ?: line.substringAfterLast('/').ifBlank { line }) to line
            pendingTitle = null
        }
        ApiResult.Ok(out)
    }

    /** Natural sort key so "2" comes before "10". */
    private fun naturalKey(name: String): String =
        Regex("\\d+").replace(name) { it.value.padStart(10, '0') }.lowercase()

    // ---- Public shared links (no auth token required) ----

    /** Extract the link code from a full pCloud share URL, or accept a bare code. */
    private fun extractPublinkCode(input: String): String {
        val m = Regex("code=([^&\\s]+)").find(input)
        if (m != null) return m.groupValues[1]
        // Bare code (no URL): take the last path-ish token.
        return input.substringAfterLast('/').substringAfterLast('=').trim()
    }

    /**
     * Follow redirects to the final URL. Short links (tinyurl, bit.ly, pc.cd, …)
     * don't contain the pCloud code themselves — they redirect to the real link,
     * which is much easier to type on a TV than a full pCloud URL.
     */
    private fun resolveFinalUrl(input: String): String = try {
        http.newCall(Request.Builder().url(input).build()).execute()
            .use { it.request.url.toString() }
    } catch (e: Exception) {
        input
    }

    /**
     * Open a pCloud public share link (file or folder) WITHOUT an account, via
     * showpublink. Tries both regions. Returns the tree for browsing/playback.
     */
    suspend fun openPublink(input: String): ApiResult<Publink> = withContext(Dispatchers.IO) {
        var src = input.trim()
        // A short/redirect link has no pCloud "code=" — resolve it to the real URL first.
        if (src.startsWith("http", ignoreCase = true) && !src.contains("code=", ignoreCase = true)) {
            src = resolveFinalUrl(src)
        }
        val code = extractPublinkCode(src)
        if (code.isBlank()) return@withContext ApiResult.Error("Couldn't read a link code.")

        var lastMsg = "Couldn't open this link. It may be invalid or expired."
        for (host in listOf("api.pcloud.com", "eapi.pcloud.com")) {
            try {
                val url = "https://$host/showpublink".toHttpUrl().newBuilder()
                    .addQueryParameter("code", code)
                    .build()
                val json = http.newCall(Request.Builder().url(url).build()).execute()
                    .use { JSONObject(it.body?.string().orEmpty()) }
                val result = json.optInt("result", -1)
                if (result == 0) {
                    val meta = json.getJSONObject("metadata")
                    val children = HashMap<Long, MutableList<PItem>>()

                    fun parse(o: JSONObject): PItem {
                        val isFolder = o.optBoolean("isfolder", false)
                        return PItem(
                            name = o.optString("name"),
                            isFolder = isFolder,
                            folderId = if (isFolder) o.optLong("folderid") else null,
                            fileId = if (!isFolder) o.optLong("fileid") else null,
                            contentType = o.optString("contenttype", ""),
                            category = o.optInt("category", 0),
                            size = o.optLong("size", 0L)
                        )
                    }

                    fun walk(o: JSONObject) {
                        if (!o.optBoolean("isfolder", false)) return
                        val fid = o.optLong("folderid")
                        val contents = o.optJSONArray("contents") ?: return
                        val kids = ArrayList<PItem>()
                        for (i in 0 until contents.length()) {
                            kids.add(parse(contents.getJSONObject(i)))
                        }
                        children[fid] = kids.sortedWith(
                            compareByDescending<PItem> { it.isFolder }.thenBy { naturalKey(it.name) }
                        ).toMutableList()
                        for (i in 0 until contents.length()) {
                            val c = contents.getJSONObject(i)
                            if (c.optBoolean("isfolder", false)) walk(c)
                        }
                    }

                    val root = parse(meta)
                    if (meta.optBoolean("isfolder", false)) walk(meta)
                    return@withContext ApiResult.Ok(Publink(code, host, root, children))
                } else if (result == 2009 || result == 1017) {
                    lastMsg = "That share link wasn't found."
                } else if (result == 2284 || result == 2261) {
                    return@withContext ApiResult.Error("This link is password-protected and can't be opened here.")
                }
            } catch (_: Exception) {
                // try the other region
            }
        }
        ApiResult.Error(lastMsg)
    }

    /** Stream URL for a file inside (or being) a public link — no auth token. */
    suspend fun getPublinkStreamUrl(
        apiHost: String,
        code: String,
        fileId: Long
    ): ApiResult<String> = withContext(Dispatchers.IO) {
        try {
            val url = "https://$apiHost/getpublinkdownload".toHttpUrl().newBuilder()
                .addQueryParameter("code", code)
                .addQueryParameter("fileid", fileId.toString())
                .build()
            val json = http.newCall(Request.Builder().url(url).build()).execute()
                .use { JSONObject(it.body?.string().orEmpty()) }
            if (json.optInt("result", -1) != 0) {
                return@withContext ApiResult.Error(
                    json.optString("error", "Couldn't get stream (code ${json.optInt("result")})")
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

    /** Download a small document's bytes from a public link (.nfo / .htm viewer). */
    suspend fun fetchPublinkDocument(
        apiHost: String,
        code: String,
        fileId: Long
    ): ApiResult<ByteArray> = withContext(Dispatchers.IO) {
        try {
            when (val link = getPublinkStreamUrl(apiHost, code, fileId)) {
                is ApiResult.Error -> ApiResult.Error(link.message)
                is ApiResult.Ok -> {
                    val req = Request.Builder().url(link.value).build()
                    http.newCall(req).execute().use { resp ->
                        if (!resp.isSuccessful) {
                            ApiResult.Error("Could not load file (HTTP ${resp.code})")
                        } else {
                            ApiResult.Ok(resp.body?.bytes() ?: ByteArray(0))
                        }
                    }
                }
            }
        } catch (e: Exception) {
            ApiResult.Error(e.message ?: "Network error")
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
