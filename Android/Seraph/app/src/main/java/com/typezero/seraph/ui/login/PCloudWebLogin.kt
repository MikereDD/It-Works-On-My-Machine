package com.typezero.seraph.ui.login

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
 * there exactly as they would in a browser — Google sign-in and 2FA included —
 * and we capture the account's auth token straight from the authenticated session:
 * either the `auth` parameter pCloud's web app puts on its API calls, or a token
 * value sitting in localStorage. No app key, OAuth app, or redirect involved.
 *
 * (This mirrors the proven approach from the pCloud TV app.)
 */
private const val COOKIE_ACCEPT_JS =
    "(function(){try{var els=document.querySelectorAll('button,a,[role=button],span,div');" +
        "for(var i=0;i<els.length;i++){var t=(els[i].innerText||els[i].textContent||'')" +
        ".trim().toLowerCase();" +
        "if(t==='i accept'||t==='accept'||t==='accept all'||t==='i agree'||t==='got it'||t==='ok'){" +
        "els[i].click();return;}}}catch(e){}})();"

private const val LOCALSTORAGE_TOKEN_JS =
    "(function(){try{var ks=Object.keys(localStorage);" +
        "for(var i=0;i<ks.length;i++){var v=localStorage.getItem(ks[i]);" +
        "if(v&&/^[A-Za-z0-9]{20,}/.test(v)){return v;}}}catch(e){}return '';})();"

@SuppressLint("SetJavaScriptEnabled")
@Composable
fun PCloudWebLogin(
    onResult: (token: String) -> Unit,
    onCancel: () -> Unit,
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
                    override fun shouldInterceptRequest(
                        view: WebView,
                        request: WebResourceRequest,
                    ): WebResourceResponse? {
                        val u = request.url
                        val host = u.host ?: ""
                        if (!done && (host == "api.pcloud.com" || host == "eapi.pcloud.com")) {
                            val auth = u.getQueryParameter("auth")
                            if (!auth.isNullOrBlank()) deliver(auth)
                        }
                        return null
                    }

                    override fun onPageFinished(view: WebView, url: String?) {
                        view.evaluateJavascript(COOKIE_ACCEPT_JS, null)
                        main.postDelayed({ view.evaluateJavascript(COOKIE_ACCEPT_JS, null) }, 800)
                        if (done) return
                        view.evaluateJavascript(LOCALSTORAGE_TOKEN_JS) { res -> deliver(res?.trim('"')) }
                    }
                }

                loadUrl("https://my.pcloud.com/")
            }
        },
    )
}
