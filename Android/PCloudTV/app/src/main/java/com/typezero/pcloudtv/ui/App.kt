package com.typezero.pcloudtv.ui

import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.lifecycle.viewmodel.compose.viewModel
import com.typezero.pcloudtv.data.MediaItem

@Composable
fun App(vm: AppViewModel = viewModel()) {
    val session = vm.session

    if (session == null) {
        if (vm.loginInProgress) {
            WebLoginScreen(
                onResult = { token -> vm.completeLogin(token) },
                onCancel = { vm.cancelLogin() }
            )
        } else {
            LoginScreen(
                error = vm.loginError,
                busy = vm.busy,
                onSignIn = { vm.startWebLogin() },
                onUseToken = { vm.useToken(it) }
            )
        }
        return
    }

    var queue by remember { mutableStateOf<List<MediaItem>?>(null) }
    val q = queue

    if (q != null) {
        PlayerScreen(
            client = vm.client,
            session = session,
            queue = q,
            onExit = { queue = null }
        )
    } else {
        BrowseScreen(
            client = vm.client,
            session = session,
            onPlayQueue = { queue = it },
            onLogout = vm::logout
        )
    }
}
