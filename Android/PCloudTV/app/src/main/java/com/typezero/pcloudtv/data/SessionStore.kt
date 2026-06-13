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

    // --- Recently played (a short, newest-first, de-duped history) ---
    private fun entryToJson(title: String, playlistKey: String?, queue: List<MediaItem>): JSONObject {
        val arr = JSONArray()
        queue.forEach { m ->
            arr.put(JSONObject().apply {
                put("t", m.title)
                m.fileId?.let { put("id", it) }
                m.directUrl?.let { put("url", it) }
                m.path?.let { put("p", it) }
            })
        }
        return JSONObject().apply {
            put("title", title)
            if (playlistKey != null) put("key", playlistKey)
            put("queue", arr)
        }
    }

    private fun jsonToEntry(obj: JSONObject): LastPlayed? = try {
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

    fun addRecent(title: String, playlistKey: String?, queue: List<MediaItem>) {
        if (queue.isEmpty() || title.isBlank()) return
        val out = JSONArray()
        out.put(entryToJson(title, playlistKey, queue))
        val prev = posPrefs.getString("recents", null)
        if (prev != null) {
            runCatching {
                val arr = JSONArray(prev)
                var count = 1
                for (i in 0 until arr.length()) {
                    if (count >= 12) break
                    val o = arr.getJSONObject(i)
                    val sameTitle = o.optString("title", "") == title
                    val sameKey = (if (o.has("key")) o.getString("key") else null) == playlistKey
                    if (sameTitle && sameKey) continue
                    out.put(o)
                    count++
                }
            }
        }
        posPrefs.edit().putString("recents", out.toString()).apply()
    }

    fun getRecents(limit: Int = 12): List<LastPlayed> {
        val s = posPrefs.getString("recents", null) ?: return emptyList()
        return try {
            val arr = JSONArray(s)
            val list = ArrayList<LastPlayed>()
            for (i in 0 until arr.length()) {
                if (list.size >= limit) break
                jsonToEntry(arr.getJSONObject(i))?.let { list.add(it) }
            }
            list
        } catch (e: Exception) {
            emptyList()
        }
    }

    /** Remove a single recently-played entry, matched by title + playlist key. */
    fun removeRecent(title: String, playlistKey: String?) {
        val s = posPrefs.getString("recents", null) ?: return
        runCatching {
            val arr = JSONArray(s)
            val out = JSONArray()
            for (i in 0 until arr.length()) {
                val o = arr.getJSONObject(i)
                val sameTitle = o.optString("title", "") == title
                val sameKey = (if (o.has("key")) o.getString("key") else null) == playlistKey
                if (sameTitle && sameKey) continue
                out.put(o)
            }
            posPrefs.edit().putString("recents", out.toString()).apply()
        }
    }

    /** Wipe the entire recently-played history. */
    fun clearRecents() {
        posPrefs.edit().remove("recents").apply()
    }

    // ---- Accounts (multi-account switcher) ----

    fun getAccounts(): List<Account> {
        val s = prefs.getString(KEY_ACCOUNTS, null)
        if (s == null) {
            // Migrate a legacy single session into the accounts list on first read.
            val token = prefs.getString(KEY_TOKEN, null)
            val host = prefs.getString(KEY_HOST, null)
            if (token != null && host != null) {
                val acc = Account(id = token, label = "pCloud account", token = token, host = host)
                persistAccounts(listOf(acc), acc.id)
                return listOf(acc)
            }
            return emptyList()
        }
        return try {
            val arr = JSONArray(s)
            buildList {
                for (i in 0 until arr.length()) {
                    val o = arr.getJSONObject(i)
                    add(
                        Account(
                            id = o.getString("id"),
                            label = o.optString("label", "pCloud account"),
                            token = o.getString("token"),
                            host = o.getString("host")
                        )
                    )
                }
            }
        } catch (e: Exception) {
            emptyList()
        }
    }

    private fun persistAccounts(list: List<Account>, activeId: String?) {
        val arr = JSONArray()
        list.forEach { a ->
            arr.put(
                JSONObject().apply {
                    put("id", a.id); put("label", a.label)
                    put("token", a.token); put("host", a.host)
                }
            )
        }
        val ed = prefs.edit().putString(KEY_ACCOUNTS, arr.toString())
        if (activeId != null) ed.putString(KEY_ACTIVE, activeId) else ed.remove(KEY_ACTIVE)
        ed.apply()
    }

    fun getActiveAccount(): Account? {
        val list = getAccounts()
        if (list.isEmpty()) return null
        val active = prefs.getString(KEY_ACTIVE, null)
        return list.firstOrNull { it.id == active } ?: list.first()
    }

    fun setActive(id: String) {
        prefs.edit().putString(KEY_ACTIVE, id).apply()
    }

    /** Add (or update, matched by id) an account and make it active. Returns its id. */
    fun addOrUpdateAccount(session: Session): String {
        val label = session.email ?: "pCloud account"
        val id = session.email ?: session.authToken
        val list = getAccounts().toMutableList()
        val acc = Account(id = id, label = label, token = session.authToken, host = session.apiHost)
        val existing = list.indexOfFirst { it.id == id }
        if (existing >= 0) list[existing] = acc else list.add(acc)
        persistAccounts(list, id)
        return id
    }

    /** Remove an account; returns the session now active (or null if none left). */
    fun removeAccount(id: String): Session? {
        val list = getAccounts().filterNot { it.id == id }
        val active = prefs.getString(KEY_ACTIVE, null)
        val newActive = if (active == id) list.firstOrNull()?.id else active
        persistAccounts(list, newActive)
        return getActiveAccount()?.toSession()
    }

    // ---- Back-compat single-session API, now backed by the accounts list ----

    fun save(session: Session) { addOrUpdateAccount(session) }

    fun load(): Session? = getActiveAccount()?.toSession()

    fun clear() = prefs.edit().clear().apply()

    companion object {
        private const val KEY_TOKEN = "auth_token"
        private const val KEY_HOST = "api_host"
        private const val KEY_ACCOUNTS = "accounts"
        private const val KEY_ACTIVE = "active_account"
    }
}
