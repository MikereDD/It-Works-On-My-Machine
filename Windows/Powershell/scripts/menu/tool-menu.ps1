#--------------------------------------------
# file:     tool-menu.ps1
# author:   Mike Redd
# version:  3.1
# created:  2026-03-30
# updated:  2026-05-17
# desc:     Unified script launcher (Admin + Personal + Games)
#--------------------------------------------

# ── Load custom UI ────────────────────────────────────────────
$uiPath = Join-Path $PSProfileDir "ui.ps1"
if (Test-Path $uiPath) {
    try {
        . $uiPath
    } catch {
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
    try {
        . $corePath
    } catch {
        Write-Host "Failed to load core.ps1: $($_.Exception.Message)"
        Pause-UiReturn "Press Enter to return..."
        return
    }
} else {
    Write-Host "Missing core.ps1: $corePath"
    Pause-UiReturn "Press Enter to return..."
    return
}

$ScriptName    = "Tool Menu"
$ScriptVersion = "3.1"
$ScriptAuthor  = "Mike Redd"

# ── Base script paths ─────────────────────────────────────────
$AdminPath    = Join-Path $PSScriptsDir "admintools"
$PersonalPath = Join-Path $PSScriptsDir "personaltools"
$GamesPath    = Join-Path $PSScriptsDir "games"

# ── Tool Definitions ──────────────────────────────────────────
$AdminTools = @(
    [PSCustomObject]@{ Name="SystemInfo";    File="systeminfo-menu.ps1" }
    [PSCustomObject]@{ Name="PowerMenu";     File="power-menu.ps1" }
    [PSCustomObject]@{ Name="UpdatesMenu";   File="updates-menu.ps1" }
    [PSCustomObject]@{ Name="NetworkMenu";   File="network-menu.ps1" }
    [PSCustomObject]@{ Name="DiskMenu";      File="disk-menu.ps1" }
    [PSCustomObject]@{ Name="EventsMenu";    File="events-menu.ps1" }
    [PSCustomObject]@{ Name="ServicesMenu";  File="services-menu.ps1" }
    [PSCustomObject]@{ Name="WatchMenu";     File="watch-menu.ps1" }
    [PSCustomObject]@{ Name="ProcessesMenu"; File="procs-menu.ps1" }
    [PSCustomObject]@{ Name="LogsMenu";      File="logs-menu.ps1" }
)

$PersonalTools = @(
    [PSCustomObject]@{ Name="SpeedtestMenu";         File="speedtest-menu.ps1" }
    [PSCustomObject]@{ Name="WeatherFetch";          File="weatherfetch-menu.ps1" }
    [PSCustomObject]@{ Name="ImdbDump";              File="imdbdump.ps1" }
    [PSCustomObject]@{ Name="ImdbThumbGrab";         File="imdbthumbgrab.ps1" }
    [PSCustomObject]@{ Name="MiNfoCreate";           File="minfocreate.ps1" }
    [PSCustomObject]@{ Name="CD Image FLAC Ripper";  File="cd-image-flac.ps1" }
    [PSCustomObject]@{ Name="CD Track FLAC Ripper";  File="cd-tracks-flac.ps1" }
    [PSCustomObject]@{ Name="DVD Encoder";           File="dvd-ripper-encoder.ps1" }
    [PSCustomObject]@{ Name="Blu-ray Backup";        File="bluray-backup.ps1" }
    [PSCustomObject]@{ Name="Blu-ray Track Dump";	 File="bluray-trackdump.ps1" }
    [PSCustomObject]@{ Name="Blu-ray Encoder";       File="BRencoder.ps1" }
    [PSCustomObject]@{ Name="WebRipper";             File="web-ripper.ps1" }
)

$GameTools = @(
    [PSCustomObject]@{ Name="Snake";       File="snake.ps1" }
    [PSCustomObject]@{ Name="Pong";        File="pong.ps1" }
    [PSCustomObject]@{ Name="2048";        File="2048.ps1" }
    [PSCustomObject]@{ Name="Minesweeper"; File="minesweeper.ps1" }
    [PSCustomObject]@{ Name="Breakout";    File="breakout.ps1" }
    [PSCustomObject]@{ Name="Tetris";      File="tetris.ps1" }
)

# ── Header ────────────────────────────────────────────────────
function Show-Header {
    Clear-UiScreen
    $BoxWidth = Get-UiBoxWidth -MaxWidth 72 -MinWidth 48

    Write-UiHeader -Title $ScriptName -Subtitle "v$ScriptVersion  by $ScriptAuthor" -Width $BoxWidth
    Write-UiRow "User" "$env:USERNAME@$env:COMPUTERNAME"
    Write-UiRow "Admin Path" $AdminPath -ValueColor $global:UI_GRY
    Write-UiRow "Personal Path" $PersonalPath -ValueColor $global:UI_GRY
    Write-UiRow "Games Path" $GamesPath -ValueColor $global:UI_GRY
    Write-UiBlankLine
}

# ── Menu ──────────────────────────────────────────────────────
function Show-Menu {
    $index = 1
    $script:ToolMap = @{}

    Write-UiDivider
    Write-Host "  $($global:UI_CYN)$($global:UI_B)Admin Tools$($global:UI_R)"
    foreach ($tool in $AdminTools) {
        $path = Join-Path $AdminPath $tool.File
        $exists = Test-Path $path
        $color = if ($exists) { $global:UI_GRN } else { $global:UI_RED }
        $suffix = if ($exists) { "" } else { " (missing)" }
        Write-Host ("  {0}{1,2}){2}  {3}{4}{5}" -f $color, $index, $global:UI_R, $global:UI_WHT, $tool.Name, "$suffix$($global:UI_R)")
        if ($exists) { $script:ToolMap["$index"] = $path }
        $index++
    }

    Write-UiDivider
    Write-Host "  $($global:UI_CYN)$($global:UI_B)Personal Tools$($global:UI_R)"
    foreach ($tool in $PersonalTools) {
        $path = Join-Path $PersonalPath $tool.File
        $exists = Test-Path $path
        $color = if ($exists) { $global:UI_GRN } else { $global:UI_RED }
        $suffix = if ($exists) { "" } else { " (missing)" }
        Write-Host ("  {0}{1,2}){2}  {3}{4}{5}" -f $color, $index, $global:UI_R, $global:UI_WHT, $tool.Name, "$suffix$($global:UI_R)")
        if ($exists) { $script:ToolMap["$index"] = $path }
        $index++
    }

    Write-UiDivider
    Write-Host "  $($global:UI_CYN)$($global:UI_B)Games$($global:UI_R)"
    foreach ($tool in $GameTools) {
        $path = Join-Path $GamesPath $tool.File
        $exists = Test-Path $path
        $color = if ($exists) { $global:UI_GRN } else { $global:UI_RED }
        $suffix = if ($exists) { "" } else { " (missing)" }
        Write-Host ("  {0}{1,2}){2}  {3}{4}{5}" -f $color, $index, $global:UI_R, $global:UI_WHT, $tool.Name, "$suffix$($global:UI_R)")
        if ($exists) { $script:ToolMap["$index"] = $path }
        $index++
    }

    Write-UiDivider
    Write-Host "  $($global:UI_GRY) Q)$($global:UI_R)  Quit"
    Write-UiBlankLine
}

# ── Launch helper ─────────────────────────────────────────────
function Start-ToolScript {
    param(
        [Parameter(Mandatory)]
        [string]$ScriptPath
    )

    if (-not (Test-Path $ScriptPath)) {
        Write-CoreError "Script not found: $ScriptPath"
        Pause-Core "Press Enter to return..."
        return
    }

    try {
        # Launch child scripts through pwsh with ExecutionPolicy Bypass so
        # downloaded/generated scripts do not fail under RemoteSigned.
        $pwshCmd = Get-Command pwsh -ErrorAction SilentlyContinue

        if (-not $pwshCmd) {
            $pwshCmd = Get-Command powershell.exe -ErrorAction SilentlyContinue
        }

        if (-not $pwshCmd) {
            throw "Could not find pwsh or powershell.exe to launch: $ScriptPath"
        }

        & $pwshCmd.Source -NoProfile -ExecutionPolicy Bypass -File $ScriptPath
    } catch {
        Write-CoreError "Launch failed: $($_.Exception.Message)"
        Pause-Core "Press Enter to return..."
    }
}

# ── Main Loop ─────────────────────────────────────────────────
while ($true) {
    Show-Header
    Show-Menu
    $choice = (Read-UiChoice "Choice:").Trim().ToUpper()

    if ($choice -eq "Q") {
        Write-UiBlankLine
        Write-Host "  $($global:UI_CYN)  Bye.$($global:UI_R)"
        Write-UiBlankLine
        return
    }

    if ($script:ToolMap.ContainsKey($choice)) {
        Start-ToolScript -ScriptPath $script:ToolMap[$choice]
        continue
    }

    Write-CoreError "Invalid option."
    Start-Sleep -Seconds 1
}