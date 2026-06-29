package com.typezero.cloudplayer.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.CloudQueue
import androidx.compose.material.icons.rounded.Lock
import androidx.compose.material.icons.rounded.PlayArrow
import androidx.compose.material.icons.rounded.Storage
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.typezero.cloudplayer.ui.theme.Brand

private data class ProviderChoice(
    val name: String,
    val subtitle: String,
    val enabled: Boolean,
    val icon: ImageVector
)

@Composable
fun ProviderStartScreen(
    onOpenPCloud: () -> Unit,
    onOpenMega: () -> Unit,
    onOpenDropbox: () -> Unit,
    onOpenBox: () -> Unit,
    onBackToLibraries: () -> Unit
) {
    val pCloudFocus = remember { FocusRequester() }
    LaunchedEffect(Unit) { runCatching { pCloudFocus.requestFocus() } }

    BoxWithConstraints(
        modifier = Modifier
            .fillMaxSize()
            .background(Brand.pageGradient)
    ) {
        val compact = maxWidth < 700.dp
        val compactCardModifier = Modifier.fillMaxWidth()

        Column(
            modifier = Modifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = if (compact) 22.dp else 56.dp, vertical = 34.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(18.dp)
        ) {
            Text(
                text = "Libraries",
                color = Brand.TextMid,
                fontWeight = FontWeight.SemiBold,
                fontSize = 15.sp,
                modifier = Modifier
                    .align(Alignment.Start)
                    .clickable { onBackToLibraries() }
            )
            Box(
                modifier = Modifier
                    .size(if (compact) 72.dp else 88.dp)
                    .clip(RoundedCornerShape(24.dp))
                    .background(Brand.Surface)
                    .border(1.dp, Brand.Stroke, RoundedCornerShape(24.dp)),
                contentAlignment = Alignment.Center
            ) {
                Icon(
                    Icons.Rounded.PlayArrow,
                    contentDescription = null,
                    tint = Brand.TextHi,
                    modifier = Modifier.size(if (compact) 42.dp else 52.dp)
                )
            }

            Text(
                text = "Cloud Player",
                color = Brand.TextHi,
                fontWeight = FontWeight.Bold,
                fontSize = if (compact) 34.sp else 46.sp
            )
            Text(
                text = "Your media. Any cloud.",
                color = Brand.TextMid,
                fontSize = if (compact) 15.sp else 18.sp,
                textAlign = TextAlign.Center
            )

            Spacer(Modifier.height(6.dp))

            Text(
                text = "Add a library",
                color = Brand.TextHi,
                fontWeight = FontWeight.SemiBold,
                fontSize = if (compact) 20.sp else 24.sp,
                modifier = Modifier
                    .fillMaxWidth()
                    .widthIn(max = 980.dp)
            )
            Text(
                text = "Choose where your media is stored. Each service becomes a library inside Cloud Player.",
                color = Brand.TextMid,
                fontSize = 14.sp,
                modifier = Modifier
                    .fillMaxWidth()
                    .widthIn(max = 980.dp)
            )

            val providers = listOf(
                ProviderChoice("pCloud", "Sign in and browse your pCloud media", true, Icons.Rounded.CloudQueue),
                ProviderChoice("MEGA", "Sign in or open a shared MEGA link", true, Icons.Rounded.CloudQueue),
                ProviderChoice("Google Drive", "Coming soon", false, Icons.Rounded.Lock),
                ProviderChoice("Dropbox", "Sign in and add your Dropbox library", true, Icons.Rounded.CloudQueue),
                ProviderChoice("OneDrive", "Coming soon", false, Icons.Rounded.Lock),
                ProviderChoice("Box", "Sign in and add your Box library", true, Icons.Rounded.CloudQueue),
                ProviderChoice("SMB / WebDAV", "Coming soon", false, Icons.Rounded.Storage)
            )

            if (compact) {
                Column(
                    modifier = Modifier.widthIn(max = 520.dp),
                    verticalArrangement = Arrangement.spacedBy(12.dp)
                ) {
                    providers.forEachIndexed { index, provider ->
                        ProviderCard(
                            provider = provider,
                            modifier = if (index == 0) compactCardModifier.focusRequester(pCloudFocus) else compactCardModifier,
                            onClick = {
                                when (provider.name) {
                                    "pCloud" -> onOpenPCloud()
                                    "MEGA" -> onOpenMega()
                                    "Dropbox" -> onOpenDropbox()
                                    "Box" -> onOpenBox()
                                }
                            }
                        )
                    }
                }
            } else {
                Column(
                    modifier = Modifier.widthIn(max = 980.dp),
                    verticalArrangement = Arrangement.spacedBy(14.dp)
                ) {
                    providers.chunked(3).forEach { row ->
                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            horizontalArrangement = Arrangement.spacedBy(14.dp)
                        ) {
                            row.forEachIndexed { index, provider ->
                                val globalIndex = providers.indexOf(provider)
                                ProviderCard(
                                    provider = provider,
                                    modifier = if (globalIndex == 0) Modifier.weight(1f).focusRequester(pCloudFocus) else Modifier.weight(1f),
                                    onClick = {
                                        when (provider.name) {
                                            "pCloud" -> onOpenPCloud()
                                            "MEGA" -> onOpenMega()
                                            "Dropbox" -> onOpenDropbox()
                                            "Box" -> onOpenBox()
                                        }
                                    }
                                )
                            }
                            repeat(3 - row.size) { Spacer(Modifier.weight(1f)) }
                        }
                    }
                }
            }

            Spacer(Modifier.height(8.dp))
            Text(
                text = "Cloud Player starts with pCloud and now adds MEGA, Dropbox, and Box as connected libraries.",
                color = Brand.TextLow,
                fontSize = 12.sp,
                textAlign = TextAlign.Center
            )
        }
    }
}

@Composable
private fun ProviderCard(
    provider: ProviderChoice,
    modifier: Modifier = Modifier,
    onClick: () -> Unit
) {
    val alpha = if (provider.enabled) 1f else 0.48f
    Column(
        modifier = modifier
            .clip(RoundedCornerShape(20.dp))
            .background(Brand.Surface.copy(alpha = if (provider.enabled) 0.96f else 0.54f))
            .border(
                width = 1.dp,
                color = if (provider.enabled) Brand.Accent.copy(alpha = 0.55f) else Brand.Stroke,
                shape = RoundedCornerShape(20.dp)
            )
            .clickable(enabled = provider.enabled) { onClick() }
            .padding(18.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp)
    ) {
        Box(
            modifier = Modifier
                .size(46.dp)
                .clip(RoundedCornerShape(15.dp))
                .background(if (provider.enabled) Brand.Accent.copy(alpha = 0.16f) else Brand.Stroke.copy(alpha = 0.18f)),
            contentAlignment = Alignment.Center
        ) {
            Icon(
                imageVector = provider.icon,
                contentDescription = null,
                tint = if (provider.enabled) Brand.Accent else Brand.TextLow,
                modifier = Modifier.size(28.dp)
            )
        }
        Text(
            text = provider.name,
            color = Brand.TextHi.copy(alpha = alpha),
            fontWeight = FontWeight.Bold,
            fontSize = 19.sp
        )
        Text(
            text = provider.subtitle,
            color = Brand.TextMid.copy(alpha = alpha),
            fontSize = 13.sp,
            lineHeight = 18.sp
        )
    }
}
