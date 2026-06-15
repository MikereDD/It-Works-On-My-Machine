package com.typezero.seraph.ui.theme

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable

private val DarkColors = darkColorScheme(
    primary = Teal,
    onPrimary = Slate900,
    secondary = Violet,
    onSecondary = Slate900,
    tertiary = Amber,
    background = Slate900,
    onBackground = SlateText,
    surface = Slate850,
    onSurface = SlateText,
    surfaceVariant = Slate800,
    onSurfaceVariant = SlateMuted,
    outline = Slate700,
)

private val LightColors = lightColorScheme(
    primary = androidx.compose.ui.graphics.Color(0xFF0F766E),
    secondary = Violet,
    tertiary = Amber,
)

@Composable
fun SeraphTheme(
    darkTheme: Boolean = isSystemInDarkTheme(),
    content: @Composable () -> Unit,
) {
    // Brand reads best dark; light is a sensible fallback only.
    val scheme = if (darkTheme) DarkColors else LightColors
    MaterialTheme(
        colorScheme = scheme,
        typography = Typography,
        content = content,
    )
}
