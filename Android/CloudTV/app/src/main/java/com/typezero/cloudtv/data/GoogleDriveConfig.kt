package com.typezero.cloudtv.data

import com.typezero.cloudtv.BuildConfig

/**
 * Google Drive OAuth + API configuration.
 *
 * The client id comes from [BuildConfig.GOOGLE_CLIENT_ID] (set in
 * app/build.gradle.kts). Until you replace the REPLACE_ME placeholder with a
 * real Android OAuth client id from Google Cloud Console, [isConfigured] is
 * false and the app will skip offering Google Drive.
 */
object GoogleDriveConfig {

    val clientId: String = BuildConfig.GOOGLE_CLIENT_ID

    /** Reversed-client-id custom scheme, e.g. com.googleusercontent.apps.1234-abc */
    private val reversedClientId: String =
        "com.googleusercontent.apps." +
            clientId.removeSuffix(".apps.googleusercontent.com")

    /** Redirect the Custom Tab returns to; must match build.gradle's appAuthRedirectScheme. */
    val redirectUri: String = "$reversedClientId:/oauth2redirect"

    const val AUTH_ENDPOINT = "https://accounts.google.com/o/oauth2/v2/auth"
    const val TOKEN_ENDPOINT = "https://oauth2.googleapis.com/token"

    /** drive.readonly is a restricted scope; openid/email/profile label the account. */
    val scopes = listOf(
        "openid",
        "email",
        "profile",
        "https://www.googleapis.com/auth/drive.readonly"
    )

    val isConfigured: Boolean get() = !clientId.startsWith("REPLACE_ME")
}
