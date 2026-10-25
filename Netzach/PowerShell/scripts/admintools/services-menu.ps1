#--------------------------------------------
# file:     services-menu.ps1
# author:   Mike Redd
# version:  2.3
# created:  2026-03-30
# updated:  2026-04-19
# desc:     Windows services management tool
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

$ScriptName    = "Services Menu"
$ScriptVersion = "2.3"
$ScriptAuthor  = "Mike Redd"

# ── Header ────────────────────────────────────────────────────
function Show-Header {
    Clear-UiScreen
    $w = Get-UiBoxWidth -MaxWidth 52 -MinWidth 40
    Write-UiHeader -Title $ScriptName -Subtitle "v$ScriptVersion  by $ScriptAuthor" -Width $w
    Write-UiRow "User" "$env:USERNAME@$env:COMPUTERNAME"
    Write-UiRow "Version" "v$ScriptVersion  by $ScriptAuthor" $global:UI_Theme.Muted
    Write-UiBlankLine
}

# ── Menu ──────────────────────────────────────────────────────
function Show-Menu {
    Write-UiDivider
    Write-Host "  $($global:UI_Theme.Accent)  1)$($global:UI_Theme.Reset)  Running services"
    Write-Host "  $($global:UI_Theme.Accent)  2)$($global:UI_Theme.Reset)  Stopped services"
    Write-Host "  $($global:UI_Theme.Accent)  3)$($global:UI_Theme.Reset)  Search service"
    Write-Host "  $($global:UI_Theme.Accent)  4)$($global:UI_Theme.Reset)  Service details"
    Write-UiDivider
    Write-Host "  $($global:UI_Theme.Warning)  5)$($global:UI_Theme.Reset)  Start a service"
    Write-Host "  $($global:UI_Theme.Warning)  6)$($global:UI_Theme.Reset)  Stop a service"
    Write-Host "  $($global:UI_Theme.Warning)  7)$($global:UI_Theme.Reset)  Restart a service"
    Write-Host "  $($global:UI_Theme.Warning)  8)$($global:UI_Theme.Reset)  Set startup type"
    Write-UiDivider
    Write-Host "  $($global:UI_Theme.Muted)  Q)$($global:UI_Theme.Reset)  Quit"
    Write-UiBlankLine
}

# ── Pause ─────────────────────────────────────────────────────
function Pause-Script {
    Pause-Core "Press Enter to return to menu..."
}

# ── Confirm ───────────────────────────────────────────────────
function Confirm-Action($message) {
    return (Confirm-Core $message)
}

# ── Status Color Helper ───────────────────────────────────────
function Get-StatusColor($status) {
    switch ("$status") {
        "Running" { return $global:UI_Theme.Success }
        "Stopped" { return $global:UI_Theme.Error }
        "Paused"  { return $global:UI_Theme.Warning }
        default   { return $global:UI_Theme.Muted }
    }
}

# ── Startup Color Helper ──────────────────────────────────────
function Get-StartupColor($startup) {
    switch ("$startup") {
        "Automatic"        { return $global:UI_Theme.Success }
        "AutomaticDelayed" { return $global:UI_Theme.Success }
        "Manual"           { return $global:UI_Theme.Warning }
        "Disabled"         { return $global:UI_Theme.Error }
        default            { return $global:UI_Theme.Muted }
    }
}

# ── Enrich Service with CIM Data ──────────────────────────────
function Get-ServiceEnriched($svc) {
    $cim = Get-CimInstance Win32_Service -Filter ("Name='{0}'" -f $svc.Name) -ErrorAction SilentlyContinue
    [PSCustomObject]@{
        Name        = $svc.Name
        DisplayName = $svc.DisplayName
        Status      = $svc.Status
        StartType   = if ($cim) { $cim.StartMode } else { "?" }
    }
}

# ── Print Service Row ─────────────────────────────────────────
function Print-ServiceRow($s) {
    $statusColor  = Get-StatusColor $s.Status
    $startupColor = Get-StartupColor $s.StartType
    $nameStr      = $s.Name.PadRight(30)
    $statusStr    = "$($s.Status)".PadRight(10)
    $startStr     = "$($s.StartType)".PadRight(14)
    $displayStr   = if ($s.DisplayName.Length -gt 40) { $s.DisplayName.Substring(0,37) + "..." } else { $s.DisplayName }

    Write-Host "  $($global:UI_Theme.Text)  $nameStr$($global:UI_Theme.Reset)  ${statusColor}$statusStr$($global:UI_Theme.Reset)  ${startupColor}$startStr$($global:UI_Theme.Reset)  $($global:UI_Theme.Muted)$displayStr$($global:UI_Theme.Reset)"
}

# ── 1 — Running Services ──────────────────────────────────────
function Show-RunningServices {
    Show-Header
    $w = Get-UiBoxWidth -MaxWidth 52 -MinWidth 40
    Write-UiBoxTitle -Title "RUNNING SERVICES" -Width $w
    Write-UiBlankLine

    $svcs = Get-Service | Where-Object { $_.Status -eq "Running" } | Sort-Object DisplayName
    Write-Host "  $($global:UI_Theme.Muted)  Found $($global:UI_Theme.Success)$($svcs.Count)$($global:UI_Theme.Muted) running service(s)$($global:UI_Theme.Reset)"
    Write-UiBlankLine
    Write-Host "  $($global:UI_Theme.Muted)  Name                           Status      Startup         Display$($global:UI_Theme.Reset)"
    Write-Host "  $($global:UI_Theme.Muted)  -----------------------------  ----------  --------------  -------$($global:UI_Theme.Reset)"
    foreach ($s in $svcs) {
        Print-ServiceRow (Get-ServiceEnriched $s)
    }
}

# ── Main Loop ─────────────────────────────────────────────────
while ($true) {
    Show-Header
    Show-Menu
    $choice = (Read-UiChoice "Choice:").Trim().ToUpper()

    switch ($choice) {
        "1" { Show-RunningServices; Pause-Script }
        "Q" {
            Write-UiBlankLine
            Write-Host "  $($global:UI_Theme.Accent)  Bye.$($global:UI_Theme.Reset)"
            Write-UiBlankLine
            return
        }
        default {
            Write-CoreError "Invalid option."
            Start-Sleep -Seconds 1
        }
    }
}