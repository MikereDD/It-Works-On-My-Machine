package com.typezero.atomicclock

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.Surface
import androidx.compose.ui.Modifier
import com.typezero.atomicclock.ui.AtomicClockScreen
import com.typezero.atomicclock.ui.theme.AtomicClockTheme
import com.typezero.atomicclock.widget.WidgetWork

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        enableEdgeToEdge()
        super.onCreate(savedInstanceState)
        WidgetWork.ensureScheduled(this)
        setContent {
            AtomicClockTheme {
                Surface(modifier = Modifier.fillMaxSize()) {
                    AtomicClockScreen()
                }
            }
        }
    }
}
