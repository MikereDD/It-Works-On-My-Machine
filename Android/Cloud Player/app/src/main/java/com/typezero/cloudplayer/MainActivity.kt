package com.typezero.cloudplayer

import android.os.Bundle
import androidx.fragment.app.FragmentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.ui.Modifier
import com.typezero.cloudplayer.ui.App
import com.typezero.cloudplayer.ui.theme.CloudPlayerTheme

class MainActivity : FragmentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Initialize Cast early so device discovery starts and the Cast button
        // populates as soon as a Chromecast / Google TV is on the network.
        runCatching {
            com.google.android.gms.cast.framework.CastContext.getSharedInstance(applicationContext)
        }
        setContent {
            CloudPlayerTheme {
                Surface(
                    modifier = Modifier
                        .fillMaxSize()
                        .background(MaterialTheme.colorScheme.background),
                    color = MaterialTheme.colorScheme.background
                ) {
                    App()
                }
            }
        }
    }
}
