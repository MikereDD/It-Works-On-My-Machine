#--------------------------------------------
# file:     dvd-ripper-encoder.ps1
# author:   Mike Redd
# version:  3.1
# created:  2026-04-11
# updated:  2026-04-11
# desc:     Encode DVDs directly with HandBrakeCLI
#           on Windows using high-quality x265 defaults
#--------------------------------------------

param(
    [switch]$DryRun
)

# ── Load custom UI ────────────────────────────────────────────
$uiPath = "$env:USERPROFILE\PS\profile.d\ui.ps1"
if (Test-Path -LiteralPath $uiPath) {
    try { . $uiPath }
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
if (Test-Path -LiteralPath $corePath) {
    try { . $corePath }
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

$ScriptName    = "DVD Ripper Encoder"
$ScriptVersion = "3.1"
$ScriptAuthor  = "Mike Redd"

# ── Config ────────────────────────────────────────────────────
$Script:RootPath         = "G:\Rip"
$Script:OutputRoot       = Join-Path $Script:RootPath 'dvdarchive'
$Script:NfoRoot          = Join-Path $Script:RootPath 'nfo'
$Script:DefaultDrive     = 'D:'
$Script:HandBrakeCLI     = $null

$Script:DefaultContainer = 'mkv'
$Script:DefaultEncoder   = 'x265_10bit'
$Script:DefaultRF        = 20
$Script:DefaultPreset    = 'slower'
$Script:MinTitleSeconds  = 900   # 15 min

# ── Header ────────────────────────────────────────────────────
function Show-Header {
    Clear-UiScreen
    $w = Get-UiBoxWidth -MaxWidth 70 -MinWidth 48

    Write-UiHeader -Title $ScriptName -Subtitle "v$ScriptVersion  by $ScriptAuthor" -Width $w
    Write-UiRow "User"     "$env:USERNAME@$env:COMPUTERNAME"
    Write-UiRow "Defaults" "$($Script:DefaultEncoder) / RF $($Script:DefaultRF) / $($Script:DefaultPreset) / $($Script:DefaultContainer)" $global:UI_GRY
    if ($DryRun) {
        Write-UiRow "Mode" "DRY RUN — no files will be written" $global:UI_YLW
    }
    Write-UiBlankLine
}

# ── Menu ──────────────────────────────────────────────────────
function Show-Menu {
    Write-UiDivider
    Write-Host "  $($global:UI_GRN)  1)$($global:UI_R)  Encode directly from DVD"
    Write-Host "  $($global:UI_GRN)  2)$($global:UI_R)  Scan DVD titles only"
    Write-Host "  $($global:UI_GRN)  3)$($global:UI_R)  Encode from existing folder"
    Write-UiDivider
    Write-Host "  $($global:UI_CYN)  4)$($global:UI_R)  Show config"
    Write-UiDivider
    Write-Host "  $($global:UI_GRY)  Q)$($global:UI_R)  Quit"
    Write-UiBlankLine
}

function Pause-Script {
    Pause-Core "Press Enter to return to menu..."
}

function Test-CommandExists {
    param([Parameter(Mandatory)][string]$Name)
    return [bool](Get-Command $Name -ErrorAction SilentlyContinue)
}

function Get-HandBrakeCLIPath {
    if ($Script:HandBrakeCLI -and (Test-Path -LiteralPath $Script:HandBrakeCLI)) {
        return [string]$Script:HandBrakeCLI
    }

    $paths = @(
        'C:\Program Files\HandBrake\HandBrakeCLI.exe',
        "$env:LOCALAPPDATA\Programs\HandBrake\HandBrakeCLI.exe",
        'C:\Tools\HandBrake\HandBrakeCLI.exe'
    )

    foreach ($p in $paths) {
        if (Test-Path -LiteralPath $p) {
            return [string]$p
        }
    }

    $cmd = Get-Command HandBrakeCLI -ErrorAction SilentlyContinue
    if ($cmd -and $cmd.Source -and (Test-Path -LiteralPath $cmd.Source)) {
        return [string]$cmd.Source
    }

    return $null
}

function Ensure-Directories {
    foreach ($p in @($Script:RootPath, $Script:OutputRoot, $Script:NfoRoot)) {
        if (-not (Test-Path -LiteralPath $p)) {
            [System.IO.Directory]::CreateDirectory($p) | Out-Null
        }
    }
}

function Ensure-Dependencies {
    $resolvedCli = Get-HandBrakeCLIPath
    if (-not $resolvedCli) {
        throw "HandBrakeCLI was not found."
    }

    $Script:HandBrakeCLI = $resolvedCli
}

function New-SafeName {
    param([Parameter(Mandatory)][string]$Name)

    $safe = $Name -replace '[\\\/:\*\?"<>\|]', '_'
    $safe = $safe.Trim()

    if ([string]::IsNullOrWhiteSpace($safe)) {
        $safe = "dvd_encode_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
    }

    return [string]$safe
}

function Get-DvdSourcePath {
    param([string]$DriveLetter = $Script:DefaultDrive)

    $drive = $DriveLetter.Trim()
    if ($drive -notmatch ':$') { $drive += ':' }

    $videoTs = Join-Path $drive 'VIDEO_TS'
    if (Test-Path -LiteralPath $videoTs) {
        return [string]$drive
    }

    throw "No VIDEO_TS folder found on $drive"
}

function Resolve-HandBrakeInputPath {
    param([Parameter(Mandatory)][string]$Path)

    if ($Path -match '^[A-Za-z]:$') {
        return [string]$Path
    }

    try {
        $resolved = (Resolve-Path -LiteralPath $Path -ErrorAction Stop).Path
    }
    catch {
        throw "Input path not found: $Path"
    }

    $videoTs = Join-Path $resolved 'VIDEO_TS'
    if (Test-Path -LiteralPath $videoTs) {
        return [string]$videoTs
    }

    return [string]$resolved
}

function Get-TrackLangFromDesc {
    # Parses a HandBrake track line tail like:
    #   "English (AC3) (2.0 ch) (iso639-2: eng), 48000Hz, 192000bps"
    #   "English (iso639-2: eng) (Bitmap)(VOBSUB)"
    # and returns a friendly label such as "English (eng)".
    param([Parameter(Mandatory)][string]$Desc)

    $name = ''
    if ($Desc -match '^\s*([^(,]+?)\s*(?:\(|,|$)') {
        $name = $matches[1].Trim()
    }

    $code = ''
    if ($Desc -match 'iso639-2:\s*([A-Za-z]{2,3})') {
        $code = $matches[1].ToLowerInvariant()
    }

    $label =
        if     ($name -and $code) { "$name ($code)" }
        elseif ($name)            { $name }
        elseif ($code)            { $code }
        else                      { 'unknown' }

    return @{ Name = $name; Code = $code; Label = $label }
}

function Invoke-HandBrakeScan {
    param([Parameter(Mandatory)][string]$InputPath)

    $resolvedInput = Resolve-HandBrakeInputPath -Path $InputPath

    Write-UiBlankLine
    Write-Host "  $($global:UI_GRN)Scanning titles with HandBrakeCLI...$($global:UI_R)"
    Write-Host ("  {0}Using{1}  {2}" -f $global:UI_DIM, $global:UI_R, $Script:HandBrakeCLI)
    Write-Host ("  {0}Input{1}  {2}" -f $global:UI_DIM, $global:UI_R, $resolvedInput)
    Write-UiBlankLine

    $scanOutput = & $Script:HandBrakeCLI `
        --input $resolvedInput `
        --title 0 `
        --scan `
        --min-duration $Script:MinTitleSeconds 2>&1

    $scanText = ($scanOutput | Out-String)

    $titles       = @()
    $currentTitle = $null
    $section      = $null   # 'audio' | 'subtitle' | $null

    foreach ($line in ($scanText -split "`r?`n")) {
        if ($line -match '^\+\s+title\s+(\d+):') {
            if ($null -ne $currentTitle) {
                $titles += [pscustomobject]$currentTitle
            }

            $currentTitle = @{
                Title        = [int]$matches[1]
                Duration     = ''
                Size         = ''
                AudioTracks  = 0
                AudioList    = @()
                SubtitleList = @()
                Raw          = @()
            }
            $section = $null
        }

        if ($null -ne $currentTitle) {
            $currentTitle.Raw += $line

            if ($line -match '^\s*\+\s+duration:\s+(.+)$') {
                $currentTitle.Duration = $matches[1].Trim()
            }
            elseif ($line -match '^\s*\+\s+size:\s+(.+)$') {
                $currentTitle.Size = $matches[1].Trim()
            }
            elseif ($line -match '^\s*\+\s+audio tracks:\s*$') {
                $section = 'audio'
            }
            elseif ($line -match '^\s*\+\s+subtitle tracks:\s*$') {
                $section = 'subtitle'
            }
            elseif ($line -match '^\s*\+\s+\w[\w ]*:\s*$') {
                # any other sub-header (chapters, etc.) ends track parsing
                $section = $null
            }
            elseif ($line -match '^\s*\+\s+(\d+),\s*(.+)$') {
                $trackNum  = [int]$matches[1]
                $trackDesc = $matches[2].Trim()
                $lang      = Get-TrackLangFromDesc -Desc $trackDesc

                if ($section -eq 'audio') {
                    $currentTitle.AudioTracks++
                    $currentTitle.AudioList += [pscustomobject]@{
                        Num   = $trackNum
                        Lang  = $lang.Label
                        Desc  = $trackDesc
                    }
                }
                elseif ($section -eq 'subtitle') {
                    $currentTitle.SubtitleList += [pscustomobject]@{
                        Num   = $trackNum
                        Lang  = $lang.Label
                        Desc  = $trackDesc
                    }
                }
            }
        }
    }

    if ($null -ne $currentTitle) {
        $titles += [pscustomobject]$currentTitle
    }

    if ($titles.Count -eq 0) {
        Write-CoreError "No titles detected."
        Write-Host $scanText
    }
    else {
        Write-Host "  $($global:UI_MAG)Detected titles:$($global:UI_R)"
        $titles | Select-Object Title, Duration, Size, AudioTracks | Format-Table -AutoSize | Out-Host
    }

    return @{
        Titles   = $titles
        ScanText = $scanText
    }
}

function Get-DurationSeconds {
    param([string]$Duration)

    if ($Duration -match '^\d{2}:\d{2}:\d{2}$') {
        return [int][TimeSpan]::Parse($Duration).TotalSeconds
    }

    return 0
}

function Get-MainTitle {
    param([Parameter(Mandatory)]$Titles)

    if (-not $Titles -or $Titles.Count -eq 0) {
        throw "No titles available."
    }

    return $Titles |
        Sort-Object { Get-DurationSeconds $_.Duration } -Descending |
        Select-Object -First 1
}

function Get-AutoTune {
    param([Parameter(Mandatory)][string]$MovieName)

    $name = $MovieName.ToLowerInvariant()

    if ($name -match 'anime|animation|animated|cartoon|pixar|disney|dreamworks|ghibli|miyazaki') {
        return @{ Tune = 'animation'; Note = 'detected animation keywords' }
    }

    if ($name -match '\b(19[0-7]\d|198[0-5])\b') {
        return @{ Tune = 'grain'; Note = 'older film/grain-friendly content' }
    }

    return @{ Tune = ''; Note = 'default x265 live-action profile' }
}

function Get-EncodeSettings {
    Write-UiBlankLine
    Write-Host "  $($global:UI_GRY)Press Enter to accept defaults shown in [brackets].$($global:UI_R)"
    Write-UiBlankLine

    $rfInput = Read-Host "RF quality [$($Script:DefaultRF)]  (18=larger, 22=smaller)"
    $rf = if ([string]::IsNullOrWhiteSpace($rfInput)) {
        $Script:DefaultRF
    }
    else {
        $v = [int]$rfInput
        if ($v -lt 16 -or $v -gt 28) {
            Write-Host "  $($global:UI_YLW)RF out of safe range — clamping to 18–22$($global:UI_R)"
            [Math]::Max(18, [Math]::Min(22, $v))
        }
        else { $v }
    }

    $presetInput = Read-Host "Preset [$($Script:DefaultPreset)]  (slow / slower / veryslow)"
    $preset = if ([string]::IsNullOrWhiteSpace($presetInput)) {
        $Script:DefaultPreset
    }
    elseif ($presetInput -in @('slow','slower','veryslow')) {
        $presetInput
    }
    else {
        Write-Host "  $($global:UI_YLW)Unknown preset — using default.$($global:UI_R)"
        $Script:DefaultPreset
    }

    $containerInput = Read-Host "Container [$($Script:DefaultContainer)]  (mkv / mp4)"
    $container = if ([string]::IsNullOrWhiteSpace($containerInput)) {
        $Script:DefaultContainer
    }
    elseif ($containerInput -in @('mkv','mp4')) {
        $containerInput
    }
    else {
        Write-Host "  $($global:UI_YLW)Unknown container — using default.$($global:UI_R)"
        $Script:DefaultContainer
    }

    return @{ RF = $rf; Preset = $preset; Container = $container }
}

function Encode-DvdTitle {
    param(
        [Parameter(Mandatory)][string]$InputPath,
        [Parameter(Mandatory)][int]$TitleNumber,
        [Parameter(Mandatory)][string]$MovieName,
        [Parameter(Mandatory)][string]$Tune,
        [ValidateSet('mkv','mp4')][string]$Container = 'mkv',
        [ValidateRange(16,28)][int]$RF = 20,
        [ValidateSet('slow','slower','veryslow')][string]$Preset = 'slower',
        [string]$AudioSelection    = 'all',   # 'all' | 'none' | '1,3'
        [string]$SubtitleSelection = 'all'    # 'all' | 'none' | '1,2'
    )

    $resolvedInput = Resolve-HandBrakeInputPath -Path $InputPath
    $safeName      = New-SafeName -Name $MovieName
    $outputFile    = Join-Path $Script:OutputRoot "$safeName.$Container"

    if (Test-Path -LiteralPath $outputFile) {
        Write-UiBlankLine
        Write-Host "  $($global:UI_YLW)Output file already exists:$($global:UI_R) $outputFile"
        $overwrite = Read-Host "Overwrite? (Y/N)"
        if ($overwrite -notmatch '^(Y|y)$') {
            $stamp      = Get-Date -Format 'yyyyMMdd_HHmmss'
            $outputFile = Join-Path $Script:OutputRoot "${safeName}_${stamp}.$Container"
            Write-Host "  $($global:UI_GRY)Writing to:$($global:UI_R) $outputFile"
        }
    }

    Write-UiBlankLine
    Write-Host "  $($global:UI_GRN)Encoding title $TitleNumber...$($global:UI_R)"
    Write-Host ("  {0}Input  {1} {2}" -f $global:UI_DIM, $global:UI_R, $resolvedInput)
    Write-Host ("  {0}Output {1} {2}" -f $global:UI_DIM, $global:UI_R, $outputFile)
    Write-Host ("  {0}Codec  {1} {2}" -f $global:UI_DIM, $global:UI_R, $Script:DefaultEncoder)
    Write-Host ("  {0}RF     {1} {2}" -f $global:UI_DIM, $global:UI_R, $RF)
    Write-Host ("  {0}Preset {1} {2}" -f $global:UI_DIM, $global:UI_R, $Preset)
    Write-Host ("  {0}Tune   {1} {2}" -f $global:UI_DIM, $global:UI_R, $(if ($Tune) { $Tune } else { '(none)' }))
    Write-Host ("  {0}Audio  {1} {2}" -f $global:UI_DIM, $global:UI_R, $(if ($AudioSelection -eq 'all') { 'all tracks' } elseif ($AudioSelection -eq 'none') { 'none' } else { "tracks $AudioSelection" }))
    Write-Host ("  {0}Subs   {1} {2}" -f $global:UI_DIM, $global:UI_R, $(if ($SubtitleSelection -eq 'all') { 'all tracks' } elseif ($SubtitleSelection -eq 'none') { 'none' } else { "tracks $SubtitleSelection" }))
    Write-Host ("  {0}Using  {1} {2}" -f $global:UI_DIM, $global:UI_R, $Script:HandBrakeCLI)
    Write-UiBlankLine

    $encodeArgs = @(
        '--input',          $resolvedInput,
        '--title',          $TitleNumber,
        '--output',         $outputFile,
        '--format',         "av_$Container",

        '--encoder',        $Script:DefaultEncoder,
        '--quality',        $RF,
        '--encoder-preset', $Preset,

        '--markers',
        '--cfr',
        '--crop-mode',      'auto',
        '--anamorphic',     'loose',
        '--modulus',        '2',
        '--comb-detect',
        '--decomb',

        '--aencoder',       'copy',
        '--audio-fallback', 'eac3'
    )

    # Audio selection: language tags carry through from the DVD either way.
    if ($AudioSelection -eq 'all') {
        $encodeArgs += '--all-audio'
    }
    elseif ($AudioSelection -ne 'none') {
        $encodeArgs += @('--audio', $AudioSelection)
    }
    # ('none' for audio is unusual but allowed — HandBrake will produce a video-only file.)

    # Subtitle selection: VOBSUB bitmaps carry into MKV with their languages.
    if ($SubtitleSelection -eq 'all') {
        $encodeArgs += '--all-subtitles'
    }
    elseif ($SubtitleSelection -eq 'none') {
        # no subtitle tracks
    }
    else {
        $encodeArgs += @('--subtitle', $SubtitleSelection)
    }

    if (-not [string]::IsNullOrWhiteSpace($Tune)) {
        $encodeArgs += @('--encoder-tune', $Tune)
    }

    if ($DryRun) {
        Write-Host "  $($global:UI_YLW)[DRY RUN] Would execute:$($global:UI_R)"
        Write-Host "  $Script:HandBrakeCLI $($encodeArgs -join ' ')"
        Write-UiBlankLine
        return
    }

    & $Script:HandBrakeCLI @encodeArgs

    if (-not (Test-Path -LiteralPath $outputFile)) {
        throw "Encode appears to have failed. Output file not found."
    }

    Write-UiBlankLine
    Write-Host "  $($global:UI_GRN)Encode complete:$($global:UI_R) $outputFile"

    Write-NfoStub -MovieName $MovieName -OutputFile $outputFile -Tune $Tune -RF $RF -Preset $Preset
}

function Write-NfoStub {
    param(
        [Parameter(Mandatory)][string]$MovieName,
        [Parameter(Mandatory)][string]$OutputFile,
        [string]$Tune   = '',
        [int]$RF        = 0,
        [string]$Preset = ''
    )

    $safeName = New-SafeName -Name $MovieName
    $nfoPath  = Join-Path $Script:NfoRoot "$safeName.nfo"
    $now      = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'

    $nfoContent = @"
Movie    : $MovieName
Encoded  : $now
Source   : DVD
Output   : $OutputFile
Encoder  : $($Script:DefaultEncoder)
RF       : $RF
Preset   : $Preset
Tune     : $(if ($Tune) { $Tune } else { '(none)' })
Script   : $ScriptName v$ScriptVersion
"@

    try {
        $nfoContent | Out-File -LiteralPath $nfoPath -Encoding utf8 -Force
        Write-Host "  $($global:UI_GRY)NFO written: $nfoPath$($global:UI_R)"
    }
    catch {
        Write-Host "  $($global:UI_YLW)Could not write NFO: $($_.Exception.Message)$($global:UI_R)"
    }
}

function Read-MovieNameWithYear {
    $movieName = Read-Host "Movie name"
    if ([string]::IsNullOrWhiteSpace($movieName)) {
        $movieName = "dvd_encode_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
    }

    $movieYear = Read-Host "Year (optional, 4 digits)"
    if (-not [string]::IsNullOrWhiteSpace($movieYear) -and $movieYear -match '^\d{4}$') {
        $movieName = "$movieName [$movieYear]"
    }

    return [string]$movieName
}

function Select-Tracks {
    # Shows the available tracks (with language) for one kind and returns a
    # HandBrake selection string: 'all' or a comma list like '1,3'. Empty/Enter = all.
    param(
        [Parameter(Mandatory)][string]$Kind,        # 'audio' | 'subtitle'
        [Parameter(Mandatory)]$Tracks               # array of {Num; Lang; Desc}
    )

    if (-not $Tracks -or $Tracks.Count -eq 0) {
        Write-Host "  $($global:UI_YLW)No $Kind tracks detected — including all available.$($global:UI_R)"
        return 'all'
    }

    Write-UiBlankLine
    Write-Host "  $($global:UI_MAG)$([System.Globalization.CultureInfo]::InvariantCulture.TextInfo.ToTitleCase($Kind)) tracks:$($global:UI_R)"
    foreach ($t in $Tracks) {
        Write-Host ("    {0}{1}{2}  {3}" -f $global:UI_DIM, $t.Num, $global:UI_R, $t.Lang)
    }

    $valid = @($Tracks | ForEach-Object { $_.Num })
    while ($true) {
        $choice = (Read-Host "  Include $Kind tracks (e.g. 1,3) [all]").Trim()
        if ([string]::IsNullOrWhiteSpace($choice) -or $choice -ieq 'all') {
            return 'all'
        }
        if ($choice -ieq 'none') {
            return 'none'
        }

        $picked = @()
        $ok = $true
        foreach ($p in ($choice -split '\s*,\s*')) {
            if ($p -match '^\d+$' -and ([int]$p -in $valid)) {
                $picked += [int]$p
            }
            else {
                Write-Host "  $($global:UI_YLW)'$p' is not a listed track number — try again.$($global:UI_R)"
                $ok = $false
                break
            }
        }
        if ($ok -and $picked.Count -gt 0) {
            return ($picked -join ',')
        }
    }
}

function Invoke-EncodeFlow {
    param(
        [Parameter(Mandatory)][string]$InputPath,
        [Parameter(Mandatory)][string]$MovieName
    )

    $scan = Invoke-HandBrakeScan -InputPath $InputPath

    # Guard against stray pipeline output: keep the hashtable if an array slips through.
    if ($scan -is [array]) { $scan = $scan | Where-Object { $_ -is [hashtable] } | Select-Object -Last 1 }

    if (-not $scan.Titles -or $scan.Titles.Count -eq 0) {
        throw "Could not find any titles to encode."
    }

    $mainTitle = Get-MainTitle -Titles $scan.Titles

    Write-UiBlankLine
    Write-Host "  $($global:UI_YLW)Suggested main title:$($global:UI_R) $($mainTitle.Title)  Duration: $($mainTitle.Duration)"

    $titleChoice = Read-Host "Title to encode [$($mainTitle.Title)]"
    $selectedTitle = if ([string]::IsNullOrWhiteSpace($titleChoice)) { $mainTitle.Title } else { [int]$titleChoice }

    $titleObj = $scan.Titles | Where-Object { $_.Title -eq $selectedTitle } | Select-Object -First 1

    $audioSel = Select-Tracks -Kind 'audio'    -Tracks $titleObj.AudioList
    $subSel   = Select-Tracks -Kind 'subtitle' -Tracks $titleObj.SubtitleList

    $tuneInfo = Get-AutoTune -MovieName $MovieName
    $tune     = $tuneInfo.Tune

    Write-Host "  $($global:UI_MAG)Auto-selected tune:$($global:UI_R) $(if ($tune) { $tune } else { '(none)' })  $($global:UI_GRY)($($tuneInfo.Note))$($global:UI_R)"

    $settings = Get-EncodeSettings

    Encode-DvdTitle `
        -InputPath         $InputPath `
        -TitleNumber       $selectedTitle `
        -MovieName         $MovieName `
        -Tune              $tune `
        -Container         $settings.Container `
        -RF                $settings.RF `
        -Preset            $settings.Preset `
        -AudioSelection    $audioSel `
        -SubtitleSelection $subSel
}

# ── Menu actions ──────────────────────────────────────────────
function Encode-DirectFromDvd {
    Write-UiBlankLine
    $drive = Read-Host "DVD drive letter [$Script:DefaultDrive]"
    if ([string]::IsNullOrWhiteSpace($drive)) { $drive = $Script:DefaultDrive }

    $movieName = Read-MovieNameWithYear

    try {
        [string]$sourceDrive = Get-DvdSourcePath -DriveLetter $drive
        Invoke-EncodeFlow -InputPath $sourceDrive -MovieName $movieName
    }
    catch {
        Write-UiBlankLine
        Write-CoreError $_.Exception.Message
    }

    Pause-Script
}

function Scan-DvdOnly {
    Write-UiBlankLine
    $drive = Read-Host "DVD drive letter [$Script:DefaultDrive]"
    if ([string]::IsNullOrWhiteSpace($drive)) { $drive = $Script:DefaultDrive }

    try {
        [string]$sourceDrive = Get-DvdSourcePath -DriveLetter $drive
        $null = Invoke-HandBrakeScan -InputPath $sourceDrive
    }
    catch {
        Write-UiBlankLine
        Write-CoreError $_.Exception.Message
    }

    Pause-Script
}

function Encode-From-ExistingFolder {
    Write-UiBlankLine
    $inputPath = Read-Host "Path to VIDEO_TS folder or parent folder"

    if (-not (Test-Path -LiteralPath $inputPath)) {
        Write-UiBlankLine
        Write-CoreError "Path not found."
        Pause-Script
        return
    }

    $movieName = Read-MovieNameWithYear

    try {
        Invoke-EncodeFlow -InputPath ([string]$inputPath) -MovieName $movieName
    }
    catch {
        Write-UiBlankLine
        Write-CoreError $_.Exception.Message
    }

    Pause-Script
}

function Show-Config {
    Write-UiBlankLine
    Write-UiRow "RootPath"     $Script:RootPath $global:UI_GRY
    Write-UiRow "OutputRoot"   $Script:OutputRoot $global:UI_GRY
    Write-UiRow "NfoRoot"      $Script:NfoRoot $global:UI_GRY
    Write-UiRow "DefaultDrive" $Script:DefaultDrive $global:UI_GRY
    Write-UiRow "Container"    $Script:DefaultContainer $global:UI_GRY
    Write-UiRow "Encoder"      $Script:DefaultEncoder $global:UI_GRY
    Write-UiRow "RF"           "$($Script:DefaultRF)" $global:UI_GRY
    Write-UiRow "Preset"       $Script:DefaultPreset $global:UI_GRY
    Write-UiRow "HandBrakeCLI" $Script:HandBrakeCLI $global:UI_GRY
    Write-UiRow "DryRun"       $(if ($DryRun) { 'Yes' } else { 'No' }) $global:UI_GRY
    Pause-Script
}

# ── Startup ───────────────────────────────────────────────────
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
        '1' { Encode-DirectFromDvd }
        '2' { Scan-DvdOnly }
        '3' { Encode-From-ExistingFolder }
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