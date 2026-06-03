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

.PARAMETER MusicRoot
    Root of the music library, e.g. 'P:\Music'.

.PARAMETER Clean
    Delete every managed "<FolderName>.m3u" under -MusicRoot before regenerating.
    Useful after renaming/reorganizing so stale playlists don't linger.

.PARAMETER Extensions
    Audio file extensions to include (without the dot). Sensible defaults provided.

.EXAMPLE
    .\generate-playlists.ps1 -MusicRoot 'P:\Music'

.EXAMPLE
    .\generate-playlists.ps1 -MusicRoot 'P:\Music' -Clean
#>
[CmdletBinding()]
param(
    [string]$MusicRoot,

    [switch]$Clean,

    [string[]]$Extensions = @(
        # music
        'flac', 'mp3', 'm4a', 'aac', 'ogg', 'opus',
        'wav', 'wma', 'alac', 'ape', 'wv', 'mka',
        # audiobooks
        'm4b', 'aa', 'aax'
    )
)

$ErrorActionPreference = 'Stop'

# When launched with no -MusicRoot (e.g. from tool-menu), prompt interactively.
$interactive = $false
if ([string]::IsNullOrWhiteSpace($MusicRoot)) {
    $interactive = $true
    $MusicRoot = (Read-Host "Music / audiobook root (e.g. P:\Music)").Trim().Trim('"')
    if (-not $Clean) {
        $ans = (Read-Host "Delete & rebuild existing playlists first? (y/N)").Trim()
        if ($ans -match '^(y|yes)$') { $Clean = $true }
    }
}

if ([string]::IsNullOrWhiteSpace($MusicRoot)) {
    Write-Error "No music root supplied."
    return
}

if (-not (Test-Path -LiteralPath $MusicRoot -PathType Container)) {
    Write-Error "MusicRoot not found: $MusicRoot"
    return
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

$utf8NoBom = [System.Text.UTF8Encoding]::new($false)

# Root folder first, then every subfolder.
$dirs = @(Get-Item -LiteralPath $MusicRoot)
$dirs += Get-ChildItem -LiteralPath $MusicRoot -Directory -Recurse

$written = 0
$cleaned = 0
$skipped = 0
$trackTotal = 0

Write-Host ""
Write-Host "  pCloud TV playlist generator" -ForegroundColor Cyan
Write-Host "  Root : $MusicRoot"
Write-Host "  Mode : $(if ($Clean) { 'clean + rebuild' } else { 'rebuild (overwrite)' })"
Write-Host "  ----------------------------------------------------------"

foreach ($d in $dirs) {
    $leaf   = $d.Name
    $plPath = Join-Path $d.FullName ("{0}.m3u" -f $leaf)

    # -Clean removes the managed playlist for this folder up front.
    if ($Clean -and (Test-Path -LiteralPath $plPath -PathType Leaf)) {
        Remove-Item -LiteralPath $plPath -Force
        $cleaned++
    }

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
        $lines.Add("#EXTINF:-1,$title")
        $lines.Add($f.Name)
    }

    $text = ($lines -join "`r`n") + "`r`n"
    [System.IO.File]::WriteAllText($plPath, $text, $utf8NoBom)

    $written++
    $trackTotal += $sorted.Count
    Write-Host ("  + {0,-40} {1,3} tracks" -f $leaf, $sorted.Count) -ForegroundColor Green
}

Write-Host "  ----------------------------------------------------------"
Write-Host ("  Playlists written : {0}" -f $written)   -ForegroundColor Cyan
if ($Clean) {
    Write-Host ("  Playlists cleaned : {0}" -f $cleaned)
}
Write-Host ("  Folders w/o audio : {0}" -f $skipped)
Write-Host ("  Tracks listed     : {0}" -f $trackTotal)
Write-Host ""

# Keep the summary on screen when run from the tool menu.
if ($interactive) {
    Read-Host "Press Enter to return..." | Out-Null
}
