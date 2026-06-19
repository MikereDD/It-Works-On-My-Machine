#--------------------------------------------
# file:     minfocreate.ps1
# author:   Mike Redd
# version:  2.5
# created:  2026-04-11
# updated:  2026-06-17
# desc:     Create NFO, HTML, and poster data
#           for a video file using OMDb and
#           MediaInfo CLI. Optional -Preview pops
#           the downloaded poster in a window.
#           v2.0: -Mode series/docu builds per-episode
#           NFOs + a series index for whole folders.
#           v2.1: per-episode NFO names mirror source files.
#           v2.2: index/poster name derived from files, no numbers.
#           v2.3: main .nfo for the set + local poster fallback.
#           v2.4: figlet banner restored in series/episode NFOs.
#           v2.5: reliable poster download w/ curl --fail + clear logging.
#--------------------------------------------

param(
    [string]$VideoDir  = "",
    [string]$VideoFile = "",
    [string]$ApiKey    = "",
    [ValidateSet('auto','single','series','docu')]
    [string]$Mode      = 'auto',
    [string]$SeriesName = "",
    [switch]$Preview
)

# ── Load custom UI ────────────────────────────────────────────
$uiPath = "$env:USERPROFILE\PS\profile.d\ui.ps1"
if (Test-Path -LiteralPath $uiPath) {
    try {
        . $uiPath
    } catch {
        Write-Host "Failed to load ui.ps1: $($_.Exception.Message)"
        return
    }
} else {
    Write-Host "Missing ui.ps1: $uiPath"
    return
}

# ── Load core helper ──────────────────────────────────────────
$corePath = "$env:USERPROFILE\PS\profile.d\core.ps1"
if (Test-Path -LiteralPath $corePath) {
    try {
        . $corePath
    } catch {
        Write-Host "Failed to load core.ps1: $($_.Exception.Message)"
        Pause-UiReturn "Press Enter to return..."
        return
    }
} else {
    Write-Host "Missing core.ps1: $corePath"
    Pause-UiReturn "Press Enter to return..."
    return
}

$ErrorActionPreference = 'Stop'

$ScriptName    = "MiNfoCreate"
$ScriptVersion = "2.5"
$ScriptAuthor  = "Mike Redd"

# Shared NFO banner (figlet) reused by single-file and multi-file output.
$Script:MinfoFiglet = @"
╔════════════════════════════════════════════════════════════════════════════╗
║                                                                            ║
║                 ███╗   ███╗██╗███╗   ██╗███████╗ ██████╗                   ║
║                 ████╗ ████║██║████╗  ██║██╔════╝██╔═══██╗                  ║
║                 ██╔████╔██║██║██╔██╗ ██║█████╗  ██║   ██║                  ║
║                 ██║╚██╔╝██║██║██║╚██╗██║██╔══╝  ██║   ██║                  ║
║                 ██║ ╚═╝ ██║██║██║ ╚████║██║     ╚██████╔╝                  ║
║                 ╚═╝     ╚═╝╚═╝╚═╝  ╚═══╝╚═╝      ╚═════╝                   ║
║                                                                            ║
║                  N F O   C R E A T O R   ·   by Mike Redd                  ║
╚════════════════════════════════════════════════════════════════════════════╝
"@

# ── Config ────────────────────────────────────────────────────
$Script:ConfigPaths = @(
    "$env:USERPROFILE\PS\profile.d\minforc.ps1",
    "$PSScriptRoot\minforc.ps1",
    "$HOME\.config\minforc.ps1"
)

foreach ($cp in $Script:ConfigPaths) {
    if (Test-Path -LiteralPath $cp) {
        . $cp
        break
    }
}

if (-not $ApiKey) {
    $ApiKey = $global:OMDB_API_KEY
}

if (-not $ApiKey -or $ApiKey -eq "your_api_key_here") {
    Clear-UiScreen
    Write-UiHeader -Title $ScriptName -Subtitle "v$ScriptVersion  by $ScriptAuthor" -Width (Get-UiBoxWidth -MaxWidth 60 -MinWidth 44)
    Write-UiRow "Status" "OMDB_API_KEY not set" $global:UI_RED
    Write-UiBlankLine
    Write-Host "  $($global:UI_CYN)Get a free key at: https://www.omdbapi.com/apikey.aspx$($global:UI_R)"
    Write-Host "  $($global:UI_YLW)Then set it in minforc.ps1$($global:UI_R)"
    Write-UiBlankLine
    Pause-UiReturn "Press Enter to return..."
    return
}

if (-not $VideoDir) {
    $VideoDir = if ($global:MINFO_VIDEODIR) { $global:MINFO_VIDEODIR } else { "G:\Rip\done" }
}

$Script:NfoDir    = if ($global:MINFO_NFODIR)    { $global:MINFO_NFODIR }    else { "G:\Rip\nfo" }
$Script:PosterDir = if ($global:MINFO_POSTERDIR) { $global:MINFO_POSTERDIR } else { "G:\Rip\meta\posters" }

if (-not $Preview -and $global:MINFO_PREVIEW) {
    $Preview = [bool]$global:MINFO_PREVIEW
}

New-Item -ItemType Directory -Path $Script:NfoDir    -Force | Out-Null
New-Item -ItemType Directory -Path $Script:PosterDir -Force | Out-Null

# ── Helpers ───────────────────────────────────────────────────
function ConvertTo-HtmlSafe {
    param([string]$Text)
    if ($null -eq $Text) { return "" }
    return ($Text -replace '&', '&amp;' -replace '<', '&lt;' -replace '>', '&gt;' -replace '"', '&quot;' -replace "'", '&#39;')
}

function Show-PosterWindow {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ImagePath
    )

    if (-not (Test-Path -LiteralPath $ImagePath)) {
        Write-Host "  $($global:UI_YLW)Image not found: $ImagePath$($global:UI_R)"
        return
    }

    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing

    $form = New-Object System.Windows.Forms.Form
    $form.Text = "Poster Preview"
    $form.StartPosition = "CenterScreen"
    $form.Width = 700
    $form.Height = 1000
    $form.BackColor = [System.Drawing.Color]::Black
    $form.KeyPreview = $true
    $form.TopMost = $true

    $pictureBox = New-Object System.Windows.Forms.PictureBox
    $pictureBox.Dock = [System.Windows.Forms.DockStyle]::Fill
    $pictureBox.SizeMode = [System.Windows.Forms.PictureBoxSizeMode]::Zoom
    $pictureBox.BackColor = [System.Drawing.Color]::Black

    try {
        $fs = [System.IO.File]::Open($ImagePath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read)
        try {
            $imgTemp = [System.Drawing.Image]::FromStream($fs)
            $bmp = New-Object System.Drawing.Bitmap $imgTemp
            $imgTemp.Dispose()
        } finally {
            $fs.Close()
            $fs.Dispose()
        }
        $pictureBox.Image = $bmp
    } catch {
        Write-Host "  $($global:UI_YLW)Failed to load image: $($_.Exception.Message)$($global:UI_R)"
        return
    }

    $form.Controls.Add($pictureBox)

    $form.Add_KeyDown({
        param($sender, $e)
        if ($e.KeyCode -eq [System.Windows.Forms.Keys]::Escape -or $e.KeyCode -eq [System.Windows.Forms.Keys]::Q) {
            $sender.Close()
        }
    })

    $form.Add_FormClosed({
        if ($pictureBox.Image) {
            $pictureBox.Image.Dispose()
        }
    })

    [void]$form.ShowDialog()
}

function Show-Header {
    Clear-UiScreen
    $w = Get-UiBoxWidth -MaxWidth 64 -MinWidth 46

    Write-UiHeader -Title $ScriptName -Subtitle "v$ScriptVersion  by $ScriptAuthor" -Width $w
    Write-UiRow "User"      "$env:USERNAME@$env:COMPUTERNAME"
    Write-UiRow "VideoDir"  $VideoDir $global:UI_GRY
    Write-UiRow "NfoDir"    $Script:NfoDir $global:UI_GRY
    Write-UiRow "PosterDir" $Script:PosterDir $global:UI_GRY
    Write-UiBlankLine
}

function Pause-Script {
    Pause-Core "Press Enter to return..."
}

function Show-ResultTable {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        return
    }

    Write-UiBlankLine
    Write-UiDivider
    Get-ChildItem -LiteralPath $Path | Format-Table Name, @{N="Size";E={
        if ($_.PSIsContainer) { "<DIR>" }
        elseif ($_.Length -ge 1MB) { "{0:N1} MB" -f ($_.Length / 1MB) }
        elseif ($_.Length -ge 1KB) { "{0:N1} KB" -f ($_.Length / 1KB) }
        else { "$($_.Length) B" }
    }}, LastWriteTime -AutoSize
    Write-UiBlankLine
}

function Add-TechSection {
    param(
        [System.Collections.Generic.List[string]]$Lines,
        [string]$Title
    )

    $Lines.Add("[ $Title ]")
    $Lines.Add("--------------------------------------------------------------------------------")
}

function Add-TechRow {
    param(
        [System.Collections.Generic.List[string]]$Lines,
        [string]$Label,
        [string]$Value
    )

    if ([string]::IsNullOrWhiteSpace($Value)) { return }
    if ($Value -eq "N/A") { return }

    $Lines.Add(("{0,-24} : {1}" -f $Label, $Value))
}

function Convert-EncodingSettingsToRows {
    param(
        [string]$SettingsText
    )

    $rows = New-Object System.Collections.Generic.List[string]

    if ([string]::IsNullOrWhiteSpace($SettingsText)) {
        return $rows
    }

    $parts = $SettingsText -split '\s*/\s*'

    foreach ($part in $parts) {
        $item = $part.Trim()
        if (-not $item) { continue }

        if ($item -match '=') {
            $k, $v = $item -split '=', 2
            $rows.Add(("{0,-24} : {1}" -f $k.Trim(), $v.Trim()))
        } else {
            $rows.Add(("{0,-24} : enabled" -f $item))
        }
    }

    return $rows
}

function Get-FirstTrack {
    param(
        [object[]]$Tracks,
        [string]$Type
    )

    return $Tracks | Where-Object { $_.'@type' -eq $Type } | Select-Object -First 1
}

function Get-StringValue {
    param(
        [object]$Track,
        [string[]]$Names
    )

    if (-not $Track) { return $null }

    foreach ($name in $Names) {
        if ($Track.PSObject.Properties.Name -contains $name) {
            $value = $Track.$name
            if ($null -ne $value -and "$value".Trim()) {
                return "$value"
            }
        }
    }

    return $null
}

function Get-ResolutionString {
    param([object]$Track)

    if (-not $Track) { return $null }

    $width  = Get-StringValue -Track $Track -Names @('Width', 'Width_String')
    $height = Get-StringValue -Track $Track -Names @('Height', 'Height_String')

    if ($width -and $height) {
        $widthClean  = ($width  -replace '\s+pixels?', '').Trim()
        $heightClean = ($height -replace '\s+pixels?', '').Trim()
        return "$widthClean x $heightClean"
    }

    return $null
}

function Format-MediaInfoFromJson {
    param(
        [object]$MediaInfoObj
    )

    if (-not $MediaInfoObj -or -not $MediaInfoObj.media -or -not $MediaInfoObj.media.track) {
        return "No MediaInfo available."
    }

    $lines  = New-Object System.Collections.Generic.List[string]
    $tracks = @($MediaInfoObj.media.track)

    $general = Get-FirstTrack -Tracks $tracks -Type 'General'
    $video   = Get-FirstTrack -Tracks $tracks -Type 'Video'
    $audio   = Get-FirstTrack -Tracks $tracks -Type 'Audio'
    $text    = Get-FirstTrack -Tracks $tracks -Type 'Text'

    if ($general) {
        Add-TechSection -Lines $lines -Title "GENERAL"
        Add-TechRow -Lines $lines -Label "Complete Name"       -Value (Get-StringValue -Track $general -Names @('CompleteName', 'CompleteName_String'))
        Add-TechRow -Lines $lines -Label "Format"              -Value (Get-StringValue -Track $general -Names @('Format'))
        Add-TechRow -Lines $lines -Label "Format Version"      -Value (Get-StringValue -Track $general -Names @('Format_Version'))
        Add-TechRow -Lines $lines -Label "File Size"           -Value (Get-StringValue -Track $general -Names @('FileSize_String4','FileSize_String3','FileSize_String2','FileSize_String'))
        Add-TechRow -Lines $lines -Label "Duration"            -Value (Get-StringValue -Track $general -Names @('Duration_String3','Duration_String2','Duration_String'))
        Add-TechRow -Lines $lines -Label "Overall Bit Rate"    -Value (Get-StringValue -Track $general -Names @('OverallBitRate_String'))
        Add-TechRow -Lines $lines -Label "Frame Rate"          -Value (Get-StringValue -Track $general -Names @('FrameRate_String'))
        Add-TechRow -Lines $lines -Label "Writing Application" -Value (Get-StringValue -Track $general -Names @('WritingApplication'))
        Add-TechRow -Lines $lines -Label "Writing Library"     -Value (Get-StringValue -Track $general -Names @('WritingLibrary'))
        $lines.Add("")
    }

    if ($video) {
        Add-TechSection -Lines $lines -Title "VIDEO"
        Add-TechRow -Lines $lines -Label "Format"              -Value (Get-StringValue -Track $video -Names @('Format'))
        Add-TechRow -Lines $lines -Label "Profile"             -Value (Get-StringValue -Track $video -Names @('Format_Profile'))
        Add-TechRow -Lines $lines -Label "Codec ID"            -Value (Get-StringValue -Track $video -Names @('CodecID'))
        Add-TechRow -Lines $lines -Label "Duration"            -Value (Get-StringValue -Track $video -Names @('Duration_String3','Duration_String2','Duration_String'))
        Add-TechRow -Lines $lines -Label "Resolution"          -Value (Get-ResolutionString -Track $video)
        Add-TechRow -Lines $lines -Label "Aspect Ratio"        -Value (Get-StringValue -Track $video -Names @('DisplayAspectRatio_String','DisplayAspectRatio'))
        Add-TechRow -Lines $lines -Label "Frame Rate"          -Value (Get-StringValue -Track $video -Names @('FrameRate_String','FrameRate'))
        Add-TechRow -Lines $lines -Label "Color Space"         -Value (Get-StringValue -Track $video -Names @('ColorSpace'))
        Add-TechRow -Lines $lines -Label "Chroma Subsampling"  -Value (Get-StringValue -Track $video -Names @('ChromaSubsampling_String','ChromaSubsampling'))
        Add-TechRow -Lines $lines -Label "Bit Depth"           -Value (Get-StringValue -Track $video -Names @('BitDepth_String','BitDepth'))
        Add-TechRow -Lines $lines -Label "Scan Type"           -Value (Get-StringValue -Track $video -Names @('ScanType'))
        Add-TechRow -Lines $lines -Label "Scan Order"          -Value (Get-StringValue -Track $video -Names @('ScanOrder'))
        Add-TechRow -Lines $lines -Label "Writing Library"     -Value (Get-StringValue -Track $video -Names @('WritingLibrary'))
        $lines.Add("")
    }

    if ($audio) {
        Add-TechSection -Lines $lines -Title "AUDIO"
        Add-TechRow -Lines $lines -Label "Format"              -Value (Get-StringValue -Track $audio -Names @('Format'))
        Add-TechRow -Lines $lines -Label "Commercial Name"     -Value (Get-StringValue -Track $audio -Names @('Format_Commercial_IfAny'))
        Add-TechRow -Lines $lines -Label "Duration"            -Value (Get-StringValue -Track $audio -Names @('Duration_String3','Duration_String2','Duration_String'))
        Add-TechRow -Lines $lines -Label "Channels"            -Value (Get-StringValue -Track $audio -Names @('Channel_s_', 'Channel_s__String'))
        Add-TechRow -Lines $lines -Label "Channel Layout"      -Value (Get-StringValue -Track $audio -Names @('ChannelLayout'))
        Add-TechRow -Lines $lines -Label "Sampling Rate"       -Value (Get-StringValue -Track $audio -Names @('SamplingRate_String','SamplingRate'))
        Add-TechRow -Lines $lines -Label "Bit Depth"           -Value (Get-StringValue -Track $audio -Names @('BitDepth_String','BitDepth'))
        Add-TechRow -Lines $lines -Label "Compression Mode"    -Value (Get-StringValue -Track $audio -Names @('Compression_Mode'))
        Add-TechRow -Lines $lines -Label "Language"            -Value (Get-StringValue -Track $audio -Names @('Language'))
        $lines.Add("")
    }

    if ($text) {
        Add-TechSection -Lines $lines -Title "TEXT"
        Add-TechRow -Lines $lines -Label "Format"              -Value (Get-StringValue -Track $text -Names @('Format'))
        Add-TechRow -Lines $lines -Label "Codec ID"            -Value (Get-StringValue -Track $text -Names @('CodecID'))
        Add-TechRow -Lines $lines -Label "Duration"            -Value (Get-StringValue -Track $text -Names @('Duration_String3','Duration_String2','Duration_String'))
        Add-TechRow -Lines $lines -Label "Language"            -Value (Get-StringValue -Track $text -Names @('Language'))
        Add-TechRow -Lines $lines -Label "Default"             -Value (Get-StringValue -Track $text -Names @('Default'))
        Add-TechRow -Lines $lines -Label "Forced"              -Value (Get-StringValue -Track $text -Names @('Forced'))
        $lines.Add("")
    }

    $encodingSource = $null
    if ($video) {
        $encodingSource = Get-StringValue -Track $video -Names @('Encoded_Library_Settings')
    }
    if (-not $encodingSource -and $general) {
        $encodingSource = Get-StringValue -Track $general -Names @('Encoded_Library_Settings')
    }

    if ($encodingSource) {
        Add-TechSection -Lines $lines -Title "ENCODING SETTINGS"
        $rows = Convert-EncodingSettingsToRows -SettingsText $encodingSource
        foreach ($row in $rows) {
            $lines.Add($row)
        }
        $lines.Add("")
    }

    return ($lines -join "`r`n").Trim()
}

# ── Find curl.exe ─────────────────────────────────────────────
$curlExe = $null
foreach ($c in @(
    "$env:SystemRoot\System32\curl.exe",
    "$env:SystemRoot\SysWOW64\curl.exe"
)) {
    if (Test-Path -LiteralPath $c) {
        $curlExe = $c
        break
    }
}

if (-not $curlExe) {
    Show-Header
    Write-UiRow "curl.exe" "not found" $global:UI_RED
    Write-UiBlankLine
    Pause-Script
    return
}

# ── Find MediaInfo ────────────────────────────────────────────
$mediaInfoExe = $null
$miCmd = Get-Command mediainfo -ErrorAction SilentlyContinue
if ($miCmd) {
    $mediaInfoExe = $miCmd.Source
} else {
    foreach ($mp in @(
        "C:\Program Files\MediaInfo\MediaInfo.exe",
        "C:\Program Files (x86)\MediaInfo\MediaInfo.exe",
        "$HOME\scoop\shims\mediainfo.exe"
    )) {
        if (Test-Path -LiteralPath $mp) {
            $mediaInfoExe = $mp
            break
        }
    }
}

# ══ Multi-file (series / documentary) support ═════════════════
function Get-MinfoVideoFiles {
    param([string]$Dir)
    $exts = @('.mkv','.mp4','.avi','.m2ts','.mov','.wmv','.ts')
    Get-ChildItem -LiteralPath $Dir -File |
        Where-Object { $exts -contains $_.Extension.ToLower() }
}

function Get-SeasonEpisode {
    param([string]$Name)
    $m = [regex]::Match($Name, '(?i)S\s*(\d{1,2})\s*[-_. ]*\s*E\s*(\d{1,3})')
    if ($m.Success) {
        return [pscustomobject]@{ Season = [int]$m.Groups[1].Value; Episode = [int]$m.Groups[2].Value }
    }
    $m = [regex]::Match($Name, '(?i)\b(\d{1,2})\s*x\s*(\d{1,3})\b')
    if ($m.Success) {
        return [pscustomobject]@{ Season = [int]$m.Groups[1].Value; Episode = [int]$m.Groups[2].Value }
    }
    return $null
}

function Get-MinfoDefaultName {
    # Derive a show/documentary name from the source filenames: drop a leading
    # episode/part number ("01 - "), drop a trailing SxxExx or Part N, then take
    # the common stem. Used only as the default the user can override.
    param([object[]]$Files)
    if (-not $Files -or @($Files).Count -lt 1) { return "" }

    $cleaned = New-Object System.Collections.Generic.List[string]
    foreach ($f in $Files) {
        $x = [System.IO.Path]::GetFileNameWithoutExtension($f.Name)
        $x = $x -replace '^\s*\d{1,3}\s*[-_.)\]]\s*', ''
        $x = $x -replace '(?i)[\s_.\-]+S\d{1,2}[\s_.\-]*E\d{1,3}.*$', ''
        $x = $x -replace '(?i)[\s_.\-]+(Part|Pt|CD|Disc|Disk)[\s_.\-]*\d+.*$', ''
        $x = ($x -replace '[\s_.\-]+$', '').Trim()
        if ($x) { $cleaned.Add($x) }
    }
    if ($cleaned.Count -lt 1) { return "" }

    $lcp = $cleaned[0]
    foreach ($n in $cleaned) {
        $i = 0
        $max = [Math]::Min($lcp.Length, $n.Length)
        while ($i -lt $max -and $lcp[$i] -eq $n[$i]) { $i++ }
        $lcp = $lcp.Substring(0, $i)
    }
    $lcp = ($lcp -replace '[\s_.\-]+$', '').Trim()
    if ($lcp) { return $lcp }
    return $cleaned[0]
}

function Invoke-OmdbQuery {
    param([hashtable]$Params, [string]$ApiKey, [string]$CurlExe)
    $qs = @("apikey=$ApiKey")
    foreach ($k in $Params.Keys) {
        $qs += ("{0}={1}" -f $k, [System.Uri]::EscapeDataString([string]$Params[$k]))
    }
    $url = "http://www.omdbapi.com/?" + ($qs -join '&')
    try {
        $raw = & $CurlExe --silent --max-time 15 $url
        $obj = $raw | ConvertFrom-Json
        if ($obj.Response -eq 'True') { return $obj }
    } catch { }
    return $null
}

function Get-MinfoTechText {
    param([string]$File, [string]$MediaInfoExe)
    if (-not $MediaInfoExe) {
        return "MediaInfo CLI not installed. Install with: winget install MediaArea.MediaInfo.CLI"
    }
    try {
        $json = & $MediaInfoExe --Output=JSON $File 2>$null
        $obj  = $json | ConvertFrom-Json
        return (Format-MediaInfoFromJson -MediaInfoObj $obj)
    } catch {
        return "MediaInfo parsing failed."
    }
}

function Invoke-MinfoSeries {
    param(
        [string]$Mode,
        [object[]]$Files,
        [string]$SeriesName,
        [string]$ApiKey,
        [string]$CurlExe,
        [string]$MediaInfoExe,
        [string]$NfoDir,
        [switch]$Preview
    )

    $isSeries = ($Mode -eq 'series')
    $kindWord = if ($isSeries) { 'TV series' } else { 'documentary' }

    if (-not $SeriesName) {
        $defaultName = Get-MinfoDefaultName -Files $Files
        if (-not $defaultName) { $defaultName = Split-Path -Leaf $VideoDir }
        Write-UiBlankLine
        Write-Host "  $($global:UI_YLW)$kindWord name:$($global:UI_R)"
        Write-Host "  $($global:UI_GRN)Default: $defaultName$($global:UI_R)"
        $inp = Read-Host "  Name (blank = default)"
        $SeriesName = if ([string]::IsNullOrWhiteSpace($inp)) { $defaultName } else { $inp }
    }
    $safeSeries = ($SeriesName -replace '[<>:"/\\|?*]', '').Trim()
    if (-not $safeSeries) { $safeSeries = 'Series' }

    Write-UiSection "OMDb Lookup ($kindWord)"
    Write-Host "  $($global:UI_CYN)Enter search title or IMDb ID (blank = '$SeriesName')$($global:UI_R)"
    $search = Read-Host "  Search"
    if ([string]::IsNullOrWhiteSpace($search)) { $search = $SeriesName }
    $year = Read-Host "  Year (optional)"

    $omType = if ($isSeries) { 'series' } else { 'movie' }
    if ($search -match '^tt\d+') {
        $showParams = @{ i = $search; plot = 'full' }
    } else {
        $showParams = @{ t = $search; type = $omType; plot = 'full' }
        if ($year) { $showParams['y'] = $year }
    }
    $show = Invoke-OmdbQuery -Params $showParams -ApiKey $ApiKey -CurlExe $CurlExe
    if ($show) {
        Write-Host "  $($global:UI_GRN)Found: $($show.Title) ($($show.Year))$($global:UI_R)"
    } else {
        Write-Host "  $($global:UI_YLW)No OMDb match; continuing with MediaInfo only.$($global:UI_R)"
    }
    $seriesImdb = if ($show) { $show.imdbID } else { $null }

    $outDir = Join-Path $NfoDir $safeSeries
    New-Item -ItemType Directory -Path $outDir -Force | Out-Null
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

    $posterRel = ""
    $posterOut = Join-Path $outDir "$safeSeries.jpg"

    # 1) OMDb poster (the path TV/movie titles OMDb carries use).
    if ($show -and $show.Poster -and $show.Poster -ne 'N/A') {
        Write-Host "  $($global:UI_CYN)Downloading poster:$($global:UI_R) $($show.Poster)"
        & $CurlExe --silent --show-error --location --fail --max-time 30 --output $posterOut $show.Poster
        $curlExit = $LASTEXITCODE
        if ($curlExit -eq 0 -and (Test-Path -LiteralPath $posterOut) -and (Get-Item -LiteralPath $posterOut).Length -gt 0) {
            $posterRel = "$safeSeries.jpg"
            Write-Host "  $($global:UI_GRN)Poster saved:$($global:UI_R) $safeSeries.jpg"
        } else {
            Write-Host "  $($global:UI_YLW)Poster download failed (curl exit $curlExit).$($global:UI_R)"
            if (Test-Path -LiteralPath $posterOut) { Remove-Item -LiteralPath $posterOut -Force -ErrorAction SilentlyContinue }
        }
    } elseif ($show) {
        Write-Host "  $($global:UI_GRY)OMDb has no poster for this title.$($global:UI_R)"
    }

    # 2) Local cover art fallback from the source folder.
    if (-not $posterRel) {
        foreach ($cand in @('poster.jpg','folder.jpg','cover.jpg','poster.png','folder.png','cover.png')) {
            $candPath = Join-Path $VideoDir $cand
            if (Test-Path -LiteralPath $candPath) {
                try {
                    Copy-Item -LiteralPath $candPath -Destination $posterOut -Force
                    $posterRel = "$safeSeries.jpg"
                    Write-Host "  $($global:UI_GRN)Poster (local):$($global:UI_R) $cand"
                } catch {
                    Write-Host "  $($global:UI_YLW)Local poster copy failed: $($_.Exception.Message)$($global:UI_R)"
                }
                break
            }
        }
    }

    if (-not $posterRel) {
        Write-Host "  $($global:UI_GRY)No poster (no OMDb art, no local cover image).$($global:UI_R)"
    }

    if ($isSeries) {
        $sorted = $Files | Sort-Object `
            @{Expression={ $se = Get-SeasonEpisode $_.Name; if ($se) { $se.Season } else { 99 } }}, `
            @{Expression={ $se = Get-SeasonEpisode $_.Name; if ($se) { $se.Episode } else { 999 } }}, `
            Name
    } else {
        $sorted = $Files | Sort-Object Name
    }

    $records = New-Object System.Collections.Generic.List[object]
    $idx = 0

    foreach ($f in $sorted) {
        $idx++
        $se = if ($isSeries) { Get-SeasonEpisode $f.Name } else { $null }

        $ep = $null
        if ($isSeries -and $se -and $seriesImdb) {
            $ep = Invoke-OmdbQuery -Params @{ i = $seriesImdb; Season = $se.Season; Episode = $se.Episode; plot = 'full' } -ApiKey $ApiKey -CurlExe $CurlExe
        }

        $tech = Get-MinfoTechText -File $f.FullName -MediaInfoExe $MediaInfoExe

        $epLabel = if ($se) { ("S{0:D2}E{1:D2}" -f $se.Season, $se.Episode) } elseif (-not $isSeries) { "Part {0}" -f $idx } else { "#{0}" -f $idx }
        $epTitle = if ($ep -and $ep.Title -and $ep.Title -ne 'N/A') { $ep.Title } elseif ($show -and -not $isSeries -and $show.Title) { $show.Title } else { [System.IO.Path]::GetFileNameWithoutExtension($f.Name) }
        $epPlot  = if ($ep -and $ep.Plot -and $ep.Plot -ne 'N/A') { $ep.Plot } elseif ((-not $isSeries) -and $show -and $show.Plot -and $show.Plot -ne 'N/A') { $show.Plot } else { "" }
        $epRel   = if ($ep -and $ep.Released -and $ep.Released -ne 'N/A') { $ep.Released } else { "" }
        $epRun   = if ($ep -and $ep.Runtime -and $ep.Runtime -ne 'N/A') { $ep.Runtime } elseif ($show -and $show.Runtime -and $show.Runtime -ne 'N/A') { $show.Runtime } else { "" }
        $epRate  = if ($ep -and $ep.imdbRating -and $ep.imdbRating -ne 'N/A') { $ep.imdbRating } else { "" }
        $epImdb  = if ($ep -and $ep.imdbID -and $ep.imdbID -ne 'N/A') { $ep.imdbID } elseif ($show) { $show.imdbID } else { "" }

        # NFO basename mirrors the SOURCE file so media servers pair them
        # (e.g. "<video>.mkv" -> "<video>.nfo"). Falls back to series + label.
        $safeEp = ([System.IO.Path]::GetFileNameWithoutExtension($f.Name) -replace '[<>:"/\\|?*]', '').Trim()
        if (-not $safeEp) { $safeEp = (("{0} - {1}" -f $safeSeries, $epLabel) -replace '[<>:"/\\|?*]', '').Trim() }
        $nfoFile = Join-Path $outDir "$safeEp.nfo"

        $nfo = New-Object System.Text.StringBuilder
        [void]$nfo.AppendLine($Script:MinfoFiglet)
        [void]$nfo.AppendLine("================================================================================")
        [void]$nfo.AppendLine("  $SeriesName")
        [void]$nfo.AppendLine("  $epLabel  ·  $epTitle")
        [void]$nfo.AppendLine("================================================================================")
        [void]$nfo.AppendLine("  Generated by $ScriptName v$ScriptVersion  ·  $timestamp")
        [void]$nfo.AppendLine("  Source file: $($f.Name)")
        [void]$nfo.AppendLine("================================================================================")
        [void]$nfo.AppendLine("")
        if ($epTitle -or $epRel -or $epRun -or $epRate) {
            [void]$nfo.AppendLine("[ EPISODE INFO ]")
            [void]$nfo.AppendLine("--------------------------------------------------------------------------------")
            [void]$nfo.AppendLine(("  Title     : {0}" -f $epTitle))
            if ($epRel)  { [void]$nfo.AppendLine(("  Released  : {0}" -f $epRel)) }
            if ($epRun)  { [void]$nfo.AppendLine(("  Runtime   : {0}" -f $epRun)) }
            if ($epRate) { [void]$nfo.AppendLine(("  IMDB      : {0}/10" -f $epRate)) }
            if ($epImdb) { [void]$nfo.AppendLine(("  IMDB URL  : https://www.imdb.com/title/{0}/" -f $epImdb)) }
            [void]$nfo.AppendLine("")
        }
        if ($epPlot) {
            [void]$nfo.AppendLine("[ PLOT ]")
            [void]$nfo.AppendLine("--------------------------------------------------------------------------------")
            [void]$nfo.AppendLine($epPlot)
            [void]$nfo.AppendLine("")
        }
        [void]$nfo.AppendLine("[ TECHNICAL INFO ]")
        [void]$nfo.AppendLine("--------------------------------------------------------------------------------")
        [void]$nfo.AppendLine($tech)
        [void]$nfo.AppendLine("")
        [void]$nfo.AppendLine("================================================================================")
        $nfo.ToString() | Out-File -LiteralPath $nfoFile -Encoding UTF8

        Write-Host "  $($global:UI_GRN)NFO:$($global:UI_R) $safeEp.nfo"

        $records.Add([pscustomobject]@{
            Label = $epLabel; Title = $epTitle; Released = $epRel
            Runtime = $epRun; Rating = $epRate; Plot = $epPlot; Tech = $tech; File = $f.Name
        })
    }

    # ── Main (series / documentary) NFO ───────────────────────
    $mainNfo = New-Object System.Text.StringBuilder
    [void]$mainNfo.AppendLine($Script:MinfoFiglet)
    [void]$mainNfo.AppendLine("================================================================================")
    [void]$mainNfo.AppendLine("  $SeriesName")
    [void]$mainNfo.AppendLine("================================================================================")
    [void]$mainNfo.AppendLine("  Generated by $ScriptName v$ScriptVersion  ·  $timestamp")
    [void]$mainNfo.AppendLine("  $kindWord  ·  $($records.Count) entries")
    [void]$mainNfo.AppendLine("================================================================================")
    [void]$mainNfo.AppendLine("")
    if ($show) {
        [void]$mainNfo.AppendLine("[ INFO ]")
        [void]$mainNfo.AppendLine("--------------------------------------------------------------------------------")
        if ($show.Title) { [void]$mainNfo.AppendLine(("  Title     : {0}" -f $show.Title)) }
        if ($show.Year)  { [void]$mainNfo.AppendLine(("  Year      : {0}" -f $show.Year)) }
        if ($show.Rated -and $show.Rated -ne 'N/A')  { [void]$mainNfo.AppendLine(("  Rated     : {0}" -f $show.Rated)) }
        if ($show.Genre -and $show.Genre -ne 'N/A')  { [void]$mainNfo.AppendLine(("  Genre     : {0}" -f $show.Genre)) }
        if ($show.totalSeasons -and $show.totalSeasons -ne 'N/A') { [void]$mainNfo.AppendLine(("  Seasons   : {0}" -f $show.totalSeasons)) }
        if ($show.imdbRating -and $show.imdbRating -ne 'N/A') { [void]$mainNfo.AppendLine(("  IMDB      : {0}/10" -f $show.imdbRating)) }
        if ($show.imdbID -and $show.imdbID -ne 'N/A') { [void]$mainNfo.AppendLine(("  IMDB URL  : https://www.imdb.com/title/{0}/" -f $show.imdbID)) }
        [void]$mainNfo.AppendLine("")
        if ($show.Plot -and $show.Plot -ne 'N/A') {
            [void]$mainNfo.AppendLine("[ PLOT ]")
            [void]$mainNfo.AppendLine("--------------------------------------------------------------------------------")
            [void]$mainNfo.AppendLine($show.Plot)
            [void]$mainNfo.AppendLine("")
        }
    }
    [void]$mainNfo.AppendLine("[ CONTENTS ]")
    [void]$mainNfo.AppendLine("--------------------------------------------------------------------------------")
    foreach ($r in $records) {
        [void]$mainNfo.AppendLine(("  {0,-10} {1}" -f $r.Label, $r.Title))
    }
    [void]$mainNfo.AppendLine("")
    [void]$mainNfo.AppendLine("  Per-entry technical details live in each entry's own .nfo file.")
    [void]$mainNfo.AppendLine("================================================================================")
    $mainNfoFile = Join-Path $outDir "$safeSeries.nfo"
    $mainNfo.ToString() | Out-File -LiteralPath $mainNfoFile -Encoding UTF8
    Write-Host "  $($global:UI_GRN)Main NFO:$($global:UI_R) $safeSeries.nfo"

    # ── Series index HTML ─────────────────────────────────────
    $cards = New-Object System.Text.StringBuilder
    foreach ($r in $records) {
        $lb   = ConvertTo-HtmlSafe $r.Label
        $t    = ConvertTo-HtmlSafe $r.Title
        $pl   = ConvertTo-HtmlSafe $r.Plot
        $tech = ConvertTo-HtmlSafe $r.Tech
        $metaParts = @()
        if ($r.Released) { $metaParts += (ConvertTo-HtmlSafe $r.Released) }
        if ($r.Runtime)  { $metaParts += (ConvertTo-HtmlSafe $r.Runtime) }
        if ($r.Rating)   { $metaParts += ("IMDB " + (ConvertTo-HtmlSafe $r.Rating) + "/10") }
        $metaLine = ($metaParts -join "  &nbsp;|&nbsp;  ")
        $plotHtml = if ($pl) { "<div class='epplot'>$pl</div>" } else { "" }
        [void]$cards.AppendLine(@"
    <div class="ep">
        <div class="ephead"><span class="eplabel">$lb</span><span class="eptitle">$t</span></div>
        <div class="epmeta">$metaLine</div>
        $plotHtml
        <details><summary>Technical info</summary><div class="mediainfo">$tech</div></details>
    </div>
"@)
    }

    $seriesTitleHtml = ConvertTo-HtmlSafe $SeriesName
    $cardsText = $cards.ToString()
    $entryCount = $records.Count
    $posterBlock = if ($posterRel) { "<img class='poster' src='$posterRel' alt='poster'>" } else { "" }
    $subLine = if ($show) {
        ConvertTo-HtmlSafe (($show.Year, $show.Rated, $show.Genre | Where-Object { $_ -and $_ -ne 'N/A' }) -join "  |  ")
    } else { "$($records.Count) items" }

    $indexFile = Join-Path $outDir "$safeSeries.htm"
    $page = @"
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>$seriesTitleHtml</title>
    <style>
        * { box-sizing: border-box; margin: 0; padding: 0; }
        body { font-family: 'Courier New', monospace; background: #0d0d0d; color: #c8c8c8; padding: 2rem; max-width: 960px; margin: 0 auto; }
        h1 { color: #00d4ff; font-size: 1.8rem; margin-bottom: 0.25rem; }
        .sub { color: #888; font-size: 0.95rem; margin-bottom: 1.5rem; }
        .head { display: flex; gap: 1.5rem; margin-bottom: 2rem; align-items: flex-start; }
        .poster { width: 200px; border: 2px solid #333; border-radius: 4px; }
        .ep { background: #111; border: 1px solid #222; border-left: 3px solid #00d4ff; border-radius: 4px; padding: 1rem 1.2rem; margin-bottom: 1rem; }
        .ephead { margin-bottom: 0.3rem; }
        .eplabel { color: #f5c518; font-weight: bold; margin-right: 0.8rem; }
        .eptitle { color: #00d4ff; font-size: 1.05rem; }
        .epmeta { color: #888; font-size: 0.8rem; margin-bottom: 0.5rem; }
        .epplot { color: #bbb; line-height: 1.6; margin-bottom: 0.5rem; }
        details summary { color: #6cf; cursor: pointer; font-size: 0.8rem; margin-top: 0.4rem; }
        .mediainfo { background: #0a0a0a; border: 1px solid #222; padding: 0.8rem; font-size: 0.8rem; white-space: pre-wrap; overflow-x: auto; color: #bbb; border-radius: 4px; line-height: 1.5; margin-top: 0.5rem; }
        footer { margin-top: 3rem; font-size: 0.75rem; color: #444; border-top: 1px solid #222; padding-top: 1rem; }
    </style>
</head>
<body>
<div class="head">
    $posterBlock
    <div>
        <h1>$seriesTitleHtml</h1>
        <div class="sub">$subLine &nbsp;|&nbsp; $entryCount entries</div>
    </div>
</div>

$cardsText

<footer>Generated by $ScriptName v$ScriptVersion &nbsp;|&nbsp; $timestamp &nbsp;|&nbsp; by $ScriptAuthor</footer>
</body>
</html>
"@
    $page | Out-File -LiteralPath $indexFile -Encoding UTF8
    Write-Host "  $($global:UI_GRN)Index:$($global:UI_R) $safeSeries.htm"

    if ($Preview -and $posterRel) {
        if ([System.Threading.Thread]::CurrentThread.GetApartmentState() -eq 'STA') {
            try { Show-PosterWindow -ImagePath (Join-Path $outDir $posterRel) } catch { }
        }
    }

    Write-UiBlankLine
    Write-UiHeader -Title "Done!" -Subtitle $outDir -Width (Get-UiBoxWidth -MaxWidth 72 -MinWidth 48)
    Show-ResultTable -Path $outDir
}

# ── Start screen ──────────────────────────────────────────────
Show-Header
Write-UiRow "curl.exe"  "found" $(if ($curlExe) { $global:UI_GRN } else { $global:UI_RED })
Write-UiRow "MediaInfo" $(if ($mediaInfoExe) { "found" } else { "not found" }) $(if ($mediaInfoExe) { $global:UI_GRN } else { $global:UI_YLW })
Write-UiBlankLine

# ── Validate video dir ────────────────────────────────────────
if (-not (Test-Path -LiteralPath $VideoDir)) {
    Write-Host "  $($global:UI_RED)Video directory not found: $VideoDir$($global:UI_R)"
    Write-Host "  $($global:UI_YLW)Pass -VideoDir to specify a different path.$($global:UI_R)"
    Write-UiBlankLine
    Pause-Script
    return
}

# ── Mode dispatch (single vs series/documentary) ──────────────
$allVids = @(Get-MinfoVideoFiles -Dir $VideoDir)
$useMode = $Mode

if ($useMode -eq 'auto') {
    if ($VideoFile -or $allVids.Count -le 1) {
        $useMode = 'single'
    } else {
        Write-Host "  $($global:UI_YLW)$($allVids.Count) video files found in this folder.$($global:UI_R)"
        Write-Host "  $($global:UI_CYN)[1] Single    [2] TV series    [3] Documentary (multi-part)$($global:UI_R)"
        $choice = Read-Host "  Choose (1/2/3)"
        switch ($choice) {
            '2' { $useMode = 'series' }
            '3' { $useMode = 'docu' }
            default { $useMode = 'single' }
        }
    }
}

if ($useMode -eq 'series' -or $useMode -eq 'docu') {
    if ($allVids.Count -lt 1) {
        Write-Host "  $($global:UI_RED)No video files found in $VideoDir$($global:UI_R)"
        Write-UiBlankLine
        Pause-Script
        return
    }
    Invoke-MinfoSeries -Mode $useMode -Files $allVids -SeriesName $SeriesName `
        -ApiKey $ApiKey -CurlExe $curlExe -MediaInfoExe $mediaInfoExe `
        -NfoDir $Script:NfoDir -Preview:$Preview
    Pause-Script
    return
}

# ── Find source video ─────────────────────────────────────────
$foundFile = $null

if ($VideoFile) {
    $foundFile = Join-Path $VideoDir $VideoFile
    if (-not (Test-Path -LiteralPath $foundFile)) {
        Write-Host "  $($global:UI_RED)File not found: $foundFile$($global:UI_R)"
        Write-UiBlankLine
        Pause-Script
        return
    }
} else {
    foreach ($ext in @("*.mkv","*.mp4","*.avi","*.m2ts","*.mov","*.wmv")) {
        $found = Get-ChildItem -Path $VideoDir -Filter $ext -File | Select-Object -First 1
        if ($found) {
            $foundFile = $found.FullName
            $VideoFile = $found.Name
            break
        }
    }

    if (-not $foundFile) {
        Write-Host "  $($global:UI_RED)No video file found in $VideoDir$($global:UI_R)"
        Write-Host "  $($global:UI_YLW)Pass -VideoFile filename.mkv to specify one.$($global:UI_R)"
        Write-UiBlankLine
        Pause-Script
        return
    }
}

Write-UiRow "Found File" $VideoFile $global:UI_GRN
Write-UiBlankLine

# ── Output title ──────────────────────────────────────────────
$defaultTitle = [System.IO.Path]::GetFileNameWithoutExtension($VideoFile) -replace "[._]", " "

Write-Host "  $($global:UI_YLW)Name your NFO/HTML files:$($global:UI_R)"
Write-Host "  $($global:UI_GRN)Default: $defaultTitle$($global:UI_R)"
Write-UiBlankLine
Write-Host -NoNewline "  $($global:UI_YLW)Keep default? (y/n): $($global:UI_R)"
$keepTitle = Read-Host

if ($keepTitle -match '^[Yy]$') {
    $title = $defaultTitle
} else {
    Write-Host -NoNewline "  $($global:UI_CYN)Enter title: $($global:UI_R)"
    $title = Read-Host
    if ([string]::IsNullOrWhiteSpace($title)) {
        $title = $defaultTitle
    }
}

$baseName = $title.Trim()
$baseName = $baseName -replace '[<>:"/\\|?*]', ''

if ([string]::IsNullOrWhiteSpace($baseName)) {
    $baseName = $defaultTitle.Trim()
}

Write-UiRow "Base Name" $baseName $global:UI_CYN
Write-UiBlankLine

# ── OMDb lookup ───────────────────────────────────────────────
Write-UiSection "OMDb Lookup"
Write-Host "  $($global:UI_CYN)Enter search title or IMDb ID (example: tt0083907)$($global:UI_R)"
$searchInput = Read-Host "  Search"
$searchYear  = Read-Host "  Year (optional)"

$baseUrl = "http://www.omdbapi.com/"
$omdbOK  = $false

if ($searchInput -match '^tt\d+') {
    $apiUrl = "${baseUrl}?apikey=${ApiKey}&i=${searchInput}&plot=full"
} else {
    $enc = [System.Uri]::EscapeDataString($searchInput)
    $apiUrl = "${baseUrl}?apikey=${ApiKey}&t=${enc}&plot=full"
    if ($searchYear) { $apiUrl += "&y=$searchYear" }
}

Write-UiBlankLine
Write-Host "  $($global:UI_CYN)Fetching movie data...$($global:UI_R)"

try {
    $raw      = & $curlExe --silent --max-time 15 $apiUrl
    $response = $raw | ConvertFrom-Json

    if ($response.Response -eq "True") {
        $omdbOK   = $true
        $mTitle   = if ($response.Title)      { $response.Title }      else { "N/A" }
        $mYear    = if ($response.Year)       { $response.Year }       else { "N/A" }
        $mRated   = if ($response.Rated)      { $response.Rated }      else { "N/A" }
        $mRel     = if ($response.Released)   { $response.Released }   else { "N/A" }
        $mRuntime = if ($response.Runtime)    { $response.Runtime }    else { "N/A" }
        $mGenre   = if ($response.Genre)      { $response.Genre }      else { "N/A" }
        $mDir     = if ($response.Director)   { $response.Director }   else { "N/A" }
        $mWriter  = if ($response.Writer)     { $response.Writer }     else { "N/A" }
        $mCast    = if ($response.Actors)     { $response.Actors }     else { "N/A" }
        $mPlot    = if ($response.Plot)       { $response.Plot }       else { "N/A" }
        $mLang    = if ($response.Language)   { $response.Language }   else { "N/A" }
        $mCountry = if ($response.Country)    { $response.Country }    else { "N/A" }
        $mAwards  = if ($response.Awards)     { $response.Awards }     else { "N/A" }
        $mImdbId  = if ($response.imdbID)     { $response.imdbID }     else { "N/A" }
        $mRating  = if ($response.imdbRating) { $response.imdbRating } else { "N/A" }
        $mVotes   = if ($response.imdbVotes)  { $response.imdbVotes }  else { "N/A" }
        $mMeta    = if ($response.Metascore)  { $response.Metascore }  else { "N/A" }
        $mPoster  = if ($response.Poster)     { $response.Poster }     else { "N/A" }
        $mRT      = ($response.Ratings | Where-Object { $_.Source -eq "Rotten Tomatoes" } | Select-Object -First 1).Value
        if (-not $mRT) { $mRT = "N/A" }

        Write-Host "  $($global:UI_GRN)Found: $mTitle ($mYear)$($global:UI_R)"
    } else {
        Write-Host "  $($global:UI_RED)OMDb Error: $($response.Error)$($global:UI_R)"
        Write-Host "  $($global:UI_YLW)Continuing with MediaInfo only...$($global:UI_R)"
    }
}
catch {
    Write-Host "  $($global:UI_RED)API call failed: $($_.Exception.Message)$($global:UI_R)"
    Write-Host "  $($global:UI_YLW)Continuing with MediaInfo only...$($global:UI_R)"
}

# ── MediaInfo ─────────────────────────────────────────────────
$mediaInfoText = ""

if ($mediaInfoExe) {
    Write-UiBlankLine
    Write-Host "  $($global:UI_CYN)Running MediaInfo on $VideoFile...$($global:UI_R)"
    try {
        $rawMediaInfoJson = & $mediaInfoExe --Output=JSON $foundFile 2>$null
        $mediaInfoObj     = $rawMediaInfoJson | ConvertFrom-Json
        $mediaInfoText    = Format-MediaInfoFromJson -MediaInfoObj $mediaInfoObj
    } catch {
        Write-Host "  $($global:UI_YLW)MediaInfo failed: $($_.Exception.Message)$($global:UI_R)"
        $mediaInfoText = "MediaInfo parsing failed."
    }
} else {
    $mediaInfoText = "MediaInfo CLI not installed. Install with: winget install MediaArea.MediaInfo.CLI"
}

# ── Output folder ─────────────────────────────────────────────
$outDir = Join-Path $Script:NfoDir $baseName
New-Item -ItemType Directory -Path $outDir -Force | Out-Null
$timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

# ── Write NFO ─────────────────────────────────────────────────
$nfoFile = Join-Path $outDir "$baseName.nfo"

$nfoContent = @"
╔════════════════════════════════════════════════════════════════════════════╗
║                                                                            ║
║                 ███╗   ███╗██╗███╗   ██╗███████╗ ██████╗                   ║
║                 ████╗ ████║██║████╗  ██║██╔════╝██╔═══██╗                  ║
║                 ██╔████╔██║██║██╔██╗ ██║█████╗  ██║   ██║                  ║
║                 ██║╚██╔╝██║██║██║╚██╗██║██╔══╝  ██║   ██║                  ║
║                 ██║ ╚═╝ ██║██║██║ ╚████║██║     ╚██████╔╝                  ║
║                 ╚═╝     ╚═╝╚═╝╚═╝  ╚═══╝╚═╝      ╚═════╝                   ║
║                                                                            ║
║                  N F O   C R E A T O R   ·   by Mike Redd                  ║
╚════════════════════════════════════════════════════════════════════════════╝
================================================================================
  $title
================================================================================
  Generated by $ScriptName v$ScriptVersion  ·  $timestamp
================================================================================

"@

if ($omdbOK) {
    $nfoContent += @"
[ MOVIE INFO ]
--------------------------------------------------------------------------------
  Title     : $mTitle
  Year      : $mYear
  Rated     : $mRated
  Released  : $mRel
  Runtime   : $mRuntime
  Genre     : $mGenre
  Director  : $mDir
  Writer    : $mWriter
  Cast      : $mCast
  Language  : $mLang
  Country   : $mCountry
  Awards    : $mAwards

[ RATINGS ]
--------------------------------------------------------------------------------
  IMDB      : $mRating/10  ($mVotes votes)
  Rotten T  : $mRT
  Metascore : $mMeta
  IMDB URL  : https://www.imdb.com/title/$mImdbId/

[ PLOT ]
--------------------------------------------------------------------------------
$mPlot

"@
}

$nfoContent += @"
[ TECHNICAL INFO ]
--------------------------------------------------------------------------------
$mediaInfoText

================================================================================
"@

$nfoContent | Out-File -LiteralPath $nfoFile -Encoding UTF8
Write-UiBlankLine
Write-Host "  $($global:UI_GRN)NFO saved: $nfoFile$($global:UI_R)"

# HTML-escape text fields
# The NFO above is plain text and keeps raw values; the HTML below
# must escape OMDb/MediaInfo text so &, <, > and quotes don't break
# the markup. Poster URL and IMDb ID are left raw on purpose.
$title         = ConvertTo-HtmlSafe $title
$mediaInfoText = ConvertTo-HtmlSafe $mediaInfoText
if ($omdbOK) {
    $mTitle   = ConvertTo-HtmlSafe $mTitle
    $mYear    = ConvertTo-HtmlSafe $mYear
    $mRated   = ConvertTo-HtmlSafe $mRated
    $mRel     = ConvertTo-HtmlSafe $mRel
    $mRuntime = ConvertTo-HtmlSafe $mRuntime
    $mGenre   = ConvertTo-HtmlSafe $mGenre
    $mDir     = ConvertTo-HtmlSafe $mDir
    $mWriter  = ConvertTo-HtmlSafe $mWriter
    $mCast    = ConvertTo-HtmlSafe $mCast
    $mPlot    = ConvertTo-HtmlSafe $mPlot
    $mLang    = ConvertTo-HtmlSafe $mLang
    $mCountry = ConvertTo-HtmlSafe $mCountry
    $mAwards  = ConvertTo-HtmlSafe $mAwards
    $mRating  = ConvertTo-HtmlSafe $mRating
    $mVotes   = ConvertTo-HtmlSafe $mVotes
    $mMeta    = ConvertTo-HtmlSafe $mMeta
    $mRT      = ConvertTo-HtmlSafe $mRT
}

# ── Write HTML ────────────────────────────────────────────────
$htmFile = Join-Path $outDir "$baseName.htm"

$posterTag = if ($omdbOK -and $mPoster -ne "N/A") {
    "<img src=`"$mPoster`" alt=`"$mTitle poster`">"
} else {
    "<div class=`"noposter`">No Poster Available</div>"
}

$rtBlock = if ($omdbOK -and $mRT -ne "N/A") { @"
            <div class="rating-box">
                <div class="score" style="color:#fa320a">$mRT</div>
                <div class="source">Rotten Tomatoes</div>
            </div>
"@ } else { "" }

$metaBlock = if ($omdbOK -and $mMeta -ne "N/A") { @"
            <div class="rating-box">
                <div class="score" style="color:#6c3">$mMeta</div>
                <div class="source">Metascore</div>
            </div>
"@ } else { "" }

$htmContent = @"
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>$(if ($omdbOK) { "$mTitle ($mYear)" } else { $title })</title>
    <style>
        * { box-sizing: border-box; margin: 0; padding: 0; }
        body {
            font-family: 'Courier New', monospace;
            background: #0d0d0d;
            color: #c8c8c8;
            padding: 2rem;
            max-width: 960px;
            margin: 0 auto;
        }
        h1 { color: #00d4ff; font-size: 1.8rem; margin-bottom: 0.25rem; }
        .year { color: #888; font-size: 1rem; margin-bottom: 1.5rem; }
        .container { display: flex; gap: 2rem; margin-bottom: 2rem; }
        .poster img { width: 220px; border: 2px solid #333; border-radius: 4px; }
        .poster .noposter {
            width: 220px; height: 330px; background: #1a1a1a;
            border: 2px solid #333; display: flex; align-items: center;
            justify-content: center; color: #555; font-size: 0.8rem;
        }
        .info { flex: 1; }
        .field { margin-bottom: 0.6rem; line-height: 1.5; }
        .label { color: #00d4ff; font-weight: bold; min-width: 100px; display: inline-block; }
        .ratings { display: flex; gap: 1.5rem; margin: 1rem 0; flex-wrap: wrap; }
        .rating-box {
            background: #1a1a1a; border: 1px solid #333;
            padding: 0.5rem 1rem; border-radius: 4px; text-align: center;
        }
        .rating-box .score { font-size: 1.4rem; color: #f5c518; font-weight: bold; }
        .rating-box .source { font-size: 0.7rem; color: #888; margin-top: 0.2rem; }
        .plot {
            background: #111; border-left: 3px solid #00d4ff;
            padding: 1rem 1.2rem; margin: 1.5rem 0;
            line-height: 1.7; color: #bbb;
        }
        h2 {
            color: #00d4ff; font-size: 1rem; text-transform: uppercase;
            letter-spacing: 2px; margin: 2rem 0 1rem;
            border-bottom: 1px solid #333; padding-bottom: 0.4rem;
        }
        .mediainfo {
            background: #0a0a0a;
            border: 1px solid #222;
            padding: 1rem;
            font-size: 0.85rem;
            white-space: pre-wrap;
            overflow-x: auto;
            color: #bbb;
            border-radius: 4px;
            line-height: 1.55;
        }
        .imdb-link a { color: #f5c518; text-decoration: none; }
        .imdb-link a:hover { text-decoration: underline; }
        footer {
            margin-top: 3rem; font-size: 0.75rem; color: #444;
            border-top: 1px solid #222; padding-top: 1rem;
        }
    </style>
</head>
<body>

<h1>$(if ($omdbOK) { $mTitle } else { $title })</h1>
<div class="year">$(if ($omdbOK) { "$mYear &nbsp;|&nbsp; $mRated &nbsp;|&nbsp; $mRuntime &nbsp;|&nbsp; $mGenre" } else { "No OMDb data" })</div>

<div class="container">
    <div class="poster">$posterTag</div>
    <div class="info">
$(if ($omdbOK) { @"
        <div class="field"><span class="label">Director</span> $mDir</div>
        <div class="field"><span class="label">Writer</span> $mWriter</div>
        <div class="field"><span class="label">Cast</span> $mCast</div>
        <div class="field"><span class="label">Language</span> $mLang</div>
        <div class="field"><span class="label">Country</span> $mCountry</div>
        <div class="field"><span class="label">Released</span> $mRel</div>
        <div class="field"><span class="label">Awards</span> $mAwards</div>
        <div class="ratings">
            <div class="rating-box">
                <div class="score">$mRating<span style="font-size:0.9rem;color:#888">/10</span></div>
                <div class="source">IMDB ($mVotes)</div>
            </div>
            $rtBlock
            $metaBlock
        </div>
        <div class="imdb-link">
            <span class="label">IMDB</span>
            <a href="https://www.imdb.com/title/$mImdbId/" target="_blank">
                https://www.imdb.com/title/$mImdbId/
            </a>
        </div>
"@ } else { "        <div class='field'>No OMDb data available.</div>" })
    </div>
</div>

$(if ($omdbOK) { "<div class=`"plot`">$mPlot</div>" })

<h2>Technical Info</h2>
<div class="mediainfo">$mediaInfoText</div>

<footer>
    Generated by $ScriptName v$ScriptVersion &nbsp;|&nbsp; $timestamp &nbsp;|&nbsp; by $ScriptAuthor
</footer>

</body>
</html>
"@

$htmContent | Out-File -LiteralPath $htmFile -Encoding UTF8
Write-Host "  $($global:UI_GRN)HTML saved: $htmFile$($global:UI_R)"

# ── Download poster ───────────────────────────────────────────
if ($omdbOK -and $mPoster -ne "N/A") {
    Write-UiBlankLine
    Write-Host "  $($global:UI_CYN)Downloading poster...$($global:UI_R)"
    $posterOut = Join-Path $outDir "$baseName.jpg"

    & $curlExe --silent --location --max-time 30 --output $posterOut $mPoster

    if ($LASTEXITCODE -eq 0 -and (Test-Path -LiteralPath $posterOut) -and (Get-Item -LiteralPath $posterOut).Length -gt 0) {
        Write-Host "  $($global:UI_GRN)Poster saved: $posterOut$($global:UI_R)"

        if ($Preview) {
            if ([System.Threading.Thread]::CurrentThread.GetApartmentState() -ne 'STA') {
                Write-Host "  $($global:UI_YLW)Poster preview needs an STA host; relaunch with -STA to use it.$($global:UI_R)"
            } else {
                try {
                    Show-PosterWindow -ImagePath $posterOut
                } catch {
                    Write-Host "  $($global:UI_YLW)Preview failed: $($_.Exception.Message)$($global:UI_R)"
                }
            }
        }
    } else {
        Write-Host "  $($global:UI_YLW)Poster download failed (non-fatal).$($global:UI_R)"
        Remove-Item -LiteralPath $posterOut -Force -ErrorAction SilentlyContinue
    }
}

# ── Done ──────────────────────────────────────────────────────
Write-UiBlankLine
Write-UiHeader -Title "Done!" -Subtitle $outDir -Width (Get-UiBoxWidth -MaxWidth 72 -MinWidth 48)
Show-ResultTable -Path $outDir
Pause-Script