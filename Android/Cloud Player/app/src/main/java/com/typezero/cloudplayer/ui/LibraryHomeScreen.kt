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
import androidx.compose.material.icons.rounded.Add
import androidx.compose.material.icons.rounded.CloudQueue
import androidx.compose.material.icons.rounded.Lock
import androidx.compose.material.icons.rounded.Storage
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.typezero.cloudplayer.BuildConfig
import com.typezero.cloudplayer.data.Account
import com.typezero.cloudplayer.data.MegaAccount
import com.typezero.cloudplayer.data.DropboxAccount
import com.typezero.cloudplayer.data.BoxAccount
import com.typezero.cloudplayer.ui.theme.Brand

private data class LibraryCardModel(
    val title: String,
    val subtitle: String,
    val icon: ImageVector,
    val enabled: Boolean = true,
    val accountId: String? = null,
    val action: LibraryAction
)

private enum class LibraryAction { OpenPCloud, AddPCloud, OpenMega, OpenDropbox, OpenBox, OpenSharedLink, AddService, ComingSoon }

@Composable
fun LibraryHomeScreen(
    pCloudAccounts: List<Account>,
    megaAccounts: List<MegaAccount>,
    dropboxAccounts: List<DropboxAccount>,
    boxAccounts: List<BoxAccount>,
    activeAccountId: String?,
    onOpenPCloudAccount: (String) -> Unit,
    onAddPCloud: () -> Unit,
    onOpenMega: () -> Unit,
    onOpenDropbox: () -> Unit,
    onOpenBox: () -> Unit,
    onOpenSharedLink: () -> Unit,
    onAddService: () -> Unit
) {
    BoxWithConstraints(
        modifier = Modifier
            .fillMaxSize()
            .background(Brand.pageGradient)
    ) {
        val compact = maxWidth < 720.dp
        val cards = buildList {
            pCloudAccounts.forEach { account ->
                add(
                    LibraryCardModel(
                        title = if (account.id == activeAccountId) "pCloud • Logged in • Active" else "pCloud • Logged in",
                        subtitle = account.label,
                        icon = Icons.Rounded.CloudQueue,
                        accountId = account.id,
                        action = LibraryAction.OpenPCloud
                    )
                )
            }
            add(
                LibraryCardModel(
                    title = if (pCloudAccounts.isEmpty()) "pCloud • Not logged in" else "pCloud • Add account",
                    subtitle = if (pCloudAccounts.isEmpty()) "Sign in and add your pCloud library" else "Add another pCloud account",
                    icon = Icons.Rounded.Add,
                    action = LibraryAction.AddPCloud
                )
            )
            megaAccounts.forEach { account ->
                add(
                    LibraryCardModel(
                        title = "MEGA • Logged in",
                        subtitle = account.label,
                        icon = Icons.Rounded.CloudQueue,
                        accountId = account.id,
                        action = LibraryAction.OpenMega
                    )
                )
            }
            add(
                LibraryCardModel(
                    title = if (megaAccounts.isEmpty()) "MEGA • Not logged in" else "MEGA • Manage account",
                    subtitle = if (megaAccounts.isEmpty()) "Sign in or open a shared MEGA link" else "View signed-in MEGA account and options",
                    icon = Icons.Rounded.CloudQueue,
                    action = LibraryAction.OpenMega
                )
            )
            dropboxAccounts.forEach { account ->
                add(
                    LibraryCardModel(
                        title = "Dropbox • Logged in",
                        subtitle = account.label,
                        icon = Icons.Rounded.CloudQueue,
                        accountId = account.id,
                        action = LibraryAction.OpenDropbox
                    )
                )
            }
            add(
                LibraryCardModel(
                    title = if (dropboxAccounts.isEmpty()) "Dropbox • Not logged in" else "Dropbox • Manage account",
                    subtitle = if (dropboxAccounts.isEmpty()) "Sign in and add your Dropbox library" else "View signed-in Dropbox account and options",
                    icon = Icons.Rounded.CloudQueue,
                    action = LibraryAction.OpenDropbox
                )
            )

            boxAccounts.forEach { account ->
                add(
                    LibraryCardModel(
                        title = "Box • Logged in",
                        subtitle = account.label,
                        icon = Icons.Rounded.CloudQueue,
                        accountId = account.id,
                        action = LibraryAction.OpenBox
                    )
                )
            }
            add(
                LibraryCardModel(
                    title = if (boxAccounts.isEmpty()) "Box • Not logged in" else "Box • Manage account",
                    subtitle = if (boxAccounts.isEmpty()) "Sign in and add your Box library" else "View signed-in Box account and options",
                    icon = Icons.Rounded.CloudQueue,
                    action = LibraryAction.OpenBox
                )
            )

            add(
                LibraryCardModel(
                    title = "Open Shared Link",
                    subtitle = "Play or cast shared media links without signing in",
                    icon = Icons.Rounded.CloudQueue,
                    action = LibraryAction.OpenSharedLink
                )
            )
            add(
                LibraryCardModel(
                    title = "+ Add Cloud Service",
                    subtitle = "Choose pCloud, MEGA, Dropbox, Box, Google Drive, OneDrive, SMB, or WebDAV",
                    icon = Icons.Rounded.Add,
                    action = LibraryAction.AddService
                )
            )
            add(LibraryCardModel("Google Drive", "Coming soon", Icons.Rounded.Lock, enabled = false, action = LibraryAction.ComingSoon))
            add(LibraryCardModel("OneDrive", "Coming soon", Icons.Rounded.Lock, enabled = false, action = LibraryAction.ComingSoon))
            add(LibraryCardModel("SMB / WebDAV", "Coming soon", Icons.Rounded.Storage, enabled = false, action = LibraryAction.ComingSoon))
        }

        Column(
            modifier = Modifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = if (compact) 22.dp else 56.dp, vertical = 34.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(18.dp)
        ) {
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

            Spacer(Modifier.height(2.dp))

            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .widthIn(max = 980.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.SpaceBetween
            ) {
                Text(
                    text = "Libraries",
                    color = Brand.TextHi,
                    fontWeight = FontWeight.SemiBold,
                    fontSize = if (compact) 22.sp else 26.sp
                )
                Text(
                    text = "v${BuildConfig.VERSION_NAME}",
                    color = Brand.TextMid,
                    fontWeight = FontWeight.SemiBold,
                    fontSize = if (compact) 15.sp else 17.sp
                )
            }
            Text(
                text = "Connected Accounts keeps every provider visible from one place. Logged-in services show the account attached to that provider, and Add Cloud Service is the path for everything we add next.",
                color = Brand.TextMid,
                fontSize = 14.sp,
                lineHeight = 20.sp,
                modifier = Modifier
                    .fillMaxWidth()
                    .widthIn(max = 980.dp)
            )

            if (compact) {
                Column(
                    modifier = Modifier.widthIn(max = 560.dp),
                    verticalArrangement = Arrangement.spacedBy(12.dp)
                ) {
                    cards.forEach { card ->
                        LibraryCard(
                            card = card,
                            modifier = Modifier.fillMaxWidth(),
                            onClick = {
                                when (card.action) {
                                    LibraryAction.OpenPCloud -> card.accountId?.let(onOpenPCloudAccount)
                                    LibraryAction.AddPCloud -> onAddPCloud()
                                    LibraryAction.OpenMega -> onOpenMega()
                                    LibraryAction.OpenDropbox -> onOpenDropbox()
                                    LibraryAction.OpenBox -> onOpenBox()
                                    LibraryAction.OpenSharedLink -> onOpenSharedLink()
                                    LibraryAction.AddService -> onAddService()
                                    LibraryAction.ComingSoon -> Unit
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
                    cards.chunked(3).forEach { row ->
                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            horizontalArrangement = Arrangement.spacedBy(14.dp)
                        ) {
                            row.forEach { card ->
                                LibraryCard(
                                    card = card,
                                    modifier = Modifier.weight(1f),
                                    onClick = {
                                        when (card.action) {
                                            LibraryAction.OpenPCloud -> card.accountId?.let(onOpenPCloudAccount)
                                            LibraryAction.AddPCloud -> onAddPCloud()
                                            LibraryAction.OpenMega -> onOpenMega()
                                            LibraryAction.OpenDropbox -> onOpenDropbox()
                                            LibraryAction.OpenBox -> onOpenBox()
                                            LibraryAction.OpenSharedLink -> onOpenSharedLink()
                                            LibraryAction.AddService -> onAddService()
                                            LibraryAction.ComingSoon -> Unit
                                        }
                                    }
                                )
                            }
                            repeat(3 - row.size) { Spacer(Modifier.weight(1f)) }
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun LibraryCard(
    card: LibraryCardModel,
    modifier: Modifier = Modifier,
    onClick: () -> Unit
) {
    val alpha = if (card.enabled) 1f else 0.46f
    Column(
        modifier = modifier
            .clip(RoundedCornerShape(20.dp))
            .background(Brand.Surface.copy(alpha = if (card.enabled) 0.96f else 0.54f))
            .border(
                width = 1.dp,
                color = if (card.enabled) Brand.Accent.copy(alpha = 0.55f) else Brand.Stroke,
                shape = RoundedCornerShape(20.dp)
            )
            .clickable(enabled = card.enabled) { onClick() }
            .padding(18.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp)
    ) {
        Box(
            modifier = Modifier
                .size(46.dp)
                .clip(RoundedCornerShape(15.dp))
                .background(if (card.enabled) Brand.Accent.copy(alpha = 0.16f) else Brand.Stroke.copy(alpha = 0.18f)),
            contentAlignment = Alignment.Center
        ) {
            Icon(
                imageVector = card.icon,
                contentDescription = null,
                tint = if (card.enabled) Brand.Accent else Brand.TextLow,
                modifier = Modifier.size(28.dp)
            )
        }
        Text(
            text = card.title,
            color = Brand.TextHi.copy(alpha = alpha),
            fontWeight = FontWeight.Bold,
            fontSize = 19.sp
        )
        Text(
            text = card.subtitle,
            color = Brand.TextMid.copy(alpha = alpha),
            fontSize = 13.sp,
            lineHeight = 18.sp
        )
    }
}
