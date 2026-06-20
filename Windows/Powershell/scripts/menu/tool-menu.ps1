#--------------------------------------------
# file:     tool-menu.ps1
# author:   Mike Redd
# version:  3.8
# created:  2026-03-30
# updated:  2026-06-19
# desc:     Unified script launcher (Admin + Personal + Games)
#--------------------------------------------

# ── Resolve base directories ──────────────────────────────────
# This file lives in <scripts>\menu\, so the scripts root is ALWAYS the
# parent of our own folder. Derive it from $PSScriptRoot so tool discovery
# never depends on a profile-provided / forwarded $PSScriptsDir being right.
# (A wrong-but-set $PSScriptsDir was making every tool resolve to a missing
# path, so picking one returned "Invalid option".)
if ($PSScriptRoot) {
    $ScriptsRoot = Split-Path $PSScriptRoot -Parent                # ...\scripts
} elseif ($PSScriptsDir) {
    $ScriptsRoot = $PSScriptsDir
} else {
    $ScriptsRoot = 'C:\Users\miker\PS\scripts'                     # last-resort fallback
}

# ui.ps1 / core.ps1 come from the profile dir. Keep the profile value if set,
# otherwise fall back to the PS root (the parent of scripts).
if (-not $PSProfileDir) { $PSProfileDir = Split-Path $ScriptsRoot -Parent }   # ...\PS

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
$ScriptVersion = "3.8"
$ScriptAuthor  = "Mike Redd"

# ── Base script paths ─────────────────────────────────────────
$AdminPath    = Join-Path $ScriptsRoot "admintools"
$PersonalPath = Join-Path $ScriptsRoot "personaltools"
$GamesPath    = Join-Path $ScriptsRoot "games"

# ── Tool Definitions ──────────────────────────────────────────
$AdminTools = @(
    [PSCustomObject]@{ Name="Admin Dashboard (GUI)"; File="admin-menu-gui.ps1" }
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
    [PSCustomObject]@{ Name="CD FLAC Ripper (GUI)";  File="cd-ripper-gui.ps1" }
    [PSCustomObject]@{ Name="M3U Playlist Generator";File="generate-playlists.ps1" }
    [PSCustomObject]@{ Name="DVD Encoder";           File="dvd-ripper-encoder.ps1" }
    [PSCustomObject]@{ Name="DVD Encoder (GUI)";     File="dvd-ripper-encoder-gui.ps1" }
    [PSCustomObject]@{ Name="Blu-ray Backup";        File="bluray-backup.ps1" }
    [PSCustomObject]@{ Name="Blu-ray Track Dump";	 File="bluray-trackdump.ps1" }
    [PSCustomObject]@{ Name="Blu-ray Encoder";       File="BRencoder.ps1" }
    [PSCustomObject]@{ Name="Blu-ray Encoder (GUI)"; File="BRencoder-gui.ps1" }
    [PSCustomObject]@{ Name="MKV Sample";            File="mkv-sample.ps1" }
	[PSCustomObject]@{ Name="Clip Video";            File="clip-video.ps1" }
	[PSCustomObject]@{ Name="Media Encoder (GUI)";     File="media-encoder-gui.ps1" }
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
        # GUI tools (convention: *-gui.ps1) are WinForms and must run under
        # Windows PowerShell in a single-threaded apartment (-STA). pwsh is MTA
        # and unreliable for WinForms, so force powershell.exe here. -File gives
        # the GUI a correct $PSScriptRoot so it finds its sibling engine script.
        if ($ScriptPath -like '*-gui.ps1') {
            $winPS = Get-Command powershell.exe -ErrorAction SilentlyContinue
            if (-not $winPS) {
                throw "powershell.exe (Windows PowerShell) is required for the GUI: $ScriptPath"
            }
            & $winPS.Source -NoProfile -ExecutionPolicy Bypass -STA -File $ScriptPath
            return
        }

        # Launch child scripts through pwsh with ExecutionPolicy Bypass so
        # downloaded/generated scripts do not fail under RemoteSigned.
        $pwshCmd = Get-Command pwsh -ErrorAction SilentlyContinue

        if (-not $pwshCmd) {
            $pwshCmd = Get-Command powershell.exe -ErrorAction SilentlyContinue
        }

        if (-not $pwshCmd) {
            throw "Could not find pwsh or powershell.exe to launch: $ScriptPath"
        }

        # -NoProfile keeps the child session clean/fast, but it also means the
        # child never runs $PROFILE -- so it would have no $PSProfileDir /
        # $PSScriptsDir and would fail to load ui.ps1 / core.ps1. Forward those
        # paths into the child session explicitly so it can bootstrap itself.
        # Using -Command with `& '<path>'` still gives the child a correct
        # $PSScriptRoot, same as -File would.
        $pp = "$PSProfileDir" -replace "'", "''"
        $ps = "$ScriptsRoot"  -replace "'", "''"
        $sp = "$ScriptPath"   -replace "'", "''"
        $bootstrap = "`$PSProfileDir = '$pp'; `$PSScriptsDir = '$ps'; & '$sp'"

        & $pwshCmd.Source -NoProfile -ExecutionPolicy Bypass -Command $bootstrap
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
