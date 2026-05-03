#--------------------------------------------
# file:     brEncoder.ps1
# author:   Mike Redd
# version:  1.6
# created:  2026-02-11
# updated:  2026-04-18
# desc:     Encode Blu-ray .m2ts files
#           to H.265/HEVC on Windows
#           using ffmpeg, then create a
#           sample clip from the finished MKV
#           and apply track metadata from
#           sidecar JSON when available
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

$ScriptName    = "Blu-ray Encoder"
$ScriptVersion = "1.6"
$ScriptAuthor  = "Mike Redd"

# ── Config ────────────────────────────────────────────────────
$Script:RootPath        = "G:\Rip"
$Script:InputRoot       = Join-Path $Script:RootPath 'bluray'
$Script:OutputRoot      = Join-Path $Script:RootPath 'raw265'
$Script:DoneRoot        = Join-Path $Script:RootPath 'done'
$Script:SampleRoot      = Join-Path $Script:RootPath 'sample'
$Script:SubtitleRoot    = Join-Path $Script:RootPath 'subtitles'
$Script:MetaRoot        = Join-Path $Script:RootPath 'meta'
$Script:TxtRoot         = Join-Path $Script:RootPath 'txt'

$Script:DefaultCRF      = 18
$Script:DefaultPreset   = 'slow'
$Script:DefaultAudio    = 'copy'
$Script:DefaultExt      = 'mkv'
$Script:DefaultStart    = '00:10:00'
$Script:DefaultLength   = 60

$Script:FFmpegPath      = $null
$Script:FFprobePath     = $null
$Script:MKVPropEditPath = $null

# ── Header ────────────────────────────────────────────────────
function Show-Header {
    Clear-UiScreen
    $w = Get-UiBoxWidth -MaxWidth 64 -MinWidth 46

    Write-UiHeader -Title $ScriptName -Subtitle "v$ScriptVersion  by $ScriptAuthor" -Width $w
    Write-UiRow "User" "$env:USERNAME@$env:COMPUTERNAME"
    Write-UiRow "Input" $Script:InputRoot $global:UI_GRY
    Write-UiRow "Meta" "G:\Rip\meta" $global:UI_GRY
    Write-UiRow "Mode" "x265 / CRF $($Script:DefaultCRF) / $($Script:DefaultPreset) / $($Script:DefaultExt)" $global:UI_GRY
    Write-UiRow "Sample" "$($Script:DefaultLength)s from finished MKV" $global:UI_GRY
    Write-UiBlankLine
}

# ── Menu ──────────────────────────────────────────────────────
function Show-Menu {
    Write-UiDivider
    Write-Host "  $($global:UI_GRN)  1)$($global:UI_R)  Encode all .m2ts files"
    Write-Host "  $($global:UI_GRN)  2)$($global:UI_R)  Encode single file"
    Write-Host "  $($global:UI_GRN)  3)$($global:UI_R)  Show source files"
    Write-UiDivider
    Write-Host "  $($global:UI_CYN)  4)$($global:UI_R)  Show config"
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
        $Script:OutputRoot,
        $Script:DoneRoot,
        $Script:SampleRoot,
        $Script:SubtitleRoot,
        $Script:MetaRoot,
        $Script:TxtRoot
    )

    foreach ($p in $paths) {
        if (-not (Test-Path $p)) {
            New-Item -Path $p -ItemType Directory -Force | Out-Null
        }
    }
}

function Ensure-Dependencies {
    $missing = @()

    $Script:FFmpegPath      = Get-ToolPath -CommandName 'ffmpeg'
    $Script:FFprobePath     = Get-ToolPath -CommandName 'ffprobe'
    $Script:MKVPropEditPath = Get-ToolPath -CommandName 'mkvpropedit'

    if (-not $Script:FFmpegPath)      { $missing += 'ffmpeg' }
    if (-not $Script:FFprobePath)     { $missing += 'ffprobe' }
    if (-not $Script:MKVPropEditPath) { $missing += 'mkvpropedit' }

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
        $safe = "bluray_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
    }

    return [string]$safe
}

function Get-M2tsFiles {
    if (-not (Test-Path $Script:InputRoot)) {
        return @()
    }

    return @(
        Get-ChildItem -Path $Script:InputRoot -Filter *.m2ts -File -Recurse |
        Sort-Object Length -Descending
    )
}

function Show-SourceFiles {
    $files = Get-M2tsFiles

    Write-UiBlankLine

    if (-not $files -or $files.Count -eq 0) {
        Write-CoreError "No .m2ts files found in $($Script:InputRoot)"
        Pause-Script
        return
    }

    $rows = foreach ($f in $files) {
        [pscustomobject]@{
            Name     = $f.Name
            SizeGB   = [math]::Round(($f.Length / 1GB), 2)
            Modified = $f.LastWriteTime
            Folder   = $f.DirectoryName
        }
    }

    Write-Host "  $($global:UI_MAG)Available source files:$($global:UI_R)"
    $rows | Format-Table -AutoSize
    Pause-Script
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

function Get-DefaultMovieName {
    param([Parameter(Mandatory)][System.IO.FileInfo]$File)
    return [string]([System.IO.Path]::GetFileNameWithoutExtension($File.Name))
}

function Read-MovieNameWithYear {
    param([string]$DefaultName)

    $movieName = Read-Host "Movie name [$DefaultName]"
    if ([string]::IsNullOrWhiteSpace($movieName)) {
        $movieName = $DefaultName
    }

    $movieYear = Read-Host "Year (optional, 4 digits)"
    if (-not [string]::IsNullOrWhiteSpace($movieYear)) {
        if ($movieYear -match '^\d{4}$') {
            $movieName = "$movieName [$movieYear]"
        }
    }

    return [string]$movieName
}

function Get-OutputPath {
    param([Parameter(Mandatory)][string]$MovieName)

    $safeName = New-SafeName -Name $MovieName
    return [string](Join-Path $Script:OutputRoot "$safeName.$($Script:DefaultExt)")
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

function Move-SourceToDone {
    param([Parameter(Mandatory)][System.IO.FileInfo]$SourceFile)

    $dest = Join-Path $Script:DoneRoot $SourceFile.Name

    if (Test-Path $dest) {
        $stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
        $dest = Join-Path $Script:DoneRoot ("{0}_{1}{2}" -f $SourceFile.BaseName, $stamp, $SourceFile.Extension)
    }

    Move-Item -Path $SourceFile.FullName -Destination $dest -Force
    return [string]$dest
}

function Write-MetaFile {
    param(
        [Parameter(Mandatory)][string]$MovieName,
        [Parameter(Mandatory)][System.IO.FileInfo]$SourceFile,
        [Parameter(Mandatory)][string]$OutputFile,
        [Parameter(Mandatory)][double]$DurationSeconds,
        [string]$TrackMetaPath
    )

    $safeName = New-SafeName -Name $MovieName
    $metaFile = Join-Path $Script:TxtRoot "$safeName.txt"

@"
MovieName : $MovieName
Source    : $($SourceFile.FullName)
Output    : $OutputFile
Encoded   : $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
Codec     : libx265
CRF       : $($Script:DefaultCRF)
Preset    : $($Script:DefaultPreset)
Audio     : $($Script:DefaultAudio)
Duration  : $DurationSeconds
Sample    : $($Script:DefaultLength) sec
TrackMeta : $TrackMetaPath
"@ | Set-Content -Path $metaFile -Encoding UTF8
}

function Wait-ForOutputFile {
    param(
        [Parameter(Mandatory)][string]$Path,
        [int]$InitialDelaySeconds = 2,
        [int]$RetryCount = 5,
        [int]$RetryDelaySeconds = 1
    )

    Start-Sleep -Seconds $InitialDelaySeconds

    $fileInfo = $null

    for ($i = 0; $i -lt $RetryCount; $i++) {
        $fileInfo = Get-Item -Path $Path -ErrorAction SilentlyContinue
        if ($fileInfo) {
            break
        }

        Start-Sleep -Seconds $RetryDelaySeconds
    }

    if (-not $fileInfo) {
        throw "Output file not found after retry: $Path"
    }

    if ($fileInfo.Length -le 0) {
        throw "Output file is empty: $Path"
    }

    return $fileInfo
}

function Get-TrackMetaCandidates {
    param(
        [Parameter(Mandatory)][System.IO.FileInfo]$SourceFile,
        [Parameter(Mandatory)][string]$MovieName
    )

    $candidates = @()

    $sourceBase = [System.IO.Path]::GetFileNameWithoutExtension($SourceFile.Name)
    $movieSafe  = New-SafeName -Name $MovieName

    $candidates += (Join-Path $Script:MetaRoot "$sourceBase.json")
    $candidates += (Join-Path $Script:MetaRoot "$movieSafe.json")

    return @($candidates | Select-Object -Unique)
}

function Load-TrackMetadata {
    param(
        [Parameter(Mandatory)][System.IO.FileInfo]$SourceFile,
        [Parameter(Mandatory)][string]$MovieName
    )

    $candidates = Get-TrackMetaCandidates -SourceFile $SourceFile -MovieName $MovieName

    foreach ($path in $candidates) {
        if (Test-Path -LiteralPath $path) {
            try {
                $raw = Get-Content -LiteralPath $path -Raw -Encoding UTF8
                $json = $raw | ConvertFrom-Json
                return [pscustomobject]@{
                    Path = $path
                    Data = $json
                }
            }
            catch {
                Write-UiBlankLine
                Write-CoreError "Failed to read track metadata: $path"
                Write-Host "  $($global:UI_GRY)$($_.Exception.Message)$($global:UI_R)"
                return $null
            }
        }
    }

    return $null
}

function Get-OutputTrackLayout {
    param([Parameter(Mandatory)][string]$Path)

    $args = @(
        '-v', 'error',
        '-show_streams',
        '-of', 'json',
        $Path
    )

    $jsonText = & $Script:FFprobePath @args 2>$null
    if ($LASTEXITCODE -ne 0) {
        throw "ffprobe failed while reading output track layout."
    }

    $json = ($jsonText | Out-String) | ConvertFrom-Json
    $streams = @($json.streams)

    $audio = @($streams | Where-Object { $_.codec_type -eq 'audio' })
    $subs  = @($streams | Where-Object { $_.codec_type -eq 'subtitle' })

    [pscustomobject]@{
        AudioCount    = $audio.Count
        SubtitleCount = $subs.Count
    }
}

function Apply-TrackMetadata {
    param(
        [Parameter(Mandatory)][string]$OutputFile,
        [Parameter(Mandatory)][System.IO.FileInfo]$SourceFile,
        [Parameter(Mandatory)][string]$MovieName
    )

    $metaInfo = Load-TrackMetadata -SourceFile $SourceFile -MovieName $MovieName
    if (-not $metaInfo) {
        Write-UiBlankLine
        Write-Host "  $($global:UI_YLW)No matching track metadata JSON found. Skipping label pass.$($global:UI_R)"
        return $null
    }

    $trackLayout = Get-OutputTrackLayout -Path $OutputFile
    $meta = $metaInfo.Data

    if (-not $meta.Title) {
        Write-UiBlankLine
        Write-CoreError "Track metadata JSON does not contain Title data."
        return $metaInfo.Path
    }

    $audioMeta = @($meta.Title.AudioTracks | Sort-Object TrackId)
    $subMeta   = @($meta.Title.SubtitleTracks | Sort-Object TrackId)

    $audioToApply = [Math]::Min($trackLayout.AudioCount, $audioMeta.Count)
    $subToApply   = [Math]::Min($trackLayout.SubtitleCount, $subMeta.Count)

    Write-UiBlankLine
    Write-Host "  $($global:UI_CYN)Applying track metadata...$($global:UI_R)"
    Write-Host "  $($global:UI_DIM)Meta  $($global:UI_R)  $($metaInfo.Path)"
    Write-Host "  $($global:UI_DIM)Audio $($global:UI_R)  output=$($trackLayout.AudioCount) / meta=$($audioMeta.Count)"
    Write-Host "  $($global:UI_DIM)Subs  $($global:UI_R)  output=$($trackLayout.SubtitleCount) / meta=$($subMeta.Count)"
    Write-UiBlankLine

    $args = @($OutputFile)

    for ($i = 0; $i -lt $audioToApply; $i++) {
        $trackNum = $i + 1
        $track = $audioMeta[$i]

        $args += '--edit'
        $args += "track:a$trackNum"

        if (-not [string]::IsNullOrWhiteSpace($track.LanguageCode)) {
            $args += '--set'
            $args += "language=$($track.LanguageCode)"
        }

        if (-not [string]::IsNullOrWhiteSpace($track.Description)) {
            $args += '--set'
            $args += "name=$($track.Description)"
        }

        $args += '--set'
        $args += ("flag-default={0}" -f $(if ($track.Default) { 1 } else { 0 }))
    }

    for ($i = 0; $i -lt $subToApply; $i++) {
        $trackNum = $i + 1
        $track = $subMeta[$i]

        $args += '--edit'
        $args += "track:s$trackNum"

        if (-not [string]::IsNullOrWhiteSpace($track.LanguageCode)) {
            $args += '--set'
            $args += "language=$($track.LanguageCode)"
        }

        if (-not [string]::IsNullOrWhiteSpace($track.Description)) {
            $args += '--set'
            $args += "name=$($track.Description)"
        }

        $args += '--set'
        $args += ("flag-default={0}" -f $(if ($track.Default) { 1 } else { 0 }))

        $args += '--set'
        $args += ("flag-forced={0}" -f $(if ($track.Forced) { 1 } else { 0 }))
    }

    & $Script:MKVPropEditPath @args

    if ($LASTEXITCODE -ne 0) {
        throw "mkvpropedit failed with exit code $LASTEXITCODE"
    }

    Write-UiBlankLine
    Write-Host "  $($global:UI_GRN)Track metadata applied.$($global:UI_R)"
    return $metaInfo.Path
}

function Create-SampleFromFinishedMkv {
    param(
        [Parameter(Mandatory)][string]$FinishedMkvPath,
        [Parameter(Mandatory)][string]$MovieName
    )

    $duration = Get-VideoDuration -Path $FinishedMkvPath
    $sampleStart = Get-SafeSampleStart -DurationSeconds $duration
    $sampleOutput = Get-SampleOutputPath -MovieName $MovieName

    Write-UiBlankLine
    Write-Host "  $($global:UI_CYN)Creating sample from finished MKV...$($global:UI_R)"
    Write-Host "  $($global:UI_DIM)Input $($global:UI_R)  $FinishedMkvPath"
    Write-Host "  $($global:UI_DIM)Output$($global:UI_R)  $sampleOutput"
    Write-Host "  $($global:UI_DIM)Start $($global:UI_R)  $sampleStart"
    Write-Host "  $($global:UI_DIM)Length$($global:UI_R)  $($Script:DefaultLength) seconds"
    Write-Host "  $($global:UI_DIM)Mode  $($global:UI_R)  stream copy"
    Write-UiBlankLine

    $args = @(
        '-hide_banner',
        '-y',
        '-ss', $sampleStart,
        '-i', $FinishedMkvPath,
        '-t', "$($Script:DefaultLength)",
        '-map', '0:v?',
        '-map', '0:a?',
        '-map', '0:s?',
        '-c', 'copy',
        $sampleOutput
    )

    & $Script:FFmpegPath @args

    if ($LASTEXITCODE -ne 0) {
        throw "Sample creation failed. ffmpeg exit code $LASTEXITCODE"
    }

    $sampleInfo = Wait-ForOutputFile -Path $sampleOutput

    Write-UiBlankLine
    Write-Host "  $($global:UI_GRN)Sample complete.$($global:UI_R)"
    Write-Host "  $($global:UI_DIM)Saved $($global:UI_R)  $($sampleInfo.FullName)"
    Write-Host "  $($global:UI_DIM)Size  $($global:UI_R)  $([math]::Round(($sampleInfo.Length / 1MB), 2)) MB"
}

function Encode-File {
    param(
        [Parameter(Mandatory)][System.IO.FileInfo]$SourceFile,
        [Parameter(Mandatory)][string]$MovieName
    )

    $outputFile = Get-OutputPath -MovieName $MovieName
    $duration   = Get-VideoDuration -Path $SourceFile.FullName
    $trackMetaPath = ""

    Write-UiBlankLine
    Write-Host "  $($global:UI_GRN)Encoding file...$($global:UI_R)"
    Write-Host "  $($global:UI_DIM)Input $($global:UI_R)  $($SourceFile.FullName)"
    Write-Host "  $($global:UI_DIM)Output$($global:UI_R)  $outputFile"
    Write-Host "  $($global:UI_DIM)Codec $($global:UI_R)  libx265"
    Write-Host "  $($global:UI_DIM)CRF   $($global:UI_R)  $($Script:DefaultCRF)"
    Write-Host "  $($global:UI_DIM)Preset$($global:UI_R)  $($Script:DefaultPreset)"
    Write-Host "  $($global:UI_DIM)Audio $($global:UI_R)  $($Script:DefaultAudio)"
    Write-UiBlankLine

    $args = @(
        '-hide_banner',
        '-y',
        '-i', $SourceFile.FullName,
        '-map', '0:v:0',
        '-map', '0:a?',
        '-map', '0:s?',
        '-c:v', 'libx265',
        '-preset', $Script:DefaultPreset,
        '-crf', "$($Script:DefaultCRF)",
        '-c:a', $Script:DefaultAudio,
        '-c:s', 'copy',
        $outputFile
    )

    & $Script:FFmpegPath @args

    if ($LASTEXITCODE -ne 0) {
        throw "ffmpeg failed with exit code $LASTEXITCODE"
    }

    $encodedInfo = Wait-ForOutputFile -Path $outputFile

    $appliedMeta = Apply-TrackMetadata -OutputFile $encodedInfo.FullName -SourceFile $SourceFile -MovieName $MovieName
    if ($appliedMeta) {
        $trackMetaPath = $appliedMeta
    }

    Create-SampleFromFinishedMkv -FinishedMkvPath $encodedInfo.FullName -MovieName $MovieName

    $donePath = Move-SourceToDone -SourceFile $SourceFile
    Write-MetaFile -MovieName $MovieName -SourceFile $SourceFile -OutputFile $encodedInfo.FullName -DurationSeconds $duration -TrackMetaPath $trackMetaPath

    Write-UiBlankLine
    Write-Host "  $($global:UI_GRN)Encode complete.$($global:UI_R)"
    Write-Host "  $($global:UI_DIM)Saved $($global:UI_R)  $($encodedInfo.FullName)"
    Write-Host "  $($global:UI_DIM)Moved $($global:UI_R)  $donePath"
}

function Encode-SingleFile {
    $files = Get-M2tsFiles

    Write-UiBlankLine

    if (-not $files -or $files.Count -eq 0) {
        Write-CoreError "No .m2ts files found in $($Script:InputRoot)"
        Pause-Script
        return
    }

    Write-Host "  $($global:UI_MAG)Source files:$($global:UI_R)"
    for ($i = 0; $i -lt $files.Count; $i++) {
        $sizeGb = [math]::Round(($files[$i].Length / 1GB), 2)
        Write-Host ("  {0,2}) {1}  [{2} GB]" -f ($i + 1), $files[$i].Name, $sizeGb)
    }

    Write-UiBlankLine
    $pick = Read-Host "Choose file number [1]"

    if ([string]::IsNullOrWhiteSpace($pick)) {
        $pick = '1'
    }

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
    $defaultName = Get-DefaultMovieName -File $file
    $movieName = Read-MovieNameWithYear -DefaultName $defaultName

    try {
        Encode-File -SourceFile $file -MovieName $movieName
    }
    catch {
        Write-UiBlankLine
        Write-CoreError $_.Exception.Message
    }

    Pause-Script
}

function Encode-AllFiles {
    $files = Get-M2tsFiles

    Write-UiBlankLine

    if (-not $files -or $files.Count -eq 0) {
        Write-CoreError "No .m2ts files found in $($Script:InputRoot)"
        Pause-Script
        return
    }

    Write-Host "  $($global:UI_YLW)About to encode $($files.Count) file(s).$($global:UI_R)"
    $confirm = Read-Host "Continue? (Y/N)"
    if ($confirm -notmatch '^(Y|y)$') {
        Pause-Script
        return
    }

    foreach ($file in $files) {
        $defaultName = Get-DefaultMovieName -File $file
        $movieName = $defaultName

        Write-UiBlankLine
        Write-Host "  $($global:UI_CYN)Now encoding:$($global:UI_R) $($file.Name)"

        try {
            Encode-File -SourceFile $file -MovieName $movieName
        }
        catch {
            Write-UiBlankLine
            Write-CoreError "Failed on $($file.Name): $($_.Exception.Message)"
        }
    }

    Pause-Script
}

function Show-Config {
    Write-UiBlankLine
    Write-UiRow "RootPath"     $Script:RootPath $global:UI_GRY
    Write-UiRow "InputRoot"    $Script:InputRoot $global:UI_GRY
    Write-UiRow "OutputRoot"   $Script:OutputRoot $global:UI_GRY
    Write-UiRow "DoneRoot"     $Script:DoneRoot $global:UI_GRY
    Write-UiRow "SampleRoot"   $Script:SampleRoot $global:UI_GRY
    Write-UiRow "SubtitleRoot" $Script:SubtitleRoot $global:UI_GRY
    Write-UiRow "MetaRoot"     $Script:MetaRoot $global:UI_GRY
    Write-UiRow "TxtRoot"      $Script:TxtRoot $global:UI_GRY
    Write-UiRow "CRF"          "$($Script:DefaultCRF)" $global:UI_GRY
    Write-UiRow "Preset"       $Script:DefaultPreset $global:UI_GRY
    Write-UiRow "Audio"        $Script:DefaultAudio $global:UI_GRY
    Write-UiRow "SampleStart"  $Script:DefaultStart $global:UI_GRY
    Write-UiRow "SampleLength" "$($Script:DefaultLength) sec" $global:UI_GRY
    Write-UiRow "FFmpeg"       $Script:FFmpegPath $global:UI_GRY
    Write-UiRow "FFprobe"      $Script:FFprobePath $global:UI_GRY
    Write-UiRow "MKVPropEdit"  $Script:MKVPropEditPath $global:UI_GRY
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
        '1' { Encode-AllFiles }
        '2' { Encode-SingleFile }
        '3' { Show-SourceFiles }
        '4' { Show-Config }
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