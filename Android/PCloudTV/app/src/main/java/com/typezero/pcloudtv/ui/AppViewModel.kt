package com.typezero.pcloudtv.ui

import android.app.Application
import android.webkit.CookieManager
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.typezero.pcloudtv.data.ApiResult
import com.typezero.pcloudtv.data.PCloudClient
import com.typezero.pcloudtv.data.SessionStore
import kotlinx.coroutines.launch

class AppViewModel(app: Application) : AndroidViewModel(app) {

    val client = PCloudClient()
    private val store = SessionStore(app)

    var session by mutableStateOf(store.load())
        private set

    var loginInProgress by mutableStateOf(false)
        private set

    var busy by mutableStateOf(false)
        private set

    var loginError by mutableStateOf<String?>(null)
        private set

    fun startWebLogin() {
        loginError = null
        loginInProgress = true
    }

    fun cancelLogin() {
        loginInProgress = false
    }

    /** Called with a token captured from the pCloud web session. */
    fun completeLogin(token: String) {
        loginInProgress = false
        validateAndSave(token)
    }

    /** Called when the user pastes a token manually. */
    fun useToken(token: String) {
        if (token.isBlank()) {
            loginError = "Paste your pCloud access token first."
            return
        }
        validateAndSave(token.trim())
    }

    private fun validateAndSave(token: String) {
        loginError = null
        busy = true
        viewModelScope.launch {
            when (val r = client.loginWithToken(token)) {
                is ApiResult.Ok -> {
                    store.save(r.value)
                    session = r.value
                }
                is ApiResult.Error -> loginError = r.message
            }
            busy = false
        }
    }

    fun logout() {
        store.clear()
        // Clear the WebView session so the next sign-in is fresh.
        CookieManager.getInstance().removeAllCookies(null)
        session = null
    }
}
