#--------------------------------------------
# file:     cd-ripper-gui.ps1
# author:   Mike Redd
# version:  1.1.0
# created:  2026-06-17
# updated:  2026-07-03
# desc:     WinForms GUI front-end for the CD -> FLAC
#           archiving toolchain. Wraps both modes:
#             * Single FLAC image + CUE (cd-image-flac.ps1)
#             * One FLAC per track       (cd-tracks-flac.ps1)
#           DiscID + MusicBrainz lookup, editable metadata
#           + track grid, cover embed, JSON sidecar.
#           Background runspaces keep the UI responsive.
#--------------------------------------------

[CmdletBinding()]
param()

# ── Elevate if needed (raw device access for cdda2wav/libdiscid) ──
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).
    IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    # Match the tool-menu convention: WinForms GUIs run under Windows PowerShell
    # in STA (pwsh is MTA and unreliable for WinForms). Re-launch the same host.
    $psExe = (Get-Command powershell.exe -ErrorAction SilentlyContinue).Source
    if (-not $psExe) { $psExe = "powershell.exe" }
    Start-Process $psExe -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -STA -File `"$PSCommandPath`""
    exit
}

# ── WinForms ────────────────────────────────
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

# ── Shared state across UI thread <-> runspaces ─────────────────
$sync = [hashtable]::Synchronized(@{})
$sync.LogQueue = [System.Collections.Concurrent.ConcurrentQueue[object]]::new()
$sync.Done     = $false
$sync.Op       = ""
$sync.Result   = $null
$sync.Error    = $null
$sync.Job      = $null
$sync.Cfg      = $null

# ── Backend worker source (injected into each runspace) ─────────
# Single-quoted here-string: evaluated at runtime inside the runspace.
$sync.WorkerSource = @'
function Send-Log {
    param([string]$Message, [string]$Type = "Info")
    $global:sync.LogQueue.Enqueue([pscustomobject]@{ Text = $Message; Type = $Type })
}

function Get-SafeName {
    param([Parameter(Mandatory)] [string]$Text)
    $safe = ($Text -replace '[<>:"/\\|?*]', '').Trim()
    if ([string]::IsNullOrWhiteSpace($safe)) { return "Unknown" }
    return $safe
}

function Escape-CueText {
    param([Parameter(Mandatory)] [string]$Text)
    return ($Text -replace '"', "'").Trim()
}

function Write-ToolLog {
    param([Parameter(Mandatory)] [string]$Path, [Parameter(Mandatory)] [string]$Message)
    $stamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Add-Content -Path $Path -Value "[$stamp] $Message"
}



function Test-WorkerPath {
    param(
        [Parameter(Mandatory)] [string]$Label,
        [Parameter(Mandatory)] [string]$Path,
        [switch]$Required
    )

    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path $Path)) {
        $msg = "$Label not found: $Path"
        if ($Required) { throw $msg }
        Send-Log $msg "Warn"
        return $false
    }

    return $true
}

function Test-WorkerTools {
    param(
        [switch]$RequireRip,
        [switch]$RequireEncode,
        [switch]$WarnMetadataTools
    )

    $cfg = $global:sync.Cfg
    if ($RequireRip)    { [void](Test-WorkerPath -Label "cdda2wav" -Path $cfg.CDDA2WAV -Required) }
    if ($RequireEncode) { [void](Test-WorkerPath -Label "flac"     -Path $cfg.FLAC     -Required) }

    if ($WarnMetadataTools) {
        [void](Test-WorkerPath -Label "metaflac" -Path $cfg.METAFLAC)
        [void](Test-WorkerPath -Label "libdiscid" -Path $cfg.LIBDISCID)
    }
}

function Test-AudioOutputFile {
    param([Parameter(Mandatory)] [string]$Path)

    if (-not (Test-Path $Path)) { throw "Expected output file was not created: $Path" }
    $item = Get-Item -LiteralPath $Path -ErrorAction Stop
    if ($item.Length -le 0) { throw "Output file is empty: $Path" }
    return $true
}

function Publish-ValidatedAudioFile {
    param(
        [Parameter(Mandatory)] [string]$TempPath,
        [Parameter(Mandatory)] [string]$FinalPath
    )

    [void](Test-AudioOutputFile -Path $TempPath)
    if (Test-Path $FinalPath) { Remove-Item -LiteralPath $FinalPath -Force -ErrorAction Stop }
    Move-Item -LiteralPath $TempPath -Destination $FinalPath -Force -ErrorAction Stop
    [void](Test-AudioOutputFile -Path $FinalPath)
}

function Initialize-LibDiscid {
    $cfg = $global:sync.Cfg
    if (-not (Test-Path $cfg.LIBDISCID)) {
        throw "libdiscid DLL not found: $($cfg.LIBDISCID)"
    }
    if (-not ("DiscidNative" -as [type])) {
        $code = @"
using System;
using System.Runtime.InteropServices;

public static class DiscidNative
{
    [DllImport("kernel32", CharSet = CharSet.Unicode, SetLastError = true)]
    public static extern IntPtr LoadLibrary(string lpFileName);

    [DllImport("discid", CallingConvention = CallingConvention.Cdecl)]
    public static extern IntPtr discid_new();

    [DllImport("discid", CallingConvention = CallingConvention.Cdecl)]
    public static extern int discid_read_sparse(IntPtr disc, string device, int features);

    [DllImport("discid", CallingConvention = CallingConvention.Cdecl)]
    public static extern IntPtr discid_get_id(IntPtr disc);

    [DllImport("discid", CallingConvention = CallingConvention.Cdecl)]
    public static extern void discid_free(IntPtr disc);
}
"@
        Add-Type -TypeDefinition $code -Language CSharp
    }
    $loaded = [DiscidNative]::LoadLibrary($cfg.LIBDISCID)
    if ($loaded -eq [IntPtr]::Zero) {
        throw "Failed to load discid.dll from: $($cfg.LIBDISCID)"
    }
}

function Get-DiscId {
    $cfg = $global:sync.Cfg
    Initialize-LibDiscid
    $disc = [DiscidNative]::discid_new()
    if ($disc -eq [IntPtr]::Zero) { throw "discid_new() failed." }
    try {
        $ok = [DiscidNative]::discid_read_sparse($disc, $cfg.CdDrive, 0)
        if ($ok -eq 0) { throw "libdiscid could not read the disc from device '$($cfg.CdDrive)'." }
        $ptr = [Runtime.InteropServices.Marshal]::PtrToStringAnsi([DiscidNative]::discid_get_id($disc))
        $id  = [string]$ptr
        if ([string]::IsNullOrWhiteSpace($id)) { throw "libdiscid returned an empty disc ID." }
        return $id
    }
    finally {
        [DiscidNative]::discid_free($disc)
    }
}

function ConvertFrom-MBRelease {
    param([Parameter(Mandatory)] $rel)
    $artist = ""
    if ($rel.'artist-credit' -and $rel.'artist-credit'.Count -gt 0) {
        $artist = $rel.'artist-credit'[0].name
    }
    $tracks = @()
    if ($rel.media) {
        foreach ($m in $rel.media) {
            if ($m.tracks) {
                foreach ($t in $m.tracks) {
                    if ($t.title) { $tracks += $t.title }
                    elseif ($t.recording -and $t.recording.title) { $tracks += $t.recording.title }
                }
            }
        }
    }
    return @{
        Album = @{
            Artist    = $artist
            Album     = $rel.title
            Year      = if ($rel.date) { ($rel.date -split "-")[0] } else { "" }
            Genre     = ""
            DiscTitle = $rel.title
            Performer = $artist
        }
        Tracks = $tracks
    }
}

function Get-MBMetadata {
    param([Parameter(Mandatory)] [string]$discId)
    $cfg = $global:sync.Cfg
    $encoded = [uri]::EscapeDataString($discId)
    $url = "https://musicbrainz.org/ws/2/discid/$encoded`?inc=aliases+artist-credits+labels+discids+recordings&fmt=json"
    Send-Log "Querying MusicBrainz disc endpoint..." "Dim"
    Start-Sleep -Milliseconds 1100
    $r = Invoke-RestMethod -Uri $url -Headers @{ "User-Agent" = $cfg.UserAgent; "Accept" = "application/json" } -TimeoutSec 20
    if (-not $r.releases) { return $null }
    return (ConvertFrom-MBRelease $r.releases[0])
}

function Search-MBRelease {
    param([Parameter(Mandatory)] [string]$Artist, [Parameter(Mandatory)] [string]$Album)
    $cfg = $global:sync.Cfg
    $query = [uri]::EscapeDataString("artist:`"$Artist`" AND release:`"$Album`"")
    $url = "https://musicbrainz.org/ws/2/release?query=$query&fmt=json&limit=10"
    Start-Sleep -Milliseconds 1100
    $r = Invoke-RestMethod -Uri $url -Headers @{ "User-Agent" = $cfg.UserAgent; "Accept" = "application/json" } -TimeoutSec 20
    if (-not $r.releases -or $r.releases.Count -lt 1) { return $null }
    return $r.releases
}

function Get-MBMetadataByReleaseId {
    param([Parameter(Mandatory)] [string]$ReleaseId)
    $cfg = $global:sync.Cfg
    $encoded = [uri]::EscapeDataString($ReleaseId)
    $url = "https://musicbrainz.org/ws/2/release/$encoded`?inc=aliases+artist-credits+labels+discids+recordings&fmt=json"
    Send-Log "Querying MusicBrainz release endpoint..." "Dim"
    Start-Sleep -Milliseconds 1100
    $rel = Invoke-RestMethod -Uri $url -Headers @{ "User-Agent" = $cfg.UserAgent; "Accept" = "application/json" } -TimeoutSec 20
    return (ConvertFrom-MBRelease $rel)
}

function Probe-Disc {
    $cfg = $global:sync.Cfg
    $logRoot = Join-Path $cfg.RipRoot "logs"
    $tempRoot = Join-Path $cfg.RipRoot "temp"
    foreach ($d in @($cfg.RipRoot, $logRoot, $tempRoot)) {
        if (-not (Test-Path $d)) { New-Item -ItemType Directory -Force -Path $d | Out-Null }
    }
    $logPath = Join-Path $logRoot "cdda2wav_probe.log"
    if (Test-Path $logPath) { Remove-Item $logPath -Force -ErrorAction SilentlyContinue }
    New-Item -ItemType File -Path $logPath -Force | Out-Null
    Write-ToolLog -Path $logPath -Message "EXE: $($cfg.CDDA2WAV)"
    Write-ToolLog -Path $logPath -Message "ARGS: -D $($cfg.CddaDevice) -J"
    Push-Location $tempRoot
    try {
        & $cfg.CDDA2WAV -D $cfg.CddaDevice -J 2>&1 | Tee-Object -FilePath $logPath -Append | Out-Null
        $exitCode = $LASTEXITCODE
    }
    finally { Pop-Location }
    Write-ToolLog -Path $logPath -Message "EXIT CODE: $exitCode"
    if ($exitCode -ne 0) { throw "Failed to probe disc." }
    return $logPath
}

function Resolve-TrackCountFromRipLog {
    param([Parameter(Mandatory)] [string]$LogPath)
    $lines = Get-Content -Path $LogPath | ForEach-Object { $_ -replace "`0", "" }
    foreach ($line in $lines) {
        if ($line -match 'total tracks:\s*(\d+)') { return [int]$Matches[1] }
        if ($line -match 'tracks?\s*[:=]\s*(\d+)\s*[-–]\s*(\d+)') { return ([int]$Matches[2] - [int]$Matches[1] + 1) }
        if ($line -match '\b(\d+)\s+audio\s+tracks?\b') { return [int]$Matches[1] }
    }
    throw "Could not determine track count from rip log. Check $LogPath."
}

function Get-StartSectorsFromRipLog {
    param([Parameter(Mandatory)] [string]$LogPath, [Parameter(Mandatory)] [int]$TrackCount)
    $lines = Get-Content -Path $LogPath | ForEach-Object { $_ -replace "`0", "" }
    $startIndex = -1
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match 'Table of Contents:\s*starting sectors') { $startIndex = $i; break }
    }
    if ($startIndex -lt 0) { throw "Could not find 'starting sectors' section in rip log." }
    $sectorText = ""
    for ($i = $startIndex + 1; $i -lt $lines.Count; $i++) {
        $sectorText += " " + $lines[$i]
        if ($lines[$i] -match 'lead-out') { break }
    }
    $matches = [regex]::Matches($sectorText, '\d+\.\(\s*(\d+)\)')
    if ($matches.Count -lt $TrackCount) {
        throw "Could not parse enough start sectors. Expected $TrackCount, found $($matches.Count)."
    }
    $sectors = New-Object System.Collections.Generic.List[int]
    for ($i = 0; $i -lt $TrackCount; $i++) { [void]$sectors.Add([int]$matches[$i].Groups[1].Value) }
    return $sectors.ToArray()
}

function Rip-Wav {
    param($out)
    $cfg = $global:sync.Cfg
    $logRoot = Join-Path $cfg.RipRoot "logs"
    Send-Log "Ripping disc to WAV image..." "Info"
    $logPath = Join-Path $logRoot "cdda2wav_rip.log"
    if (Test-Path $logPath) { Remove-Item $logPath -Force -ErrorAction SilentlyContinue }
    New-Item -ItemType File -Path $logPath -Force | Out-Null
    Write-ToolLog -Path $logPath -Message "EXE: $($cfg.CDDA2WAV)"
    Write-ToolLog -Path $logPath -Message "ARGS: -D $($cfg.CddaDevice) -O wav $out"
    & $cfg.CDDA2WAV -D $cfg.CddaDevice -O wav $out 2>&1 | Tee-Object -FilePath $logPath -Append | Out-Null
    Write-ToolLog -Path $logPath -Message "EXIT CODE: $LASTEXITCODE"
    Write-ToolLog -Path $logPath -Message "WAV EXISTS: $(Test-Path $out)"
    return $LASTEXITCODE
}

function Encode-Flac {
    param($wav, $flac, $meta)
    $cfg = $global:sync.Cfg
    $logRoot = Join-Path $cfg.RipRoot "logs"
    Send-Log "Encoding FLAC image..." "Info"
    $logPath = Join-Path $logRoot "flac_encode.log"
    if (Test-Path $logPath) { Remove-Item $logPath -Force -ErrorAction SilentlyContinue }
    New-Item -ItemType File -Path $logPath -Force | Out-Null
    $flacArgs = @(
        "-8", "--verify",
        "--tag=ARTIST=$($meta.Artist)",
        "--tag=ALBUM=$($meta.Album)",
        "--tag=DATE=$($meta.Year)",
        "--tag=GENRE=$($meta.Genre)",
        "--output-name=$flac",
        $wav
    )
    Write-ToolLog -Path $logPath -Message "EXE: $($cfg.FLAC)"
    Write-ToolLog -Path $logPath -Message "ARGS: $($flacArgs -join ' ')"
    & $cfg.FLAC @flacArgs 2>&1 | Tee-Object -FilePath $logPath -Append | Out-Null
    Write-ToolLog -Path $logPath -Message "EXIT CODE: $LASTEXITCODE"
    return $LASTEXITCODE
}

function Rip-TrackWav {
    param([Parameter(Mandatory)] [int]$TrackNumber, [Parameter(Mandatory)] [string]$OutPath)
    $cfg = $global:sync.Cfg
    $logRoot = Join-Path $cfg.RipRoot "logs"
    $logPath = Join-Path $logRoot ("cdda2wav_track_{0:D2}.log" -f $TrackNumber)
    if (Test-Path $logPath) { Remove-Item $logPath -Force -ErrorAction SilentlyContinue }
    New-Item -ItemType File -Path $logPath -Force | Out-Null
    Write-ToolLog -Path $logPath -Message "EXE: $($cfg.CDDA2WAV)"
    Write-ToolLog -Path $logPath -Message "ARGS: -D $($cfg.CddaDevice) -t $TrackNumber -O wav $OutPath"
    & $cfg.CDDA2WAV -D $cfg.CddaDevice -t "$TrackNumber" -O wav $OutPath 2>&1 | Tee-Object -FilePath $logPath -Append | Out-Null
    Write-ToolLog -Path $logPath -Message "EXIT CODE: $LASTEXITCODE"
    Write-ToolLog -Path $logPath -Message "WAV EXISTS: $(Test-Path $OutPath)"
    return $LASTEXITCODE
}

function Encode-TrackFlac {
    param(
        [Parameter(Mandatory)] [string]$WavPath,
        [Parameter(Mandatory)] [string]$FlacPath,
        [Parameter(Mandatory)] [hashtable]$AlbumInfo,
        [Parameter(Mandatory)] [string]$TrackTitle,
        [Parameter(Mandatory)] [int]$TrackNumber
    )
    $cfg = $global:sync.Cfg
    $logRoot = Join-Path $cfg.RipRoot "logs"
    $logPath = Join-Path $logRoot ("flac_track_{0:D2}.log" -f $TrackNumber)
    if (Test-Path $logPath) { Remove-Item $logPath -Force -ErrorAction SilentlyContinue }
    New-Item -ItemType File -Path $logPath -Force | Out-Null
    $flacArgs = @(
        "-8", "--verify",
        "--tag=ARTIST=$($AlbumInfo.Artist)",
        "--tag=ALBUM=$($AlbumInfo.Album)",
        "--tag=TITLE=$TrackTitle",
        "--tag=TRACKNUMBER=$TrackNumber",
        "--tag=DATE=$($AlbumInfo.Year)",
        "--tag=GENRE=$($AlbumInfo.Genre)",
        "--output-name=$FlacPath",
        $WavPath
    )
    Write-ToolLog -Path $logPath -Message "EXE: $($cfg.FLAC)"
    Write-ToolLog -Path $logPath -Message "ARGS: $($flacArgs -join ' ')"
    & $cfg.FLAC @flacArgs 2>&1 | Tee-Object -FilePath $logPath -Append | Out-Null
    Write-ToolLog -Path $logPath -Message "EXIT CODE: $LASTEXITCODE"
    return $LASTEXITCODE
}

function Embed-Cue {
    param($flac, $cue)
    $cfg = $global:sync.Cfg
    if ([string]::IsNullOrWhiteSpace($cfg.METAFLAC) -or -not (Test-Path $cfg.METAFLAC)) {
        Send-Log "metaflac not found; skipping embedded cuesheet." "Warn"
        return
    }
    Send-Log "Embedding cuesheet into FLAC..." "Info"
    & $cfg.METAFLAC "--import-cuesheet-from=$cue" $flac | Out-Null
}

function Embed-Cover {
    param($flac, $img)
    $cfg = $global:sync.Cfg
    if (-not (Test-Path $img)) { Send-Log "Cover not found, skipping." "Warn"; return }
    if ([string]::IsNullOrWhiteSpace($cfg.METAFLAC) -or -not (Test-Path $cfg.METAFLAC)) {
        Send-Log "metaflac not found; skipping cover art embed." "Warn"
        return
    }
    Send-Log "Embedding cover art..." "Info"
    & $cfg.METAFLAC --remove --block-type=PICTURE $flac 2>$null | Out-Null
    & $cfg.METAFLAC --import-picture-from="$img" $flac 2>&1 | Out-Null
    if ($LASTEXITCODE -eq 0) { Send-Log "Cover art embedded." "Good" }
    else { Send-Log "Cover embed failed." "Bad" }
}

function Write-CueSheet {
    param(
        [Parameter(Mandatory)] [string]$CuePath,
        [Parameter(Mandatory)] [string]$AudioFileName,
        [Parameter(Mandatory)] [hashtable]$AlbumInfo,
        [Parameter(Mandatory)] [string[]]$TrackTitles,
        [Parameter(Mandatory)] [int[]]$StartSectors
    )
    if ($TrackTitles.Count -ne $StartSectors.Count) {
        throw "Track title count ($($TrackTitles.Count)) does not match start sector count ($($StartSectors.Count))."
    }
    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add("REM GENERATED BY POWERSHELL")
    if (-not [string]::IsNullOrWhiteSpace($AlbumInfo.Year))  { $lines.Add("REM DATE $($AlbumInfo.Year)") }
    if (-not [string]::IsNullOrWhiteSpace($AlbumInfo.Genre)) { $lines.Add("REM GENRE $($AlbumInfo.Genre)") }
    $lines.Add('PERFORMER "' + (Escape-CueText $AlbumInfo.Performer) + '"')
    $lines.Add('TITLE "'     + (Escape-CueText $AlbumInfo.DiscTitle) + '"')
    $lines.Add('FILE "'      + (Escape-CueText $AudioFileName) + '" WAVE')
    for ($i = 0; $i -lt $TrackTitles.Count; $i++) {
        [int]$trackNum = $i + 1
        $title  = Escape-CueText $TrackTitles[$i]
        [int]$sector = $StartSectors[$i]
        [int]$minutes = [math]::Floor($sector / 4500)
        [int]$seconds = [math]::Floor(($sector % 4500) / 75)
        [int]$frames  = $sector % 75
        $index01 = "{0:D2}:{1:D2}:{2:D2}" -f $minutes, $seconds, $frames
        $lines.Add(("  TRACK {0:D2} AUDIO" -f $trackNum))
        $lines.Add('    TITLE "' + $title + '"')
        $lines.Add('    PERFORMER "' + (Escape-CueText $AlbumInfo.Performer) + '"')
        $lines.Add("    INDEX 01 $index01")
    }
    [System.IO.File]::WriteAllLines($CuePath, $lines, [System.Text.Encoding]::ASCII)
}

function Save-ImageJson {
    param($JsonPath, $AlbumInfo, [string[]]$TrackTitles, [int[]]$StartSectors, $FlacFileName, $CueFileName, $DiscId)
    $trackObjects = @()
    for ($i = 0; $i -lt $TrackTitles.Count; $i++) {
        $trackObjects += [PSCustomObject]@{ number = $i + 1; title = $TrackTitles[$i]; sector = $StartSectors[$i] }
    }
    $payload = [PSCustomObject]@{
        discId = $DiscId; artist = $AlbumInfo.Artist; album = $AlbumInfo.Album
        year = $AlbumInfo.Year; genre = $AlbumInfo.Genre; discTitle = $AlbumInfo.DiscTitle
        performer = $AlbumInfo.Performer; flacFile = $FlacFileName; cueFile = $CueFileName; tracks = $trackObjects
    }
    $payload | ConvertTo-Json -Depth 5 | Set-Content -Path $JsonPath -Encoding UTF8
}

function Save-TracksJson {
    param($JsonPath, $AlbumInfo, [string[]]$TrackTitles, [string[]]$FlacFiles, $DiscId)
    $trackObjects = @()
    for ($i = 0; $i -lt $TrackTitles.Count; $i++) {
        $fileName = if ($i -lt $FlacFiles.Count) { $FlacFiles[$i] } else { "" }
        $trackObjects += [PSCustomObject]@{ number = $i + 1; title = $TrackTitles[$i]; flacFile = $fileName }
    }
    $payload = [PSCustomObject]@{
        discId = $DiscId; artist = $AlbumInfo.Artist; album = $AlbumInfo.Album
        year = $AlbumInfo.Year; genre = $AlbumInfo.Genre; discTitle = $AlbumInfo.DiscTitle
        performer = $AlbumInfo.Performer; tracks = $trackObjects
    }
    $payload | ConvertTo-Json -Depth 5 | Set-Content -Path $JsonPath -Encoding UTF8
}

# ── Operation entry points ──────────────────
function Invoke-Detect {
    Test-WorkerTools -RequireRip -WarnMetadataTools

    $discId = ""
    $artist = ""; $album = ""; $year = ""; $genre = ""
    $tracks = @()
    $trackCount = 0

    try {
        $discId = Get-DiscId
        Send-Log "DiscID: $discId" "Info"
    } catch {
        Send-Log "DiscID read failed: $($_.Exception.Message)" "Warn"
    }

    if ($discId) {
        try {
            $lookup = Get-MBMetadata $discId
            if ($lookup) {
                $artist = $lookup.Album.Artist
                $album  = $lookup.Album.Album
                $year   = $lookup.Album.Year
                $genre  = $lookup.Album.Genre
                $tracks = $lookup.Tracks
                Send-Log "MusicBrainz match: $artist - $album ($($tracks.Count) tracks)" "Good"
            } else {
                Send-Log "No exact MusicBrainz disc match found." "Warn"
            }
        } catch {
            Send-Log "Disc lookup failed: $($_.Exception.Message)" "Warn"
        }
    }

    try {
        $probeLog = Probe-Disc
        $trackCount = Resolve-TrackCountFromRipLog -LogPath $probeLog
        Send-Log "Disc reports $trackCount tracks." "Good"
    } catch {
        Send-Log "Disc probe failed: $($_.Exception.Message)" "Warn"
    }

    return @{
        DiscId = $discId; Artist = $artist; Album = $album; Year = $year; Genre = $genre
        Tracks = $tracks; TrackCount = $trackCount
    }
}

function Invoke-Search {
    $job = $global:sync.Job
    $results = Search-MBRelease -Artist $job.SearchArtist -Album $job.SearchAlbum
    if (-not $results) { Send-Log "No MusicBrainz text matches found." "Warn"; return @() }
    $list = @()
    foreach ($rel in $results) {
        $a = ""
        if ($rel.'artist-credit' -and $rel.'artist-credit'.Count -gt 0) { $a = $rel.'artist-credit'[0].name }
        $list += [PSCustomObject]@{
            Id = $rel.id; Artist = $a; Title = $rel.title
            Date = if ($rel.date) { $rel.date } else { "" }
            Country = if ($rel.country) { $rel.country } else { "" }
        }
    }
    Send-Log "Found $($list.Count) candidate release(s)." "Good"
    return $list
}

function Invoke-Release {
    $job = $global:sync.Job
    $lookup = Get-MBMetadataByReleaseId -ReleaseId $job.ReleaseId
    if (-not $lookup) { return $null }
    return @{
        DiscId = ""; Artist = $lookup.Album.Artist; Album = $lookup.Album.Album
        Year = $lookup.Album.Year; Genre = $lookup.Album.Genre
        Tracks = $lookup.Tracks; TrackCount = $lookup.Tracks.Count
    }
}

function Invoke-Rip {
    Test-WorkerTools -RequireRip -RequireEncode -WarnMetadataTools

    $cfg = $global:sync.Cfg
    $job = $global:sync.Job

    $tempRoot = Join-Path $cfg.RipRoot "temp"
    $logRoot  = Join-Path $cfg.RipRoot "logs"
    foreach ($d in @($cfg.RipRoot, $tempRoot, $logRoot)) {
        if (-not (Test-Path $d)) { New-Item -ItemType Directory -Force -Path $d | Out-Null }
    }

    $albumInfo = @{
        Artist = $job.Artist; Album = $job.Album; Year = $job.Year; Genre = $job.Genre
        DiscTitle = $job.Album; Performer = $job.Artist
    }
    $tracks = $job.Tracks
    $artistSafe = Get-SafeName $albumInfo.Artist
    $albumSafe  = Get-SafeName $albumInfo.Album

    if ($job.Mode -eq "image") {
        $imageRoot = Join-Path $cfg.RipRoot "image"
        $dir = Join-Path $imageRoot "$artistSafe\$albumSafe"
        New-Item -ItemType Directory -Force -Path $dir | Out-Null

        $base = "$artistSafe - $albumSafe"
        $wav  = Join-Path $tempRoot "$base.wav"
        $flac = Join-Path $dir "$base.flac"
        $flacWork = "${flac}.__encoding__.tmp.flac"
        $cue  = Join-Path $dir "$base.cue"
        $json = Join-Path $dir "album.json"
        $ripLog = Join-Path $logRoot "cdda2wav_rip.log"

        foreach ($f in @($wav, $flac, $flacWork, $cue, $json)) {
            if (Test-Path $f) { Remove-Item $f -Force -ErrorAction SilentlyContinue }
        }

        if ((Rip-Wav $wav) -ne 0 -or -not (Test-Path $wav)) { Send-Log "WAV rip failed or output was missing." "Bad"; return }
        if ((Encode-Flac $wav $flacWork $albumInfo) -ne 0) { Send-Log "FLAC encode failed." "Bad"; return }

        try {
            Publish-ValidatedAudioFile -TempPath $flacWork -FinalPath $flac
            Send-Log "Validated FLAC image output." "Good"
        } catch {
            Send-Log "FLAC validation/publish failed: $($_.Exception.Message)" "Bad"; return
        }

        try {
            [int[]]$startSectors = Get-StartSectorsFromRipLog -LogPath $ripLog -TrackCount $tracks.Count
            Send-Log "Parsed $($startSectors.Count) start sectors." "Info"
        } catch {
            Send-Log "Failed to parse track offsets: $($_.Exception.Message)" "Bad"; return
        }

        try {
            Write-CueSheet -CuePath $cue -AudioFileName ([System.IO.Path]::GetFileName($flac)) `
                           -AlbumInfo $albumInfo -TrackTitles $tracks -StartSectors $startSectors
            Send-Log "Wrote CUE sheet." "Good"
        } catch {
            Send-Log "CUE creation failed: $($_.Exception.Message)" "Bad"; return
        }

        try {
            Save-ImageJson -JsonPath $json -AlbumInfo $albumInfo -TrackTitles $tracks -StartSectors $startSectors `
                           -FlacFileName ([System.IO.Path]::GetFileName($flac)) -CueFileName ([System.IO.Path]::GetFileName($cue)) -DiscId $job.DiscId
            Send-Log "Saved metadata sidecar." "Good"
        } catch {
            Send-Log "Failed to save JSON: $($_.Exception.Message)" "Warn"
        }

        Embed-Cue $flac $cue
        if ($job.Cover -and (Test-Path $job.Cover)) { Embed-Cover $flac $job.Cover }

        Send-Log "Done." "Good"
        Send-Log "FLAC: $flac" "Dim"
        Send-Log "CUE : $cue"  "Dim"
        $global:sync.OutputDir = $dir
    }
    else {
        $trackRoot = Join-Path $cfg.RipRoot "tracks"
        $albumDir = Join-Path $trackRoot "$artistSafe\$albumSafe"
        New-Item -ItemType Directory -Force -Path $albumDir | Out-Null
        $json = Join-Path $albumDir "album.json"

        $flacFiles = New-Object System.Collections.Generic.List[string]
        $failedTracks = New-Object System.Collections.Generic.List[int]
        for ($i = 0; $i -lt $tracks.Count; $i++) {
            $trackNum = $i + 1
            $trackTitle = $tracks[$i]
            $safeTitle = Get-SafeName $trackTitle
            $wavPath  = Join-Path $tempRoot ("{0:D2} - {1}.wav"  -f $trackNum, $safeTitle)
            $flacPath = Join-Path $albumDir ("{0:D2} - {1}.flac" -f $trackNum, $safeTitle)
            $flacWork = "${flacPath}.__encoding__.tmp.flac"
            foreach ($f in @($wavPath, $flacPath, $flacWork)) {
                if (Test-Path $f) { Remove-Item $f -Force -ErrorAction SilentlyContinue }
            }

            Send-Log ("Ripping track {0:D2}: {1}" -f $trackNum, $trackTitle) "Info"
            $ripCode = Rip-TrackWav -TrackNumber $trackNum -OutPath $wavPath
            if ($ripCode -ne 0 -or -not (Test-Path $wavPath)) {
                Send-Log ("Failed to rip track {0:D2}" -f $trackNum) "Bad"; [void]$failedTracks.Add($trackNum); continue
            }

            Send-Log ("Encoding track {0:D2}: {1}" -f $trackNum, $trackTitle) "Info"
            $encCode = Encode-TrackFlac -WavPath $wavPath -FlacPath $flacWork -AlbumInfo $albumInfo -TrackTitle $trackTitle -TrackNumber $trackNum
            if ($encCode -ne 0) {
                Send-Log ("Failed to encode track {0:D2}" -f $trackNum) "Bad"; [void]$failedTracks.Add($trackNum); continue
            }

            try {
                Publish-ValidatedAudioFile -TempPath $flacWork -FinalPath $flacPath
            } catch {
                Send-Log ("Track {0:D2} validation/publish failed: {1}" -f $trackNum, $_.Exception.Message) "Bad"; [void]$failedTracks.Add($trackNum); continue
            }

            if ($job.Cover -and (Test-Path $job.Cover)) { Embed-Cover $flacPath $job.Cover }
            Remove-Item $wavPath -Force -ErrorAction SilentlyContinue
            [void]$flacFiles.Add([System.IO.Path]::GetFileName($flacPath))
            Send-Log ("Created {0:D2} - {1}.flac" -f $trackNum, $trackTitle) "Good"
        }

        if ($failedTracks.Count -gt 0 -or $flacFiles.Count -ne $tracks.Count) {
            Send-Log ("CD track rip finished with failures. Expected {0}, created {1}. Failed tracks: {2}" -f $tracks.Count, $flacFiles.Count, ($failedTracks -join ', ')) "Bad"
        }

        try {
            Save-TracksJson -JsonPath $json -AlbumInfo $albumInfo -TrackTitles $tracks -FlacFiles $flacFiles.ToArray() -DiscId $job.DiscId
            Send-Log "Saved metadata sidecar." "Good"
        } catch {
            Send-Log "Failed to save JSON: $($_.Exception.Message)" "Warn"
        }

        if ($failedTracks.Count -gt 0 -or $flacFiles.Count -ne $tracks.Count) {
            Send-Log "Finished with errors. Check logs before using this rip." "Bad"
        }
        else {
            Send-Log "Done." "Good"
        }
        Send-Log "TRACK DIR: $albumDir" "Dim"
        $global:sync.OutputDir = $albumDir
    }
}
'@

# ── Theme ───────────────────────────────────
$clrBack    = [System.Drawing.Color]::FromArgb(30, 30, 30)
$clrPanel   = [System.Drawing.Color]::FromArgb(37, 37, 38)
$clrInput   = [System.Drawing.Color]::FromArgb(51, 51, 55)
$clrText    = [System.Drawing.Color]::FromArgb(220, 220, 220)
$clrAccent  = [System.Drawing.Color]::FromArgb(78, 201, 176)   # teal
$clrBtn     = [System.Drawing.Color]::FromArgb(14, 99, 156)    # blue
$clrBtnGo   = [System.Drawing.Color]::FromArgb(34, 134, 94)    # green
$clrGood    = [System.Drawing.Color]::FromArgb(78, 201, 176)
$clrInfo    = [System.Drawing.Color]::FromArgb(156, 220, 254)
$clrWarn    = [System.Drawing.Color]::FromArgb(220, 220, 170)
$clrBad     = [System.Drawing.Color]::FromArgb(244, 135, 113)
$clrDim     = [System.Drawing.Color]::FromArgb(140, 140, 140)
$fontUI     = New-Object System.Drawing.Font("Segoe UI", 9)
$fontMono   = New-Object System.Drawing.Font("Consolas", 9)
$fontHead   = New-Object System.Drawing.Font("Segoe UI Semibold", 15)

# ── Control factory helpers ─────────────────
function New-Label {
    param($Text, $X, $Y, $W = 90)
    $l = New-Object System.Windows.Forms.Label
    $l.Text = $Text; $l.Location = "$X,$Y"; $l.Size = "$W,22"
    $l.ForeColor = $clrText; $l.Font = $fontUI
    $l.TextAlign = "MiddleLeft"
    return $l
}
function New-Text {
    param($X, $Y, $W, $Val = "")
    $t = New-Object System.Windows.Forms.TextBox
    $t.Location = "$X,$Y"; $t.Size = "$W,23"; $t.Text = $Val
    $t.BackColor = $clrInput; $t.ForeColor = $clrText
    $t.BorderStyle = "FixedSingle"; $t.Font = $fontUI
    return $t
}
function New-Button {
    param($Text, $X, $Y, $W, $H = 28, $Color = $clrBtn)
    $b = New-Object System.Windows.Forms.Button
    $b.Text = $Text; $b.Location = "$X,$Y"; $b.Size = "$W,$H"
    $b.BackColor = $Color; $b.ForeColor = [System.Drawing.Color]::White
    $b.FlatStyle = "Flat"; $b.FlatAppearance.BorderSize = 0; $b.Font = $fontUI
    $b.Cursor = "Hand"
    return $b
}
function New-Group {
    param($Text, $X, $Y, $W, $H)
    $g = New-Object System.Windows.Forms.GroupBox
    $g.Text = $Text; $g.Location = "$X,$Y"; $g.Size = "$W,$H"
    $g.ForeColor = $clrAccent; $g.BackColor = $clrPanel
    $g.Font = $fontUI
    return $g
}

# ── Form ────────────────────────────────────
$form = New-Object System.Windows.Forms.Form
$form.Text = "CD -> FLAC Ripper v1.1.0"
$form.Size = "1000,980"
$form.MinimumSize = "900,840"
$form.StartPosition = "CenterScreen"
$form.BackColor = $clrBack
$form.Font = $fontUI

# Header
$header = New-Object System.Windows.Forms.Panel
$header.Dock = "Top"; $header.Height = 52; $header.BackColor = $clrPanel
$hLabel = New-Object System.Windows.Forms.Label
$hLabel.Text = "  CD -> FLAC Ripper v1.1.0"; $hLabel.ForeColor = $clrAccent
$hLabel.Font = $fontHead; $hLabel.Dock = "Fill"; $hLabel.TextAlign = "MiddleLeft"
$header.Controls.Add($hLabel)
$form.Controls.Add($header)

$W = 964   # inner content width baseline


# ── Default paths ───────────────────────────
$defaultRipRoot = "G:\Rip\CD"
$defaultCdda2Wav = "C:\Program Files (x86)\cdrtfe\tools\cdrtools\cdda2wav.exe"
$defaultFlac = Join-Path $HOME "Apps\FLAC\flac.exe"
$defaultMetaFlac = Join-Path $HOME "Apps\FLAC\metaflac.exe"
$defaultLibDiscid = Join-Path $HOME "Apps\libdiscid\discid.dll"

# ── Group: Tools & Paths ────────────────────
$gPaths = New-Group "Tools and Paths" 8 60 $W 178
$gPaths.Anchor = "Top,Left,Right"

$gPaths.Controls.Add((New-Label "CD Drive" 14 26 64))
$txtDrive = New-Text 80 25 70 "D:"; $gPaths.Controls.Add($txtDrive)
$gPaths.Controls.Add((New-Label "CDDA Dev" 170 26 70))
$txtDevice = New-Text 242 25 80 "0,0,0"; $gPaths.Controls.Add($txtDevice)
$gPaths.Controls.Add((New-Label "Rip Root" 342 26 60))
$txtRipRoot = New-Text 404 25 460 $defaultRipRoot; $txtRipRoot.Anchor = "Top,Left,Right"; $gPaths.Controls.Add($txtRipRoot)
$btnRipRoot = New-Button "..." 868 24 32 24; $btnRipRoot.Anchor = "Top,Right"; $gPaths.Controls.Add($btnRipRoot)

$pathRows = @(
    @{ Lbl="cdda2wav";  Var="txtCdda";  Def=$defaultCdda2Wav },
    @{ Lbl="flac";      Var="txtFlac";  Def=$defaultFlac },
    @{ Lbl="metaflac";  Var="txtMeta";  Def=$defaultMetaFlac },
    @{ Lbl="libdiscid"; Var="txtDisc";  Def=$defaultLibDiscid }
)
$y = 58
foreach ($row in $pathRows) {
    $gPaths.Controls.Add((New-Label $row.Lbl 14 ($y+2) 66))
    $tb = New-Text 80 ($y+1) 752 $row.Def; $tb.Anchor = "Top,Left,Right"
    $gPaths.Controls.Add($tb)
    Set-Variable -Name $row.Var -Value $tb
    $bb = New-Button "..." 836 $y 32 24; $bb.Anchor = "Top,Right"
    $tbRef = $tb
    $bb.Add_Click({
        $dlg = New-Object System.Windows.Forms.OpenFileDialog
        if ($dlg.ShowDialog() -eq "OK") { $tbRef.Text = $dlg.FileName }
    }.GetNewClosure())
    $gPaths.Controls.Add($bb)
    $y += 28
}
$form.Controls.Add($gPaths)

# ── Group: Disc & Metadata ──────────────────
$gMeta = New-Group "Disc and Metadata" 8 244 $W 196
$gMeta.Anchor = "Top,Left,Right"

$btnDetect = New-Button "Detect Disc (MusicBrainz)" 14 24 200 30 $clrBtn
$gMeta.Controls.Add($btnDetect)
$lblDiscId = New-Label "DiscID: -" 226 28 700; $lblDiscId.ForeColor = $clrDim
$lblDiscId.Anchor = "Top,Left,Right"; $gMeta.Controls.Add($lblDiscId)

$gMeta.Controls.Add((New-Label "Artist" 14 66 50))
$txtArtist = New-Text 66 65 330; $gMeta.Controls.Add($txtArtist)
$gMeta.Controls.Add((New-Label "Album" 410 66 46))
$txtAlbum = New-Text 458 65 490; $txtAlbum.Anchor = "Top,Left,Right"; $gMeta.Controls.Add($txtAlbum)

$gMeta.Controls.Add((New-Label "Year" 14 96 50))
$txtYear = New-Text 66 95 90; $gMeta.Controls.Add($txtYear)
$gMeta.Controls.Add((New-Label "Genre" 170 96 44))
$txtGenre = New-Text 216 95 180; $gMeta.Controls.Add($txtGenre)

# MusicBrainz text search row
$gMeta.Controls.Add((New-Label "MB Search" 14 134 70))
$txtSearchArtist = New-Text 88 133 180; $txtSearchArtist.Text = ""; $gMeta.Controls.Add($txtSearchArtist)
$lblSA = New-Label "artist" 88 156 180; $lblSA.ForeColor = $clrDim; $lblSA.Font = (New-Object System.Drawing.Font("Segoe UI",7)); $gMeta.Controls.Add($lblSA)
$txtSearchAlbum = New-Text 274 133 180; $gMeta.Controls.Add($txtSearchAlbum)
$lblSB = New-Label "album" 274 156 180; $lblSB.ForeColor = $clrDim; $lblSB.Font = (New-Object System.Drawing.Font("Segoe UI",7)); $gMeta.Controls.Add($lblSB)
$btnSearch = New-Button "Search" 460 132 80 26; $gMeta.Controls.Add($btnSearch)
$cmbResults = New-Object System.Windows.Forms.ComboBox
$cmbResults.Location = "548,133"; $cmbResults.Size = "320,24"; $cmbResults.DropDownStyle = "DropDownList"
$cmbResults.BackColor = $clrInput; $cmbResults.ForeColor = $clrText; $cmbResults.Anchor = "Top,Left,Right"
$cmbResults.FlatStyle = "Flat"; $gMeta.Controls.Add($cmbResults)
$btnUseResult = New-Button "Use" 872 132 70 26; $btnUseResult.Anchor = "Top,Right"; $gMeta.Controls.Add($btnUseResult)
$form.Controls.Add($gMeta)

# ── Group: Tracks ───────────────────────────
$gTracks = New-Group "Tracks" 8 446 $W 188
$gTracks.Anchor = "Top,Left,Right"

$grid = New-Object System.Windows.Forms.DataGridView
$grid.Location = "14,24"; $grid.Size = "830,150"; $grid.Anchor = "Top,Left,Right,Bottom"
$grid.BackgroundColor = $clrPanel; $grid.ForeColor = $clrText
$grid.GridColor = [System.Drawing.Color]::FromArgb(64,64,64)
$grid.BorderStyle = "None"; $grid.EnableHeadersVisualStyles = $false
$grid.AllowUserToResizeRows = $false; $grid.RowHeadersVisible = $false
$grid.SelectionMode = "FullRowSelect"; $grid.AllowUserToAddRows = $false
$grid.ColumnHeadersDefaultCellStyle.BackColor = $clrInput
$grid.ColumnHeadersDefaultCellStyle.ForeColor = $clrAccent
$grid.ColumnHeadersDefaultCellStyle.Font = (New-Object System.Drawing.Font("Segoe UI Semibold",9))
$grid.DefaultCellStyle.BackColor = $clrPanel
$grid.DefaultCellStyle.ForeColor = $clrText
$grid.DefaultCellStyle.SelectionBackColor = $clrBtn
$grid.DefaultCellStyle.SelectionForeColor = [System.Drawing.Color]::White
$grid.AlternatingRowsDefaultCellStyle.BackColor = [System.Drawing.Color]::FromArgb(43,43,46)
$grid.Font = $fontUI

$colNum = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
$colNum.HeaderText = "#"; $colNum.Width = 44; $colNum.ReadOnly = $true
$colNum.DefaultCellStyle.Alignment = "MiddleCenter"
$grid.Columns.Add($colNum) | Out-Null
$colTitle = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
$colTitle.HeaderText = "Title"; $colTitle.AutoSizeMode = "Fill"
$grid.Columns.Add($colTitle) | Out-Null
$gTracks.Controls.Add($grid)

$btnAddRow = New-Button "+ Add" 852 24 90 26; $btnAddRow.Anchor = "Top,Right"; $gTracks.Controls.Add($btnAddRow)
$btnDelRow = New-Button "- Remove" 852 56 90 26; $btnDelRow.Anchor = "Top,Right"; $gTracks.Controls.Add($btnDelRow)
$btnClrRows = New-Button "Clear" 852 88 90 26; $btnClrRows.Anchor = "Top,Right"; $gTracks.Controls.Add($btnClrRows)
$form.Controls.Add($gTracks)

# ── Group: Output ───────────────────────────
$gOut = New-Group "Output" 8 640 $W 96
$gOut.Anchor = "Top,Left,Right"

$rbImage = New-Object System.Windows.Forms.RadioButton
$rbImage.Text = "Single FLAC image + CUE"; $rbImage.Location = "14,26"; $rbImage.Size = "210,22"
$rbImage.ForeColor = $clrText; $rbImage.Checked = $true; $gOut.Controls.Add($rbImage)
$rbTracks = New-Object System.Windows.Forms.RadioButton
$rbTracks.Text = "One FLAC per track"; $rbTracks.Location = "240,26"; $rbTracks.Size = "180,22"
$rbTracks.ForeColor = $clrText; $gOut.Controls.Add($rbTracks)

$gOut.Controls.Add((New-Label "Cover" 14 60 44))
$txtCover = New-Text 62 59 800; $txtCover.Anchor = "Top,Left,Right"; $gOut.Controls.Add($txtCover)
$btnCover = New-Button "..." 868 58 32 24; $btnCover.Anchor = "Top,Right"; $gOut.Controls.Add($btnCover)
$form.Controls.Add($gOut)

# ── Action row ──────────────────────────────
$pAct = New-Object System.Windows.Forms.Panel
$pAct.Location = "8,742"; $pAct.Size = "$W,36"; $pAct.BackColor = $clrBack
$pAct.Anchor = "Top,Left,Right"
$btnStart = New-Button "Start Rip" 6 2 160 32 $clrBtnGo
$btnStart.Font = New-Object System.Drawing.Font("Segoe UI Semibold",10); $pAct.Controls.Add($btnStart)
$lblBusy = New-Label "" 176 6 400; $lblBusy.ForeColor = $clrWarn; $pAct.Controls.Add($lblBusy)
$btnOpen = New-Button "Open Output" 700 2 120 32 $clrBtn; $btnOpen.Anchor = "Top,Right"; $pAct.Controls.Add($btnOpen)
$btnClear = New-Button "Clear Log" 828 2 110 32 $clrBtn; $btnClear.Anchor = "Top,Right"; $pAct.Controls.Add($btnClear)
$form.Controls.Add($pAct)

# ── Log ─────────────────────────────────────
$gLog = New-Group "Log" 8 784 $W 150
$gLog.Anchor = "Top,Left,Right,Bottom"
$rtb = New-Object System.Windows.Forms.RichTextBox
$rtb.Location = "12,22"; $rtb.Size = "940,116"; $rtb.Anchor = "Top,Left,Right,Bottom"
$rtb.BackColor = [System.Drawing.Color]::FromArgb(24,24,24); $rtb.ForeColor = $clrText
$rtb.Font = $fontMono; $rtb.ReadOnly = $true; $rtb.BorderStyle = "None"
$gLog.Controls.Add($rtb)
$form.Controls.Add($gLog)

# ── UI helpers ──────────────────────────────
function Add-LogLine {
    param($text, $type)
    $color = switch ($type) {
        "Good" { $clrGood } "Warn" { $clrWarn } "Bad" { $clrBad } "Dim" { $clrDim } default { $clrInfo }
    }
    $rtb.SelectionStart = $rtb.TextLength; $rtb.SelectionLength = 0
    $rtb.SelectionColor = $color
    $rtb.AppendText($text + "`r`n")
    $rtb.SelectionColor = $rtb.ForeColor
    $rtb.ScrollToCaret()
}

function Renumber-Grid {
    for ($i = 0; $i -lt $grid.Rows.Count; $i++) {
        $grid.Rows[$i].Cells[0].Value = ("{0:D2}" -f ($i + 1))
    }
}

function Set-Tracks {
    param([string[]]$titles, [int]$count)
    $grid.Rows.Clear()

    if ($count -gt 0) {
        if ($titles -and $titles.Count -gt 0 -and $titles.Count -ne $count) {
            Add-LogLine ("Metadata track count ({0}) does not match disc track count ({1}); padding/trimming grid." -f $titles.Count, $count) "Warn"
        }
        for ($i = 0; $i -lt $count; $i++) {
            $title = ""
            if ($titles -and $i -lt $titles.Count) { $title = $titles[$i] }
            if ([string]::IsNullOrWhiteSpace($title)) { $title = "Track $($i + 1)" }
            $grid.Rows.Add(@("", $title)) | Out-Null
        }
    }
    elseif ($titles -and $titles.Count -gt 0) {
        foreach ($t in $titles) { $grid.Rows.Add(@("", $t)) | Out-Null }
    }

    Renumber-Grid
}

function Get-Cfg {
    return @{
        RipRoot   = $txtRipRoot.Text.Trim()
        CdDrive   = $txtDrive.Text.Trim()
        CddaDevice= $txtDevice.Text.Trim()
        CDDA2WAV  = $txtCdda.Text.Trim()
        FLAC      = $txtFlac.Text.Trim()
        METAFLAC  = $txtMeta.Text.Trim()
        LIBDISCID = $txtDisc.Text.Trim()
        UserAgent = "MikeRedd-CDRipperGUI/1.1.0"
    }
}

function Set-Busy {
    param([bool]$busy, [string]$msg = "")
    $controls = @($btnDetect, $btnSearch, $btnUseResult, $btnStart, $btnAddRow, $btnDelRow, $btnClrRows)
    foreach ($c in $controls) { $c.Enabled = -not $busy }
    $lblBusy.Text = $msg
    if ($busy) { $form.Cursor = "AppStarting" } else { $form.Cursor = "Default" }
}

# ── Runspace launcher ───────────────────────
function Start-Op {
    param([string]$Op)
    if ($sync.Busy) { return }
    $sync.Busy = $true
    $sync.Op = $Op
    $sync.Done = $false
    $sync.Result = $null
    $sync.Error = $null
    $sync.Cfg = Get-Cfg

    $rs = [runspacefactory]::CreateRunspace()
    $rs.ApartmentState = "STA"
    $rs.ThreadOptions = "ReuseThread"
    $rs.Open()
    $rs.SessionStateProxy.SetVariable("sync", $sync)

    $ps = [powershell]::Create()
    $ps.Runspace = $rs
    [void]$ps.AddScript({
        $global:sync = $sync
        Invoke-Expression $global:sync.WorkerSource
        try {
            switch ($global:sync.Op) {
                "detect"  { $global:sync.Result = Invoke-Detect }
                "search"  { $global:sync.Result = Invoke-Search }
                "release" { $global:sync.Result = Invoke-Release }
                "rip"     { Invoke-Rip; $global:sync.Result = $true }
            }
        } catch {
            $global:sync.Error = $_.Exception.Message
            Send-Log "ERROR: $($_.Exception.Message)" "Bad"
        } finally {
            $global:sync.Done = $true
        }
    })
    $sync.PS = $ps
    $sync.RS = $rs
    $sync.Handle = $ps.BeginInvoke()
}

# ── Completion dispatch ─────────────────────
function Complete-Op {
    param([string]$op, $res)
    switch ($op) {
        "detect" {
            if ($res) {
                $lblDiscId.Text = "DiscID: " + ($(if ($res.DiscId) { $res.DiscId } else { "(not read)" }))
                if ($res.Artist) { $txtArtist.Text = $res.Artist }
                if ($res.Album)  { $txtAlbum.Text  = $res.Album }
                if ($res.Year)   { $txtYear.Text   = $res.Year }
                if ($res.Genre)  { $txtGenre.Text  = $res.Genre }
                Set-Tracks $res.Tracks $res.TrackCount
            }
        }
        "release" {
            if ($res) {
                if ($res.Artist) { $txtArtist.Text = $res.Artist }
                if ($res.Album)  { $txtAlbum.Text  = $res.Album }
                if ($res.Year)   { $txtYear.Text   = $res.Year }
                if ($res.Genre)  { $txtGenre.Text  = $res.Genre }
                Set-Tracks $res.Tracks $res.TrackCount
            }
        }
        "search" {
            $cmbResults.Items.Clear()
            $script:SearchMap = @()
            if ($res -and $res.Count -gt 0) {
                foreach ($r in $res) {
                    $label = "$($r.Artist) - $($r.Title)"
                    if ($r.Date)    { $label += "  ($($r.Date))" }
                    if ($r.Country) { $label += " [$($r.Country)]" }
                    [void]$cmbResults.Items.Add($label)
                    $script:SearchMap += $r.Id
                }
                $cmbResults.SelectedIndex = 0
            }
        }
        "rip" { }
    }
}

# ── Timer: drain log queue + handle completion ──
$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 120
$timer.Add_Tick({
    $item = $null
    while ($sync.LogQueue.TryDequeue([ref]$item)) {
        Add-LogLine $item.Text $item.Type
    }
    if ($sync.Done) {
        $sync.Done = $false
        $op  = $sync.Op
        $res = $sync.Result
        try { $sync.PS.EndInvoke($sync.Handle) } catch { }
        try { $sync.RS.Close() } catch { }
        try { $sync.PS.Dispose() } catch { }
        Complete-Op $op $res
        $sync.Busy = $false
        Set-Busy $false ""
    }
})
$timer.Start()

# ── Event wiring ────────────────────────────
$btnRipRoot.Add_Click({
    $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
    if ($dlg.ShowDialog() -eq "OK") { $txtRipRoot.Text = $dlg.SelectedPath }
})
$btnCover.Add_Click({
    $dlg = New-Object System.Windows.Forms.OpenFileDialog
    $dlg.Filter = "Images|*.jpg;*.jpeg;*.png|All files|*.*"
    if ($dlg.ShowDialog() -eq "OK") { $txtCover.Text = $dlg.FileName }
})

$btnDetect.Add_Click({
    Set-Busy $true "Reading disc and querying MusicBrainz..."
    Add-LogLine "Detecting disc..." "Info"
    Start-Op "detect"
})

$btnSearch.Add_Click({
    if ([string]::IsNullOrWhiteSpace($txtSearchArtist.Text) -or [string]::IsNullOrWhiteSpace($txtSearchAlbum.Text)) {
        Add-LogLine "Enter both a search artist and album." "Warn"; return
    }
    $sync.Job = @{ SearchArtist = $txtSearchArtist.Text.Trim(); SearchAlbum = $txtSearchAlbum.Text.Trim() }
    Set-Busy $true "Searching MusicBrainz..."
    Start-Op "search"
})

$btnUseResult.Add_Click({
    if ($cmbResults.SelectedIndex -lt 0 -or -not $script:SearchMap) {
        Add-LogLine "No search result selected." "Warn"; return
    }
    $id = $script:SearchMap[$cmbResults.SelectedIndex]
    $sync.Job = @{ ReleaseId = $id }
    Set-Busy $true "Fetching release metadata..."
    Add-LogLine "Loading selected release..." "Info"
    Start-Op "release"
})

$btnAddRow.Add_Click({ $grid.Rows.Add(@("", "")) | Out-Null; Renumber-Grid })
$btnDelRow.Add_Click({
    if ($grid.SelectedRows.Count -gt 0) {
        $grid.Rows.Remove($grid.SelectedRows[0]); Renumber-Grid
    } elseif ($grid.Rows.Count -gt 0) {
        $grid.Rows.RemoveAt($grid.Rows.Count - 1); Renumber-Grid
    }
})
$btnClrRows.Add_Click({ $grid.Rows.Clear() })
$grid.Add_RowsRemoved({ Renumber-Grid })
$grid.Add_RowsAdded({ Renumber-Grid })

$btnClear.Add_Click({ $rtb.Clear() })
$btnOpen.Add_Click({
    if ($sync.OutputDir -and (Test-Path $sync.OutputDir)) {
        Start-Process explorer.exe $sync.OutputDir
    } elseif (Test-Path $txtRipRoot.Text) {
        Start-Process explorer.exe $txtRipRoot.Text
    }
})

$btnStart.Add_Click({
    # Gather track titles
    $titles = @()
    for ($i = 0; $i -lt $grid.Rows.Count; $i++) {
        $v = $grid.Rows[$i].Cells[1].Value
        if ($null -ne $v -and -not [string]::IsNullOrWhiteSpace([string]$v)) { $titles += [string]$v }
        else { $titles += "Track $($i+1)" }
    }

    if ([string]::IsNullOrWhiteSpace($txtArtist.Text) -or [string]::IsNullOrWhiteSpace($txtAlbum.Text)) {
        Add-LogLine "Artist and Album are required." "Warn"; return
    }
    if ($titles.Count -lt 1) {
        Add-LogLine "Add at least one track (use Detect or + Add)." "Warn"; return
    }

    $mode = if ($rbTracks.Checked) { "tracks" } else { "image" }
    $sync.Job = @{
        Mode   = $mode
        Artist = $txtArtist.Text.Trim()
        Album  = $txtAlbum.Text.Trim()
        Year   = $txtYear.Text.Trim()
        Genre  = $txtGenre.Text.Trim()
        DiscId = ($lblDiscId.Text -replace '^DiscID:\s*', '')
        Tracks = $titles
        Cover  = $txtCover.Text.Trim()
    }
    if ($sync.Job.DiscId -eq "-" -or $sync.Job.DiscId -like "(not read)*") { $sync.Job.DiscId = "" }

    Set-Busy $true "Ripping ($mode)... this can take a while."
    Add-LogLine "=== Starting rip: $mode mode ===" "Good"
    Start-Op "rip"
})

$form.Add_FormClosing({
    $timer.Stop()
    try { if ($sync.PS) { $sync.PS.Dispose() } } catch { }
    try { if ($sync.RS) { $sync.RS.Close() } } catch { }
})

Add-LogLine "Ready. Insert a disc, then Detect or fill metadata manually." "Dim"
[void]$form.ShowDialog()
