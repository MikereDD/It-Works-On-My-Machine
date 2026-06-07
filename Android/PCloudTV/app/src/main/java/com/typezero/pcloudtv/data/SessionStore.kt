package com.typezero.pcloudtv.data

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject

/**
 * Persists the pCloud auth token + region in app-private storage.
 * No password is ever stored. Signing out clears the token.
 */
class SessionStore(context: Context) {

    private val prefs =
        context.getSharedPreferences("pcloud_session", Context.MODE_PRIVATE)

    // Resume positions live in their own store so signing out doesn't wipe them.
    private val posPrefs =
        context.getSharedPreferences("pcloud_positions", Context.MODE_PRIVATE)

    fun savePosition(fileId: Long, positionMs: Long) {
        posPrefs.edit().putLong("pos_$fileId", positionMs).apply()
    }

    fun getPosition(fileId: Long): Long = posPrefs.getLong("pos_$fileId", 0L)

    fun clearPosition(fileId: Long) {
        posPrefs.edit().remove("pos_$fileId").apply()
    }

    // --- Per-playlist progress: which track in the playlist was playing. The
    // within-track position is handled by the per-file position store above, so a
    // playlist resumes at the right track AND the right spot in that track. ---
    fun savePlaylistIndex(playlistKey: String, index: Int) {
        posPrefs.edit().putInt("plidx_$playlistKey", index).apply()
    }

    fun getPlaylistIndex(playlistKey: String): Int = posPrefs.getInt("plidx_$playlistKey", 0)

    fun clearPlaylistIndex(playlistKey: String) {
        posPrefs.edit().remove("plidx_$playlistKey").apply()
    }

    // --- Last played: the most recent queue, so the browser can offer "Continue". ---
    fun saveLastPlayed(title: String, playlistKey: String?, queue: List<MediaItem>) {
        if (queue.isEmpty()) return
        val arr = JSONArray()
        queue.forEach { m ->
            arr.put(JSONObject().apply {
                put("t", m.title)
                m.fileId?.let { put("id", it) }
                m.directUrl?.let { put("url", it) }
                m.path?.let { put("p", it) }
            })
        }
        val obj = JSONObject().apply {
            put("title", title)
            if (playlistKey != null) put("key", playlistKey)
            put("queue", arr)
        }
        posPrefs.edit().putString("last_played", obj.toString()).apply()
    }

    fun getLastPlayed(): LastPlayed? {
        val s = posPrefs.getString("last_played", null) ?: return null
        return try {
            val obj = JSONObject(s)
            val arr = obj.getJSONArray("queue")
            val q = ArrayList<MediaItem>(arr.length())
            for (i in 0 until arr.length()) {
                val o = arr.getJSONObject(i)
                q.add(
                    MediaItem(
                        title = o.optString("t", ""),
                        fileId = if (o.has("id")) o.getLong("id") else null,
                        directUrl = if (o.has("url")) o.getString("url") else null,
                        path = if (o.has("p")) o.getString("p") else null
                    )
                )
            }
            if (q.isEmpty()) null
            else LastPlayed(
                title = obj.optString("title", q.first().title),
                playlistKey = if (obj.has("key")) obj.getString("key") else null,
                queue = q
            )
        } catch (e: Exception) {
            null
        }
    }

    fun clearLastPlayed() {
        posPrefs.edit().remove("last_played").apply()
    }

    fun save(session: Session) {
        prefs.edit()
            .putString(KEY_TOKEN, session.authToken)
            .putString(KEY_HOST, session.apiHost)
            .apply()
    }

    fun load(): Session? {
        val token = prefs.getString(KEY_TOKEN, null) ?: return null
        val host = prefs.getString(KEY_HOST, null) ?: return null
        return Session(token, host)
    }

    fun clear() = prefs.edit().clear().apply()

    companion object {
        private const val KEY_TOKEN = "auth_token"
        private const val KEY_HOST = "api_host"
    }
}
