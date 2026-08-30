#--------------------------------------------
# file:     clip-video.ps1
# author:   Mike Redd
# version:  0.1
# created:  2026-06-20
# updated:  2026-06-20
# desc:     Clip a video segment to MKV or MP4 (ffmpeg)

<#
.SYNOPSIS
    clip-video.ps1 - Menu-driven video clipper (ffmpeg front-end). Outputs MKV or MP4.

.DESCRIPTION
    Cuts a segment out of a local video between two timestamps. Two cut modes:
      - Stream copy : near-instant, no re-encode, cuts land on/near keyframes.
      - Re-encode   : frame-accurate, transcodes the segment (libx264 CRF 18).
    Two output containers:
      - MKV : keeps every track (-map 0) - multi-audio, subtitles, attachments.
      - MP4 : video + audio only, +faststart, broadest device support. Image
              subtitles (PGS/VOBSUB) and MKV attachments can't live in MP4, so
              they're dropped.

    Part of the personaltools/ toolkit. Dot-sources core.ps1 / ui.ps1 from the
    script directory and uses Show-Header / Pause-Script / Confirm-Action. Falls
    back to local shims if those modules aren't present, so it also runs solo.

.NOTES
    Windows PowerShell 5.1 compatible (no ?? / ?. / ?[] operators).
#>

[CmdletBinding()]
param(
    [string]$InputFile,
    [string]$Start,                              # e.g. 00:34:45 or 34:45 or 2085
    [string]$End,                                # e.g. 00:38:50
    [string]$Mode,                               # 'copy' or 'reencode'
    [string]$Container,                           # 'mkv' or 'mp4'
    [string]$OutputDir = 'G:\Rip\clips',
    [string]$OutputFile
)

# --- shared modules ---------------------------------------------------------
$corePath = Join-Path $PSScriptRoot 'core.ps1'
$uiPath   = Join-Path $PSScriptRoot 'ui.ps1'
if (Test-Path -LiteralPath $corePath) { . $corePath }
if (Test-Path -LiteralPath $uiPath)   { . $uiPath }

# Fallback shims (only defined if the modules didn't supply them).
if (-not (Get-Command Show-Header -ErrorAction SilentlyContinue)) {
    function Show-Header {
        param([string]$Title)
        Write-Host ''
        Write-Host ("=== {0} ===" -f $Title) -ForegroundColor Cyan
        Write-Host ''
    }
}
if (-not (Get-Command Pause-Script -ErrorAction SilentlyContinue)) {
    function Pause-Script { Read-Host 'Press Enter to continue' | Out-Null }
}
if (-not (Get-Command Confirm-Action -ErrorAction SilentlyContinue)) {
    function Confirm-Action {
        param([string]$Message)
        $r = Read-Host ("{0} [y/N]" -f $Message)
        return ($r -match '^(y|yes)$')
    }
}

# --- helpers ----------------------------------------------------------------
function Test-Tool {
    param([string]$Name)
    return [bool](Get-Command $Name -ErrorAction SilentlyContinue)
}

function ConvertTo-Seconds {
    # Accepts HH:MM:SS(.fff), MM:SS(.fff), or raw seconds. Returns [double] or $null.
    param([string]$Time)
    if ([string]::IsNullOrWhiteSpace($Time)) { return $null }
    $t = $Time.Trim()
    if ($t -match '^\d+(\.\d+)?$') { return [double]$t }
    $parts = $t.Split(':')
    if ($parts.Count -lt 2 -or $parts.Count -gt 3) { return $null }
    foreach ($p in $parts) { if ($p -notmatch '^\d+(\.\d+)?$') { return $null } }
    if ($parts.Count -eq 3) {
        return ([double]$parts[0] * 3600) + ([double]$parts[1] * 60) + [double]$parts[2]
    }
    return ([double]$parts[0] * 60) + [double]$parts[1]
}

function Format-Hms {
    param([double]$TotalSeconds)
    $ts = [TimeSpan]::FromSeconds($TotalSeconds)
    $h  = [int][math]::Floor($ts.TotalHours)
    return ('{0:00}:{1:00}:{2:00}' -f $h, $ts.Minutes, $ts.Seconds)
}

function Get-SourceDuration {
    # Returns source length in seconds via ffprobe, or $null if unavailable.
    param([string]$Path)
    if (-not (Test-Tool 'ffprobe')) { return $null }
    $raw = & ffprobe -v error -show_entries format=duration -of csv=p=0 -- "$Path" 2>$null
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($raw)) { return $null }
    $val = 0.0
    if ([double]::TryParse(($raw | Select-Object -First 1).Trim(),
            [System.Globalization.NumberStyles]::Float,
            [System.Globalization.CultureInfo]::InvariantCulture, [ref]$val)) {
        return $val
    }
    return $null
}

function Read-Timestamp {
    param([string]$Label, [double]$MaxSeconds = -1)
    while ($true) {
        $raw  = Read-Host $Label
        $secs = ConvertTo-Seconds $raw
        if ($null -eq $secs) {
            Write-Host '  Bad format. Use HH:MM:SS, MM:SS, or seconds.' -ForegroundColor Yellow
            continue
        }
        if ($MaxSeconds -ge 0 -and $secs -gt $MaxSeconds) {
            Write-Host ('  Past end of source ({0}).' -f (Format-Hms $MaxSeconds)) -ForegroundColor Yellow
            continue
        }
        return $secs
    }
}

function Get-UniqueOutput {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $Path }
    $dir  = [System.IO.Path]::GetDirectoryName($Path)
    $name = [System.IO.Path]::GetFileNameWithoutExtension($Path)
    $ext  = [System.IO.Path]::GetExtension($Path)
    $i = 2
    while ($true) {
        $candidate = Join-Path $dir ("{0}_{1}{2}" -f $name, $i, $ext)
        if (-not (Test-Path -LiteralPath $candidate)) { return $candidate }
        $i++
    }
}

function Select-Mode {
    # Returns 'copy' or 'reencode'.
    Write-Host ''
    Write-Host '  Cut mode:' -ForegroundColor Cyan
    Write-Host '    [1] Stream copy   (fast, keyframe-aligned)'
    Write-Host '    [2] Re-encode     (frame-accurate, libx264 CRF 18)'
    while ($true) {
        $sel = Read-Host '  Choose'
        switch ($sel) {
            '1' { return 'copy' }
            '2' { return 'reencode' }
            default { Write-Host '  Enter 1 or 2.' -ForegroundColor Yellow }
        }
    }
}

function Select-Container {
    # Returns 'mkv' or 'mp4'.
    Write-Host ''
    Write-Host '  Output container:' -ForegroundColor Cyan
    Write-Host '    [1] MKV   (keeps all audio / subtitle / attachment tracks)'
    Write-Host '    [2] MP4   (video + audio only, +faststart, broad device support)'
    while ($true) {
        $sel = Read-Host '  Choose'
        switch ($sel) {
            '1' { return 'mkv' }
            '2' { return 'mp4' }
            default { Write-Host '  Enter 1 or 2.' -ForegroundColor Yellow }
        }
    }
}

function Invoke-Clip {
    param(
        [string]$In,
        [double]$StartSecs,
        [double]$DurSecs,
        [string]$Out,
        [string]$ClipMode,
        [string]$Container
    )

    # -ss before -i = fast input seek; -t after -i = output duration (unambiguous).
    $ffArgs = @('-y', '-ss', $StartSecs, '-i', $In, '-t', $DurSecs)

    if ($Container -eq 'mp4') {
        # MP4 can't hold image subs (PGS/VOBSUB) or MKV attachments -> video + audio only.
        $ffArgs += @('-map', '0:v?', '-map', '0:a?')
        if ($ClipMode -eq 'reencode') {
            $ffArgs += @('-c:v', 'libx264', '-crf', '18', '-preset', 'medium', '-c:a', 'copy')
        }
        else {
            $ffArgs += @('-c', 'copy')
        }
        $ffArgs += @('-movflags', '+faststart')
    }
    else {
        # MKV keeps everything.
        $ffArgs += @('-map', '0')
        if ($ClipMode -eq 'reencode') {
            $ffArgs += @('-c:v', 'libx264', '-crf', '18', '-preset', 'medium', '-c:a', 'copy', '-c:s', 'copy')
        }
        else {
            $ffArgs += @('-c', 'copy')
        }
    }
    $ffArgs += $Out

    Write-Host ''
    Write-Host ("  ffmpeg {0}" -f ($ffArgs -join ' ')) -ForegroundColor DarkGray
    Write-Host ''

    & ffmpeg @ffArgs
    return ($LASTEXITCODE -eq 0)
}

# --- main -------------------------------------------------------------------
Show-Header 'Video Clipper'

if (-not (Test-Tool 'ffmpeg')) {
    Write-Host 'ffmpeg not found on PATH.' -ForegroundColor Red
    Pause-Script
    return
}

do {
    # 1. input file
    $in = $InputFile
    while ([string]::IsNullOrWhiteSpace($in) -or -not (Test-Path -LiteralPath $in)) {
        if (-not [string]::IsNullOrWhiteSpace($in)) {
            Write-Host ('  Not found: {0}' -f $in) -ForegroundColor Yellow
        }
        $in = (Read-Host '  Input video path').Trim('"')
    }

    $srcDur = Get-SourceDuration $in
    if ($null -ne $srcDur) {
        Write-Host ('  Source length: {0}' -f (Format-Hms $srcDur)) -ForegroundColor DarkGray
    }

    # 2. timestamps
    $startSecs = ConvertTo-Seconds $Start
    if ($null -eq $startSecs) { $startSecs = Read-Timestamp '  Start (HH:MM:SS)' $srcDur }

    $endSecs = ConvertTo-Seconds $End
    if ($null -eq $endSecs) { $endSecs = Read-Timestamp '  End   (HH:MM:SS)' $srcDur }

    while ($endSecs -le $startSecs) {
        Write-Host '  End must be after start.' -ForegroundColor Yellow
        $endSecs = Read-Timestamp '  End   (HH:MM:SS)' $srcDur
    }
    $durSecs = $endSecs - $startSecs

    # 3. mode
    $clipMode = $Mode
    if ($clipMode -ne 'copy' -and $clipMode -ne 'reencode') { $clipMode = Select-Mode }

    # 4. container (inferred from -OutputFile extension if one was given)
    $container = $Container
    if (-not [string]::IsNullOrWhiteSpace($OutputFile)) {
        $oext = [System.IO.Path]::GetExtension($OutputFile).TrimStart('.').ToLower()
        if ($oext -eq 'mp4' -or $oext -eq 'mkv') { $container = $oext }
    }
    if ($container -ne 'mkv' -and $container -ne 'mp4') { $container = Select-Container }

    # 5. output path
    $out = $OutputFile
    if ([string]::IsNullOrWhiteSpace($out)) {
        $base = [System.IO.Path]::GetFileNameWithoutExtension($in)
        $out  = Join-Path $OutputDir ("{0}_clip.{1}" -f $base, $container)
    }
    # ensure the target folder exists
    $outDir = [System.IO.Path]::GetDirectoryName($out)
    if (-not [string]::IsNullOrWhiteSpace($outDir) -and -not (Test-Path -LiteralPath $outDir)) {
        New-Item -ItemType Directory -Path $outDir -Force | Out-Null
    }
    $out = Get-UniqueOutput $out

    # 6. summary + confirm
    Write-Host ''
    Write-Host '  ---------------------------------------------' -ForegroundColor DarkGray
    Write-Host ('  In    : {0}' -f $in)
    Write-Host ('  Out   : {0}' -f $out)
    Write-Host ('  Start : {0}' -f (Format-Hms $startSecs))
    Write-Host ('  End   : {0}' -f (Format-Hms $endSecs))
    Write-Host ('  Length: {0}' -f (Format-Hms $durSecs))
    if ($clipMode -eq 'reencode') {
        Write-Host '  Mode  : Re-encode (frame-accurate)'
    } else {
        Write-Host '  Mode  : Stream copy (fast)'
    }
    Write-Host ('  Out fmt: {0}' -f $container.ToUpper())
    if ($container -eq 'mp4') {
        Write-Host '  Note  : MP4 keeps video + audio only (subs / attachments dropped).' -ForegroundColor DarkYellow
    }
    Write-Host '  ---------------------------------------------' -ForegroundColor DarkGray

    if (Confirm-Action '  Run this clip?') {
        $ok = Invoke-Clip -In $in -StartSecs $startSecs -DurSecs $durSecs -Out $out -ClipMode $clipMode -Container $container
        Write-Host ''
        if ($ok) {
            Write-Host ('  Done -> {0}' -f $out) -ForegroundColor Green
        } else {
            Write-Host '  ffmpeg reported an error.' -ForegroundColor Red
        }
    } else {
        Write-Host '  Cancelled.' -ForegroundColor Yellow
    }

    # reset params so a second pass prompts fresh
    $InputFile = ''; $Start = ''; $End = ''; $Mode = ''; $Container = ''; $OutputFile = ''
    Write-Host ''
}
while (Confirm-Action '  Clip another?')

Pause-Script
