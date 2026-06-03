package com.typezero.pcloudtv.data

import android.content.Context

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
