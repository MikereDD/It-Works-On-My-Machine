package com.typezero.cloudplayer.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.ArrowBack
import androidx.compose.material.icons.rounded.CloudQueue
import androidx.compose.material.icons.rounded.Link
import androidx.compose.material.icons.rounded.Lock
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.typezero.cloudplayer.data.MegaAccount
import com.typezero.cloudplayer.ui.theme.Brand

@Composable
fun MegaConnectScreen(
    megaAccounts: List<MegaAccount>,
    onBack: () -> Unit,
    onLibraries: () -> Unit,
    onSignInWithMega: () -> Unit,
    onRemoveMegaAccount: (String) -> Unit,
    initialMessage: String? = null
) {
    var sharedLink by remember { mutableStateOf("") }
    var message by remember(initialMessage) { mutableStateOf(initialMessage) }

    BoxWithConstraints(
        modifier = Modifier
            .fillMaxSize()
            .background(Brand.pageGradient)
    ) {
        val compact = maxWidth < 700.dp

        Column(
            modifier = Modifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = if (compact) 22.dp else 56.dp, vertical = 34.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(18.dp)
        ) {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .widthIn(max = 920.dp),
                horizontalArrangement = Arrangement.Start
            ) {
                Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    OutlinedButton(onClick = onBack) {
                        Icon(Icons.Rounded.ArrowBack, contentDescription = null, modifier = Modifier.size(18.dp))
                        Spacer(Modifier.size(8.dp))
                        Text("Back")
                    }
                    OutlinedButton(onClick = onLibraries) {
                        Icon(Icons.Rounded.CloudQueue, contentDescription = null, modifier = Modifier.size(18.dp))
                        Spacer(Modifier.size(8.dp))
                        Text("Libraries")
                    }
                }
            }

            Box(
                modifier = Modifier
                    .size(if (compact) 74.dp else 92.dp)
                    .clip(RoundedCornerShape(26.dp))
                    .background(Brand.Surface)
                    .border(1.dp, Brand.Stroke, RoundedCornerShape(26.dp)),
                contentAlignment = Alignment.Center
            ) {
                Icon(
                    Icons.Rounded.CloudQueue,
                    contentDescription = null,
                    tint = Brand.TextHi,
                    modifier = Modifier.size(if (compact) 42.dp else 54.dp)
                )
            }

            Text(
                text = "MEGA",
                color = Brand.TextHi,
                fontWeight = FontWeight.Bold,
                fontSize = if (compact) 34.sp else 46.sp
            )
            Text(
                text = "Add MEGA as a Cloud Player library.",
                color = Brand.TextMid,
                fontSize = if (compact) 15.sp else 18.sp,
                textAlign = TextAlign.Center
            )

            if (megaAccounts.isNotEmpty()) {
                Column(
                    modifier = Modifier
                        .widthIn(max = 760.dp)
                        .fillMaxWidth()
                        .clip(RoundedCornerShape(22.dp))
                        .background(Brand.Surface.copy(alpha = 0.94f))
                        .border(1.dp, Brand.Accent.copy(alpha = 0.55f), RoundedCornerShape(22.dp))
                        .padding(20.dp),
                    verticalArrangement = Arrangement.spacedBy(12.dp)
                ) {
                    Text(
                        text = "Logged in",
                        color = Brand.TextHi,
                        fontWeight = FontWeight.Bold,
                        fontSize = 20.sp
                    )
                    megaAccounts.forEach { account ->
                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            horizontalArrangement = Arrangement.SpaceBetween,
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            Column(modifier = Modifier.weight(1f)) {
                                Text(account.label, color = Brand.TextHi, fontWeight = FontWeight.SemiBold)
                                Text(
                                    "Account browsing will activate after the MEGA SDK/decryption provider is connected.",
                                    color = Brand.TextLow,
                                    fontSize = 12.sp,
                                    lineHeight = 17.sp
                                )
                            }
                            OutlinedButton(onClick = { onRemoveMegaAccount(account.id) }) {
                                Text("Remove")
                            }
                        }
                    }
                    Button(
                        onClick = onLibraries,
                        colors = ButtonDefaults.buttonColors(containerColor = Brand.SurfaceFocused)
                    ) {
                        Text("Back to Libraries", color = Brand.TextHi)
                    }
                }
            }

            Column(
                modifier = Modifier
                    .widthIn(max = 760.dp)
                    .fillMaxWidth()
                    .clip(RoundedCornerShape(22.dp))
                    .background(Brand.Surface.copy(alpha = 0.94f))
                    .border(1.dp, Brand.Stroke, RoundedCornerShape(22.dp))
                    .padding(20.dp),
                verticalArrangement = Arrangement.spacedBy(16.dp)
            ) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Icon(Icons.Rounded.Lock, contentDescription = null, tint = Brand.TextHi)
                    Spacer(Modifier.size(10.dp))
                    Text(
                        text = "Sign in with MEGA",
                        color = Brand.TextHi,
                        fontWeight = FontWeight.Bold,
                        fontSize = 20.sp
                    )
                }
                Text(
                    text = "MEGA accounts with two-factor authentication must use MEGA's own login page. Cloud Player opens MEGA directly so password, 2FA, CAPTCHA, and future security changes are handled by MEGA instead of a custom email/password form.",
                    color = Brand.TextMid,
                    fontSize = 14.sp,
                    lineHeight = 20.sp
                )
                Button(
                    onClick = onSignInWithMega,
                    colors = ButtonDefaults.buttonColors(containerColor = Brand.SurfaceFocused)
                ) {
                    Text("Open MEGA login", color = Brand.TextHi)
                }
                Text(
                    text = "Account browsing still needs the official MEGA SDK/decryption provider before files can be listed and streamed inside Cloud Player.",
                    color = Brand.TextLow,
                    fontSize = 12.sp,
                    lineHeight = 18.sp
                )
            }

            Column(
                modifier = Modifier
                    .widthIn(max = 760.dp)
                    .fillMaxWidth()
                    .clip(RoundedCornerShape(22.dp))
                    .background(Brand.Surface.copy(alpha = 0.94f))
                    .border(1.dp, Brand.Accent.copy(alpha = 0.38f), RoundedCornerShape(22.dp))
                    .padding(20.dp),
                verticalArrangement = Arrangement.spacedBy(16.dp)
            ) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Icon(Icons.Rounded.Link, contentDescription = null, tint = Brand.TextHi)
                    Spacer(Modifier.size(10.dp))
                    Text(
                        text = "Open shared MEGA link",
                        color = Brand.TextHi,
                        fontWeight = FontWeight.Bold,
                        fontSize = 20.sp
                    )
                }
                Text(
                    text = "Paste a MEGA file or folder link. Shared link streaming will be enabled after the MEGA decrypting provider is connected.",
                    color = Brand.TextMid,
                    fontSize = 14.sp,
                    lineHeight = 20.sp
                )
                OutlinedTextField(
                    value = sharedLink,
                    onValueChange = { sharedLink = it; message = null },
                    modifier = Modifier.fillMaxWidth(),
                    singleLine = false,
                    minLines = 2,
                    label = { Text("MEGA link") },
                    placeholder = { Text("https://mega.nz/file/... or https://mega.nz/folder/...") }
                )
                Button(
                    onClick = {
                        val link = sharedLink.trim()
                        message = when {
                            link.isBlank() -> "Paste a MEGA shared link first."
                            !looksLikeMegaLink(link) -> "That does not look like a MEGA file or folder link."
                            else -> "MEGA link accepted. Streaming support comes next after the MEGA decrypting provider is connected."
                        }
                    },
                    colors = ButtonDefaults.buttonColors(containerColor = Brand.Accent, contentColor = Color.Black)
                ) {
                    Text("Check Link")
                }
            }

            message?.let {
                Text(
                    text = it,
                    color = Brand.TextHi,
                    fontSize = 14.sp,
                    textAlign = TextAlign.Center,
                    modifier = Modifier.widthIn(max = 760.dp)
                )
            }
        }
    }
}

private fun looksLikeMegaLink(value: String): Boolean {
    val lower = value.lowercase()
    return (lower.contains("mega.nz/file/") ||
            lower.contains("mega.nz/folder/") ||
            lower.contains("mega.co.nz/#!") ||
            lower.contains("mega.nz/#!") ||
            lower.contains("mega.nz/#f!"))
}
