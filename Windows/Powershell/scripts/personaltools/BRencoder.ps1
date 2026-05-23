#--------------------------------------------
# file:     brEncoder.ps1
# author:   Mike Redd
# version:  2.2
# created:  2026-02-11
# updated:  2026-05-23
# desc:     Encode Blu-ray .m2ts files
#           to H.265/HEVC on Windows
#           using ffmpeg, then create a
#           sample clip from the finished MKV
#           and apply track metadata from
#           sidecar JSON when available
#           validates metadata, verifies final MKV
#           language/default/forced tags
#           remuxes final MKV with real track IDs
# changes:  v2.2 - added -probesize 100M / -analyzeduration 300M to all ffmpeg
#                  and ffprobe calls that open .m2ts files; fixes "unspecified
#                  size" warnings and missing PGS subtitle streams on large
#                  Blu-ray MPEG-TS containers
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
$ScriptVersion = "2.2"
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

# Video quality — veryslow+psy tuning for maximum fidelity
# CRF 16 for HDR (more headroom for 10-bit HDR detail), 17 for SDR
$Script:CRF_HDR         = 16
$Script:CRF_SDR         = 17
$Script:DefaultPreset   = 'veryslow'
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
$Script:X265PsyParams   = "rd=4:psy-rd=1.5:psy-rdoq=1.0:aq-mode=3:deblock=-1,-1"

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
    Write-UiRow "Meta"    "G:\Rip\meta" $global:UI_GRY
    Write-UiRow "Preset"  "$($Script:DefaultPreset)  •  10-bit yuv420p10le" $global:UI_GRY
    Write-UiRow "CRF"     "HDR=$($Script:CRF_HDR)  /  SDR=$($Script:CRF_SDR)  (auto-detected)" $global:UI_GRY
    Write-UiRow "Psy"     "rd=4  psy-rd=1.5  psy-rdoq=1.0  aq-mode=3" $global:UI_GRY
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
        $Script:TxtRoot
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

    if (Test-Path $outputFile) {
        $stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
        $outputFile = Join-Path $Script:SampleRoot "${safeName}_sample_$stamp.$($Script:DefaultExt)"
    }

    return [string]$outputFile
}

function Move-SourceToDone {
    param([Parameter(Mandatory)][System.IO.FileInfo]$SourceFile)

    $dest = Join-Path $Script:DoneRoot $SourceFile.Name

    if (Test-Path $dest) {
        $stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
        $dest = Join-Path $Script:DoneRoot ("{0}_{1}{2}" -f $SourceFile.BaseName, $stamp, $SourceFile.Extension)
    }

    Move-Item -Path $SourceFile.FullName -Destination $dest -Force
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
"@ | Set-Content -Path $metaFile -Encoding UTF8
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
        $fileInfo = Get-Item -Path $Path -ErrorAction SilentlyContinue
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

function Get-TrackMetaCandidates {
    param(
        [Parameter(Mandatory)][System.IO.FileInfo]$SourceFile,
        [Parameter(Mandatory)][string]$MovieName
    )

    $candidates = New-Object System.Collections.Generic.List[string]

    $sourceBase = [System.IO.Path]::GetFileNameWithoutExtension($SourceFile.Name)
    $movieSafe  = New-SafeName -Name $MovieName

    # Direct matches first. Avoid generic Blu-ray stream aliases like 00004.json;
    # those can collide between different discs.
    if ($sourceBase -notmatch '^\d{5}$') {
        $candidates.Add((Join-Path $Script:MetaRoot "$sourceBase.json"))
    }
    $candidates.Add((Join-Path $Script:MetaRoot "$movieSafe.json"))

    # If the source is a Blu-ray stream such as 00004.m2ts, also check the
    # parent backup folder name, because backup metadata is saved as Movie.json.
    $dir = $SourceFile.Directory
    while ($dir -and $dir.FullName -ne $Script:InputRoot) {
        if ($dir.Name -and $dir.Name -notin @('STREAM', 'BDMV')) {
            $folderSafe = New-SafeName -Name $dir.Name
            $candidates.Add((Join-Path $Script:MetaRoot "$folderSafe.json"))
        }
        $dir = $dir.Parent
    }

    return @($candidates | Select-Object -Unique)
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
                $raw = Get-Content -LiteralPath $path -Raw -Encoding UTF8
                $json = $raw | ConvertFrom-Json
                return [pscustomobject]@{
                    Path = $path
                    Data = $json
                }
            }
            catch {
                Write-UiBlankLine
                Write-CoreError "Failed to read track metadata: $path"
                Write-Host "  $($global:UI_GRY)$($_.Exception.Message)$($global:UI_R)"
                return $null
            }
        }
    }

    # Fallback scan: useful when the source file is 00004.m2ts but the metadata
    # sidecar is named after the movie. This prevents the dreaded 'und' tracks.
    if (Test-Path -LiteralPath $Script:MetaRoot) {
        $jsonFiles = Get-ChildItem -LiteralPath $Script:MetaRoot -Filter *.json -File -ErrorAction SilentlyContinue |
                     Sort-Object LastWriteTime -Descending |
                     Select-Object -First $Script:MetadataScanLimit

        foreach ($file in $jsonFiles) {
            try {
                $raw = Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8
                $json = $raw | ConvertFrom-Json
                if (Test-TrackMetadataMatch -Meta $json -SourceFile $SourceFile -MovieName $MovieName) {
                    return [pscustomobject]@{
                        Path = $file.FullName
                        Data = $json
                    }
                }
            }
            catch {
                continue
            }
        }
    }

    return $null
}

function Resolve-LanguageCode {
    param([string]$Code)

    if ([string]::IsNullOrWhiteSpace($Code)) { return 'und' }

    $clean = $Code.Trim().ToLowerInvariant()

    # Already a valid 3-letter ISO 639-2 code — pass it straight through
    if ($clean -match '^[a-z]{3}$') { return $clean }

    # Full language name → ISO 639-2/B code
    switch ($clean) {
        'english'    { return 'eng' }
        'spanish'    { return 'spa' }
        'french'     { return 'fre' }
        'japanese'   { return 'jpn' }
        'german'     { return 'ger' }
        'italian'    { return 'ita' }
        'portuguese' { return 'por' }
        'chinese'    { return 'chi' }
        'korean'     { return 'kor' }
        'arabic'     { return 'ara' }
        'russian'    { return 'rus' }
        'dutch'      { return 'dut' }
        'hindi'      { return 'hin' }
        'swedish'    { return 'swe' }
        'norwegian'  { return 'nor' }
        'danish'     { return 'dan' }
        'finnish'    { return 'fin' }
        'polish'     { return 'pol' }
        'czech'      { return 'cze' }
        'hungarian'  { return 'hun' }
        'turkish'    { return 'tur' }
        'greek'      { return 'gre' }
        'hebrew'     { return 'heb' }
        'thai'       { return 'tha' }
        'vietnamese' { return 'vie' }
        'indonesian' { return 'ind' }
        'malay'      { return 'may' }
        'romanian'   { return 'rum' }
        'ukrainian'  { return 'ukr' }
        'croatian'   { return 'hrv' }
        'slovak'     { return 'slo' }
        'bulgarian'  { return 'bul' }
        'catalan'    { return 'cat' }
        # 2-letter ISO 639-1 codes — map to 639-2
        'en'         { return 'eng' }
        'es'         { return 'spa' }
        'fr'         { return 'fre' }
        'ja'         { return 'jpn' }
        'de'         { return 'ger' }
        'it'         { return 'ita' }
        'pt'         { return 'por' }
        'zh'         { return 'chi' }
        'ko'         { return 'kor' }
        'ar'         { return 'ara' }
        'ru'         { return 'rus' }
        'nl'         { return 'dut' }
        'hi'         { return 'hin' }
        'sv'         { return 'swe' }
        'no'         { return 'nor' }
        'da'         { return 'dan' }
        'fi'         { return 'fin' }
        'pl'         { return 'pol' }
        'cs'         { return 'cze' }
        'hu'         { return 'hun' }
        'tr'         { return 'tur' }
        'el'         { return 'gre' }
        'he'         { return 'heb' }
        'th'         { return 'tha' }
        'vi'         { return 'vie' }
        'id'         { return 'ind' }
        'ms'         { return 'may' }
        'ro'         { return 'rum' }
        'uk'         { return 'ukr' }
        'hr'         { return 'hrv' }
        'sk'         { return 'slo' }
        'bg'         { return 'bul' }
        'ca'         { return 'cat' }
        # Explicit unknowns
        'unknown'       { return 'und' }
        'undetermined'  { return 'und' }
        default         { return $clean }
    }
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
        if ($Title.AudioTracks) { return @($Title.AudioTracks | Sort-Object TrackId) }
        if ($Title.Tracks)      { return @($Title.Tracks | Where-Object { $_.Type -eq 'Audio' } | Sort-Object TrackId) }
    }

    if ($Kind -eq 'subtitle') {
        if ($Title.SubtitleTracks) { return @($Title.SubtitleTracks | Sort-Object TrackId) }
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
        $warnings.Add("Audio count mismatch: output=$($TrackLayout.AudioCount), metadata=$($audioMeta.Count). Will apply the safe minimum.")
    }
    if ($TrackLayout.SubtitleCount -ne $subMeta.Count) {
        $warnings.Add("Subtitle count mismatch: output=$($TrackLayout.SubtitleCount), metadata=$($subMeta.Count). Will apply the safe minimum.")
    }

    $knownAudio = @($audioMeta | Where-Object { (Resolve-LanguageCode -Code $_.LanguageCode) -ne 'und' })
    $knownSubs  = @($subMeta   | Where-Object { (Resolve-LanguageCode -Code $_.LanguageCode) -ne 'und' })
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

function Invoke-MKVLanguageRemux {
    param(
        [Parameter(Mandatory)][string]$OutputFile,
        [Parameter(Mandatory)][object]$TrackLayout,
        [Parameter(Mandatory)][object[]]$AudioMeta,
        [Parameter(Mandatory)][object[]]$SubMeta
    )

    $dir  = Split-Path -Parent $OutputFile
    $base = [System.IO.Path]::GetFileNameWithoutExtension($OutputFile)
    $ext  = [System.IO.Path]::GetExtension($OutputFile)
    $tmp  = Join-Path $dir ("{0}.metadata_tmp{1}" -f $base, $ext)
    $bak  = Join-Path $dir ("{0}.pre_metadata_{1}{2}" -f $base, (Get-Date -Format 'yyyyMMdd_HHmmss'), $ext)

    if (Test-Path -LiteralPath $tmp) {
        Remove-Item -LiteralPath $tmp -Force
    }

    $muxArgs = @('-o', $tmp)

    $audioToApply = [Math]::Min($TrackLayout.AudioTracks.Count, $AudioMeta.Count)
    for ($i = 0; $i -lt $audioToApply; $i++) {
        $outTrack = $TrackLayout.AudioTracks[$i]
        $metaTrack = $AudioMeta[$i]
        $id = [int]$outTrack.id
        $lang = Get-MetaLanguage -Track $metaTrack
        $name = Get-MetaTrackName -Track $metaTrack

        $muxArgs += '--language'
        $muxArgs += ("{0}:{1}" -f $id, $lang)

        if (-not [string]::IsNullOrWhiteSpace($name)) {
            $muxArgs += '--track-name'
            $muxArgs += ("{0}:{1}" -f $id, $name)
        }

        $muxArgs += '--default-track'
        $muxArgs += ("{0}:{1}" -f $id, $(if ($metaTrack.Default) { 'yes' } else { 'no' }))
    }

    $subToApply = [Math]::Min($TrackLayout.SubtitleTracks.Count, $SubMeta.Count)
    for ($i = 0; $i -lt $subToApply; $i++) {
        $outTrack = $TrackLayout.SubtitleTracks[$i]
        $metaTrack = $SubMeta[$i]
        $id = [int]$outTrack.id
        $lang = Get-MetaLanguage -Track $metaTrack
        $name = Get-MetaTrackName -Track $metaTrack

        $muxArgs += '--language'
        $muxArgs += ("{0}:{1}" -f $id, $lang)

        if (-not [string]::IsNullOrWhiteSpace($name)) {
            $muxArgs += '--track-name'
            $muxArgs += ("{0}:{1}" -f $id, $name)
        }

        $muxArgs += '--default-track'
        $muxArgs += ("{0}:{1}" -f $id, $(if ($metaTrack.Default) { 'yes' } else { 'no' }))

        $muxArgs += '--forced-display-flag'
        $muxArgs += ("{0}:{1}" -f $id, $(if ($metaTrack.Forced) { 'yes' } else { 'no' }))
    }

    $muxArgs += $OutputFile

    Write-Host "  $($global:UI_CYN)Remuxing with mkvmerge using real MKV track IDs...$($global:UI_R)"
    & $Script:MKVMergePath @muxArgs

    if ($LASTEXITCODE -ne 0) {
        if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Force }
        throw "mkvmerge metadata remux failed with exit code $LASTEXITCODE"
    }

    if (-not (Test-Path -LiteralPath $tmp)) {
        throw "mkvmerge metadata remux did not create temp output: $tmp"
    }

    Move-Item -LiteralPath $OutputFile -Destination $bak -Force
    Move-Item -LiteralPath $tmp -Destination $OutputFile -Force
    Remove-Item -LiteralPath $bak -Force -ErrorAction SilentlyContinue
}

function Apply-TrackMetadata {
    param(
        [Parameter(Mandatory)][string]$OutputFile,
        [Parameter(Mandatory)][System.IO.FileInfo]$SourceFile,
        [Parameter(Mandatory)][string]$MovieName
    )

    $metaInfo = Load-TrackMetadata -SourceFile $SourceFile -MovieName $MovieName
    if (-not $metaInfo) {
        Write-UiBlankLine
        Write-Host "  $($global:UI_YLW)No matching track metadata JSON found. Skipping label pass.$($global:UI_R)"
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

    # Use mkvmerge, not mkvpropedit, for the final tagging pass.
    # mkvmerge -J gives the real MKV track IDs in the finished file. Those IDs
    # are the only safe IDs to use when applying --language, --track-name,
    # default-track, and forced-display-flag. This fixes the old "everything is
    # und" failure caused by relying on positional or ffmpeg-style indexes.
    Invoke-MKVLanguageRemux -OutputFile $OutputFile -TrackLayout $trackLayout -AudioMeta $audioMeta -SubMeta $subMeta

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
    Write-Host "  $($global:UI_DIM)Mode  $($global:UI_R)  stream copy"
    Write-UiBlankLine

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
        '-map', '0:s?',
        '-c', 'copy',
        $sampleOutput
    )

    & $Script:FFmpegPath @args

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
        [Parameter(Mandatory)][string]$MovieName
    )

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

    # ── Build ffmpeg args ──────────────────────────────────────
    $ffArgs = @(
        '-hide_banner',
        '-y',
        '-probesize', $Script:M2tsProbeSize,
        '-analyzeduration', $Script:M2tsAnalyzeDur,
        '-i', $SourceFile.FullName,
        '-map', '0:v:0',
        '-map', '0:a?',
        '-map', '0:s?',
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

    & $Script:FFmpegPath @ffArgs

    if ($LASTEXITCODE -ne 0) {
        throw "ffmpeg failed with exit code $LASTEXITCODE"
    }

    $encodedInfo = Wait-ForOutputFile -Path $outputFile

    $appliedMeta = Apply-TrackMetadata -OutputFile $encodedInfo.FullName -SourceFile $SourceFile -MovieName $MovieName
    if ($appliedMeta) {
        $trackMetaPath = $appliedMeta
    }

    Create-SampleFromFinishedMkv -FinishedMkvPath $encodedInfo.FullName -MovieName $MovieName

    $donePath = Move-SourceToDone -SourceFile $SourceFile
    Write-MetaFile -MovieName $MovieName -SourceFile $SourceFile -OutputFile $encodedInfo.FullName `
                   -DurationSeconds $duration -TrackMetaPath $trackMetaPath -VideoProfile $vp

    Write-UiBlankLine
    Write-Host "  $($global:UI_GRN)Encode complete.$($global:UI_R)"
    Write-Host "  $($global:UI_DIM)Profile$($global:UI_R)  $($vp.Profile)  •  CRF $($vp.CRF)  •  $($Script:DefaultPreset)"
    Write-Host "  $($global:UI_DIM)Saved  $($global:UI_R)  $($encodedInfo.FullName)"
    Write-Host "  $($global:UI_DIM)Moved  $($global:UI_R)  $donePath"
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

while ($true) {
    Show-Header
    Show-Menu
    $choice = (Read-Host "Choose").Trim().ToUpper()

    switch ($choice) {
        '1' { Encode-AllFiles }
        '2' { Encode-SingleFile }
        '3' { Show-SourceFiles }
        '4' { Show-Config }
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