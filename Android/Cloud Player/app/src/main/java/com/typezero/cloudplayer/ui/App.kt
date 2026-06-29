package com.typezero.cloudplayer.ui

import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.lifecycle.viewmodel.compose.viewModel
import com.typezero.cloudplayer.data.ApiResult
import com.typezero.cloudplayer.data.MediaItem

@Composable
fun App(vm: AppViewModel = viewModel()) {
    val session = vm.session
    val publicLink = vm.publicLink
    val megaSharedWebUrl = vm.megaSharedWebUrl
    val nativeSharedQueue = vm.nativeSharedQueue
    var selectedProvider by remember { mutableStateOf<String?>(null) }
    var activeLibrary by remember { mutableStateOf<String?>(null) }
    var megaMessage by remember { mutableStateOf<String?>(null) }


    // ---- Native direct/shared-media playback ----
    if (nativeSharedQueue != null) {
        PlayerScreen(
            queue = nativeSharedQueue,
            resolveUrl = { item ->
                item.directUrl?.let { ApiResult.Ok(it) } ?: ApiResult.Error("No playable stream URL")
            },
            fetchArt = { vm.client.fetchEmbeddedArt(it) },
            onExit = { vm.closeNativeSharedPlayback() }
        )
        return
    }

    // ---- MEGA shared links (no account): open the official MEGA web viewer with the full #key. ----
    // MEGA files/folders are client-side encrypted. Until the native MEGA SDK/decryption
    // backend is bundled, the correct working behavior is to preserve the #key and send
    // the normalized link into MEGA's own web app instead of stopping at validation.
    if (megaSharedWebUrl != null) {
        CloudWebBrowserScreen(
            providerName = "MEGA Shared Link",
            startUrl = megaSharedWebUrl,
            onLibraries = {
                vm.closeMegaSharedWebLink()
                selectedProvider = null
                activeLibrary = null
            },
            onProviderOptions = { selectedProvider = "mega" }
        )
        return
    }

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

    LaunchedEffect(session?.authToken, selectedProvider) {
        if (session != null && selectedProvider == "pcloud" && !vm.loginInProgress && !vm.addingAccount) {
            selectedProvider = null
            activeLibrary = null
        }
    }

    // ---- Provider connection flows ----

    if (selectedProvider == "shared-link") {
        LoginScreen(
            error = vm.loginError,
            busy = vm.busy,
            onSignIn = { vm.startWebLogin() },
            onUseToken = {
                vm.useToken(it)
                activeLibrary = null
                selectedProvider = null
            },
            onOpenLink = { vm.openPublicLink(it) },
            onLibraries = { selectedProvider = null; activeLibrary = null }
        )
        return
    }

    if (selectedProvider == "add-service") {
        ProviderStartScreen(
            onOpenPCloud = { selectedProvider = "pcloud" },
            onOpenMega = { selectedProvider = if (vm.megaAccounts.isNotEmpty()) "mega-browser" else "mega" },
            onOpenDropbox = { selectedProvider = if (vm.dropboxAccounts.isNotEmpty()) "dropbox-browser" else "dropbox" },
            onOpenBox = { selectedProvider = if (vm.boxAccounts.isNotEmpty()) "box-browser" else "box" },
            onBackToLibraries = { selectedProvider = null; activeLibrary = null }
        )
        return
    }

    if (selectedProvider == "mega-web-login") {
        MegaWebLoginScreen(
            onSignedIn = { email ->
                vm.markMegaWebSignedIn(email)
                megaMessage = null
                selectedProvider = null
                activeLibrary = null
            },
            onCancel = { selectedProvider = "mega" }
        )
        return
    }



    if (selectedProvider == "dropbox-web-login") {
        DropboxWebLoginScreen(
            onSignedIn = { email ->
                vm.markDropboxWebSignedIn(email)
                selectedProvider = null
                activeLibrary = null
            },
            onCancel = { selectedProvider = "dropbox" }
        )
        return
    }



    if (selectedProvider == "box-web-login") {
        BoxWebLoginScreen(
            onSignedIn = { email ->
                vm.markBoxWebSignedIn(email)
                selectedProvider = null
                activeLibrary = null
            },
            onCancel = { selectedProvider = "box" }
        )
        return
    }

    if (selectedProvider == "mega-browser") {
        CloudWebBrowserScreen(
            providerName = "MEGA",
            startUrl = "https://mega.nz/fm",
            onLibraries = { selectedProvider = null; activeLibrary = null },
            onProviderOptions = { selectedProvider = "mega" }
        )
        return
    }

    if (selectedProvider == "dropbox-browser") {
        CloudWebBrowserScreen(
            providerName = "Dropbox",
            startUrl = "https://www.dropbox.com/home",
            onLibraries = { selectedProvider = null; activeLibrary = null },
            onProviderOptions = { selectedProvider = "dropbox" }
        )
        return
    }

    if (selectedProvider == "box-browser") {
        CloudWebBrowserScreen(
            providerName = "Box",
            startUrl = "https://app.box.com/folder/0",
            onLibraries = { selectedProvider = null; activeLibrary = null },
            onProviderOptions = { selectedProvider = "box" }
        )
        return
    }

    if (selectedProvider == "box") {
        BoxConnectScreen(
            boxAccounts = vm.boxAccounts,
            onBack = { selectedProvider = null },
            onLibraries = {
                selectedProvider = null
                activeLibrary = null
            },
            onSignInWithBox = { selectedProvider = "box-web-login" },
            onRemoveBoxAccount = vm::removeBoxAccount
        )
        return
    }

    if (selectedProvider == "dropbox") {
        DropboxConnectScreen(
            dropboxAccounts = vm.dropboxAccounts,
            onBack = { selectedProvider = null },
            onLibraries = {
                selectedProvider = null
                activeLibrary = null
            },
            onSignInWithDropbox = { selectedProvider = "dropbox-web-login" },
            onRemoveDropboxAccount = vm::removeDropboxAccount
        )
        return
    }

    if (selectedProvider == "mega") {
        MegaConnectScreen(
            megaAccounts = vm.megaAccounts,
            onBack = {
                megaMessage = null
                selectedProvider = null
            },
            onLibraries = {
                megaMessage = null
                selectedProvider = null
                activeLibrary = null
            },
            onSignInWithMega = { selectedProvider = "mega-web-login" },
            onRemoveMegaAccount = vm::removeMegaAccount,
            onOpenSharedMegaLink = { link ->
                vm.openPublicLink(link)
                megaMessage = null
            },
            initialMessage = megaMessage
        )
        return
    }

    if (vm.loginInProgress) {
        WebLoginScreen(
            onResult = { token ->
                vm.completeLogin(token)
                selectedProvider = null
                activeLibrary = null
            },
            onCancel = {
                vm.cancelLogin()
                selectedProvider = null
                activeLibrary = null
            }
        )
        return
    }

    if (session == null || vm.addingAccount || selectedProvider == "pcloud") {
        if (session == null && !vm.addingAccount && selectedProvider == null) {
            LibraryHomeScreen(
                pCloudAccounts = vm.accounts,
                megaAccounts = vm.megaAccounts,
                dropboxAccounts = vm.dropboxAccounts,
                boxAccounts = vm.boxAccounts,
                activeAccountId = vm.activeAccountId,
                onOpenPCloudAccount = { id ->
                    vm.switchAccount(id)
                    activeLibrary = "pcloud"
                },
                onAddPCloud = { selectedProvider = "pcloud" },
                onOpenMega = { selectedProvider = if (vm.megaAccounts.isNotEmpty()) "mega-browser" else "mega" },
                onOpenDropbox = { selectedProvider = if (vm.dropboxAccounts.isNotEmpty()) "dropbox-browser" else "dropbox" },
                onOpenBox = { selectedProvider = if (vm.boxAccounts.isNotEmpty()) "box-browser" else "box" },
                onOpenSharedLink = { selectedProvider = "shared-link" },
                onAddService = { selectedProvider = "add-service" }
            )
            return
        }

        LoginScreen(
            error = vm.loginError,
            busy = vm.busy,
            onSignIn = { vm.startWebLogin() },
            onUseToken = {
                vm.useToken(it)
                activeLibrary = null
            },
            onOpenLink = { vm.openPublicLink(it) },
            onLibraries = if (vm.addingAccount || session != null) {
                {
                    vm.cancelLogin()
                    selectedProvider = null
                    activeLibrary = null
                }
            } else null
        )
        return
    }

    // ---- Library hub: Cloud Player can hold more than one provider/library. ----
    if (activeLibrary != "pcloud") {
        LibraryHomeScreen(
            pCloudAccounts = vm.accounts,
            megaAccounts = vm.megaAccounts,
            dropboxAccounts = vm.dropboxAccounts,
            boxAccounts = vm.boxAccounts,
            activeAccountId = vm.activeAccountId,
            onOpenPCloudAccount = { id ->
                vm.switchAccount(id)
                activeLibrary = "pcloud"
            },
            onAddPCloud = { vm.beginAddAccount() },
            onOpenMega = { selectedProvider = if (vm.megaAccounts.isNotEmpty()) "mega-browser" else "mega" },
            onOpenDropbox = { selectedProvider = if (vm.dropboxAccounts.isNotEmpty()) "dropbox-browser" else "dropbox" },
            onOpenBox = { selectedProvider = if (vm.boxAccounts.isNotEmpty()) "box-browser" else "box" },
            onOpenSharedLink = { selectedProvider = "shared-link" },
            onAddService = { selectedProvider = "add-service" }
        )
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
            onLibraries = { activeLibrary = null },
            onLogout = {
                vm.logout()
                activeLibrary = null
            }
        )
    }
}
