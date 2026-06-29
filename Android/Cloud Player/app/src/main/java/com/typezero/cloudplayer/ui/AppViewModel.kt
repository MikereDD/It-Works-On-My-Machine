package com.typezero.cloudplayer.ui

import android.app.Application
import android.webkit.CookieManager
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.typezero.cloudplayer.data.ApiResult
import com.typezero.cloudplayer.data.Account
import com.typezero.cloudplayer.data.DropboxAccount
import com.typezero.cloudplayer.data.BoxAccount
import com.typezero.cloudplayer.data.PCloudClient
import com.typezero.cloudplayer.data.MegaAccount
import com.typezero.cloudplayer.data.Publink
import com.typezero.cloudplayer.data.MegaSharedLinkParser
import com.typezero.cloudplayer.data.SessionStore
import com.typezero.cloudplayer.data.MediaItem
import com.typezero.cloudplayer.data.SharedMediaLinkParser
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

    var accounts by mutableStateOf(store.getAccounts())
        private set

    var addingAccount by mutableStateOf(false)
        private set

    var megaAccounts by mutableStateOf(store.getMegaAccounts())
        private set

    var dropboxAccounts by mutableStateOf(store.getDropboxAccounts())
        private set

    var boxAccounts by mutableStateOf(store.getBoxAccounts())
        private set

    /** Id of the active account (matches Account.id = email ?: token). */
    val activeAccountId: String?
        get() = session?.let { it.email ?: it.authToken }

    fun startWebLogin() {
        loginError = null
        loginInProgress = true
    }

    fun cancelLogin() {
        loginInProgress = false
        addingAccount = false
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
                    accounts = store.getAccounts()
                    addingAccount = false
                }
                is ApiResult.Error -> loginError = r.message
            }
            busy = false
        }
    }

    /** Start adding another account: jump straight into the web login. */
    fun beginAddAccount() {
        loginError = null
        addingAccount = true
        loginInProgress = true
        // Fresh web session so you can sign in as a *different* account.
        CookieManager.getInstance().removeAllCookies(null)
    }

    fun switchAccount(id: String) {
        store.setActive(id)
        session = store.load()
        accounts = store.getAccounts()
    }

    fun removeAccount(id: String) {
        session = store.removeAccount(id)
        accounts = store.getAccounts()
        if (session == null) CookieManager.getInstance().removeAllCookies(null)
    }

    fun markMegaWebSignedIn(email: String? = null) {
        store.addMegaWebSession(email)
        megaAccounts = store.getMegaAccounts()
    }

    fun removeMegaAccount(id: String) {
        store.removeMegaAccount(id)
        megaAccounts = store.getMegaAccounts()
    }

    fun markDropboxWebSignedIn(email: String? = null) {
        store.addDropboxWebSession(email)
        dropboxAccounts = store.getDropboxAccounts()
    }

    fun removeDropboxAccount(id: String) {
        store.removeDropboxAccount(id)
        dropboxAccounts = store.getDropboxAccounts()
    }

    fun markBoxWebSignedIn(email: String? = null) {
        store.addBoxWebSession(email)
        boxAccounts = store.getBoxAccounts()
    }

    fun removeBoxAccount(id: String) {
        store.removeBoxAccount(id)
        boxAccounts = store.getBoxAccounts()
    }

    fun logout() {
        // Sign out of the active account; fall back to another if one exists.
        val active = store.getActiveAccount()
        session = if (active != null) store.removeAccount(active.id) else null
        accounts = store.getAccounts()
        if (session == null) {
            // No accounts left — clear the WebView session for a fresh sign-in.
            CookieManager.getInstance().removeAllCookies(null)
        }
    }

    // ---- Public shared links (no account needed) ----

    var publicLink by mutableStateOf<Publink?>(null)
        private set

    var megaSharedWebUrl by mutableStateOf<String?>(null)
        private set

    var nativeSharedQueue by mutableStateOf<List<MediaItem>?>(null)
        private set

    fun openPublicLink(input: String) {
        val trimmed = input.trim()
        if (trimmed.isBlank()) {
            loginError = "Paste a shared link first."
            return
        }

        if (MegaSharedLinkParser.looksLikeMegaLink(trimmed)) {
            val megaLink = MegaSharedLinkParser.parse(trimmed)
            if (megaLink == null) {
                loginError = "MEGA link found, but the decryption key is missing. Paste the full link including #key, or paste the separate decryption key under the link."
            } else {
                loginError = null
                publicLink = null
                nativeSharedQueue = null
                megaSharedWebUrl = megaLink.normalizedUrl
            }
            return
        }

        SharedMediaLinkParser.parse(trimmed)?.let { parsed ->
            loginError = null
            publicLink = null
            megaSharedWebUrl = null
            nativeSharedQueue = listOf(MediaItem(parsed.title, fileId = null, directUrl = parsed.playbackUrl))
            return
        }

        loginError = null
        busy = true
        viewModelScope.launch {
            when (val r = client.openPublink(trimmed)) {
                is ApiResult.Ok -> publicLink = r.value
                is ApiResult.Error -> loginError = r.message
            }
            busy = false
        }
    }

    fun closePublicLink() {
        publicLink = null
    }

    fun closeNativeSharedPlayback() {
        nativeSharedQueue = null
    }

    fun closeMegaSharedWebLink() {
        megaSharedWebUrl = null
    }
}
