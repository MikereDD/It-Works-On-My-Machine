package com.typezero.cloudplayer.ui

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.view.KeyEvent
import android.view.MotionEvent
import android.webkit.CookieManager
import android.webkit.WebResourceError
import android.webkit.WebResourceRequest
import android.webkit.WebResourceResponse
import android.webkit.WebView
import android.webkit.WebViewClient
import android.widget.FrameLayout
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color as ComposeColor
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.viewinterop.AndroidView

/**
 * Opens pCloud's real web login (my.pcloud.com) in a WebView. The user signs in
 * there — including any 2FA — and we capture the account's access token from the
 * authenticated session (the "auth" parameter on its API calls, or localStorage).
 *
 * Android TV / Google TV have no touchscreen and pCloud's web page can't be driven
 * by the D-pad, so the WebView is wrapped in [TvCursorWebView]: the remote moves a
 * pointer and OK taps, exactly like a mouse. Text fields then open the on-screen
 * keyboard as usual.
 */
private val PCLOUD_LOGIN_URLS = listOf(
    "https://my.pcloud.com/#page=login",
    "https://my.pcloud.com//#page=login",
    "https://www.pcloud.com/#page=login",
    "https://u.pcloud.com/#page=login"
)

private const val COOKIE_ACCEPT_JS =
    "(function(){try{var els=document.querySelectorAll('button,a,[role=button],span,div');" +
        "for(var i=0;i<els.length;i++){var t=(els[i].innerText||els[i].textContent||'')" +
        ".trim().toLowerCase();" +
        "if(t==='i accept'||t==='accept'||t==='accept all'||t==='i agree'||t==='got it'||t==='ok'){" +
        "els[i].click();return;}}}catch(e){}})();"

/** FrameLayout that hosts a WebView and overlays a D-pad-driven mouse cursor. */
private class TvCursorWebView(context: Context) : FrameLayout(context) {
    val web = WebView(context)
    private var cx = -1f
    private var cy = -1f
    private val step = resources.displayMetrics.density * 36f
    private val fill = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = Color.WHITE }
    private val ring = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.BLACK
        style = Paint.Style.STROKE
        strokeWidth = 3f
    }

    init {
        addView(web, LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.MATCH_PARENT))
        isFocusable = true
        isFocusableInTouchMode = true
    }

    override fun onSizeChanged(w: Int, h: Int, ow: Int, oh: Int) {
        super.onSizeChanged(w, h, ow, oh)
        if (cx < 0f) { cx = w / 2f; cy = h / 2f }
        invalidate()
    }

    private fun tap(x: Float, y: Float) {
        val t = SystemClock.uptimeMillis()
        val down = MotionEvent.obtain(t, t, MotionEvent.ACTION_DOWN, x, y, 0)
        val up = MotionEvent.obtain(t, t + 60, MotionEvent.ACTION_UP, x, y, 0)
        web.dispatchTouchEvent(down)
        web.dispatchTouchEvent(up)
        down.recycle()
        up.recycle()
    }

    // Intercept D-pad here, before the focused child (WebView/input) sees it, so the
    // cursor keeps working even after a text field grabs focus. The soft keyboard
    // runs in its own window, so typing is unaffected. BACK is left to propagate.
    override fun dispatchKeyEvent(event: KeyEvent): Boolean {
        val code = event.keyCode
        val isDpad = code == KeyEvent.KEYCODE_DPAD_LEFT ||
            code == KeyEvent.KEYCODE_DPAD_RIGHT ||
            code == KeyEvent.KEYCODE_DPAD_UP ||
            code == KeyEvent.KEYCODE_DPAD_DOWN ||
            code == KeyEvent.KEYCODE_DPAD_CENTER ||
            code == KeyEvent.KEYCODE_ENTER ||
            code == KeyEvent.KEYCODE_NUMPAD_ENTER
        if (!isDpad) return super.dispatchKeyEvent(event)
        if (event.action == KeyEvent.ACTION_DOWN) {
            when (code) {
                KeyEvent.KEYCODE_DPAD_LEFT -> cx = (cx - step).coerceAtLeast(0f)
                KeyEvent.KEYCODE_DPAD_RIGHT -> cx = (cx + step).coerceAtMost(width.toFloat())
                KeyEvent.KEYCODE_DPAD_UP -> cy = (cy - step).coerceAtLeast(0f)
                KeyEvent.KEYCODE_DPAD_DOWN -> cy = (cy + step).coerceAtMost(height.toFloat())
                else -> tap(cx, cy)
            }
            invalidate()
        }
        return true
    }

    override fun dispatchDraw(canvas: Canvas) {
        super.dispatchDraw(canvas)
        if (cx >= 0f) {
            canvas.drawCircle(cx, cy, 11f, fill)
            canvas.drawCircle(cx, cy, 11f, ring)
        }
    }
}

@SuppressLint("SetJavaScriptEnabled")
@Composable
fun WebLoginScreen(
    onResult: (token: String) -> Unit,
    onCancel: () -> Unit
) {
    BackHandler { onCancel() }

    Box(modifier = Modifier.fillMaxSize()) {
        AndroidView(
            modifier = Modifier.fillMaxSize(),
            factory = { ctx ->
                val frame = TvCursorWebView(ctx)
                val web = frame.web
                web.settings.javaScriptEnabled = true
                web.settings.domStorageEnabled = true
                CookieManager.getInstance().setAcceptCookie(true)
                CookieManager.getInstance().setAcceptThirdPartyCookies(web, true)

                var done = false
                var loginUrlIndex = 0
                val main = Handler(Looper.getMainLooper())

                fun loadPCloudLogin(reason: String? = null) {
                    val url = PCLOUD_LOGIN_URLS.getOrElse(loginUrlIndex) { PCLOUD_LOGIN_URLS.last() }
                    web.loadUrl(url)
                }

                fun tryNextPCloudLoginUrl() {
                    if (loginUrlIndex < PCLOUD_LOGIN_URLS.lastIndex) {
                        loginUrlIndex += 1
                        loadPCloudLogin()
                    }
                }

                fun deliver(token: String?) {
                    if (done || token.isNullOrBlank() || token.length < 20) return
                    done = true
                    main.post { onResult(token) }
                }

                web.webViewClient = object : WebViewClient() {
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
                        return null
                    }

                    override fun onReceivedError(
                        view: WebView,
                        request: WebResourceRequest,
                        error: WebResourceError
                    ) {
                        super.onReceivedError(view, request, error)
                        if (!done && request.isForMainFrame) {
                            tryNextPCloudLoginUrl()
                        }
                    }

                    override fun onPageFinished(view: WebView, url: String?) {
                        view.evaluateJavascript(COOKIE_ACCEPT_JS, null)
                        main.postDelayed({ view.evaluateJavascript(COOKIE_ACCEPT_JS, null) }, 800)
                        main.postDelayed({ view.evaluateJavascript(COOKIE_ACCEPT_JS, null) }, 2000)

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

                // Start on pCloud's login route, not the root web app.  Some Android
                // WebView builds currently get net::ERR_CONNECTION_RESET from
                // https://my.pcloud.com/ directly, so we try known pCloud login
                // entry points before giving up.
                loadPCloudLogin()
                frame.post { frame.requestFocus() }
                frame
            }
        )

        // Hint so TV users know the remote drives a pointer here.
        Text(
            "Use the D-pad to move the pointer · OK to click · Back to cancel",
            color = ComposeColor.White,
            fontSize = 12.sp,
            modifier = Modifier
                .align(Alignment.BottomCenter)
                .padding(16.dp)
                .clip(RoundedCornerShape(10.dp))
                .background(ComposeColor(0xCC000000))
                .padding(horizontal = 14.dp, vertical = 8.dp)
        )
    }
}
