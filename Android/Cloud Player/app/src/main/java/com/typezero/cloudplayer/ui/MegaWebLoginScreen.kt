package com.typezero.cloudplayer.ui

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.os.SystemClock
import android.view.KeyEvent
import android.view.MotionEvent
import android.webkit.CookieManager
import android.webkit.JavascriptInterface
import android.webkit.WebResourceRequest
import android.webkit.WebView
import android.webkit.WebViewClient
import android.widget.FrameLayout
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Button
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color as ComposeColor
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.viewinterop.AndroidView

/**
 * Opens MEGA's real login page so MEGA can handle password, 2FA, CAPTCHA,
 * account recovery, and any future auth changes itself. Cloud Player should not
 * try to reimplement MEGA's email/password/2FA flow.
 *
 * Once MEGA reaches its signed-in web app, Cloud Player saves a visible library
 * marker with the best account label it can detect. That marker is what makes
 * the Libraries screen say "MEGA • Logged in" instead of always showing
 * "MEGA • Not logged in" after a successful web sign-in.
 */
private const val MEGA_COOKIE_ACCEPT_JS =
    "(function(){try{var els=document.querySelectorAll('button,a,[role=button],span,div');" +
        "for(var i=0;i<els.length;i++){var t=(els[i].innerText||els[i].textContent||'')" +
        ".trim().toLowerCase();" +
        "if(t==='accept'||t==='accept all'||t==='i agree'||t==='got it'||t==='ok'){" +
        "els[i].click();return;}}}catch(e){}})();"

private const val MEGA_LOGIN_PROBE_JS = """
(function(){
    try {
        var href = String(location.href || '');
        var title = String(document.title || '');
        var text = (document.body && (document.body.innerText || document.body.textContent) || '');
        var lower = (href + '\n' + title + '\n' + text).toLowerCase();
        var logged = false;

        // MEGA is a single-page app. After password + 2FA it may not do a
        // normal page load, so do not rely only on /fm URLs. Check the public
        // router text plus MEGA's in-page globals used by the official web app.
        if (/mega\.(nz|co\.nz)\/(fm|#fm|folder|file)/i.test(href)) logged = true;
        if (lower.indexOf('cloud drive') >= 0) logged = true;
        if (lower.indexOf('rubbish bin') >= 0) logged = true;
        if (lower.indexOf('transfer manager') >= 0) logged = true;
        if (lower.indexOf('account settings') >= 0) logged = true;
        if (lower.indexOf('upgrade account') >= 0) logged = true;
        if (lower.indexOf('my account') >= 0 && lower.indexOf('logout') >= 0) logged = true;
        if (lower.indexOf('log out') >= 0 && lower.indexOf('cloud drive') >= 0) logged = true;

        var email = '';
        var re = /[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}/ig;
        function pick(s) {
            if (email || !s) return;
            var m = String(s).match(re);
            if (m && m.length) {
                for (var i = 0; i < m.length; i++) {
                    var e = m[i];
                    if (!/mega\.nz$/i.test(e) && !/mega\.co\.nz$/i.test(e) && !/^support@/i.test(e)) {
                        email = e;
                        return;
                    }
                }
                email = m[0];
            }
        }

        // Official MEGA web app globals. These are the most reliable signal
        // once the file-manager shell is loaded after 2FA.
        try {
            if (typeof u_type !== 'undefined' && Number(u_type) >= 3) logged = true;
            if (typeof u_handle !== 'undefined' && String(u_handle || '').length > 0) logged = true;
            if (typeof u_attr !== 'undefined' && u_attr) {
                logged = true;
                pick(u_attr.email || u_attr.name || JSON.stringify(u_attr));
            }
            if (typeof M !== 'undefined' && M) {
                if (M.account || M.RootID || M.RubbishID || M.InboxID) logged = true;
                try { pick(JSON.stringify(M.account || {})); } catch(e) {}
            }
        } catch(e) {}

        pick(text);
        try { for (var i = 0; i < localStorage.length; i++) { var k = localStorage.key(i); pick(k); pick(localStorage.getItem(k)); } } catch(e) {}
        try { for (var j = 0; j < sessionStorage.length; j++) { var sk = sessionStorage.key(j); pick(sk); pick(sessionStorage.getItem(sk)); } } catch(e) {}
        try {
            if (localStorage.getItem('sid') || localStorage.getItem('k') || localStorage.getItem('u_handle') || localStorage.getItem('u_attr')) logged = true;
            if (sessionStorage.getItem('sid') || sessionStorage.getItem('k') || sessionStorage.getItem('u_handle') || sessionStorage.getItem('u_attr')) logged = true;
        } catch(e) {}

        if (logged) window.AndroidMegaLogin.onMegaSignedIn(email || 'MEGA account', href);
    } catch(e) {}
})();
"""

private class MegaLoginBridge(
    private val webView: WebView,
    private val complete: (String?) -> Unit
) {
    @Volatile private var done = false

    @JavascriptInterface
    fun onMegaSignedIn(email: String?, url: String?) {
        if (done) return
        val lower = url.orEmpty().lowercase()
        val cleanEmail = email?.trim()?.takeIf { it.isNotBlank() }
        val looksSignedIn = lower.contains("mega.nz/fm") ||
            lower.contains("mega.nz/#fm") ||
            lower.contains("/fm") ||
            lower.contains("#fm") ||
            lower.contains("mega.nz/folder") ||
            lower.contains("mega.nz/file") ||
            cleanEmail != null
        if (!looksSignedIn) return
        done = true
        webView.post { complete(cleanEmail) }
    }
}

private class MegaTvCursorWebView(context: Context) : FrameLayout(context) {
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

@SuppressLint("SetJavaScriptEnabled", "JavascriptInterface")
@Composable
fun MegaWebLoginScreen(
    onSignedIn: (String?) -> Unit,
    onCancel: () -> Unit
) {
    BackHandler { onCancel() }

    Box(modifier = Modifier.fillMaxSize()) {
        AndroidView(
            modifier = Modifier.fillMaxSize(),
            factory = { ctx ->
                val frame = MegaTvCursorWebView(ctx)
                val web = frame.web
                web.settings.javaScriptEnabled = true
                web.settings.domStorageEnabled = true
                CookieManager.getInstance().setAcceptCookie(true)
                CookieManager.getInstance().setAcceptThirdPartyCookies(web, true)

                fun probeSignedIn() {
                    web.evaluateJavascript(MEGA_LOGIN_PROBE_JS, null)
                }

                web.addJavascriptInterface(MegaLoginBridge(web) { email -> onSignedIn(email) }, "AndroidMegaLogin")

                web.webViewClient = object : WebViewClient() {
                    override fun shouldOverrideUrlLoading(view: WebView, request: WebResourceRequest): Boolean {
                        view.postDelayed({ probeSignedIn() }, 600)
                        return false
                    }

                    override fun onPageFinished(view: WebView, url: String?) {
                        view.evaluateJavascript(MEGA_COOKIE_ACCEPT_JS, null)
                        probeSignedIn()
                    }
                }

                web.loadUrl("https://mega.nz/login")
                // MEGA is a single-page web app. Successful login/2FA can change
                // hash/router state without triggering a normal page load, so poll
                // briefly and let the JS bridge complete the flow when it sees the
                // file manager or an account email.
                fun schedulePoll(remaining: Int) {
                    if (remaining <= 0) return
                    web.postDelayed({
                        probeSignedIn()
                        schedulePoll(remaining - 1)
                    }, 1500L)
                }
                schedulePoll(200)

                frame.post { frame.requestFocus() }
                frame
            }
        )

        Column(
            modifier = Modifier
                .align(Alignment.BottomCenter)
                .padding(16.dp)
                .clip(RoundedCornerShape(10.dp))
                .background(ComposeColor(0xCC000000))
                .padding(horizontal = 14.dp, vertical = 8.dp),
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            Text(
                "Use the D-pad to move the pointer · OK to click · Back to cancel",
                color = ComposeColor.White,
                fontSize = 12.sp
            )
            Button(
                onClick = { onSignedIn("MEGA account") },
                modifier = Modifier.padding(top = 8.dp)
            ) {
                Text("Done — save MEGA login")
            }
        }
    }
}
