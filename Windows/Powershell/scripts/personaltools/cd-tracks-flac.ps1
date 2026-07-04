#--------------------------------------------
# file:     cd-tracks-flac.ps1
# author:   Mike Redd
# version:  1.7.0
# created:  2026-04-12
# updated:  2026-07-04
# desc:     Rip audio CD to one FLAC per track
#           + MusicBrainz metadata fallback
#           + album.json + Cover Art Archive/Discogs album art + per-track covers + CD NFO
#           Uses shared core/ui helpers
#--------------------------------------------

[CmdletBinding()]
param(
    [string]$RipRoot = "G:\Rip\CD",
    [string]$CdDrive = "D:",
    [string]$CddaDevice = "0,0,0",
    [string]$Cdda2WavExe = "C:\Program Files (x86)\cdrtfe\tools\cdrtools\cdda2wav.exe",
    [string]$FlacExe = (Join-Path $HOME "Apps\FLAC\flac.exe"),
    [string]$MetaFlacExe = (Join-Path $HOME "Apps\FLAC\metaflac.exe"),
    [string]$LibDiscidDll = (Join-Path $HOME "Apps\libdiscid\discid.dll"),
    [string]$CoverPath = "",
    [string]$TrackCoverMapPath = "",
    [string]$DiscogsUrl = "",
    [string]$DiscogsToken = $env:DISCOGS_TOKEN,
    [switch]$NoAlbumArt,
    [switch]$NoNfo,
    [switch]$NoElevate
)

# ── Elevate if needed ───────────────────────
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).
    IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $NoElevate -and -not $isAdmin) {
    $psExe = (Get-Command powershell.exe -ErrorAction SilentlyContinue).Source
    if (-not $psExe) { $psExe = (Get-Command pwsh -ErrorAction SilentlyContinue).Source }
    if (-not $psExe) { $psExe = "powershell.exe" }
    Start-Process $psExe -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
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
$VER = "1.7.0"

$global:RipRoot   = $RipRoot
$global:TempRoot  = Join-Path $global:RipRoot "temp"
$global:TrackRoot = Join-Path $global:RipRoot "tracks"
$global:LogRoot   = Join-Path $global:RipRoot "logs"
$global:CoverRoot = Join-Path $global:RipRoot "cover"

$global:CdDrive    = $CdDrive
$global:CddaDevice = $CddaDevice

$global:CDDA2WAV_EXE = $Cdda2WavExe
$global:FLAC_EXE     = $FlacExe
$global:METAFLAC_EXE = $MetaFlacExe

$global:LIBDISCID_DLL = $LibDiscidDll
$global:MB_USER_AGENT = "MikeRedd-CDTracksFlac/1.7.0"
$global:DISCOGS_TOKEN = $DiscogsToken

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



function Test-CDRipperTools {
    $missingRequired = @()

    foreach ($tool in @(
        @{ Name = "cdda2wav"; Path = $global:CDDA2WAV_EXE },
        @{ Name = "flac";     Path = $global:FLAC_EXE }
    )) {
        if ([string]::IsNullOrWhiteSpace($tool.Path) -or -not (Test-Path $tool.Path)) {
            $missingRequired += ("{0}: {1}" -f $tool.Name, $tool.Path)
        }
    }

    if ($missingRequired.Count -gt 0) {
        throw "Missing required CD ripping tools:`n$($missingRequired -join "`n")"
    }

    if ([string]::IsNullOrWhiteSpace($global:METAFLAC_EXE) -or -not (Test-Path $global:METAFLAC_EXE)) {
        Write-Status "metaflac not found; FLAC files will still be created, but cuesheet/cover embedding will be skipped: $global:METAFLAC_EXE" "Warn"
    }

    if ([string]::IsNullOrWhiteSpace($global:LIBDISCID_DLL) -or -not (Test-Path $global:LIBDISCID_DLL)) {
        Write-Status "libdiscid not found; exact DiscID lookup will fall back to text/manual metadata: $global:LIBDISCID_DLL" "Warn"
    }
}

function Test-AudioOutputFile {
    param([Parameter(Mandatory)] [string]$Path)

    if (-not (Test-Path $Path)) {
        throw "Expected output file was not created: $Path"
    }

    $item = Get-Item -LiteralPath $Path -ErrorAction Stop
    if ($item.Length -le 0) {
        throw "Output file is empty: $Path"
    }

    return $true
}

function Publish-ValidatedAudioFile {
    param(
        [Parameter(Mandatory)] [string]$TempPath,
        [Parameter(Mandatory)] [string]$FinalPath
    )

    [void](Test-AudioOutputFile -Path $TempPath)
    if (Test-Path $FinalPath) {
        Remove-Item -LiteralPath $FinalPath -Force -ErrorAction Stop
    }
    Move-Item -LiteralPath $TempPath -Destination $FinalPath -Force -ErrorAction Stop
    [void](Test-AudioOutputFile -Path $FinalPath)
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

function Get-MBDiscogsUrl {
    param($Release)

    try {
        if ($Release -and $Release.relations) {
            foreach ($rel in $Release.relations) {
                $resource = ""
                try {
                    if ($rel.url -and $rel.url.resource) { $resource = [string]$rel.url.resource }
                } catch { }

                if (-not [string]::IsNullOrWhiteSpace($resource)) {
                    if ($resource -match '(?i)discogs\.com/(?:[^\s?#]+/)?release/\d+') { return $resource }
                    if ($rel.type -and ([string]$rel.type) -match '(?i)discogs') { return $resource }
                }
            }
        }
    } catch { }

    return ""
}

function Get-MBMetadata {
    param([Parameter(Mandatory)] [string]$discId)

    $encodedDiscId = [uri]::EscapeDataString($discId)
    $url = "https://musicbrainz.org/ws/2/discid/${encodedDiscId}?inc=artist-credits+labels+recordings+media+discids+release-groups+url-rels&fmt=json"

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

    $label = Get-MBReleaseLabel -Release $rel
    $discogsUrl = Get-MBDiscogsUrl -Release $rel

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
            Artist          = $artist
            Album           = $rel.title
            Year            = if ($rel.date) { ($rel.date -split "-")[0] } else { "" }
            Genre           = ""
            DiscTitle       = $rel.title
            Performer       = $artist
            ReleaseId       = if ($rel.id) { [string]$rel.id } else { "" }
            MusicBrainzUrl  = if ($rel.id) { "https://musicbrainz.org/release/$($rel.id)" } else { "" }
            ReleaseGroupId  = if ($rel.'release-group' -and $rel.'release-group'.id) { [string]$rel.'release-group'.id } else { "" }
            ReleaseGroupUrl = if ($rel.'release-group' -and $rel.'release-group'.id) { "https://musicbrainz.org/release-group/$($rel.'release-group'.id)" } else { "" }
            DiscogsUrl      = $discogsUrl
            DiscogsReleaseId = Get-DiscogsReleaseIdFromText -Texts @($discogsUrl)
            Date            = if ($rel.date) { [string]$rel.date } else { "" }
            Country         = if ($rel.country) { [string]$rel.country } else { "" }
            Status          = if ($rel.status) { [string]$rel.status } else { "" }
            Label           = $label
        }
        Tracks = $tracks
    }
}

function Get-MBReleaseIdFromText {
    param([string[]]$Texts)

    foreach ($text in $Texts) {
        if ([string]::IsNullOrWhiteSpace($text)) { continue }
        $value = [string]$text
        if ($value -match '/release/([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})') { return $Matches[1] }
        if ($value -match '^\s*([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})\s*$') { return $Matches[1] }
    }

    return ""
}

function Get-MBArtistCreditName {
    param($Release)

    $names = @()
    if ($Release.'artist-credit') {
        foreach ($credit in $Release.'artist-credit') {
            if ($credit.name) { $names += [string]$credit.name }
            elseif ($credit.artist -and $credit.artist.name) { $names += [string]$credit.artist.name }
        }
    }

    return (($names | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }) -join " ").Trim()
}

function Get-MBTrackCount {
    param($Release)

    $trackCount = 0
    if ($Release.media) {
        foreach ($m in $Release.media) {
            if ($m.'track-count') { $trackCount += [int]$m.'track-count' }
            elseif ($m.tracks) { $trackCount += [int]$m.tracks.Count }
        }
    }

    return $trackCount
}

function Get-MBSearchVariants {
    param([string]$Text)

    $variants = New-Object System.Collections.Generic.List[string]
    if ([string]::IsNullOrWhiteSpace($Text)) { return @() }

    $clean = (($Text -replace '[“”]', '"') -replace '[\r\n\t]+', ' ').Trim()
    $clean = ($clean -replace '\s+', ' ').Trim()
    if (-not [string]::IsNullOrWhiteSpace($clean)) { $variants.Add($clean) }

    if ($clean -match '(?i)^the\s+(.+)$') { $variants.Add($Matches[1].Trim()) }
    else { $variants.Add("The $clean") }

    $noPunct = ($clean -replace '[:;,_/\\\-]+', ' ').Trim()
    $noPunct = ($noPunct -replace '\s+', ' ').Trim()
    if (-not [string]::IsNullOrWhiteSpace($noPunct)) { $variants.Add($noPunct) }

    return @($variants | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)
}

function Get-MBSearchQueries {
    param(
        [Parameter(Mandatory)] [string]$Artist,
        [Parameter(Mandatory)] [string]$Album
    )

    $queries = New-Object System.Collections.Generic.List[string]
    $artistVariants = @(Get-MBSearchVariants -Text $Artist)
    $albumVariants  = @(Get-MBSearchVariants -Text $Album)

    if ($artistVariants.Count -gt 0 -and $albumVariants.Count -gt 0) {
        $a0 = $artistVariants[0]
        $b0 = $albumVariants[0]
        $queries.Add("artist:`"$a0`" AND release:`"$b0`"")
        $queries.Add("artistname:`"$a0`" AND release:`"$b0`"")
        $queries.Add("$a0 $b0")
        $queries.Add("$b0 $a0")
        $queries.Add("`"$a0`" `"$b0`"")
        $queries.Add("release:`"$b0`"")
        $queries.Add($b0)
    }

    foreach ($a in $artistVariants) {
        foreach ($b in $albumVariants) {
            $queries.Add("artist:`"$a`" AND release:`"$b`"")
            $queries.Add("artistname:`"$a`" AND release:`"$b`"")
            $queries.Add("$a $b")
            $queries.Add("$b $a")
        }
    }

    foreach ($b in $albumVariants) {
        $queries.Add("release:`"$b`"")
        $queries.Add($b)
    }

    return @($queries | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)
}

function Get-MBReleaseScore {
    param(
        [Parameter(Mandatory)] $Release,
        [Parameter(Mandatory)] [string]$Artist,
        [Parameter(Mandatory)] [string]$Album
    )

    $artistNeedle = $Artist.ToLowerInvariant().Trim()
    $albumNeedle  = $Album.ToLowerInvariant().Trim()
    $titleHay     = ([string]$Release.title).ToLowerInvariant()
    $artistHay    = (Get-MBArtistCreditName -Release $Release).ToLowerInvariant()
    $score = 0

    if ($albumNeedle -and $titleHay.Contains($albumNeedle)) { $score += 120 }
    if ($albumNeedle -and $titleHay.StartsWith($albumNeedle)) { $score += 30 }
    if ($artistNeedle -and $artistHay.Contains($artistNeedle)) { $score += 100 }
    if ($artistNeedle -and $artistNeedle.Contains($artistHay) -and $artistHay.Length -gt 2) { $score += 40 }

    foreach ($word in ($albumNeedle -split '\s+')) {
        if ($word.Length -ge 3 -and $titleHay.Contains($word)) { $score += 10 }
    }
    foreach ($word in ($artistNeedle -split '\s+')) {
        if ($word.Length -ge 3 -and $artistHay.Contains($word)) { $score += 10 }
    }

    if ($Release.status -eq 'Official') { $score += 5 }
    if ($Release.date) { $score += 2 }
    if ((Get-MBTrackCount -Release $Release) -gt 0) { $score += 2 }

    return $score
}

function Get-MBReleaseRawById {
    param([Parameter(Mandatory)] [string]$ReleaseId)

    $encodedReleaseId = [uri]::EscapeDataString($ReleaseId)
    $url = "https://musicbrainz.org/ws/2/release/${encodedReleaseId}?inc=artist-credits+labels+recordings+media+discids+release-groups+url-rels&fmt=json"
    Write-Host "MB release lookup URL: $url" -ForegroundColor DarkGray
    Start-Sleep -Milliseconds 1100
    return Invoke-RestMethod -Uri $url -Headers @{
        "User-Agent" = $global:MB_USER_AGENT
        "Accept"     = "application/json"
    } -TimeoutSec 20
}

function Search-MBRelease {
    param(
        [Parameter(Mandatory)] [string]$Artist,
        [Parameter(Mandatory)] [string]$Album
    )

    $artistClean = $Artist.Trim()
    $albumClean  = $Album.Trim()
    if ([string]::IsNullOrWhiteSpace($artistClean) -or [string]::IsNullOrWhiteSpace($albumClean)) { return $null }

    $releaseId = Get-MBReleaseIdFromText -Texts @($artistClean, $albumClean)
    if ($releaseId) {
        try {
            $rel = Get-MBReleaseRawById -ReleaseId $releaseId
            if ($rel -and $rel.id) { return @($rel) }
        } catch {
            Write-Status "MusicBrainz release URL/ID lookup failed: $($_.Exception.Message)" "Warn"
        }
    }

    $found = @{}
    $queries = @(Get-MBSearchQueries -Artist $artistClean -Album $albumClean)

    foreach ($q in $queries) {
        $query = [uri]::EscapeDataString($q)
        $url = "https://musicbrainz.org/ws/2/release?query=$query&fmt=json&limit=25"
        Write-Host "MB text search URL: $url" -ForegroundColor DarkGray
        Start-Sleep -Milliseconds 1100
        try {
            $r = Invoke-RestMethod -Uri $url -Headers @{
                "User-Agent" = $global:MB_USER_AGENT
                "Accept"     = "application/json"
            } -TimeoutSec 20

            if ($r.releases) {
                foreach ($rel in $r.releases) {
                    if ($rel.id -and -not $found.ContainsKey($rel.id)) { $found[$rel.id] = $rel }
                }
            }
            if ($found.Count -ge 10) { break }
        } catch {
            Write-Status "MusicBrainz text search attempt failed: $($_.Exception.Message)" "Warn"
        }
    }

    if ($found.Count -lt 1) { return $null }

    $ranked = foreach ($rel in $found.Values) {
        [PSCustomObject]@{
            Release = $rel
            Score   = Get-MBReleaseScore -Release $rel -Artist $artistClean -Album $albumClean
        }
    }

    return @($ranked | Sort-Object Score -Descending | Select-Object -First 15 | ForEach-Object { $_.Release })
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
    $url = "https://musicbrainz.org/ws/2/release/${encodedReleaseId}?inc=artist-credits+labels+recordings+media+discids+release-groups+url-rels&fmt=json"

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

    $label = Get-MBReleaseLabel -Release $rel
    $discogsUrl = Get-MBDiscogsUrl -Release $rel

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
            Artist          = $artist
            Album           = $rel.title
            Year            = if ($rel.date) { ($rel.date -split "-")[0] } else { "" }
            Genre           = ""
            DiscTitle       = $rel.title
            Performer       = $artist
            ReleaseId       = if ($rel.id) { [string]$rel.id } else { "" }
            MusicBrainzUrl  = if ($rel.id) { "https://musicbrainz.org/release/$($rel.id)" } else { "" }
            ReleaseGroupId  = if ($rel.'release-group' -and $rel.'release-group'.id) { [string]$rel.'release-group'.id } else { "" }
            ReleaseGroupUrl = if ($rel.'release-group' -and $rel.'release-group'.id) { "https://musicbrainz.org/release-group/$($rel.'release-group'.id)" } else { "" }
            DiscogsUrl      = $discogsUrl
            DiscogsReleaseId = Get-DiscogsReleaseIdFromText -Texts @($discogsUrl)
            Date            = if ($rel.date) { [string]$rel.date } else { "" }
            Country         = if ($rel.country) { [string]$rel.country } else { "" }
            Status          = if ($rel.status) { [string]$rel.status } else { "" }
            Label           = $label
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
        if ($line -match 'tracks?\s*[:=]\s*(\d+)\s*[-–]\s*(\d+)') {
            return ([int]$Matches[2] - [int]$Matches[1] + 1)
        }
        if ($line -match '\b(\d+)\s+audio\s+tracks?\b') {
            return [int]$Matches[1]
        }
    }

    throw "Could not determine track count from rip log. Check $LogPath."
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
        [string]$DiscId = "",
        [object[]]$TrackCoverMap = @()
    )

    $trackObjects = @()
    for ($i = 0; $i -lt $TrackTitles.Count; $i++) {
        $fileName = if ($i -lt $FlacFiles.Count) { $FlacFiles[$i] } else { "" }
        $coverFile = Get-TrackCoverMapValue -TrackCoverMap $TrackCoverMap -TrackNumber ($i + 1)
        if (-not [string]::IsNullOrWhiteSpace($coverFile)) { $coverFile = [System.IO.Path]::GetFileName($coverFile) }

        $trackObjects += [PSCustomObject]@{
            number   = $i + 1
            title    = $TrackTitles[$i]
            flacFile = $fileName
            trackCoverFile = $coverFile
        }
    }

    $payload = [PSCustomObject]@{
        discId               = $DiscId
        musicBrainzReleaseId      = Get-AlbumInfoValue -AlbumInfo $AlbumInfo -Name "ReleaseId"
        musicBrainzReleaseGroupId = Get-AlbumInfoValue -AlbumInfo $AlbumInfo -Name "ReleaseGroupId"
        musicBrainzUrl            = Get-AlbumInfoValue -AlbumInfo $AlbumInfo -Name "MusicBrainzUrl"
        musicBrainzReleaseGroupUrl= Get-AlbumInfoValue -AlbumInfo $AlbumInfo -Name "ReleaseGroupUrl"
        discogsReleaseId = Get-AlbumInfoValue -AlbumInfo $AlbumInfo -Name "DiscogsReleaseId"
        discogsUrl = Get-AlbumInfoValue -AlbumInfo $AlbumInfo -Name "DiscogsUrl"
        artist               = $AlbumInfo.Artist
        album                = $AlbumInfo.Album
        year                 = $AlbumInfo.Year
        date                 = Get-AlbumInfoValue -AlbumInfo $AlbumInfo -Name "Date"
        genre                = $AlbumInfo.Genre
        label                = Get-AlbumInfoValue -AlbumInfo $AlbumInfo -Name "Label"
        country              = Get-AlbumInfoValue -AlbumInfo $AlbumInfo -Name "Country"
        status               = Get-AlbumInfoValue -AlbumInfo $AlbumInfo -Name "Status"
        discTitle            = $AlbumInfo.DiscTitle
        performer            = $AlbumInfo.Performer
        tracks               = $trackObjects
        trackCovers          = @($TrackCoverMap | ForEach-Object { [PSCustomObject]@{ track = $_.Track; cover = ([System.IO.Path]::GetFileName([string]$_.Cover)) } })
    }

    $payload | ConvertTo-Json -Depth 5 | Set-Content -Path $JsonPath -Encoding UTF8
}

function Embed-Cover {
    param(
        [Parameter(Mandatory)] [string]$FlacPath,
        [Parameter(Mandatory)] [string]$ImagePath
    )

    if (-not (Test-Path $ImagePath)) { return }
    if ([string]::IsNullOrWhiteSpace($global:METAFLAC_EXE) -or -not (Test-Path $global:METAFLAC_EXE)) {
        Write-Status "metaflac not found; skipping cover art embed." "Warn"
        return
    }

    Write-Status "Embedding cover art..." "Info"

    & $global:METAFLAC_EXE --remove --block-type=PICTURE $FlacPath 2>$null | Out-Null
    & $global:METAFLAC_EXE --import-picture-from="$ImagePath" $FlacPath 2>&1 | Out-Null

    if ($LASTEXITCODE -eq 0) {
        Write-Status "Cover art embedded." "Good"
    } else {
        Write-Status "Cover embed failed." "Bad"
    }
}


function Get-AlbumInfoValue {
    param(
        [Parameter(Mandatory)] $AlbumInfo,
        [Parameter(Mandatory)] [string]$Name
    )

    if ($null -eq $AlbumInfo) { return "" }
    if ($AlbumInfo -is [hashtable] -and $AlbumInfo.ContainsKey($Name)) {
        return [string]$AlbumInfo[$Name]
    }
    $prop = $AlbumInfo.PSObject.Properties[$Name]
    if ($prop) { return [string]$prop.Value }
    return ""
}

function Get-MBReleaseLabel {
    param($Release)

    if ($Release.'label-info') {
        foreach ($li in $Release.'label-info') {
            if ($li.label -and $li.label.name) { return [string]$li.label.name }
        }
    }
    return ""
}


function Get-DiscogsReleaseIdFromText {
    param([string[]]$Texts)

    foreach ($text in $Texts) {
        if ([string]::IsNullOrWhiteSpace($text)) { continue }
        $value = [string]$text
        if ($value -match '(?i)discogs\.com/(?:[^\s?#]+/)?release/(\d+)') { return $Matches[1] }
        if ($value -match '(?i)\brelease/(\d+)') { return $Matches[1] }
    }

    return ""
}

function Get-DiscogsAuthHeaders {
    $headers = @{ "User-Agent" = $global:MB_USER_AGENT; "Accept" = "application/json" }
    $token = ""
    try { if ($global:DISCOGS_TOKEN) { $token = [string]$global:DISCOGS_TOKEN } } catch { }
    if ([string]::IsNullOrWhiteSpace($token)) { $token = [Environment]::GetEnvironmentVariable("DISCOGS_TOKEN") }
    if (-not [string]::IsNullOrWhiteSpace($token)) { $headers["Authorization"] = "Discogs token=$token" }
    return $headers
}

function Get-DiscogsImageUrlFromHtml {
    param([Parameter(Mandatory)] [string]$Html)

    $patterns = @(
        '<meta\s+property=["'']og:image["'']\s+content=["'']([^"'']+)["'']',
        '<meta\s+content=["'']([^"'']+)["'']\s+property=["'']og:image["'']',
        '<meta\s+name=["'']twitter:image["'']\s+content=["'']([^"'']+)["'']',
        '"image"\s*:\s*"([^"]+)"'
    )

    foreach ($p in $patterns) {
        $m = [regex]::Match($Html, $p, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
        if ($m.Success) { return [System.Net.WebUtility]::HtmlDecode($m.Groups[1].Value) }
    }

    return ""
}

function Get-DiscogsImageUrl {
    param(
        [string]$DiscogsUrl = "",
        [string]$ReleaseId = ""
    )

    if ([string]::IsNullOrWhiteSpace($ReleaseId)) {
        $ReleaseId = Get-DiscogsReleaseIdFromText -Texts @($DiscogsUrl)
    }
    if ([string]::IsNullOrWhiteSpace($ReleaseId)) { return "" }

    $headers = Get-DiscogsAuthHeaders
    $apiUrl = "https://api.discogs.com/releases/$ReleaseId"
    Write-Status "Querying Discogs release art: $ReleaseId" "Info"
    Start-Sleep -Milliseconds 1100

    try {
        $release = Invoke-RestMethod -Uri $apiUrl -Headers $headers -TimeoutSec 25
        if ($release.images) {
            $primary = @($release.images | Where-Object { $_.type -match 'primary' } | Select-Object -First 1)
            $img = if ($primary -and $primary.Count -gt 0) { $primary[0] } else { @($release.images | Select-Object -First 1)[0] }
            if ($img.uri) { return [string]$img.uri }
            if ($img.uri150) { return [string]$img.uri150 }
            if ($img.resource_url) { return [string]$img.resource_url }
        }
        if ($release.cover_image) { return [string]$release.cover_image }
        if ($release.thumb) { return [string]$release.thumb }
    } catch {
        $statusCode = $null
        try { if ($_.Exception.Response -and $_.Exception.Response.StatusCode) { $statusCode = [int]$_.Exception.Response.StatusCode } } catch { }
        if ($statusCode -eq 401 -or $statusCode -eq 403) {
            Write-Status "Discogs API image lookup needs a Discogs token; trying public page image instead." "Warn"
        } else {
            Write-Status "Discogs API image lookup failed: $($_.Exception.Message)" "Warn"
        }
    }

    if ([string]::IsNullOrWhiteSpace($DiscogsUrl)) { $DiscogsUrl = "https://www.discogs.com/release/$ReleaseId" }
    try {
        Write-Status "Checking Discogs page image metadata..." "Info"
        $page = Invoke-WebRequest -Uri $DiscogsUrl -UseBasicParsing -Headers @{ "User-Agent" = $global:MB_USER_AGENT; "Accept" = "text/html,*/*" } -TimeoutSec 25
        $html = [string]$page.Content
        $fromHtml = Get-DiscogsImageUrlFromHtml -Html $html
        if (-not [string]::IsNullOrWhiteSpace($fromHtml)) { return $fromHtml }
    } catch {
        Write-Status "Discogs page image lookup failed: $($_.Exception.Message)" "Warn"
    }

    return ""
}

function Save-DownloadedCover {
    param(
        [Parameter(Mandatory)] [string]$ImageUrl,
        [Parameter(Mandatory)] [string]$AlbumDir,
        [Parameter(Mandatory)] [string]$SourceName
    )

    try {
        $dest = Join-Path $AlbumDir "cover.jpg"
        Write-Status "Downloading album art from $SourceName..." "Info"
        Invoke-WebRequest -Uri $ImageUrl -OutFile $dest -UseBasicParsing -Headers @{ "User-Agent" = $global:MB_USER_AGENT; "Accept" = "image/*,*/*" } -TimeoutSec 45 | Out-Null
        if ((Test-Path $dest) -and ((Get-Item -LiteralPath $dest).Length -gt 0)) {
            Write-Status "Saved album art: $dest" "Good"
            return $dest
        }
        Write-Status "$SourceName album art download did not create a valid file." "Warn"
    } catch {
        Write-Status "$SourceName album art download failed: $($_.Exception.Message)" "Warn"
    }

    return ""
}

function Save-CoverArtFromDiscogs {
    param(
        [Parameter(Mandatory)] $AlbumInfo,
        [Parameter(Mandatory)] [string]$AlbumDir,
        [string]$DiscogsUrl = ""
    )

    $releaseId = Get-AlbumInfoValue -AlbumInfo $AlbumInfo -Name "DiscogsReleaseId"
    if ([string]::IsNullOrWhiteSpace($releaseId)) { $releaseId = Get-DiscogsReleaseIdFromText -Texts @($DiscogsUrl, (Get-AlbumInfoValue -AlbumInfo $AlbumInfo -Name "DiscogsUrl")) }
    $url = if (-not [string]::IsNullOrWhiteSpace($DiscogsUrl)) { $DiscogsUrl } else { Get-AlbumInfoValue -AlbumInfo $AlbumInfo -Name "DiscogsUrl" }

    if ([string]::IsNullOrWhiteSpace($releaseId) -and [string]::IsNullOrWhiteSpace($url)) { return "" }

    $imgUrl = Get-DiscogsImageUrl -DiscogsUrl $url -ReleaseId $releaseId
    if ([string]::IsNullOrWhiteSpace($imgUrl)) {
        Write-Status "No downloadable Discogs image found; use the Cover browse button/manual path if needed." "Warn"
        return ""
    }

    return (Save-DownloadedCover -ImageUrl $imgUrl -AlbumDir $AlbumDir -SourceName "Discogs")
}

function Save-ManualCoverToAlbumDir {
    param(
        [Parameter(Mandatory)] [string]$ManualCoverPath,
        [Parameter(Mandatory)] [string]$AlbumDir
    )

    if ([string]::IsNullOrWhiteSpace($ManualCoverPath) -or -not (Test-Path $ManualCoverPath)) { return "" }

    try {
        $sourceItem = Get-Item -LiteralPath $ManualCoverPath -ErrorAction Stop
        $jpgDest = Join-Path $AlbumDir "cover.jpg"
        if ($sourceItem.FullName.Equals($jpgDest, [System.StringComparison]::OrdinalIgnoreCase)) { return $sourceItem.FullName }

        try {
            Add-Type -AssemblyName System.Drawing -ErrorAction SilentlyContinue
            $img = [System.Drawing.Image]::FromFile($sourceItem.FullName)
            try { $img.Save($jpgDest, [System.Drawing.Imaging.ImageFormat]::Jpeg) } finally { $img.Dispose() }
            if ((Test-Path $jpgDest) -and ((Get-Item -LiteralPath $jpgDest).Length -gt 0)) {
                Write-Status "Saved manual cover as: $jpgDest" "Good"
                return $jpgDest
            }
        } catch {
            $ext = $sourceItem.Extension
            if ([string]::IsNullOrWhiteSpace($ext)) { $ext = ".jpg" }
            $dest = Join-Path $AlbumDir ("cover" + $ext.ToLowerInvariant())
            if (-not $sourceItem.FullName.Equals($dest, [System.StringComparison]::OrdinalIgnoreCase)) {
                Copy-Item -LiteralPath $sourceItem.FullName -Destination $dest -Force -ErrorAction Stop
            }
            if ((Test-Path $dest) -and ((Get-Item -LiteralPath $dest).Length -gt 0)) {
                Write-Status "Saved manual cover as: $dest" "Good"
                return $dest
            }
        }
    } catch {
        Write-Status "Manual cover copy failed: $($_.Exception.Message)" "Warn"
    }

    return ""
}


function Save-TrackCoverToAlbumDir {
    param(
        [Parameter(Mandatory)] [string]$TrackCoverPath,
        [Parameter(Mandatory)] [string]$AlbumDir,
        [Parameter(Mandatory)] [int]$TrackNumber,
        [string]$TrackTitle = ""
    )

    if ([string]::IsNullOrWhiteSpace($TrackCoverPath) -or -not (Test-Path $TrackCoverPath)) { return "" }

    try {
        $sourceItem = Get-Item -LiteralPath $TrackCoverPath -ErrorAction Stop
        $jpgDest = Join-Path $AlbumDir ("cover-track-{0:D2}.jpg" -f $TrackNumber)
        if ($sourceItem.FullName.Equals($jpgDest, [System.StringComparison]::OrdinalIgnoreCase)) { return $sourceItem.FullName }

        try {
            Add-Type -AssemblyName System.Drawing -ErrorAction SilentlyContinue
            $img = [System.Drawing.Image]::FromFile($sourceItem.FullName)
            try { $img.Save($jpgDest, [System.Drawing.Imaging.ImageFormat]::Jpeg) } finally { $img.Dispose() }
            if ((Test-Path $jpgDest) -and ((Get-Item -LiteralPath $jpgDest).Length -gt 0)) {
                Write-Status ("Saved track {0:D2} cover as: {1}" -f $TrackNumber, $jpgDest) "Good"
                return $jpgDest
            }
        } catch {
            $ext = $sourceItem.Extension
            if ([string]::IsNullOrWhiteSpace($ext)) { $ext = ".jpg" }
            $dest = Join-Path $AlbumDir ("cover-track-{0:D2}{1}" -f $TrackNumber, $ext.ToLowerInvariant())
            if (-not $sourceItem.FullName.Equals($dest, [System.StringComparison]::OrdinalIgnoreCase)) {
                Copy-Item -LiteralPath $sourceItem.FullName -Destination $dest -Force -ErrorAction Stop
            }
            if ((Test-Path $dest) -and ((Get-Item -LiteralPath $dest).Length -gt 0)) {
                Write-Status ("Saved track {0:D2} cover as: {1}" -f $TrackNumber, $dest) "Good"
                return $dest
            }
        }
    } catch {
        Write-Status ("Track {0:D2} cover copy failed: {1}" -f $TrackNumber, $_.Exception.Message) "Warn"
    }

    return ""
}

function Get-TrackCoverMapValue {
    param(
        [object[]]$TrackCoverMap = @(),
        [Parameter(Mandatory)] [int]$TrackNumber
    )
    foreach ($entry in @($TrackCoverMap)) {
        if ($null -eq $entry) { continue }
        $track = 0
        try { $track = [int]$entry.Track } catch { }
        if ($track -eq $TrackNumber) { return [string]$entry.Cover }
    }
    return ""
}

function Get-ObjectTextValue {
    param($Object, [string[]]$Names)
    if ($null -eq $Object) { return "" }
    foreach ($name in $Names) {
        $prop = $Object.PSObject.Properties[$name]
        if ($prop -and -not [string]::IsNullOrWhiteSpace([string]$prop.Value)) { return [string]$prop.Value }
    }
    return ""
}

function Import-TrackCoverSourceMap {
    param([string]$Path)
    $map = @{}
    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path $Path)) { return $map }
    try {
        $items = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
        foreach ($item in @($items)) {
            $cover = Get-ObjectTextValue -Object $item -Names @('cover','path','image','file')
            if ([string]::IsNullOrWhiteSpace($cover)) { continue }
            $spec = Get-ObjectTextValue -Object $item -Names @('tracks','range','track')
            if ([string]::IsNullOrWhiteSpace($spec)) { continue }
            foreach ($part in ($spec -split ',')) {
                $p = $part.Trim()
                if ($p -match '^(\d+)\s*-\s*(\d+)$') {
                    $a = [int]$Matches[1]; $b = [int]$Matches[2]
                    if ($a -gt $b) { $t = $a; $a = $b; $b = $t }
                    for ($n = $a; $n -le $b; $n++) { $map[$n] = $cover }
                }
                elseif ($p -match '^\d+$') { $map[[int]$p] = $cover }
            }
        }
        if ($map.Count -gt 0) { Write-Status "Loaded $($map.Count) track cover override(s)." "Good" }
    } catch {
        Write-Status "Failed to read track cover map: $($_.Exception.Message)" "Warn"
    }
    return $map
}

function Get-CoverArtArchiveImageUrl {
    param(
        [Parameter(Mandatory)] [string]$Mbid,
        [ValidateSet("release", "release-group")] [string]$Entity = "release"
    )
    $encodedMbid = [uri]::EscapeDataString($Mbid)
    $url = "https://coverartarchive.org/${Entity}/${encodedMbid}"
    Write-Status "Querying Cover Art Archive ${Entity} art..." "Info"
    Start-Sleep -Milliseconds 1100
    try {
        $r = Invoke-RestMethod -Uri $url -Headers @{ "User-Agent" = $global:MB_USER_AGENT; "Accept" = "application/json" } -TimeoutSec 25
        if (-not $r.images) { return "" }
        $front = @($r.images | Where-Object { $_.front -eq $true } | Select-Object -First 1)
        $img = if ($front -and $front.Count -gt 0) { $front[0] } else { @($r.images | Select-Object -First 1)[0] }
        if (-not $img) { return "" }
        if ($img.thumbnails) {
            if ($img.thumbnails.large)  { return [string]$img.thumbnails.large }
            if ($img.thumbnails.'1200') { return [string]$img.thumbnails.'1200' }
            if ($img.thumbnails.'500')  { return [string]$img.thumbnails.'500' }
            if ($img.thumbnails.small)  { return [string]$img.thumbnails.small }
        }
        if ($img.image) { return [string]$img.image }
        return ""
    } catch {
        $statusCode = $null
        try { if ($_.Exception.Response -and $_.Exception.Response.StatusCode) { $statusCode = [int]$_.Exception.Response.StatusCode } } catch { }
        if ($statusCode -eq 404) {
            Write-Status "No Cover Art Archive ${Entity} art found (404); checking next cover source." "Warn"
        } else {
            Write-Status "Cover Art Archive ${Entity} lookup failed: $($_.Exception.Message)" "Warn"
        }
        return ""
    }
}

function Save-CoverArtFromMusicBrainz {
    param(
        [Parameter(Mandatory)] $AlbumInfo,
        [Parameter(Mandatory)] [string]$AlbumDir
    )
    $releaseId = Get-AlbumInfoValue -AlbumInfo $AlbumInfo -Name "ReleaseId"
    $releaseGroupId = Get-AlbumInfoValue -AlbumInfo $AlbumInfo -Name "ReleaseGroupId"

    $lookups = New-Object System.Collections.Generic.List[object]
    if (-not [string]::IsNullOrWhiteSpace($releaseId)) {
        [void]$lookups.Add([PSCustomObject]@{ Entity = "release"; Id = $releaseId })
    }
    if (-not [string]::IsNullOrWhiteSpace($releaseGroupId)) {
        [void]$lookups.Add([PSCustomObject]@{ Entity = "release-group"; Id = $releaseGroupId })
    }

    if ($lookups.Count -lt 1) {
        Write-Status "No MusicBrainz release or release-group ID available for cover art lookup." "Warn"
        return ""
    }

    foreach ($lookup in $lookups) {
        $imgUrl = Get-CoverArtArchiveImageUrl -Mbid $lookup.Id -Entity $lookup.Entity
        if ([string]::IsNullOrWhiteSpace($imgUrl)) { continue }
        $saved = Save-DownloadedCover -ImageUrl $imgUrl -AlbumDir $AlbumDir -SourceName "Cover Art Archive"
        if (-not [string]::IsNullOrWhiteSpace($saved) -and (Test-Path $saved)) { return $saved }
    }

    Write-Status "No downloadable Cover Art Archive image found; continuing to next cover source." "Warn"
    return ""
}



function Resolve-AlbumCoverPath {
    param(
        [Parameter(Mandatory)] $AlbumInfo,
        [Parameter(Mandatory)] [string]$AlbumDir,
        [string]$ManualCoverPath = "",
        [string]$DiscogsUrl = "",
        [switch]$AllowDownload,
        [switch]$AllowPrompt
    )

    if (-not [string]::IsNullOrWhiteSpace($ManualCoverPath) -and (Test-Path $ManualCoverPath)) {
        $manual = Save-ManualCoverToAlbumDir -ManualCoverPath $ManualCoverPath -AlbumDir $AlbumDir
        if (-not [string]::IsNullOrWhiteSpace($manual) -and (Test-Path $manual)) { return $manual }
        return $ManualCoverPath
    }

    foreach ($candidate in @(
        (Join-Path $AlbumDir "cover.jpg"),
        (Join-Path $AlbumDir "cover.png"),
        (Join-Path $AlbumDir "folder.jpg"),
        (Join-Path $AlbumDir "folder.png")
    )) {
        if (Test-Path $candidate) { return $candidate }
    }

    if ($AllowDownload) {
        $discogs = Save-CoverArtFromDiscogs -AlbumInfo $AlbumInfo -AlbumDir $AlbumDir -DiscogsUrl $DiscogsUrl
        if (-not [string]::IsNullOrWhiteSpace($discogs) -and (Test-Path $discogs)) { return $discogs }

        $downloaded = Save-CoverArtFromMusicBrainz -AlbumInfo $AlbumInfo -AlbumDir $AlbumDir
        if (-not [string]::IsNullOrWhiteSpace($downloaded) -and (Test-Path $downloaded)) { return $downloaded }
    }

    if ($AllowPrompt) {
        $manual = Read-Host "Cover image path (blank skip)"
        if (-not [string]::IsNullOrWhiteSpace($manual) -and (Test-Path $manual.Trim())) {
            $copied = Save-ManualCoverToAlbumDir -ManualCoverPath $manual.Trim() -AlbumDir $AlbumDir
            if (-not [string]::IsNullOrWhiteSpace($copied) -and (Test-Path $copied)) { return $copied }
            return $manual.Trim()
        }
    }

    return ""
}

function Format-CDFileSize {
    param([long]$Bytes)
    if ($Bytes -ge 1GB) { return ("{0:N2} GB" -f ($Bytes / 1GB)) }
    if ($Bytes -ge 1MB) { return ("{0:N2} MB" -f ($Bytes / 1MB)) }
    if ($Bytes -ge 1KB) { return ("{0:N2} KB" -f ($Bytes / 1KB)) }
    return "$Bytes B"
}

function Format-CDDuration {
    param([double]$Seconds)
    if ($Seconds -le 0) { return "" }
    $ts = [TimeSpan]::FromSeconds($Seconds)
    if ($ts.TotalHours -ge 1) { return ("{0:D2}:{1:D2}:{2:D2}" -f [int]$ts.TotalHours, $ts.Minutes, $ts.Seconds) }
    return ("{0:D2}:{1:D2}" -f $ts.Minutes, $ts.Seconds)
}

function Get-FlacTechnicalInfo {
    param([Parameter(Mandatory)] [string]$Path)

    $info = [ordered]@{
        SampleRate = ""
        Channels   = ""
        BitDepth   = ""
        Duration   = ""
    }

    if ([string]::IsNullOrWhiteSpace($global:METAFLAC_EXE) -or -not (Test-Path $global:METAFLAC_EXE) -or -not (Test-Path $Path)) {
        return $info
    }

    try {
        $sr = (& $global:METAFLAC_EXE --show-sample-rate $Path 2>$null | Select-Object -First 1)
        $ch = (& $global:METAFLAC_EXE --show-channels $Path 2>$null | Select-Object -First 1)
        $bd = (& $global:METAFLAC_EXE --show-bps $Path 2>$null | Select-Object -First 1)
        $samples = (& $global:METAFLAC_EXE --show-total-samples $Path 2>$null | Select-Object -First 1)

        if ($sr) { $info.SampleRate = "$sr Hz" }
        if ($ch) { $info.Channels = "$ch" }
        if ($bd) { $info.BitDepth = "$bd-bit" }
        if ($sr -and $samples) {
            $seconds = [double]$samples / [double]$sr
            $info.Duration = Format-CDDuration -Seconds $seconds
        }
    }
    catch { }

    return $info
}

function Write-CDNfo {
    param(
        [Parameter(Mandatory)] [string]$NfoPath,
        [Parameter(Mandatory)] [string]$Mode,
        [Parameter(Mandatory)] $AlbumInfo,
        [Parameter(Mandatory)] [string[]]$TrackTitles,
        [string[]]$Files = @(),
        [string]$DiscId = "",
        [string]$CoverPath = "",
        [object[]]$TrackCoverMap = @()
    )

    try {
        $lines = New-Object System.Collections.Generic.List[string]
        $lines.Add("  ______ _____       ______ _            _____  _                       ")
        $lines.Add(" / _____|  __ \     |  ____| |          |  __ \(_)                      ")
        $lines.Add("| |     | |  | |____| |__  | | __ _  ___| |__) |_ _ __  _ __   ___ _ __ ")
        $lines.Add("| |     | |  | |____|  __| | |/ _` |/ __|  _  /| | '_ \| '_ \ / _ \ '__|")
        $lines.Add("| |____ | |__| |    | |    | | (_| | (__| | \ \| | |_) | |_) |  __/ |   ")
        $lines.Add(" \_____|_____/     |_|    |_|\__,_|\___|_|  \_\_| .__/| .__/ \___|_|   ")
        $lines.Add("                                                 | |   | |              ")
        $lines.Add("                                                 |_|   |_|              ")
        $lines.Add("")
        $lines.Add("CD -> FLAC Ripper v$VER")
        $lines.Add("Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')")
        $lines.Add("Mode     : $Mode")
        $lines.Add("Source   : Audio CD")
        $lines.Add("")
        $lines.Add("Album Information")
        $lines.Add("-----------------")
        $lines.Add("Artist   : $(Get-AlbumInfoValue -AlbumInfo $AlbumInfo -Name 'Artist')")
        $lines.Add("Album    : $(Get-AlbumInfoValue -AlbumInfo $AlbumInfo -Name 'Album')")
        $lines.Add("Year     : $(Get-AlbumInfoValue -AlbumInfo $AlbumInfo -Name 'Year')")
        $lines.Add("Genre    : $(Get-AlbumInfoValue -AlbumInfo $AlbumInfo -Name 'Genre')")
        $lines.Add("Label    : $(Get-AlbumInfoValue -AlbumInfo $AlbumInfo -Name 'Label')")
        $lines.Add("Country  : $(Get-AlbumInfoValue -AlbumInfo $AlbumInfo -Name 'Country')")
        $lines.Add("Status   : $(Get-AlbumInfoValue -AlbumInfo $AlbumInfo -Name 'Status')")
        $lines.Add("DiscID   : $DiscId")
        $lines.Add("MBID     : $(Get-AlbumInfoValue -AlbumInfo $AlbumInfo -Name 'ReleaseId')")
        $lines.Add("MB URL   : $(Get-AlbumInfoValue -AlbumInfo $AlbumInfo -Name 'MusicBrainzUrl')")
        $lines.Add("RG MBID  : $(Get-AlbumInfoValue -AlbumInfo $AlbumInfo -Name 'ReleaseGroupId')")
        $lines.Add("RG URL   : $(Get-AlbumInfoValue -AlbumInfo $AlbumInfo -Name 'ReleaseGroupUrl')")
        $lines.Add("Discogs : $(Get-AlbumInfoValue -AlbumInfo $AlbumInfo -Name 'DiscogsUrl')")
        if ($CoverPath) { $lines.Add("Cover    : $([System.IO.Path]::GetFileName($CoverPath))") }
        if ($TrackCoverMap -and @($TrackCoverMap).Count -gt 0) {
            $lines.Add("")
            $lines.Add("Track Cover Overrides")
            $lines.Add("---------------------")
            foreach ($tc in @($TrackCoverMap)) {
                if ($null -eq $tc) { continue }
                $coverName = [System.IO.Path]::GetFileName([string]$tc.Cover)
                $trackNum = 0
                try { $trackNum = [int]$tc.Track } catch { }
                if ($trackNum -gt 0 -and -not [string]::IsNullOrWhiteSpace($coverName)) {
                    $lines.Add(("{0:D2}. {1}" -f $trackNum, $coverName))
                }
            }
        }
        $lines.Add("")
        $lines.Add("Tools")
        $lines.Add("-----")
        $lines.Add("cdda2wav : $global:CDDA2WAV_EXE")
        $lines.Add("flac     : $global:FLAC_EXE")
        $lines.Add("metaflac : $global:METAFLAC_EXE")
        $lines.Add("libdiscid: $global:LIBDISCID_DLL")
        $lines.Add("")
        $lines.Add("Track List")
        $lines.Add("----------")
        for ($i = 0; $i -lt $TrackTitles.Count; $i++) {
            $lines.Add(("{0:D2}. {1}" -f ($i + 1), $TrackTitles[$i]))
        }
        $lines.Add("")
        $lines.Add("Files")
        $lines.Add("-----")
        $safeFiles = @($Files) | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | Select-Object -Unique
        foreach ($file in $safeFiles) {
            if (-not (Test-Path $file)) { continue }
            $item = Get-Item -LiteralPath $file
            $lines.Add("$($item.Name)  [$((Format-CDFileSize -Bytes $item.Length))]")
            if ($item.Extension -ieq ".flac") {
                $tech = Get-FlacTechnicalInfo -Path $item.FullName
                $details = @()
                if ($tech.Duration)   { $details += "Duration $($tech.Duration)" }
                if ($tech.SampleRate) { $details += "Sample Rate $($tech.SampleRate)" }
                if ($tech.Channels)   { $details += "Channels $($tech.Channels)" }
                if ($tech.BitDepth)   { $details += "Bit Depth $($tech.BitDepth)" }
                if ($details.Count -gt 0) { $lines.Add("  " + ($details -join " | ")) }
            }
        }
        $lines.Add("")
        $lines.Add("It Works On My Machine")

        [System.IO.File]::WriteAllLines($NfoPath, $lines, [System.Text.Encoding]::UTF8)
        Write-Status "Created NFO: $NfoPath" "Good"
    }
    catch {
        Write-Status "NFO creation failed: $($_.Exception.Message)" "Warn"
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
        DiscTitle       = $album
        Performer       = $artist
        ReleaseId       = ""
        MusicBrainzUrl  = ""
        ReleaseGroupId  = ""
        ReleaseGroupUrl = ""
        DiscogsReleaseId = Get-DiscogsReleaseIdFromText -Texts @($DiscogsUrl)
        DiscogsUrl       = $DiscogsUrl
        Date            = $year
        Country         = ""
        Status          = ""
        Label           = ""
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

    try {
        Test-CDRipperTools
    }
    catch {
        Write-Status $_.Exception.Message "Bad"
        Pause-Key
        return
    }

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

    if (-not [string]::IsNullOrWhiteSpace($DiscogsUrl)) {
        $albumInfo.DiscogsUrl = $DiscogsUrl
        $albumInfo.DiscogsReleaseId = Get-DiscogsReleaseIdFromText -Texts @($DiscogsUrl)
    }

    $artistSafe = Get-SafeName $albumInfo.Artist
    $albumSafe  = Get-SafeName $albumInfo.Album

    $albumDir = Join-Path $global:TrackRoot "$artistSafe\$albumSafe"
    if (-not (Test-Path $albumDir)) {
        New-Item -ItemType Directory -Force -Path $albumDir | Out-Null
    }

    $json = Join-Path $albumDir "album.json"

    $coverPath = Resolve-AlbumCoverPath -AlbumInfo $albumInfo -AlbumDir $albumDir -ManualCoverPath $CoverPath -DiscogsUrl $DiscogsUrl -AllowDownload:(!$NoAlbumArt) -AllowPrompt:(!$NoAlbumArt)
    $trackCoverSourceMap = Import-TrackCoverSourceMap -Path $TrackCoverMapPath
    $trackCoverMap = New-Object System.Collections.Generic.List[object]

    $flacFiles = New-Object System.Collections.Generic.List[string]
    $flacPaths = New-Object System.Collections.Generic.List[string]
    $failedTracks = New-Object System.Collections.Generic.List[int]

    for ($i = 0; $i -lt $trackCount; $i++) {
        $trackNum   = $i + 1
        $trackTitle = $tracks[$i]
        $safeTitle  = Get-SafeName $trackTitle

        $wavPath  = Join-Path $global:TempRoot ("{0:D2} - {1}.wav" -f $trackNum, $safeTitle)
        $flacPath = Join-Path $albumDir        ("{0:D2} - {1}.flac" -f $trackNum, $safeTitle)
        $flacWork = "${flacPath}.__encoding__.tmp.flac"

        foreach ($f in @($wavPath, $flacPath, $flacWork)) {
            if (Test-Path $f) {
                Remove-Item $f -Force -ErrorAction SilentlyContinue
            }
        }

        Write-Status ("Ripping track {0:D2}: {1}" -f $trackNum, $trackTitle) "Info"

        $ripCode = Rip-TrackWav -TrackNumber $trackNum -OutPath $wavPath
        if ($ripCode -ne 0 -or -not (Test-Path $wavPath)) {
            Write-Status ("Failed to rip track {0:D2}" -f $trackNum) "Bad"
            [void]$failedTracks.Add($trackNum)
            continue
        }

        Write-Status ("Encoding track {0:D2}: {1}" -f $trackNum, $trackTitle) "Info"

        $encCode = Encode-TrackFlac -WavPath $wavPath -FlacPath $flacWork -AlbumInfo $albumInfo -TrackTitle $trackTitle -TrackNumber $trackNum
        if ($encCode -ne 0) {
            Write-Status ("Failed to encode track {0:D2}" -f $trackNum) "Bad"
            [void]$failedTracks.Add($trackNum)
            continue
        }

        try {
            Publish-ValidatedAudioFile -TempPath $flacWork -FinalPath $flacPath
        }
        catch {
            Write-Status ("Track {0:D2} validation/publish failed: {1}" -f $trackNum, $_.Exception.Message) "Bad"
            [void]$failedTracks.Add($trackNum)
            continue
        }

        $embedCoverPath = $coverPath
        if ($trackCoverSourceMap.ContainsKey($trackNum)) {
            $savedTrackCover = Save-TrackCoverToAlbumDir -TrackCoverPath ([string]$trackCoverSourceMap[$trackNum]) -AlbumDir $albumDir -TrackNumber $trackNum -TrackTitle $trackTitle
            if (-not [string]::IsNullOrWhiteSpace($savedTrackCover) -and (Test-Path $savedTrackCover)) {
                $embedCoverPath = $savedTrackCover
                [void]$trackCoverMap.Add([PSCustomObject]@{ Track = $trackNum; Title = $trackTitle; Cover = $savedTrackCover })
            }
        }
        if ($embedCoverPath) {
            Embed-Cover -FlacPath $flacPath -ImagePath $embedCoverPath
        }

        Remove-Item $wavPath -Force -ErrorAction SilentlyContinue
        [void]$flacFiles.Add([System.IO.Path]::GetFileName($flacPath))
        [void]$flacPaths.Add($flacPath)

        Write-Status ("Created {0:D2} - {1}.flac" -f $trackNum, $trackTitle) "Good"
    }

    if ($failedTracks.Count -gt 0 -or $flacFiles.Count -ne $trackCount) {
        Write-Status ("CD track rip finished with failures. Expected {0}, created {1}. Failed tracks: {2}" -f $trackCount, $flacFiles.Count, ($failedTracks -join ', ')) "Bad"
    }

    try {
        Save-AlbumMetadataJson -JsonPath $json `
                               -AlbumInfo $albumInfo `
                               -TrackTitles $tracks `
                               -FlacFiles $flacFiles.ToArray() `
                               -DiscId $discId `
                               -TrackCoverMap ($trackCoverMap.ToArray())
        Write-Status "Saved metadata sidecar." "Good"
    }
    catch {
        Write-Status "Failed to save metadata JSON: $($_.Exception.Message)" "Warn"
    }

    $nfo = Join-Path $albumDir ("$artistSafe - $albumSafe.nfo")
    if (-not $NoNfo) {
        $trackCoverFiles = @($trackCoverMap.ToArray() | ForEach-Object { $_.Cover })
        $nfoFiles = (@($flacPaths.ToArray()) + @($json, $coverPath) + @($trackCoverFiles)) | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }
        Write-CDNfo -NfoPath $nfo `
                    -Mode "One FLAC per track" `
                    -AlbumInfo $albumInfo `
                    -TrackTitles $tracks `
                    -Files $nfoFiles `
                    -DiscId $discId `
                    -CoverPath $coverPath `
                    -TrackCoverMap ($trackCoverMap.ToArray())
    }

    Write-Host ""
    if ($failedTracks.Count -gt 0 -or $flacFiles.Count -ne $trackCount) {
        Write-Status "Finished with errors. Check logs before using this rip." "Bad"
    }
    else {
        Write-Status "Done." "Good"
    }
    Write-Host " TRACK DIR : $albumDir" -ForegroundColor Yellow
    Write-Host " JSON      : $json"     -ForegroundColor Yellow
    if (Test-Path $nfo) { Write-Host " NFO       : $nfo" -ForegroundColor Yellow }
    if ($coverPath -and (Test-Path $coverPath)) { Write-Host " COVER     : $coverPath" -ForegroundColor Yellow }
    Write-Host ""

    Pause-Key
}

Start-Job