#--------------------------------------------
# file:     tool-menu.ps1
# author:   Mike Redd
# version:  4.3
# created:  2026-03-30
# updated:  2026-07-05
# desc:     Unified script launcher (Admin + Personal + Games + MediaForge)
#--------------------------------------------

# ── Resolve base directories ──────────────────────────────────
function Get-OptionalGlobalValue {
    param([Parameter(Mandatory)][string]$Name)
    $v = Get-Variable -Name $Name -Scope Global -ErrorAction SilentlyContinue
    if ($v) { return $v.Value }
    return $null
}

$ExistingScriptsDir = Get-OptionalGlobalValue -Name 'PSScriptsDir'
$ExistingProfileDir = Get-OptionalGlobalValue -Name 'PSProfileDir'

if ($PSScriptRoot) {
    $rootLeaf = Split-Path $PSScriptRoot -Leaf
    if ($rootLeaf -ieq 'menu') {
        $ScriptsRoot = Split-Path $PSScriptRoot -Parent                # ...\scripts
    }
    elseif (Test-Path -LiteralPath (Join-Path $PSScriptRoot 'personaltools')) {
        $ScriptsRoot = $PSScriptRoot                                  # launched from ...\scripts
    }
    else {
        $ScriptsRoot = Split-Path $PSScriptRoot -Parent
    }
}
elseif ($ExistingScriptsDir) {
    $ScriptsRoot = $ExistingScriptsDir
}
else {
    $ScriptsRoot = Join-Path $HOME 'PS\scripts'
}

$PSRoot = Split-Path $ScriptsRoot -Parent
$ProfileCandidates = @(
    $ExistingProfileDir,
    (Join-Path $PSRoot 'profile.d'),
    $PSRoot
) | Where-Object { $_ } | Select-Object -Unique

function Resolve-SupportScript {
    param(
        [Parameter(Mandatory)][string]$Name,
        [string]$PreferredDir
    )

    $dirs = @($PreferredDir) + $ProfileCandidates
    foreach ($dir in ($dirs | Where-Object { $_ } | Select-Object -Unique)) {
        $candidate = Join-Path $dir $Name
        if (Test-Path -LiteralPath $candidate) { return $candidate }
    }
    return $null
}

# ── Load custom UI ────────────────────────────────────────────
$uiPath = Resolve-SupportScript -Name 'ui.ps1' -PreferredDir $ExistingProfileDir
if ($uiPath) {
    $PSProfileDir = Split-Path $uiPath -Parent
    try {
        . $uiPath
    } catch {
        Write-Host "Failed to load ui.ps1: $($_.Exception.Message)"
        return
    }
} else {
    Write-Host "Missing ui.ps1. Checked: $($ProfileCandidates -join ', ')"
    return
}

# ── Load core helper ──────────────────────────────────────────
$corePath = Resolve-SupportScript -Name 'core.ps1' -PreferredDir $PSProfileDir
if ($corePath) {
    try {
        . $corePath
    } catch {
        Write-Host "Failed to load core.ps1: $($_.Exception.Message)"
        if (Get-Command Pause-UiReturn -ErrorAction SilentlyContinue) { Pause-UiReturn "Press Enter to return..." }
        return
    }
} else {
    Write-Host "Missing core.ps1. Checked: $($ProfileCandidates -join ', ')"
    if (Get-Command Pause-UiReturn -ErrorAction SilentlyContinue) { Pause-UiReturn "Press Enter to return..." }
    return
}

$ScriptName    = "Tool Menu"
$ScriptVersion = "4.3"
$ScriptAuthor  = "Mike Redd"

# Keep child tools grounded even when the parent profile was not loaded.
$PSScriptsDir = $ScriptsRoot
$PSProfileDir = Split-Path $corePath -Parent

# ── Base script paths ─────────────────────────────────────────
$AdminPath    = Join-Path $ScriptsRoot "admintools"
$PersonalPath = Join-Path $ScriptsRoot "personaltools"
$GamesPath    = Join-Path $ScriptsRoot "games"

# ── Tool Definitions ──────────────────────────────────────────
$AdminTools = @(
    [PSCustomObject]@{ Name="Admin Dashboard (GUI)"; File="admin-menu-gui.ps1"; Gui=$true }
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
    [PSCustomObject]@{ Name="SpeedtestMenu";              File="speedtest-menu.ps1" }
    [PSCustomObject]@{ Name="WeatherFetch";               File="weatherfetch-menu.ps1" }
    [PSCustomObject]@{ Name="MediaForge IMDb Dump";       File="MediaForge\imdbdump.ps1";                  AltFiles=@("imdbdump.ps1") }
    [PSCustomObject]@{ Name="MediaForge Poster Grab";     File="MediaForge\imdbthumbgrab.ps1";             AltFiles=@("imdbthumbgrab.ps1") }

    [PSCustomObject]@{ Name="MediaForge (GUI)";           File="MediaForge\mediaforge-gui.ps1";            AltFiles=@("MediaForge\media-encoder-gui.ps1", "mediaforge-gui.ps1", "media-encoder-gui.ps1"); Gui=$true }
    [PSCustomObject]@{ Name="MediaForge CD Ripper (GUI)"; File="MediaForge\cd-ripper-gui.ps1";             AltFiles=@("cd-ripper-gui.ps1"); Gui=$true }
    [PSCustomObject]@{ Name="MediaForge DVD Encoder (GUI)"; File="MediaForge\dvd-ripper-encoder-gui.ps1";  AltFiles=@("dvd-ripper-encoder-gui.ps1"); Gui=$true }
    [PSCustomObject]@{ Name="MediaForge Blu-ray Encoder (GUI)"; File="MediaForge\BRencoder-gui.ps1";      AltFiles=@("BRencoder-gui.ps1"); Gui=$true }

    [PSCustomObject]@{ Name="MiNfoCreate";                File="MediaForge\minfocreate.ps1";               AltFiles=@("minfocreate.ps1") }
    [PSCustomObject]@{ Name="CD Image FLAC Ripper";       File="MediaForge\cd-image-flac.ps1";             AltFiles=@("cd-image-flac.ps1") }
    [PSCustomObject]@{ Name="CD Track FLAC Ripper";       File="MediaForge\cd-tracks-flac.ps1";            AltFiles=@("cd-tracks-flac.ps1") }
    [PSCustomObject]@{ Name="M3U Playlist Generator";     File="generate-playlists.ps1" }
    [PSCustomObject]@{ Name="DVD Encoder";                File="MediaForge\dvd-ripper-encoder.ps1";        AltFiles=@("dvd-ripper-encoder.ps1") }
    [PSCustomObject]@{ Name="Blu-ray Backup";             File="MediaForge\bluray-backup.ps1";             AltFiles=@("bluray-backup.ps1") }
    [PSCustomObject]@{ Name="Blu-ray Track Dump";         File="MediaForge\bluray-trackdump.ps1";          AltFiles=@("bluray-trackdump.ps1") }
    [PSCustomObject]@{ Name="Blu-ray Encoder";            File="MediaForge\BRencoder.ps1";                 AltFiles=@("BRencoder.ps1") }
    [PSCustomObject]@{ Name="MKV Sample";                 File="MediaForge\mkv-sample.ps1";                AltFiles=@("mkv-sample.ps1") }

    [PSCustomObject]@{ Name="Clip Video";                 File="clip-video.ps1" }
    [PSCustomObject]@{ Name="WebRipper";                  File="web-ripper.ps1" }
    [PSCustomObject]@{ Name="Atomic Clock";               File="AtomicClock.ps1"; Gui=$true }
    [PSCustomObject]@{ Name="Cadence (Audio Player)";     File="Cadence\cadence.ps1"; Gui=$true }
    [PSCustomObject]@{ Name="Parallax (Video Player)";    File="Parallax\parallax.ps1"; Gui=$true }
)

$GameTools = @(
    [PSCustomObject]@{ Name="Snake";       File="snake.ps1" }
    [PSCustomObject]@{ Name="Pong";        File="pong.ps1" }
    [PSCustomObject]@{ Name="2048";        File="2048.ps1" }
    [PSCustomObject]@{ Name="Minesweeper"; File="minesweeper.ps1" }
    [PSCustomObject]@{ Name="Breakout";    File="breakout.ps1" }
    [PSCustomObject]@{ Name="Tetris";      File="tetris.ps1" }
)

function Get-ToolCandidateFiles {
    param([Parameter(Mandatory)]$Tool)

    $files = @()
    if ($Tool.PSObject.Properties['File'] -and $Tool.File) { $files += [string]$Tool.File }
    if ($Tool.PSObject.Properties['AltFiles'] -and $Tool.AltFiles) { $files += @($Tool.AltFiles) }
    return ($files | Where-Object { $_ } | Select-Object -Unique)
}

function Resolve-ToolPath {
    param(
        [Parameter(Mandatory)][string]$BasePath,
        [Parameter(Mandatory)]$Tool
    )

    $first = $null
    foreach ($file in (Get-ToolCandidateFiles -Tool $Tool)) {
        $candidate = if ([System.IO.Path]::IsPathRooted($file)) { $file } else { Join-Path $BasePath $file }
        if (-not $first) { $first = $candidate }
        if (Test-Path -LiteralPath $candidate) {
            return [PSCustomObject]@{ Exists=$true; Path=$candidate }
        }
    }

    return [PSCustomObject]@{ Exists=$false; Path=$first }
}

function Test-ToolIsGui {
    param(
        [Parameter(Mandatory)]$Tool,
        [Parameter(Mandatory)][string]$Path
    )

    if ($Tool.PSObject.Properties['Gui'] -and $Tool.Gui -eq $true) { return $true }
    return ($Path -like '*-gui.ps1')
}

# ── Header ────────────────────────────────────────────────────
function Show-Header {
    Clear-UiScreen
    $BoxWidth = Get-UiBoxWidth -MaxWidth 72 -MinWidth 48

    Write-UiHeader -Title $ScriptName -Subtitle "v$ScriptVersion  by $ScriptAuthor" -Width $BoxWidth
    Write-UiRow "User" "$env:USERNAME@$env:COMPUTERNAME"
    Write-UiRow "Scripts" $ScriptsRoot -ValueColor $global:UI_GRY
    Write-UiRow "Admin Path" $AdminPath -ValueColor $global:UI_GRY
    Write-UiRow "Personal Path" $PersonalPath -ValueColor $global:UI_GRY
    Write-UiRow "Games Path" $GamesPath -ValueColor $global:UI_GRY
    Write-UiBlankLine
}

# ── Menu ──────────────────────────────────────────────────────
function Write-ToolGroup {
    param(
        [Parameter(Mandatory)][string]$Title,
        [Parameter(Mandatory)]$Tools,
        [Parameter(Mandatory)][string]$BasePath,
        [Parameter(Mandatory)][ref]$Index
    )

    Write-UiDivider
    Write-Host "  $($global:UI_CYN)$($global:UI_B)$Title$($global:UI_R)"
    foreach ($tool in $Tools) {
        $info   = Resolve-ToolPath -BasePath $BasePath -Tool $tool
        $exists = [bool]$info.Exists
        $color  = if ($exists) { $global:UI_GRN } else { $global:UI_RED }
        $suffix = if ($exists) { "" } else { " (missing)" }
        Write-Host ("  {0}{1,2}){2}  {3}{4}{5}" -f $color, $Index.Value, $global:UI_R, $global:UI_WHT, $tool.Name, "$suffix$($global:UI_R)")
        if ($exists) {
            $script:ToolMap["$($Index.Value)"] = [PSCustomObject]@{
                Path = $info.Path
                Gui  = (Test-ToolIsGui -Tool $tool -Path $info.Path)
            }
        }
        $Index.Value++
    }
}

function Show-Menu {
    $index = 1
    $script:ToolMap = @{}

    Write-ToolGroup -Title 'Admin Tools'    -Tools $AdminTools    -BasePath $AdminPath    -Index ([ref]$index)
    Write-ToolGroup -Title 'Personal Tools' -Tools $PersonalTools -BasePath $PersonalPath -Index ([ref]$index)
    Write-ToolGroup -Title 'Games'          -Tools $GameTools     -BasePath $GamesPath    -Index ([ref]$index)

    Write-UiDivider
    Write-Host "  $($global:UI_GRY) Q)$($global:UI_R)  Quit"
    Write-UiBlankLine
}

# ── Launch helper ─────────────────────────────────────────────
function Start-ToolScript {
    param(
        [Parameter(Mandatory)]
        [string]$ScriptPath,
        [switch]$IsGui
    )

    if (-not (Test-Path -LiteralPath $ScriptPath)) {
        Write-CoreError "Script not found: $ScriptPath"
        Pause-Core "Press Enter to return..."
        return
    }

    try {
        if ($IsGui) {
            # GUI tools are WinForms/WPF and need STA.
            # Prefer PowerShell 7+ for MediaForge/Cadence-era GUIs, then fall
            # back to Windows PowerShell. Launch detached so this menu remains usable.
            $work = Split-Path $ScriptPath -Parent

            $pwshCmd = Get-Command pwsh.exe -ErrorAction SilentlyContinue
            if (-not $pwshCmd) { $pwshCmd = Get-Command pwsh -ErrorAction SilentlyContinue }
            $winPS = Get-Command powershell.exe -ErrorAction SilentlyContinue

            if ($pwshCmd) {
                $hostExe = $pwshCmd.Source
            } elseif ($winPS) {
                $hostExe = $winPS.Source
            } else {
                throw "Neither pwsh.exe nor powershell.exe found to launch the GUI: $ScriptPath"
            }

            $argLine = "-NoProfile -ExecutionPolicy Bypass -STA -File `"$ScriptPath`""
            Start-Process -FilePath $hostExe -ArgumentList $argLine -WorkingDirectory $work

            Write-Host ("  {0}Launched:{1} {2}  {3}via {4} -STA; menu stays open{5}" -f `
                $global:UI_GRN, $global:UI_R, (Split-Path $ScriptPath -Leaf), $global:UI_GRY, (Split-Path $hostExe -Leaf), $global:UI_R)
            Start-Sleep -Milliseconds 700
            return
        }

        # Console tools run INLINE so you interact with them and return here.
        # Run from the script's own folder so MediaForge helper tools resolve
        # local sidecars/assets exactly like direct launches.
        $pwshCmd = Get-Command pwsh.exe -ErrorAction SilentlyContinue
        if (-not $pwshCmd) { $pwshCmd = Get-Command pwsh -ErrorAction SilentlyContinue }
        if (-not $pwshCmd) { $pwshCmd = Get-Command powershell.exe -ErrorAction SilentlyContinue }
        if (-not $pwshCmd) { throw "Could not find pwsh or powershell.exe to launch: $ScriptPath" }

        # -NoProfile keeps the child clean, so pass the known roots explicitly.
        $pp = "$PSProfileDir" -replace "'", "''"
        $ps = "$ScriptsRoot"  -replace "'", "''"
        $sp = "$ScriptPath"   -replace "'", "''"
        $wd = "$(Split-Path $ScriptPath -Parent)" -replace "'", "''"
        $bootstrap = "`$PSProfileDir = '$pp'; `$PSScriptsDir = '$ps'; Push-Location '$wd'; try { & '$sp' } finally { Pop-Location }"

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
        $entry = $script:ToolMap[$choice]
        Start-ToolScript -ScriptPath $entry.Path -IsGui:$entry.Gui
        continue
    }

    Write-CoreError "Invalid option."
    Start-Sleep -Seconds 1
}
