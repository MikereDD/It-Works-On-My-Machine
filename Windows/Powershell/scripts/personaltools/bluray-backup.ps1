#--------------------------------------------
# file:     bluray-backup.ps1
# author:   Mike Redd
# version:  2.2
# created:  2026-04-11
# updated:  2026-05-23
# desc:     Blu-ray backup + decrypt wrapper
#           for MakeMKV
#           ToolMenu-friendly version
#           Uses ui.ps1 and core.ps1 helpers
#           Outputs to G:\Rip\bluray
#           and writes track metadata JSON/TXT
#           for BREncoder
# changes:  v2.2 - display saved JSON filename prominently after backup so the
#                  name is visible when launching BREncoder next
#--------------------------------------------

param()

$ErrorActionPreference = 'Stop'

# ── Load shared UI/core ──────────────────────────────────────
$uiPath   = "$env:USERPROFILE\PS\profile.d\ui.ps1"
$corePath = "$env:USERPROFILE\PS\profile.d\core.ps1"

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

if (Test-Path $corePath) {
    try {
        . $corePath
    }
    catch {
        Write-Host "Failed to load core.ps1: $($_.Exception.Message)"
        if (Get-Command Pause-UiReturn -ErrorAction SilentlyContinue) {
            Pause-UiReturn "Press Enter to return..."
        }
        else {
            Read-Host "Press Enter to return..." | Out-Null
        }
        return
    }
}
else {
    Write-Host "Missing core.ps1: $corePath"
    if (Get-Command Pause-UiReturn -ErrorAction SilentlyContinue) {
        Pause-UiReturn "Press Enter to return..."
    }
    else {
        Read-Host "Press Enter to return..." | Out-Null
    }
    return
}

$ScriptName    = "Blu-ray Backup"
$ScriptVersion = "2.2"
$ScriptAuthor  = "Mike Redd"

# ── Config ───────────────────────────────────────────────────
$Script:RootPath   = "G:\Rip"
$Script:OutputRoot = Join-Path $Script:RootPath "bluray"
$Script:MetaRoot   = Join-Path $Script:RootPath "meta"
$Script:Drive      = "disc:0"

function Ensure-Dirs {
    foreach ($p in @($Script:RootPath, $Script:OutputRoot, $Script:MetaRoot)) {
        if (-not (Test-Path -LiteralPath $p)) {
            New-Item -ItemType Directory -Path $p -Force | Out-Null
        }
    }
}

function Get-SafeName {
    param(
        [Parameter(Mandatory)]
        [string]$Name
    )

    $safe = $Name -replace '[\\\/:\*\?"<>\|]', '_'
    $safe = $safe.Trim()

    if ([string]::IsNullOrWhiteSpace($safe)) {
        $safe = "bluray_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
    }

    return $safe
}

function Get-MakeMKVPath {
    $candidates = @(
        "C:\Program Files\MakeMKV\makemkvcon.exe",
        "C:\Program Files (x86)\MakeMKV\makemkvcon.exe",
        "C:\Program Files\MakeMKV\makemkvcon64.exe",
        "C:\Program Files (x86)\MakeMKV\makemkvcon64.exe"
    )

    foreach ($path in $candidates) {
        if (Test-Path -LiteralPath $path) {
            return $path
        }
    }

    $cmd = Get-Command "makemkvcon.exe" -ErrorAction SilentlyContinue
    if ($cmd -and $cmd.Source) {
        return $cmd.Source
    }

    $cmd64 = Get-Command "makemkvcon64.exe" -ErrorAction SilentlyContinue
    if ($cmd64 -and $cmd64.Source) {
        return $cmd64.Source
    }

    return $null
}

function Pause-Script {
    if (Get-Command Pause-UiReturn -ErrorAction SilentlyContinue) {
        Pause-UiReturn "Press Enter to return..."
    }
    else {
        Read-Host "Press Enter to return..." | Out-Null
    }
}

function Read-Choice {
    param([string]$Prompt)

    if (Get-Command Read-UiChoice -ErrorAction SilentlyContinue) {
        return (Read-UiChoice $Prompt)
    }

    return (Read-Host $Prompt)
}

function Show-Header {
    if (Get-Command Clear-UiScreen -ErrorAction SilentlyContinue) {
        Clear-UiScreen
    }
    else {
        Clear-Host
    }

    if (
        (Get-Command Get-UiBoxWidth -ErrorAction SilentlyContinue) -and
        (Get-Command Write-UiHeader -ErrorAction SilentlyContinue) -and
        (Get-Command Write-UiRow -ErrorAction SilentlyContinue) -and
        (Get-Command Write-UiBlankLine -ErrorAction SilentlyContinue)
    ) {
        $BoxWidth = Get-UiBoxWidth -MaxWidth 58 -MinWidth 42
        Write-UiHeader -Title $ScriptName -Subtitle "v$ScriptVersion  by $ScriptAuthor" -Width $BoxWidth
        Write-UiRow "Drive"  $Script:Drive      -ValueColor $global:UI_GRY
        Write-UiRow "Output" $Script:OutputRoot -ValueColor $global:UI_GRY
        Write-UiRow "Meta"   $Script:MetaRoot   -ValueColor $global:UI_GRY
        Write-UiBlankLine
        return
    }

    Write-Host ""
    Write-Host "============================================================"
    Write-Host " $ScriptName v$ScriptVersion"
    Write-Host " by $ScriptAuthor"
    Write-Host "============================================================"
    Write-Host " Drive : $Script:Drive"
    Write-Host " Output: $Script:OutputRoot"
    Write-Host " Meta  : $Script:MetaRoot"
    Write-Host ""
}

function Show-SectionTitle {
    param(
        [string]$Title,
        [string]$Color = $global:UI_CYN
    )

    if (Get-Command Write-UiSection -ErrorAction SilentlyContinue) {
        Write-UiSection -Title $Title -Color $Color
    }
    else {
        Write-Host "---- $Title ----"
    }
}

function Blank-Line {
    if (Get-Command Write-UiBlankLine -ErrorAction SilentlyContinue) {
        Write-UiBlankLine
    }
    else {
        Write-Host ""
    }
}

function Show-Menu {
    Show-Header
    Show-SectionTitle "Options" $global:UI_CYN
    Write-Host "  1) Start Blu-ray backup"
    Write-Host "  Q) Return to ToolMenu"
    Blank-Line
}

function Get-StreamPath {
    param([Parameter(Mandatory)][string]$RootPath)

    $dirs = Get-ChildItem -LiteralPath $RootPath -Recurse -Directory -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -ieq "STREAM" }

    foreach ($d in $dirs) {
        $m = Get-ChildItem -LiteralPath $d.FullName -Filter *.m2ts -File -ErrorAction SilentlyContinue
        if ($m -and $m.Count -gt 0) {
            return $d.FullName
        }
    }

    return $null
}

function Get-LargestM2TS {
    param([Parameter(Mandatory)][string]$Path)

    Get-ChildItem -LiteralPath $Path -Filter *.m2ts -File -ErrorAction SilentlyContinue |
    Sort-Object Length -Descending |
    Select-Object -First 1
}

function Get-MakeMKVInfoLines {
    param(
        [Parameter(Mandatory)][string]$Exe,
        [string]$Source = $Script:Drive
    )

    $lines = & $Exe -r info $Source 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "makemkvcon info failed with exit code $LASTEXITCODE"
    }

    return $lines
}

function ConvertFrom-MakeMKVInfo {
    param([Parameter(Mandatory)][string[]]$Lines)

    $titles = @{}

    foreach ($line in $Lines) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }

        if ($line -match '^TINFO:(\d+),(\d+),\d+,"(.*)"$') {
            $titleId = [int]$matches[1]
            $fieldId = [int]$matches[2]
            $value   = $matches[3]

            if (-not $titles.ContainsKey($titleId)) {
                $titles[$titleId] = [ordered]@{
                    TitleId       = $titleId
                    Name          = $null
                    Chapters      = $null
                    Duration      = $null
                    SizeText      = $null
                    SizeBytes     = 0
                    SourceFile    = $null
                    SegmentMap    = $null
                    OutputName    = $null
                    LanguageCode  = $null
                    LanguageName  = $null
                    Summary       = $null
                    Tracks        = @{}
                }
            }

            switch ($fieldId) {
                2  { $titles[$titleId].Name         = $value }
                8  { $titles[$titleId].Chapters     = $value }
                9  { $titles[$titleId].Duration     = $value }
                10 { $titles[$titleId].SizeText     = $value }
                11 {
                    if ($value -match '^\d+$') {
                        $titles[$titleId].SizeBytes = [int64]$value
                    }
                }
                16 { $titles[$titleId].SourceFile   = $value }
                26 { $titles[$titleId].SegmentMap   = $value }
                27 { $titles[$titleId].OutputName   = $value }
                28 { $titles[$titleId].LanguageCode = $value }
                29 { $titles[$titleId].LanguageName = $value }
                30 { $titles[$titleId].Summary      = $value }
            }

            continue
        }

        if ($line -match '^SINFO:(\d+),(\d+),(\d+),\d+,"(.*)"$') {
            $titleId = [int]$matches[1]
            $trackId = [int]$matches[2]
            $fieldId = [int]$matches[3]
            $value   = $matches[4]

            if (-not $titles.ContainsKey($titleId)) {
                $titles[$titleId] = [ordered]@{
                    TitleId       = $titleId
                    Name          = $null
                    Chapters      = $null
                    Duration      = $null
                    SizeText      = $null
                    SizeBytes     = 0
                    SourceFile    = $null
                    SegmentMap    = $null
                    OutputName    = $null
                    LanguageCode  = $null
                    LanguageName  = $null
                    Summary       = $null
                    Tracks        = @{}
                }
            }

            if (-not $titles[$titleId].Tracks.ContainsKey($trackId)) {
                $titles[$titleId].Tracks[$trackId] = [ordered]@{
                    TrackId       = $trackId
                    Type          = $null
                    LanguageCode  = $null
                    LanguageName  = $null
                    CodecId       = $null
                    CodecShort    = $null
                    CodecLong     = $null
                    ChannelsText  = $null
                    Description   = $null
                    Default       = $false
                    Forced        = $false
                }
            }

            $track = $titles[$titleId].Tracks[$trackId]

            switch ($fieldId) {
                1  { $track.Type         = $value }
                2  { $track.ChannelsText = $value }
                3  { $track.LanguageCode = $value }
                4  { $track.LanguageName = $value }
                5  { $track.CodecId      = $value }
                6  { $track.CodecShort   = $value }
                7  { $track.CodecLong    = $value }
                30 {
                    $track.Description = $value
                    if ($value -match '(?i)forced only') {
                        $track.Forced = $true
                    }
                }
                38 {
                    if ($value -match 'd') {
                        $track.Default = $true
                    }
                }
                39 {
                    if ($value -match 'Default') {
                        $track.Default = $true
                    }
                }
            }

            continue
        }
    }

    $result = foreach ($titleId in ($titles.Keys | Sort-Object)) {
        $title = $titles[$titleId]
        $trackList = @($title.Tracks.Values | Sort-Object TrackId)

        [pscustomobject]@{
            TitleId        = $title.TitleId
            Name           = $title.Name
            Chapters       = $title.Chapters
            Duration       = $title.Duration
            SizeText       = $title.SizeText
            SizeBytes      = $title.SizeBytes
            SourceFile     = $title.SourceFile
            SegmentMap     = $title.SegmentMap
            OutputName     = $title.OutputName
            LanguageCode   = $title.LanguageCode
            LanguageName   = $title.LanguageName
            Summary        = $title.Summary
            Tracks         = $trackList
            VideoTracks    = @($trackList | Where-Object { $_.Type -eq 'Video' })
            AudioTracks    = @($trackList | Where-Object { $_.Type -eq 'Audio' })
            SubtitleTracks = @($trackList | Where-Object { $_.Type -eq 'Subtitles' })
        }
    }

    return @($result)
}

function Get-MainTitleFromInfo {
    param([Parameter(Mandatory)][object[]]$Titles)

    return $Titles |
        Sort-Object @{ Expression = { $_.SizeBytes }; Descending = $true }, `
                    @{ Expression = { $_.Duration  }; Descending = $true } |
        Select-Object -First 1
}

# Common language quick-pick table — shown when a track needs a language assigned.
# Key = number shown to user, Value = [code, display name]
$Script:QuickLangs = [ordered]@{
    '1'  = @('eng', 'English')
    '2'  = @('spa', 'Spanish')
    '3'  = @('fre', 'French')
    '4'  = @('ger', 'German')
    '5'  = @('ita', 'Italian')
    '6'  = @('por', 'Portuguese')
    '7'  = @('jpn', 'Japanese')
    '8'  = @('chi', 'Chinese')
    '9'  = @('kor', 'Korean')
    '10' = @('ara', 'Arabic')
    '11' = @('rus', 'Russian')
    '12' = @('dut', 'Dutch')
    '13' = @('hin', 'Hindi')
}

function Show-LanguagePicker {
    <#
    .SYNOPSIS
        Displays a numbered language quick-pick and returns a 3-letter ISO 639-2
        code. The user can pick a number or type a code directly. Returns 'und'
        if they skip.
    #>
    param(
        [Parameter(Mandatory)][string]$TrackLabel
    )

    Blank-Line
    Write-Host "  Track: $TrackLabel"
    Write-Host "  Language is missing or unknown. Pick a number or type a 3-letter code:"
    Blank-Line

    foreach ($key in $Script:QuickLangs.Keys) {
        $entry = $Script:QuickLangs[$key]
        Write-Host ("    {0,2})  {1,-12}  {2}" -f $key, $entry[0], $entry[1])
    }

    Write-Host "     S)  Skip (leave as 'und')"
    Blank-Line

    $input = (Read-Choice "Language [S]:")
    if ([string]::IsNullOrWhiteSpace($input)) { return 'und' }

    $input = $input.Trim()

    if ($input -match '^[Ss]$') { return 'und' }

    # Number pick
    if ($Script:QuickLangs.Contains($input)) {
        return $Script:QuickLangs[$input][0]
    }

    # Raw 3-letter code typed directly
    if ($input -match '^[a-zA-Z]{3}$') {
        return $input.ToLowerInvariant()
    }

    # 2-letter fallback — map to 3-letter
    $twoToThree = @{
        'en'='eng'; 'es'='spa'; 'fr'='fre'; 'de'='ger'; 'it'='ita'
        'pt'='por'; 'ja'='jpn'; 'zh'='chi'; 'ko'='kor'; 'ar'='ara'
        'ru'='rus'; 'nl'='dut'; 'hi'='hin'; 'sv'='swe'; 'no'='nor'
        'da'='dan'; 'fi'='fin'; 'pl'='pol'; 'cs'='cze'; 'hu'='hun'
    }
    if ($twoToThree.ContainsKey($input.ToLowerInvariant())) {
        return $twoToThree[$input.ToLowerInvariant()]
    }

    Write-Host "  Unrecognised input '$input' — leaving as 'und'."
    return 'und'
}

function Resolve-TrackLanguages {
    <#
    .SYNOPSIS
        Walks all audio and subtitle tracks in the parsed MakeMKV title object.
        For any track whose LanguageCode is null, empty, or 'und', prompts the
        user to assign a language before the JSON is saved.

        Mutates the track objects in-place so Save-TrackMeta picks up the values.
    #>
    param([Parameter(Mandatory)][object]$Title)

    $audioTracks    = @($Title.AudioTracks)
    $subtitleTracks = @($Title.SubtitleTracks)

    $needsInput = @(
        $audioTracks    | Where-Object { [string]::IsNullOrWhiteSpace($_.LanguageCode) -or $_.LanguageCode -eq 'und' }
        $subtitleTracks | Where-Object { [string]::IsNullOrWhiteSpace($_.LanguageCode) -or $_.LanguageCode -eq 'und' }
    )

    if ($needsInput.Count -eq 0) {
        # All tracks already have language codes from MakeMKV — nothing to do.
        Blank-Line
        Write-Host "  All tracks have language codes from MakeMKV."
        return
    }

    Blank-Line
    Show-SectionTitle "Language Assignment" $global:UI_YLW
    Write-Host "  $($needsInput.Count) track(s) have no language. Assign them now so BREncoder"
    Write-Host "  can write correct language tags to the encoded MKV."

    foreach ($track in $audioTracks) {
        if (-not [string]::IsNullOrWhiteSpace($track.LanguageCode) -and $track.LanguageCode -ne 'und') { continue }

        $codec = if ($track.CodecShort) { $track.CodecShort } elseif ($track.CodecLong) { $track.CodecLong } else { 'audio' }
        $ch    = if ($track.ChannelsText) { " $($track.ChannelsText)" } else { '' }
        $label = "Audio track $($track.TrackId) — $codec$ch"

        $code = Show-LanguagePicker -TrackLabel $label
        $track.LanguageCode = $code
        $track.LanguageName = if ($code -ne 'und') {
            ($Script:QuickLangs.Values | Where-Object { $_[0] -eq $code } | Select-Object -First 1)?[1] ?? $code
        } else { 'Undetermined' }

        Write-Host "  → Set to: $($track.LanguageCode)"
    }

    foreach ($track in $subtitleTracks) {
        if (-not [string]::IsNullOrWhiteSpace($track.LanguageCode) -and $track.LanguageCode -ne 'und') { continue }

        $forced = if ($track.Forced) { ' [forced]' } else { '' }
        $label  = "Subtitle track $($track.TrackId)$forced"

        $code = Show-LanguagePicker -TrackLabel $label
        $track.LanguageCode = $code
        $track.LanguageName = if ($code -ne 'und') {
            ($Script:QuickLangs.Values | Where-Object { $_[0] -eq $code } | Select-Object -First 1)?[1] ?? $code
        } else { 'Undetermined' }

        Write-Host "  → Set to: $($track.LanguageCode)"
    }

    Blank-Line
    Write-Host "  Language assignment complete."
}

function New-BRTrackMetadataSchema {
    param([Parameter(Mandatory)][object]$Meta)

    $title = $Meta.Title

    return [pscustomobject]@{
        SchemaVersion     = 'BRTrackMeta/1.0'
        CreatedAt         = (Get-Date).ToString('s')
        CreatedBy         = ('bluray-backup.ps1 v' + $ScriptVersion)
        MovieName         = $Meta.MovieName
        LargestM2TS       = $Meta.LargestM2TS
        LargestPath       = $Meta.LargestPath
        SourceFingerprint = [pscustomobject]@{
            FileName   = $Meta.LargestM2TS
            FullPath   = $Meta.LargestPath
            TitleId    = $title.TitleId
            TitleName  = $title.Name
            Duration   = $title.Duration
            SizeText   = $title.SizeText
            SizeBytes  = $title.SizeBytes
            Playlist   = $title.SourceFile
            SegmentMap = $title.SegmentMap
            OutputName = $title.OutputName
        }
        MainTitle         = $title
        # Backward compatibility for older BREncoder versions.
        Title             = $title
    }
}

function Save-TrackMeta {
    param(
        [Parameter(Mandatory)][object]$Meta,
        [Parameter(Mandatory)][string]$BasePath
    )

    $Meta = New-BRTrackMetadataSchema -Meta $Meta

    $jsonPath = "$BasePath.json"
    $txtPath  = "$BasePath.tracks.txt"

    $jsonText = $Meta | ConvertTo-Json -Depth 16
    $jsonText | Set-Content -LiteralPath $jsonPath -Encoding UTF8

    # Also write alias JSON files that BREncoder can find when the source
    # file is named like 00004.m2ts instead of the movie name.
    $aliasNames = @()
    if ($Meta.LargestM2TS) { $aliasNames += [System.IO.Path]::GetFileNameWithoutExtension([string]$Meta.LargestM2TS) }
    if ($Meta.Title -and $Meta.Title.SourceFile) { $aliasNames += [System.IO.Path]::GetFileNameWithoutExtension([string]$Meta.Title.SourceFile) }
    if ($Meta.Title -and $Meta.Title.OutputName) { $aliasNames += [System.IO.Path]::GetFileNameWithoutExtension([string]$Meta.Title.OutputName) }

    foreach ($alias in ($aliasNames | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)) {
        # Skip generic stream aliases like 00004.json because those collide between discs.
        if ($alias -match '^\d{5}$') { continue }

        $aliasSafe = Get-SafeName -Name $alias
        $aliasPath = Join-Path ([System.IO.Path]::GetDirectoryName($BasePath)) "$aliasSafe.json"
        if ($aliasPath -ne $jsonPath) {
            $jsonText | Set-Content -LiteralPath $aliasPath -Encoding UTF8
        }
    }

    $out = @()
    $out += "Schema     : $($Meta.SchemaVersion)"
    $out += "Movie      : $($Meta.MovieName)"
    $out += "LargestM2TS: $($Meta.LargestM2TS)"
    $out += "TitleId    : $($Meta.Title.TitleId)"
    $out += "TitleName  : $($Meta.Title.Name)"
    $out += "SourceFile : $($Meta.Title.SourceFile)"
    $out += "Duration   : $($Meta.Title.Duration)"
    $out += "Size       : $($Meta.Title.SizeText)"
    $out += "Fingerprint: title=$($Meta.SourceFingerprint.TitleId) playlist=$($Meta.SourceFingerprint.Playlist) bytes=$($Meta.SourceFingerprint.SizeBytes)"
    $out += ""

    if ($Meta.Title.AudioTracks.Count -gt 0) {
        $out += "[Audio]"
        foreach ($a in $Meta.Title.AudioTracks) {
            $flags = @()
            if ($a.Default) { $flags += "default" }
            $flagText = if ($flags.Count -gt 0) { " [" + ($flags -join ", ") + "]" } else { "" }
            $langDisplay = if ($a.LanguageName) { "$($a.LanguageCode) / $($a.LanguageName)" } else { $a.LanguageCode }
            $out += ("a{0}: {1} | {2}{3}" -f $a.TrackId, $langDisplay, $a.Description, $flagText)
        }
        $out += ""
    }

    if ($Meta.Title.SubtitleTracks.Count -gt 0) {
        $out += "[Subtitles]"
        foreach ($s in $Meta.Title.SubtitleTracks) {
            $flags = @()
            if ($s.Forced)  { $flags += "forced" }
            if ($s.Default) { $flags += "default" }
            $flagText = if ($flags.Count -gt 0) { " [" + ($flags -join ", ") + "]" } else { "" }
            $langDisplay = if ($s.LanguageName) { "$($s.LanguageCode) / $($s.LanguageName)" } else { $s.LanguageCode }
            $out += ("s{0}: {1} | {2}{3}" -f $s.TrackId, $langDisplay, $s.Description, $flagText)
        }
        $out += ""
    }

    Set-Content -LiteralPath $txtPath -Value $out -Encoding UTF8
}

function Start-Backup {
    Show-Header
    Show-SectionTitle "Backup Setup" $global:UI_CYN

    $makeMKV = Get-MakeMKVPath
    if (-not $makeMKV) {
        Write-Host "  MakeMKV CLI was not found."
        Blank-Line
        Write-Host "  Checked common locations and PATH for:"
        Write-Host "  makemkvcon.exe / makemkvcon64.exe"
        Pause-Script
        return
    }

    if (Get-Command Write-UiRow -ErrorAction SilentlyContinue) {
        Write-UiRow "MakeMKV" $makeMKV -ValueColor $global:UI_GRY
        Blank-Line
    }
    else {
        Write-Host "  MakeMKV: $makeMKV"
        Blank-Line
    }

    $name = Read-Choice "Movie name (Q to cancel):"
    if ($null -eq $name) { return }

    $name = $name.Trim()
    if ($name -match '^[Qq]$') { return }

    if ([string]::IsNullOrWhiteSpace($name)) {
        $name = "bluray_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
    }

    $year = Read-Choice "Year (optional, Q to cancel):"
    if ($null -eq $year) { return }

    $year = $year.Trim()
    if ($year -match '^[Qq]$') { return }

    if ($year -match '^\d{4}$') {
        $name = "$name [$year]"
    }

    $safeName = Get-SafeName -Name $name
    $dest     = Join-Path $Script:OutputRoot $safeName
    $metaBase = Join-Path $Script:MetaRoot   $safeName

    Show-Header
    Show-SectionTitle "Backup Starting" $global:UI_YLW

    if (Get-Command Write-UiRow -ErrorAction SilentlyContinue) {
        Write-UiRow "Source" $Script:Drive -ValueColor $global:UI_GRY
        Write-UiRow "Dest"   $dest         -ValueColor $global:UI_GRY
        Blank-Line
    }
    else {
        Write-Host "  Source: $Script:Drive"
        Write-Host "  Dest  : $dest"
        Blank-Line
    }

    try {
        & $makeMKV `
            backup `
            --decrypt `
            --cache=512 `
            -r `
            --progress=-same `
            $Script:Drive `
            $dest

        $exitCode = $LASTEXITCODE

        Blank-Line
        if ($exitCode -eq 0) {
            Show-SectionTitle "Backup Complete" $global:UI_GRN
            if (Get-Command Write-UiRow -ErrorAction SilentlyContinue) {
                Write-UiRow "Saved To" $dest -ValueColor $global:UI_GRY
            }
            else {
                Write-Host "  Saved To: $dest"
            }
        }
        else {
            Write-Host "  MakeMKV failed with exit code $exitCode"
            Pause-Script
            return
        }

        $stream = Get-StreamPath -RootPath $dest
        $largest = $null

        if ($stream) {
            $largest = Get-LargestM2TS -Path $stream
        }

        $infoLines = Get-MakeMKVInfoLines -Exe $makeMKV -Source $Script:Drive
        $titles    = ConvertFrom-MakeMKVInfo -Lines $infoLines
        $mainTitle = Get-MainTitleFromInfo -Titles $titles

        if (-not $mainTitle) {
            Write-CoreError "Could not determine main title metadata."
            Pause-Script
            return
        }

        # Prompt for any tracks MakeMKV returned with no language code.
        # This ensures the JSON BREncoder reads always has real language tags.
        Resolve-TrackLanguages -Title $mainTitle

        $meta = [pscustomobject]@{
            MovieName   = $name
            LargestM2TS = $(if ($largest) { $largest.Name } else { "" })
            LargestPath = $(if ($largest) { $largest.FullName } else { "" })
            Title       = $mainTitle
        }

        Save-TrackMeta -Meta $meta -BasePath $metaBase

        Blank-Line
        Show-SectionTitle "Track Metadata Saved" $global:UI_MAG

        # Show the exact JSON key name BREncoder will match against.
        # When prompted for a movie name in BREncoder, use this name exactly.
        $jsonFile = [System.IO.Path]::GetFileName("$metaBase.json")
        $jsonKey  = [System.IO.Path]::GetFileNameWithoutExtension($jsonFile)
        Write-Host "  JSON : $metaBase.json"
        Write-Host "  TXT  : $metaBase.tracks.txt"
        Blank-Line
        Write-Host "  ┌─ Use this name in BREncoder ──────────────────────────"
        Write-Host "  │  $jsonKey"
        Write-Host "  └───────────────────────────────────────────────────────"

        if ($largest) {
            Blank-Line
            Write-Host "  Largest .m2ts : $($largest.Name)"
        }

        Write-Host "  Metadata title: $($mainTitle.TitleId) -> $($mainTitle.SourceFile)"
    }
    catch {
        Blank-Line
        Write-Host "  $($_.Exception.Message)"
    }

    Pause-Script
}

function Main {
    Ensure-Dirs

    while ($true) {
        Show-Menu
        $choice = Read-Choice "Choice:"

        if ($null -eq $choice) {
            continue
        }

        switch ($choice.Trim().ToUpper()) {
            '1' { Start-Backup }
            'Q' { return }
            default {
                Write-Host "  Invalid selection."
                Start-Sleep -Seconds 1
            }
        }
    }
}

try {
    Main
}
catch {
    Blank-Line
    Write-Host "  $($_.Exception.Message)"
    Pause-Script
}