#--------------------------------------------
# file:     mkv-sample.ps1
# author:   Mike Redd / ChatGPT
# version:  1.0
# created:  2026-04-16
# updated:  2026-04-16
# desc:     Create a short sample clip
#           from a finished MKV file
#           in G:\Rip\raw265 using ffmpeg
#--------------------------------------------

param()

# ── Load custom UI ────────────────────────────────────────────
$uiPath = "$env:USERPROFILE\PS\profile.d\ui.ps1"
if (Test-Path $uiPath) {
    try {
        . $uiPath
    }
    catch {
        Write-Host "Failed to load ui.ps1: $($_.Exception.Message)"
        return
    }
}
else {
    Write-Host "Missing ui.ps1: $uiPath"
    return
}

# ── Load core helper ──────────────────────────────────────────
$corePath = "$env:USERPROFILE\PS\profile.d\core.ps1"
if (Test-Path $corePath) {
    try {
        . $corePath
    }
    catch {
        Write-Host "Failed to load core.ps1: $($_.Exception.Message)"
        return
    }
}
else {
    Write-Host "Missing core.ps1: $corePath"
    return
}

$ErrorActionPreference = 'Stop'

$ScriptName    = "MKV Sample"
$ScriptVersion = "1.0"
$ScriptAuthor  = "Mike Redd"

# ── Config ────────────────────────────────────────────────────
$Script:RootPath       = "G:\Rip"
$Script:InputRoot      = Join-Path $Script:RootPath 'raw265'
$Script:SampleRoot     = Join-Path $Script:RootPath 'sample'
$Script:DefaultExt     = 'mkv'
$Script:DefaultStart   = '00:10:00'
$Script:DefaultLength  = 60
$Script:FFmpegPath     = $null
$Script:FFprobePath    = $null

# ── Header ────────────────────────────────────────────────────
function Show-Header {
    Clear-UiScreen
    $w = Get-UiBoxWidth -MaxWidth 64 -MinWidth 46

    Write-UiHeader -Title $ScriptName -Subtitle "v$ScriptVersion  by $ScriptAuthor" -Width $w
    Write-UiRow "User" "$env:USERNAME@$env:COMPUTERNAME"
    Write-UiRow "Input" $Script:InputRoot $global:UI_GRY
    Write-UiRow "Output" $Script:SampleRoot $global:UI_GRY
    Write-UiRow "Mode" "copy / $($Script:DefaultLength)s sample" $global:UI_GRY
    Write-UiBlankLine
}

# ── Menu ──────────────────────────────────────────────────────
function Show-Menu {
    Write-UiDivider
    Write-Host "  $($global:UI_GRN)  1)$($global:UI_R)  Create sample from selected MKV"
    Write-Host "  $($global:UI_GRN)  2)$($global:UI_R)  Show source files"
    Write-UiDivider
    Write-Host "  $($global:UI_CYN)  3)$($global:UI_R)  Show config"
    Write-UiDivider
    Write-Host "  $($global:UI_GRY)  Q)$($global:UI_R)  Quit"
    Write-UiBlankLine
}

function Pause-Script {
    Pause-Core "Press Enter to return to menu..."
}

function Get-ToolPath {
    param([Parameter(Mandatory)][string]$CommandName)

    $cmd = Get-Command $CommandName -ErrorAction SilentlyContinue
    if ($cmd -and $cmd.Source) {
        return [string]$cmd.Source
    }

    return $null
}

function Ensure-Directories {
    $paths = @(
        $Script:RootPath,
        $Script:InputRoot,
        $Script:SampleRoot
    )

    foreach ($p in $paths) {
        if (-not (Test-Path $p)) {
            New-Item -Path $p -ItemType Directory -Force | Out-Null
        }
    }
}

function Ensure-Dependencies {
    $missing = @()

    $Script:FFmpegPath  = Get-ToolPath -CommandName 'ffmpeg'
    $Script:FFprobePath = Get-ToolPath -CommandName 'ffprobe'

    if (-not $Script:FFmpegPath)  { $missing += 'ffmpeg' }
    if (-not $Script:FFprobePath) { $missing += 'ffprobe' }

    if ($missing.Count -gt 0) {
        Write-UiBlankLine
        Write-CoreError "Missing required tools: $($missing -join ', ')"
        throw "Required dependency missing."
    }
}

function New-SafeName {
    param([Parameter(Mandatory)][string]$Name)

    $safe = $Name -replace '[\\\/:\*\?"<>\|]', '_'
    $safe = $safe.Trim()

    if ([string]::IsNullOrWhiteSpace($safe)) {
        $safe = "sample_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
    }

    return [string]$safe
}

function Get-MkvFiles {
    if (-not (Test-Path $Script:InputRoot)) {
        return @()
    }

    return @(Get-ChildItem -Path $Script:InputRoot -Filter *.mkv -File | Sort-Object LastWriteTime -Descending)
}

function Show-SourceFiles {
    $files = Get-MkvFiles

    Write-UiBlankLine

    if (-not $files -or $files.Count -eq 0) {
        Write-CoreError "No .mkv files found in $($Script:InputRoot)"
        Pause-Script
        return
    }

    $rows = foreach ($f in $files) {
        [pscustomobject]@{
            Name     = $f.Name
            SizeGB   = [math]::Round(($f.Length / 1GB), 2)
            Modified = $f.LastWriteTime
        }
    }

    Write-Host "  $($global:UI_MAG)Available source files:$($global:UI_R)"
    $rows | Format-Table -AutoSize
    Pause-Script
}

function Get-DefaultMovieName {
    param([Parameter(Mandatory)][System.IO.FileInfo]$File)
    return [string]([System.IO.Path]::GetFileNameWithoutExtension($File.Name))
}

function Get-SampleOutputPath {
    param([Parameter(Mandatory)][string]$MovieName)

    $safeName = New-SafeName -Name $MovieName
    $outputFile = Join-Path $Script:SampleRoot "${safeName}_sample.$($Script:DefaultExt)"

    if (Test-Path $outputFile) {
        $stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
        $outputFile = Join-Path $Script:SampleRoot "${safeName}_sample_$stamp.$($Script:DefaultExt)"
    }

    return [string]$outputFile
}

function Get-VideoDuration {
    param([Parameter(Mandatory)][string]$Path)

    $args = @(
        '-v', 'error',
        '-show_entries', 'format=duration',
        '-of', 'default=noprint_wrappers=1:nokey=1',
        $Path
    )

    $out = & $Script:FFprobePath @args 2>$null

    if ($LASTEXITCODE -ne 0) {
        return 0
    }

    $value = ($out | Out-String).Trim()
    $duration = 0.0

    if ([double]::TryParse(
        $value,
        [System.Globalization.NumberStyles]::Float,
        [System.Globalization.CultureInfo]::InvariantCulture,
        [ref]$duration
    )) {
        return $duration
    }

    return 0
}

function Get-SafeSampleStart {
    param([Parameter(Mandatory)][double]$DurationSeconds)

    $defaultStartSeconds = [int]([TimeSpan]::Parse($Script:DefaultStart).TotalSeconds)

    if ($DurationSeconds -le ($Script:DefaultLength + 5)) {
        return '00:00:00'
    }

    if ($DurationSeconds -le ($defaultStartSeconds + $Script:DefaultLength)) {
        $fallbackStart = [Math]::Max([int]($DurationSeconds - $Script:DefaultLength - 5), 0)
        return ([TimeSpan]::FromSeconds($fallbackStart).ToString("hh\:mm\:ss"))
    }

    return $Script:DefaultStart
}

function Create-SampleFile {
    param([Parameter(Mandatory)][System.IO.FileInfo]$SourceFile)

    $movieName = Get-DefaultMovieName -File $SourceFile
    $outputFile = Get-SampleOutputPath -MovieName $movieName
    $duration = Get-VideoDuration -Path $SourceFile.FullName
    $sampleStart = Get-SafeSampleStart -DurationSeconds $duration

    Write-UiBlankLine
    Write-Host "  $($global:UI_GRN)Creating sample file...$($global:UI_R)"
    Write-Host "  $($global:UI_DIM)Input $($global:UI_R)  $($SourceFile.FullName)"
    Write-Host "  $($global:UI_DIM)Output$($global:UI_R)  $outputFile"
    Write-Host "  $($global:UI_DIM)Start $($global:UI_R)  $sampleStart"
    Write-Host "  $($global:UI_DIM)Length$($global:UI_R)  $($Script:DefaultLength) seconds"
    Write-Host "  $($global:UI_DIM)Mode  $($global:UI_R)  stream copy"
    Write-UiBlankLine

    $args = @(
        '-hide_banner',
        '-y',
        '-ss', $sampleStart,
        '-i', $SourceFile.FullName,
        '-t', "$($Script:DefaultLength)",
        '-map', '0:v?',
        '-map', '0:a?',
        '-map', '0:s?',
        '-c', 'copy',
        $outputFile
    )

    & $Script:FFmpegPath @args

    if ($LASTEXITCODE -ne 0) {
        throw "ffmpeg failed with exit code $LASTEXITCODE"
    }

    Start-Sleep -Milliseconds 300

    $outputInfo = Get-Item -Path $outputFile -ErrorAction SilentlyContinue
    if (-not $outputInfo) {
        throw "Sample creation failed. Output file not found."
    }

    if ($outputInfo.Length -le 0) {
        throw "Sample creation failed. Output file is empty."
    }

    Write-UiBlankLine
    Write-Host "  $($global:UI_GRN)Sample complete.$($global:UI_R)"
    Write-Host "  $($global:UI_DIM)Saved $($global:UI_R)  $($outputInfo.FullName)"
    Write-Host "  $($global:UI_DIM)Size  $($global:UI_R)  $([math]::Round(($outputInfo.Length / 1MB), 2)) MB"
}

function Create-SampleFromSelectedFile {
    $files = Get-MkvFiles

    Write-UiBlankLine

    if (-not $files -or $files.Count -eq 0) {
        Write-CoreError "No .mkv files found in $($Script:InputRoot)"
        Pause-Script
        return
    }

    Write-Host "  $($global:UI_MAG)Source files:$($global:UI_R)"
    for ($i = 0; $i -lt $files.Count; $i++) {
        $sizeGb = [math]::Round(($files[$i].Length / 1GB), 2)
        Write-Host ("  {0,2}) {1}  [{2} GB]" -f ($i + 1), $files[$i].Name, $sizeGb)
    }

    Write-Host ""
    $pick = Read-Host "Choose file number"

    if (-not ($pick -match '^\d+$')) {
        Write-CoreError "Invalid selection."
        Pause-Script
        return
    }

    $index = [int]$pick - 1
    if ($index -lt 0 -or $index -ge $files.Count) {
        Write-CoreError "Selection out of range."
        Pause-Script
        return
    }

    $file = $files[$index]

    try {
        Create-SampleFile -SourceFile $file
    }
    catch {
        Write-UiBlankLine
        Write-CoreError $_.Exception.Message
    }

    Pause-Script
}

function Show-Config {
    Write-UiBlankLine
    Write-UiRow "RootPath"    $Script:RootPath $global:UI_GRY
    Write-UiRow "InputRoot"   $Script:InputRoot $global:UI_GRY
    Write-UiRow "SampleRoot"  $Script:SampleRoot $global:UI_GRY
    Write-UiRow "Start"       $Script:DefaultStart $global:UI_GRY
    Write-UiRow "Length"      "$($Script:DefaultLength) sec" $global:UI_GRY
    Write-UiRow "FFmpeg"      $Script:FFmpegPath $global:UI_GRY
    Write-UiRow "FFprobe"     $Script:FFprobePath $global:UI_GRY
    Pause-Script
}

try {
    Ensure-Dependencies
    Ensure-Directories
}
catch {
    Write-UiBlankLine
    Write-CoreError $_.Exception.Message
    return
}

while ($true) {
    Show-Header
    Show-Menu
    $choice = (Read-Host "Choose").Trim().ToUpper()

    switch ($choice) {
        '1' { Create-SampleFromSelectedFile }
        '2' { Show-SourceFiles }
        '3' { Show-Config }
        'Q' {
            Write-UiBlankLine
            Write-Host "  $($global:UI_CYN)Goodbye.$($global:UI_R)"
            Write-UiBlankLine
            return
        }
        default {
            Write-CoreError "Invalid choice."
            Start-Sleep -Seconds 1
        }
    }
}