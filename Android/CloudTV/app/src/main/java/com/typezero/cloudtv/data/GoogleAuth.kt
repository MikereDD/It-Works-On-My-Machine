package com.typezero.cloudtv.data

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.util.Base64
import kotlinx.coroutines.suspendCancellableCoroutine
import net.openid.appauth.AuthState
import net.openid.appauth.AuthorizationException
import net.openid.appauth.AuthorizationRequest
import net.openid.appauth.AuthorizationResponse
import net.openid.appauth.AuthorizationService
import net.openid.appauth.AuthorizationServiceConfiguration
import net.openid.appauth.ResponseTypeValues
import net.openid.appauth.TokenResponse
import org.json.JSONObject
import kotlin.coroutines.resume

/**
 * Google OAuth (auth-code + PKCE) via AppAuth / Chrome Custom Tabs. Google
 * blocks OAuth inside embedded WebViews, so this is the required path.
 *
 * Flow: [authIntent] launches the Custom Tab; the redirect comes back to an
 * Activity which passes the result to [handleResult] to exchange the code for
 * tokens. The resulting [AuthState] is serialized to a String and stored on the
 * account; [freshToken] reads it back and auto-refreshes the access token.
 *
 * NOTE: untested until a real client id + SHA-1 are registered.
 */
class GoogleAuth(context: Context) {

    private val appContext = context.applicationContext
    private val service = AuthorizationService(appContext)

    private val serviceConfig = AuthorizationServiceConfiguration(
        Uri.parse(GoogleDriveConfig.AUTH_ENDPOINT),
        Uri.parse(GoogleDriveConfig.TOKEN_ENDPOINT)
    )

    /** Intent that opens the Google sign-in Custom Tab. Launch it for result. */
    fun authIntent(): Intent {
        val request = AuthorizationRequest.Builder(
            serviceConfig,
            GoogleDriveConfig.clientId,
            ResponseTypeValues.CODE,
            Uri.parse(GoogleDriveConfig.redirectUri)
        ).setScopes(GoogleDriveConfig.scopes).build()
        return service.getAuthorizationRequestIntent(request)
    }

    /**
     * Exchange the auth code from the redirect [data] for tokens.
     * @return the serialized AuthState + the account email, or null on failure.
     */
    suspend fun handleResult(data: Intent): AuthResult? {
        val resp = AuthorizationResponse.fromIntent(data) ?: return null
        val authState = AuthState(resp, AuthorizationException.fromIntent(data))
        val token = suspendCancellableCoroutine<TokenResponse?> { cont ->
            service.performTokenRequest(resp.createTokenExchangeRequest()) { tr, _ ->
                cont.resume(tr)
            }
        } ?: return null
        authState.update(token, null)
        val email = token.idToken?.let { emailFromIdToken(it) }
        return AuthResult(authState.jsonSerializeString(), email)
    }

    /** Return a valid access token for a stored AuthState, refreshing if needed. */
    suspend fun freshToken(authStateJson: String): String? {
        val authState = runCatching { AuthState.jsonDeserialize(authStateJson) }.getOrNull()
            ?: return null
        return suspendCancellableCoroutine { cont ->
            authState.performActionWithFreshTokens(service) { accessToken, _, _ ->
                cont.resume(accessToken)
            }
        }
    }

    fun dispose() = service.dispose()

    data class AuthResult(val authStateJson: String, val email: String?)

    private fun emailFromIdToken(idToken: String): String? = runCatching {
        val payload = idToken.split(".")[1]
        val json = String(Base64.decode(payload, Base64.URL_SAFE or Base64.NO_PADDING))
        JSONObject(json).optString("email").takeIf { it.isNotBlank() }
    }.getOrNull()
}
