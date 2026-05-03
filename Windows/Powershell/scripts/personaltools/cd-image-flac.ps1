#--------------------------------------------
# file:     cd-image-flac.ps1
# author:   Mike Redd
# version:  3.1
# created:  2026-04-11
# updated:  2026-04-12
# desc:     CD → FLAC + CUE + JSON + Cover Art
#           + MusicBrainz Disc ID metadata
#           + MusicBrainz text-search fallback
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

# ── Paths ───────────────────────────────────
$global:RipRoot   = "G:\Rip\CD"
$global:TempRoot  = "$RipRoot\temp"
$global:ImageRoot = "$RipRoot\image"
$global:LogRoot   = "$RipRoot\logs"

$global:CdDrive    = "D:"
$global:CddaDevice = "0,0,0"

$global:CDDA2WAV_EXE = "C:\Program Files (x86)\cdrtfe\tools\cdrtools\cdda2wav.exe"
$global:FLAC_EXE     = "C:\Users\miker\Apps\FLAC\flac.exe"
$global:METAFLAC_EXE = "C:\Users\miker\Apps\FLAC\metaflac.exe"

# ── MusicBrainz / DiscID ────────────────────
$global:LIBDISCID_DLL = "C:\Users\miker\Apps\libdiscid\discid.dll"
$global:MB_USER_AGENT = "MikeRedd-CDRipper/3.1"

# ── Helpers ─────────────────────────────────
function Write-Status {
    param($msg, $type = "Info")
    switch ($type) {
        "Good" { Write-Host $msg -ForegroundColor Green }
        "Warn" { Write-Host $msg -ForegroundColor Yellow }
        "Bad"  { Write-Host $msg -ForegroundColor Red }
        default { Write-Host $msg -ForegroundColor Cyan }
    }
}

function Initialize-Folders {
    $global:RipRoot, $global:TempRoot, $global:ImageRoot, $global:LogRoot |
        ForEach-Object {
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

function Escape-CueText {
    param([Parameter(Mandatory)] [string]$Text)
    return ($Text -replace '"', "'").Trim()
}

# ────────────────────────────────────────────
# 🔹 DISCID (MusicBrainz)
# ────────────────────────────────────────────

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

# ────────────────────────────────────────────
# 🔹 MusicBrainz
# ────────────────────────────────────────────

function Get-MBMetadata {
    param([Parameter(Mandatory)] [string]$discId)

    $encodedDiscId = [uri]::EscapeDataString($discId)
    $url = "https://musicbrainz.org/ws/2/discid/${encodedDiscId}?inc=aliases+artist-credits+labels+discids+recordings&fmt=json"

    Write-Host "MB disc lookup URL: $url" -ForegroundColor DarkGray
    Write-Host "Querying MusicBrainz disc endpoint..." -ForegroundColor DarkGray
    Start-Sleep -Milliseconds 1100

    $r = Invoke-RestMethod -Uri $url -Headers @{
        "User-Agent" = $global:MB_USER_AGENT
        "Accept"     = "application/json"
    } -TimeoutSec 20

    Write-Host "MusicBrainz disc response received." -ForegroundColor DarkGray

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
    Write-Host "Querying MusicBrainz release endpoint..." -ForegroundColor DarkGray
    Start-Sleep -Milliseconds 1100

    $rel = Invoke-RestMethod -Uri $url -Headers @{
        "User-Agent" = $global:MB_USER_AGENT
        "Accept"     = "application/json"
    } -TimeoutSec 20

    Write-Host "MusicBrainz release response received." -ForegroundColor DarkGray

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

# ────────────────────────────────────────────
# 🔹 CUE / JSON / COVER
# ────────────────────────────────────────────

function Get-StartSectorsFromRipLog {
    param(
        [Parameter(Mandatory)] [string]$LogPath,
        [Parameter(Mandatory)] [int]$TrackCount
    )

    $lines = Get-Content -Path $LogPath | ForEach-Object { $_ -replace "`0", "" }

    $startIndex = -1
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match 'Table of Contents:\s*starting sectors') {
            $startIndex = $i
            break
        }
    }

    if ($startIndex -lt 0) {
        throw "Could not find 'starting sectors' section in rip log."
    }

    $sectorText = ""
    for ($i = $startIndex + 1; $i -lt $lines.Count; $i++) {
        $sectorText += " " + $lines[$i]
        if ($lines[$i] -match 'lead-out') {
            break
        }
    }

    $matches = [regex]::Matches($sectorText, '\d+\.\(\s*(\d+)\)')
    if ($matches.Count -lt $TrackCount) {
        throw "Could not parse enough start sectors. Expected $TrackCount, found $($matches.Count)."
    }

    $sectors = New-Object System.Collections.Generic.List[int]
    for ($i = 0; $i -lt $TrackCount; $i++) {
        [void]$sectors.Add([int]$matches[$i].Groups[1].Value)
    }

    return $sectors.ToArray()
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
        $title         = Escape-CueText $TrackTitles[$i]
        [int]$sector   = $StartSectors[$i]

        [int]$minutes = [math]::Floor($sector / 4500)
        [int]$seconds = [math]::Floor(($sector % 4500) / 75)
        [int]$frames  = $sector % 75
        $index01      = "{0:D2}:{1:D2}:{2:D2}" -f $minutes, $seconds, $frames

        $lines.Add(("  TRACK {0:D2} AUDIO" -f $trackNum))
        $lines.Add('    TITLE "' + $title + '"')
        $lines.Add('    PERFORMER "' + (Escape-CueText $AlbumInfo.Performer) + '"')
        $lines.Add("    INDEX 01 $index01")
    }

    [System.IO.File]::WriteAllLines($CuePath, $lines, [System.Text.Encoding]::ASCII)
}

function Save-AlbumMetadataJson {
    param(
        [Parameter(Mandatory)] [string]$JsonPath,
        [Parameter(Mandatory)] [hashtable]$AlbumInfo,
        [Parameter(Mandatory)] [string[]]$TrackTitles,
        [Parameter(Mandatory)] [int[]]$StartSectors,
        [Parameter(Mandatory)] [string]$FlacFileName,
        [Parameter(Mandatory)] [string]$CueFileName,
        [string]$DiscId = ""
    )

    $trackObjects = @()
    for ($i = 0; $i -lt $TrackTitles.Count; $i++) {
        $trackObjects += [PSCustomObject]@{
            number = $i + 1
            title  = $TrackTitles[$i]
            sector = $StartSectors[$i]
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
        flacFile  = $FlacFileName
        cueFile   = $CueFileName
        tracks    = $trackObjects
    }

    $payload | ConvertTo-Json -Depth 5 | Set-Content -Path $JsonPath -Encoding UTF8
}

function Embed-Cue {
    param($flac, $cue)

    Write-Status "Embedding cuesheet into FLAC..."
    & $global:METAFLAC_EXE "--import-cuesheet-from=$cue" $flac | Out-Null
}

function Embed-Cover {
    param($flac, $img)

    if (-not (Test-Path $img)) {
        Write-Status "Cover not found, skipping." "Warn"
        return
    }

    Write-Status "Embedding cover art..."

    # Remove existing artwork (optional but clean)
    & $global:METAFLAC_EXE --remove --block-type=PICTURE $flac 2>$null

    # Let metaflac auto-detect everything
    & $global:METAFLAC_EXE --import-picture-from="$img" $flac 2>&1 | Out-Null

    if ($LASTEXITCODE -eq 0) {
        Write-Status "Cover art embedded." "Good"
    } else {
        Write-Status "Cover embed failed." "Bad"
    }
}

# ────────────────────────────────────────────
# 🔹 CORE RIP
# ────────────────────────────────────────────

function Rip-Wav {
    param($out)

    Write-Status "Ripping disc to WAV image..."

    $logPath = Join-Path $global:LogRoot "cdda2wav_rip.log"
    if (Test-Path $logPath) { Remove-Item $logPath -Force -ErrorAction SilentlyContinue }
    New-Item -ItemType File -Path $logPath -Force | Out-Null

    Write-ToolLog -Path $logPath -Message "EXE: $global:CDDA2WAV_EXE"
    Write-ToolLog -Path $logPath -Message "ARGS: -D $($global:CddaDevice) -O wav $out"
    Write-ToolLog -Path $logPath -Message "OUT : $out"

    & $global:CDDA2WAV_EXE -D $global:CddaDevice -O wav $out 2>&1 | Tee-Object -FilePath $logPath -Append | Out-Null

    Write-ToolLog -Path $logPath -Message "EXIT CODE: $LASTEXITCODE"
    Write-ToolLog -Path $logPath -Message "WAV EXISTS: $(Test-Path $out)"

    return $LASTEXITCODE
}

function Encode-Flac {
    param($wav, $flac, $meta)

    Write-Status "Encoding FLAC image..."

    $logPath = Join-Path $global:LogRoot "flac_encode.log"
    if (Test-Path $logPath) { Remove-Item $logPath -Force -ErrorAction SilentlyContinue }
    New-Item -ItemType File -Path $logPath -Force | Out-Null

    $args = @(
        "-8"
        "--verify"
        "--tag=ARTIST=$($meta.Artist)"
        "--tag=ALBUM=$($meta.Album)"
        "--tag=DATE=$($meta.Year)"
        "--tag=GENRE=$($meta.Genre)"
        "--output-name=$flac"
        $wav
    )

    Write-ToolLog -Path $logPath -Message "EXE: $global:FLAC_EXE"
    Write-ToolLog -Path $logPath -Message "ARGS: $($args -join ' ')"

    & $global:FLAC_EXE @args 2>&1 | Tee-Object -FilePath $logPath -Append | Out-Null

    Write-ToolLog -Path $logPath -Message "EXIT CODE: $LASTEXITCODE"
    Write-ToolLog -Path $logPath -Message "FLAC EXISTS: $(Test-Path $flac)"

    return $LASTEXITCODE
}

# ────────────────────────────────────────────
# 🔹 MAIN
# ────────────────────────────────────────────

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

    if (-not $albumInfo) {
        $artist = Read-Host "Artist"
        $album  = Read-Host "Album"
        $year   = Read-Host "Year"
        $genre  = Read-Host "Genre"

        $albumInfo = @{
            Artist    = $artist
            Album     = $album
            Year      = $year
            Genre     = $genre
            DiscTitle = $album
            Performer = $artist
        }

        $count = [int](Read-Host "Track count")
        $tracks = @()
        for ($i = 1; $i -le $count; $i++) {
            $tracks += (Read-Host "Track $i")
        }
    }

    $artistSafe = Get-SafeName $albumInfo.Artist
    $albumSafe  = Get-SafeName $albumInfo.Album

    $dir = "$global:ImageRoot\$artistSafe\$albumSafe"
    New-Item -ItemType Directory -Force -Path $dir | Out-Null

    $base   = "$artistSafe - $albumSafe"
    $wav    = "$global:TempRoot\$base.wav"
    $flac   = "$dir\$base.flac"
    $cue    = "$dir\$base.cue"
    $json   = "$dir\album.json"
    $ripLog = Join-Path $global:LogRoot "cdda2wav_rip.log"

    foreach ($f in @($wav, $flac, $cue, $json)) {
        if (Test-Path $f) {
            Remove-Item $f -Force -ErrorAction SilentlyContinue
        }
    }

    if ((Rip-Wav $wav) -ne 0) { return }
    if ((Encode-Flac $wav $flac $albumInfo) -ne 0) { return }

    try {
        [int[]]$startSectors = Get-StartSectorsFromRipLog -LogPath $ripLog -TrackCount $tracks.Count
        Write-Host "Parsed start sectors: $($startSectors -join ', ')" -ForegroundColor Yellow
        Write-ToolLog -Path $ripLog -Message "PARSED START SECTORS: $($startSectors -join ', ')"
    }
    catch {
        Write-Status "Failed to parse track offsets from rip log: $($_.Exception.Message)" "Bad"
        return
    }

    try {
        Write-CueSheet -CuePath $cue `
                       -AudioFileName ([System.IO.Path]::GetFileName($flac)) `
                       -AlbumInfo $albumInfo `
                       -TrackTitles $tracks `
                       -StartSectors $startSectors
    }
    catch {
        Write-Status "CUE creation failed: $($_.Exception.Message)" "Bad"
        return
    }

    try {
        Save-AlbumMetadataJson -JsonPath $json `
                               -AlbumInfo $albumInfo `
                               -TrackTitles $tracks `
                               -StartSectors $startSectors `
                               -FlacFileName ([System.IO.Path]::GetFileName($flac)) `
                               -CueFileName ([System.IO.Path]::GetFileName($cue)) `
                               -DiscId $discId
        Write-Status "Saved metadata sidecar." "Good"
    }
    catch {
        Write-Status "Failed to save metadata JSON: $($_.Exception.Message)" "Warn"
    }

    Embed-Cue $flac $cue

    $defaultJpg = Join-Path $dir "cover.jpg"
    $defaultPng = Join-Path $dir "cover.png"

    $cover = $null
    if (Test-Path $defaultJpg) {
        $cover = $defaultJpg
    }
    elseif (Test-Path $defaultPng) {
        $cover = $defaultPng
    }
    else {
        $cover = Read-Host "Cover image path (blank skip)"
    }

    if ($cover) {
        Embed-Cover $flac $cover
    }

    Write-Status "Done." "Good"
    Write-Host " FLAC : $flac"
    Write-Host " CUE  : $cue"
    Write-Host " JSON : $json"
}

Start-Job