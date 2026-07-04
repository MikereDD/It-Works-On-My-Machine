#--------------------------------------------
# file:     cd-ripper-gui.ps1
# author:   Mike Redd
# version:  1.4.0
# created:  2026-06-17
# updated:  2026-07-04
# desc:     WinForms GUI front-end for the CD -> FLAC
#           archiving toolchain. Wraps both modes:
#             * Single FLAC image + CUE (cd-image-flac.ps1)
#             * One FLAC per track       (cd-tracks-flac.ps1)
#           DiscID + MusicBrainz lookup, editable metadata
#           + track grid, Cover Art Archive fetch, cover embed, per-track covers, JSON sidecar, CD NFO + Discogs cover fallback.
#           Background runspaces keep the UI responsive.
#--------------------------------------------

[CmdletBinding()]
param(
    [string]$CdDrive = "D:",
    [ValidateSet("image","tracks")]
    [string]$Mode = "image",
    [switch]$AutoDetect
)

if ($CdDrive -and $CdDrive -notmatch ':$') { $CdDrive += ':' }

# ── Elevate if needed (raw device access for cdda2wav/libdiscid) ──
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).
    IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    # Match the tool-menu convention: WinForms GUIs run under Windows PowerShell
    # in STA (pwsh is MTA and unreliable for WinForms). Preserve caller args
    # from media-encoder-gui, including drive/mode/autodetect.
    $psExe = (Get-Command powershell.exe -ErrorAction SilentlyContinue).Source
    if (-not $psExe) { $psExe = "powershell.exe" }

    $relaunchArgs = @(
        '-NoProfile',
        '-ExecutionPolicy', 'Bypass',
        '-STA',
        '-File', ('"{0}"' -f $PSCommandPath),
        '-CdDrive', ('"{0}"' -f $CdDrive),
        '-Mode', $Mode
    )
    if ($AutoDetect) { $relaunchArgs += '-AutoDetect' }

    Start-Process $psExe -Verb RunAs -ArgumentList $relaunchArgs
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


function Get-AlbumInfoValue {
    param(
        [Parameter(Mandatory)] $AlbumInfo,
        [Parameter(Mandatory)] [string]$Name
    )
    if ($null -eq $AlbumInfo) { return "" }
    if ($AlbumInfo -is [hashtable] -and $AlbumInfo.ContainsKey($Name)) { return [string]$AlbumInfo[$Name] }
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
    $cfg = $global:sync.Cfg
    $headers = @{ "User-Agent" = $cfg.UserAgent; "Accept" = "application/json" }
    $token = ""
    try { if ($cfg.DiscogsToken) { $token = [string]$cfg.DiscogsToken } } catch { }
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
    Send-Log "Querying Discogs release art: $ReleaseId" "Info"
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
            Send-Log "Discogs API image lookup needs a Discogs token; trying public page image instead." "Warn"
        } else {
            Send-Log "Discogs API image lookup failed: $($_.Exception.Message)" "Warn"
        }
    }

    if ([string]::IsNullOrWhiteSpace($DiscogsUrl)) { $DiscogsUrl = "https://www.discogs.com/release/$ReleaseId" }
    try {
        Send-Log "Checking Discogs page image metadata..." "Info"
        $page = Invoke-WebRequest -Uri $DiscogsUrl -UseBasicParsing -Headers @{ "User-Agent" = $global:sync.Cfg.UserAgent; "Accept" = "text/html,*/*" } -TimeoutSec 25
        $html = [string]$page.Content
        $fromHtml = Get-DiscogsImageUrlFromHtml -Html $html
        if (-not [string]::IsNullOrWhiteSpace($fromHtml)) { return $fromHtml }
    } catch {
        Send-Log "Discogs page image lookup failed: $($_.Exception.Message)" "Warn"
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
        Send-Log "Downloading album art from $SourceName..." "Info"
        Invoke-WebRequest -Uri $ImageUrl -OutFile $dest -UseBasicParsing -Headers @{ "User-Agent" = $global:sync.Cfg.UserAgent; "Accept" = "image/*,*/*" } -TimeoutSec 45 | Out-Null
        if ((Test-Path $dest) -and ((Get-Item -LiteralPath $dest).Length -gt 0)) {
            Send-Log "Saved album art: $dest" "Good"
            return $dest
        }
        Send-Log "$SourceName album art download did not create a valid file." "Warn"
    } catch {
        Send-Log "$SourceName album art download failed: $($_.Exception.Message)" "Warn"
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
        Send-Log "No downloadable Discogs image found; use the Cover browse button/manual path if needed." "Warn"
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
                Send-Log "Saved manual cover as: $jpgDest" "Good"
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
                Send-Log "Saved manual cover as: $dest" "Good"
                return $dest
            }
        }
    } catch {
        Send-Log "Manual cover copy failed: $($_.Exception.Message)" "Warn"
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
        $safeTitle = Get-SafeName $TrackTitle
        if ([string]::IsNullOrWhiteSpace($safeTitle)) { $safeTitle = ("Track {0:D2}" -f $TrackNumber) }
        $sourceItem = Get-Item -LiteralPath $TrackCoverPath -ErrorAction Stop
        $jpgDest = Join-Path $AlbumDir ("cover-track-{0:D2}.jpg" -f $TrackNumber)
        if ($sourceItem.FullName.Equals($jpgDest, [System.StringComparison]::OrdinalIgnoreCase)) { return $sourceItem.FullName }

        try {
            Add-Type -AssemblyName System.Drawing -ErrorAction SilentlyContinue
            $img = [System.Drawing.Image]::FromFile($sourceItem.FullName)
            try { $img.Save($jpgDest, [System.Drawing.Imaging.ImageFormat]::Jpeg) } finally { $img.Dispose() }
            if ((Test-Path $jpgDest) -and ((Get-Item -LiteralPath $jpgDest).Length -gt 0)) {
                Send-Log ("Saved track {0:D2} cover as: {1}" -f $TrackNumber, $jpgDest) "Good"
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
                Send-Log ("Saved track {0:D2} cover as: {1}" -f $TrackNumber, $dest) "Good"
                return $dest
            }
        }
    } catch {
        Send-Log ("Track {0:D2} cover copy failed: {1}" -f $TrackNumber, $_.Exception.Message) "Warn"
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

function Get-CoverArtArchiveImageUrl {
    param(
        [Parameter(Mandatory)] [string]$Mbid,
        [ValidateSet("release", "release-group")] [string]$Entity = "release"
    )
    $cfg = $global:sync.Cfg
    $encodedMbid = [uri]::EscapeDataString($Mbid)
    $url = "https://coverartarchive.org/${Entity}/${encodedMbid}"
    Send-Log "Querying Cover Art Archive ${Entity} art..." "Info"
    Start-Sleep -Milliseconds 1100
    try {
        $r = Invoke-RestMethod -Uri $url -Headers @{ "User-Agent" = $cfg.UserAgent; "Accept" = "application/json" } -TimeoutSec 25
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
            Send-Log "No Cover Art Archive ${Entity} art found (404); checking next cover source." "Warn"
        } else {
            Send-Log "Cover Art Archive ${Entity} lookup failed: $($_.Exception.Message)" "Warn"
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
        Send-Log "No MusicBrainz release or release-group ID available for cover art lookup." "Warn"
        return ""
    }

    foreach ($lookup in $lookups) {
        $imgUrl = Get-CoverArtArchiveImageUrl -Mbid $lookup.Id -Entity $lookup.Entity
        if ([string]::IsNullOrWhiteSpace($imgUrl)) { continue }
        $saved = Save-DownloadedCover -ImageUrl $imgUrl -AlbumDir $AlbumDir -SourceName "Cover Art Archive"
        if (-not [string]::IsNullOrWhiteSpace($saved) -and (Test-Path $saved)) { return $saved }
    }

    Send-Log "No downloadable Cover Art Archive image found; continuing to next cover source." "Warn"
    return ""
}

function Resolve-AlbumCoverPath {
    param(
        [Parameter(Mandatory)] $AlbumInfo,
        [Parameter(Mandatory)] [string]$AlbumDir,
        [string]$ManualCoverPath = "",
        [string]$DiscogsUrl = "",
        [bool]$Fetch = $true
    )
    if (-not [string]::IsNullOrWhiteSpace($ManualCoverPath) -and (Test-Path $ManualCoverPath)) {
        $manual = Save-ManualCoverToAlbumDir -ManualCoverPath $ManualCoverPath -AlbumDir $AlbumDir
        if (-not [string]::IsNullOrWhiteSpace($manual) -and (Test-Path $manual)) { return $manual }
        return $ManualCoverPath
    }
    foreach ($candidate in @((Join-Path $AlbumDir "cover.jpg"),(Join-Path $AlbumDir "cover.png"),(Join-Path $AlbumDir "folder.jpg"),(Join-Path $AlbumDir "folder.png"))) {
        if (Test-Path $candidate) { return $candidate }
    }
    if ($Fetch) {
        $discogs = Save-CoverArtFromDiscogs -AlbumInfo $AlbumInfo -AlbumDir $AlbumDir -DiscogsUrl $DiscogsUrl
        if (-not [string]::IsNullOrWhiteSpace($discogs) -and (Test-Path $discogs)) { return $discogs }

        $downloaded = Save-CoverArtFromMusicBrainz -AlbumInfo $AlbumInfo -AlbumDir $AlbumDir
        if (-not [string]::IsNullOrWhiteSpace($downloaded) -and (Test-Path $downloaded)) { return $downloaded }
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
    $cfg = $global:sync.Cfg
    $info = [ordered]@{ SampleRate = ""; Channels = ""; BitDepth = ""; Duration = "" }
    if ([string]::IsNullOrWhiteSpace($cfg.METAFLAC) -or -not (Test-Path $cfg.METAFLAC) -or -not (Test-Path $Path)) { return $info }
    try {
        $sr = (& $cfg.METAFLAC --show-sample-rate $Path 2>$null | Select-Object -First 1)
        $ch = (& $cfg.METAFLAC --show-channels $Path 2>$null | Select-Object -First 1)
        $bd = (& $cfg.METAFLAC --show-bps $Path 2>$null | Select-Object -First 1)
        $samples = (& $cfg.METAFLAC --show-total-samples $Path 2>$null | Select-Object -First 1)
        if ($sr) { $info.SampleRate = "$sr Hz" }
        if ($ch) { $info.Channels = "$ch" }
        if ($bd) { $info.BitDepth = "$bd-bit" }
        if ($sr -and $samples) { $info.Duration = Format-CDDuration -Seconds ([double]$samples / [double]$sr) }
    } catch { }
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
    $cfg = $global:sync.Cfg
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
        $lines.Add("CD -> FLAC Ripper v1.4.0")
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
        $lines.Add("cdda2wav : $($cfg.CDDA2WAV)")
        $lines.Add("flac     : $($cfg.FLAC)")
        $lines.Add("metaflac : $($cfg.METAFLAC)")
        $lines.Add("libdiscid: $($cfg.LIBDISCID)")
        $lines.Add("")
        $lines.Add("Track List")
        $lines.Add("----------")
        for ($i = 0; $i -lt $TrackTitles.Count; $i++) { $lines.Add(("{0:D2}. {1}" -f ($i + 1), $TrackTitles[$i])) }
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
        Send-Log "Created NFO: $NfoPath" "Good"
    } catch {
        Send-Log "NFO creation failed: $($_.Exception.Message)" "Warn"
    }
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

function ConvertFrom-MBRelease {
    param([Parameter(Mandatory)] $rel)
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
                    if ($t.title) { $tracks += $t.title }
                    elseif ($t.recording -and $t.recording.title) { $tracks += $t.recording.title }
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

function Get-MBMetadata {
    param([Parameter(Mandatory)] [string]$discId)
    $cfg = $global:sync.Cfg
    $encoded = [uri]::EscapeDataString($discId)
    $url = "https://musicbrainz.org/ws/2/discid/$encoded`?inc=artist-credits+labels+recordings+media+discids+release-groups+url-rels&fmt=json"
    Send-Log "Querying MusicBrainz disc endpoint..." "Dim"
    Start-Sleep -Milliseconds 1100
    $r = Invoke-RestMethod -Uri $url -Headers @{ "User-Agent" = $cfg.UserAgent; "Accept" = "application/json" } -TimeoutSec 20
    if (-not $r.releases) { return $null }
    return (ConvertFrom-MBRelease $r.releases[0])
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

function Invoke-MBReleaseLookupRaw {
    param([Parameter(Mandatory)] [string]$ReleaseId)

    $cfg = $global:sync.Cfg
    $encoded = [uri]::EscapeDataString($ReleaseId)
    $url = "https://musicbrainz.org/ws/2/release/$encoded`?inc=artist-credits+labels+recordings+media+discids+release-groups+url-rels&fmt=json"
    Send-Log "MusicBrainz release URL/ID lookup: $ReleaseId" "Dim"
    Start-Sleep -Milliseconds 1100
    return Invoke-RestMethod -Uri $url -Headers @{ "User-Agent" = $cfg.UserAgent; "Accept" = "application/json" } -TimeoutSec 20
}

function Search-MBRelease {
    param(
        [Parameter(Mandatory)] [string]$Artist,
        [Parameter(Mandatory)] [string]$Album
    )

    $cfg = $global:sync.Cfg
    $artistClean = $Artist.Trim()
    $albumClean  = $Album.Trim()
    if ([string]::IsNullOrWhiteSpace($artistClean) -or [string]::IsNullOrWhiteSpace($albumClean)) { return $null }

    $releaseId = Get-MBReleaseIdFromText -Texts @($artistClean, $albumClean)
    if ($releaseId) {
        try {
            $rel = Invoke-MBReleaseLookupRaw -ReleaseId $releaseId
            if ($rel -and $rel.id) { return @($rel) }
        } catch {
            Send-Log "MusicBrainz release URL/ID lookup failed: $($_.Exception.Message)" "Warn"
        }
    }

    $found = @{}
    $queries = @(Get-MBSearchQueries -Artist $artistClean -Album $albumClean)

    foreach ($q in $queries) {
        $query = [uri]::EscapeDataString($q)
        $url = "https://musicbrainz.org/ws/2/release?query=$query&fmt=json&limit=25"
        Send-Log "MusicBrainz text search: $q" "Dim"
        Start-Sleep -Milliseconds 1100
        try {
            $r = Invoke-RestMethod -Uri $url -Headers @{ "User-Agent" = $cfg.UserAgent; "Accept" = "application/json" } -TimeoutSec 20
            if ($r.releases) {
                foreach ($rel in $r.releases) {
                    if ($rel.id -and -not $found.ContainsKey($rel.id)) { $found[$rel.id] = $rel }
                }
            }
            if ($found.Count -ge 10) { break }
        } catch {
            Send-Log "MusicBrainz text search attempt failed: $($_.Exception.Message)" "Warn"
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

function Convert-MBReleasesToCandidates {
    param($Releases)

    $list = @()
    if (-not $Releases) { return $list }

    foreach ($rel in $Releases) {
        $a = ""
        if ($rel.'artist-credit' -and $rel.'artist-credit'.Count -gt 0) { $a = $rel.'artist-credit'[0].name }
        $trackCount = 0
        if ($rel.media) {
            foreach ($m in $rel.media) {
                if ($m.'track-count') { $trackCount += [int]$m.'track-count' }
                elseif ($m.tracks) { $trackCount += [int]$m.tracks.Count }
            }
        }
        $list += [PSCustomObject]@{
            Id = $rel.id
            Artist = $a
            Title = $rel.title
            Date = if ($rel.date) { $rel.date } else { "" }
            Country = if ($rel.country) { $rel.country } else { "" }
            TrackCount = $trackCount
        }
    }

    return $list
}

function Get-MBMetadataByReleaseId {
    param([Parameter(Mandatory)] [string]$ReleaseId)
    $cfg = $global:sync.Cfg
    $encoded = [uri]::EscapeDataString($ReleaseId)
    $url = "https://musicbrainz.org/ws/2/release/$encoded`?inc=artist-credits+labels+recordings+media+discids+release-groups+url-rels&fmt=json"
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
        discId = $DiscId; musicBrainzReleaseId = Get-AlbumInfoValue -AlbumInfo $AlbumInfo -Name "ReleaseId"
        musicBrainzReleaseGroupId = Get-AlbumInfoValue -AlbumInfo $AlbumInfo -Name "ReleaseGroupId"
        musicBrainzUrl = Get-AlbumInfoValue -AlbumInfo $AlbumInfo -Name "MusicBrainzUrl"
        musicBrainzReleaseGroupUrl = Get-AlbumInfoValue -AlbumInfo $AlbumInfo -Name "ReleaseGroupUrl"
        discogsReleaseId = Get-AlbumInfoValue -AlbumInfo $AlbumInfo -Name "DiscogsReleaseId"
        discogsUrl = Get-AlbumInfoValue -AlbumInfo $AlbumInfo -Name "DiscogsUrl"
        artist = $AlbumInfo.Artist; album = $AlbumInfo.Album; year = $AlbumInfo.Year
        date = Get-AlbumInfoValue -AlbumInfo $AlbumInfo -Name "Date"; genre = $AlbumInfo.Genre
        label = Get-AlbumInfoValue -AlbumInfo $AlbumInfo -Name "Label"; country = Get-AlbumInfoValue -AlbumInfo $AlbumInfo -Name "Country"
        status = Get-AlbumInfoValue -AlbumInfo $AlbumInfo -Name "Status"; discTitle = $AlbumInfo.DiscTitle
        performer = $AlbumInfo.Performer; flacFile = $FlacFileName; cueFile = $CueFileName; tracks = $trackObjects
    }
    $payload | ConvertTo-Json -Depth 5 | Set-Content -Path $JsonPath -Encoding UTF8
}

function Save-TracksJson {
    param($JsonPath, $AlbumInfo, [string[]]$TrackTitles, [string[]]$FlacFiles, $DiscId, [object[]]$TrackCoverMap = @())
    $trackObjects = @()
    for ($i = 0; $i -lt $TrackTitles.Count; $i++) {
        $fileName = if ($i -lt $FlacFiles.Count) { $FlacFiles[$i] } else { "" }
        $coverFile = Get-TrackCoverMapValue -TrackCoverMap $TrackCoverMap -TrackNumber ($i + 1)
        if (-not [string]::IsNullOrWhiteSpace($coverFile)) { $coverFile = [System.IO.Path]::GetFileName($coverFile) }
        $trackObjects += [PSCustomObject]@{ number = $i + 1; title = $TrackTitles[$i]; flacFile = $fileName; trackCoverFile = $coverFile }
    }
    $payload = [PSCustomObject]@{
        discId = $DiscId; musicBrainzReleaseId = Get-AlbumInfoValue -AlbumInfo $AlbumInfo -Name "ReleaseId"
        musicBrainzReleaseGroupId = Get-AlbumInfoValue -AlbumInfo $AlbumInfo -Name "ReleaseGroupId"
        musicBrainzUrl = Get-AlbumInfoValue -AlbumInfo $AlbumInfo -Name "MusicBrainzUrl"
        musicBrainzReleaseGroupUrl = Get-AlbumInfoValue -AlbumInfo $AlbumInfo -Name "ReleaseGroupUrl"
        discogsReleaseId = Get-AlbumInfoValue -AlbumInfo $AlbumInfo -Name "DiscogsReleaseId"
        discogsUrl = Get-AlbumInfoValue -AlbumInfo $AlbumInfo -Name "DiscogsUrl"
        artist = $AlbumInfo.Artist; album = $AlbumInfo.Album; year = $AlbumInfo.Year
        date = Get-AlbumInfoValue -AlbumInfo $AlbumInfo -Name "Date"; genre = $AlbumInfo.Genre
        label = Get-AlbumInfoValue -AlbumInfo $AlbumInfo -Name "Label"; country = Get-AlbumInfoValue -AlbumInfo $AlbumInfo -Name "Country"
        status = Get-AlbumInfoValue -AlbumInfo $AlbumInfo -Name "Status"; discTitle = $AlbumInfo.DiscTitle
        performer = $AlbumInfo.Performer; tracks = $trackObjects
        trackCovers = @($TrackCoverMap | ForEach-Object { [PSCustomObject]@{ track = $_.Track; cover = ([System.IO.Path]::GetFileName([string]$_.Cover)) } })
    }
    $payload | ConvertTo-Json -Depth 5 | Set-Content -Path $JsonPath -Encoding UTF8
}

# ── Operation entry points ──────────────────
function Invoke-Detect {
    Test-WorkerTools -RequireRip -WarnMetadataTools

    $job = $global:sync.Job
    $discId = ""
    $artist = ""; $album = ""; $year = ""; $genre = ""
    $tracks = @()
    $trackCount = 0
    $releaseId = ""
    $releaseGroupId = ""
    $searchResults = @()

    $fallbackArtist = ""
    $fallbackAlbum  = ""
    if ($job) {
        if ($job.SearchArtist) { $fallbackArtist = [string]$job.SearchArtist }
        if ($job.SearchAlbum)  { $fallbackAlbum  = [string]$job.SearchAlbum }
    }

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
                $releaseId = $lookup.Album.ReleaseId
                $releaseGroupId = $lookup.Album.ReleaseGroupId
                $discogsUrl = $lookup.Album.DiscogsUrl
                if (-not [string]::IsNullOrWhiteSpace($discogsUrl)) { Send-Log "MusicBrainz linked Discogs release: $discogsUrl" "Good" }
                Send-Log "MusicBrainz match: $artist - $album ($($tracks.Count) tracks)" "Good"
            } else {
                Send-Log "No exact MusicBrainz disc match found." "Warn"
            }
        } catch {
            Send-Log "Disc lookup failed: $($_.Exception.Message)" "Warn"
            Send-Log "Exact DiscID lookup failed. Use Search MB or Open MB for artist/album lookup." "Warn"
        }
    }

    try {
        $probeLog = Probe-Disc
        $trackCount = Resolve-TrackCountFromRipLog -LogPath $probeLog
        Send-Log "Disc reports $trackCount tracks." "Good"
    } catch {
        Send-Log "Disc probe failed: $($_.Exception.Message)" "Warn"
    }

    if (($tracks.Count -lt 1) -and
        -not [string]::IsNullOrWhiteSpace($fallbackArtist) -and
        -not [string]::IsNullOrWhiteSpace($fallbackAlbum)) {
        try {
            Send-Log "Offering MusicBrainz search candidates for: $fallbackArtist - $fallbackAlbum" "Info"
            $results = Search-MBRelease -Artist $fallbackArtist -Album $fallbackAlbum
            $searchResults = Convert-MBReleasesToCandidates $results
            if ($searchResults.Count -gt 0) {
                Send-Log "Found $($searchResults.Count) MusicBrainz candidate release(s). Pick one from the dropdown and click Use." "Good"
            } else {
                Send-Log "No MusicBrainz search candidates found for the fallback artist/album." "Warn"
            }
        } catch {
            Send-Log "MusicBrainz fallback search failed: $($_.Exception.Message)" "Warn"
        }
    } elseif ($tracks.Count -lt 1) {
        Send-Log "No exact MusicBrainz match. Enter Artist + Album, then click Search MB." "Warn"
    }

    return @{
        DiscId = $discId; ReleaseId = $releaseId; ReleaseGroupId = $releaseGroupId; DiscogsUrl = $discogsUrl; Artist = $artist; Album = $album; Year = $year; Genre = $genre
        Tracks = $tracks; TrackCount = $trackCount; SearchResults = $searchResults
    }
}

function Invoke-Search {
    $job = $global:sync.Job
    $results = Search-MBRelease -Artist $job.SearchArtist -Album $job.SearchAlbum
    $list = Convert-MBReleasesToCandidates $results
    if (-not $list -or $list.Count -lt 1) { Send-Log "No MusicBrainz text matches found." "Warn"; return @() }
    Send-Log "Found $($list.Count) candidate release(s)." "Good"
    return $list
}

function Invoke-Release {
    $job = $global:sync.Job
    $lookup = Get-MBMetadataByReleaseId -ReleaseId $job.ReleaseId
    if (-not $lookup) { return $null }
    return @{
        DiscId = ""; ReleaseId = $lookup.Album.ReleaseId; ReleaseGroupId = $lookup.Album.ReleaseGroupId; DiscogsUrl = $lookup.Album.DiscogsUrl; Artist = $lookup.Album.Artist; Album = $lookup.Album.Album
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
        ReleaseId = $job.ReleaseId
        MusicBrainzUrl = if ($job.ReleaseId) { "https://musicbrainz.org/release/$($job.ReleaseId)" } else { "" }
        ReleaseGroupId = $job.ReleaseGroupId
        ReleaseGroupUrl = if ($job.ReleaseGroupId) { "https://musicbrainz.org/release-group/$($job.ReleaseGroupId)" } else { "" }
        DiscogsReleaseId = Get-DiscogsReleaseIdFromText -Texts @($job.DiscogsUrl)
        DiscogsUrl = $job.DiscogsUrl
        Date = $job.Year
        Country = ""
        Status = ""
        Label = ""
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
        $coverPath = Resolve-AlbumCoverPath -AlbumInfo $albumInfo -AlbumDir $dir -ManualCoverPath $job.Cover -DiscogsUrl $job.DiscogsUrl -Fetch:$cfg.FetchArt

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
        if ($coverPath -and (Test-Path $coverPath)) { Embed-Cover $flac $coverPath }

        $nfo = Join-Path $dir ("$base.nfo")
        if ($cfg.CreateNfo) {
            $nfoFiles = @($flac, $cue, $json, $coverPath) | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }
            Write-CDNfo -NfoPath $nfo -Mode "Single FLAC image + CUE" -AlbumInfo $albumInfo -TrackTitles $tracks -Files $nfoFiles -DiscId $job.DiscId -CoverPath $coverPath
        }

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
        $coverPath = Resolve-AlbumCoverPath -AlbumInfo $albumInfo -AlbumDir $albumDir -ManualCoverPath $job.Cover -DiscogsUrl $job.DiscogsUrl -Fetch:$cfg.FetchArt

        $flacFiles = New-Object System.Collections.Generic.List[string]
        $flacPaths = New-Object System.Collections.Generic.List[string]
        $failedTracks = New-Object System.Collections.Generic.List[int]
        $trackCoverMap = New-Object System.Collections.Generic.List[object]
        $trackCoverSources = @()
        if ($job.TrackCovers) { $trackCoverSources = @($job.TrackCovers) }
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

            $embedCoverPath = $coverPath
            $trackCoverSource = ""
            if ($trackCoverSources -and $i -lt $trackCoverSources.Count) { $trackCoverSource = [string]$trackCoverSources[$i] }
            if (-not [string]::IsNullOrWhiteSpace($trackCoverSource) -and (Test-Path $trackCoverSource)) {
                $savedTrackCover = Save-TrackCoverToAlbumDir -TrackCoverPath $trackCoverSource -AlbumDir $albumDir -TrackNumber $trackNum -TrackTitle $trackTitle
                if (-not [string]::IsNullOrWhiteSpace($savedTrackCover) -and (Test-Path $savedTrackCover)) {
                    $embedCoverPath = $savedTrackCover
                    [void]$trackCoverMap.Add([PSCustomObject]@{ Track = $trackNum; Title = $trackTitle; Cover = $savedTrackCover })
                }
            }
            if ($embedCoverPath -and (Test-Path $embedCoverPath)) { Embed-Cover $flacPath $embedCoverPath }
            Remove-Item $wavPath -Force -ErrorAction SilentlyContinue
            [void]$flacFiles.Add([System.IO.Path]::GetFileName($flacPath))
            [void]$flacPaths.Add($flacPath)
            Send-Log ("Created {0:D2} - {1}.flac" -f $trackNum, $trackTitle) "Good"
        }

        if ($failedTracks.Count -gt 0 -or $flacFiles.Count -ne $tracks.Count) {
            Send-Log ("CD track rip finished with failures. Expected {0}, created {1}. Failed tracks: {2}" -f $tracks.Count, $flacFiles.Count, ($failedTracks -join ', ')) "Bad"
        }

        try {
            Save-TracksJson -JsonPath $json -AlbumInfo $albumInfo -TrackTitles $tracks -FlacFiles $flacFiles.ToArray() -DiscId $job.DiscId -TrackCoverMap ($trackCoverMap.ToArray())
            Send-Log "Saved metadata sidecar." "Good"
        } catch {
            Send-Log "Failed to save JSON: $($_.Exception.Message)" "Warn"
        }

        $nfo = Join-Path $albumDir ("$artistSafe - $albumSafe.nfo")
        if ($cfg.CreateNfo) {
            $trackCoverFiles = @($trackCoverMap.ToArray() | ForEach-Object { $_.Cover })
            $nfoFiles = (@($flacPaths.ToArray()) + @($json, $coverPath) + @($trackCoverFiles)) | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }
            Write-CDNfo -NfoPath $nfo -Mode "One FLAC per track" -AlbumInfo $albumInfo -TrackTitles $tracks -Files $nfoFiles -DiscId $job.DiscId -CoverPath $coverPath -TrackCoverMap ($trackCoverMap.ToArray())
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
$form.Text = "CD -> FLAC Ripper v1.4.0"
$form.Size = "1000,1020"
$form.MinimumSize = "900,840"
$form.StartPosition = "CenterScreen"
$form.BackColor = $clrBack
$form.Font = $fontUI

# Header
$header = New-Object System.Windows.Forms.Panel
$header.Dock = "Top"; $header.Height = 52; $header.BackColor = $clrPanel
$hLabel = New-Object System.Windows.Forms.Label
$hLabel.Text = "  CD -> FLAC Ripper v1.4.0"; $hLabel.ForeColor = $clrAccent
$hLabel.Font = $fontHead; $hLabel.Dock = "Fill"; $hLabel.TextAlign = "MiddleLeft"
$header.Controls.Add($hLabel)
$form.Controls.Add($header)

$W = 964   # inner content width baseline
$script:CurrentReleaseId = ""
$script:CurrentReleaseGroupId = ""


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
$txtDrive = New-Text 80 25 70 $CdDrive; $gPaths.Controls.Add($txtDrive)
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
$btnSearch = New-Button "Search MB" 460 132 78 26; $gMeta.Controls.Add($btnSearch)
$cmbResults = New-Object System.Windows.Forms.ComboBox
$cmbResults.Location = "544,133"; $cmbResults.Size = "250,24"; $cmbResults.DropDownStyle = "DropDownList"
$cmbResults.BackColor = $clrInput; $cmbResults.ForeColor = $clrText; $cmbResults.Anchor = "Top,Left,Right"
$cmbResults.FlatStyle = "Flat"; $gMeta.Controls.Add($cmbResults)
$btnUseResult = New-Button "Use" 802 132 60 26; $btnUseResult.Anchor = "Top,Right"; $gMeta.Controls.Add($btnUseResult)
$btnOpenMB = New-Button "Open MB" 872 132 70 26; $btnOpenMB.Anchor = "Top,Right"; $gMeta.Controls.Add($btnOpenMB)
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
$colCover = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
$colCover.HeaderText = "Track Cover"; $colCover.Width = 220
$grid.Columns.Add($colCover) | Out-Null
$gTracks.Controls.Add($grid)

$btnAddRow = New-Button "+ Add" 852 24 90 26; $btnAddRow.Anchor = "Top,Right"; $gTracks.Controls.Add($btnAddRow)
$btnDelRow = New-Button "- Remove" 852 56 90 26; $btnDelRow.Anchor = "Top,Right"; $gTracks.Controls.Add($btnDelRow)
$btnClrRows = New-Button "Clear" 852 88 90 26; $btnClrRows.Anchor = "Top,Right"; $gTracks.Controls.Add($btnClrRows)
$btnSetTrackCover = New-Button "Set Cover" 852 120 90 26; $btnSetTrackCover.Anchor = "Top,Right"; $gTracks.Controls.Add($btnSetTrackCover)
$btnClearTrackCover = New-Button "Clear Cover" 852 152 90 26; $btnClearTrackCover.Anchor = "Top,Right"; $gTracks.Controls.Add($btnClearTrackCover)
$form.Controls.Add($gTracks)

# ── Group: Output ───────────────────────────
$gOut = New-Group "Output" 8 640 $W 126
$gOut.Anchor = "Top,Left,Right"

$rbImage = New-Object System.Windows.Forms.RadioButton
$rbImage.Text = "Single FLAC image + CUE"; $rbImage.Location = "14,26"; $rbImage.Size = "210,22"
$rbImage.ForeColor = $clrText; $gOut.Controls.Add($rbImage)
$rbTracks = New-Object System.Windows.Forms.RadioButton
$rbTracks.Text = "One FLAC per track"; $rbTracks.Location = "240,26"; $rbTracks.Size = "180,22"
$rbTracks.ForeColor = $clrText; $gOut.Controls.Add($rbTracks)
$chkFetchArt = New-Object System.Windows.Forms.CheckBox
$chkFetchArt.Text = "Fetch album art"; $chkFetchArt.Location = "440,26"; $chkFetchArt.Size = "140,22"
$chkFetchArt.ForeColor = $clrText; $chkFetchArt.Checked = $true; $gOut.Controls.Add($chkFetchArt)
$chkNfo = New-Object System.Windows.Forms.CheckBox
$chkNfo.Text = "Create NFO"; $chkNfo.Location = "590,26"; $chkNfo.Size = "120,22"
$chkNfo.ForeColor = $clrText; $chkNfo.Checked = $true; $gOut.Controls.Add($chkNfo)
if ($Mode -eq "tracks") { $rbTracks.Checked = $true } else { $rbImage.Checked = $true }

$gOut.Controls.Add((New-Label "Discogs URL" 14 60 76))
$txtDiscogs = New-Text 94 59 746; $txtDiscogs.Anchor = "Top,Left,Right"; $gOut.Controls.Add($txtDiscogs)
$btnOpenDiscogs = New-Button "Open" 848 58 52 24; $btnOpenDiscogs.Anchor = "Top,Right"; $gOut.Controls.Add($btnOpenDiscogs)

$gOut.Controls.Add((New-Label "Cover" 14 90 44))
$txtCover = New-Text 62 89 800; $txtCover.Anchor = "Top,Left,Right"; $gOut.Controls.Add($txtCover)
$btnCover = New-Button "..." 868 88 32 24; $btnCover.Anchor = "Top,Right"; $gOut.Controls.Add($btnCover)
$form.Controls.Add($gOut)

# ── Action row ──────────────────────────────
$pAct = New-Object System.Windows.Forms.Panel
$pAct.Location = "8,772"; $pAct.Size = "$W,36"; $pAct.BackColor = $clrBack
$pAct.Anchor = "Top,Left,Right"
$btnStart = New-Button "Start Rip" 6 2 160 32 $clrBtnGo
$btnStart.Font = New-Object System.Drawing.Font("Segoe UI Semibold",10); $pAct.Controls.Add($btnStart)
$lblBusy = New-Label "" 176 6 400; $lblBusy.ForeColor = $clrWarn; $pAct.Controls.Add($lblBusy)
$btnOpen = New-Button "Open Output" 700 2 120 32 $clrBtn; $btnOpen.Anchor = "Top,Right"; $pAct.Controls.Add($btnOpen)
$btnClear = New-Button "Clear Log" 828 2 110 32 $clrBtn; $btnClear.Anchor = "Top,Right"; $pAct.Controls.Add($btnClear)
$form.Controls.Add($pAct)

# ── Log ─────────────────────────────────────
$gLog = New-Group "Log" 8 814 $W 150
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
            $grid.Rows.Add(@("", $title, "")) | Out-Null
        }
    }
    elseif ($titles -and $titles.Count -gt 0) {
        foreach ($t in $titles) { $grid.Rows.Add(@("", $t, "")) | Out-Null }
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
        FetchArt  = $chkFetchArt.Checked
        CreateNfo = $chkNfo.Checked
        DiscogsToken = [Environment]::GetEnvironmentVariable("DISCOGS_TOKEN")
        UserAgent = "MikeRedd-CDRipperGUI/1.4.0"
    }
}

function Set-Busy {
    param([bool]$busy, [string]$msg = "")
    $controls = @($btnDetect, $btnSearch, $btnUseResult, $btnOpenMB, $btnOpenDiscogs, $btnStart, $btnAddRow, $btnDelRow, $btnClrRows, $btnSetTrackCover, $btnClearTrackCover)
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

function Set-SearchResults {
    param($results)

    $cmbResults.Items.Clear()
    $script:SearchMap = @()

    if ($results -and $results.Count -gt 0) {
        foreach ($r in $results) {
            $label = "$($r.Artist) - $($r.Title)"
            if ($r.Date)    { $label += "  ($($r.Date))" }
            if ($r.Country) { $label += " [$($r.Country)]" }
            if ($r.TrackCount -gt 0) { $label += "  {$($r.TrackCount) tracks}" }
            [void]$cmbResults.Items.Add($label)
            $script:SearchMap += $r.Id
        }
        $cmbResults.SelectedIndex = 0
    }
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
                if ($res.ReleaseId) { $script:CurrentReleaseId = $res.ReleaseId; Add-LogLine "MusicBrainz release ID: $($res.ReleaseId)" "Dim" }
                if ($res.ReleaseGroupId) { $script:CurrentReleaseGroupId = $res.ReleaseGroupId; Add-LogLine "MusicBrainz release group ID: $($res.ReleaseGroupId)" "Dim" }
                if ($res.DiscogsUrl -and [string]::IsNullOrWhiteSpace($txtDiscogs.Text)) { $txtDiscogs.Text = $res.DiscogsUrl; Add-LogLine "Discogs cover source found from MusicBrainz." "Good" }

                if ([string]::IsNullOrWhiteSpace($txtSearchArtist.Text) -and -not [string]::IsNullOrWhiteSpace($txtArtist.Text)) {
                    $txtSearchArtist.Text = $txtArtist.Text
                }
                if ([string]::IsNullOrWhiteSpace($txtSearchAlbum.Text) -and -not [string]::IsNullOrWhiteSpace($txtAlbum.Text)) {
                    $txtSearchAlbum.Text = $txtAlbum.Text
                }

                Set-Tracks $res.Tracks $res.TrackCount
                if ($res.SearchResults -and $res.SearchResults.Count -gt 0) { Set-SearchResults $res.SearchResults }
            }
        }
        "release" {
            if ($res) {
                if ($res.Artist) { $txtArtist.Text = $res.Artist }
                if ($res.Album)  { $txtAlbum.Text  = $res.Album }
                if ($res.Year)   { $txtYear.Text   = $res.Year }
                if ($res.Genre)  { $txtGenre.Text  = $res.Genre }
                if ($res.ReleaseId) { $script:CurrentReleaseId = $res.ReleaseId; Add-LogLine "MusicBrainz release ID: $($res.ReleaseId)" "Dim" }
                if ($res.ReleaseGroupId) { $script:CurrentReleaseGroupId = $res.ReleaseGroupId; Add-LogLine "MusicBrainz release group ID: $($res.ReleaseGroupId)" "Dim" }
                if ($res.DiscogsUrl -and [string]::IsNullOrWhiteSpace($txtDiscogs.Text)) { $txtDiscogs.Text = $res.DiscogsUrl; Add-LogLine "Discogs cover source found from MusicBrainz." "Good" }
                Set-Tracks $res.Tracks $res.TrackCount
            }
        }
        "search" {
            Set-SearchResults $res
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
$btnSetTrackCover.Add_Click({
    if ($grid.Rows.Count -lt 1) { Add-LogLine "Add tracks before assigning track covers." "Warn"; return }
    $dlg = New-Object System.Windows.Forms.OpenFileDialog
    $dlg.Filter = "Images|*.jpg;*.jpeg;*.png|All files|*.*"
    if ($dlg.ShowDialog() -ne "OK") { return }
    $rows = @()
    foreach ($r in $grid.SelectedRows) { $rows += $r }
    if ($rows.Count -lt 1 -and $grid.CurrentRow) { $rows += $grid.CurrentRow }
    if ($rows.Count -lt 1) { $rows = @($grid.Rows) }
    foreach ($r in $rows) { $r.Cells[2].Value = $dlg.FileName }
    Add-LogLine ("Assigned track cover to {0} row(s)." -f $rows.Count) "Good"
})
$btnClearTrackCover.Add_Click({
    if ($grid.Rows.Count -lt 1) { return }
    $rows = @()
    foreach ($r in $grid.SelectedRows) { $rows += $r }
    if ($rows.Count -lt 1 -and $grid.CurrentRow) { $rows += $grid.CurrentRow }
    if ($rows.Count -lt 1) { $rows = @($grid.Rows) }
    foreach ($r in $rows) { $r.Cells[2].Value = "" }
    Add-LogLine ("Cleared track cover from {0} row(s)." -f $rows.Count) "Dim"
})
$btnOpenDiscogs.Add_Click({
    $url = $txtDiscogs.Text.Trim()
    if ([string]::IsNullOrWhiteSpace($url)) {
        $queryText = ("{0} {1}" -f $txtArtist.Text.Trim(), $txtAlbum.Text.Trim()).Trim()
        if ([string]::IsNullOrWhiteSpace($queryText)) {
            Add-LogLine "Enter a Discogs release URL, or fill Artist and Album before opening Discogs." "Warn"
            return
        }
        $q = [uri]::EscapeDataString($queryText)
        $url = "https://www.discogs.com/search/?q=$q&type=release"
    }
    Add-LogLine "Opening Discogs in your browser." "Info"
    Start-Process $url
})

$btnDetect.Add_Click({
    $fallbackArtist = if ([string]::IsNullOrWhiteSpace($txtSearchArtist.Text)) { $txtArtist.Text.Trim() } else { $txtSearchArtist.Text.Trim() }
    $fallbackAlbum  = if ([string]::IsNullOrWhiteSpace($txtSearchAlbum.Text))  { $txtAlbum.Text.Trim()  } else { $txtSearchAlbum.Text.Trim() }
    $sync.Job = @{ SearchArtist = $fallbackArtist; SearchAlbum = $fallbackAlbum }
    Set-Busy $true "Reading disc and querying MusicBrainz..."
    Add-LogLine "Detecting disc..." "Info"
    Start-Op "detect"
})

$btnSearch.Add_Click({
    if ([string]::IsNullOrWhiteSpace($txtSearchArtist.Text) -and -not [string]::IsNullOrWhiteSpace($txtArtist.Text)) {
        $txtSearchArtist.Text = $txtArtist.Text.Trim()
    }
    if ([string]::IsNullOrWhiteSpace($txtSearchAlbum.Text) -and -not [string]::IsNullOrWhiteSpace($txtAlbum.Text)) {
        $txtSearchAlbum.Text = $txtAlbum.Text.Trim()
    }
    if ([string]::IsNullOrWhiteSpace($txtSearchArtist.Text) -or [string]::IsNullOrWhiteSpace($txtSearchAlbum.Text)) {
        Add-LogLine "Enter Artist and Album, then click Search MB." "Warn"; return
    }
    $sync.Job = @{ SearchArtist = $txtSearchArtist.Text.Trim(); SearchAlbum = $txtSearchAlbum.Text.Trim() }
    Set-Busy $true "Searching MusicBrainz..."
    Add-LogLine "Searching MusicBrainz for: $($sync.Job.SearchArtist) - $($sync.Job.SearchAlbum)" "Info"
    Start-Op "search"
})

$btnOpenMB.Add_Click({
    $artist = if ([string]::IsNullOrWhiteSpace($txtSearchArtist.Text)) { $txtArtist.Text.Trim() } else { $txtSearchArtist.Text.Trim() }
    $album  = if ([string]::IsNullOrWhiteSpace($txtSearchAlbum.Text))  { $txtAlbum.Text.Trim()  } else { $txtSearchAlbum.Text.Trim() }
    $queryText = ("{0} {1}" -f $artist, $album).Trim()
    if ([string]::IsNullOrWhiteSpace($queryText)) {
        Add-LogLine "Enter Artist and Album before opening MusicBrainz search." "Warn"
        return
    }
    $q = [uri]::EscapeDataString($queryText)
    $url = "https://musicbrainz.org/search?query=$q&type=release&method=indexed"
    Add-LogLine "Opening MusicBrainz release search in your browser." "Info"
    Start-Process $url
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

$btnAddRow.Add_Click({ $grid.Rows.Add(@("", "", "")) | Out-Null; Renumber-Grid })
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
    # Gather track titles and optional per-track cover paths
    $titles = @()
    $trackCovers = @()
    for ($i = 0; $i -lt $grid.Rows.Count; $i++) {
        $v = $grid.Rows[$i].Cells[1].Value
        if ($null -ne $v -and -not [string]::IsNullOrWhiteSpace([string]$v)) { $titles += [string]$v }
        else { $titles += "Track $($i+1)" }
        $coverCell = $grid.Rows[$i].Cells[2].Value
        if ($null -ne $coverCell -and -not [string]::IsNullOrWhiteSpace([string]$coverCell)) { $trackCovers += [string]$coverCell }
        else { $trackCovers += "" }
    }

    if ([string]::IsNullOrWhiteSpace($txtArtist.Text) -or [string]::IsNullOrWhiteSpace($txtAlbum.Text)) {
        Add-LogLine "Artist and Album are required." "Warn"; return
    }
    if ($titles.Count -lt 1) {
        Add-LogLine "Add at least one track (use Detect or + Add)." "Warn"; return
    }

    $mode = if ($rbTracks.Checked) { "tracks" } else { "image" }
    if ($mode -eq "image" -and (@($trackCovers | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }).Count -gt 0)) {
        Add-LogLine "Per-track covers are only used in One FLAC per track mode; image+CUE uses the main Cover only." "Warn"
    }
    $sync.Job = @{
        Mode   = $mode
        Artist = $txtArtist.Text.Trim()
        Album  = $txtAlbum.Text.Trim()
        Year   = $txtYear.Text.Trim()
        Genre  = $txtGenre.Text.Trim()
        DiscId = ($lblDiscId.Text -replace '^DiscID:\s*', '')
        ReleaseId = $script:CurrentReleaseId
        ReleaseGroupId = $script:CurrentReleaseGroupId
        Tracks = $titles
        Cover  = $txtCover.Text.Trim()
        TrackCovers = $trackCovers
        DiscogsUrl = $txtDiscogs.Text.Trim()
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

$form.Add_Shown({
    if ($AutoDetect) {
        Add-LogLine "Auto-detect requested from Media Encoder GUI." "Info"
        $btnDetect.PerformClick()
    }
})

Add-LogLine "Ready. Insert a disc, then Detect or fill metadata manually." "Dim"
[void]$form.ShowDialog()
