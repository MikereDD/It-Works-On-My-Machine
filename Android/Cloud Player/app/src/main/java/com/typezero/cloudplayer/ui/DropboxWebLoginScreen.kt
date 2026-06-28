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
import android.webkit.JavascriptInterface
import android.webkit.WebView
import android.webkit.WebViewClient
import android.widget.FrameLayout
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Button
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color as ComposeColor
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.viewinterop.AndroidView

private const val DROPBOX_LOGIN_PROBE_JS = """
(function(){
  try {
    var href = String(location.href || '');
    var title = String(document.title || '');
    var text = (document.body && (document.body.innerText || document.body.textContent) || '');
    var lower = (href + '\n' + title + '\n' + text).toLowerCase();
    var logged = false;
    var inTwoFactor =
      lower.indexOf('two-step') >= 0 || lower.indexOf('two factor') >= 0 ||
      lower.indexOf('2-step') >= 0 || lower.indexOf('2fa') >= 0 ||
      lower.indexOf('security code') >= 0 || lower.indexOf('verification code') >= 0 ||
      lower.indexOf('enter code') >= 0 || lower.indexOf('authenticator') >= 0;
    var stillSigningIn =
      lower.indexOf('sign in') >= 0 || lower.indexOf('log in') >= 0 ||
      lower.indexOf('email') >= 0 && lower.indexOf('password') >= 0;
    if (!inTwoFactor) {
      if (href.indexOf('dropbox.com/home') >= 0) logged = true;
      if (href.indexOf('dropbox.com/h') >= 0) logged = true;
      if (href.indexOf('dropbox.com/files') >= 0) logged = true;
      if (lower.indexOf('dropbox') >= 0 && lower.indexOf('files') >= 0 && !stillSigningIn) logged = true;
      if (lower.indexOf('upload files') >= 0 || lower.indexOf('new folder') >= 0) logged = true;
    }
    var email = '';
    var m = text.match(/[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}/ig);
    if (m && m.length) email = m[0];
    if (logged) window.AndroidDropboxLogin.onDropboxSignedIn(email || 'Dropbox account', href);
  } catch(e) {}
})();
"""

private class DropboxLoginBridge(
    private val webView: WebView,
    private val complete: (String?) -> Unit
) {
    @Volatile private var done = false

    @JavascriptInterface
    fun onDropboxSignedIn(email: String?, url: String?) {
        if (done) return
        val cleanEmail = email?.trim()?.takeIf { it.isNotBlank() }
        done = true
        webView.post { complete(cleanEmail) }
    }
}

private class DropboxTvCursorWebView(context: Context) : FrameLayout(context) {
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
        val isDpad = code == KeyEvent.KEYCODE_DPAD_LEFT || code == KeyEvent.KEYCODE_DPAD_RIGHT ||
            code == KeyEvent.KEYCODE_DPAD_UP || code == KeyEvent.KEYCODE_DPAD_DOWN ||
            code == KeyEvent.KEYCODE_DPAD_CENTER || code == KeyEvent.KEYCODE_ENTER ||
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
fun DropboxWebLoginScreen(
    onSignedIn: (String?) -> Unit,
    onCancel: () -> Unit
) {
    BackHandler { onCancel() }

    Box(modifier = Modifier.background(ComposeColor.Black)) {
        AndroidView(
            modifier = Modifier.matchParentSize(),
            factory = { ctx ->
                val frame = DropboxTvCursorWebView(ctx)
                val web = frame.web
                web.settings.javaScriptEnabled = true
                web.settings.domStorageEnabled = true
                CookieManager.getInstance().setAcceptCookie(true)
                CookieManager.getInstance().setAcceptThirdPartyCookies(web, true)

                val main = Handler(Looper.getMainLooper())
                val bridge = DropboxLoginBridge(web) { email -> main.post { onSignedIn(email) } }
                web.addJavascriptInterface(bridge, "AndroidDropboxLogin")
                web.webViewClient = object : WebViewClient() {
                    override fun onPageFinished(view: WebView, url: String?) {
                        fun probe() = view.evaluateJavascript(DROPBOX_LOGIN_PROBE_JS, null)
                        probe()
                        main.postDelayed({ probe() }, 1200)
                        main.postDelayed({ probe() }, 3000)
                    }
                }
                web.loadUrl("https://www.dropbox.com/login")
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
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            Text("Use D-pad pointer · OK to click · Back to cancel", color = ComposeColor.White, fontSize = 12.sp)
            Text("Dropbox 2FA: finish the code/authenticator step here, then save.", color = ComposeColor.White, fontSize = 12.sp)
            Button(onClick = { onSignedIn(null) }) { Text("Done — save Dropbox after 2FA") }
        }
    }
}
