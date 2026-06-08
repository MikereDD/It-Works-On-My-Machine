package com.typezero.cloudtv.data

import com.typezero.cloudtv.BuildConfig

/**
 * Microsoft (OneDrive / Graph) OAuth + API configuration.
 *
 * Uses the v2.0 `/common` endpoints, which accept both personal Microsoft
 * accounts and work/school accounts. One multi-tenant client id serves every
 * user — they each sign into their own OneDrive. No client secret (public
 * client + PKCE).
 */
object MicrosoftConfig {

    val clientId: String = BuildConfig.MICROSOFT_CLIENT_ID

    const val AUTH_ENDPOINT = "https://login.microsoftonline.com/common/oauth2/v2.0/authorize"
    const val TOKEN_ENDPOINT = "https://login.microsoftonline.com/common/oauth2/v2.0/token"

    const val GRAPH_BASE = "https://graph.microsoft.com/v1.0"

    /** offline_access yields a refresh token; Files.Read is enough to browse + stream. */
    val scopes = listOf("openid", "profile", "offline_access", "User.Read", "Files.Read")

    val isConfigured: Boolean get() = !clientId.startsWith("REPLACE_ME")
}
