#--------------------------------------------
# file:     updates-menu.ps1
# author:   Mike Redd
# version:  2.4
# created:  2026-03-30
# updated:  2026-04-19
# desc:     Windows updates system & reboot
#--------------------------------------------

# ── Load custom UI ────────────────────────────────────────────
$uiPath = Join-Path $PSProfileDir "ui.ps1"
if (Test-Path $uiPath) {
    try { . $uiPath } catch {
        Write-Host "Failed to load ui.ps1: $($_.Exception.Message)"
        return
    }
} else {
    Write-Host "Missing ui.ps1: $uiPath"
    return
}

# ── Load core helper ──────────────────────────────────────────
$corePath = Join-Path $PSProfileDir "core.ps1"
if (Test-Path $corePath) {
    try { . $corePath } catch {
        Write-Host "Failed to load core.ps1: $($_.Exception.Message)"
        Pause-UiReturn "Press Enter to return..."
        return
    }
} else {
    Write-Host "Missing core.ps1: $corePath"
    Pause-UiReturn "Press Enter to return..."
    return
}

$ScriptName    = "Windows Update Menu"
$ScriptVersion = "2.4"
$ScriptAuthor  = "Mike Redd"

# ── Cached update list ────────────────────────────────────────
$script:CachedUpdates  = $null
$script:LastScanTime   = $null
$script:RebootRequired = $false

# ── Admin check ───────────────────────────────────────────────
function Test-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $p  = New-Object Security.Principal.WindowsPrincipal($id)
    return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# ── Ensure PSWindowsUpdate ────────────────────────────────────
function Ensure-PSWindowsUpdate {
    if (Get-Module -ListAvailable -Name PSWindowsUpdate) {
        Import-Module PSWindowsUpdate -ErrorAction SilentlyContinue
        return $true
    }

    Write-UiBlankLine
    Write-Host "  $($global:UI_YLW)$($global:UI_B)  PSWindowsUpdate module not found.$($global:UI_R)"
    Write-Host "  $($global:UI_GRY)  Required to manage updates.$($global:UI_R)"
    Write-UiBlankLine
    Write-Host -NoNewline "  $($global:UI_YLW)  Install now? (y/n): $($global:UI_R)"
    $ans = Read-Host

    if ($ans -notmatch '^[Yy]$') { return $false }

    try {
        Install-Module PSWindowsUpdate -Force -Scope CurrentUser -Repository PSGallery -AllowClobber -ErrorAction Stop
        Import-Module PSWindowsUpdate -ErrorAction Stop
        Write-CoreSuccess "PSWindowsUpdate installed."
        return $true
    } catch {
        Write-CoreError "Install failed: $($_.Exception.Message)"
        return $false
    }
}

# ── Reboot pending ────────────────────────────────────────────
function Test-RebootPending {
    $paths = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired",
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending",
        "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager"
    )
    try {
        if (Test-Path $paths[0] -or Test-Path $paths[1]) { return $true }
        if (Get-ItemProperty $paths[2] -Name PendingFileRenameOperations -ErrorAction SilentlyContinue) { return $true }
    } catch {}
    return $false
}

# ── Header ───────────────────────────────────────────────────
function Show-Header {
    Clear-UiScreen
    $w = Get-UiBoxWidth -MaxWidth 52 -MinWidth 40

    Write-UiHeader -Title $ScriptName -Subtitle "v$ScriptVersion  by $ScriptAuthor" -Width $w
    Write-UiRow "User" "$env:USERNAME@$env:COMPUTERNAME"

    if (Test-Admin) {
        Write-UiRow "Admin" "Yes" $global:UI_GRN
    } else {
        Write-UiRow "Admin" "No (limited)" $global:UI_RED
    }

    if ($script:LastScanTime) {
        $age = [Math]::Round(((Get-Date) - $script:LastScanTime).TotalMinutes)
        $count = if ($script:CachedUpdates) { $script:CachedUpdates.Count } else { 0 }
        Write-UiRow "Updates" "$count pending (${age}m ago)"
    }

    if ($script:RebootRequired -or (Test-RebootPending)) {
        Write-UiRow "Reboot" "REQUIRED" $global:UI_RED
    }

    Write-UiBlankLine
}

function Show-Menu {
    Write-UiDivider
    Write-Host "  1) Scan & List Updates"
    Write-Host "  2) Update History"
    Write-Host "  3) Install All"
    Write-Host "  4) Security Only"
    Write-Host "  5) Reboot"
    Write-UiDivider
    Write-Host "  Q) Quit"
    Write-UiBlankLine
}

function Pause-Script { Pause-Core "Press Enter..." }
function Confirm-Action($m) { Confirm-Core $m }

# ── Cache freshness check ─────────────────────────────────────
function Refresh-CacheIfStale {
    if ($script:LastScanTime -and ((Get-Date) - $script:LastScanTime).TotalMinutes -gt 30) {
        $script:CachedUpdates = $null
    }
}

# ── Scan ─────────────────────────────────────────────────────
function Invoke-ScanAndList {
    Show-Header
    Write-Host "  Scanning..."
    try {
        $updates = Get-WindowsUpdate -ErrorAction Stop
        $script:CachedUpdates = $updates
        $script:LastScanTime  = Get-Date

        if (-not $updates) {
            Write-CoreSuccess "System up to date."
            return
        }

        foreach ($u in $updates) {
            Write-Host "  - $($u.Title)"
        }

    } catch {
        Write-CoreError "Scan failed."
    }
}

# ── Install all ───────────────────────────────────────────────
function Install-AllUpdates {
    Refresh-CacheIfStale

    if (-not $script:CachedUpdates) {
        $script:CachedUpdates = Get-WindowsUpdate
    }

    $updates = $script:CachedUpdates
    if (-not $updates) { return }

    if (-not (Confirm-Action "Install all updates?")) { return }

    foreach ($u in $updates) {
        try {
            $u | Install-WindowsUpdate -AcceptAll -IgnoreReboot | Out-Null
            Write-CoreSuccess "Installed: $($u.Title)"
        } catch {
            Write-CoreError "Failed: $($u.Title)"
        }
    }

    if (Test-RebootPending) {
        $script:RebootRequired = $true
    }
}

# ── Reboot ───────────────────────────────────────────────────
function Invoke-Reboot {
    if (-not (Confirm-Action "Reboot now?")) { return }
    Restart-Computer -Force
}

# ── Startup ──────────────────────────────────────────────────
if (-not (Ensure-PSWindowsUpdate)) { return }

# ── Main loop ────────────────────────────────────────────────
while ($true) {
    Show-Header
    Show-Menu

    $choice = (Read-Host "Choice").ToUpper()

    switch ($choice) {
        "1" { Invoke-ScanAndList; Pause-Script }
        "3" { Install-AllUpdates; Pause-Script }
        "5" { Invoke-Reboot; Pause-Script }
        "Q" { return }
        default { Write-CoreError "Invalid" }
    }
}