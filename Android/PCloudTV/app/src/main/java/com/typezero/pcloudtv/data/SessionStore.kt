package com.typezero.pcloudtv.data

import android.content.Context

/**
 * Persists the pCloud auth token + region in app-private storage so the user
 * only logs in once. The password is NEVER stored — only the returned token.
 */
class SessionStore(context: Context) {

    private val prefs =
        context.getSharedPreferences("pcloud_session", Context.MODE_PRIVATE)

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
