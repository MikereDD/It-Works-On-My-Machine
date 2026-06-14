package com.typezero.siphon.ui.theme

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color

private val Teal = Color(0xFF1CC8B4)
private val Indigo = Color(0xFF282E78)

private val DarkColors = darkColorScheme(
    primary = Teal,
    onPrimary = Color(0xFF06231F),
    secondary = Color(0xFF8AB4FF),
    background = Color(0xFF0E1014),
    surface = Color(0xFF161A20),
    surfaceVariant = Color(0xFF222730),
    onBackground = Color(0xFFE6EAF0),
    onSurface = Color(0xFFE6EAF0)
)

private val LightColors = lightColorScheme(
    primary = Indigo,
    secondary = Color(0xFF1CC8B4),
    background = Color(0xFFF7F8FA),
    surface = Color(0xFFFFFFFF)
)

@Composable
fun SiphonTheme(content: @Composable () -> Unit) {
    MaterialTheme(
        colorScheme = if (isSystemInDarkTheme()) DarkColors else LightColors,
        content = content
    )
}
