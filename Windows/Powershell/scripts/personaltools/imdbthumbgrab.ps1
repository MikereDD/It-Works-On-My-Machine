#--------------------------------------------
# file:     imdbthumbgrab.ps1
# author:   Mike Redd
# version:  1.2
# created:  2026-04-11
# updated:  2026-04-11
# desc:     Search OMDb by title/year or IMDb ID,
#           download poster/thumbnail, and
#           display it in a popup window.
#--------------------------------------------

param(
    [string]$Title   = "",
    [string]$Year    = "",
    [string]$ImdbId  = "",
    [string]$ApiKey  = "",
    [switch]$Show,
    [switch]$Help
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
        return
    }
} else {
    Write-Host "Missing core.ps1: $corePath"
    return
}

$ErrorActionPreference = 'Stop'

$ScriptName    = "ImdbThumbGrab"
$ScriptVersion = "1.2"
$ScriptAuthor  = "Mike Redd"

# ── Load config ───────────────────────────────────────────────
$Script:ConfigPaths = @(
    "$env:USERPROFILE\PS\profile.d\minforc.ps1",
    "$PSScriptRoot\minforc.ps1",
    "$HOME\.config\minforc.ps1"
)

foreach ($cp in $Script:ConfigPaths) {
    if (Test-Path -LiteralPath $cp) {
        try {
            . $cp
            break
        } catch {}
    }
}

# ── Resolve API key and paths ─────────────────────────────────
if (-not $ApiKey) {
    $ApiKey = $global:OMDB_API_KEY
}

$Script:PosterDir = if ($global:MINFO_POSTERDIR) {
    $global:MINFO_POSTERDIR
} else {
    "G:\Rip\meta\posters"
}

New-Item -ItemType Directory -Path $Script:PosterDir -Force | Out-Null

# ── Helpers ───────────────────────────────────────────────────
function Show-Header {
    Clear-UiScreen
    $w = Get-UiBoxWidth -MaxWidth 72 -MinWidth 50

    Write-UiHeader -Title $ScriptName -Subtitle "v$ScriptVersion  by $ScriptAuthor" -Width $w
    Write-UiRow "User"      "$env:USERNAME@$env:COMPUTERNAME"
    Write-UiRow "PosterDir" $Script:PosterDir $global:UI_GRY
    Write-UiBlankLine
}

function Pause-Script {
    Pause-Core "Press Enter to return..."
}

function Show-Usage {
    Show-Header
    Write-UiSection "Usage"
    Write-Host "  $($global:UI_WHT).\imdbthumbgrab.ps1 -Title `"movie title`"$($global:UI_R)"
    Write-Host "  $($global:UI_WHT).\imdbthumbgrab.ps1 -Title `"Blade Runner`" -Year 1982$($global:UI_R)"
    Write-Host "  $($global:UI_WHT).\imdbthumbgrab.ps1 -ImdbId tt0083658$($global:UI_R)"
    Write-UiBlankLine

    Write-UiSection "Parameters"
    Write-Host "  $($global:UI_GRY)-Title    Movie or show title$($global:UI_R)"
    Write-Host "  $($global:UI_GRY)-Year     Optional year filter$($global:UI_R)"
    Write-Host "  $($global:UI_GRY)-ImdbId   Lookup directly by IMDb ID$($global:UI_R)"
    Write-Host "  $($global:UI_GRY)-ApiKey   OMDb API key$($global:UI_R)"
    Write-Host "  $($global:UI_GRY)-Show     Show popup preview after download$($global:UI_R)"
    Write-UiBlankLine

    Write-UiSection "Examples"
    Write-Host "  $($global:UI_GRY).\imdbthumbgrab.ps1 -Title `"The Evil Dead`" -Show$($global:UI_R)"
    Write-Host "  $($global:UI_GRY).\imdbthumbgrab.ps1 -Title `"Blade Runner`" -Year 1982 -Show$($global:UI_R)"
    Write-Host "  $($global:UI_GRY).\imdbthumbgrab.ps1 -ImdbId tt0083658 -Show$($global:UI_R)"
    Write-UiBlankLine

    Pause-Script
}

function Read-MenuInput {
    param(
        [string]$Prompt = "Choice"
    )

    Write-Host -NoNewline "  $($global:UI_CYN)$Prompt$($global:UI_R)$($global:UI_DIM): $($global:UI_R)"
    return (Read-Host).Trim()
}

function Get-SafePosterName {
    param(
        [string]$Title,
        [string]$Year,
        [string]$ImdbId
    )

    $baseName = $Title.Trim()

    if ($Year -and $Year -ne "N/A") {
        $baseName = "$baseName [$Year]"
    }

    $baseName = $baseName -replace '[<>:"/\\|?*]', ''
    $baseName = $baseName.Trim()

    if ([string]::IsNullOrWhiteSpace($baseName)) {
        if ($ImdbId -and $ImdbId -ne "N/A") {
            $baseName = $ImdbId
        } else {
            $baseName = "poster"
        }
    }

    return $baseName
}

function Show-PosterWindow {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ImagePath
    )

    if (-not (Test-Path -LiteralPath $ImagePath)) {
        Write-Host "Image not found: $ImagePath"
        return
    }

    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing

    $form = New-Object System.Windows.Forms.Form
    $form.Text = "IMDb Poster Preview"
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
        Write-Host "Failed to load image: $($_.Exception.Message)"
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

function Get-ImdbThumbData {
    param(
        [string]$Title,
        [string]$Year,
        [string]$ImdbId,
        [string]$ApiKey,
        [string]$CurlExe
    )

    $baseUrl = "http://www.omdbapi.com/"

    if ($ImdbId) {
        $apiUrl = "${baseUrl}?apikey=${ApiKey}&i=${ImdbId}&plot=short"
    } else {
        $enc = [System.Uri]::EscapeDataString($Title)
        $apiUrl = "${baseUrl}?apikey=${ApiKey}&t=${enc}&plot=short"
        if ($Year) {
            $apiUrl += "&y=$Year"
        }
    }

    $raw = & $CurlExe --silent --max-time 15 $apiUrl
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($raw)) {
        throw "curl request failed."
    }

    $response = $raw | ConvertFrom-Json

    if ($response.Response -ne "True") {
        throw "OMDb Error: $($response.Error)"
    }

    return $response
}

function Save-PosterFile {
    param(
        [Parameter(Mandatory = $true)]
        [string]$PosterUrl,

        [Parameter(Mandatory = $true)]
        [string]$OutFile,

        [Parameter(Mandatory = $true)]
        [string]$CurlExe
    )

    & $CurlExe --silent --location --max-time 30 --output $OutFile $PosterUrl

    if ($LASTEXITCODE -ne 0) {
        Remove-Item -LiteralPath $OutFile -Force -ErrorAction SilentlyContinue
        throw "Poster download failed."
    }

    if (-not (Test-Path -LiteralPath $OutFile)) {
        throw "Poster file was not created."
    }

    $item = Get-Item -LiteralPath $OutFile
    if ($item.Length -le 0) {
        Remove-Item -LiteralPath $OutFile -Force -ErrorAction SilentlyContinue
        throw "Poster file is empty."
    }

    return $item
}

function Invoke-ThumbLookup {
    param(
        [string]$Title,
        [string]$Year,
        [string]$ImdbId,
        [switch]$PreviewImage
    )

    Show-Header
    Write-UiRow "Mode" $(if ($ImdbId) { "IMDb ID lookup" } else { "Title lookup" }) $global:UI_CYN

    if ($Title)  { Write-UiRow "Title"   $Title  $global:UI_GRY }
    if ($Year)   { Write-UiRow "Year"    $Year   $global:UI_GRY }
    if ($ImdbId) { Write-UiRow "IMDb ID" $ImdbId $global:UI_GRY }
    Write-UiBlankLine

    try {
        $response = Get-ImdbThumbData -Title $Title -Year $Year -ImdbId $ImdbId -ApiKey $ApiKey -CurlExe $script:curlExe
    } catch {
        Write-Host "  $($global:UI_RED)$($_.Exception.Message)$($global:UI_R)"
        Write-UiBlankLine
        Pause-Script
        return
    }

    $mTitle  = if ($response.Title)    { $response.Title }    else { "N/A" }
    $mYear   = if ($response.Year)     { $response.Year }     else { "N/A" }
    $mType   = if ($response.Type)     { $response.Type }     else { "N/A" }
    $mImdbId = if ($response.imdbID)   { $response.imdbID }   else { "N/A" }
    $mPoster = if ($response.Poster)   { $response.Poster }   else { "N/A" }
    $mRated  = if ($response.imdbRating) { $response.imdbRating } else { "N/A" }

    Write-UiSection "$mTitle ($mYear)"
    Write-UiRow "Type"        $mType
    Write-UiRow "IMDb ID"     $mImdbId
    Write-UiRow "IMDb Rating" $mRated
    Write-UiRow "Poster URL"  $mPoster $global:UI_GRY
    Write-UiBlankLine

    if (-not $mPoster -or $mPoster -eq "N/A") {
        Write-Host "  $($global:UI_RED)No poster was returned by OMDb.$($global:UI_R)"
        Write-UiBlankLine
        Pause-Script
        return
    }

    $baseName = Get-SafePosterName -Title $mTitle -Year $mYear -ImdbId $mImdbId
    $outFile  = Join-Path $Script:PosterDir "$baseName.jpg"

    Write-Host "  $($global:UI_CYN)Downloading poster...$($global:UI_R)"

    try {
        $savedFile = Save-PosterFile -PosterUrl $mPoster -OutFile $outFile -CurlExe $script:curlExe
        $size = [Math]::Round($savedFile.Length / 1KB, 1)

        Write-UiBlankLine
        Write-Host "  $($global:UI_GRN)Poster saved: $outFile  (${size} KB)$($global:UI_R)"
        Write-UiBlankLine
    } catch {
        Write-UiBlankLine
        Write-Host "  $($global:UI_RED)$($_.Exception.Message)$($global:UI_R)"
        Write-UiBlankLine
        Pause-Script
        return
    }

    if ($PreviewImage) {
        Show-PosterWindow -ImagePath $outFile
    }

    Pause-Script
}

function Start-InteractiveMode {
    while ($true) {
        Show-Header
        Write-UiSection "Search Input"
        Write-Host "  $($global:UI_GRY)Leave year blank if unknown.$($global:UI_R)"
        Write-Host "  $($global:UI_GRY)Enter Q at any prompt to return.$($global:UI_R)"
        Write-UiBlankLine

        $first = Read-MenuInput "Movie title or IMDb ID"
        if ($first -match '^[Qq]$') { return }

        if ([string]::IsNullOrWhiteSpace($first)) {
            Write-Host "  $($global:UI_RED)A title or IMDb ID is required.$($global:UI_R)"
            Write-UiBlankLine
            Pause-Script
            continue
        }

        $isImdbId = $first -match '^tt\d{6,10}$'

        $title  = ""
        $year   = ""
        $imdbId = ""

        if ($isImdbId) {
            $imdbId = $first
        } else {
            $title = $first
            $year = Read-MenuInput "Year (optional)"
            if ($year -match '^[Qq]$') { return }
        }

        $preview = Read-MenuInput "Show popup preview? (Y/N)"
        if ($preview -match '^[Qq]$') { return }

        $doShow = $false
        if ($preview -match '^(Y|YES)$' -or $preview -match '^(y|yes)$') {
            $doShow = $true
        }

        Invoke-ThumbLookup -Title $title -Year $year -ImdbId $imdbId -PreviewImage:$doShow
        return
    }
}

# ── Find curl.exe ─────────────────────────────────────────────
$script:curlExe = $null
foreach ($c in @(
    "$env:SystemRoot\System32\curl.exe",
    "$env:SystemRoot\SysWOW64\curl.exe"
)) {
    if (Test-Path -LiteralPath $c) {
        $script:curlExe = $c
        break
    }
}

if (-not $script:curlExe) {
    Show-Header
    Write-UiRow "curl.exe" "not found" $global:UI_RED
    Write-UiBlankLine
    Pause-Script
    return
}

# ── Validation ────────────────────────────────────────────────
if ($Help) {
    Show-Usage
    return
}

if (-not $ApiKey -or $ApiKey -eq "your_api_key_here") {
    Show-Header
    Write-UiRow "Status" "OMDB_API_KEY not set" $global:UI_RED
    Write-UiBlankLine
    Write-Host "  $($global:UI_CYN)Get a free key at: https://www.omdbapi.com/apikey.aspx$($global:UI_R)"
    Write-Host "  $($global:UI_YLW)Set it in minforc.ps1 or pass -ApiKey yourkey$($global:UI_R)"
    Write-UiBlankLine
    Pause-Script
    return
}

# ── Main ──────────────────────────────────────────────────────
if (-not $Title -and -not $ImdbId) {
    Start-InteractiveMode
    return
}

Invoke-ThumbLookup -Title $Title -Year $Year -ImdbId $ImdbId -PreviewImage:$Show