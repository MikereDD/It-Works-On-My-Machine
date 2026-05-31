package com.typezero.pcloudtv.ui.theme

import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color

private val PCloudColors = darkColorScheme(
    primary = Color(0xFF4FA3FF),
    onPrimary = Color(0xFF00121F),
    secondary = Color(0xFF89C2FF),
    background = Color(0xFF0B0E14),
    onBackground = Color(0xFFE6EAF2),
    surface = Color(0xFF151A24),
    onSurface = Color(0xFFE6EAF2),
    surfaceVariant = Color(0xFF222A38),
    onSurfaceVariant = Color(0xFFB9C3D6),
)

@Composable
fun PCloudTVTheme(content: @Composable () -> Unit) {
    // TV apps render dark regardless of the system setting.
    MaterialTheme(colorScheme = PCloudColors, content = content)
}
