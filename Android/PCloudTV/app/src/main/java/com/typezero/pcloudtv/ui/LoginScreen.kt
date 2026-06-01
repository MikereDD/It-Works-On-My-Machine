package com.typezero.pcloudtv.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.focusable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.CloudQueue
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.typezero.pcloudtv.ui.theme.Brand

@Composable
fun LoginScreen(
    error: String?,
    busy: Boolean,
    onSignIn: () -> Unit,
    onUseToken: (String) -> Unit
) {
    var token by remember { mutableStateOf("") }

    BoxWithConstraints(
        modifier = Modifier.fillMaxSize().background(Brand.pageGradient)
    ) {
        val compact = maxWidth < 600.dp
        val block = Modifier.fillMaxWidth().widthIn(max = 460.dp)

        Column(
            modifier = Modifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = if (compact) 22.dp else 48.dp, vertical = 28.dp),
            verticalArrangement = Arrangement.spacedBy(14.dp),
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            Spacer(Modifier.height(8.dp))
            Box(
                modifier = Modifier
                    .size(if (compact) 64.dp else 76.dp)
                    .clip(RoundedCornerShape(20.dp))
                    .background(Brand.Accent.copy(alpha = 0.16f)),
                contentAlignment = Alignment.Center
            ) {
                Icon(
                    Icons.Rounded.CloudQueue,
                    contentDescription = null,
                    tint = Brand.Accent,
                    modifier = Modifier.size(if (compact) 36.dp else 42.dp)
                )
            }

            Text("pCloud TV", fontSize = if (compact) 32.sp else 40.sp,
                fontWeight = FontWeight.Bold, color = Brand.TextHi)
            Text("Stream your pCloud video & audio",
                color = Brand.TextMid, fontSize = 14.sp)

            if (error != null) {
                Box(
                    modifier = block
                        .clip(RoundedCornerShape(12.dp))
                        .background(MaterialTheme.colorScheme.error.copy(alpha = 0.12f))
                        .border(1.dp, MaterialTheme.colorScheme.error.copy(alpha = 0.4f),
                            RoundedCornerShape(12.dp))
                        .padding(14.dp)
                ) {
                    Text(error, color = MaterialTheme.colorScheme.error, fontSize = 13.sp)
                }
            }

            Spacer(Modifier.height(2.dp))
            PillButton(
                text = "Sign in with pCloud",
                primary = true,
                enabled = !busy,
                modifier = block,
                onClick = onSignIn
            )

            Spacer(Modifier.height(6.dp))
            Text("— or paste an access token —", color = Brand.TextLow, fontSize = 12.sp)

            OutlinedTextField(
                value = token,
                onValueChange = { token = it },
                label = { Text("pCloud access token") },
                singleLine = true,
                shape = RoundedCornerShape(12.dp),
                colors = OutlinedTextFieldDefaults.colors(
                    focusedBorderColor = Brand.Accent,
                    unfocusedBorderColor = Brand.Stroke,
                    focusedLabelColor = Brand.Accent,
                    cursorColor = Brand.Accent
                ),
                keyboardOptions = KeyboardOptions(imeAction = ImeAction.Done),
                keyboardActions = KeyboardActions(onDone = { onUseToken(token) }),
                modifier = block
            )

            PillButton(
                text = "Use access token",
                primary = false,
                enabled = !busy,
                busy = busy,
                modifier = block,
                onClick = { onUseToken(token) }
            )

            Text(
                "Tap \"Sign in with pCloud\" to open pCloud's login page — two-factor " +
                    "authentication is handled there. Only the returned access token is " +
                    "stored on this device.",
                color = Brand.TextLow,
                fontSize = 12.sp,
                modifier = block
            )
        }
    }
}

@Composable
private fun PillButton(
    text: String,
    primary: Boolean,
    enabled: Boolean,
    modifier: Modifier = Modifier,
    busy: Boolean = false,
    onClick: () -> Unit
) {
    var focused by remember { mutableStateOf(false) }
    val interaction = remember { MutableInteractionSource() }
    val active = focused
    val bg = when {
        primary -> Brand.Accent
        active -> Brand.SurfaceFocused
        else -> Brand.Surface
    }
    val fg = if (primary) MaterialTheme.colorScheme.onPrimary else Brand.TextHi
    val borderColor = if (primary) Brand.Accent else if (active) Brand.Accent else Brand.Stroke

    Box(
        modifier = modifier
            .height(52.dp)
            .clip(RoundedCornerShape(26.dp))
            .background(bg)
            .border(1.5.dp, borderColor, RoundedCornerShape(26.dp))
            .onFocusChanged { focused = it.isFocused }
            .focusable(enabled = enabled, interactionSource = interaction)
            .clickable(enabled = enabled, interactionSource = interaction,
                indication = null, onClick = onClick),
        contentAlignment = Alignment.Center
    ) {
        if (busy) {
            CircularProgressIndicator(modifier = Modifier.size(22.dp), color = fg, strokeWidth = 2.dp)
        } else {
            Text(text, color = fg, fontSize = 16.sp, fontWeight = FontWeight.SemiBold)
        }
    }
}

