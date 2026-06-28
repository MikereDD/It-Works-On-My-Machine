package com.typezero.cloudplayer.ui.theme

import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Typography
import androidx.compose.material3.darkColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color

/** Brand palette + reusable design tokens — Cadence-style monochrome console. */
object Brand {
    val Bg = Color(0xFF0A0A0C)
    val BgElevated = Color(0xFF131318)
    val Surface = Color(0xFF17181C)
    val SurfaceFocused = Color(0xFF24252B)
    val Stroke = Color(0xFF2B2C32)

    val Accent = Color(0xFFEAEAEE)      // near-white monochrome accent
    val AccentSoft = Color(0xFFC6C6CE)
    val Glow = Color(0xFFB4B4BC)        // light-gray glow accent

    val TextHi = Color(0xFFF3F3F6)
    val TextMid = Color(0xFF97979F)
    val TextLow = Color(0xFF63646C)

    // File-type accents — desaturated to neutral grays, subtle tonal difference only
    val Folder = Color(0xFFD7D7DE)
    val Video = Color(0xFFB0B0B8)
    val Audio = Color(0xFFC6C6CE)

    /** Atmospheric page background: near-black with a faint top lift. */
    val pageGradient = Brush.verticalGradient(
        0f to Color(0xFF17181C),
        0.45f to Bg,
        1f to Color(0xFF050506)
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
    onPrimary = Color(0xFF0A0A0C),
    secondary = Brand.Glow,
    onSecondary = Color(0xFF0A0A0C),
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
fun CloudPlayerTheme(content: @Composable () -> Unit) {
    MaterialTheme(
        colorScheme = PCloudColors,
        typography = Typography(),
        content = content
    )
}
