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
import android.webkit.WebChromeClient
import android.webkit.WebView
import android.webkit.WebViewClient
import android.widget.FrameLayout
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.ArrowBack
import androidx.compose.material.icons.rounded.CloudQueue
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color as ComposeColor
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.viewinterop.AndroidView

private class CloudBrowserCursorWebView(context: Context) : FrameLayout(context) {
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

@SuppressLint("SetJavaScriptEnabled")
@Composable
fun CloudWebBrowserScreen(
    providerName: String,
    startUrl: String,
    onLibraries: () -> Unit,
    onProviderOptions: () -> Unit
) {
    val webRef = remember { mutableStateOf<WebView?>(null) }

    // In provider browsing mode, Back is app navigation, not website navigation.
    // This keeps Android TV users from getting trapped in Dropbox/MEGA web history.
    BackHandler { onLibraries() }

    Box(modifier = Modifier.fillMaxSize().background(ComposeColor.Black)) {
        AndroidView(
            modifier = Modifier.fillMaxSize(),
            factory = { ctx ->
                val frame = CloudBrowserCursorWebView(ctx)
                val web = frame.web
                webRef.value = web
                web.settings.javaScriptEnabled = true
                web.settings.domStorageEnabled = true
                web.settings.databaseEnabled = true
                web.settings.loadWithOverviewMode = true
                web.settings.useWideViewPort = true
                web.settings.mediaPlaybackRequiresUserGesture = false
                CookieManager.getInstance().setAcceptCookie(true)
                CookieManager.getInstance().setAcceptThirdPartyCookies(web, true)
                web.webChromeClient = WebChromeClient()
                web.webViewClient = object : WebViewClient() {
                    override fun onPageFinished(view: WebView, url: String?) {
                        super.onPageFinished(view, url)
                        view.evaluateJavascript(providerCleanUpJavaScript(providerName), null)
                    }
                }
                web.loadUrl(startUrl)
                frame.post { frame.requestFocus() }
                frame
            }
        )

        Row(
            modifier = Modifier
                .align(Alignment.TopStart)
                .padding(10.dp)
                .clip(RoundedCornerShape(999.dp))
                .background(ComposeColor(0x99000000))
                .clickable { onLibraries() }
                .padding(horizontal = 12.dp, vertical = 7.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Icon(Icons.Rounded.CloudQueue, contentDescription = null, tint = ComposeColor.White, modifier = Modifier.size(18.dp))
            Spacer(Modifier.size(7.dp))
            Text(
                text = "Libraries",
                color = ComposeColor.White,
                fontSize = 14.sp,
                fontWeight = FontWeight.Bold,
                modifier = Modifier.padding(end = 14.dp)
            )
            Icon(Icons.Rounded.ArrowBack, contentDescription = null, tint = ComposeColor.White, modifier = Modifier.size(16.dp))
            Spacer(Modifier.size(6.dp))
            Text(
                text = providerName,
                color = ComposeColor.White,
                fontSize = 14.sp,
                fontWeight = FontWeight.Bold
            )
        }
    }
}

private fun providerCleanUpJavaScript(providerName: String): String {
    val provider = providerName.lowercase()
    return if (provider.contains("dropbox")) {
        """
        (function(){
          var style = document.getElementById('cloudplayer-clean-web');
          if (!style) {
            style = document.createElement('style');
            style.id = 'cloudplayer-clean-web';
            style.innerHTML = `
              /* Keep the real Dropbox file list visible. Only hide obvious promos. */
              div[class*=upgrade],
              div[class*=Upgrade],
              div[class*=promo],
              div[class*=Promo],
              div[class*=onboarding],
              div[class*=Onboarding] {
                display: none !important;
                visibility: hidden !important;
              }
              body { overflow: auto !important; }
            `;
            document.head.appendChild(style);
          }

          Array.from(document.querySelectorAll('button, a, div, section')).forEach(function(el){
            var text = (el.innerText || '').toLowerCase();
            if (
              text.indexOf('upgrade to dropbox') >= 0 ||
              text.indexOf('compare plans') >= 0 ||
              text.indexOf('create your free account') >= 0 ||
              text.indexOf('not today') >= 0
            ) {
              var box = el.closest('section') ||
                        el.closest('div[class*=modal]') ||
                        el.closest('div[class*=banner]') ||
                        el.closest('div[class*=promo]') ||
                        el;
              box.style.display = 'none';
              box.style.visibility = 'hidden';
            }
          });
        })();
        """.trimIndent()
    } else {
        """
        (function(){
          var style = document.getElementById('cloudplayer-clean-web');
          if (!style) {
            style = document.createElement('style');
            style.id = 'cloudplayer-clean-web';
            style.innerHTML = `
              body { overflow: auto !important; }
            `;
            document.head.appendChild(style);
          }
        })();
        """.trimIndent()
    }
}
