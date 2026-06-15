package com.typezero.seraph.data.musicbrainz

import com.typezero.seraph.data.model.MusicBrainzResult
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONObject
import java.io.IOException
import java.net.HttpURLConnection
import java.net.URL
import java.net.URLEncoder

/**
 * Thin MusicBrainz WS/2 + Cover Art Archive client built on HttpURLConnection so
 * the app carries no HTTP dependency. MusicBrainz requires a descriptive
 * User-Agent and rate-limits anonymous callers to ~1 request/second, which we
 * enforce with a synchronized minimum spacing between calls.
 */
class MusicBrainzClient {

    @Volatile private var lastCallAt = 0L

    suspend fun searchRecordings(
        title: String,
        artist: String,
        album: String,
        limit: Int = 8,
    ): List<MusicBrainzResult> = withContext(Dispatchers.IO) {
        val parts = buildList {
            if (title.isNotBlank()) add("recording:\"${title.trim()}\"")
            if (artist.isNotBlank()) add("artist:\"${artist.trim()}\"")
            if (album.isNotBlank()) add("release:\"${album.trim()}\"")
        }
        if (parts.isEmpty()) return@withContext emptyList()
        val query = URLEncoder.encode(parts.joinToString(" AND "), "UTF-8")
        val url = "$WS/recording?query=$query&fmt=json&limit=$limit"
        val body = get(url) ?: return@withContext emptyList()
        parseRecordings(body)
    }

    /** Front cover bytes for a release, or null. Tries 500px then full size. */
    suspend fun frontCover(releaseMbid: String): ByteArray? = withContext(Dispatchers.IO) {
        getBytes("$CAA/release/$releaseMbid/front-500")
            ?: getBytes("$CAA/release/$releaseMbid/front")
    }

    private fun parseRecordings(json: String): List<MusicBrainzResult> {
        val root = JSONObject(json)
        val recs = root.optJSONArray("recordings") ?: return emptyList()
        val out = ArrayList<MusicBrainzResult>(recs.length())
        for (i in 0 until recs.length()) {
            val r = recs.getJSONObject(i)
            val artist = r.optJSONArray("artist-credit")?.let { ac ->
                (0 until ac.length()).joinToString("") { idx ->
                    val c = ac.getJSONObject(idx)
                    c.optString("name") + c.optString("joinphrase")
                }
            }.orEmptyName()
            val release = r.optJSONArray("releases")?.optJSONObject(0)
            val media = release?.optJSONArray("media")?.optJSONObject(0)
            val track = media?.optJSONArray("track")?.optJSONObject(0)
            out += MusicBrainzResult(
                recordingMbid = r.optString("id"),
                title = r.optString("title"),
                artist = artist,
                album = release?.optString("title").orEmpty(),
                releaseMbid = release?.optString("id")?.ifBlank { null },
                date = release?.optString("date")?.ifBlank { null },
                trackNumber = track?.optString("number")?.ifBlank { null },
                trackTotal = media?.optInt("track-count", 0)?.takeIf { it > 0 }?.toString(),
                score = r.optInt("score", 0),
            )
        }
        return out
    }

    private fun get(url: String): String? = openThrottled(url) { conn ->
        conn.inputStream.bufferedReader().use { it.readText() }
    }

    private fun getBytes(url: String): ByteArray? = openThrottled(url) { conn ->
        conn.inputStream.use { it.readBytes() }
    }

    private fun <T> openThrottled(url: String, read: (HttpURLConnection) -> T): T? {
        return try {
            throttleBlocking()
            val conn = (URL(url).openConnection() as HttpURLConnection).apply {
                requestMethod = "GET"
                connectTimeout = 12_000
                readTimeout = 12_000
                instanceFollowRedirects = true
                setRequestProperty("User-Agent", USER_AGENT)
                setRequestProperty("Accept", "application/json")
            }
            if (conn.responseCode in 200..299) read(conn) else null.also { conn.disconnect() }
        } catch (_: IOException) {
            null
        }
    }

    /** Crude blocking spacer; callers are already on Dispatchers.IO. */
    private fun throttleBlocking() {
        synchronized(this) {
            val wait = MIN_SPACING_MS - (System.currentTimeMillis() - lastCallAt)
            if (wait > 0) Thread.sleep(wait)
            lastCallAt = System.currentTimeMillis()
        }
    }

    private fun String?.orEmptyName() = this ?: ""

    companion object {
        private const val WS = "https://musicbrainz.org/ws/2"
        private const val CAA = "https://coverartarchive.org"
        private const val MIN_SPACING_MS = 1100L
        // MusicBrainz asks that the app + contact be identifiable.
        const val USER_AGENT =
            "Seraph/0.1.0 ( https://github.com/MikereDD/It-Works-On-My-Machine )"
    }
}
