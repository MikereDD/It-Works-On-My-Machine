/*
 * file:    Theme.kt
 * author:  Mike Redd (typezero)
 * version: 0.6.0
 * desc:    Resound's visual identity — a "darkroom for sound". Deep ink
 *          background, signal-teal accent pulled from the waveform colour, amber
 *          reserved for the live record state, monospace for timecodes. Always
 *          dark; an audio editor lives in the dark.
 */
package com.typezero.resound.ui.theme

import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Shapes
import androidx.compose.material3.Typography
import androidx.compose.material3.darkColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

// ---- Palette ---------------------------------------------------------------
val Ink        = Color(0xFF0A0E14) // app background
val Panel       = Color(0xFF121A24) // cards, lanes
val PanelHi     = Color(0xFF1B2733) // elevated, clip bodies, fields
val Line        = Color(0xFF243140) // hairlines, borders
val Signal      = Color(0xFF35D0C0) // primary accent (the waveform brand)
val SignalDeep  = Color(0xFF0E8C82) // dim / pressed
val Amber        = Color(0xFFF5A623) // record / active
val TextHi      = Color(0xFFE8EEF2)
val TextLo      = Color(0xFF8597A6)

private val ResoundColors = darkColorScheme(
    primary = Signal,
    onPrimary = Ink,
    primaryContainer = SignalDeep,
    onPrimaryContainer = TextHi,
    secondary = Amber,
    onSecondary = Ink,
    tertiary = Amber,
    background = Ink,
    onBackground = TextHi,
    surface = Panel,
    onSurface = TextHi,
    surfaceVariant = PanelHi,
    onSurfaceVariant = TextLo,
    outline = Line,
    outlineVariant = Line,
    error = Color(0xFFFF6B6B),
)

// Timecodes / durations read like a console tape: monospace, tracked out.
val Mono = FontFamily.Monospace

private val ResoundType = Typography().let { base ->
    base.copy(
        headlineSmall = base.headlineSmall.copy(
            fontWeight = FontWeight.Bold,
            letterSpacing = (-0.5).sp,
        ),
        titleMedium = base.titleMedium.copy(fontWeight = FontWeight.SemiBold),
        labelLarge = base.labelLarge.copy(
            fontWeight = FontWeight.SemiBold,
            letterSpacing = 0.3.sp,
        ),
        bodySmall = base.bodySmall.copy(color = TextLo),
    )
}

val TimecodeStyle = TextStyle(
    fontFamily = Mono,
    fontWeight = FontWeight.Medium,
    fontSize = 13.sp,
    letterSpacing = 0.5.sp,
)

private val ResoundShapes = Shapes(
    extraSmall = RoundedCornerShape(6.dp),
    small = RoundedCornerShape(10.dp),
    medium = RoundedCornerShape(14.dp),
    large = RoundedCornerShape(20.dp),
)

@Composable
fun ResoundTheme(content: @Composable () -> Unit) {
    MaterialTheme(
        colorScheme = ResoundColors,
        typography = ResoundType,
        shapes = ResoundShapes,
        content = content,
    )
}
