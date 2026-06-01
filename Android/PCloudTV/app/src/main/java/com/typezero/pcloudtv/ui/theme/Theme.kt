package com.typezero.pcloudtv.ui.theme

import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Typography
import androidx.compose.material3.darkColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color

/** Brand palette + reusable design tokens for a dark "media console" look. */
object Brand {
    val Bg = Color(0xFF070A12)
    val BgElevated = Color(0xFF0E1320)
    val Surface = Color(0xFF141B2A)
    val SurfaceFocused = Color(0xFF1E2A40)
    val Stroke = Color(0xFF243049)

    val Accent = Color(0xFF5BB8FF)      // primary blue
    val AccentSoft = Color(0xFF8FD0FF)
    val Glow = Color(0xFF34E0C4)        // teal glow accent

    val TextHi = Color(0xFFEAF1FC)
    val TextMid = Color(0xFF9DAAC4)
    val TextLow = Color(0xFF63718C)

    // File-type accents
    val Folder = Color(0xFFFFB454)
    val Video = Color(0xFF5BB8FF)
    val Audio = Color(0xFF34E0C4)

    /** Atmospheric page background: deep navy with a soft top glow. */
    val pageGradient = Brush.verticalGradient(
        0f to Color(0xFF0B1322),
        0.45f to Bg,
        1f to Color(0xFF05070D)
    )

    /** Scrim behind player controls. */
    val controlScrim = Brush.verticalGradient(
        0f to Color(0x00000000),
        0.55f to Color(0x66000000),
        1f to Color(0xCC000000)
    )
}

private val PCloudColors = darkColorScheme(
    primary = Brand.Accent,
    onPrimary = Color(0xFF04121F),
    secondary = Brand.Glow,
    onSecondary = Color(0xFF002019),
    background = Brand.Bg,
    onBackground = Brand.TextHi,
    surface = Brand.Surface,
    onSurface = Brand.TextHi,
    surfaceVariant = Brand.SurfaceFocused,
    onSurfaceVariant = Brand.TextMid,
    outline = Brand.Stroke,
    error = Color(0xFFFF6B6B),
)

@Composable
fun PCloudTVTheme(content: @Composable () -> Unit) {
    MaterialTheme(
        colorScheme = PCloudColors,
        typography = Typography(),
        content = content
    )
}
