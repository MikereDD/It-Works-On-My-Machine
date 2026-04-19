#--------------------------------------------
# file:     tool-menu.ps1
# author:   Mike Redd
# version:  2.9
# created:  2026-03-30
# updated:  2026-04-19
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
$ScriptVersion = "2.9"
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
    [PSCustomObject]@{ Name="SpeedtestMenu";    File="speedtest-menu.ps1" }
    [PSCustomObject]@{ Name="WeatherFetch";     File="weatherfetch-menu.ps1" }
    [PSCustomObject]@{ Name="ImdbDump";         File="imdbdump.ps1" }
    [PSCustomObject]@{ Name="ImdbThumbGrab";    File="imdbthumbgrab.ps1" }
    [PSCustomObject]@{ Name="MiNfoCreate";      File="minfocreate.ps1" }

    [PSCustomObject]@{ Name="CD Image FLAC Ripper"; File="cd-image-flac.ps1" }
    [PSCustomObject]@{ Name="CD Track FLAC Ripper"; File="cd-tracks-flac.ps1" }
    [PSCustomObject]@{ Name="DVD Encoder";        File="dvd-ripper-encoder.ps1" }
    [PSCustomObject]@{ Name="Blu-ray Backup";     File="bluray-backup.ps1" }
    [PSCustomObject]@{ Name="M2TS Largest Copy";  File="m2ts-largest-copy.ps1" }
    [PSCustomObject]@{ Name="Blu-ray Encoder";    File="BRencoder.ps1" }
    [PSCustomObject]@{ Name="WebRipper";          File="web-ripper.ps1" }
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
    $BoxWidth = Get-UiBoxWidth -MaxWidth 52 -MinWidth 40

    Write-UiHeader -Title $ScriptName -Subtitle "v$ScriptVersion  by $ScriptAuthor" -Width $BoxWidth
    Write-UiRow "User" "$env:USERNAME@$env:COMPUTERNAME"
    Write-UiRow "Admin Path" $AdminPath -ValueColor $global:UI_GRY
    Write-UiRow "Personal Path" $PersonalPath -ValueColor $global:UI_GRY
    Write-UiRow "Games Path" $GamesPath -ValueColor $global:UI_GRY
    Write-UiBlankLine
}

# ── (rest of your file unchanged) ─────────────────────────────