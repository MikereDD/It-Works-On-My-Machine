package com.typezero.seraph.pcloud

import android.content.Context

/**
 * Persists the pCloud bearer token and the API host to use for this account.
 * pCloud is region-split (api.pcloud.com vs eapi.pcloud.com); the authorize
 * redirect tells us which via a hostname/locationid, captured here.
 *
 * NOTE: plain SharedPreferences for now — swap in EncryptedSharedPreferences
 * (androidx.security:security-crypto) before shipping if you want at-rest crypto.
 */
class PCloudSession(context: Context) {
    private val prefs = context.applicationContext.getSharedPreferences("pcloud", Context.MODE_PRIVATE)

    var token: String?
        get() = prefs.getString("token", null)
        private set(value) { prefs.edit().putString("token", value).apply() }

    var apiHost: String
        get() = prefs.getString("host", DEFAULT_HOST) ?: DEFAULT_HOST
        private set(value) { prefs.edit().putString("host", value).apply() }

    val isSignedIn: Boolean get() = !token.isNullOrBlank()

    fun save(token: String, host: String?) {
        this.token = token
        this.apiHost = host?.takeIf { it.isNotBlank() } ?: DEFAULT_HOST
    }

    fun clear() = prefs.edit().clear().apply()

    companion object {
        const val DEFAULT_HOST = "api.pcloud.com"
        /** Map pCloud locationid -> API host (1 = US, 2 = EU). */
        fun hostForLocation(locationId: String?): String =
            if (locationId == "2") "eapi.pcloud.com" else DEFAULT_HOST
    }
}
