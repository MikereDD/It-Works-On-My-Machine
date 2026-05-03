#--------------------------------------------
# file:     web-ripper.ps1
# author:   Mike Redd
# version:  1.8
# created:  2026-04-18
# updated:  2026-04-18
# desc:     Web media downloader wrapper for
#           yt-dlp + ffmpeg
#           Uses ui.ps1 + core.ps1 helpers
#           and saves to G:\Rip\web
#           Output format: MP4
#--------------------------------------------

param()

$ErrorActionPreference = 'Stop'

# ── Load UI/Core ──────────────────────────────────────────────
$uiPath   = "$env:USERPROFILE\PS\profile.d\ui.ps1"
$corePath = "$env:USERPROFILE\PS\profile.d\core.ps1"

if (Test-Path $uiPath) {
    try { . $uiPath } catch {}
}

if (Test-Path $corePath) {
    try { . $corePath } catch {}
}

# ── Fallback UI values if ui.ps1 is unavailable ──────────────
if (-not $global:UI_R)   { $global:UI_R   = "" }
if (-not $global:UI_B)   { $global:UI_B   = "" }
if (-not $global:UI_DIM) { $global:UI_DIM = "" }
if (-not $global:UI_CYN) { $global:UI_CYN = "" }
if (-not $global:UI_YLW) { $global:UI_YLW = "" }
if (-not $global:UI_GRN) { $global:UI_GRN = "" }
if (-not $global:UI_RED) { $global:UI_RED = "" }
if (-not $global:UI_WHT) { $global:UI_WHT = "" }
if (-not $global:UI_GRY) { $global:UI_GRY = "" }
if (-not $global:UI_MAG) { $global:UI_MAG = "" }

# ── Script Info ───────────────────────────────────────────────
$ScriptName    = "Web Ripper"
$ScriptVersion = "1.8"
$ScriptAuthor  = "Mike Redd"

# ── Config ────────────────────────────────────────────────────
$Script:RootPath    = "G:\Rip"
$Script:OutputRoot  = Join-Path $Script:RootPath "web"
$Script:TempRoot    = Join-Path $Script:RootPath "temp"
$Script:OutputExt   = "mp4"
$Script:OutputLabel = "MP4"

New-Item -ItemType Directory -Force -Path $Script:OutputRoot | Out-Null
New-Item -ItemType Directory -Force -Path $Script:TempRoot   | Out-Null

# ── Helpers ───────────────────────────────────────────────────
function Test-DTCommand {
    param([Parameter(Mandatory)][string]$Name)
    return [bool](Get-Command $Name -ErrorAction SilentlyContinue)
}

function Pause-DT {
    param([string]$Message = "Press Enter to continue...")

    if (Get-Command Pause-UiReturn -ErrorAction SilentlyContinue) {
        Pause-UiReturn $Message
    }
    else {
        Write-Host ""
        Read-Host $Message
    }
}

function Read-DTChoice {
    param([string]$Prompt = "Choice:")

    if (Get-Command Read-UiChoice -ErrorAction SilentlyContinue) {
        return (Read-UiChoice $Prompt)
    }

    return (Read-Host $Prompt)
}

function Clear-DTScreen {
    if (Get-Command Clear-UiScreen -ErrorAction SilentlyContinue) {
        Clear-UiScreen
    }
    else {
        Clear-Host
    }
}

function Write-DTBlankLine {
    if (Get-Command Write-UiBlankLine -ErrorAction SilentlyContinue) {
        Write-UiBlankLine
    }
    else {
        Write-Host ""
    }
}

function Write-DTSection {
    param(
        [string]$Title,
        [string]$Color = $global:UI_CYN
    )

    if (Get-Command Write-UiSection -ErrorAction SilentlyContinue) {
        Write-UiSection -Title $Title -Color $Color
    }
    else {
        Write-Host "  $Color$Title$($global:UI_R)"
    }
}

function Write-DTRow {
    param(
        [string]$Name,
        [string]$Value,
        [string]$ValueColor = $global:UI_WHT
    )

    if (Get-Command Write-UiRow -ErrorAction SilentlyContinue) {
        Write-UiRow $Name $Value -ValueColor $ValueColor
    }
    else {
        Write-Host "  $($global:UI_WHT)$Name$($global:UI_R)  $ValueColor$Value$($global:UI_R)"
    }
}

function Show-WebRipperHeader {
    Clear-DTScreen

    $BoxWidth = 60
    if (Get-Command Get-UiBoxWidth -ErrorAction SilentlyContinue) {
        $BoxWidth = Get-UiBoxWidth -MaxWidth 60 -MinWidth 42
    }

    if (Get-Command Write-UiHeader -ErrorAction SilentlyContinue) {
        Write-UiHeader -Title $ScriptName -Subtitle "v$ScriptVersion  by $ScriptAuthor" -Width $BoxWidth
    }
    else {
        Write-Host ""
        Write-Host "  $($global:UI_CYN)$($global:UI_B)$ScriptName$($global:UI_R)"
        Write-Host "  $($global:UI_GRY)v$ScriptVersion  by $ScriptAuthor$($global:UI_R)"
        Write-Host ""
    }

    Write-DTRow "Output" $Script:OutputRoot $global:UI_GRY
    Write-DTRow "Format" $Script:OutputLabel $global:UI_GRY
    Write-DTBlankLine

    Write-DTSection "Supported Sites" $global:UI_CYN
    Write-Host "  1) Generic URL"
    Write-Host "  2) YouTube"
    Write-Host "  3) X / Twitter"
    Write-Host "  4) Instagram"
    Write-Host "  5) TikTok"
    Write-Host "  6) Vimeo"
    Write-Host "  7) Reddit"
    Write-Host "  $($global:UI_DIM)and many more via yt-dlp$($global:UI_R)"
    Write-DTBlankLine
    Write-Host "  $($global:UI_DIM)Note: site support can change as platforms update.$($global:UI_R)"
    Write-DTBlankLine
}

function Get-SafeFilename {
    param(
        [Parameter(Mandatory)][string]$Name,
        [int]$MaxLength = 140
    )

    $safe = $Name
    $invalidChars = [System.IO.Path]::GetInvalidFileNameChars()

    foreach ($char in $invalidChars) {
        $safe = $safe.Replace($char, '_')
    }

    $safe = ($safe -replace '\s+', ' ').Trim()
    $safe = $safe.TrimEnd('.', ' ')

    if ([string]::IsNullOrWhiteSpace($safe)) {
        $safe = "Untitled"
    }

    if ($safe.Length -gt $MaxLength) {
        $safe = $safe.Substring(0, $MaxLength).TrimEnd()
    }

    return $safe
}

function Get-WebPlatform {
    param([Parameter(Mandatory)][string]$Url)

    $u = $Url.ToLower()

    if ($u -match 'youtu\.be|youtube\.com') { return "YouTube" }
    if ($u -match 'twitter\.com|x\.com')    { return "X / Twitter" }
    if ($u -match 'instagram\.com')         { return "Instagram" }
    if ($u -match 'tiktok\.com')            { return "TikTok" }
    if ($u -match 'vimeo\.com')             { return "Vimeo" }
    if ($u -match 'reddit\.com|redd\.it')   { return "Reddit" }

    return "Unknown / Generic"
}

function Get-CookieArgs {
    param([string]$Platform)

    if ($Platform -ne "Instagram") {
        return @()
    }

    while ($true) {
        Show-WebRipperHeader
        Write-DTSection "Instagram Authentication" $global:UI_YLW
        Write-Host "  1) Use Firefox cookies"
        Write-Host "  2) Use Chrome cookies"
        Write-Host "  3) No cookies"
        Write-Host "  Q) Cancel"
        Write-DTBlankLine

        $choice = (Read-DTChoice "Choice:").Trim().ToLower()

        switch ($choice) {
            '1' { return @("--cookies-from-browser", "firefox") }
            '2' { return @("--cookies-from-browser", "chrome") }
            '3' { return @() }
            'q' { return $null }
            default {
                Write-Host ""
                Write-Host "  $($global:UI_RED)Invalid selection.$($global:UI_R)"
                Start-Sleep -Seconds 1
            }
        }
    }
}

function Get-FormatArgs {
    return @(
        "-S", "proto,ext:mp4:m4a,res,br"
    )
}

function Invoke-YTDlpCapture {
    param(
        [Parameter(Mandatory)][string[]]$Args
    )

    $output = & yt-dlp @Args 2>&1
    $exitCode = $LASTEXITCODE

    return [PSCustomObject]@{
        Output   = ($output -join [Environment]::NewLine)
        ExitCode = $exitCode
    }
}

function Get-WebMetadata {
    param(
        [Parameter(Mandatory)][string]$Url,
        [string[]]$CookieArgs = @()
    )

    $args = @(
        "-vU",
        "--no-playlist",
        "--dump-single-json",
        "--skip-download"
    ) + $CookieArgs + @("--", $Url)

    $result = Invoke-YTDlpCapture -Args $args

    if ($result.ExitCode -ne 0 -or [string]::IsNullOrWhiteSpace($result.Output)) {
        $msg = $result.Output.Trim()
        if ([string]::IsNullOrWhiteSpace($msg)) {
            $msg = "yt-dlp failed while fetching metadata."
        }
        throw $msg
    }

    $lines = $result.Output -split "`r?`n"
    $jsonStart = $lines | Where-Object { $_.Trim().StartsWith('{') } | Select-Object -First 1

    if (-not $jsonStart) {
        throw "yt-dlp did not return JSON metadata.`n`n$result.Output"
    }

    $jsonIndex = [Array]::IndexOf($lines, $jsonStart)
    $jsonText  = ($lines[$jsonIndex..($lines.Count - 1)] -join [Environment]::NewLine)

    try {
        return ($jsonText | ConvertFrom-Json)
    }
    catch {
        throw "yt-dlp returned non-JSON metadata output.`n`n$result.Output"
    }
}

function Select-WebFilename {
    param(
        [Parameter(Mandatory)][string]$Title,
        [Parameter(Mandatory)][string]$Uploader,
        [Parameter(Mandatory)][string]$Id
    )

    while ($true) {
        Show-WebRipperHeader
        Write-DTSection "Detected Metadata" $global:UI_CYN
        Write-DTRow "Title"    $Title
        Write-DTRow "Uploader" $Uploader
        Write-DTRow "ID"       $Id $global:UI_GRY
        Write-DTBlankLine

        Write-DTSection "Naming Options" $global:UI_YLW
        Write-Host "  1) Uploader - Title [ID]"
        Write-Host "  2) Title [ID]"
        Write-Host "  3) Manual title [ID]"
        Write-Host "  4) Manual full filename"
        Write-Host "  Q) Quit"
        Write-DTBlankLine

        $choice = (Read-DTChoice "Choice:").Trim().ToLower()

        switch ($choice) {
            '1' { return (Get-SafeFilename -Name "$Uploader - $Title [$Id]") }
            '2' { return (Get-SafeFilename -Name "$Title [$Id]") }
            '3' {
                $manualTitle = Read-Host "Enter manual title"
                if (-not [string]::IsNullOrWhiteSpace($manualTitle)) {
                    return (Get-SafeFilename -Name "$manualTitle [$Id]")
                }
            }
            '4' {
                $manualName = Read-Host "Enter full filename (no extension)"
                if (-not [string]::IsNullOrWhiteSpace($manualName)) {
                    return (Get-SafeFilename -Name $manualName)
                }
            }
            'q' { return $null }
            default {
                Write-Host ""
                Write-Host "  $($global:UI_RED)Invalid selection.$($global:UI_R)"
                Start-Sleep -Seconds 1
            }
        }
    }
}

function Invoke-WebDownload {
    param(
        [Parameter(Mandatory)][string]$Url,
        [Parameter(Mandatory)][string]$BaseName,
        [Parameter(Mandatory)][string]$Platform,
        [string[]]$CookieArgs = @()
    )

    $outputTemplate = Join-Path $Script:OutputRoot ($BaseName + ".%(ext)s")
    $formatArgs = Get-FormatArgs

    Show-WebRipperHeader
    Write-DTSection "Download Starting" $global:UI_CYN
    Write-DTRow "Filename" $BaseName
    Write-DTRow "Output"   $Script:OutputRoot $global:UI_GRY
    Write-DTRow "Format"   $Script:OutputLabel $global:UI_GRY
    Write-DTRow "Platform" $Platform
    Write-DTBlankLine

    $args = @()
    $args += @("-vU")
    $args += $formatArgs
    $args += @(
        "--merge-output-format", "mp4",
        "--embed-metadata",
        "--embed-thumbnail",
        "--convert-thumbnails", "jpg",
        "--no-playlist"
    )
    $args += $CookieArgs
    $args += @(
        "-o", $outputTemplate,
        "--", $Url
    )

    & yt-dlp @args

    if ($LASTEXITCODE -ne 0) {
        throw "yt-dlp failed with exit code $LASTEXITCODE. See debug output above."
    }

    Write-Host ""
    Write-Host "  $($global:UI_GRN)Download complete.$($global:UI_R)"
}

function Start-WebRipper {
    while ($true) {
        try {
            Show-WebRipperHeader
            Write-DTSection "Options" $global:UI_YLW
            Write-Host "  1) Download from URL"
            Write-Host "  2) YouTube"
            Write-Host "  3) X / Twitter"
            Write-Host "  4) Instagram"
            Write-Host "  5) TikTok"
            Write-Host "  6) Vimeo"
            Write-Host "  7) Reddit"
            Write-Host "  Q) Quit"
            Write-DTBlankLine

            $mainChoice = (Read-DTChoice "Choice:").Trim().ToLower()

            switch ($mainChoice) {
                'q' { return }
                '1' { $urlPrompt = "Enter URL (or Q to quit)" }
                '2' { $urlPrompt = "Enter YouTube URL (or Q to quit)" }
                '3' { $urlPrompt = "Enter X / Twitter URL (or Q to quit)" }
                '4' { $urlPrompt = "Enter Instagram URL (or Q to quit)" }
                '5' { $urlPrompt = "Enter TikTok URL (or Q to quit)" }
                '6' { $urlPrompt = "Enter Vimeo URL (or Q to quit)" }
                '7' { $urlPrompt = "Enter Reddit URL (or Q to quit)" }
                default {
                    Write-Host ""
                    Write-Host "  $($global:UI_RED)Invalid selection.$($global:UI_R)"
                    Start-Sleep -Seconds 1
                    continue
                }
            }

            Write-Host ""
            $url = Read-Host $urlPrompt

            if ([string]::IsNullOrWhiteSpace($url)) {
                Write-Host ""
                Write-Host "  $($global:UI_YLW)No URL entered.$($global:UI_R)"
                Pause-DT
                continue
            }

            if ($url.Trim().ToLower() -eq 'q') {
                continue
            }

            $platform = Get-WebPlatform -Url $url

            $cookieArgs = @()
            if ($platform -eq "Instagram") {
                $cookieArgs = Get-CookieArgs -Platform $platform
                if ($null -eq $cookieArgs) {
                    continue
                }
            }

            Show-WebRipperHeader
            Write-DTSection "Detected Site" $global:UI_CYN
            Write-DTRow "Platform" $platform
            Write-DTBlankLine

            Write-Host "  $($global:UI_CYN)Fetching metadata...$($global:UI_R)"
            Write-DTBlankLine

            $meta = Get-WebMetadata -Url $url -CookieArgs $cookieArgs

            $title = if ($meta.title) { $meta.title } else { "Untitled" }

            $uploader = if ($meta.uploader) {
                $meta.uploader
            }
            elseif ($meta.channel) {
                $meta.channel
            }
            elseif ($meta.creator) {
                $meta.creator
            }
            else {
                "UnknownUploader"
            }

            $id = if ($meta.id) { $meta.id } else { (Get-Date -Format "yyyyMMddHHmmss") }

            $baseName = Select-WebFilename -Title $title -Uploader $uploader -Id $id

            if (-not $baseName) {
                continue
            }

            Show-WebRipperHeader
            Write-DTSection "Ready to Download" $global:UI_CYN
            Write-DTRow "Platform" $platform
            Write-DTRow "Title"    $title
            Write-DTRow "Uploader" $uploader
            Write-DTRow "ID"       $id $global:UI_GRY
            Write-DTRow "Save As"  "$baseName.$($Script:OutputExt)"
            if ($platform -eq "Instagram" -and $cookieArgs.Count -gt 0) {
                Write-DTRow "Auth" "Browser Cookies" $global:UI_GRY
            }
            Write-DTBlankLine

            $confirm = (Read-DTChoice "Proceed? (Y/n)").Trim().ToLower()
            if ($confirm -match '^(n|no)$') {
                continue
            }

            Invoke-WebDownload -Url $url -BaseName $baseName -Platform $platform -CookieArgs $cookieArgs
            Pause-DT
        }
        catch {
            Write-Host ""
            Write-Host "  $($global:UI_RED)Error:$($global:UI_R) $($_.Exception.Message)"
            Pause-DT
        }
    }
}

# ── Main ──────────────────────────────────────────────────────
try {
    if (-not (Test-DTCommand -Name "yt-dlp")) {
        throw "yt-dlp was not found in PATH."
    }

    if (-not (Test-DTCommand -Name "ffmpeg")) {
        throw "ffmpeg was not found in PATH."
    }

    Start-WebRipper
}
catch {
    Show-WebRipperHeader
    Write-Host "  $($global:UI_RED)Error:$($global:UI_R) $($_.Exception.Message)"
    Pause-DT
}