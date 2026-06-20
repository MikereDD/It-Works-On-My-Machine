package com.typezero.atomicclock.ui.components

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.wrapContentHeight
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.typezero.atomicclock.ui.ClockParts

/**
 * Big central display: a faint full ring with a bright arc that sweeps once per
 * second (driven by [fractionOfSecond]), with the time stacked in the middle.
 */
@Composable
fun ClockFace(
    parts: ClockParts,
    fractionOfSecond: Float,
    accent: Color,
    modifier: Modifier = Modifier,
) {
    val trackColor = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.07f)
    Box(modifier = modifier, contentAlignment = Alignment.Center) {
        Canvas(
            modifier = Modifier
                .fillMaxWidth(0.92f)
                .aspectRatio(1f),
        ) {
            val stroke = 6.dp.toPx()
            val inset = stroke / 2f
            val arcSize = androidx.compose.ui.geometry.Size(
                size.width - stroke, size.height - stroke,
            )
            val topLeft = androidx.compose.ui.geometry.Offset(inset, inset)

            // Faint full track.
            drawArc(
                color = trackColor,
                startAngle = 0f,
                sweepAngle = 360f,
                useCenter = false,
                topLeft = topLeft,
                size = arcSize,
                style = Stroke(width = stroke, cap = StrokeCap.Round),
            )
            // Bright sweeping second arc.
            drawArc(
                brush = Brush.sweepGradient(
                    listOf(accent.copy(alpha = 0.2f), accent),
                ),
                startAngle = -90f,
                sweepAngle = 360f * fractionOfSecond.coerceIn(0f, 1f),
                useCenter = false,
                topLeft = topLeft,
                size = arcSize,
                style = Stroke(width = stroke, cap = StrokeCap.Round),
            )
        }

        Column(
            horizontalAlignment = Alignment.CenterHorizontally,
            modifier = Modifier
                .fillMaxSize()
                .wrapContentHeight(Alignment.CenterVertically)
                .padding(horizontal = 14.dp),
        ) {
            if (parts.amPm.isNotEmpty()) {
                Text(
                    text = parts.amPm,
                    style = MaterialTheme.typography.labelLarge,
                    color = accent,
                )
            }
            Row(verticalAlignment = Alignment.Bottom) {
                Text(
                    text = parts.mainTime,
                    style = MaterialTheme.typography.displayLarge,
                    color = MaterialTheme.colorScheme.onBackground,
                    textAlign = TextAlign.Center,
                    maxLines = 1,
                    softWrap = false,
                )
                Text(
                    text = parts.millis,
                    style = MaterialTheme.typography.titleMedium.copy(
                        fontWeight = FontWeight.Medium,
                        fontSize = 18.sp,
                    ),
                    color = accent,
                    maxLines = 1,
                    softWrap = false,
                    modifier = Modifier.padding(bottom = 11.dp),
                )
            }
            Text(
                text = parts.date,
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            Text(
                text = parts.zone,
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.8f),
                modifier = Modifier.alpha(0.9f),
            )
        }
    }
}
