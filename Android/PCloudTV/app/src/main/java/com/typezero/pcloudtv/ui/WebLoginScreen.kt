package com.typezero.pcloudtv.ui

import android.annotation.SuppressLint
import android.os.Handler
import android.os.Looper
import android.webkit.CookieManager
import android.webkit.WebResourceRequest
import android.webkit.WebResourceResponse
import android.webkit.WebView
import android.webkit.WebViewClient
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.viewinterop.AndroidView

/**
 * Opens pCloud's real web login (my.pcloud.com) in a WebView. The user signs in
 * there — including any 2FA — and we capture the account's access token from the
 * authenticated session, either from the "auth" parameter the web app attaches to
 * its API calls, or from localStorage as a fallback. The token is then validated
 * and stored by the ViewModel.
 *
 * This is a pragmatic approach that relies on pCloud's web client behaviour
 * (pCloud has disabled new OAuth app registration, so the official flow isn't
 * currently available).
 */
@SuppressLint("SetJavaScriptEnabled")
@Composable
fun WebLoginScreen(
    onResult: (token: String) -> Unit,
    onCancel: () -> Unit
) {
    BackHandler { onCancel() }

    AndroidView(
        modifier = Modifier.fillMaxSize(),
        factory = { ctx ->
            WebView(ctx).apply {
                settings.javaScriptEnabled = true
                settings.domStorageEnabled = true
                CookieManager.getInstance().setAcceptCookie(true)
                CookieManager.getInstance().setAcceptThirdPartyCookies(this, true)

                var done = false
                val main = Handler(Looper.getMainLooper())

                fun deliver(token: String?) {
                    if (done || token.isNullOrBlank() || token.length < 20) return
                    done = true
                    main.post { onResult(token) }
                }

                webViewClient = object : WebViewClient() {
                    // Catch the token from the web app's authenticated API calls.
                    override fun shouldInterceptRequest(
                        view: WebView,
                        request: WebResourceRequest
                    ): WebResourceResponse? {
                        val u = request.url
                        val host = u.host ?: ""
                        if (!done && (host == "api.pcloud.com" || host == "eapi.pcloud.com")) {
                            val auth = u.getQueryParameter("auth")
                            if (!auth.isNullOrBlank()) deliver(auth)
                        }
                        return null // let the request proceed
                    }

                    // Fallback: scan localStorage for a token-looking value.
                    override fun onPageFinished(view: WebView, url: String?) {
                        if (done) return
                        view.evaluateJavascript(
                            "(function(){try{var ks=Object.keys(localStorage);" +
                                "for(var i=0;i<ks.length;i++){var v=localStorage.getItem(ks[i]);" +
                                "if(v&&/^[A-Za-z0-9]{20,}/.test(v)){return v;}}}catch(e){}return '';})();"
                        ) { res ->
                            deliver(res?.trim('"'))
                        }
                    }
                }

                loadUrl("https://my.pcloud.com/")
            }
        }
    )
}
