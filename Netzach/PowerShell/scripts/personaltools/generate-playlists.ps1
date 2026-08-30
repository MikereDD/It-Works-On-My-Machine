<#
.SYNOPSIS
    Generate one .m3u playlist per folder in a music / audiobook library.

.DESCRIPTION
    Walks -MusicRoot recursively. For every folder that directly contains audio
    files (music tracks or audiobook parts), it writes a playlist named
    "<FolderName>.m3u" *inside that folder*, listing the files (natural order) as
    RELATIVE filenames.

    Relative entries are deliberate: they sit next to the media they reference,
    so the playlist resolves correctly both locally and after you sync the folder
    to pCloud and open it in the pCloud TV app (which matches entries by filename
    within the same folder).

    The script only ever manages playlists named after their own folder
    ("<FolderName>.m3u"). It never touches any other .m3u you created by hand.

    Output and prompts route through the shared toolkit modules (ui.ps1 + core.ps1)
    so the look matches the rest of the Dumb Terminal Team scripts.

.PARAMETER MusicRoot
    Root of the music library, e.g. 'P:\Music'.

.PARAMETER Clean
    Delete every managed "<FolderName>.m3u" under -MusicRoot before regenerating.
    Useful after renaming/reorganizing so stale playlists don't linger.

.PARAMETER CleanOnly
    Delete every managed "<FolderName>.m3u" under -MusicRoot and stop. No playlists
    are regenerated. Implies cleaning; ignores -Clean.

.PARAMETER Probe
    Opt-in: use ffprobe to read each track's real duration into the #EXTINF line.
    Slower on large libraries (one ffprobe call per file). If ffprobe isn't on PATH,
    durations fall back to -1. Without -Probe, every entry is written as #EXTINF:-1.

.PARAMETER Extensions
    Audio file extensions to include (without the dot). Sensible defaults provided.

.EXAMPLE
    .\generate-playlists.ps1 -MusicRoot 'P:\Music'

.EXAMPLE
    .\generate-playlists.ps1 -MusicRoot 'P:\Music' -Clean

.EXAMPLE
    .\generate-playlists.ps1 -MusicRoot 'P:\Music' -CleanOnly

.EXAMPLE
    .\generate-playlists.ps1 -MusicRoot 'P:\Music' -Clean -Probe

.NOTES
    Depends on ui.ps1 and core.ps1 (found next to this script, or under
    $env:USERPROFILE\PS\profile.d).
#>
[CmdletBinding()]
param(
    [string]$MusicRoot,

    [switch]$Clean,

    [switch]$CleanOnly,

    [switch]$Probe,

    [string[]]$Extensions = @(
        # music
        'flac', 'mp3', 'm4a', 'aac', 'ogg', 'opus',
        'wav', 'wma', 'alac', 'ape', 'wv', 'mka',
        # audiobooks
        'm4b', 'aa', 'aax'
    )
)

$ErrorActionPreference = 'Stop'

# ── Load shared toolkit modules (ui + core) ───────────────────
# Prefer the profile dir the launcher forwards ($PSProfileDir); then copies next
# to this script; then the canonical profile.d path as a last resort.
$psLib = if ($PSProfileDir -and (Test-Path -LiteralPath (Join-Path $PSProfileDir 'core.ps1'))) {
    $PSProfileDir
} elseif (Test-Path -LiteralPath "$PSScriptRoot\core.ps1") {
    $PSScriptRoot
} else {
    "$env:USERPROFILE\PS\profile.d"
}
. (Join-Path $psLib 'ui.ps1')
. (Join-Path $psLib 'core.ps1')

# When launched with no -MusicRoot (e.g. from tool-menu), prompt interactively.
$interactive = $false
if ([string]::IsNullOrWhiteSpace($MusicRoot)) {
    $interactive = $true
    $MusicRoot = (Read-UiChoice -Prompt "Music / audiobook root (e.g. P:\Music):").Trim().Trim('"')
    if (-not $Clean -and -not $CleanOnly) {
        if (Confirm-Core -Message "Delete & rebuild existing playlists first?") { $Clean = $true }
    }
}

if ([string]::IsNullOrWhiteSpace($MusicRoot)) {
    Write-CoreError "No music root supplied."
    if ($interactive) { Pause-Core }
    return
}

if (-not (Test-Path -LiteralPath $MusicRoot -PathType Container)) {
    Write-CoreError "MusicRoot not found: $MusicRoot"
    if ($interactive) { Pause-Core }
    return
}

# Probe availability (only when -Probe requested).
$probeOk = $false
if ($Probe) {
    if (Get-Command ffprobe -ErrorAction SilentlyContinue) {
        $probeOk = $true
    } else {
        Write-CoreError "ffprobe not found on PATH - writing unknown durations (-1)."
    }
}

# Normalize extensions to a fast lookup set (lowercase, no dot).
$audioExt = [System.Collections.Generic.HashSet[string]]::new(
    [string[]]($Extensions | ForEach-Object { $_.TrimStart('.').ToLowerInvariant() }),
    [System.StringComparer]::OrdinalIgnoreCase
)

# Natural sort key: pad digit runs so "2" sorts before "10".
function Get-SortKey([string]$name) {
    [regex]::Replace($name, '\d+', { param($m) $m.Value.PadLeft(10, '0') })
}

# Duration in whole seconds via ffprobe, or -1 if unknown / probe failed.
function Get-AudioDuration([string]$path) {
    try {
        $raw = (& ffprobe -v error -show_entries format=duration -of csv=p=0 -- "$path" 2>$null |
            Select-Object -First 1)
        $val = 0.0
        if ([double]::TryParse(
                $raw,
                [System.Globalization.NumberStyles]::Float,
                [System.Globalization.CultureInfo]::InvariantCulture,
                [ref]$val)) {
            return [int][math]::Round($val)
        }
    } catch {}
    return -1
}

$utf8NoBom = [System.Text.UTF8Encoding]::new($false)

# Root folder first, then every subfolder.
$dirs = @(Get-Item -LiteralPath $MusicRoot)
$dirs += Get-ChildItem -LiteralPath $MusicRoot -Directory -Recurse

$written    = 0
$cleaned    = 0
$skipped    = 0
$trackTotal = 0

$modeText = if ($CleanOnly) { 'clean only (no rebuild)' }
            elseif ($Clean) { 'clean + rebuild' }
            else            { 'rebuild (overwrite)' }

Write-UiHeader -Title "pCloud TV playlist generator"
Write-UiRow -Label "Root" -Value $MusicRoot -ValueColor $global:UI_WHT
Write-UiRow -Label "Mode" -Value $modeText  -ValueColor $global:UI_WHT
if ($Probe) {
    Write-UiRow -Label "Durations" -Value $(if ($probeOk) { 'ffprobe' } else { 'unknown (-1)' }) -ValueColor $global:UI_WHT
}
Write-UiDivider

foreach ($d in $dirs) {
    $leaf   = $d.Name
    $plPath = Join-Path $d.FullName ("{0}.m3u" -f $leaf)

    # -Clean / -CleanOnly remove the managed playlist for this folder up front.
    if (($Clean -or $CleanOnly) -and (Test-Path -LiteralPath $plPath -PathType Leaf)) {
        Remove-Item -LiteralPath $plPath -Force
        $cleaned++
    }

    # -CleanOnly stops after removal; nothing is regenerated.
    if ($CleanOnly) { continue }

    $audio = Get-ChildItem -LiteralPath $d.FullName -File |
        Where-Object { $audioExt.Contains($_.Extension.TrimStart('.')) }

    if ($audio.Count -eq 0) {
        $skipped++
        continue
    }

    $sorted = $audio | Sort-Object { Get-SortKey $_.Name }

    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add('#EXTM3U')
    foreach ($f in $sorted) {
        $title = [System.IO.Path]::GetFileNameWithoutExtension($f.Name)
        $dur   = if ($probeOk) { Get-AudioDuration $f.FullName } else { -1 }
        $lines.Add("#EXTINF:$dur,$title")
        $lines.Add($f.Name)
    }

    $text = ($lines -join "`r`n") + "`r`n"
    [System.IO.File]::WriteAllText($plPath, $text, $utf8NoBom)

    $written++
    $trackTotal += $sorted.Count
    Write-UiRow -Label $leaf -Value ("{0} tracks" -f $sorted.Count) -LabelWidth 40
}

Write-UiDivider
if ($CleanOnly) {
    Write-UiRow -Label "Playlists removed" -Value $cleaned -ValueColor $global:UI_CYN
} else {
    Write-UiRow -Label "Playlists written" -Value $written -ValueColor $global:UI_CYN
    if ($Clean) {
        Write-UiRow -Label "Playlists cleaned" -Value $cleaned
    }
    Write-UiRow -Label "Folders w/o audio" -Value $skipped -ValueColor $global:UI_GRY
    Write-UiRow -Label "Tracks listed"     -Value $trackTotal -ValueColor $global:UI_CYN
}
Write-UiBlankLine

Write-CoreLog "playlists: run complete (written=$written cleaned=$cleaned skipped=$skipped tracks=$trackTotal)"

# Keep the summary on screen when run from the tool menu.
if ($interactive) { Pause-Core }
