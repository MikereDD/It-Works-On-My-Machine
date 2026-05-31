package com.typezero.pcloudtv.ui

import android.app.Application
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.typezero.pcloudtv.data.ApiResult
import com.typezero.pcloudtv.data.PCloudClient
import com.typezero.pcloudtv.data.Session
import com.typezero.pcloudtv.data.SessionStore
import kotlinx.coroutines.launch

class AppViewModel(app: Application) : AndroidViewModel(app) {

    val client = PCloudClient()
    private val store = SessionStore(app)

    var session by mutableStateOf<Session?>(store.load())
        private set

    var loggingIn by mutableStateOf(false)
        private set
    var loginError by mutableStateOf<String?>(null)
        private set

    fun login(username: String, password: String) {
        if (username.isBlank() || password.isBlank()) {
            loginError = "Enter your pCloud email and password"
            return
        }
        loggingIn = true
        loginError = null
        viewModelScope.launch {
            when (val r = client.login(username.trim(), password)) {
                is ApiResult.Ok -> {
                    store.save(r.value)
                    session = r.value
                }
                is ApiResult.Error -> loginError = r.message
            }
            loggingIn = false
        }
    }

    fun logout() {
        store.clear()
        session = null
    }
}
