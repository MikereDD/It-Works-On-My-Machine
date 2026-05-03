#--------------------------------------------
# file:     cd-tracks-flac.ps1
# author:   Mike Redd
# version:  1.3
# created:  2026-04-12
# updated:  2026-04-12
# desc:     Rip audio CD to one FLAC per track
#           + MusicBrainz metadata fallback
#           + album.json + optional cover art
#           Uses shared core/ui helpers
#--------------------------------------------

[CmdletBinding()]
param()

# ── Elevate if needed ───────────────────────
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).
    IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    Start-Process pwsh -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
    exit
}

# ── Script/Profile paths ────────────────────
$ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProfileDir = Join-Path $HOME "PS\profile.d"

$corePath = @(
    (Join-Path $ScriptRoot "core.ps1"),
    (Join-Path $ProfileDir "core.ps1")
) | Where-Object { Test-Path $_ } | Select-Object -First 1

$uiPath = @(
    (Join-Path $ScriptRoot "ui.ps1"),
    (Join-Path $ProfileDir "ui.ps1")
) | Where-Object { Test-Path $_ } | Select-Object -First 1

if ($corePath) { . $corePath }
if ($uiPath)   { . $uiPath }

# ── Config ──────────────────────────────────
$VER = "1.3"

$global:RipRoot   = "G:\Rip\CD"
$global:TempRoot  = Join-Path $global:RipRoot "temp"
$global:TrackRoot = Join-Path $global:RipRoot "tracks"
$global:LogRoot   = Join-Path $global:RipRoot "logs"
$global:CoverRoot = Join-Path $global:RipRoot "cover"

$global:CdDrive    = "D:"
$global:CddaDevice = "0,0,0"

$global:CDDA2WAV_EXE = "C:\Program Files (x86)\cdrtfe\tools\cdrtools\cdda2wav.exe"
$global:FLAC_EXE     = "C:\Users\miker\Apps\FLAC\flac.exe"
$global:METAFLAC_EXE = "C:\Users\miker\Apps\FLAC\metaflac.exe"

$global:LIBDISCID_DLL = "C:\Users\miker\Apps\libdiscid\discid.dll"
$global:MB_USER_AGENT = "MikeRedd-CDTracksFlac/1.2"

# ── UI helpers ──────────────────────────────
function Show-Header {
    param([string]$Title)

    Clear-Host

    if (Get-Command Show-BoxHeader -ErrorAction SilentlyContinue) {
        Show-BoxHeader -Title $Title
        return
    }

    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host " $Title" -ForegroundColor Yellow
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host ""
}

function Pause-Key {
    if (Get-Command Pause-UI -ErrorAction SilentlyContinue) {
        Pause-UI
        return
    }

    Write-Host ""
    Read-Host "Press Enter to continue" | Out-Null
}

function Write-Status {
    param(
        [string]$Message,
        [ValidateSet("Info","Good","Warn","Bad")]
        [string]$Type = "Info"
    )

    if (Get-Command Write-UIMessage -ErrorAction SilentlyContinue) {
        Write-UIMessage -Message $Message -Type $Type
        return
    }

    switch ($Type) {
        "Good" { Write-Host $Message -ForegroundColor Green }
        "Warn" { Write-Host $Message -ForegroundColor Yellow }
        "Bad"  { Write-Host $Message -ForegroundColor Red }
        default { Write-Host $Message -ForegroundColor Cyan }
    }
}

# ── General helpers ─────────────────────────
function Initialize-Folders {
    @(
        $global:RipRoot,
        $global:TempRoot,
        $global:TrackRoot,
        $global:LogRoot,
        $global:CoverRoot
    ) | ForEach-Object {
        if (-not (Test-Path $_)) {
            New-Item -ItemType Directory -Force -Path $_ | Out-Null
        }
    }
}

function Write-ToolLog {
    param(
        [Parameter(Mandatory)] [string]$Path,
        [Parameter(Mandatory)] [string]$Message
    )

    $stamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Add-Content -Path $Path -Value "[$stamp] $Message"
}

function Get-SafeName {
    param([Parameter(Mandatory)] [string]$Text)

    $safe = $Text -replace '[<>:"/\\|?*]', ''
    $safe = $safe.Trim()

    if ([string]::IsNullOrWhiteSpace($safe)) {
        return "Unknown"
    }

    return $safe
}

# ── libdiscid ───────────────────────────────
function Initialize-LibDiscid {
    if (-not (Test-Path $global:LIBDISCID_DLL)) {
        throw "libdiscid DLL not found: $($global:LIBDISCID_DLL)"
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

    $loaded = [DiscidNative]::LoadLibrary($global:LIBDISCID_DLL)
    if ($loaded -eq [IntPtr]::Zero) {
        throw "Failed to load discid.dll from: $($global:LIBDISCID_DLL)"
    }
}

function Get-DiscId {
    Initialize-LibDiscid

    $disc = [DiscidNative]::discid_new()
    if ($disc -eq [IntPtr]::Zero) {
        throw "discid_new() failed."
    }

    try {
        $ok = [DiscidNative]::discid_read_sparse($disc, $global:CdDrive, 0)
        if ($ok -eq 0) {
            throw "libdiscid could not read the disc from device '$($global:CdDrive)'."
        }

        $ptr = [Runtime.InteropServices.Marshal]::PtrToStringAnsi([DiscidNative]::discid_get_id($disc))
        $id  = [string]$ptr

        if ([string]::IsNullOrWhiteSpace($id)) {
            throw "libdiscid returned an empty disc ID."
        }

        return $id
    }
    finally {
        [DiscidNative]::discid_free($disc)
    }
}

# ── MusicBrainz ─────────────────────────────
function Get-MBMetadata {
    param([Parameter(Mandatory)] [string]$discId)

    $encodedDiscId = [uri]::EscapeDataString($discId)
    $url = "https://musicbrainz.org/ws/2/discid/${encodedDiscId}?inc=aliases+artist-credits+labels+discids+recordings&fmt=json"

    Write-Host "MB disc lookup URL: $url" -ForegroundColor DarkGray
    Start-Sleep -Milliseconds 1100

    $r = Invoke-RestMethod -Uri $url -Headers @{
        "User-Agent" = $global:MB_USER_AGENT
        "Accept"     = "application/json"
    } -TimeoutSec 20

    if (-not $r.releases) { return $null }

    $rel = $r.releases[0]

    $artist = ""
    if ($rel.'artist-credit' -and $rel.'artist-credit'.Count -gt 0) {
        $artist = $rel.'artist-credit'[0].name
    }

    $tracks = @()
    if ($rel.media) {
        foreach ($m in $rel.media) {
            if ($m.tracks) {
                foreach ($t in $m.tracks) {
                    if ($t.title) {
                        $tracks += $t.title
                    } elseif ($t.recording -and $t.recording.title) {
                        $tracks += $t.recording.title
                    }
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

function Search-MBRelease {
    param(
        [Parameter(Mandatory)] [string]$Artist,
        [Parameter(Mandatory)] [string]$Album
    )

    $query = [uri]::EscapeDataString("artist:`"$Artist`" AND release:`"$Album`"")
    $url = "https://musicbrainz.org/ws/2/release?query=$query&fmt=json&limit=10"

    Start-Sleep -Milliseconds 1100

    $r = Invoke-RestMethod -Uri $url -Headers @{
        "User-Agent" = $global:MB_USER_AGENT
        "Accept"     = "application/json"
    } -TimeoutSec 20

    if (-not $r.releases -or $r.releases.Count -lt 1) {
        return $null
    }

    return $r.releases
}

function Select-MBRelease {
    param([Parameter(Mandatory)] $Releases)

    Write-Host ""
    Write-Status "Possible MusicBrainz matches:" "Good"
    Write-Host ""

    for ($i = 0; $i -lt $Releases.Count; $i++) {
        $rel = $Releases[$i]

        $artist = ""
        if ($rel.'artist-credit' -and $rel.'artist-credit'.Count -gt 0) {
            $artist = $rel.'artist-credit'[0].name
        }

        $date = if ($rel.date) { $rel.date } else { "" }
        $country = if ($rel.country) { $rel.country } else { "" }

        Write-Host ("  {0,2}) {1}  |  {2}  |  {3}  |  {4}" -f ($i + 1), $artist, $rel.title, $date, $country)
    }

    Write-Host ""
    $pick = Read-Host "Choose match number (blank to skip)"

    if ([string]::IsNullOrWhiteSpace($pick)) {
        return $null
    }

    $tmp = 0
    if (-not [int]::TryParse($pick, [ref]$tmp)) {
        return $null
    }

    if ($tmp -lt 1 -or $tmp -gt $Releases.Count) {
        return $null
    }

    return $Releases[$tmp - 1]
}

function Get-MBMetadataByReleaseId {
    param(
        [Parameter(Mandatory)] [string]$ReleaseId
    )

    $encodedReleaseId = [uri]::EscapeDataString($ReleaseId)
    $url = "https://musicbrainz.org/ws/2/release/${encodedReleaseId}?inc=aliases+artist-credits+labels+discids+recordings&fmt=json"

    Write-Host "MB release lookup URL: $url" -ForegroundColor DarkGray
    Start-Sleep -Milliseconds 1100

    $rel = Invoke-RestMethod -Uri $url -Headers @{
        "User-Agent" = $global:MB_USER_AGENT
        "Accept"     = "application/json"
    } -TimeoutSec 20

    $artist = ""
    if ($rel.'artist-credit' -and $rel.'artist-credit'.Count -gt 0) {
        $artist = $rel.'artist-credit'[0].name
    }

    $tracks = @()
    if ($rel.media) {
        foreach ($m in $rel.media) {
            if ($m.tracks) {
                foreach ($t in $m.tracks) {
                    if ($t.title) {
                        $tracks += $t.title
                    } elseif ($t.recording -and $t.recording.title) {
                        $tracks += $t.recording.title
                    }
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

function Show-Metadata {
    param($m)

    Write-Status "Detected metadata:" "Good"
    Write-Host "Artist: $($m.Album.Artist)"
    Write-Host "Album : $($m.Album.Album)"
    Write-Host "Year  : $($m.Album.Year)"
    Write-Host ""

    for ($i = 0; $i -lt $m.Tracks.Count; $i++) {
        Write-Host ("{0:D2}. {1}" -f ($i + 1), $m.Tracks[$i])
    }

    Write-Host ""
}

# ── Disc probing / ripping ──────────────────
function Probe-Disc {
    $logPath = Join-Path $global:LogRoot "cdda2wav_probe.log"
    if (Test-Path $logPath) { Remove-Item $logPath -Force -ErrorAction SilentlyContinue }
    New-Item -ItemType File -Path $logPath -Force | Out-Null

    Write-ToolLog -Path $logPath -Message "EXE: $global:CDDA2WAV_EXE"
    Write-ToolLog -Path $logPath -Message "ARGS: -D $($global:CddaDevice) -J"

    Push-Location $global:TempRoot
    try {
        & $global:CDDA2WAV_EXE -D $global:CddaDevice -J 2>&1 | Tee-Object -FilePath $logPath -Append | Out-Null
        $exitCode = $LASTEXITCODE
    }
    finally {
        Pop-Location
    }

    Write-ToolLog -Path $logPath -Message "EXIT CODE: $exitCode"

    if ($exitCode -ne 0) {
        throw "Failed to probe disc."
    }

    return $logPath
}

function Resolve-TrackCountFromRipLog {
    param([Parameter(Mandatory)] [string]$LogPath)

    $lines = Get-Content -Path $LogPath | ForEach-Object { $_ -replace "`0", "" }

    foreach ($line in $lines) {
        if ($line -match 'total tracks:\s*(\d+)') {
            return [int]$Matches[1]
        }
    }

    throw "Could not determine track count from rip log."
}

function Rip-TrackWav {
    param(
        [Parameter(Mandatory)] [int]$TrackNumber,
        [Parameter(Mandatory)] [string]$OutPath
    )

    $logPath = Join-Path $global:LogRoot ("cdda2wav_track_{0:D2}.log" -f $TrackNumber)
    if (Test-Path $logPath) { Remove-Item $logPath -Force -ErrorAction SilentlyContinue }
    New-Item -ItemType File -Path $logPath -Force | Out-Null

    $trackArg = "$TrackNumber"

    Write-ToolLog -Path $logPath -Message "EXE: $global:CDDA2WAV_EXE"
    Write-ToolLog -Path $logPath -Message "ARGS: -D $($global:CddaDevice) -t $trackArg -O wav $OutPath"
    Write-ToolLog -Path $logPath -Message "OUT : $OutPath"

    & $global:CDDA2WAV_EXE -D $global:CddaDevice -t $trackArg -O wav $OutPath 2>&1 | Tee-Object -FilePath $logPath -Append | Out-Null

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

    $logPath = Join-Path $global:LogRoot ("flac_track_{0:D2}.log" -f $TrackNumber)
    if (Test-Path $logPath) { Remove-Item $logPath -Force -ErrorAction SilentlyContinue }
    New-Item -ItemType File -Path $logPath -Force | Out-Null

    $args = @(
        "-8"
        "--verify"
        "--tag=ARTIST=$($AlbumInfo.Artist)"
        "--tag=ALBUM=$($AlbumInfo.Album)"
        "--tag=TITLE=$TrackTitle"
        "--tag=TRACKNUMBER=$TrackNumber"
        "--tag=DATE=$($AlbumInfo.Year)"
        "--tag=GENRE=$($AlbumInfo.Genre)"
        "--output-name=$FlacPath"
        $WavPath
    )

    Write-ToolLog -Path $logPath -Message "EXE: $global:FLAC_EXE"
    Write-ToolLog -Path $logPath -Message "ARGS: $($args -join ' ')"

    & $global:FLAC_EXE @args 2>&1 | Tee-Object -FilePath $logPath -Append | Out-Null

    Write-ToolLog -Path $logPath -Message "EXIT CODE: $LASTEXITCODE"
    Write-ToolLog -Path $logPath -Message "FLAC EXISTS: $(Test-Path $FlacPath)"

    return $LASTEXITCODE
}

# ── JSON / cover ────────────────────────────
function Save-AlbumMetadataJson {
    param(
        [Parameter(Mandatory)] [string]$JsonPath,
        [Parameter(Mandatory)] [hashtable]$AlbumInfo,
        [Parameter(Mandatory)] [string[]]$TrackTitles,
        [Parameter(Mandatory)] [string[]]$FlacFiles,
        [string]$DiscId = ""
    )

    $trackObjects = @()
    for ($i = 0; $i -lt $TrackTitles.Count; $i++) {
        $fileName = if ($i -lt $FlacFiles.Count) { $FlacFiles[$i] } else { "" }

        $trackObjects += [PSCustomObject]@{
            number   = $i + 1
            title    = $TrackTitles[$i]
            flacFile = $fileName
        }
    }

    $payload = [PSCustomObject]@{
        discId    = $DiscId
        artist    = $AlbumInfo.Artist
        album     = $AlbumInfo.Album
        year      = $AlbumInfo.Year
        genre     = $AlbumInfo.Genre
        discTitle = $AlbumInfo.DiscTitle
        performer = $AlbumInfo.Performer
        tracks    = $trackObjects
    }

    $payload | ConvertTo-Json -Depth 5 | Set-Content -Path $JsonPath -Encoding UTF8
}

function Embed-Cover {
    param(
        [Parameter(Mandatory)] [string]$FlacPath,
        [Parameter(Mandatory)] [string]$ImagePath
    )

    if (-not (Test-Path $ImagePath)) { return }

    Write-Status "Embedding cover art..." "Info"

    & $global:METAFLAC_EXE --remove --block-type=PICTURE $FlacPath 2>$null | Out-Null
    & $global:METAFLAC_EXE --import-picture-from="$ImagePath" $FlacPath 2>&1 | Out-Null

    if ($LASTEXITCODE -eq 0) {
        Write-Status "Cover art embedded." "Good"
    } else {
        Write-Status "Cover embed failed." "Bad"
    }
}

# ── Manual metadata fallback ────────────────
function Get-ManualMetadata {
    $artist = Read-Host "Artist"
    $album  = Read-Host "Album"
    $year   = Read-Host "Year"
    $genre  = Read-Host "Genre"

    return @{
        Artist    = $artist
        Album     = $album
        Year      = $year
        Genre     = $genre
        DiscTitle = $album
        Performer = $artist
    }
}

function Get-ManualTrackTitles {
    param([Parameter(Mandatory)] [int]$TrackCount)

    $titles = @()
    for ($i = 1; $i -le $TrackCount; $i++) {
        $titles += (Read-Host "Track $i")
    }
    return $titles
}

# ── Main ────────────────────────────────────
function Start-Job {
    Initialize-Folders

    $albumInfo = $null
    $tracks    = $null
    $discId    = ""

    try {
        $discId = Get-DiscId
        Write-Status "DiscID: $discId"

        $lookup = Get-MBMetadata $discId

        if ($lookup) {
            Show-Metadata $lookup
            $use = Read-Host "Use detected metadata? (Y/n)"

            if ($use -notmatch '^[Nn]$') {
                $albumInfo = $lookup.Album
                $tracks    = $lookup.Tracks
            }
        }
        else {
            Write-Status "No exact MusicBrainz disc match found." "Warn"
        }
    }
    catch {
        Write-Status "Exact disc lookup failed: $($_.Exception.Message)" "Warn"
    }

    if (-not $albumInfo) {
        Write-Host ""
        Write-Status "MusicBrainz text search fallback" "Info"

        $searchArtist = Read-Host "Artist for lookup (blank to skip)"
        $searchAlbum  = Read-Host "Album for lookup (blank to skip)"

        if (-not [string]::IsNullOrWhiteSpace($searchArtist) -and -not [string]::IsNullOrWhiteSpace($searchAlbum)) {
            try {
                $results = Search-MBRelease -Artist $searchArtist -Album $searchAlbum

                if ($results) {
                    $picked = Select-MBRelease -Releases $results

                    if ($picked) {
                        Write-Host "Picked release MBID: $($picked.id)" -ForegroundColor DarkGray
                        $lookup = Get-MBMetadataByReleaseId -ReleaseId $picked.id

                        if ($lookup) {
                            Show-Metadata $lookup
                            $use = Read-Host "Use selected metadata? (Y/n)"

                            if ($use -notmatch '^[Nn]$') {
                                $albumInfo = $lookup.Album
                                $tracks    = $lookup.Tracks
                            }
                        }
                    }
                }
                else {
                    Write-Status "No MusicBrainz text matches found." "Warn"
                }
            }
            catch {
                Write-Status "Text lookup failed: $($_.Exception.Message)" "Warn"
            }
        }
    }

    try {
        $probeLog = Probe-Disc
        $trackCount = Resolve-TrackCountFromRipLog -LogPath $probeLog
        Write-Status "Disc reports $trackCount tracks." "Good"
    }
    catch {
        Write-Status "Failed to probe disc: $($_.Exception.Message)" "Bad"
        Pause-Key
        return
    }

    if (-not $albumInfo) {
        $albumInfo = Get-ManualMetadata
    }

    if (-not $tracks -or $tracks.Count -ne $trackCount) {
        if ($tracks -and $tracks.Count -ne $trackCount) {
            Write-Status "Track metadata count ($($tracks.Count)) does not match disc track count ($trackCount)." "Warn"
        }

        $tracks = Get-ManualTrackTitles -TrackCount $trackCount
    }

    $artistSafe = Get-SafeName $albumInfo.Artist
    $albumSafe  = Get-SafeName $albumInfo.Album

    $albumDir = Join-Path $global:TrackRoot "$artistSafe\$albumSafe"
    if (-not (Test-Path $albumDir)) {
        New-Item -ItemType Directory -Force -Path $albumDir | Out-Null
    }

    $json = Join-Path $albumDir "album.json"

    $defaultJpg1 = Join-Path $albumDir "cover.jpg"
    $defaultPng1 = Join-Path $albumDir "cover.png"
    $defaultJpg2 = Join-Path $global:CoverRoot "cover.jpg"
    $defaultPng2 = Join-Path $global:CoverRoot "cover.png"

    $coverPath = $null
    foreach ($candidate in @($defaultJpg1, $defaultPng1, $defaultJpg2, $defaultPng2)) {
        if (Test-Path $candidate) {
            $coverPath = $candidate
            break
        }
    }

    if (-not $coverPath) {
        $manualCover = Read-Host "Cover image path (blank skip)"
        if (-not [string]::IsNullOrWhiteSpace($manualCover)) {
            $coverPath = $manualCover.Trim()
        }
    }

    $flacFiles = New-Object System.Collections.Generic.List[string]

    for ($i = 0; $i -lt $trackCount; $i++) {
        $trackNum   = $i + 1
        $trackTitle = $tracks[$i]
        $safeTitle  = Get-SafeName $trackTitle

        $wavPath  = Join-Path $global:TempRoot ("{0:D2} - {1}.wav" -f $trackNum, $safeTitle)
        $flacPath = Join-Path $albumDir        ("{0:D2} - {1}.flac" -f $trackNum, $safeTitle)

        foreach ($f in @($wavPath, $flacPath)) {
            if (Test-Path $f) {
                Remove-Item $f -Force -ErrorAction SilentlyContinue
            }
        }

        Write-Status ("Ripping track {0:D2}: {1}" -f $trackNum, $trackTitle) "Info"

        $ripCode = Rip-TrackWav -TrackNumber $trackNum -OutPath $wavPath
        if ($ripCode -ne 0 -or -not (Test-Path $wavPath)) {
            Write-Status ("Failed to rip track {0:D2}" -f $trackNum) "Bad"
            continue
        }

        Write-Status ("Encoding track {0:D2}: {1}" -f $trackNum, $trackTitle) "Info"

        $encCode = Encode-TrackFlac -WavPath $wavPath -FlacPath $flacPath -AlbumInfo $albumInfo -TrackTitle $trackTitle -TrackNumber $trackNum
        if ($encCode -ne 0 -or -not (Test-Path $flacPath)) {
            Write-Status ("Failed to encode track {0:D2}" -f $trackNum) "Bad"
            continue
        }

        if ($coverPath) {
            Embed-Cover -FlacPath $flacPath -ImagePath $coverPath
        }

        Remove-Item $wavPath -Force -ErrorAction SilentlyContinue
        [void]$flacFiles.Add([System.IO.Path]::GetFileName($flacPath))

        Write-Status ("Created {0:D2} - {1}.flac" -f $trackNum, $trackTitle) "Good"
    }

    try {
        Save-AlbumMetadataJson -JsonPath $json `
                               -AlbumInfo $albumInfo `
                               -TrackTitles $tracks `
                               -FlacFiles $flacFiles.ToArray() `
                               -DiscId $discId
        Write-Status "Saved metadata sidecar." "Good"
    }
    catch {
        Write-Status "Failed to save metadata JSON: $($_.Exception.Message)" "Warn"
    }

    Write-Host ""
    Write-Status "Done." "Good"
    Write-Host " TRACK DIR : $albumDir" -ForegroundColor Yellow
    Write-Host " JSON      : $json"     -ForegroundColor Yellow
    Write-Host ""

    Pause-Key
}

Start-Job