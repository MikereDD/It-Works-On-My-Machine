package com.typezero.pcloudtv.ui

import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.lifecycle.viewmodel.compose.viewModel
import com.typezero.pcloudtv.data.ApiResult
import com.typezero.pcloudtv.data.MediaItem

@Composable
fun App(vm: AppViewModel = viewModel()) {
    val session = vm.session
    val publicLink = vm.publicLink

    // ---- Public shared-link mode (no account) ----
    if (publicLink != null) {
        var pubQueue by remember { mutableStateOf<List<MediaItem>?>(null) }
        val q = pubQueue
        if (q != null) {
            PlayerScreen(
                queue = q,
                resolveUrl = { item ->
                    item.directUrl?.let { ApiResult.Ok(it) }
                        ?: item.fileId?.let {
                            vm.client.getPublinkStreamUrl(publicLink.apiHost, publicLink.code, it)
                        }
                        ?: ApiResult.Error("Bad item")
                },
                fetchArt = { vm.client.fetchEmbeddedArt(it) },
                onExit = { pubQueue = null }
            )
        } else {
            PublicBrowseScreen(
                link = publicLink,
                client = vm.client,
                onPlayQueue = { pubQueue = it },
                onClose = { vm.closePublicLink() }
            )
        }
        return
    }

    if (session == null || vm.addingAccount) {
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
                onUseToken = { vm.useToken(it) },
                onOpenLink = { vm.openPublicLink(it) }
            )
        }
        return
    }

    var queue by remember { mutableStateOf<List<MediaItem>?>(null) }
    var playlistKey by remember { mutableStateOf<String?>(null) }
    val q = queue
    if (q != null) {
        PlayerScreen(
            queue = q,
            resolveUrl = { item ->
                when {
                    item.directUrl != null -> ApiResult.Ok(item.directUrl)
                    item.path != null -> vm.client.getStreamUrlByPath(session, item.path)
                    item.fileId != null -> vm.client.getStreamUrl(session, item.fileId)
                    else -> ApiResult.Error("Bad item")
                }
            },
            playlistKey = playlistKey,
            fetchArt = { vm.client.fetchEmbeddedArt(it) },
            onExit = { queue = null; playlistKey = null }
        )
    } else {
        BrowseScreen(
            client = vm.client,
            session = session,
            accounts = vm.accounts,
            activeAccountId = vm.activeAccountId,
            onPlayQueue = { items, key -> queue = items; playlistKey = key },
            onSwitchAccount = vm::switchAccount,
            onAddAccount = vm::beginAddAccount,
            onLogout = vm::logout
        )
    }
}
