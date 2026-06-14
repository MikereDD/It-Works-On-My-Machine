package com.typezero.siphon

import android.Manifest
import android.content.Intent
import android.os.Build
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.result.contract.ActivityResultContracts
import androidx.activity.viewModels
import androidx.core.content.ContextCompat
import android.content.pm.PackageManager
import com.typezero.siphon.ui.SiphonViewModel
import com.typezero.siphon.ui.Tab
import com.typezero.siphon.ui.screens.SiphonRoot
import com.typezero.siphon.ui.theme.SiphonTheme

class MainActivity : ComponentActivity() {

    private val container by lazy { (application as SiphonApp).container }
    private val vm: SiphonViewModel by viewModels { SiphonViewModel.Factory(container) }

    private val permission =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU)
            Manifest.permission.READ_MEDIA_VIDEO else Manifest.permission.READ_EXTERNAL_STORAGE

    private val requestPermission =
        registerForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
            vm.onPermissionResult(granted)
        }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        if (hasPermission()) vm.onPermissionResult(true)
        handleShareIntent(intent)

        setContent {
            SiphonTheme {
                SiphonRoot(vm = vm, onRequestPermission = { requestPermission.launch(permission) })
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handleShareIntent(intent)
    }

    private fun hasPermission(): Boolean =
        ContextCompat.checkSelfPermission(this, permission) == PackageManager.PERMISSION_GRANTED

    /** If a link was shared into Siphon, prefill the Link tab. */
    private fun handleShareIntent(intent: Intent?) {
        if (intent?.action == Intent.ACTION_SEND && intent.type == "text/plain") {
            intent.getStringExtra(Intent.EXTRA_TEXT)?.let { shared ->
                vm.setLinkUrl(shared.trim())
                vm.selectTab(Tab.LINK)
            }
        }
    }
}
