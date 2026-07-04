#--------------------------------------------
# file:     brEncoder.ps1
# author:   Mike Redd
# version:  3.2.3
# created:  2026-02-11
# updated:  2026-07-04
# desc:     Encode Blu-ray .m2ts files
#           to H.265/HEVC on Windows
#           using ffmpeg, then create a
#           sample clip from the finished MKV
#           and apply required sidecar
#           audio/subtitle metadata
#           validates metadata, verifies final MKV
#           language/default/forced tags
#           remuxes final MKV with real track IDs
# changes:  v3.2.3 - fix CLPI parser variable collision with PowerShell $PID
#           v3.2.0 - production-line stable pass: raw .m2ts stream mapping
#                    now uses actual source/CLPI counts so every physical
#                    audio and subtitle stream is mapped; CLPI/sidecar physical
#                    languages are used for deterministic final tags; output
#                    track counts are validated before the encode is marked done
#           v3.1.8 - subtitle tags now driven by the source .mkv's own per-stream
#                    language tags (in physical 0:s order) instead of the disc
#                    sidecar, which over-counts when MakeMKV drops duplicate PGS
#                    streams (e.g. output=10 vs sidecar=20). Both the encode map
#                    and the mkvpropedit remux read source tags for .mkv inputs;
#                    .m2ts inputs keep sidecar tagging. Source-driven subs are
#                    auto-named "PGS <lang>" and forced is read from forced_track
#           v3.1.7 - sample creation no longer fails on PGS subtitles: the
#                    sample maps video + audio only (a PGS sub can't be
#                    stream-copied from a mid-file seek - "unspecified size"),
#                    and its ffmpeg call relaxes the script-wide EAP=Stop like
#                    the main encode so a benign stderr warning can't abort it
#--------------------------------------------

param()

# ── Load custom UI ────────────────────────────────────────────
$uiPath = "$env:USERPROFILE\PS\profile.d\ui.ps1"
if (Test-Path $uiPath) {
    try {
        . $uiPath
    }
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
if (Test-Path $corePath) {
    try {
        . $corePath
    }
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

$ScriptName    = "Blu-ray Encoder"
$ScriptVersion = "3.2.0"
$ScriptAuthor  = "Mike Redd"

# ── Config ────────────────────────────────────────────────────
$Script:RootPath        = "G:\Rip"
$Script:InputRoot       = Join-Path $Script:RootPath 'bluray'
$Script:OutputRoot      = Join-Path $Script:RootPath 'raw265'
$Script:DoneRoot        = Join-Path $Script:RootPath 'done'
$Script:SampleRoot      = Join-Path $Script:RootPath 'sample'
$Script:SubtitleRoot    = Join-Path $Script:RootPath 'subtitles'
$Script:MetaRoot        = Join-Path $Script:RootPath 'meta'
$Script:TxtRoot         = Join-Path $Script:RootPath 'txt'
$Script:M2tsRoot        = Join-Path $Script:RootPath 'm2ts'

# Video quality — slow+psy tuning for high-fidelity Blu-ray encodes
# CRF 18 for HDR, 19 for SDR. Lower these later if you want larger files.
$Script:CRF_HDR         = 18
$Script:CRF_SDR         = 19
$Script:DefaultPreset   = 'slow'
$Script:DefaultAudio    = 'copy'
$Script:DefaultExt      = 'mkv'
$Script:DefaultStart    = '00:10:00'
$Script:DefaultLength   = 60

# x265 psychovisual params — applied to all encodes
# psy-rd=1.5   restore detail softened by rate control
# psy-rdoq=1.0 preserve high-freq texture (grain, fine detail)
# aq-mode=3    HEVC-aware adaptive quantisation
# rd=4         higher rate-distortion optimisation (slow but thorough)
# deblock=-1,-1  slightly softer deblock to avoid smearing fine edges
$Script:X265PsyParams   = "rd=3:psy-rd=1.5:psy-rdoq=1.0:aq-mode=3:deblock=-1,-1:pools=*"

$Script:FFmpegPath      = $null
$Script:FFprobePath     = $null
$Script:MKVPropEditPath = $null
$Script:MKVMergePath    = $null
$Script:MetadataScanLimit = 200
$Script:DebugMeta         = $false   # set to $true to dump sidecar JSON track shapes

# ffmpeg/ffprobe probe options for large Blu-ray .m2ts containers.
# Without these, PGS subtitle streams report "unspecified size" and may be
# skipped. Values must be strings so they pass cleanly to ffmpeg args arrays.
$Script:M2tsProbeSize     = '100000000'   # 100 MB
$Script:M2tsAnalyzeDur    = '300000000'   # 300 M microseconds

# ── Header ────────────────────────────────────────────────────
function Show-Header {
    Clear-UiScreen
    $w = Get-UiBoxWidth -MaxWidth 64 -MinWidth 46

    Write-UiHeader -Title $ScriptName -Subtitle "v$ScriptVersion  by $ScriptAuthor" -Width $w
    Write-UiRow "User"    "$env:USERNAME@$env:COMPUTERNAME"
    Write-UiRow "Input"   $Script:InputRoot $global:UI_GRY
    Write-UiRow "Meta"    "source folder first, then G:\Rip\meta / txt" $global:UI_GRY
    Write-UiRow "Preset"  "$($Script:DefaultPreset)  •  10-bit yuv420p10le" $global:UI_GRY
    Write-UiRow "CRF"     "HDR=$($Script:CRF_HDR)  /  SDR=$($Script:CRF_SDR)  (auto-detected)" $global:UI_GRY
    Write-UiRow "Psy"     "rd=3  psy-rd=1.5  psy-rdoq=1.0  aq-mode=3" $global:UI_GRY
    Write-UiRow "Audio"   "copy (lossless passthrough)" $global:UI_GRY
    Write-UiRow "Sample"  "$($Script:DefaultLength)s from finished MKV" $global:UI_GRY
    Write-UiBlankLine
}

# ── Menu ──────────────────────────────────────────────────────
function Show-Menu {
    Write-UiDivider
    Write-Host "  $($global:UI_GRN)  1)$($global:UI_R)  Encode all .m2ts files"
    Write-Host "  $($global:UI_GRN)  2)$($global:UI_R)  Encode single file"
    Write-Host "  $($global:UI_GRN)  3)$($global:UI_R)  Show source files"
    Write-UiDivider
    Write-Host "  $($global:UI_YLW)  5)$($global:UI_R)  Repair language tags on finished MKV"
    Write-UiDivider
    Write-Host "  $($global:UI_CYN)  4)$($global:UI_R)  Show config"
    Write-UiDivider
    Write-Host "  $($global:UI_GRY)  Q)$($global:UI_R)  Quit"
    Write-UiBlankLine
}

function Pause-Script {
    Pause-Core "Press Enter to return to menu..."
}

function Get-ToolPath {
    param([Parameter(Mandatory)][string]$CommandName)

    $cmd = Get-Command $CommandName -ErrorAction SilentlyContinue
    if ($cmd -and $cmd.Source) {
        return [string]$cmd.Source
    }

    return $null
}

function Ensure-Directories {
    $paths = @(
        $Script:RootPath,
        $Script:InputRoot,
        $Script:OutputRoot,
        $Script:DoneRoot,
        $Script:SampleRoot,
        $Script:SubtitleRoot,
        $Script:MetaRoot,
        $Script:TxtRoot,
        $Script:M2tsRoot
    )

    foreach ($p in $paths) {
        if (-not (Test-Path $p)) {
            New-Item -Path $p -ItemType Directory -Force | Out-Null
        }
    }
}

function Ensure-Dependencies {
    $missing = @()

    $Script:FFmpegPath      = Get-ToolPath -CommandName 'ffmpeg'
    $Script:FFprobePath     = Get-ToolPath -CommandName 'ffprobe'
    $Script:MKVPropEditPath = Get-ToolPath -CommandName 'mkvpropedit'
    $Script:MKVMergePath    = Get-ToolPath -CommandName 'mkvmerge'

    if (-not $Script:FFmpegPath)      { $missing += 'ffmpeg' }
    if (-not $Script:FFprobePath)     { $missing += 'ffprobe' }
    if (-not $Script:MKVPropEditPath) { $missing += 'mkvpropedit' }
    if (-not $Script:MKVMergePath)    { $missing += 'mkvmerge' }

    if ($missing.Count -gt 0) {
        Write-UiBlankLine
        Write-CoreError "Missing required tools: $($missing -join ', ')"
        throw "Required dependency missing."
    }
}

function New-SafeName {
    param([Parameter(Mandatory)][string]$Name)

    $safe = $Name -replace '[\\\/:\*\?"<>\|]', '_'
    $safe = $safe.Trim()

    if ([string]::IsNullOrWhiteSpace($safe)) {
        $safe = "bluray_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
    }

    return [string]$safe
}

function Get-M2tsFiles {
    if (-not (Test-Path $Script:InputRoot)) {
        return @()
    }

    return @(
        Get-ChildItem -Path $Script:InputRoot -Filter *.m2ts -File -Recurse |
        Sort-Object Length -Descending
    )
}

function Show-SourceFiles {
    $files = Get-M2tsFiles

    Write-UiBlankLine

    if (-not $files -or $files.Count -eq 0) {
        Write-CoreError "No .m2ts files found in $($Script:InputRoot)"
        Pause-Script
        return
    }

    $rows = foreach ($f in $files) {
        [pscustomobject]@{
            Name     = $f.Name
            SizeGB   = [math]::Round(($f.Length / 1GB), 2)
            Modified = $f.LastWriteTime
            Folder   = $f.DirectoryName
        }
    }

    Write-Host "  $($global:UI_MAG)Available source files:$($global:UI_R)"
    $rows | Format-Table -AutoSize
    Pause-Script
}

function Get-SourceVideoProfile {
    <#
    .SYNOPSIS
        Probes the source file and returns an object describing whether it is HDR
        or SDR, along with all color metadata needed for a correct x265 encode.

    .OUTPUTS
        [pscustomobject] with:
            IsHDR          [bool]   true if HDR10 or PQ/HLG transfer detected
            CRF            [int]    recommended CRF (CRF_HDR or CRF_SDR)
            PixFmt         [string] yuv420p10le always (10-bit for both modes)
            ColorPrimaries [string] e.g. bt2020 or bt709
            ColorTrc       [string] e.g. smpte2084 (PQ), arib-std-b67 (HLG), bt709
            Colorspace     [string] e.g. bt2020nc or bt709
            MasterDisplay  [string] HDR10 mastering display string or $null
            MaxCLL         [string] max content light level string or $null
            Profile        [string] human-readable label e.g. "HDR10" or "SDR"
    #>
    param([Parameter(Mandatory)][string]$Path)

    $probeArgs = @(
        '-v', 'error',
        '-probesize', $Script:M2tsProbeSize,
        '-analyzeduration', $Script:M2tsAnalyzeDur,
        '-select_streams', 'v:0',
        '-show_entries', 'stream=color_transfer,color_primaries,color_space,pix_fmt',
        '-show_entries', 'stream_side_data=side_data_type',
        '-of', 'json',
        $Path
    )

    $probeOut  = & $Script:FFprobePath @probeArgs 2>$null
    $probeJson = $null
    try { $probeJson = ($probeOut | Out-String) | ConvertFrom-Json } catch {}

    $stream = if ($probeJson -and $probeJson.streams) { $probeJson.streams[0] } else { $null }

    $trc      = if ($stream -and $stream.color_transfer)  { [string]$stream.color_transfer }  else { '' }
    $primaries = if ($stream -and $stream.color_primaries) { [string]$stream.color_primaries } else { '' }
    $colorspace = if ($stream -and $stream.color_space)    { [string]$stream.color_space }    else { '' }

    # PQ (smpte2084) = HDR10 / Dolby Vision base layer
    # HLG (arib-std-b67) = HDR HLG broadcast
    $isHDR = ($trc -match 'smpte2084|arib-std-b67|smpte428|bt2020-10|bt2020-12')

    # Pull HDR10 mastering display and MaxCLL if present
    # ffprobe exposes these via -show_frames on the first frame; use a quick 1-frame probe
    $masterDisplay = $null
    $maxCLL        = $null

    if ($isHDR) {
        $frameArgs = @(
            '-v', 'error',
            '-probesize', $Script:M2tsProbeSize,
            '-analyzeduration', $Script:M2tsAnalyzeDur,
            '-read_intervals', '%+#1',
            '-select_streams', 'v:0',
            '-show_frames',
            '-of', 'json',
            $Path
        )
        $frameOut  = & $Script:FFprobePath @frameArgs 2>$null
        $frameJson = $null
        try { $frameJson = ($frameOut | Out-String) | ConvertFrom-Json } catch {}

        if ($frameJson -and $frameJson.frames -and $frameJson.frames.Count -gt 0) {
            $sideData = $frameJson.frames[0].side_data_list
            if ($sideData) {
                $mdBlock = $sideData | Where-Object { $_.side_data_type -match 'Mastering display' } | Select-Object -First 1
                $cllBlock = $sideData | Where-Object { $_.side_data_type -match 'Content light level' } | Select-Object -First 1

                if ($mdBlock) {
                    # Build x265 master-display string: G(x,y)B(x,y)R(x,y)WP(x,y)L(max,min)
                    # ffprobe returns values in 0.00002 / 0.0001 nit units; convert to x265 int units
                    $gx = [int]([double]$mdBlock.green_x   * 50000)
                    $gy = [int]([double]$mdBlock.green_y   * 50000)
                    $bx = [int]([double]$mdBlock.blue_x    * 50000)
                    $by = [int]([double]$mdBlock.blue_y    * 50000)
                    $rx = [int]([double]$mdBlock.red_x     * 50000)
                    $ry = [int]([double]$mdBlock.red_y     * 50000)
                    $wx = [int]([double]$mdBlock.white_point_x * 50000)
                    $wy = [int]([double]$mdBlock.white_point_y * 50000)
                    $lmax = [int]([double]$mdBlock.max_luminance * 10000)
                    $lmin = [int]([double]$mdBlock.min_luminance * 10000)
                    $masterDisplay = "G($gx,$gy)B($bx,$by)R($rx,$ry)WP($wx,$wy)L($lmax,$lmin)"
                }

                if ($cllBlock) {
                    $maxCLL = "$([int]$cllBlock.max_content),$([int]$cllBlock.max_average)"
                }
            }
        }
    }

    # Resolve final color tags — fall back to sane defaults if source tags are missing
    $outPrimaries  = if ($primaries)   { $primaries }  elseif ($isHDR) { 'bt2020' }    else { 'bt709' }
    $outTrc        = if ($trc)         { $trc }        elseif ($isHDR) { 'smpte2084' } else { 'bt709' }
    $outColorspace = if ($colorspace)  { $colorspace } elseif ($isHDR) { 'bt2020nc' }  else { 'bt709' }

    $profile = if ($isHDR) {
        if ($trc -match 'arib-std-b67') { 'HLG' } else { 'HDR10' }
    } else { 'SDR' }

    return [pscustomobject]@{
        IsHDR          = $isHDR
        CRF            = if ($isHDR) { $Script:CRF_HDR } else { $Script:CRF_SDR }
        PixFmt         = 'yuv420p10le'
        ColorPrimaries = $outPrimaries
        ColorTrc       = $outTrc
        Colorspace     = $outColorspace
        MasterDisplay  = $masterDisplay
        MaxCLL         = $maxCLL
        Profile        = $profile
    }
}

function Get-VideoDuration {
    param([Parameter(Mandatory)][string]$Path)

    $args = @(
        '-v', 'error',
        '-probesize', $Script:M2tsProbeSize,
        '-analyzeduration', $Script:M2tsAnalyzeDur,
        '-show_entries', 'format=duration',
        '-of', 'default=noprint_wrappers=1:nokey=1',
        $Path
    )

    $out = & $Script:FFprobePath @args 2>$null

    if ($LASTEXITCODE -ne 0) {
        return 0
    }

    $value = ($out | Out-String).Trim()
    $duration = 0.0

    if ([double]::TryParse(
        $value,
        [System.Globalization.NumberStyles]::Float,
        [System.Globalization.CultureInfo]::InvariantCulture,
        [ref]$duration
    )) {
        return $duration
    }

    return 0
}

function Get-SafeSampleStart {
    param([Parameter(Mandatory)][double]$DurationSeconds)

    $defaultStartSeconds = [int]([TimeSpan]::Parse($Script:DefaultStart).TotalSeconds)

    if ($DurationSeconds -le ($Script:DefaultLength + 5)) {
        return '00:00:00'
    }

    if ($DurationSeconds -le ($defaultStartSeconds + $Script:DefaultLength)) {
        $fallbackStart = [Math]::Max([int]($DurationSeconds - $Script:DefaultLength - 5), 0)
        return ([TimeSpan]::FromSeconds($fallbackStart).ToString("hh\:mm\:ss"))
    }

    return $Script:DefaultStart
}

function Get-DefaultMovieName {
    param([Parameter(Mandatory)][System.IO.FileInfo]$File)

    # Blu-ray streams are often named 00000.m2ts/00004.m2ts.
    # When that happens, use the backup folder name instead of the stream file name.
    $base = [System.IO.Path]::GetFileNameWithoutExtension($File.Name)
    if ($base -match '^\d{5}$') {
        $dir = $File.Directory
        while ($dir -and $dir.FullName -ne $Script:InputRoot) {
            if ($dir.Name -and $dir.Name -notin @('STREAM', 'BDMV')) {
                return [string]$dir.Name
            }
            $dir = $dir.Parent
        }
    }

    return [string]$base
}

function Read-MovieNameWithYear {
    param([string]$DefaultName)

    $movieName = Read-Host "Movie name [$DefaultName]"
    if ([string]::IsNullOrWhiteSpace($movieName)) {
        $movieName = $DefaultName
    }

    $movieYear = Read-Host "Year (optional, 4 digits)"
    if (-not [string]::IsNullOrWhiteSpace($movieYear)) {
        if ($movieYear -match '^\d{4}$') {
            $movieName = "$movieName [$movieYear]"
        }
    }

    return [string]$movieName
}

function Get-OutputPath {
    param([Parameter(Mandatory)][string]$MovieName)

    $safeName = New-SafeName -Name $MovieName
    return [string](Join-Path $Script:OutputRoot "$safeName.$($Script:DefaultExt)")
}

function Get-SampleOutputPath {
    param([Parameter(Mandatory)][string]$MovieName)

    $safeName = New-SafeName -Name $MovieName
    $outputFile = Join-Path $Script:SampleRoot "${safeName}_sample.$($Script:DefaultExt)"

    if (Test-Path -LiteralPath $outputFile) {
        $stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
        $outputFile = Join-Path $Script:SampleRoot "${safeName}_sample_$stamp.$($Script:DefaultExt)"
    }

    return [string]$outputFile
}

function Copy-SourceToM2ts {
    # Copies (does not move) the finished source .m2ts into the m2ts directory,
    # leaving the original in place. Collision-safe via timestamp suffix.
    param([Parameter(Mandatory)][System.IO.FileInfo]$SourceFile)

    $dest = Join-Path $Script:M2tsRoot $SourceFile.Name

    if (Test-Path -LiteralPath $dest) {
        $stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
        $dest = Join-Path $Script:M2tsRoot ("{0}_{1}{2}" -f $SourceFile.BaseName, $stamp, $SourceFile.Extension)
    }

    Copy-Item -LiteralPath $SourceFile.FullName -Destination $dest -Force
    return [string]$dest
}

function Write-MetaFile {
    param(
        [Parameter(Mandatory)][string]$MovieName,
        [Parameter(Mandatory)][System.IO.FileInfo]$SourceFile,
        [Parameter(Mandatory)][string]$OutputFile,
        [Parameter(Mandatory)][double]$DurationSeconds,
        [string]$TrackMetaPath,
        [object]$VideoProfile
    )

    $safeName = New-SafeName -Name $MovieName
    $metaFile = Join-Path $Script:TxtRoot "$safeName.txt"

    $profileLabel   = if ($VideoProfile) { $VideoProfile.Profile }        else { 'unknown' }
    $crf            = if ($VideoProfile) { $VideoProfile.CRF }            else { '?' }
    $pixFmt         = if ($VideoProfile) { $VideoProfile.PixFmt }         else { '?' }
    $colorPrimaries = if ($VideoProfile) { $VideoProfile.ColorPrimaries }  else { '?' }
    $colorTrc       = if ($VideoProfile) { $VideoProfile.ColorTrc }        else { '?' }
    $colorspace     = if ($VideoProfile) { $VideoProfile.Colorspace }      else { '?' }
    $masterDisplay  = if ($VideoProfile -and $VideoProfile.MasterDisplay) { $VideoProfile.MasterDisplay } else { 'n/a' }
    $maxCLL         = if ($VideoProfile -and $VideoProfile.MaxCLL)        { $VideoProfile.MaxCLL }        else { 'n/a' }

@"
MovieName      : $MovieName
Source         : $($SourceFile.FullName)
Output         : $OutputFile
Encoded        : $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
Codec          : libx265
SourceProfile  : $profileLabel
CRF            : $crf
Preset         : $($Script:DefaultPreset)
PixFmt         : $pixFmt
PsyParams      : $($Script:X265PsyParams)
ColorPrimaries : $colorPrimaries
ColorTrc       : $colorTrc
Colorspace     : $colorspace
MasterDisplay  : $masterDisplay
MaxCLL         : $maxCLL
Audio          : $($Script:DefaultAudio)
Duration       : $DurationSeconds
Sample         : $($Script:DefaultLength) sec
TrackMeta      : $TrackMetaPath
"@ | Microsoft.PowerShell.Management\Set-Content -Path $metaFile -Encoding UTF8
}

function Wait-ForOutputFile {
    param(
        [Parameter(Mandatory)][string]$Path,
        [int]$InitialDelaySeconds = 2,
        [int]$RetryCount = 5,
        [int]$RetryDelaySeconds = 1
    )

    Start-Sleep -Seconds $InitialDelaySeconds

    $fileInfo = $null

    for ($i = 0; $i -lt $RetryCount; $i++) {
        $fileInfo = Get-Item -LiteralPath $Path -ErrorAction SilentlyContinue
        if ($fileInfo) {
            break
        }

        Start-Sleep -Seconds $RetryDelaySeconds
    }

    if (-not $fileInfo) {
        throw "Output file not found after retry: $Path"
    }

    if ($fileInfo.Length -le 0) {
        throw "Output file is empty: $Path"
    }

    return $fileInfo
}

function Get-TrackMetaSearchRoots {
    param(
        [Parameter(Mandatory)][System.IO.FileInfo]$SourceFile,
        [Parameter(Mandatory)][string]$MovieName
    )

    $roots = New-Object System.Collections.Generic.List[string]

    if ($SourceFile.Directory -and (Test-Path -LiteralPath $SourceFile.Directory.FullName)) {
        $roots.Add($SourceFile.Directory.FullName)
    }

    $dir = $SourceFile.Directory
    while ($dir) {
        if (Test-Path -LiteralPath $dir.FullName) {
            $roots.Add($dir.FullName)
        }
        if ($dir.FullName -ieq $Script:InputRoot) { break }
        $dir = $dir.Parent
    }

    $roots.Add($Script:MetaRoot)
    $roots.Add($Script:TxtRoot)
    $roots.Add($Script:OutputRoot)

    return @($roots | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)
}

function Get-AllTrackMetadataFiles {
    param(
        [Parameter(Mandatory)][System.IO.FileInfo]$SourceFile,
        [Parameter(Mandatory)][string]$MovieName
    )

    $files = New-Object System.Collections.Generic.List[object]
    foreach ($root in (Get-TrackMetaSearchRoots -SourceFile $SourceFile -MovieName $MovieName)) {
        if (-not (Test-Path -LiteralPath $root)) { continue }

        Get-ChildItem -LiteralPath $root -File -Recurse -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -like '*.json' -or $_.Name -like '*.tracks.txt' } |
            ForEach-Object { $files.Add($_) }
    }

    return @($files | Sort-Object FullName -Unique)
}

function Get-TrackMetaCandidates {
    param(
        [Parameter(Mandatory)][System.IO.FileInfo]$SourceFile,
        [Parameter(Mandatory)][string]$MovieName
    )

    $candidates = New-Object System.Collections.Generic.List[string]

    $sourceBase = [System.IO.Path]::GetFileNameWithoutExtension($SourceFile.Name)
    $movieSafe  = New-SafeName -Name $MovieName

    foreach ($root in (Get-TrackMetaSearchRoots -SourceFile $SourceFile -MovieName $MovieName)) {
        if ([string]::IsNullOrWhiteSpace($root)) { continue }

        if ($sourceBase -notmatch '^\d{5}$') {
            $candidates.Add((Join-Path $root "$sourceBase.json"))
            $candidates.Add((Join-Path $root "$sourceBase.tracks.txt"))
        }

        $candidates.Add((Join-Path $root "$movieSafe.json"))
        $candidates.Add((Join-Path $root "$movieSafe.tracks.txt"))

        $dir = $SourceFile.Directory
        while ($dir) {
            if ($dir.Name -and $dir.Name -notin @('STREAM', 'BDMV')) {
                $folderSafe = New-SafeName -Name $dir.Name
                $candidates.Add((Join-Path $root "$folderSafe.json"))
                $candidates.Add((Join-Path $root "$folderSafe.tracks.txt"))
            }
            if ($dir.FullName -ieq $Script:InputRoot) { break }
            $dir = $dir.Parent
        }
    }

    return @($candidates | Select-Object -Unique)
}

function New-BRTextTrackObject {
    param(
        [Parameter(Mandatory)][string]$TrackId,
        [Parameter(Mandatory)][string]$LanguageCode,
        [Parameter(Mandatory)][string]$Description,
        [Parameter(Mandatory)][int]$Order,
        [switch]$Forced,
        [switch]$Default
    )

    $langCode = Resolve-LanguageCode -Code $LanguageCode
    $langName = switch ($langCode) {
        'eng' { 'English' }
        'spa' { 'Spanish' }
        'fra' { 'French' }
        'fre' { 'French' }
        'jpn' { 'Japanese' }
        'ger' { 'German' }
        default { $null }
    }

    $cleanDescription = $Description.Trim()
    $cleanDescription = $cleanDescription -replace '\s*\([^)]*forced only[^)]*\)', ''
    $cleanDescription = $cleanDescription -replace '\s*\[[^\]]+\]', ''
    $cleanDescription = ($cleanDescription -replace '\s+', ' ').Trim()

    if ($langName) {
        if ($cleanDescription -match ("^PGS\s+{0}$" -f [regex]::Escape($langName))) {
            $cleanDescription = "$langName PGS"
        }
        elseif ($cleanDescription -match ("^(?<codec>.+?)\s+{0}$" -f [regex]::Escape($langName))) {
            $cleanDescription = "$langName $($Matches['codec'].Trim())"
        }
    }

    if ($Forced -and $cleanDescription -notmatch '(?i)forced') {
        $cleanDescription = "$cleanDescription Forced"
    }

    [pscustomobject]@{
        TrackId      = $TrackId
        LanguageCode = $langCode
        Description  = $cleanDescription
        Name         = $cleanDescription
        TrackName    = $cleanDescription
        Forced       = [bool]$Forced
        Default      = [bool]$Default
        Order        = $Order
        SourceFormat = 'BRTrackMetaText'
    }
}

function Convert-BRTrackTextToMetadata {
    <#
    .SYNOPSIS
        Parses bluray-trackdump/bluray-backup BRTrackMeta .tracks.txt sidecars.

    .NOTES
        Important detail: source IDs such as s17/s8/s9 are Blu-ray source IDs,
        not final MKV track IDs. For subtitle text files we preserve the order
        shown in [Subtitles] because that reflects source stream order. Audio is
        sorted by numeric a# because the final MKV audio layout usually follows
        a1, a2, a3... even when the text sidecar prints the default track last.
    #>
    param(
        [Parameter(Mandatory)][string]$Path
    )

    $lines = Microsoft.PowerShell.Management\Get-Content -LiteralPath $Path -Encoding UTF8
    $movie = [System.IO.Path]::GetFileNameWithoutExtension($Path) -replace '\.tracks$', ''
    $audio = New-Object System.Collections.Generic.List[object]
    $subs  = New-Object System.Collections.Generic.List[object]
    $section = ''
    $order = 0

    foreach ($line in $lines) {
        $trim = $line.Trim()
        if ([string]::IsNullOrWhiteSpace($trim)) { continue }

        if ($trim -match '^Movie\s*:\s*(.+)$') {
            $movie = $Matches[1].Trim()
            continue
        }

        if ($trim -match '^\[Audio\]')     { $section = 'audio'; continue }
        if ($trim -match '^\[Subtitles\]') { $section = 'subtitle'; continue }
        if ($trim -match '^\[')            { $section = ''; continue }

        if ($section -notin @('audio','subtitle')) { continue }

        # Example:
        # s9: eng / English | PGS English  (forced only) [forced, default]
        if ($trim -notmatch '^(?<id>[as]\d+)\s*:\s*(?<lang>[A-Za-z]{2,3}|und)\b.*?\|\s*(?<desc>.+)$') {
            continue
        }

        $order++
        $id   = $Matches['id']
        $lang = $Matches['lang']
        $desc = $Matches['desc'].Trim()
        $forced = ($trim -match '\[([^\]]*,\s*)?forced(\s*,[^\]]*)?\]' -or $trim -match '\(forced only\)')
        $default = ($trim -match '\[([^\]]*,\s*)?default(\s*,[^\]]*)?\]')

        $track = New-BRTextTrackObject -TrackId $id -LanguageCode $lang -Description $desc -Order $order -Forced:$forced -Default:$default

        if ($section -eq 'audio') { $audio.Add($track) }
        else { $subs.Add($track) }
    }

    # Text sidecars sometimes list default audio last. The encoded MKV follows
    # source audio stream order, so normalize audio to a1,a2,a3... while keeping
    # subtitle order exactly as listed.
    $audioSorted = @($audio | Sort-Object { [int](([string]$_.TrackId) -replace '^a','') })
    $subsOrdered = @($subs  | Sort-Object Order)

    [pscustomobject]@{
        MovieName = $movie
        MainTitle = [pscustomobject]@{
            OutputName     = $movie
            AudioTracks    = $audioSorted
            SubtitleTracks = $subsOrdered
        }
    }
}

function Read-TrackMetadataFile {
    param([Parameter(Mandatory)][string]$Path)

    $name = [System.IO.Path]::GetFileName($Path)
    if ($name -like '*.tracks.txt') {
        return Convert-BRTrackTextToMetadata -Path $Path
    }

    $raw = Microsoft.PowerShell.Management\Get-Content -LiteralPath $Path -Raw -Encoding UTF8
    return ($raw | ConvertFrom-Json)
}

function Get-LooseNameKey {
    # Punctuation-insensitive key for fuzzy sidecar matching, so a display name
    # like "Blade Runner 2049 (2017)" still matches a sidecar named or recorded
    # as "Blade Runner 2049 [2017]". Strips known metadata extensions, lowercases,
    # and flattens () [] {} and every other non-alphanumeric run to one space.
    # Used only as a fallback -- exact candidate paths are still tried first.
    param([string]$Name)

    if ([string]::IsNullOrWhiteSpace($Name)) { return '' }
    $k = ([string]$Name) -replace '(?i)\.(json|tracks\.txt|m2ts|mkv|mpls|clpi)$', ''
    $k = $k.ToLowerInvariant() -replace '[^a-z0-9]+', ' '
    return (($k -replace '\s+', ' ').Trim())
}


function Test-TrackMetadataMatch {
    param(
        [Parameter(Mandatory)][object]$Meta,
        [Parameter(Mandatory)][System.IO.FileInfo]$SourceFile,
        [Parameter(Mandatory)][string]$MovieName
    )

    $sourceName = $SourceFile.Name
    $sourceBase = [System.IO.Path]::GetFileNameWithoutExtension($SourceFile.Name)
    $movieSafe = New-SafeName -Name $MovieName

    $metaNames = @()
    if ($Meta.MovieName) { $metaNames += [string]$Meta.MovieName }
    if ($Meta.LargestM2TS) { $metaNames += [string]$Meta.LargestM2TS }
    if ($Meta.LargestPath) { $metaNames += [System.IO.Path]::GetFileName([string]$Meta.LargestPath) }
    if ($Meta.Title -and $Meta.Title.SourceFile) { $metaNames += [string]$Meta.Title.SourceFile }
    if ($Meta.Title -and $Meta.Title.OutputName) { $metaNames += [string]$Meta.Title.OutputName }
    if ($Meta.MainTitle -and $Meta.MainTitle.SourceFile) { $metaNames += [string]$Meta.MainTitle.SourceFile }
    if ($Meta.MainTitle -and $Meta.MainTitle.OutputName) { $metaNames += [string]$Meta.MainTitle.OutputName }
    if ($Meta.SourceFingerprint) {
        if ($Meta.SourceFingerprint.FileName) { $metaNames += [string]$Meta.SourceFingerprint.FileName }
        if ($Meta.SourceFingerprint.StreamFile) { $metaNames += [string]$Meta.SourceFingerprint.StreamFile }
        if ($Meta.SourceFingerprint.OutputName) { $metaNames += [string]$Meta.SourceFingerprint.OutputName }
        if ($Meta.SourceFingerprint.Playlist) { $metaNames += [string]$Meta.SourceFingerprint.Playlist }
    }

    foreach ($name in $metaNames) {
        if ([string]::IsNullOrWhiteSpace($name)) { continue }
        $base = [System.IO.Path]::GetFileNameWithoutExtension($name)
        if ($name -ieq $sourceName) { return $true }
        if ($base -ieq $sourceBase) { return $true }
        if ((New-SafeName -Name $name) -ieq $movieSafe) { return $true }
        if ((New-SafeName -Name $base) -ieq $movieSafe) { return $true }
    }

    # Last useful fallback: if the movie name equals the JSON movie name.
    if ($Meta.MovieName -and ((New-SafeName -Name ([string]$Meta.MovieName)) -ieq $movieSafe)) {
        return $true
    }

    # Punctuation-insensitive fallback: e.g. "... (2017)" matches "... [2017]".
    $movieKey = Get-LooseNameKey -Name $MovieName
    if ($movieKey) {
        foreach ($name in $metaNames) {
            if ((Get-LooseNameKey -Name $name) -ieq $movieKey) { return $true }
        }
        if ($Meta.MovieName -and ((Get-LooseNameKey -Name ([string]$Meta.MovieName)) -ieq $movieKey)) { return $true }
    }

    return $false
}

function Load-TrackMetadata {
    param(
        [Parameter(Mandatory)][System.IO.FileInfo]$SourceFile,
        [Parameter(Mandatory)][string]$MovieName
    )

    $candidates = Get-TrackMetaCandidates -SourceFile $SourceFile -MovieName $MovieName

    foreach ($path in $candidates) {
        if (Test-Path -LiteralPath $path) {
            try {
                $data = Read-TrackMetadataFile -Path $path
                return [pscustomobject]@{
                    Path = $path
                    Data = $data
                }
            }
            catch {
                Write-UiBlankLine
                Write-CoreError "Failed to read track metadata: $path"
                Write-Host "  $($global:UI_GRY)$($_.Exception.Message)$($global:UI_R)"
                throw
            }
        }
    }

    $metadataFiles = @(Get-AllTrackMetadataFiles -SourceFile $SourceFile -MovieName $MovieName |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First $Script:MetadataScanLimit)

    $movieKey = Get-LooseNameKey -Name $MovieName
    foreach ($file in $metadataFiles) {
        try {
            $data = Read-TrackMetadataFile -Path $file.FullName
            $fileKey = Get-LooseNameKey -Name $file.Name
            if ((Test-TrackMetadataMatch -Meta $data -SourceFile $SourceFile -MovieName $MovieName) -or ($movieKey -and $fileKey -ieq $movieKey)) {
                return [pscustomobject]@{
                    Path = $file.FullName
                    Data = $data
                }
            }
        }
        catch {
            continue
        }
    }

    return $null
}

function Resolve-LanguageCode {
    param([string]$Code)

    if ([string]::IsNullOrWhiteSpace($Code)) { return 'und' }

    $clean = $Code.Trim().ToLowerInvariant()
    $clean = $clean -replace '[^a-z]', ''
    if ([string]::IsNullOrWhiteSpace($clean)) { return 'und' }

    # Normalize common ISO-639 aliases to the bibliographic 639-2 codes most
    # often written by MakeMKV/MKVToolNix in older Blu-ray workflows.
    switch ($clean) {
        'fra' { return 'fre' }  'fre' { return 'fre' }  'french' { return 'fre' }  'fr' { return 'fre' }
        'deu' { return 'ger' }  'ger' { return 'ger' }  'german' { return 'ger' }  'de' { return 'ger' }
        'zho' { return 'chi' }  'chi' { return 'chi' }  'chinese' { return 'chi' } 'zh' { return 'chi' }
        'nld' { return 'dut' }  'dut' { return 'dut' }  'dutch' { return 'dut' }   'nl' { return 'dut' }
        'ell' { return 'gre' }  'gre' { return 'gre' }  'greek' { return 'gre' }   'el' { return 'gre' }
        'ces' { return 'cze' }  'cze' { return 'cze' }  'czech' { return 'cze' }   'cs' { return 'cze' }
        'slk' { return 'slo' }  'slo' { return 'slo' }  'slovak' { return 'slo' }  'sk' { return 'slo' }
        'ron' { return 'rum' }  'rum' { return 'rum' }  'romanian' { return 'rum' } 'ro' { return 'rum' }
        'msa' { return 'may' }  'may' { return 'may' }  'malay' { return 'may' }   'ms' { return 'may' }
    }

    # Full language name → ISO 639-2/B code
    switch ($clean) {
        'english'    { return 'eng' }
        'spanish'    { return 'spa' }
        'japanese'   { return 'jpn' }
        'italian'    { return 'ita' }
        'portuguese' { return 'por' }
        'korean'     { return 'kor' }
        'arabic'     { return 'ara' }
        'russian'    { return 'rus' }
        'hindi'      { return 'hin' }
        'swedish'    { return 'swe' }
        'norwegian'  { return 'nor' }
        'danish'     { return 'dan' }
        'finnish'    { return 'fin' }
        'polish'     { return 'pol' }
        'hungarian'  { return 'hun' }
        'turkish'    { return 'tur' }
        'hebrew'     { return 'heb' }
        'thai'       { return 'tha' }
        'vietnamese' { return 'vie' }
        'indonesian' { return 'ind' }
        'ukrainian'  { return 'ukr' }
        'croatian'   { return 'hrv' }
        'bulgarian'  { return 'bul' }
        'catalan'    { return 'cat' }
        # 2-letter ISO 639-1 codes — map to 639-2
        'en' { return 'eng' } 'es' { return 'spa' } 'ja' { return 'jpn' }
        'it' { return 'ita' } 'pt' { return 'por' } 'ko' { return 'kor' }
        'ar' { return 'ara' } 'ru' { return 'rus' } 'hi' { return 'hin' }
        'sv' { return 'swe' } 'no' { return 'nor' } 'da' { return 'dan' }
        'fi' { return 'fin' } 'pl' { return 'pol' } 'hu' { return 'hun' }
        'tr' { return 'tur' } 'he' { return 'heb' } 'th' { return 'tha' }
        'vi' { return 'vie' } 'id' { return 'ind' } 'uk' { return 'ukr' }
        'hr' { return 'hrv' } 'bg' { return 'bul' } 'ca' { return 'cat' }
        # Explicit unknowns
        'unknown'      { return 'und' }
        'undetermined' { return 'und' }
        'und'          { return 'und' }
    }

    # Already a valid 3-letter ISO 639 code — pass it through after aliases.
    if ($clean -match '^[a-z]{3}$') { return $clean }

    return 'und'
}


function Get-TrackMetaTitle {
    param([Parameter(Mandatory)][object]$Meta)

    if ($Meta.MainTitle) { return $Meta.MainTitle }
    if ($Meta.Title)     { return $Meta.Title }
    return $null
}

function Resolve-TrackList {
    param(
        [Parameter(Mandatory)][object]$Title,
        [Parameter(Mandatory)][ValidateSet('audio','subtitle')][string]$Kind
    )

    if ($Kind -eq 'audio') {
        if ($Title.AudioTracks) { return @($Title.AudioTracks) }
        if ($Title.Tracks)      { return @($Title.Tracks | Where-Object { $_.Type -eq 'Audio' } | Sort-Object TrackId) }
    }

    if ($Kind -eq 'subtitle') {
        if ($Title.SubtitleTracks) { return @($Title.SubtitleTracks) }
        if ($Title.Tracks)         { return @($Title.Tracks | Where-Object { $_.Type -eq 'Subtitles' } | Sort-Object TrackId) }
    }

    return @()
}

function Get-OutputTrackLayout {
    param([Parameter(Mandatory)][string]$Path)

    $jsonText = & $Script:MKVMergePath -J $Path 2>$null
    if ($LASTEXITCODE -ne 0) {
        throw "mkvmerge -J failed while reading output track layout."
    }

    $json = ($jsonText | Out-String) | ConvertFrom-Json
    $tracks = @($json.tracks)
    $audio = @($tracks | Where-Object { $_.type -eq 'audio' })
    $subs  = @($tracks | Where-Object { $_.type -eq 'subtitles' })

    [pscustomobject]@{
        AudioCount    = $audio.Count
        SubtitleCount = $subs.Count
        Tracks        = $tracks
        AudioTracks   = $audio
        SubtitleTracks = $subs
    }
}

function Test-BRTrackMetadata {
    param(
        [Parameter(Mandatory)][object]$Meta,
        [Parameter(Mandatory)][object]$Title,
        [Parameter(Mandatory)][object]$TrackLayout
    )

    $warnings = New-Object System.Collections.Generic.List[string]
    $audioMeta = @(Resolve-TrackList -Title $Title -Kind audio)
    $subMeta   = @(Resolve-TrackList -Title $Title -Kind subtitle)

    if ($audioMeta.Count -eq 0) { $warnings.Add('Metadata has no audio tracks.') }
    if ($TrackLayout.AudioCount -ne $audioMeta.Count) {
        $warnings.Add("Audio count mismatch: output=$($TrackLayout.AudioCount), metadata=$($audioMeta.Count). Physical CLPI/source counts will be used when available.")
    }
    if ($TrackLayout.SubtitleCount -ne $subMeta.Count) {
        $warnings.Add("Subtitle count mismatch: output=$($TrackLayout.SubtitleCount), metadata=$($subMeta.Count). Physical CLPI/source counts will be used when available.")
    }

    $knownAudio = @($audioMeta | Where-Object { (Get-MetaLanguage -Track $_) -ne 'und' })
    $knownSubs  = @($subMeta   | Where-Object { (Get-MetaLanguage -Track $_) -ne 'und' })
    if ($audioMeta.Count -gt 0 -and $knownAudio.Count -eq 0) { $warnings.Add('All metadata audio languages are und/unknown.') }
    if ($subMeta.Count   -gt 0 -and $knownSubs.Count  -eq 0) { $warnings.Add('All metadata subtitle languages are und/unknown.') }

    return @($warnings)
}

function Show-MetadataWarnings {
    param([string[]]$Warnings)

    if (-not $Warnings -or $Warnings.Count -eq 0) { return }

    Write-UiBlankLine
    Write-Host "  $($global:UI_YLW)Metadata validation warnings:$($global:UI_R)"
    foreach ($w in $Warnings) {
        Write-Host "  $($global:UI_YLW)-$($global:UI_R) $w"
    }
}

function Show-FinalMetadataVerification {
    param([Parameter(Mandatory)][string]$OutputFile)

    $layout = Get-OutputTrackLayout -Path $OutputFile

    Write-UiBlankLine
    Write-Host "  $($global:UI_CYN)Final MKV metadata verification:$($global:UI_R)"

    if ($layout.AudioTracks.Count -gt 0) {
        Write-Host "  $($global:UI_MAG)Audio:$($global:UI_R)"
        $n = 1
        foreach ($t in $layout.AudioTracks) {
            $p = $t.properties
            $lang = if ($p.language) { $p.language } else { 'und' }
            $name = if ($p.track_name) { $p.track_name } else { '' }
            $def  = if ($p.default_track) { ' default' } else { '' }
            Write-Host ("    a{0}: {1} {2}{3}" -f $n, $lang, $name, $def)
            $n++
        }
    }

    if ($layout.SubtitleTracks.Count -gt 0) {
        Write-Host "  $($global:UI_MAG)Subtitles:$($global:UI_R)"
        $n = 1
        foreach ($t in $layout.SubtitleTracks) {
            $p = $t.properties
            $lang = if ($p.language) { $p.language } else { 'und' }
            $name = if ($p.track_name) { $p.track_name } else { '' }
            $def  = if ($p.default_track) { ' default' } else { '' }
            $forc = if ($p.forced_track)  { ' forced' } else { '' }
            Write-Host ("    s{0}: {1} {2}{3}{4}" -f $n, $lang, $name, $def, $forc)
            $n++
        }
    }
}


function Get-MetaLanguage {
    param([Parameter(Mandatory)][object]$Track)

    # Different ripping tools (MakeMKV, HandBrake, tsMuxer, bluray-backup, etc.)
    # use different property names for the language field. Try all known variants
    # before giving up and returning 'und'.
    $candidates = @(
        $Track.LanguageCode,
        $Track.Language,
        $Track.Lang,
        $Track.LanguageName,
        $Track.language,
        $Track.languageCode,
        $Track.lang,
        $Track.languageName,
        $Track.iso639_2,
        $Track.iso639,
        $Track.tag_language,
        $Track.Language3,
        $Track.LangCode,
        $Track.Iso,
        $Track.AudioLanguage,
        $Track.SubtitleLanguage
    )

    foreach ($c in $candidates) {
        if ($null -eq $c) { continue }
        $val = [string]$c
        if ([string]::IsNullOrWhiteSpace($val)) { continue }
        $lang = Resolve-LanguageCode -Code $val
        if ($lang -and $lang -ne 'und') { return $lang }
    }

    return 'und'
}

function Get-MetaTrackName {
    param([Parameter(Mandatory)][object]$Track)

    $candidates = @(
        $Track.Description,
        $Track.Name,
        $Track.TrackName,
        $Track.CodecLong,
        $Track.CodecShort
    )

    foreach ($c in $candidates) {
        if (-not [string]::IsNullOrWhiteSpace([string]$c)) {
            return [string]$c
        }
    }

    return $null
}

function Get-AnyTaggedLanguageCount {
    param([Parameter(Mandatory)][object]$TrackLayout)

    $count = 0
    foreach ($t in @($TrackLayout.AudioTracks + $TrackLayout.SubtitleTracks)) {
        $lang = if ($t.properties.language) { [string]$t.properties.language } else { 'und' }
        if ($lang -and $lang -ne 'und') { $count++ }
    }
    return $count
}

function Get-SourceStreamLanguageMap {
    <#
    .SYNOPSIS
        Probes the source file with ffprobe and returns the raw per-stream
        language tag for every audio and subtitle stream, in the SAME order
        ffmpeg muxes them (0:a:0, 0:a:1 ... and 0:s:0, 0:s:1 ...).

    .NOTES
        This is the order-safe key for language tagging. The encode mapped
        streams straight off this file with 0:a:N?/0:s:N?, so ffprobe's
        enumeration here lines up one-for-one with the finished MKV's track
        order — unlike the sidecar list, which is ordered by MakeMKV's track
        index and can disagree with ffmpeg's m2ts stream order.

        Returns 'und' for streams that carry no language tag so the caller can
        decide whether to fall back to the sidecar for those slots only.
        On any failure returns empty arrays, which makes the caller degrade
        cleanly to sidecar-only (the previous behaviour).
    #>
    param([Parameter(Mandatory)][string]$SourcePath)

    $empty = [pscustomobject]@{ Audio = @(); Sub = @() }

    if ([string]::IsNullOrWhiteSpace($SourcePath) -or -not (Test-Path -LiteralPath $SourcePath)) {
        return $empty
    }

    $probeArgs = @(
        '-v', 'error',
        '-probesize', $Script:M2tsProbeSize,
        '-analyzeduration', $Script:M2tsAnalyzeDur,
        '-show_entries', 'stream=index,codec_type:stream_tags=language',
        '-of', 'json',
        $SourcePath
    )

    $probeOut  = & $Script:FFprobePath @probeArgs 2>$null
    $probeJson = $null
    try { $probeJson = ($probeOut | Out-String) | ConvertFrom-Json } catch {}

    if (-not $probeJson -or -not $probeJson.streams) { return $empty }

    # ffprobe emits streams in container index order; Where-Object preserves it.
    $audio = @($probeJson.streams |
        Where-Object { $_.codec_type -eq 'audio' } |
        ForEach-Object { if ($_.tags -and $_.tags.language) { [string]$_.tags.language } else { 'und' } })
    $sub = @($probeJson.streams |
        Where-Object { $_.codec_type -eq 'subtitle' } |
        ForEach-Object { if ($_.tags -and $_.tags.language) { [string]$_.tags.language } else { 'und' } })

    return [pscustomobject]@{ Audio = $audio; Sub = $sub }
}


function Get-MetaPhysicalStreamLanguages {
    <#
    .SYNOPSIS
        Reads physical source-stream language lists saved in BRTrackMeta/1.1.

    .DESCRIPTION
        bluray-backup.ps1 v2.3 stores CLPI-derived audio/subtitle languages in
        the sidecar. That gives repair/tagging a deterministic fallback even when
        only the copied .m2ts remains and the original BDMV\CLIPINF folder is gone.
    #>
    param([object]$Meta)

    $empty = [pscustomobject]@{ Audio = @(); Subtitle = @(); Status = 'sidecar physical: none' }
    if (-not $Meta) { return $empty }

    $physical = $null
    if ($Meta.PSObject.Properties['PhysicalStreams'] -and $Meta.PhysicalStreams) {
        $physical = $Meta.PhysicalStreams
    }
    elseif ($Meta.SourceFingerprint -and $Meta.SourceFingerprint.PSObject.Properties['PhysicalStreams'] -and $Meta.SourceFingerprint.PhysicalStreams) {
        $physical = $Meta.SourceFingerprint.PhysicalStreams
    }

    if (-not $physical) { return $empty }

    $audioRaw = @()
    foreach ($prop in @('AudioLanguages','Audio','AudioLangs','AudioLanguageCodes')) {
        $m = $physical.PSObject.Properties[$prop]
        if ($m -and $m.Value) { $audioRaw = @($m.Value); break }
    }

    $subRaw = @()
    foreach ($prop in @('SubtitleLanguages','Subtitles','Subtitle','SubtitleLangs','SubtitleLanguageCodes')) {
        $m = $physical.PSObject.Properties[$prop]
        if ($m -and $m.Value) { $subRaw = @($m.Value); break }
    }

    $audio = @($audioRaw | ForEach-Object { Resolve-LanguageCode -Code ([string]$_) })
    $subs  = @($subRaw   | ForEach-Object { Resolve-LanguageCode -Code ([string]$_) })
    $status = if ($physical.PSObject.Properties['Status'] -and $physical.Status) { [string]$physical.Status } else { 'sidecar physical stream languages' }

    return [pscustomobject]@{ Audio = $audio; Subtitle = $subs; Status = $status }
}

function Read-ClpiSubtitleLanguages {
    <#
    .SYNOPSIS
        Reads authoritative PGS subtitle languages from the Blu-ray clip info
        file (BDMV\CLIPINF\<clip>.clpi) that sits beside the source .m2ts.
    .DESCRIPTION
        The raw .m2ts carries no subtitle language tags, but the .clpi stores
        every elementary stream's ISO-639 language by PID. PGS streams sorted
        by PID are in the exact order ffmpeg maps 0:s:0..0:s:N, so the returned
        list lines up 1:1 with the encoded subtitle tracks. Returns $null if the
        .clpi can't be found or parsed (caller falls back to sidecar tagging).
    #>
    param([Parameter(Mandatory)][string]$M2tsPath)

    try {
        $streamDir = [System.IO.Path]::GetDirectoryName($M2tsPath)        # ...\BDMV\STREAM
        $base      = [System.IO.Path]::GetFileNameWithoutExtension($M2tsPath)
        $bdmv      = [System.IO.Path]::GetDirectoryName($streamDir)       # ...\BDMV
        if (-not $bdmv) { return $null }
        $clpi = Join-Path (Join-Path $bdmv 'CLIPINF') ('{0}.clpi' -f $base)
        if (-not (Test-Path -LiteralPath $clpi)) { return $null }

        $b = [System.IO.File]::ReadAllBytes($clpi)
        if ($b.Length -lt 40) { return $null }
        if ([System.Text.Encoding]::ASCII.GetString($b, 0, 4) -ne 'HDMV') { return $null }

        # ProgramInfo_start_address is a big-endian uint32 at offset 12.
        $progStart = ([int]$b[12] -shl 24) -bor ([int]$b[13] -shl 16) -bor ([int]$b[14] -shl 8) -bor [int]$b[15]
        if ($progStart -le 0 -or ($progStart + 6) -ge $b.Length) { return $null }

        $p = $progStart + 4          # skip length (4 bytes)
        $p += 1                      # reserved_for_word_align (1)
        $numSeq = [int]$b[$p]; $p += 1

        $subs = New-Object System.Collections.Generic.List[object]
        for ($sq = 0; $sq -lt $numSeq; $sq++) {
            $p += 4                  # SPN_program_sequence_start
            $p += 2                  # program_map_PID
            $numStreams = [int]$b[$p]; $p += 1
            $p += 1                  # reserved
            for ($k = 0; $k -lt $numStreams; $k++) {
                if (($p + 3) -gt $b.Length) { return $null }
                $streamPid = ([int]$b[$p] -shl 8) -bor [int]$b[$p + 1]; $p += 2
                $ciLen = [int]$b[$p]; $p += 1     # StreamCodingInfo length
                $ciEnd = $p + $ciLen
                if ($ciEnd -gt $b.Length) { return $null }
                $codingType = [int]$b[$p]
                if ($codingType -eq 0x90 -or $codingType -eq 0x91) {
                    # PG/IG subtitle: 3-byte language_code right after coding type.
                    $lang = [System.Text.Encoding]::ASCII.GetString($b, $p + 1, 3)
                    $subs.Add([pscustomobject]@{ PID = $streamPid; Lang = $lang })
                }
                elseif ($codingType -eq 0x92) {
                    # Text subtitle: char_code (1) then 3-byte language_code.
                    $lang = [System.Text.Encoding]::ASCII.GetString($b, $p + 2, 3)
                    $subs.Add([pscustomobject]@{ PID = $streamPid; Lang = $lang })
                }
                $p = $ciEnd
            }
        }

        if ($subs.Count -eq 0) { return $null }
        # ffmpeg maps PGS in ascending PID order -> sort to match 0:s:0..N.
        return @($subs | Sort-Object PID | ForEach-Object {
            Resolve-LanguageCode -Code ($_.Lang -replace '[^A-Za-z]', '')
        })
    }
    catch { return $null }
}

function Read-ClpiStreamLanguages {
    <#
    .SYNOPSIS
        Reads ISO-639 languages for BOTH audio and PG/Text subtitle streams from
        the Blu-ray clip info (BDMV\CLIPINF\<clip>.clpi) beside the source .m2ts.
    .DESCRIPTION
        The raw .m2ts carries no language tags; the .clpi StreamCodingInfo table
        does, for audio coding types as well as PG/IG/Text subtitles. Returns
        [pscustomobject]@{ Audio=@(langs); Subtitle=@(langs); Status='...' } with
        each list sorted by PID so it lines up 1:1 with ffmpeg's 0:a:0..N and
        0:s:0..N mapping. Lists are empty when nothing is found; Status is a short
        human-readable note for logging. Never throws -- worst case is empty lists.
    #>
    param([Parameter(Mandatory)][string]$M2tsPath)

    $audio = New-Object System.Collections.Generic.List[object]
    $subs  = New-Object System.Collections.Generic.List[object]
    try {
        $streamDir = [System.IO.Path]::GetDirectoryName($M2tsPath)
        $base      = [System.IO.Path]::GetFileNameWithoutExtension($M2tsPath)
        $bdmv      = [System.IO.Path]::GetDirectoryName($streamDir)
        if (-not $bdmv) { return [pscustomobject]@{ Audio=@(); Subtitle=@(); Status='clpi: no BDMV parent dir' } }
        $clpi = Join-Path (Join-Path $bdmv 'CLIPINF') ('{0}.clpi' -f $base)
        if (-not (Test-Path -LiteralPath $clpi)) {
            return [pscustomobject]@{ Audio=@(); Subtitle=@(); Status=("clpi: not found -> {0}" -f $clpi) }
        }
        $b = [System.IO.File]::ReadAllBytes($clpi)
        if ($b.Length -lt 40 -or [System.Text.Encoding]::ASCII.GetString($b, 0, 4) -ne 'HDMV') {
            return [pscustomobject]@{ Audio=@(); Subtitle=@(); Status='clpi: bad header (not HDMV)' }
        }
        $progStart = ([int]$b[12] -shl 24) -bor ([int]$b[13] -shl 16) -bor ([int]$b[14] -shl 8) -bor [int]$b[15]
        if ($progStart -le 0 -or ($progStart + 6) -ge $b.Length) {
            return [pscustomobject]@{ Audio=@(); Subtitle=@(); Status='clpi: bad ProgramInfo offset' }
        }
        $p = $progStart + 4      # skip length (4)
        $p += 1                  # reserved_for_word_align (1)
        $numSeq = [int]$b[$p]; $p += 1
        for ($sq = 0; $sq -lt $numSeq; $sq++) {
            $p += 4              # SPN_program_sequence_start
            $p += 2              # program_map_PID
            $numStreams = [int]$b[$p]; $p += 1
            $p += 1              # reserved
            for ($k = 0; $k -lt $numStreams; $k++) {
                if (($p + 3) -gt $b.Length) { break }
                $streamPid = ([int]$b[$p] -shl 8) -bor [int]$b[$p + 1]; $p += 2
                $ciLen = [int]$b[$p]; $p += 1     # StreamCodingInfo length
                $ciEnd = $p + $ciLen
                if ($ciEnd -gt $b.Length) { break }
                $ct = [int]$b[$p]
                # Audio coding types: MPEG1/2 (0x03,0x04), LPCM (0x80), AC-3 (0x81),
                # DTS (0x82), TrueHD (0x83), E-AC3 (0x84), DTS-HD (0x85), DTS-HD MA
                # (0x86), secondary E-AC3/DTS (0xA1,0xA2). Layout after coding_type:
                # audio_format/sample_rate (1 byte) then 3-byte ISO-639 language.
                if ($ct -eq 0x03 -or $ct -eq 0x04 -or ($ct -ge 0x80 -and $ct -le 0x86) -or $ct -eq 0xA1 -or $ct -eq 0xA2) {
                    $lang = [System.Text.Encoding]::ASCII.GetString($b, $p + 2, 3)
                    $audio.Add([pscustomobject]@{ PID = $streamPid; Lang = $lang })
                }
                elseif ($ct -eq 0x90 -or $ct -eq 0x91) {
                    # PG/IG subtitle: 3-byte language right after coding type.
                    $lang = [System.Text.Encoding]::ASCII.GetString($b, $p + 1, 3)
                    $subs.Add([pscustomobject]@{ PID = $streamPid; Lang = $lang })
                }
                elseif ($ct -eq 0x92) {
                    # Text subtitle: char_code (1) then 3-byte language.
                    $lang = [System.Text.Encoding]::ASCII.GetString($b, $p + 2, 3)
                    $subs.Add([pscustomobject]@{ PID = $streamPid; Lang = $lang })
                }
                $p = $ciEnd
            }
        }
        $aL = @($audio | Sort-Object PID | ForEach-Object { Resolve-LanguageCode -Code ($_.Lang -replace '[^A-Za-z]', '') })
        $sL = @($subs  | Sort-Object PID | ForEach-Object { Resolve-LanguageCode -Code ($_.Lang -replace '[^A-Za-z]', '') })
        return [pscustomobject]@{ Audio = $aL; Subtitle = $sL; Status = ("clpi: {0} audio / {1} subtitle langs" -f $aL.Count, $sL.Count) }
    }
    catch {
        return [pscustomobject]@{ Audio = @(); Subtitle = @(); Status = ("clpi: parse error - {0}" -f $_.Exception.Message) }
    }
}

function Get-LanguageDisplayName {
    param([string]$Code)
    $lang = Resolve-LanguageCode -Code $Code
    switch ($lang) {
        'eng' { 'English' }
        'spa' { 'Spanish' }
        'fre' { 'French' }
        'ger' { 'German' }
        'jpn' { 'Japanese' }
        'ita' { 'Italian' }
        'por' { 'Portuguese' }
        'rus' { 'Russian' }
        'kor' { 'Korean' }
        'chi' { 'Chinese' }
        'dut' { 'Dutch' }
        'ara' { 'Arabic' }
        'hin' { 'Hindi' }
        'swe' { 'Swedish' }
        'nor' { 'Norwegian' }
        'dan' { 'Danish' }
        'fin' { 'Finnish' }
        'pol' { 'Polish' }
        'cze' { 'Czech' }
        'hun' { 'Hungarian' }
        'tur' { 'Turkish' }
        'gre' { 'Greek' }
        'heb' { 'Hebrew' }
        'tha' { 'Thai' }
        'vie' { 'Vietnamese' }
        'ind' { 'Indonesian' }
        'may' { 'Malay' }
        'rum' { 'Romanian' }
        'ukr' { 'Ukrainian' }
        'hrv' { 'Croatian' }
        'slo' { 'Slovak' }
        'bul' { 'Bulgarian' }
        'cat' { 'Catalan' }
        default { $null }
    }
}

function New-AudioTrackName {
    # Friendly name like "TrueHD Atmos 7.1 English" from the mkvmerge codec
    # display string + channel count + language. Used when tagging audio from
    # the .clpi, which carries no track names.
    param([string]$Codec, [int]$Channels, [string]$Lang)

    $ch = switch ($Channels) {
        8 { '7.1' }
        7 { '6.1' }
        6 { '5.1' }
        2 { '2.0' }
        1 { 'Mono' }
        default { if ($Channels -gt 0) { "$Channels ch" } else { '' } }
    }
    $ln = Get-LanguageDisplayName -Code $Lang
    return ((@($Codec, $ch, $ln) | Where-Object { $_ }) -join ' ').Trim()
}

function Invoke-MKVLanguageRemux {
    <#
    .SYNOPSIS
        Writes language, track name, default, and forced flags directly into
        the MKV track headers using mkvpropedit.

    .NOTES
        Language priority: authoritative .clpi (physical PID order) > GUI
        overrides > sidecar. Source ffprobe language tags are never used.
    #>
    param(
        [Parameter(Mandatory)][string]$OutputFile,
        [Parameter(Mandatory)][object]$TrackLayout,
        [Parameter(Mandatory)][object[]]$AudioMeta,
        [Parameter(Mandatory)][object[]]$SubMeta,
        [string]$SourcePath,
        [string]$OverridesFile,
        [object]$Meta
    )

    $propArgs = @($OutputFile)
    $applied  = 0

    # Optional per-track overrides (authoritative, from the GUI). Each entry:
    # { type:'audio'|'subtitle', n:<1-based>, lang, forced, default, commentary, name }
    $ovrAudio = @{}; $ovrSub = @{}
    if ($OverridesFile -and (Test-Path -LiteralPath $OverridesFile)) {
        try {
            $ovrData = Get-Content -LiteralPath $OverridesFile -Raw | ConvertFrom-Json
            foreach ($o in @($ovrData)) {
                $n = [int]$o.n
                if     ($o.type -eq 'audio')    { $ovrAudio[$n] = $o }
                elseif ($o.type -eq 'subtitle') { $ovrSub[$n]   = $o }
            }
            Write-Host "  Overrides loaded: $($ovrAudio.Count) audio, $($ovrSub.Count) subtitle"
        } catch { Write-Host "    (overrides parse failed: $($_.Exception.Message))" }
    }

    # Audio languages from the Blu-ray clip info when the sidecar (playlist-level
    # MakeMKV count) diverges from the physical stream count ffmpeg actually muxes.
    # The .clpi is in physical PID order, so it lines up 1:1 with the encoded tracks.
    $audOutCount  = $TrackLayout.AudioTracks.Count
    $clpiAllLangs = if ($SourcePath) { Read-ClpiStreamLanguages -M2tsPath $SourcePath } else { $null }
    $clpiAudLangs = if ($clpiAllLangs) { @($clpiAllLangs.Audio) } else { @() }
    $metaPhysical = Get-MetaPhysicalStreamLanguages -Meta $Meta
    $metaAudLangs = @($metaPhysical.Audio)
    $metaSubLangs = @($metaPhysical.Subtitle)
    $useClpiAudio = ($clpiAudLangs.Count -eq $audOutCount -and $audOutCount -gt 0)
    $useMetaAudio = (-not $useClpiAudio -and $metaAudLangs.Count -eq $audOutCount -and $audOutCount -gt 0)

    if ($ovrAudio.Count -eq 0 -and -not $useClpiAudio -and -not $useMetaAudio -and $audOutCount -ne $AudioMeta.Count) {
        throw "Audio validation failed: output=$audOutCount, metadata=$($AudioMeta.Count), and no usable .clpi/sidecar physical languages. Refusing unsafe partial tagging."
    }
    # Prefer authoritative subtitle languages from the Blu-ray clip info; if the
    # original CLPI is gone, use the CLPI-derived physical lists saved in sidecar.
    $subOutCount  = $TrackLayout.SubtitleTracks.Count
    $clpiSubLangs = if ($clpiAllLangs) { @($clpiAllLangs.Subtitle) } else { @() }
    $useClpiSubs  = ($clpiSubLangs.Count -eq $subOutCount -and $subOutCount -gt 0)
    $useMetaSubs  = (-not $useClpiSubs -and $metaSubLangs.Count -eq $subOutCount -and $subOutCount -gt 0)

    # Source-MKV subtitle languages: when encoding from a MakeMKV/remux .mkv (not
    # a raw BDMV), the source already carries per-stream ISO-639 tags in the exact
    # 0:s:0..N order ffmpeg muxed, so they line up 1:1 with the encoded output even
    # when the disc-level sidecar lists more streams than MakeMKV actually kept.
    $srcSubLangs = @(); $srcSubForced = @()
    if ($SourcePath -and ($SourcePath -match '\.mkv$') -and (Test-Path -LiteralPath $SourcePath)) {
        try {
            $srcJson = & $Script:MKVMergePath -J $SourcePath 2>$null | Out-String | ConvertFrom-Json
            $srcSub  = @(@($srcJson.tracks) | Where-Object { $_.type -eq 'subtitles' })
            $srcSubLangs  = @($srcSub | ForEach-Object { if ($_.properties.language) { [string]$_.properties.language } else { 'und' } })
            $srcSubForced = @($srcSub | ForEach-Object { [bool]$_.properties.forced_track })
        } catch { $srcSubLangs = @(); $srcSubForced = @() }
    }
    $knownSrcSub = @($srcSubLangs | Where-Object { $_ -ne 'und' }).Count
    $useSrcSubs  = ($srcSubLangs.Count -eq $subOutCount -and $subOutCount -gt 0 -and $knownSrcSub -gt 0)

    if ($ovrSub.Count -eq 0 -and -not $useClpiSubs -and -not $useMetaSubs -and -not $useSrcSubs -and $subOutCount -ne $SubMeta.Count) {
        throw "Subtitle validation failed: output=$subOutCount, metadata=$($SubMeta.Count), and no usable .clpi/sidecar physical/source languages or overrides. Refusing unsafe partial tagging."
    }

    # Default audio = best-sounding English that physically exists: rank lossless
    # codecs over lossy, then most channels. Explicit GUI overrides still win.
    $audLangAt = {
        param([int]$ix)
        if     ($useClpiAudio)            { return [string]$clpiAudLangs[$ix] }
        elseif ($useMetaAudio)            { return [string]$metaAudLangs[$ix] }
        elseif ($ix -lt $AudioMeta.Count) { return (Get-MetaLanguage -Track $AudioMeta[$ix]) }
        else                              { return 'und' }
    }
    $audDefaultIndex = 0
    if ($ovrAudio.Count -eq 0) {
        $codecRank = @{ 'A_TRUEHD' = 6; 'A_MLP' = 6; 'A_FLAC' = 5; 'A_DTS' = 4; 'A_EAC3' = 3; 'A_AC3' = 2; 'A_AAC' = 1; 'A_OPUS' = 1 }
        $bestRank = -1; $bestCh = -1
        for ($di = 0; $di -lt $audOutCount; $di++) {
            if ((& $audLangAt $di) -ne 'eng') { continue }
            $props = $TrackLayout.AudioTracks[$di].properties
            $cid = if ($props -and $props.codec_id)      { [string]$props.codec_id }     else { '' }
            $ch  = if ($props -and $props.audio_channels) { [int]$props.audio_channels } else { 0 }
            $rank = if ($codecRank.ContainsKey($cid)) { $codecRank[$cid] } else { 0 }
            if ($rank -gt $bestRank -or ($rank -eq $bestRank -and $ch -gt $bestCh)) {
                $bestRank = $rank; $bestCh = $ch; $audDefaultIndex = $di + 1
            }
        }
        if ($audDefaultIndex -eq 0 -and $audOutCount -gt 0) { $audDefaultIndex = 1 }
    }

    $audioCount = $audOutCount
    for ($i = 0; $i -lt $audioCount; $i++) {
        $metaTrack = if ($i -lt $AudioMeta.Count) { $AudioMeta[$i] } else { $null }
        $o = $ovrAudio[$i + 1]
        if ($o) {
            $lang      = Resolve-LanguageCode -Code ([string]$o.lang)
            $name      = if ($o.PSObject.Properties['name'] -and $o.name) { [string]$o.name } else { $null }
            $isDefault = [bool]$o.default
            $isComm    = [bool]$o.commentary
            $src       = 'override'
        }
        elseif ($useClpiAudio -or $useMetaAudio) {
            $lang      = if ($useClpiAudio) { [string]$clpiAudLangs[$i] } else { [string]$metaAudLangs[$i] }
            $name      = New-AudioTrackName -Codec ([string]$TrackLayout.AudioTracks[$i].codec) -Channels ([int]$TrackLayout.AudioTracks[$i].properties.audio_channels) -Lang $lang
            $isDefault = (($i + 1) -eq $audDefaultIndex)
            $isComm    = $false
            $src       = if ($useClpiAudio) { 'clpi' } else { 'sidecar-physical' }
        }
        elseif ($metaTrack) {
            $lang      = Get-MetaLanguage -Track $metaTrack
            $name      = Get-MetaTrackName -Track $metaTrack
            $isDefault = (($i + 1) -eq $audDefaultIndex)
            $isComm    = $false
            $src       = 'sidecar'
        }
        else {
            $lang = 'und'; $name = $null; $isDefault = (($i + 1) -eq $audDefaultIndex); $isComm = $false; $src = 'none'
        }
        if ($isComm -and [string]::IsNullOrWhiteSpace($name)) {
            $ln = Get-LanguageDisplayName -Code $lang
            $name = if ($ln) { "$ln Commentary" } else { 'Commentary' }
        }

        $propArgs += '--edit'
        $propArgs += "track:a$($i + 1)"
        $propArgs += '--set'
        $propArgs += "language=$lang"
        if (-not [string]::IsNullOrWhiteSpace($name)) {
            $propArgs += '--set'
            $propArgs += "name=$name"
        }
        $propArgs += '--set'
        $propArgs += "flag-default=$(if ($isDefault) { '1' } else { '0' })"
        $propArgs += '--set'
        $propArgs += "flag-commentary=$(if ($isComm) { '1' } else { '0' })"

        Write-Host ("    audio {0}: lang={1} ({2})  name={3}  default={4}  commentary={5}" -f
            ($i + 1), $lang, $src,
            $(if ([string]::IsNullOrWhiteSpace($name)) { [char]0x2014 } else { $name }),
            $(if ($isDefault) { 'yes' } else { 'no' }),
            $(if ($isComm) { 'yes' } else { 'no' }))
        $applied++
    }

    # Build effective subtitle tracks: language from .clpi when usable, else
    # from the sidecar. Forced comes from the sidecar positionally only when its
    # count matches; name follows the language so the two never contradict.
    $sidecarSubMatches = ($SubMeta.Count -eq $subOutCount)
    $effSub = New-Object System.Collections.Generic.List[object]
    $seenSubLang = @{}
    for ($i = 0; $i -lt $subOutCount; $i++) {
        # The .clpi authoritatively describes the subtitle streams in physical
        # PID order (== ffmpeg 0:s:0..N) whenever its count matches the encoded
        # output. There it is the single source of truth: an override built from
        # the mis-ordered sidecar grid can't be trusted positionally, so it is
        # skipped for subtitles. Language is exact; forced is inferred from a
        # repeated language (the second copy of a language is the forced/signs
        # track); English is forced default below.
        $o = $ovrSub[$i + 1]
        if ($useClpiSubs -or $useMetaSubs) {
            $lang   = if ($useClpiSubs) { [string]$clpiSubLangs[$i] } else { [string]$metaSubLangs[$i] }
            $forced = [bool]$seenSubLang[$lang]
            $seenSubLang[$lang] = $true
            $isComm = $false
            $isDef  = $false
            $name   = $null
        }
        elseif ($useSrcSubs) {
            # Authoritative per-stream tags from the source .mkv, in physical
            # 0:s order. forced comes from the source forced_track flag so the
            # encode map and this remux name forced subs identically.
            $lang   = [string]$srcSubLangs[$i]
            $forced = [bool]$srcSubForced[$i]
            $isComm = $false
            $isDef  = $false
            $name   = $null
        }
        elseif ($o) {
            $lang   = Resolve-LanguageCode -Code ([string]$o.lang)
            $forced = [bool]$o.forced
            $isComm = [bool]$o.commentary
            $isDef  = [bool]$o.default
            $name   = if ($o.PSObject.Properties['name'] -and $o.name) { [string]$o.name } else { $null }
        }
        else {
            if     ($i -lt $SubMeta.Count) { $lang = Get-MetaLanguage -Track $SubMeta[$i] }
            else                           { $lang = 'und' }
            $forced = [bool]($sidecarSubMatches -and $SubMeta[$i].Forced)
            $isComm = $false
            $isDef  = $false
            $name   = if ($i -lt $SubMeta.Count) { Get-MetaTrackName -Track $SubMeta[$i] }
                      else { $null }
        }

        if ([string]::IsNullOrWhiteSpace($name)) {
            $ln = Get-LanguageDisplayName -Code $lang
            if ($ln) {
                if     ($forced) { $name = "PGS $ln (forced only)" }
                elseif ($isComm) { $name = "$ln Commentary" }
                else             { $name = "PGS $ln" }
            }
        }

        $effSub.Add([pscustomobject]@{ Lang = $lang; Name = $name; Forced = $forced; Commentary = $isComm; Default = $isDef })
    }

    # Default subtitle: explicit overrides win; otherwise force English (first
    # non-forced English, else first English).
    $subDefaultIndex = 0
    if ($ovrSub.Count -gt 0 -and -not $useClpiSubs -and -not $useSrcSubs) {
        for ($di = 0; $di -lt $effSub.Count; $di++) {
            if ($effSub[$di].Default) { $subDefaultIndex = $di + 1; break }
        }
    }
    else {
        for ($di = 0; $di -lt $effSub.Count; $di++) {
            if ($effSub[$di].Lang -eq 'eng' -and -not $effSub[$di].Forced) { $subDefaultIndex = $di + 1; break }
        }
        if ($subDefaultIndex -eq 0) {
            for ($di = 0; $di -lt $effSub.Count; $di++) {
                if ($effSub[$di].Lang -eq 'eng') { $subDefaultIndex = $di + 1; break }
            }
        }
    }

    $langSrc = if ($useClpiSubs) { 'clpi' } elseif ($useMetaSubs) { 'sidecar-physical' } elseif ($useSrcSubs) { 'source-mkv' } elseif ($ovrSub.Count -gt 0) { 'override' } else { 'sidecar' }
    for ($i = 0; $i -lt $effSub.Count; $i++) {
        $t = $effSub[$i]
        $propArgs += '--edit'
        $propArgs += "track:s$($i + 1)"
        $propArgs += '--set'
        $propArgs += "language=$($t.Lang)"

        if (-not [string]::IsNullOrWhiteSpace($t.Name)) {
            $propArgs += '--set'
            $propArgs += "name=$($t.Name)"
        }

        $propArgs += '--set'
        $propArgs += "flag-default=$(if (($i + 1) -eq $subDefaultIndex) { '1' } else { '0' })"
        $propArgs += '--set'
        $propArgs += "flag-forced=$(if ($t.Forced) { '1' } else { '0' })"
        $propArgs += '--set'
        $propArgs += "flag-commentary=$(if ($t.Commentary) { '1' } else { '0' })"

        Write-Host ("    sub   {0}: lang={1} ({2})  name={3}  default={4}  forced={5}  commentary={6}" -f
            ($i + 1), $t.Lang, $langSrc,
            $(if ([string]::IsNullOrWhiteSpace($t.Name)) { [char]0x2014 } else { $t.Name }),
            $(if (($i + 1) -eq $subDefaultIndex) { 'yes' } else { 'no' }),
            $(if ($t.Forced) { 'yes' } else { 'no' }),
            $(if ($t.Commentary) { 'yes' } else { 'no' }))
        $applied++
    }

    if ($applied -eq 0) {
        throw "No tracks were tagged. Refusing to mark encode complete."
    }

    Write-Host "  $($global:UI_CYN)Writing track metadata via mkvpropedit...$($global:UI_R)"
    & $Script:MKVPropEditPath @propArgs 2>&1 | ForEach-Object { Write-Host "    $_" }

    if ($LASTEXITCODE -ne 0) {
        throw "mkvpropedit failed with exit code $LASTEXITCODE"
    }
}

function Get-StreamLanguagesFromSource {
    <#
    .SYNOPSIS
        Reads audio and subtitle language tags directly from the source .m2ts
        (or any file) via ffprobe, then applies them to an already-encoded MKV
        using mkvpropedit --edit track --set language.

    .NOTES
        This is the fallback path when no sidecar JSON is available.
        mkvpropedit writes directly into the track header — the same field that
        mkvmerge --identify shows as [language:xxx] — so the result is visible
        immediately without a remux.
    #>
    param(
        [Parameter(Mandatory)][string]$SourcePath,
        [Parameter(Mandatory)][string]$OutputMkvPath
    )

    Write-Host "  $($global:UI_CYN)Probing source stream languages via ffprobe...$($global:UI_R)"

    # Pull all stream language tags from source
    $probeArgs = @(
        '-v', 'error',
        '-probesize', $Script:M2tsProbeSize,
        '-analyzeduration', $Script:M2tsAnalyzeDur,
        '-show_entries', 'stream=index,codec_type:stream_tags=language',
        '-of', 'json',
        $SourcePath
    )

    $probeOut  = & $Script:FFprobePath @probeArgs 2>$null
    $probeJson = $null
    try { $probeJson = ($probeOut | Out-String) | ConvertFrom-Json } catch {}

    if (-not $probeJson -or -not $probeJson.streams) {
        Write-Host "  $($global:UI_YLW)ffprobe returned no stream data from source.$($global:UI_R)"
        return $false
    }

    # Separate into audio and subtitle streams (skip video)
    $audioStreams = @($probeJson.streams | Where-Object { $_.codec_type -eq 'audio' })
    $subStreams   = @($probeJson.streams | Where-Object { $_.codec_type -eq 'subtitle' })

    if ($audioStreams.Count -eq 0 -and $subStreams.Count -eq 0) {
        Write-Host "  $($global:UI_YLW)No audio or subtitle streams found in source.$($global:UI_R)"
        return $false
    }

    # Get the MKV output track layout so we can map source stream index → MKV track ID
    $layout = Get-OutputTrackLayout -Path $OutputMkvPath

    Write-Host "  $($global:UI_DIM)Source audio streams : $($audioStreams.Count)$($global:UI_R)"
    Write-Host "  $($global:UI_DIM)Source sub streams   : $($subStreams.Count)$($global:UI_R)"
    Write-Host "  $($global:UI_DIM)MKV audio tracks     : $($layout.AudioCount)$($global:UI_R)"
    Write-Host "  $($global:UI_DIM)MKV subtitle tracks  : $($layout.SubtitleCount)$($global:UI_R)"

    $audioToApply = [Math]::Min($audioStreams.Count, $layout.AudioTracks.Count)
    $subToApply   = [Math]::Min($subStreams.Count,   $layout.SubtitleTracks.Count)

    # Build mkvpropedit args — one --edit + --set per track
    # mkvpropedit track numbering is 1-based positional: track:a1, track:a2, track:s1, track:s2 ...
    $propArgs = @($OutputMkvPath)
    $applied  = 0

    for ($i = 0; $i -lt $audioToApply; $i++) {
        $rawLang = if ($audioStreams[$i].tags -and $audioStreams[$i].tags.language) {
            [string]$audioStreams[$i].tags.language
        } else { 'und' }
        $lang = Resolve-LanguageCode -Code $rawLang
        $trackRef = "track:a$($i + 1)"
        $propArgs += '--edit'
        $propArgs += $trackRef
        $propArgs += '--set'
        $propArgs += "language=$lang"
        Write-Host ("    audio {0}: {1} → {2}" -f ($i + 1), $rawLang, $lang)
        $applied++
    }

    for ($i = 0; $i -lt $subToApply; $i++) {
        $rawLang = if ($subStreams[$i].tags -and $subStreams[$i].tags.language) {
            [string]$subStreams[$i].tags.language
        } else { 'und' }
        $lang = Resolve-LanguageCode -Code $rawLang
        $trackRef = "track:s$($i + 1)"
        $propArgs += '--edit'
        $propArgs += $trackRef
        $propArgs += '--set'
        $propArgs += "language=$lang"
        Write-Host ("    sub   {0}: {1} → {2}" -f ($i + 1), $rawLang, $lang)
        $applied++
    }

    if ($applied -eq 0) {
        Write-Host "  $($global:UI_YLW)No language tags found in source streams.$($global:UI_R)"
        return $false
    }

    Write-Host "  $($global:UI_CYN)Writing language tags via mkvpropedit...$($global:UI_R)"
    & $Script:MKVPropEditPath @propArgs 2>&1 | ForEach-Object { Write-Host "    $_" }

    if ($LASTEXITCODE -ne 0) {
        Write-Host "  $($global:UI_RED)mkvpropedit failed with exit code $LASTEXITCODE$($global:UI_R)"
        return $false
    }

    Write-Host "  $($global:UI_GRN)Language tags written to track headers.$($global:UI_R)"
    return $true
}

function Repair-MKVLanguages {
    <#
    .SYNOPSIS
        Standalone menu action: fix language tags on an already-encoded MKV
        without re-encoding. Prompts for the finished MKV and its source .m2ts,
        then calls Apply-TrackMetadata. v3.0 requires a sidecar and refuses ffprobe guessing.
    #>

    Show-Header
    Write-Host "  $($global:UI_CYN)Repair Language Tags$($global:UI_R)"
    Write-UiBlankLine
    Write-Host "  This applies sidecar metadata from JSON or .tracks.txt when available."
    Write-Host "  No re-encode. Requires sidecar metadata; no ffprobe guessing."
    Write-UiBlankLine

    # Pick the MKV to fix
    $mkvFiles = @(Get-ChildItem -Path $Script:OutputRoot -Filter '*.mkv' -File | Sort-Object Name)
    if ($mkvFiles.Count -eq 0) {
        Write-Host "  $($global:UI_YLW)No MKV files found in $($Script:OutputRoot)$($global:UI_R)"
        Pause-Script; return
    }

    Write-Host "  $($global:UI_MAG)Available MKV files:$($global:UI_R)"
    for ($i = 0; $i -lt $mkvFiles.Count; $i++) {
        Write-Host ("    [{0}] {1}" -f ($i + 1), $mkvFiles[$i].Name)
    }
    Write-UiBlankLine

    $sel = Read-Host "  Select MKV number"
    $idx = 0
    if (-not [int]::TryParse($sel.Trim(), [ref]$idx) -or $idx -lt 1 -or $idx -gt $mkvFiles.Count) {
        Write-Host "  $($global:UI_YLW)Invalid selection.$($global:UI_R)"
        Pause-Script; return
    }
    $targetMkv = $mkvFiles[$idx - 1].FullName

    # Pick the source .m2ts. v2.6+ copies completed sources to m2ts/, older runs used done/.
    $m2tsFiles = @(
        if (Test-Path -LiteralPath $Script:M2tsRoot)  { Get-ChildItem -Path $Script:M2tsRoot  -Filter '*.m2ts' -File -Recurse -ErrorAction SilentlyContinue }
        if (Test-Path -LiteralPath $Script:DoneRoot)  { Get-ChildItem -Path $Script:DoneRoot  -Filter '*.m2ts' -File -Recurse -ErrorAction SilentlyContinue }
        if (Test-Path -LiteralPath $Script:InputRoot) { Get-ChildItem -Path $Script:InputRoot -Filter '*.m2ts' -File -Recurse -ErrorAction SilentlyContinue }
    ) | Sort-Object FullName -Unique

    $sourcePath = $null
    if ($m2tsFiles.Count -gt 0) {
        Write-UiBlankLine
        Write-Host "  $($global:UI_MAG)Available source files:$($global:UI_R)"
        for ($i = 0; $i -lt $m2tsFiles.Count; $i++) {
            Write-Host ("    [{0}] {1}" -f ($i + 1), $m2tsFiles[$i].Name)
        }
        Write-Host "    [0] Enter path manually"
        Write-UiBlankLine

        $sel2 = Read-Host "  Select source number"
        $idx2 = 0
        if ([int]::TryParse($sel2.Trim(), [ref]$idx2) -and $idx2 -ge 1 -and $idx2 -le $m2tsFiles.Count) {
            $sourcePath = $m2tsFiles[$idx2 - 1].FullName
        }
    }

    if (-not $sourcePath) {
        $sourcePath = (Read-Host "  Enter full path to source .m2ts").Trim('"').Trim()
    }

    if (-not (Test-Path -LiteralPath $sourcePath)) {
        Write-Host "  $($global:UI_RED)Source file not found: $sourcePath$($global:UI_R)"
        Pause-Script; return
    }

    Write-UiBlankLine
    Write-Host "  $($global:UI_DIM)MKV   $($global:UI_R)  $targetMkv"
    Write-Host "  $($global:UI_DIM)Source$($global:UI_R)  $sourcePath"
    Write-UiBlankLine

    $sourceInfo = Get-Item -LiteralPath $sourcePath
    $movieName = [System.IO.Path]::GetFileNameWithoutExtension($targetMkv)

    try {
        Apply-TrackMetadata -OutputFile $targetMkv -SourceFile $sourceInfo -MovieName $movieName | Out-Null
    }
    catch {
        Write-UiBlankLine
        Write-CoreError $_.Exception.Message
    }

    Pause-Script
}

function Select-TrackMetadata {
    <#
    .SYNOPSIS
        Deterministic v3.0 metadata selector.

    .NOTES
        BREncoder must not guess subtitle/audio languages. If no sidecar exists,
        encoding/repair stops instead of falling back to ffprobe tags.
    #>
    param(
        [Parameter(Mandatory)][System.IO.FileInfo]$SourceFile,
        [Parameter(Mandatory)][string]$MovieName
    )

    $autoMatch = Load-TrackMetadata -SourceFile $SourceFile -MovieName $MovieName

    if ($autoMatch) {
        $jsonName = [System.IO.Path]::GetFileName($autoMatch.Path)
        Write-UiBlankLine
        Write-Host "  $($global:UI_CYN)Metadata found:$($global:UI_R)"
        Write-Host "  $($global:UI_DIM)File $($global:UI_R)  $jsonName"
        Write-Host "  $($global:UI_DIM)Path $($global:UI_R)  $($autoMatch.Path)"

        $title = Get-TrackMetaTitle -Meta $autoMatch.Data
        if ($title) {
            $audioList = @(Resolve-TrackList -Title $title -Kind audio)
            $subList   = @(Resolve-TrackList -Title $title -Kind subtitle)
            Write-Host "  $($global:UI_DIM)Audio$($global:UI_R)  $($audioList.Count) track(s)"
            Write-Host "  $($global:UI_DIM)Subs $($global:UI_R)  $($subList.Count) track(s)"
            if ($audioList.Count -gt 0) {
                $langs = ($audioList | ForEach-Object { Get-MetaLanguage -Track $_ }) -join ', '
                Write-Host "  $($global:UI_DIM)A Langs$($global:UI_R) $langs"
            }
            if ($subList.Count -gt 0) {
                $langs = ($subList | ForEach-Object { Get-MetaLanguage -Track $_ }) -join ', '
                Write-Host "  $($global:UI_DIM)S Langs$($global:UI_R) $langs"
            }
            $phys = Get-MetaPhysicalStreamLanguages -Meta $autoMatch.Data
            if ($phys.Audio.Count -gt 0 -or $phys.Subtitle.Count -gt 0) {
                Write-Host "  $($global:UI_DIM)Physical$($global:UI_R) $($phys.Audio.Count) audio / $($phys.Subtitle.Count) subtitle language(s) saved"
            }
        }

        return $autoMatch
    }

    Write-UiBlankLine
    Write-CoreError "No metadata sidecar found for '$MovieName'."
    Write-Host "  BREncoder v3.0 refuses to guess audio/subtitle languages."
    Write-UiBlankLine
    Write-Host "  $($global:UI_CYN)Searched:$($global:UI_R)"
    foreach ($root in (Get-TrackMetaSearchRoots -SourceFile $SourceFile -MovieName $MovieName)) {
        Write-Host "    $root"
    }
    Write-UiBlankLine
    Write-Host "  Expected one of:"
    Write-Host "    $MovieName.json"
    Write-Host "    $MovieName.tracks.txt"
    Write-UiBlankLine
    Write-Host "  Run bluray-backup.ps1 or bluray-trackdump.ps1 to generate metadata first."
    throw "No required BRTrackMeta sidecar found. Encoding cancelled."
}

function New-FFmpegMapArgsFromTrackMetadata {
    <#
    .SYNOPSIS
        Builds explicit ffmpeg -map and metadata arguments from required sidecar
        metadata plus the actual physical source stream count.

    .NOTES
        Stable rule: ffmpeg stream mapping must be driven by the source stream
        count, not by MakeMKV sidecar count. The sidecar remains required because
        it identifies the disc/title and supplies names/flags, but raw .m2ts
        inputs can have physical stream order/count differences. For .m2ts we
        use ffprobe counts first, then CLPI/sidecar physical counts, then sidecar
        counts as the last fallback. For .mkv sources, mkvmerge source tags stay
        authoritative because they are already remuxed in 0:a/0:s order.
    #>
    param(
        [object]$MetaInfo,
        [string]$SourcePath
    )

    if (-not $MetaInfo -or -not $MetaInfo.Data) {
        throw "No sidecar metadata provided. Encoding cancelled."
    }

    $title = Get-TrackMetaTitle -Meta $MetaInfo.Data
    if (-not $title) {
        throw "Track metadata does not contain MainTitle/Title data."
    }

    $audioMeta = @(Resolve-TrackList -Title $title -Kind audio)
    $subMeta   = @(Resolve-TrackList -Title $title -Kind subtitle)

    if ($audioMeta.Count -eq 0 -and $subMeta.Count -eq 0) {
        throw "Track metadata contains no audio or subtitle tracks."
    }

    $ffMapArgs = @('-map', '0:v:0')
    $sourceLabel = 'sidecar'

    # MakeMKV/remux MKV source: use the MKV's own physical track layout and tags.
    $srcAudLangs = @(); $srcSubLangs = @()
    $srcAudNames = @(); $srcSubNames = @(); $srcSubForced = @()
    $useSrcTags = $false
    if ($SourcePath -and ($SourcePath -match '\.mkv$') -and (Test-Path -LiteralPath $SourcePath)) {
        try {
            $sj = & $Script:MKVMergePath -J $SourcePath 2>$null | Out-String | ConvertFrom-Json
            $sa = @(@($sj.tracks) | Where-Object { $_.type -eq 'audio' })
            $ss = @(@($sj.tracks) | Where-Object { $_.type -eq 'subtitles' })
            $srcAudLangs  = @($sa | ForEach-Object { if ($_.properties.language) { Resolve-LanguageCode -Code ([string]$_.properties.language) } else { 'und' } })
            $srcSubLangs  = @($ss | ForEach-Object { if ($_.properties.language) { Resolve-LanguageCode -Code ([string]$_.properties.language) } else { 'und' } })
            $srcAudNames  = @($sa | ForEach-Object { if ($_.properties.track_name) { [string]$_.properties.track_name } else { '' } })
            $srcSubNames  = @($ss | ForEach-Object { if ($_.properties.track_name) { [string]$_.properties.track_name } else { '' } })
            $srcSubForced = @($ss | ForEach-Object { [bool]$_.properties.forced_track })
            $useSrcTags = ($srcAudLangs.Count -gt 0 -or $srcSubLangs.Count -gt 0)
        } catch { $useSrcTags = $false }
    }

    if ($useSrcTags) {
        $audCount = $srcAudLangs.Count
        $subCount = $srcSubLangs.Count
        $sourceLabel = 'source-mkv'
        Write-Host "  $($global:UI_CYN)Source .mkv tags authoritative: $audCount audio / $subCount subtitle$($global:UI_R)"
    }
    else {
        # Raw .m2ts / BDMV source: count the physical streams. ffprobe count is
        # the safest map count because ffmpeg will map the same indexes; CLPI and
        # sidecar physical lists are used for languages when their counts match.
        $srcMap = if ($SourcePath -and (Test-Path -LiteralPath $SourcePath)) { Get-SourceStreamLanguageMap -SourcePath $SourcePath } else { $null }
        $probeAudLangs = if ($srcMap) { @($srcMap.Audio | ForEach-Object { Resolve-LanguageCode -Code ([string]$_) }) } else { @() }
        $probeSubLangs = if ($srcMap) { @($srcMap.Sub   | ForEach-Object { Resolve-LanguageCode -Code ([string]$_) }) } else { @() }

        $clpi = if ($SourcePath -and ($SourcePath -match '\.m2ts$') -and (Test-Path -LiteralPath $SourcePath)) { Read-ClpiStreamLanguages -M2tsPath $SourcePath } else { $null }
        $clpiAudLangs = if ($clpi) { @($clpi.Audio) } else { @() }
        $clpiSubLangs = if ($clpi) { @($clpi.Subtitle) } else { @() }

        $metaPhysical = Get-MetaPhysicalStreamLanguages -Meta $MetaInfo.Data
        $metaAudLangs = @($metaPhysical.Audio)
        $metaSubLangs = @($metaPhysical.Subtitle)

        $audPhysicalCount = (@($probeAudLangs.Count, $clpiAudLangs.Count, $metaAudLangs.Count) | Measure-Object -Maximum).Maximum
        $subPhysicalCount = (@($probeSubLangs.Count, $clpiSubLangs.Count, $metaSubLangs.Count) | Measure-Object -Maximum).Maximum
        $audCount = if ($audPhysicalCount -gt 0) { [int]$audPhysicalCount } else { $audioMeta.Count }
        $subCount = if ($subPhysicalCount -gt 0) { [int]$subPhysicalCount } else { $subMeta.Count }

        if ($audCount -eq 0) { throw "No audio streams were found in source or metadata. Encoding cancelled." }

        $useClpiAudio = ($clpiAudLangs.Count -eq $audCount -and $audCount -gt 0)
        $useMetaAudio = (-not $useClpiAudio -and $metaAudLangs.Count -eq $audCount -and $audCount -gt 0)
        $useProbeAudio = (-not $useClpiAudio -and -not $useMetaAudio -and $probeAudLangs.Count -eq $audCount -and @($probeAudLangs | Where-Object { $_ -ne 'und' }).Count -gt 0)

        $useClpiSubs = ($clpiSubLangs.Count -eq $subCount -and $subCount -gt 0)
        $useMetaSubs = (-not $useClpiSubs -and $metaSubLangs.Count -eq $subCount -and $subCount -gt 0)
        $useProbeSubs = (-not $useClpiSubs -and -not $useMetaSubs -and $probeSubLangs.Count -eq $subCount -and @($probeSubLangs | Where-Object { $_ -ne 'und' }).Count -gt 0)

        $sourceLabel = if ($useClpiAudio -or $useClpiSubs) { 'source-clpi' } elseif ($useMetaAudio -or $useMetaSubs) { 'sidecar-physical' } elseif ($useProbeAudio -or $useProbeSubs) { 'source-probe' } else { 'sidecar' }

        if ($audCount -ne $audioMeta.Count -or $subCount -ne $subMeta.Count) {
            Write-Host "  $($global:UI_YLW)Physical stream count differs from sidecar: map=$audCount audio/$subCount subs, sidecar=$($audioMeta.Count) audio/$($subMeta.Count) subs$($global:UI_R)"
        }

        $physAudioAt = {
            param([int]$ix)
            if     ($useClpiAudio) { return [string]$clpiAudLangs[$ix] }
            elseif ($useMetaAudio) { return [string]$metaAudLangs[$ix] }
            elseif ($useProbeAudio){ return [string]$probeAudLangs[$ix] }
            elseif ($ix -lt $audioMeta.Count) { return (Get-MetaLanguage -Track $audioMeta[$ix]) }
            else { return 'und' }
        }
        $physSubAt = {
            param([int]$ix)
            if     ($useClpiSubs)  { return [string]$clpiSubLangs[$ix] }
            elseif ($useMetaSubs)  { return [string]$metaSubLangs[$ix] }
            elseif ($useProbeSubs) { return [string]$probeSubLangs[$ix] }
            elseif ($ix -lt $subMeta.Count) { return (Get-MetaLanguage -Track $subMeta[$ix]) }
            else { return 'und' }
        }

        $rawSeenSubLang = @{}
    }

    for ($i = 0; $i -lt $audCount; $i++) {
        $ffMapArgs += '-map'
        $ffMapArgs += ("0:a:{0}?" -f $i)
    }

    for ($i = 0; $i -lt $subCount; $i++) {
        $ffMapArgs += '-map'
        $ffMapArgs += ("0:s:{0}?" -f $i)
    }

    for ($i = 0; $i -lt $audCount; $i++) {
        if ($useSrcTags) {
            $lang = $srcAudLangs[$i]
            $name = $srcAudNames[$i]
        } else {
            $lang = & $physAudioAt $i
            $name = if ($i -lt $audioMeta.Count) { Get-MetaTrackName -Track $audioMeta[$i] } else { $null }
        }

        $ffMapArgs += ("-metadata:s:a:{0}" -f $i)
        $ffMapArgs += "language=$lang"

        if (-not [string]::IsNullOrWhiteSpace($name)) {
            $ffMapArgs += ("-metadata:s:a:{0}" -f $i)
            $ffMapArgs += "title=$name"
        }
    }

    for ($i = 0; $i -lt $subCount; $i++) {
        if ($useSrcTags) {
            $lang     = $srcSubLangs[$i]
            $name     = $srcSubNames[$i]
            $isForced = $srcSubForced[$i]
            $isDef    = $false
            if ([string]::IsNullOrWhiteSpace($name)) {
                $ln = Get-LanguageDisplayName -Code $lang
                if ($ln) { $name = if ($isForced) { "PGS $ln (forced only)" } else { "PGS $ln" } }
            }
        } else {
            $lang = & $physSubAt $i
            $sidecarPositionSafe = ($subMeta.Count -eq $subCount -and -not ($sourceLabel -in @('source-clpi','sidecar-physical','source-probe')))
            if ($sidecarPositionSafe -and $i -lt $subMeta.Count) {
                $name     = Get-MetaTrackName -Track $subMeta[$i]
                $isForced = [bool]$subMeta[$i].Forced
                $isDef    = [bool]$subMeta[$i].Default
            }
            else {
                $isForced = [bool]$rawSeenSubLang[$lang]
                $rawSeenSubLang[$lang] = $true
                $isDef = $false
                $ln = Get-LanguageDisplayName -Code $lang
                $name = if ($ln) { if ($isForced) { "PGS $ln (forced only)" } else { "PGS $ln" } } else { $null }
            }
        }

        $ffMapArgs += ("-metadata:s:s:{0}" -f $i)
        $ffMapArgs += "language=$lang"

        if (-not [string]::IsNullOrWhiteSpace($name)) {
            $ffMapArgs += ("-metadata:s:s:{0}" -f $i)
            $ffMapArgs += "title=$name"
        }

        if ($isForced) {
            $ffMapArgs += ("-disposition:s:{0}" -f $i)
            $ffMapArgs += 'forced'
        }
        elseif ($isDef) {
            $ffMapArgs += ("-disposition:s:{0}" -f $i)
            $ffMapArgs += 'default'
        }
    }

    return [pscustomobject]@{
        Args       = $ffMapArgs
        AudioCount = $audCount
        SubCount   = $subCount
        Source     = $sourceLabel
    }
}


function Apply-TrackMetadata {
    param(
        [Parameter(Mandatory)][string]$OutputFile,
        [Parameter(Mandatory)][System.IO.FileInfo]$SourceFile,
        [Parameter(Mandatory)][string]$MovieName,
        [object]$PreselectedMetaInfo = $null,
        [string]$OverridesFile
    )

    $metaInfo = if ($PreselectedMetaInfo) {
        $PreselectedMetaInfo
    } else {
        Select-TrackMetadata -SourceFile $SourceFile -MovieName $MovieName
    }
    if (-not $metaInfo) {
        Write-UiBlankLine
        Write-Host "  $($global:UI_YLW)No sidecar metadata found — falling back to ffprobe source language tags.$($global:UI_R)"
        Get-StreamLanguagesFromSource -SourcePath $SourceFile.FullName -OutputMkvPath $OutputFile
        Write-UiBlankLine
        Show-FinalMetadataVerification -OutputFile $OutputFile
        return $null
    }

    $trackLayout = Get-OutputTrackLayout -Path $OutputFile
    $meta = $metaInfo.Data

    $title = Get-TrackMetaTitle -Meta $meta
    if (-not $title) {
        Write-UiBlankLine
        Write-CoreError "Track metadata JSON does not contain MainTitle/Title data."
        return $metaInfo.Path
    }

    $warnings = Test-BRTrackMetadata -Meta $meta -Title $title -TrackLayout $trackLayout
    Show-MetadataWarnings -Warnings $warnings

    $audioMeta = @(Resolve-TrackList -Title $title -Kind audio)
    $subMeta   = @(Resolve-TrackList -Title $title -Kind subtitle)

    # Debug mode: dump the first track shape from each list so you can see exactly
    # which property names your sidecar JSON uses. Enable via $Script:DebugMeta = $true.
    if ($Script:DebugMeta) {
        Write-UiBlankLine
        Write-Host "  $($global:UI_YLW)[DEBUG] Sidecar JSON track shapes:$($global:UI_R)"
        if ($audioMeta.Count -gt 0) {
            Write-Host "  $($global:UI_DIM)Audio[0]:$($global:UI_R)"
            $audioMeta[0] | ConvertTo-Json -Depth 2 | ForEach-Object { Write-Host "    $_" }
        }
        if ($subMeta.Count -gt 0) {
            Write-Host "  $($global:UI_DIM)Sub[0]:$($global:UI_R)"
            $subMeta[0] | ConvertTo-Json -Depth 2 | ForEach-Object { Write-Host "    $_" }
        }
        Write-UiBlankLine
    }

    Write-UiBlankLine
    Write-Host "  $($global:UI_CYN)Applying track metadata...$($global:UI_R)"
    Write-Host "  $($global:UI_DIM)Meta  $($global:UI_R)  $($metaInfo.Path)"
    Write-Host "  $($global:UI_DIM)Audio $($global:UI_R)  output=$($trackLayout.AudioCount) / meta=$($audioMeta.Count)"
    Write-Host "  $($global:UI_DIM)Subs  $($global:UI_R)  output=$($trackLayout.SubtitleCount) / meta=$($subMeta.Count)"
    Write-UiBlankLine

    # Use mkvpropedit with positional track refs (track:a1, track:s1 ...).
    # mkvmerge -J is still used to get the real audio/subtitle counts and ordering,
    # but the actual tag writes go through mkvpropedit --edit/--set which edits
    # headers in-place and has stable flag names across all MKVToolNix versions.
    Invoke-MKVLanguageRemux -OutputFile $OutputFile -TrackLayout $trackLayout -AudioMeta $audioMeta -SubMeta $subMeta -SourcePath $SourceFile.FullName -OverridesFile $OverridesFile -Meta $meta

    Write-UiBlankLine
    Write-Host "  $($global:UI_GRN)Track metadata applied.$($global:UI_R)"
    Show-FinalMetadataVerification -OutputFile $OutputFile
    return $metaInfo.Path
}

function Create-SampleFromFinishedMkv {
    param(
        [Parameter(Mandatory)][string]$FinishedMkvPath,
        [Parameter(Mandatory)][string]$MovieName
    )

    $duration = Get-VideoDuration -Path $FinishedMkvPath
    $sampleStart = Get-SafeSampleStart -DurationSeconds $duration
    $sampleOutput = Get-SampleOutputPath -MovieName $MovieName

    Write-UiBlankLine
    Write-Host "  $($global:UI_CYN)Creating sample from finished MKV...$($global:UI_R)"
    Write-Host "  $($global:UI_DIM)Input $($global:UI_R)  $FinishedMkvPath"
    Write-Host "  $($global:UI_DIM)Output$($global:UI_R)  $sampleOutput"
    Write-Host "  $($global:UI_DIM)Start $($global:UI_R)  $sampleStart"
    Write-Host "  $($global:UI_DIM)Length$($global:UI_R)  $($Script:DefaultLength) seconds"
    Write-Host "  $($global:UI_DIM)Mode  $($global:UI_R)  stream copy (video + audio; subtitles skipped)"
    Write-UiBlankLine

    # A sample is for eyeballing video/audio quality; subtitles are skipped.
    # PGS subs especially can't be stream-copied from a mid-file seek point
    # (ffmpeg: "unspecified size"), so map video + audio only and drop subs.
    $args = @(
        '-hide_banner',
        '-y',
        '-probesize', $Script:M2tsProbeSize,
        '-analyzeduration', $Script:M2tsAnalyzeDur,
        '-ss', $sampleStart,
        '-i', $FinishedMkvPath,
        '-t', "$($Script:DefaultLength)",
        '-map', '0:v?',
        '-map', '0:a?',
        '-sn',
        '-c', 'copy',
        $sampleOutput
    )

    # ffmpeg warnings go to stderr; in a runspace under the script-wide EAP=Stop
    # the first one becomes a terminating error before we can read the exit code.
    # Relax EAP for the call and judge success by exit code, like the encode does.
    $smpEAP = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        & $Script:FFmpegPath @args
    }
    finally {
        $ErrorActionPreference = $smpEAP
    }

    if ($LASTEXITCODE -ne 0) {
        throw "Sample creation failed. ffmpeg exit code $LASTEXITCODE"
    }

    $sampleInfo = Wait-ForOutputFile -Path $sampleOutput

    Write-UiBlankLine
    Write-Host "  $($global:UI_GRN)Sample complete.$($global:UI_R)"
    Write-Host "  $($global:UI_DIM)Saved $($global:UI_R)  $($sampleInfo.FullName)"
    Write-Host "  $($global:UI_DIM)Size  $($global:UI_R)  $([math]::Round(($sampleInfo.Length / 1MB), 2)) MB"
}

function Encode-File {
    param(
        [Parameter(Mandatory)][System.IO.FileInfo]$SourceFile,
        [Parameter(Mandatory)][string]$MovieName,
        # Headless/GUI hooks: AutoAccept suppresses any interactive prompts in
        # the encode chain; ProgressFile makes ffmpeg write -progress key=value
        # blocks to that path for a front end to tail.
        [switch]$AutoAccept,
        [string]$ProgressFile,
        [string]$OverridesFile
    )

    if ($AutoAccept) { $Script:NonInteractive = $true }

    $outputFile    = Get-OutputPath -MovieName $MovieName
    $duration      = Get-VideoDuration -Path $SourceFile.FullName
    $trackMetaPath = ""

    # ── Probe source for HDR/SDR profile ──────────────────────
    Write-UiBlankLine
    Write-Host "  $($global:UI_CYN)Probing source video profile...$($global:UI_R)"
    $vp = Get-SourceVideoProfile -Path $SourceFile.FullName

    $profileColor = if ($vp.IsHDR) { $global:UI_YLW } else { $global:UI_GRY }
    Write-Host "  $($global:UI_DIM)Profile$($global:UI_R)  $($profileColor)$($vp.Profile)$($global:UI_R)"
    Write-Host "  $($global:UI_DIM)Color  $($global:UI_R)  primaries=$($vp.ColorPrimaries)  trc=$($vp.ColorTrc)  space=$($vp.Colorspace)"
    if ($vp.MasterDisplay) {
        Write-Host "  $($global:UI_DIM)Master $($global:UI_R)  $($vp.MasterDisplay)"
    }
    if ($vp.MaxCLL) {
        Write-Host "  $($global:UI_DIM)MaxCLL $($global:UI_R)  $($vp.MaxCLL)"
    }

    Write-UiBlankLine
    Write-Host "  $($global:UI_GRN)Encoding file...$($global:UI_R)"
    Write-Host "  $($global:UI_DIM)Input  $($global:UI_R)  $($SourceFile.FullName)"
    Write-Host "  $($global:UI_DIM)Output $($global:UI_R)  $outputFile"
    Write-Host "  $($global:UI_DIM)Codec  $($global:UI_R)  libx265"
    Write-Host "  $($global:UI_DIM)CRF    $($global:UI_R)  $($vp.CRF)  ($($vp.Profile))"
    Write-Host "  $($global:UI_DIM)Preset $($global:UI_R)  $($Script:DefaultPreset)"
    Write-Host "  $($global:UI_DIM)PixFmt $($global:UI_R)  $($vp.PixFmt)"
    Write-Host "  $($global:UI_DIM)Psy    $($global:UI_R)  $($Script:X265PsyParams)"
    Write-Host "  $($global:UI_DIM)Audio  $($global:UI_R)  $($Script:DefaultAudio)"
    Write-UiBlankLine

    # ── Build x265-params string ───────────────────────────────
    $x265Params = $Script:X265PsyParams

    if ($vp.IsHDR) {
        # Embed HDR10 color volume metadata so the display knows what to do
        $x265Params += ":colorprim=$($vp.ColorPrimaries)"
        $x265Params += ":transfer=$($vp.ColorTrc)"
        $x265Params += ":colormatrix=$($vp.Colorspace)"
        $x265Params += ":hdr10=1"
        $x265Params += ":hdr10-opt=1"
        if ($vp.MasterDisplay) {
            $x265Params += ":master-display=$($vp.MasterDisplay)"
        }
        if ($vp.MaxCLL) {
            $x265Params += ":max-cll=$($vp.MaxCLL)"
        }
    }

    # ── Preselect sidecar metadata before ffmpeg builds the output track order ──
    $preselectedMeta = Select-TrackMetadata -SourceFile $SourceFile -MovieName $MovieName
    $metadataMap = New-FFmpegMapArgsFromTrackMetadata -MetaInfo $preselectedMeta -SourcePath $SourceFile.FullName

    if ($metadataMap) {
        Write-UiBlankLine
        Write-Host "  $($global:UI_CYN)Using $($metadataMap.Source)-driven stream map:$($global:UI_R)"
        Write-Host "  $($global:UI_DIM)Audio$($global:UI_R)  $($metadataMap.AudioCount) track(s)"
        Write-Host "  $($global:UI_DIM)Subs $($global:UI_R)  $($metadataMap.SubCount) track(s)"
    }
    else {
        throw "No usable sidecar stream map. Encoding cancelled."
    }

    # ── Build ffmpeg args ──────────────────────────────────────
    $ffArgs = @('-hide_banner', '-y')
    if ($ProgressFile) {
        # Machine-readable progress for a front end (frame/out_time/speed...).
        # -nostats stops ffmpeg also streaming a per-second stats line to stderr
        # (the front end reads the progress file instead), which would otherwise
        # flood the GUI log and produce NativeCommandError noise.
        $ffArgs += @('-progress', $ProgressFile, '-stats_period', '1', '-nostats')
    }
    $ffArgs += @(
        '-probesize', $Script:M2tsProbeSize,
        '-analyzeduration', $Script:M2tsAnalyzeDur,
        '-i', $SourceFile.FullName
    )

    if ($metadataMap) {
        $ffArgs += @($metadataMap.Args)
    }
    else {
        throw "No sidecar map available. Refusing automatic ffmpeg mapping."
    }

    $ffArgs += @(
        '-c:v', 'libx265',
        '-preset', $Script:DefaultPreset,
        '-crf', "$($vp.CRF)",
        '-pix_fmt', $vp.PixFmt,
        '-x265-params', $x265Params,
        # Pass color metadata at the container level too so players see it
        '-color_primaries', $vp.ColorPrimaries,
        '-color_trc', $vp.ColorTrc,
        '-colorspace', $vp.Colorspace,
        '-c:a', $Script:DefaultAudio,
        '-c:s', 'copy',
        $outputFile
    )

    # ffmpeg writes progress/info to stderr. In a runspace (e.g. the GUI) those
    # surface as NativeCommandError records, and the script-wide EAP=Stop would
    # turn the very first one into a terminating error before we can read the
    # real exit code. Relax EAP for the encode itself and judge by exit code.
    $ffEAP = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        & $Script:FFmpegPath @ffArgs
    }
    finally {
        $ErrorActionPreference = $ffEAP
    }

    if ($LASTEXITCODE -ne 0) {
        throw "ffmpeg failed with exit code $LASTEXITCODE"
    }

    $encodedInfo = Wait-ForOutputFile -Path $outputFile

    $encodedLayout = Get-OutputTrackLayout -Path $encodedInfo.FullName
    if ($encodedLayout.AudioCount -ne $metadataMap.AudioCount -or $encodedLayout.SubtitleCount -ne $metadataMap.SubCount) {
        throw ("Stream map validation failed: expected {0} audio / {1} subtitle, encoded {2} audio / {3} subtitle. Refusing to mark complete." -f `
            $metadataMap.AudioCount, $metadataMap.SubCount, $encodedLayout.AudioCount, $encodedLayout.SubtitleCount)
    }

    $appliedMeta = Apply-TrackMetadata -OutputFile $encodedInfo.FullName -SourceFile $SourceFile -MovieName $MovieName -PreselectedMetaInfo $preselectedMeta -OverridesFile $OverridesFile
    if ($appliedMeta) {
        # Guard against stray pipeline output: keep only the last value and force to string.
        if ($appliedMeta -is [array]) { $appliedMeta = $appliedMeta[-1] }
        $trackMetaPath = [string]$appliedMeta
    }

    Create-SampleFromFinishedMkv -FinishedMkvPath $encodedInfo.FullName -MovieName $MovieName

    $copyPath = Copy-SourceToM2ts -SourceFile $SourceFile
    Write-MetaFile -MovieName $MovieName -SourceFile $SourceFile -OutputFile $encodedInfo.FullName `
                   -DurationSeconds $duration -TrackMetaPath $trackMetaPath -VideoProfile $vp

    Write-UiBlankLine
    Write-Host "  $($global:UI_GRN)Encode complete.$($global:UI_R)"
    Write-Host "  $($global:UI_DIM)Profile$($global:UI_R)  $($vp.Profile)  •  CRF $($vp.CRF)  •  $($Script:DefaultPreset)"
    Write-Host "  $($global:UI_DIM)Saved  $($global:UI_R)  $($encodedInfo.FullName)"
    Write-Host "  $($global:UI_DIM)Copied $($global:UI_R)  $copyPath"
}

function Encode-SingleFile {
    $files = Get-M2tsFiles

    Write-UiBlankLine

    if (-not $files -or $files.Count -eq 0) {
        Write-CoreError "No .m2ts files found in $($Script:InputRoot)"
        Pause-Script
        return
    }

    Write-Host "  $($global:UI_MAG)Source files:$($global:UI_R)"
    for ($i = 0; $i -lt $files.Count; $i++) {
        $sizeGb = [math]::Round(($files[$i].Length / 1GB), 2)
        Write-Host ("  {0,2}) {1}  [{2} GB]" -f ($i + 1), $files[$i].Name, $sizeGb)
    }

    Write-UiBlankLine
    $pick = Read-Host "Choose file number [1]"

    if ([string]::IsNullOrWhiteSpace($pick)) {
        $pick = '1'
    }

    if (-not ($pick -match '^\d+$')) {
        Write-CoreError "Invalid selection."
        Pause-Script
        return
    }

    $index = [int]$pick - 1
    if ($index -lt 0 -or $index -ge $files.Count) {
        Write-CoreError "Selection out of range."
        Pause-Script
        return
    }

    $file = $files[$index]
    $defaultName = Get-DefaultMovieName -File $file
    $movieName = Read-MovieNameWithYear -DefaultName $defaultName

    try {
        Encode-File -SourceFile $file -MovieName $movieName
    }
    catch {
        Write-UiBlankLine
        Write-CoreError $_.Exception.Message
    }

    Pause-Script
}

function Encode-AllFiles {
    $files = Get-M2tsFiles

    Write-UiBlankLine

    if (-not $files -or $files.Count -eq 0) {
        Write-CoreError "No .m2ts files found in $($Script:InputRoot)"
        Pause-Script
        return
    }

    Write-Host "  $($global:UI_YLW)About to encode $($files.Count) file(s).$($global:UI_R)"
    $confirm = Read-Host "Continue? (Y/N)"
    if ($confirm -notmatch '^(Y|y)$') {
        Pause-Script
        return
    }

    foreach ($file in $files) {
        $defaultName = Get-DefaultMovieName -File $file
        $movieName = $defaultName

        Write-UiBlankLine
        Write-Host "  $($global:UI_CYN)Now encoding:$($global:UI_R) $($file.Name)"

        try {
            Encode-File -SourceFile $file -MovieName $movieName
        }
        catch {
            Write-UiBlankLine
            Write-CoreError "Failed on $($file.Name): $($_.Exception.Message)"
        }
    }

    Pause-Script
}

function Show-Config {
    Write-UiBlankLine
    Write-UiRow "RootPath"     $Script:RootPath $global:UI_GRY
    Write-UiRow "InputRoot"    $Script:InputRoot $global:UI_GRY
    Write-UiRow "OutputRoot"   $Script:OutputRoot $global:UI_GRY
    Write-UiRow "DoneRoot"     $Script:DoneRoot $global:UI_GRY
    Write-UiRow "SampleRoot"   $Script:SampleRoot $global:UI_GRY
    Write-UiRow "SubtitleRoot" $Script:SubtitleRoot $global:UI_GRY
    Write-UiRow "MetaRoot"     $Script:MetaRoot $global:UI_GRY
    Write-UiRow "TxtRoot"      $Script:TxtRoot $global:UI_GRY
    Write-UiRow "CRF (HDR)"    "$($Script:CRF_HDR)" $global:UI_GRY
    Write-UiRow "CRF (SDR)"    "$($Script:CRF_SDR)" $global:UI_GRY
    Write-UiRow "Preset"       $Script:DefaultPreset $global:UI_GRY
    Write-UiRow "PixFmt"       "yuv420p10le (10-bit)" $global:UI_GRY
    Write-UiRow "PsyParams"    $Script:X265PsyParams $global:UI_GRY
    Write-UiRow "Audio"        "$($Script:DefaultAudio) (lossless passthrough)" $global:UI_GRY
    Write-UiRow "SampleStart"  $Script:DefaultStart $global:UI_GRY
    Write-UiRow "SampleLength" "$($Script:DefaultLength) sec" $global:UI_GRY
    Write-UiRow "FFmpeg"       $Script:FFmpegPath $global:UI_GRY
    Write-UiRow "FFprobe"      $Script:FFprobePath $global:UI_GRY
    Write-UiRow "MKVPropEdit"  $Script:MKVPropEditPath $global:UI_GRY
    Write-UiRow "MKVMerge"     $Script:MKVMergePath $global:UI_GRY
    Pause-Script
}

try {
    Ensure-Dependencies
    Ensure-Directories
}
catch {
    Write-UiBlankLine
    Write-CoreError $_.Exception.Message
    return
}

# Only launch the interactive menu when run directly. When the GUI (or any
# other script) dot-sources this file it sets $env:BRENCODER_NOMENU so the
# functions load without entering the menu loop.
if (-not $env:BRENCODER_NOMENU) {
while ($true) {
    Show-Header
    Show-Menu
    $choice = (Read-Host "Choose").Trim().ToUpper()

    switch ($choice) {
        '1' { Encode-AllFiles }
        '2' { Encode-SingleFile }
        '3' { Show-SourceFiles }
        '4' { Show-Config }
        '5' { Repair-MKVLanguages }
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
}
