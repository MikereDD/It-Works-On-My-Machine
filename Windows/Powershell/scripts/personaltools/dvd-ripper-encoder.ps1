#--------------------------------------------
# file:     dvd-ripper-encoder.ps1
# author:   Mike Redd
# version:  4.6.1
# created:  2026-04-11
# updated:  2026-06-21
# desc:     Encode DVDs directly with HandBrakeCLI on Windows
#           using high-quality x265 defaults. Sibling pipeline
#           to BRencoder.ps1: DVDTrackMeta sidecars, mkvpropedit
#           language remux, source archiving, and -AutoAccept
#           for unattended encodes.
#           v4.2: auto-install libdvdcss (version-discovery fetch)
#                 bitness-matched, cached, self-healing on updates.
#           v4.3: stream HandBrake output + exit-code check on encode.
#           v4.4: fix encode binding — allow empty (no) x265 tune.
#           v4.5: fix HandBrake args — --loose-anamorphic (was --anamorphic loose).
#           v4.6: best-quality MKV defaults — detelecine + decomb for
#                 film DVDs, VFR (was CFR) so 3:2 film resolves to
#                 23.976p, and FLAC audio fallback (was eac3) to keep
#                 LPCM tracks lossless.
#           v4.6.1: fix invalid HandBrake fallback codec (flac -> flac24)
#                   that failed job init; drop redundant --audio-copy-mask.
#--------------------------------------------

param(
    [switch]$DryRun,
    [switch]$AutoAccept
)

# ── Load custom UI ────────────────────────────────────────────
$uiPath = "$env:USERPROFILE\PS\profile.d\ui.ps1"
if (Test-Path -LiteralPath $uiPath) {
    try { . $uiPath }
    catch {
        Write-Host "Failed to load ui.ps1: $($_.Exception.Message)"
        return
    }
}
else {
    Write-Host "Missing ui.ps1: $uiPath"
    return
}

# ── Load core helper ──────────────────────────────────────────
$corePath = "$env:USERPROFILE\PS\profile.d\core.ps1"
if (Test-Path -LiteralPath $corePath) {
    try { . $corePath }
    catch {
        Write-Host "Failed to load core.ps1: $($_.Exception.Message)"
        return
    }
}
else {
    Write-Host "Missing core.ps1: $corePath"
    return
}

$ErrorActionPreference = 'Stop'

$ScriptName    = "DVD Ripper Encoder"
$ScriptVersion = "4.6.1"
$ScriptAuthor  = "Mike Redd"

# ── Config ────────────────────────────────────────────────────
$Script:RootPath         = "G:\Rip"
$Script:OutputRoot       = Join-Path $Script:RootPath 'dvdarchive'
$Script:NfoRoot          = Join-Path $Script:RootPath 'nfo'
$Script:MetaRoot         = Join-Path $Script:RootPath 'meta'
$Script:SourceRoot       = Join-Path $Script:RootPath 'dvdsource'
$Script:DefaultDrive     = 'D:'
$Script:HandBrakeCLI     = $null
$Script:MkvPropEdit      = $null

$Script:DefaultContainer = 'mkv'
$Script:DefaultEncoder   = 'x265_10bit'
$Script:DefaultRF        = 20
$Script:DefaultPreset    = 'slower'
$Script:MinTitleSeconds  = 900   # 15 min

$Script:MetaSchema       = 'DVDTrackMeta/1.0'
$Script:ArchiveSource    = $true   # copy VIDEO_TS to dvdsource\ after a clean encode

# ── Header ────────────────────────────────────────────────────
function Show-Header {
    Clear-UiScreen
    $w = Get-UiBoxWidth -MaxWidth 70 -MinWidth 48

    Write-UiHeader -Title $ScriptName -Subtitle "v$ScriptVersion  by $ScriptAuthor" -Width $w
    Write-UiRow "User"     "$env:USERNAME@$env:COMPUTERNAME"
    Write-UiRow "Defaults" "$($Script:DefaultEncoder) / RF $($Script:DefaultRF) / $($Script:DefaultPreset) / $($Script:DefaultContainer)" $global:UI_GRY
    if ($DryRun) {
        Write-UiRow "Mode" "DRY RUN — no files will be written" $global:UI_YLW
    }
    if ($AutoAccept) {
        Write-UiRow "Mode" "AUTO-ACCEPT — defaults, no prompts" $global:UI_YLW
    }
    Write-UiBlankLine
}

# ── Menu ──────────────────────────────────────────────────────
function Show-Menu {
    Write-UiDivider
    Write-Host "  $($global:UI_GRN)  1)$($global:UI_R)  Encode directly from DVD"
    Write-Host "  $($global:UI_GRN)  2)$($global:UI_R)  Scan DVD titles only"
    Write-Host "  $($global:UI_GRN)  3)$($global:UI_R)  Encode from existing folder"
    Write-UiDivider
    Write-Host "  $($global:UI_MAG)  4)$($global:UI_R)  Write track-meta sidecar (scan → meta)"
    Write-Host "  $($global:UI_MAG)  5)$($global:UI_R)  Remux MKV languages (standalone)"
    Write-UiDivider
    Write-Host "  $($global:UI_CYN)  6)$($global:UI_R)  Show config"
    Write-UiDivider
    Write-Host "  $($global:UI_GRY)  Q)$($global:UI_R)  Quit"
    Write-UiBlankLine
}

function Pause-Script {
    Pause-Core "Press Enter to return to menu..."
}

function Test-CommandExists {
    param([Parameter(Mandatory)][string]$Name)
    return [bool](Get-Command $Name -ErrorAction SilentlyContinue)
}

function Get-HandBrakeCLIPath {
    if ($Script:HandBrakeCLI -and (Test-Path -LiteralPath $Script:HandBrakeCLI)) {
        return [string]$Script:HandBrakeCLI
    }

    $paths = @(
        'C:\Program Files\HandBrake\HandBrakeCLI.exe',
        "$env:LOCALAPPDATA\Programs\HandBrake\HandBrakeCLI.exe",
        'C:\Tools\HandBrake\HandBrakeCLI.exe'
    )

    foreach ($p in $paths) {
        if (Test-Path -LiteralPath $p) {
            return [string]$p
        }
    }

    $cmd = Get-Command HandBrakeCLI -ErrorAction SilentlyContinue
    if ($cmd -and $cmd.Source -and (Test-Path -LiteralPath $cmd.Source)) {
        return [string]$cmd.Source
    }

    return $null
}

function Get-MkvPropEditPath {
    if ($Script:MkvPropEdit -and (Test-Path -LiteralPath $Script:MkvPropEdit)) {
        return [string]$Script:MkvPropEdit
    }

    $paths = @(
        'C:\Program Files\MKVToolNix\mkvpropedit.exe',
        'C:\Program Files (x86)\MKVToolNix\mkvpropedit.exe',
        "$env:LOCALAPPDATA\Programs\MKVToolNix\mkvpropedit.exe",
        'C:\Tools\MKVToolNix\mkvpropedit.exe'
    )

    foreach ($p in $paths) {
        if (Test-Path -LiteralPath $p) {
            return [string]$p
        }
    }

    $cmd = Get-Command mkvpropedit -ErrorAction SilentlyContinue
    if ($cmd -and $cmd.Source -and (Test-Path -LiteralPath $cmd.Source)) {
        return [string]$cmd.Source
    }

    return $null
}

function Get-DvdVolumeLabel {
    param([Parameter(Mandatory)][string]$DriveLetter)

    $letter = $DriveLetter.Trim().TrimEnd(':').Substring(0, 1)
    try {
        $vol = Get-Volume -DriveLetter $letter -ErrorAction Stop
        if ($vol -and -not [string]::IsNullOrWhiteSpace($vol.FileSystemLabel)) {
            # DVD labels are usually ALLCAPS_WITH_UNDERSCORES — make them friendlier.
            $label = $vol.FileSystemLabel.Trim()
            $label = ($label -replace '_', ' ')
            $label = (Get-Culture).TextInfo.ToTitleCase($label.ToLowerInvariant())
            return [string]$label
        }
    }
    catch { }

    return ''
}

function Ensure-Directories {
    foreach ($p in @($Script:RootPath, $Script:OutputRoot, $Script:NfoRoot, $Script:MetaRoot, $Script:SourceRoot)) {
        if (-not (Test-Path -LiteralPath $p)) {
            [System.IO.Directory]::CreateDirectory($p) | Out-Null
        }
    }
}

# Read the PE "Machine" field of a Windows binary so we never pair a 32-bit
# libdvdcss with a 64-bit HandBrake (or vice-versa). Returns 0x8664 (x64),
# 0x14c (x86), or 0 if it can't be read.
function Get-PEMachine {
    param([Parameter(Mandatory)][string]$Path)
    try {
        $fs = [System.IO.File]::OpenRead($Path)
        try {
            $br = New-Object System.IO.BinaryReader($fs)
            $fs.Position = 0x3C
            $peOff = $br.ReadInt32()
            if ($peOff -le 0 -or $peOff -gt ($fs.Length - 6)) { return 0 }
            $fs.Position = $peOff
            if ($br.ReadUInt32() -ne 0x00004550) { return 0 }   # 'PE\0\0'
            return [int]$br.ReadUInt16()
        }
        finally { $fs.Dispose() }
    }
    catch { return 0 }
}

# Build an ordered list of libdvdcss download URLs, newest-first. VideoLAN has
# no '/last/' symlink — versions live under /<x.y.z>/<arch>/ — so we read the
# directory index to find the newest build, then append known-good fallbacks.
function Get-LibDvdCssUrls {
    param([Parameter(Mandatory)][string]$Arch)   # 'win64' | 'win32'

    $base     = 'https://download.videolan.org/pub/libdvdcss'
    $versions = @()
    try {
        try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 } catch { }
        $idx = (Invoke-WebRequest -Uri "$base/" -UseBasicParsing -TimeoutSec 30).Content
        $versions = @([regex]::Matches($idx, 'href="(\d+\.\d+\.\d+)/"') | ForEach-Object { $_.Groups[1].Value }) |
                    Sort-Object { [version]$_ } -Descending
    }
    catch { }

    # Versions known to ship prebuilt Windows binaries (newest-first), used if the
    # index can't be read or as a backstop after it.
    $fallback = @('1.4.3', '1.4.2', '1.4.0', '1.3.0', '1.2.13', '1.2.12', '1.2.11')

    $ordered = @($versions + $fallback) | Select-Object -Unique
    return $ordered | ForEach-Object { "$base/$_/$Arch/libdvdcss-2.dll" }
}

# HandBrake removed its built-in CSS support long ago, so a retail (CSS) DVD
# scans as zero titles unless libdvdcss-2.dll sits next to HandBrakeCLI.exe.
# This makes that self-healing:
#   1. already present            -> done
#   2. cached from a prior run    -> copy into place (survives WinGet upgrades cheaply)
#   3. VLC's bundled copy         -> cache + copy (bitness-matched)
#   4. download from VideoLAN     -> tries newest build first, falls through versions
# Never throws; a retail DVD just stays unreadable if every source fails.
function Ensure-LibDvdCss {
    param([Parameter(Mandatory)][string]$HandBrakeExe)

    if ([string]::IsNullOrWhiteSpace($HandBrakeExe) -or -not (Test-Path -LiteralPath $HandBrakeExe)) {
        return [pscustomobject]@{ Status = 'no-handbrake' }
    }

    $hbDir  = Split-Path -Parent $HandBrakeExe
    $target = Join-Path $hbDir 'libdvdcss-2.dll'
    if (Test-Path -LiteralPath $target) {
        return [pscustomobject]@{ Status = 'present'; Path = $target }
    }

    $hbMachine = Get-PEMachine -Path $HandBrakeExe
    if ($hbMachine -ne 0x8664 -and $hbMachine -ne 0x14c) { $hbMachine = 0x8664 }  # assume x64 if unreadable
    $arch = if ($hbMachine -eq 0x14c) { 'win32' } else { 'win64' }

    $cacheDir = Join-Path $env:LOCALAPPDATA 'MediaEncoderGUI'
    $cache    = Join-Path $cacheDir "libdvdcss-2.$arch.dll"
    if (-not (Test-Path -LiteralPath $cacheDir)) {
        try { [void](New-Item -ItemType Directory -Force -Path $cacheDir) } catch { }
    }

    function Copy-Css { param($from, $to) try { Copy-Item -LiteralPath $from -Destination $to -Force; return (Test-Path -LiteralPath $to) } catch { return $false } }
    function Test-CssDll { param($p) (Test-Path -LiteralPath $p) -and ((Get-Item -LiteralPath $p).Length -gt 20000) -and ((Get-PEMachine -Path $p) -eq $hbMachine) }

    # 2) cache hit
    if (Test-Path -LiteralPath $cache) {
        if (Copy-Css $cache $target) {
            return [pscustomobject]@{ Status = 'restored-from-cache'; Path = $target }
        }
    }

    # 3) VLC's bundled copy (only if its bitness matches HandBrake)
    $vlc = @(
        (Join-Path $env:ProgramFiles 'VideoLAN\VLC\libdvdcss-2.dll'),
        (Join-Path ${env:ProgramFiles(x86)} 'VideoLAN\VLC\libdvdcss-2.dll')
    ) | Where-Object { $_ -and (Test-Path -LiteralPath $_) -and (Get-PEMachine -Path $_) -eq $hbMachine } | Select-Object -First 1
    if ($vlc) {
        [void](Copy-Css $vlc $cache)
        if (Copy-Css $vlc $target) {
            return [pscustomobject]@{ Status = 'copied-from-vlc'; Path = $target; Source = $vlc }
        }
    }

    # 4) download from VideoLAN — try newest build first, fall through versions
    try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 } catch { }
    $urls    = Get-LibDvdCssUrls -Arch $arch
    $tmp     = Join-Path $cacheDir "libdvdcss-2.$arch.tmp"
    $lastErr = 'no candidate URLs'
    foreach ($u in $urls) {
        try {
            if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue }
            Invoke-WebRequest -Uri $u -OutFile $tmp -UseBasicParsing -TimeoutSec 60
            if (Test-CssDll $tmp) {
                Move-Item -LiteralPath $tmp -Destination $cache -Force
                if (Copy-Css $cache $target) {
                    return [pscustomobject]@{ Status = 'downloaded'; Path = $target; Source = $u }
                }
                $lastErr = "downloaded but could not place into $hbDir"
            }
            else {
                $lastErr = "validation failed (size/bitness) for $u"
                try { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue } catch { }
            }
        }
        catch { $lastErr = "$($_.Exception.Message)  [$u]" }
    }
    return [pscustomobject]@{ Status = 'failed'; Arch = $arch; Error = $lastErr }
}

function Ensure-Dependencies {
    $resolvedCli = Get-HandBrakeCLIPath
    if (-not $resolvedCli) {
        throw "HandBrakeCLI was not found."
    }

    $Script:HandBrakeCLI = $resolvedCli

    # Make sure HandBrake can actually decrypt retail DVDs (auto-install libdvdcss).
    $css = Ensure-LibDvdCss -HandBrakeExe $Script:HandBrakeCLI
    switch ($css.Status) {
        'present'             { Write-Host "  $($global:UI_GRY)libdvdcss present — retail DVDs OK.$($global:UI_R)" }
        'restored-from-cache' { Write-Host "  $($global:UI_GRN)libdvdcss restored from cache (post-update).$($global:UI_R)" }
        'copied-from-vlc'     { Write-Host "  $($global:UI_GRN)libdvdcss installed from VLC.$($global:UI_R)" }
        'downloaded'          { Write-Host "  $($global:UI_GRN)libdvdcss downloaded from VideoLAN and installed.$($global:UI_R)" }
        'failed'              {
            Write-Host "  $($global:UI_YLW)Could not auto-install libdvdcss ($($css.Arch)).$($global:UI_R)"
            Write-Host "  $($global:UI_GRY)Reason: $($css.Error)$($global:UI_R)"
            Write-Host "  $($global:UI_GRY)Retail DVDs will scan as 0 titles. Install VLC, or drop $($css.Arch) libdvdcss-2.dll next to HandBrakeCLI.exe.$($global:UI_R)"
        }
    }

    # mkvpropedit is optional — only needed for the language remux step.
    $resolvedMkv = Get-MkvPropEditPath
    if ($resolvedMkv) {
        $Script:MkvPropEdit = $resolvedMkv
    }
    else {
        $Script:MkvPropEdit = $null
        Write-Host "  $($global:UI_YLW)mkvpropedit not found — language remux will be skipped.$($global:UI_R)"
        Write-Host "  $($global:UI_GRY)Install MKVToolNix to enable it.$($global:UI_R)"
    }
}

function New-SafeName {
    param([Parameter(Mandatory)][string]$Name)

    $safe = $Name -replace '[\\\/:\*\?"<>\|]', '_'
    $safe = $safe.Trim()

    if ([string]::IsNullOrWhiteSpace($safe)) {
        $safe = "dvd_encode_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
    }

    return [string]$safe
}

function Get-DvdSourcePath {
    param([string]$DriveLetter = $Script:DefaultDrive)

    $drive = $DriveLetter.Trim()
    if ($drive -notmatch ':$') { $drive += ':' }

    $videoTs = Join-Path $drive 'VIDEO_TS'
    if (Test-Path -LiteralPath $videoTs) {
        return [string]$drive
    }

    throw "No VIDEO_TS folder found on $drive"
}

function Resolve-HandBrakeInputPath {
    param([Parameter(Mandatory)][string]$Path)

    if ($Path -match '^[A-Za-z]:$') {
        return [string]$Path
    }

    try {
        $resolved = (Resolve-Path -LiteralPath $Path -ErrorAction Stop).Path
    }
    catch {
        throw "Input path not found: $Path"
    }

    $videoTs = Join-Path $resolved 'VIDEO_TS'
    if (Test-Path -LiteralPath $videoTs) {
        return [string]$videoTs
    }

    return [string]$resolved
}

function Get-TrackLangFromDesc {
    # Parses a HandBrake track line tail like:
    #   "English (AC3) (2.0 ch) (iso639-2: eng), 48000Hz, 192000bps"
    #   "English (iso639-2: eng) (Bitmap)(VOBSUB)"
    # and returns a friendly label such as "English (eng)".
    param([Parameter(Mandatory)][string]$Desc)

    $name = ''
    if ($Desc -match '^\s*([^(,]+?)\s*(?:\(|,|$)') {
        $name = $matches[1].Trim()
    }

    $code = ''
    if ($Desc -match 'iso639-2:\s*([A-Za-z]{2,3})') {
        $code = $matches[1].ToLowerInvariant()
    }

    $label =
        if     ($name -and $code) { "$name ($code)" }
        elseif ($name)            { $name }
        elseif ($code)            { $code }
        else                      { 'unknown' }

    return @{ Name = $name; Code = $code; Label = $label }
}

function Invoke-HandBrakeScan {
    param([Parameter(Mandatory)][string]$InputPath)

    $resolvedInput = Resolve-HandBrakeInputPath -Path $InputPath

    Write-UiBlankLine
    Write-Host "  $($global:UI_GRN)Scanning titles with HandBrakeCLI...$($global:UI_R)"
    Write-Host ("  {0}Using{1}  {2}" -f $global:UI_DIM, $global:UI_R, $Script:HandBrakeCLI)
    Write-Host ("  {0}Input{1}  {2}" -f $global:UI_DIM, $global:UI_R, $resolvedInput)
    Write-UiBlankLine

    $scanOutput = & $Script:HandBrakeCLI `
        --input $resolvedInput `
        --title 0 `
        --scan `
        --min-duration $Script:MinTitleSeconds 2>&1

    $scanText = ($scanOutput | Out-String)

    $titles       = @()
    $currentTitle = $null
    $section      = $null   # 'audio' | 'subtitle' | $null

    foreach ($line in ($scanText -split "`r?`n")) {
        if ($line -match '^\+\s+title\s+(\d+):') {
            if ($null -ne $currentTitle) {
                $titles += [pscustomobject]$currentTitle
            }

            $currentTitle = @{
                Title        = [int]$matches[1]
                Duration     = ''
                Size         = ''
                AudioTracks  = 0
                AudioList    = @()
                SubtitleList = @()
                Raw          = @()
            }
            $section = $null
        }

        if ($null -ne $currentTitle) {
            $currentTitle.Raw += $line

            if ($line -match '^\s*\+\s+duration:\s+(.+)$') {
                $currentTitle.Duration = $matches[1].Trim()
            }
            elseif ($line -match '^\s*\+\s+size:\s+(.+)$') {
                $currentTitle.Size = $matches[1].Trim()
            }
            elseif ($line -match '^\s*\+\s+audio tracks:\s*$') {
                $section = 'audio'
            }
            elseif ($line -match '^\s*\+\s+subtitle tracks:\s*$') {
                $section = 'subtitle'
            }
            elseif ($line -match '^\s*\+\s+\w[\w ]*:\s*$') {
                # any other sub-header (chapters, etc.) ends track parsing
                $section = $null
            }
            elseif ($line -match '^\s*\+\s+(\d+),\s*(.+)$') {
                $trackNum  = [int]$matches[1]
                $trackDesc = $matches[2].Trim()
                $lang      = Get-TrackLangFromDesc -Desc $trackDesc

                if ($section -eq 'audio') {
                    $currentTitle.AudioTracks++
                    $currentTitle.AudioList += [pscustomobject]@{
                        Num   = $trackNum
                        Lang  = $lang.Label
                        Code  = $lang.Code
                        Desc  = $trackDesc
                    }
                }
                elseif ($section -eq 'subtitle') {
                    $currentTitle.SubtitleList += [pscustomobject]@{
                        Num   = $trackNum
                        Lang  = $lang.Label
                        Code  = $lang.Code
                        Desc  = $trackDesc
                    }
                }
            }
        }
    }

    if ($null -ne $currentTitle) {
        $titles += [pscustomobject]$currentTitle
    }

    if ($titles.Count -eq 0) {
        Write-CoreError "No titles detected."
        Write-Host $scanText
    }
    else {
        Write-Host "  $($global:UI_MAG)Detected titles:$($global:UI_R)"
        $titles | Select-Object Title, Duration, Size, AudioTracks | Format-Table -AutoSize | Out-Host
    }

    return @{
        Titles   = $titles
        ScanText = $scanText
    }
}

function Get-DurationSeconds {
    param([string]$Duration)

    if ($Duration -match '^\d{2}:\d{2}:\d{2}$') {
        return [int][TimeSpan]::Parse($Duration).TotalSeconds
    }

    return 0
}

function Get-MainTitle {
    param([Parameter(Mandatory)]$Titles)

    if (-not $Titles -or $Titles.Count -eq 0) {
        throw "No titles available."
    }

    return $Titles |
        Sort-Object { Get-DurationSeconds $_.Duration } -Descending |
        Select-Object -First 1
}

function Get-AutoTune {
    param([Parameter(Mandatory)][string]$MovieName)

    $name = $MovieName.ToLowerInvariant()

    if ($name -match 'anime|animation|animated|cartoon|pixar|disney|dreamworks|ghibli|miyazaki') {
        return @{ Tune = 'animation'; Note = 'detected animation keywords' }
    }

    if ($name -match '\b(19[0-7]\d|198[0-5])\b') {
        return @{ Tune = 'grain'; Note = 'older film/grain-friendly content' }
    }

    return @{ Tune = ''; Note = 'default x265 live-action profile' }
}

# ── Track-meta sidecar (DVDTrackMeta/1.0) ─────────────────────
function Get-MetaSidecarPath {
    param([Parameter(Mandatory)][string]$MovieName)
    $safeName = New-SafeName -Name $MovieName
    return [string](Join-Path $Script:MetaRoot "$safeName.dvdmeta")
}

function Read-DvdTrackMeta {
    # Returns @{ Title; Audio = @{<num>=<code>}; Subtitle = @{...} } or $null.
    param([Parameter(Mandatory)][string]$MovieName)

    $path = Get-MetaSidecarPath -MovieName $MovieName
    if (-not (Test-Path -LiteralPath $path)) { return $null }

    $audio = @{}
    $sub   = @{}
    $title = 0
    $valid = $false

    foreach ($line in (Get-Content -LiteralPath $path -ErrorAction SilentlyContinue)) {
        $t = $line.Trim()
        if ($t.StartsWith('DVDTrackMeta/')) { $valid = $true; continue }
        if ([string]::IsNullOrWhiteSpace($t) -or $t.StartsWith('#')) { continue }

        if ($t -match '^title\s*=\s*(\d+)\s*(?:#.*)?$') {
            $title = [int]$matches[1]
        }
        elseif ($t -match '^audio\.(\d+)\s*=\s*([A-Za-z]{2,3})\s*(?:#.*)?$') {
            $audio[[int]$matches[1]] = $matches[2].ToLowerInvariant()
        }
        elseif ($t -match '^subtitle\.(\d+)\s*=\s*([A-Za-z]{2,3})\s*(?:#.*)?$') {
            $sub[[int]$matches[1]] = $matches[2].ToLowerInvariant()
        }
    }

    if (-not $valid) { return $null }
    return @{ Title = $title; Audio = $audio; Subtitle = $sub }
}

function Write-DvdTrackMeta {
    # Writes/refreshes a sidecar documenting every scanned track. Scan code wins;
    # an existing sidecar entry fills gaps; otherwise 'und'. User can hand-edit.
    param(
        [Parameter(Mandatory)][string]$MovieName,
        [Parameter(Mandatory)][int]$Title,
        $AudioList    = @(),
        $SubtitleList = @(),
        $Existing     = $null
    )

    $path = Get-MetaSidecarPath -MovieName $MovieName
    $now  = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'

    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine($Script:MetaSchema)
    [void]$sb.AppendLine("# Track language map for: $MovieName")
    [void]$sb.AppendLine("# Generated $now by $ScriptName v$ScriptVersion")
    [void]$sb.AppendLine("# Edit codes to ISO 639-2 (eng, fra, spa, jpn, deu, ...) then re-run the encode.")
    [void]$sb.AppendLine("movie=$MovieName")
    [void]$sb.AppendLine("source=DVD")
    [void]$sb.AppendLine("title=$Title")

    foreach ($a in $AudioList) {
        $code = $a.Code
        if ((-not $code) -or $code -eq 'und') {
            if ($Existing -and $Existing.Audio.ContainsKey([int]$a.Num)) { $code = $Existing.Audio[[int]$a.Num] }
        }
        if (-not $code) { $code = 'und' }
        [void]$sb.AppendLine("audio.$($a.Num)=$code    # $($a.Lang)")
    }

    foreach ($s in $SubtitleList) {
        $code = $s.Code
        if ((-not $code) -or $code -eq 'und') {
            if ($Existing -and $Existing.Subtitle.ContainsKey([int]$s.Num)) { $code = $Existing.Subtitle[[int]$s.Num] }
        }
        if (-not $code) { $code = 'und' }
        [void]$sb.AppendLine("subtitle.$($s.Num)=$code    # $($s.Lang)")
    }

    try {
        $sb.ToString() | Out-File -LiteralPath $path -Encoding utf8 -Force
        Write-Host "  $($global:UI_GRY)Track-meta sidecar: $path$($global:UI_R)"
    }
    catch {
        Write-Host "  $($global:UI_YLW)Could not write sidecar: $($_.Exception.Message)$($global:UI_R)"
    }
}

# ── Track selection + language resolution ─────────────────────
function Get-SelectedTracks {
    # Returns the scan track objects that match a selection string, in output order.
    param($List, [string]$Selection)

    if (-not $List -or $List.Count -eq 0) { return @() }
    if ($Selection -eq 'none') { return @() }
    if ($Selection -eq 'all' -or [string]::IsNullOrWhiteSpace($Selection)) { return ,@($List) }

    $out = @()
    foreach ($p in ($Selection -split '\s*,\s*')) {
        if ($p -match '^\d+$') {
            $m = $List | Where-Object { $_.Num -eq [int]$p } | Select-Object -First 1
            if ($m) { $out += $m }
        }
    }
    return ,$out
}

function Resolve-LangCodes {
    # For each selected track (in output order): scan code wins, else sidecar, else 'und'.
    param($Selected, $SidecarMap)

    $codes = @()
    foreach ($t in $Selected) {
        $c = ''
        if ($t.Code -and $t.Code -ne 'und') {
            $c = $t.Code
        }
        elseif ($SidecarMap -and $SidecarMap.ContainsKey([int]$t.Num)) {
            $c = $SidecarMap[[int]$t.Num]
        }
        if (-not $c) { $c = 'und' }
        $codes += $c
    }
    return ,$codes
}

# ── Language remux via mkvpropedit ────────────────────────────
function Invoke-MKVLanguageRemux {
    # Sets per-track language tags on an existing MKV. Output-order arrays:
    # $AudioCodes[0] -> track:a1, $SubtitleCodes[0] -> track:s1, etc.
    param(
        [Parameter(Mandatory)][string]$MkvPath,
        [string[]]$AudioCodes    = @(),
        [string[]]$SubtitleCodes = @()
    )

    if (-not $Script:MkvPropEdit) {
        Write-Host "  $($global:UI_YLW)Skipping language remux — mkvpropedit unavailable.$($global:UI_R)"
        return
    }
    if (-not $DryRun -and -not (Test-Path -LiteralPath $MkvPath)) {
        Write-Host "  $($global:UI_YLW)Skipping language remux — file not found: $MkvPath$($global:UI_R)"
        return
    }
    if ($MkvPath -notmatch '\.mkv$') {
        Write-Host "  $($global:UI_YLW)Skipping language remux — not an MKV: $MkvPath$($global:UI_R)"
        return
    }

    $ppArgs = @($MkvPath)
    $edits  = 0

    for ($i = 0; $i -lt $AudioCodes.Count; $i++) {
        $c = $AudioCodes[$i]
        if ($c -and $c -ne 'und') {
            $ppArgs += @('--edit', "track:a$($i + 1)", '--set', "language=$c")
            $edits++
        }
    }
    for ($i = 0; $i -lt $SubtitleCodes.Count; $i++) {
        $c = $SubtitleCodes[$i]
        if ($c -and $c -ne 'und') {
            $ppArgs += @('--edit', "track:s$($i + 1)", '--set', "language=$c")
            $edits++
        }
    }

    if ($edits -eq 0) {
        Write-Host "  $($global:UI_GRY)No language tags to set (all undefined or already correct).$($global:UI_R)"
        return
    }

    if ($DryRun) {
        Write-Host "  $($global:UI_YLW)[DRY RUN] Would remux languages:$($global:UI_R)"
        Write-Host "  $Script:MkvPropEdit $($ppArgs -join ' ')"
        return
    }

    try {
        & $Script:MkvPropEdit @ppArgs | Out-Null
        if ($LASTEXITCODE -eq 0) {
            Write-Host "  $($global:UI_GRN)Language tags applied ($edits track(s)).$($global:UI_R)"
        }
        else {
            Write-Host "  $($global:UI_YLW)mkvpropedit returned exit code $LASTEXITCODE — tags may be partial.$($global:UI_R)"
        }
    }
    catch {
        Write-Host "  $($global:UI_YLW)Language remux failed: $($_.Exception.Message)$($global:UI_R)"
    }
}

# ── Source archiving ──────────────────────────────────────────
function Get-VideoTsPath {
    param([Parameter(Mandatory)][string]$InputPath)

    $candidates = @()
    $candidates += (Join-Path $InputPath 'VIDEO_TS')
    try {
        $resolved = Resolve-HandBrakeInputPath -Path $InputPath
        if ($resolved -match 'VIDEO_TS$') { $candidates += $resolved }
        else { $candidates += (Join-Path $resolved 'VIDEO_TS') }
    }
    catch { }

    foreach ($c in $candidates) {
        if ($c -and (Test-Path -LiteralPath $c)) { return [string]$c }
    }
    return $null
}

function Copy-DvdSource {
    param(
        [Parameter(Mandatory)][string]$InputPath,
        [Parameter(Mandatory)][string]$MovieName
    )

    if (-not $Script:ArchiveSource) { return }

    $vts = Get-VideoTsPath -InputPath $InputPath
    if (-not $vts) {
        Write-Host "  $($global:UI_YLW)Source archive skipped — no VIDEO_TS found under $InputPath$($global:UI_R)"
        return
    }

    $safe = New-SafeName -Name $MovieName
    $dest = Join-Path $Script:SourceRoot $safe
    $destVts = Join-Path $dest 'VIDEO_TS'

    if (Test-Path -LiteralPath $destVts) {
        Write-Host "  $($global:UI_GRY)Source already archived: $destVts$($global:UI_R)"
        return
    }

    if ($DryRun) {
        Write-Host "  $($global:UI_YLW)[DRY RUN] Would archive source $vts -> $destVts$($global:UI_R)"
        return
    }

    try {
        if (-not (Test-Path -LiteralPath $dest)) {
            [System.IO.Directory]::CreateDirectory($dest) | Out-Null
        }
        Write-Host "  $($global:UI_GRY)Archiving source (this can be several GB)...$($global:UI_R)"
        Copy-Item -LiteralPath $vts -Destination $dest -Recurse -Force
        Write-Host "  $($global:UI_GRN)Source archived: $destVts$($global:UI_R)"
    }
    catch {
        Write-Host "  $($global:UI_YLW)Source archive failed: $($_.Exception.Message)$($global:UI_R)"
    }
}

function Get-EncodeSettings {
    if ($AutoAccept) {
        return @{ RF = $Script:DefaultRF; Preset = $Script:DefaultPreset; Container = $Script:DefaultContainer }
    }

    Write-UiBlankLine
    Write-Host "  $($global:UI_GRY)Press Enter to accept defaults shown in [brackets].$($global:UI_R)"
    Write-UiBlankLine

    $rfInput = Read-Host "RF quality [$($Script:DefaultRF)]  (18=larger, 22=smaller)"
    $rf = if ([string]::IsNullOrWhiteSpace($rfInput)) {
        $Script:DefaultRF
    }
    else {
        $v = [int]$rfInput
        if ($v -lt 16 -or $v -gt 28) {
            Write-Host "  $($global:UI_YLW)RF out of safe range — clamping to 18–22$($global:UI_R)"
            [Math]::Max(18, [Math]::Min(22, $v))
        }
        else { $v }
    }

    $presetInput = Read-Host "Preset [$($Script:DefaultPreset)]  (slow / slower / veryslow)"
    $preset = if ([string]::IsNullOrWhiteSpace($presetInput)) {
        $Script:DefaultPreset
    }
    elseif ($presetInput -in @('slow','slower','veryslow')) {
        $presetInput
    }
    else {
        Write-Host "  $($global:UI_YLW)Unknown preset — using default.$($global:UI_R)"
        $Script:DefaultPreset
    }

    $containerInput = Read-Host "Container [$($Script:DefaultContainer)]  (mkv / mp4)"
    $container = if ([string]::IsNullOrWhiteSpace($containerInput)) {
        $Script:DefaultContainer
    }
    elseif ($containerInput -in @('mkv','mp4')) {
        $containerInput
    }
    else {
        Write-Host "  $($global:UI_YLW)Unknown container — using default.$($global:UI_R)"
        $Script:DefaultContainer
    }

    return @{ RF = $rf; Preset = $preset; Container = $container }
}

function Encode-DvdTitle {
    param(
        [Parameter(Mandatory)][string]$InputPath,
        [Parameter(Mandatory)][int]$TitleNumber,
        [Parameter(Mandatory)][string]$MovieName,
        [AllowEmptyString()][string]$Tune = '',   # '' = no x265 tune; must allow empty
        [ValidateSet('mkv','mp4')][string]$Container = 'mkv',
        [ValidateRange(16,28)][int]$RF = 20,
        [ValidateSet('slow','slower','veryslow')][string]$Preset = 'slower',
        [string]$AudioSelection    = 'all',   # 'all' | 'none' | '1,3'
        [string]$SubtitleSelection = 'all',   # 'all' | 'none' | '1,2'
        [string[]]$AudioCodes      = @(),     # output-order ISO 639-2 codes
        [string[]]$SubtitleCodes   = @()
    )

    $resolvedInput = Resolve-HandBrakeInputPath -Path $InputPath
    $safeName      = New-SafeName -Name $MovieName
    $outputFile    = Join-Path $Script:OutputRoot "$safeName.$Container"

    if (Test-Path -LiteralPath $outputFile) {
        Write-UiBlankLine
        Write-Host "  $($global:UI_YLW)Output file already exists:$($global:UI_R) $outputFile"

        $overwrite = if ($AutoAccept) { 'N' } else { Read-Host "Overwrite? (Y/N)" }

        if ($overwrite -notmatch '^(Y|y)$') {
            $stamp      = Get-Date -Format 'yyyyMMdd_HHmmss'
            $outputFile = Join-Path $Script:OutputRoot "${safeName}_${stamp}.$Container"
            Write-Host "  $($global:UI_GRY)Writing to:$($global:UI_R) $outputFile"
        }
    }

    Write-UiBlankLine
    Write-Host "  $($global:UI_GRN)Encoding title $TitleNumber...$($global:UI_R)"
    Write-Host ("  {0}Input  {1} {2}" -f $global:UI_DIM, $global:UI_R, $resolvedInput)
    Write-Host ("  {0}Output {1} {2}" -f $global:UI_DIM, $global:UI_R, $outputFile)
    Write-Host ("  {0}Codec  {1} {2}" -f $global:UI_DIM, $global:UI_R, $Script:DefaultEncoder)
    Write-Host ("  {0}RF     {1} {2}" -f $global:UI_DIM, $global:UI_R, $RF)
    Write-Host ("  {0}Preset {1} {2}" -f $global:UI_DIM, $global:UI_R, $Preset)
    Write-Host ("  {0}Tune   {1} {2}" -f $global:UI_DIM, $global:UI_R, $(if ($Tune) { $Tune } else { '(none)' }))
    Write-Host ("  {0}Audio  {1} {2}" -f $global:UI_DIM, $global:UI_R, $(if ($AudioSelection -eq 'all') { 'all tracks' } elseif ($AudioSelection -eq 'none') { 'none' } else { "tracks $AudioSelection" }))
    Write-Host ("  {0}Subs   {1} {2}" -f $global:UI_DIM, $global:UI_R, $(if ($SubtitleSelection -eq 'all') { 'all tracks' } elseif ($SubtitleSelection -eq 'none') { 'none' } else { "tracks $SubtitleSelection" }))
    Write-Host ("  {0}Using  {1} {2}" -f $global:UI_DIM, $global:UI_R, $Script:HandBrakeCLI)
    Write-UiBlankLine

    $encodeArgs = @(
        '--input',          $resolvedInput,
        '--title',          $TitleNumber,
        '--output',         $outputFile,
        '--format',         "av_$Container",

        '--encoder',        $Script:DefaultEncoder,
        '--quality',        $RF,
        '--encoder-preset', $Preset,

        '--markers',
        '--vfr',
        '--crop-mode',      'auto',
        '--loose-anamorphic',
        '--modulus',        '2',
        '--detelecine',
        '--comb-detect',
        '--decomb',

        '--aencoder',       'copy',
        '--audio-fallback', 'flac24'
    )

    # Audio selection: language tags carry through from the DVD either way.
    if ($AudioSelection -eq 'all') {
        $encodeArgs += '--all-audio'
    }
    elseif ($AudioSelection -ne 'none') {
        $encodeArgs += @('--audio', $AudioSelection)
    }
    # ('none' for audio is unusual but allowed — HandBrake will produce a video-only file.)

    # Subtitle selection: VOBSUB bitmaps carry into MKV with their languages.
    if ($SubtitleSelection -eq 'all') {
        $encodeArgs += '--all-subtitles'
    }
    elseif ($SubtitleSelection -eq 'none') {
        # no subtitle tracks
    }
    else {
        $encodeArgs += @('--subtitle', $SubtitleSelection)
    }

    if (-not [string]::IsNullOrWhiteSpace($Tune)) {
        $encodeArgs += @('--encoder-tune', $Tune)
    }

    if ($DryRun) {
        Write-Host "  $($global:UI_YLW)[DRY RUN] Would execute:$($global:UI_R)"
        Write-Host "  $Script:HandBrakeCLI $($encodeArgs -join ' ')"
        if ($Container -eq 'mkv') {
            Invoke-MKVLanguageRemux -MkvPath $outputFile -AudioCodes $AudioCodes -SubtitleCodes $SubtitleCodes
        }
        Copy-DvdSource -InputPath $InputPath -MovieName $MovieName
        Write-UiBlankLine
        return
    }

    Write-Host "  $($global:UI_GRN)HandBrake encode starting — output streams below.$($global:UI_R)"
    Write-Host ("  {0}Cmd{1} {2} {3}" -f $global:UI_DIM, $global:UI_R, $Script:HandBrakeCLI, ($encodeArgs -join ' '))

    # Merge stderr (where HandBrake logs + progress) into the pipeline and echo each
    # line via Write-Host so it surfaces in the GUI log (and the console). Without this
    # the encode runs blind: native output lands in streams the GUI never reads.
    & $Script:HandBrakeCLI @encodeArgs 2>&1 | ForEach-Object {
        Write-Host ("  HB| " + (($_ | Out-String).TrimEnd() -replace "\x1b\[[0-9;]*[A-Za-z]", ''))
    }
    $hbExit = $LASTEXITCODE
    Write-Host "  $($global:UI_DIM)HandBrake exit code:$($global:UI_R) $hbExit"

    if ($hbExit -ne 0) {
        throw "HandBrake exited with code $hbExit — no usable output. See the HB| lines above."
    }
    if (-not (Test-Path -LiteralPath $outputFile)) {
        throw "Encode finished (exit 0) but no output file at: $outputFile"
    }

    Write-UiBlankLine
    Write-Host "  $($global:UI_GRN)Encode complete:$($global:UI_R) $outputFile"

    # Post-encode: fix language tags (MKV only), archive source, write NFO.
    if ($Container -eq 'mkv') {
        Write-UiBlankLine
        Write-Host "  $($global:UI_GRN)Tagging track languages...$($global:UI_R)"
        Invoke-MKVLanguageRemux -MkvPath $outputFile -AudioCodes $AudioCodes -SubtitleCodes $SubtitleCodes
    }
    else {
        Write-Host "  $($global:UI_GRY)Container is $Container — language remux applies to MKV only.$($global:UI_R)"
    }

    Copy-DvdSource -InputPath $InputPath -MovieName $MovieName

    Write-NfoStub -MovieName $MovieName -OutputFile $outputFile -Tune $Tune -RF $RF -Preset $Preset
}

function Write-NfoStub {
    param(
        [Parameter(Mandatory)][string]$MovieName,
        [Parameter(Mandatory)][string]$OutputFile,
        [string]$Tune   = '',
        [int]$RF        = 0,
        [string]$Preset = ''
    )

    $safeName = New-SafeName -Name $MovieName
    $nfoPath  = Join-Path $Script:NfoRoot "$safeName.nfo"
    $now      = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'

    $nfoContent = @"
Movie    : $MovieName
Encoded  : $now
Source   : DVD
Output   : $OutputFile
Encoder  : $($Script:DefaultEncoder)
RF       : $RF
Preset   : $Preset
Tune     : $(if ($Tune) { $Tune } else { '(none)' })
Script   : $ScriptName v$ScriptVersion
"@

    try {
        $nfoContent | Out-File -LiteralPath $nfoPath -Encoding utf8 -Force
        Write-Host "  $($global:UI_GRY)NFO written: $nfoPath$($global:UI_R)"
    }
    catch {
        Write-Host "  $($global:UI_YLW)Could not write NFO: $($_.Exception.Message)$($global:UI_R)"
    }
}

function Read-MovieNameWithYear {
    param([string]$DefaultName = '')

    if ($AutoAccept) {
        if (-not [string]::IsNullOrWhiteSpace($DefaultName)) {
            Write-Host "  $($global:UI_GRY)Auto-accept: naming from disc label -> $DefaultName$($global:UI_R)"
            return [string]$DefaultName
        }
        $fallback = "dvd_encode_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
        Write-Host "  $($global:UI_GRY)Auto-accept: no disc label, using $fallback$($global:UI_R)"
        return [string]$fallback
    }

    $prompt = if ([string]::IsNullOrWhiteSpace($DefaultName)) { "Movie name" } else { "Movie name [$DefaultName]" }
    $movieName = Read-Host $prompt
    if ([string]::IsNullOrWhiteSpace($movieName)) {
        $movieName = if (-not [string]::IsNullOrWhiteSpace($DefaultName)) {
            $DefaultName
        }
        else {
            "dvd_encode_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
        }
    }

    $movieYear = Read-Host "Year (optional, 4 digits)"
    if (-not [string]::IsNullOrWhiteSpace($movieYear) -and $movieYear -match '^\d{4}$') {
        $movieName = "$movieName [$movieYear]"
    }

    return [string]$movieName
}

function Select-Tracks {
    # Shows the available tracks (with language) for one kind and returns a
    # HandBrake selection string: 'all' or a comma list like '1,3'. Empty/Enter = all.
    param(
        [Parameter(Mandatory)][string]$Kind,        # 'audio' | 'subtitle'
        [Parameter(Mandatory)]$Tracks               # array of {Num; Lang; Desc}
    )

    if (-not $Tracks -or $Tracks.Count -eq 0) {
        Write-Host "  $($global:UI_YLW)No $Kind tracks detected — including all available.$($global:UI_R)"
        return 'all'
    }

    if ($AutoAccept) {
        Write-Host "  $($global:UI_GRY)Auto-accept: including all $Kind tracks.$($global:UI_R)"
        return 'all'
    }

    Write-UiBlankLine
    Write-Host "  $($global:UI_MAG)$([System.Globalization.CultureInfo]::InvariantCulture.TextInfo.ToTitleCase($Kind)) tracks:$($global:UI_R)"
    foreach ($t in $Tracks) {
        Write-Host ("    {0}{1}{2}  {3}" -f $global:UI_DIM, $t.Num, $global:UI_R, $t.Lang)
    }

    $valid = @($Tracks | ForEach-Object { $_.Num })
    while ($true) {
        $choice = (Read-Host "  Include $Kind tracks (e.g. 1,3) [all]").Trim()
        if ([string]::IsNullOrWhiteSpace($choice) -or $choice -ieq 'all') {
            return 'all'
        }
        if ($choice -ieq 'none') {
            return 'none'
        }

        $picked = @()
        $ok = $true
        foreach ($p in ($choice -split '\s*,\s*')) {
            if ($p -match '^\d+$' -and ([int]$p -in $valid)) {
                $picked += [int]$p
            }
            else {
                Write-Host "  $($global:UI_YLW)'$p' is not a listed track number — try again.$($global:UI_R)"
                $ok = $false
                break
            }
        }
        if ($ok -and $picked.Count -gt 0) {
            return ($picked -join ',')
        }
    }
}

function Invoke-EncodeFlow {
    param(
        [Parameter(Mandatory)][string]$InputPath,
        [Parameter(Mandatory)][string]$MovieName
    )

    $scan = Invoke-HandBrakeScan -InputPath $InputPath

    # Guard against stray pipeline output: keep the hashtable if an array slips through.
    if ($scan -is [array]) { $scan = $scan | Where-Object { $_ -is [hashtable] } | Select-Object -Last 1 }

    if (-not $scan.Titles -or $scan.Titles.Count -eq 0) {
        throw "Could not find any titles to encode."
    }

    $mainTitle = Get-MainTitle -Titles $scan.Titles

    Write-UiBlankLine
    Write-Host "  $($global:UI_YLW)Suggested main title:$($global:UI_R) $($mainTitle.Title)  Duration: $($mainTitle.Duration)"

    if ($AutoAccept) {
        $selectedTitle = $mainTitle.Title
        Write-Host "  $($global:UI_GRY)Auto-accept: encoding title $selectedTitle.$($global:UI_R)"
    }
    else {
        $titleChoice = Read-Host "Title to encode [$($mainTitle.Title)]"
        $selectedTitle = if ([string]::IsNullOrWhiteSpace($titleChoice)) { $mainTitle.Title } else { [int]$titleChoice }
    }

    $titleObj = $scan.Titles | Where-Object { $_.Title -eq $selectedTitle } | Select-Object -First 1

    $audioSel = Select-Tracks -Kind 'audio'    -Tracks $titleObj.AudioList
    $subSel   = Select-Tracks -Kind 'subtitle' -Tracks $titleObj.SubtitleList

    # Resolve output-order language codes: scan-primary, sidecar fallback.
    $sidecar  = Read-DvdTrackMeta -MovieName $MovieName
    if ($sidecar) {
        Write-Host "  $($global:UI_GRY)Found track-meta sidecar — using it to fill undefined languages.$($global:UI_R)"
    }
    $selAudio  = Get-SelectedTracks -List $titleObj.AudioList    -Selection $audioSel
    $selSubs   = Get-SelectedTracks -List $titleObj.SubtitleList -Selection $subSel
    $audioCodes = Resolve-LangCodes -Selected $selAudio -SidecarMap ($(if ($sidecar) { $sidecar.Audio }    else { $null }))
    $subCodes   = Resolve-LangCodes -Selected $selSubs  -SidecarMap ($(if ($sidecar) { $sidecar.Subtitle } else { $null }))

    $tuneInfo = Get-AutoTune -MovieName $MovieName
    $tune     = $tuneInfo.Tune

    Write-Host "  $($global:UI_MAG)Auto-selected tune:$($global:UI_R) $(if ($tune) { $tune } else { '(none)' })  $($global:UI_GRY)($($tuneInfo.Note))$($global:UI_R)"

    $settings = Get-EncodeSettings

    Encode-DvdTitle `
        -InputPath         $InputPath `
        -TitleNumber       $selectedTitle `
        -MovieName         $MovieName `
        -Tune              $tune `
        -Container         $settings.Container `
        -RF                $settings.RF `
        -Preset            $settings.Preset `
        -AudioSelection    $audioSel `
        -SubtitleSelection $subSel `
        -AudioCodes        $audioCodes `
        -SubtitleCodes     $subCodes

    # Refresh the sidecar so it always documents the disc's tracks.
    Write-DvdTrackMeta -MovieName $MovieName -Title $selectedTitle `
        -AudioList $titleObj.AudioList -SubtitleList $titleObj.SubtitleList -Existing $sidecar
}

# ── Menu actions ──────────────────────────────────────────────
function Encode-DirectFromDvd {
    Write-UiBlankLine

    if ($AutoAccept) {
        $drive = $Script:DefaultDrive
        Write-Host "  $($global:UI_GRY)Auto-accept: using drive $drive$($global:UI_R)"
    }
    else {
        $drive = Read-Host "DVD drive letter [$Script:DefaultDrive]"
        if ([string]::IsNullOrWhiteSpace($drive)) { $drive = $Script:DefaultDrive }
    }

    $label     = Get-DvdVolumeLabel -DriveLetter $drive
    $movieName = Read-MovieNameWithYear -DefaultName $label

    try {
        [string]$sourceDrive = Get-DvdSourcePath -DriveLetter $drive
        Invoke-EncodeFlow -InputPath $sourceDrive -MovieName $movieName
    }
    catch {
        Write-UiBlankLine
        Write-CoreError $_.Exception.Message
    }

    Pause-Script
}

function Scan-DvdOnly {
    Write-UiBlankLine
    $drive = Read-Host "DVD drive letter [$Script:DefaultDrive]"
    if ([string]::IsNullOrWhiteSpace($drive)) { $drive = $Script:DefaultDrive }

    try {
        [string]$sourceDrive = Get-DvdSourcePath -DriveLetter $drive
        $null = Invoke-HandBrakeScan -InputPath $sourceDrive
    }
    catch {
        Write-UiBlankLine
        Write-CoreError $_.Exception.Message
    }

    Pause-Script
}

function Encode-From-ExistingFolder {
    Write-UiBlankLine
    $inputPath = Read-Host "Path to VIDEO_TS folder or parent folder"

    if (-not (Test-Path -LiteralPath $inputPath)) {
        Write-UiBlankLine
        Write-CoreError "Path not found."
        Pause-Script
        return
    }

    # Default the title to the folder name (its parent if the path is VIDEO_TS).
    $leaf = Split-Path -Leaf $inputPath
    if ($leaf -ieq 'VIDEO_TS') { $leaf = Split-Path -Leaf (Split-Path -Parent $inputPath) }

    $movieName = Read-MovieNameWithYear -DefaultName $leaf

    try {
        Invoke-EncodeFlow -InputPath ([string]$inputPath) -MovieName $movieName
    }
    catch {
        Write-UiBlankLine
        Write-CoreError $_.Exception.Message
    }

    Pause-Script
}

function Write-TrackMetaSidecar-Action {
    Write-UiBlankLine

    if ($AutoAccept) {
        $drive = $Script:DefaultDrive
    }
    else {
        $drive = Read-Host "DVD drive letter [$Script:DefaultDrive]"
        if ([string]::IsNullOrWhiteSpace($drive)) { $drive = $Script:DefaultDrive }
    }

    $label     = Get-DvdVolumeLabel -DriveLetter $drive
    $movieName = Read-MovieNameWithYear -DefaultName $label

    try {
        [string]$sourceDrive = Get-DvdSourcePath -DriveLetter $drive
        $scan = Invoke-HandBrakeScan -InputPath $sourceDrive
        if ($scan -is [array]) { $scan = $scan | Where-Object { $_ -is [hashtable] } | Select-Object -Last 1 }

        if (-not $scan.Titles -or $scan.Titles.Count -eq 0) {
            throw "No titles found to document."
        }

        $mainTitle = Get-MainTitle -Titles $scan.Titles
        $titleObj  = $scan.Titles | Where-Object { $_.Title -eq $mainTitle.Title } | Select-Object -First 1
        $existing  = Read-DvdTrackMeta -MovieName $movieName

        Write-DvdTrackMeta -MovieName $movieName -Title $mainTitle.Title `
            -AudioList $titleObj.AudioList -SubtitleList $titleObj.SubtitleList -Existing $existing

        Write-UiBlankLine
        Write-Host "  $($global:UI_GRY)Edit the sidecar to fix any 'und' codes, then run an encode.$($global:UI_R)"
    }
    catch {
        Write-UiBlankLine
        Write-CoreError $_.Exception.Message
    }

    Pause-Script
}

function Remux-ExistingMkv-Action {
    Write-UiBlankLine

    if (-not $Script:MkvPropEdit) {
        Write-CoreError "mkvpropedit not available. Install MKVToolNix to use this."
        Pause-Script
        return
    }

    $mkvPath = Read-Host "Path to .mkv file"
    if ([string]::IsNullOrWhiteSpace($mkvPath) -or -not (Test-Path -LiteralPath $mkvPath)) {
        Write-CoreError "File not found."
        Pause-Script
        return
    }

    Write-Host "  $($global:UI_GRY)Enter ISO 639-2 codes in track order, comma-separated (blank = skip).$($global:UI_R)"
    Write-Host "  $($global:UI_GRY)Example audio: eng,fra   subtitles: eng,spa$($global:UI_R)"

    $audioIn = (Read-Host "Audio track languages").Trim()
    $subIn   = (Read-Host "Subtitle track languages").Trim()

    $audioCodes = if ($audioIn) { @($audioIn -split '\s*,\s*') } else { @() }
    $subCodes   = if ($subIn)   { @($subIn   -split '\s*,\s*') } else { @() }

    try {
        Invoke-MKVLanguageRemux -MkvPath ([string]$mkvPath) -AudioCodes $audioCodes -SubtitleCodes $subCodes
    }
    catch {
        Write-UiBlankLine
        Write-CoreError $_.Exception.Message
    }

    Pause-Script
}

function Show-Config {
    Write-UiBlankLine
    Write-UiRow "RootPath"      $Script:RootPath $global:UI_GRY
    Write-UiRow "OutputRoot"    $Script:OutputRoot $global:UI_GRY
    Write-UiRow "NfoRoot"       $Script:NfoRoot $global:UI_GRY
    Write-UiRow "MetaRoot"      $Script:MetaRoot $global:UI_GRY
    Write-UiRow "SourceRoot"    $Script:SourceRoot $global:UI_GRY
    Write-UiRow "DefaultDrive"  $Script:DefaultDrive $global:UI_GRY
    Write-UiRow "Container"     $Script:DefaultContainer $global:UI_GRY
    Write-UiRow "Encoder"       $Script:DefaultEncoder $global:UI_GRY
    Write-UiRow "RF"            "$($Script:DefaultRF)" $global:UI_GRY
    Write-UiRow "Preset"        $Script:DefaultPreset $global:UI_GRY
    Write-UiRow "HandBrakeCLI"  $Script:HandBrakeCLI $global:UI_GRY
    Write-UiRow "MkvPropEdit"   $(if ($Script:MkvPropEdit) { $Script:MkvPropEdit } else { '(not found — remux disabled)' }) $global:UI_GRY
    Write-UiRow "ArchiveSource" $(if ($Script:ArchiveSource) { 'Yes' } else { 'No' }) $global:UI_GRY
    Write-UiRow "DryRun"        $(if ($DryRun) { 'Yes' } else { 'No' }) $global:UI_GRY
    Write-UiRow "AutoAccept"    $(if ($AutoAccept) { 'Yes' } else { 'No' }) $global:UI_GRY
    Pause-Script
}

# ── Startup (interactive menu runs only when executed directly; the GUI ──
# ── dot-sources this file with DVDENCODER_NOMENU set to reuse the functions) ──
if (-not $env:DVDENCODER_NOMENU) {

try {
    Ensure-Dependencies
    Ensure-Directories
}
catch {
    Write-UiBlankLine
    Write-CoreError $_.Exception.Message
    return
}

while ($true) {
    Show-Header
    Show-Menu
    $choice = (Read-Host "Choose").Trim().ToUpper()

    switch ($choice) {
        '1' { Encode-DirectFromDvd }
        '2' { Scan-DvdOnly }
        '3' { Encode-From-ExistingFolder }
        '4' { Write-TrackMetaSidecar-Action }
        '5' { Remux-ExistingMkv-Action }
        '6' { Show-Config }
        'Q' {
            Write-UiBlankLine
            Write-Host "  $($global:UI_CYN)Goodbye.$($global:UI_R)"
            Write-UiBlankLine
            return
        }
        default {
            Write-CoreError "Invalid choice."
            Start-Sleep -Seconds 1
        }
    }
}

} # end: if (-not $env:DVDENCODER_NOMENU)