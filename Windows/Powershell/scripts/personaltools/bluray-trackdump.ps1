#--------------------------------------------
# file:     bluray-trackdump.ps1
# author:   Mike Redd
# version:  1.4
# created:  2026-04-18
# updated:  2026-05-23
# desc:     ToolMenu-friendly Blu-ray track
#           metadata dumper.
#           Creates a temp decrypted backup,
#           finds the largest .m2ts, reads
#           MakeMKV title/track metadata,
#           saves shared-schema .json and .tracks.txt,
#           then removes temp backup.
# changes:  v1.4 - added Resolve-TrackLanguages: prompts for manual language
#                  entry on any track MakeMKV returns as null or 'und'
#                  added Show-LanguagePicker with 13-language quick-pick menu
#                  improved Save-TrackMeta TXT to show code + name
#                  display BREncoder JSON key name prominently after save
#--------------------------------------------

param()

$ErrorActionPreference = 'Stop'

# ── Load UI ─────────────────────────────────
$uiPath = "$env:USERPROFILE\PS\profile.d\ui.ps1"
if (Test-Path -LiteralPath $uiPath) {
    . $uiPath
}
else {
    Write-Host "Missing ui.ps1"
    return
}

$corePath = "$env:USERPROFILE\PS\profile.d\core.ps1"
if (Test-Path -LiteralPath $corePath) {
    . $corePath
}
else {
    Write-Host "Missing core.ps1"
    return
}

$ScriptName    = "Blu-ray Track Dump"
$ScriptVersion = "1.4"
$ScriptAuthor  = "Mike Redd"

# ── Config ─────────────────────────────────
$Script:RootPath   = "G:\Rip"
$Script:BackupRoot = Join-Path $Script:RootPath "bluray"
$Script:MetaRoot   = Join-Path $Script:RootPath "meta"
$Script:Drive      = "disc:0"

# ── Header ─────────────────────────────────
function Show-Header {
    Clear-UiScreen
    Write-UiHeader -Title $ScriptName -Subtitle "v$ScriptVersion by $ScriptAuthor"
    Write-UiRow "Drive"  $Script:Drive
    Write-UiRow "Output" $Script:MetaRoot -ValueColor $global:UI_GRY
    Write-UiBlankLine
}

function Pause-Script {
    Pause-UiReturn "Press Enter to return..."
}

function Ensure-Dirs {
    foreach ($p in @($Script:RootPath, $Script:BackupRoot, $Script:MetaRoot)) {
        if (-not (Test-Path -LiteralPath $p)) {
            New-Item -ItemType Directory -Path $p -Force | Out-Null
        }
    }
}

function Get-SafeName {
    param([string]$Name)

    $safe = ($Name -replace '[\\\/:\*\?"<>\|]', '_').Trim()
    if ([string]::IsNullOrWhiteSpace($safe)) {
        $safe = "bluray_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
    }

    return $safe
}

function Get-MakeMKVPath {
    $paths = @(
        "C:\Program Files\MakeMKV\makemkvcon.exe",
        "C:\Program Files (x86)\MakeMKV\makemkvcon.exe",
        "C:\Program Files\MakeMKV\makemkvcon64.exe",
        "C:\Program Files (x86)\MakeMKV\makemkvcon64.exe"
    )

    foreach ($p in $paths) {
        if (Test-Path -LiteralPath $p) {
            return $p
        }
    }

    $cmd = Get-Command "makemkvcon.exe" -ErrorAction SilentlyContinue
    if ($cmd -and $cmd.Source) { return $cmd.Source }

    $cmd64 = Get-Command "makemkvcon64.exe" -ErrorAction SilentlyContinue
    if ($cmd64 -and $cmd64.Source) { return $cmd64.Source }

    return $null
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

# ── MakeMKV Progress ───────────────────────
function Show-MakeMKVProgress {
    param($exe, $drive, $dest)

    $args = "backup --decrypt --cache=512 -r --progress=-same $drive `"$dest`""

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $exe
    $psi.Arguments = $args
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError  = $true
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow  = $true

    $p = New-Object System.Diagnostics.Process
    $p.StartInfo = $psi
    $null = $p.Start()

    $percent = 0

    while (-not $p.HasExited) {
        while (-not $p.StandardOutput.EndOfStream) {
            $line = $p.StandardOutput.ReadLine()

            if ($line -match 'PRGV:(\d+),(\d+),(\d+)') {
                $cur = [double]$matches[2]
                $tot = [double]$matches[3]
                if ($tot -gt 0) {
                    $percent = [math]::Floor(($cur / $tot) * 100)
                }
            }
        }

        $filled = [math]::Floor($percent / 4)
        if ($filled -lt 0) { $filled = 0 }
        if ($filled -gt 25) { $filled = 25 }

        $bar = ('#' * $filled).PadRight(25, '-')
        Write-Host "`r [$bar] $percent%" -NoNewline
        Start-Sleep -Milliseconds 200
    }

    Write-Host ""
    $p.WaitForExit()
    return $p.ExitCode
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

# Common language quick-pick — shown when a track has no language code.
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
    param([Parameter(Mandatory)][string]$TrackLabel)

    Write-UiBlankLine
    Write-Host "  Track: $TrackLabel"
    Write-Host "  Language is missing or unknown. Pick a number or type a 3-letter code:"
    Write-UiBlankLine

    foreach ($key in $Script:QuickLangs.Keys) {
        $entry = $Script:QuickLangs[$key]
        Write-Host ("    {0,2})  {1,-12}  {2}" -f $key, $entry[0], $entry[1])
    }

    Write-Host "     S)  Skip (leave as 'und')"
    Write-UiBlankLine

    $input = (Read-Host "Language [S]").Trim()
    if ([string]::IsNullOrWhiteSpace($input) -or $input -match '^[Ss]$') { return 'und' }

    if ($Script:QuickLangs.Contains($input)) { return $Script:QuickLangs[$input][0] }

    if ($input -match '^[a-zA-Z]{3}$') { return $input.ToLowerInvariant() }

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
    param([Parameter(Mandatory)][object]$Title)

    $audioTracks    = @($Title.AudioTracks)
    $subtitleTracks = @($Title.SubtitleTracks)

    $needsInput = @(
        $audioTracks    | Where-Object { [string]::IsNullOrWhiteSpace($_.LanguageCode) -or $_.LanguageCode -eq 'und' }
        $subtitleTracks | Where-Object { [string]::IsNullOrWhiteSpace($_.LanguageCode) -or $_.LanguageCode -eq 'und' }
    )

    if ($needsInput.Count -eq 0) {
        Write-UiBlankLine
        Write-Host "  All tracks have language codes from MakeMKV."
        return
    }

    Write-UiBlankLine
    Write-UiSection -Title "Language Assignment"
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

    Write-UiBlankLine
    Write-Host "  Language assignment complete."
}

function New-BRTrackMetadataSchema {
    param([Parameter(Mandatory)][object]$Meta)

    $title = $Meta.Title

    return [pscustomobject]@{
        SchemaVersion     = 'BRTrackMeta/1.0'
        CreatedAt         = (Get-Date).ToString('s')
        CreatedBy         = ('bluray-trackdump.ps1 v' + $ScriptVersion)
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

# ── Menu ───────────────────────────────────
function Show-Menu {
    Show-Header
    Write-UiSection -Title "Actions"
    Write-Host "  1) Dump track metadata for largest .m2ts"
    Write-UiDivider
    Write-Host "  Q) Return"
}

# ── Main Action ────────────────────────────
function Start-TrackDump {
    Show-Header

    $exe = Get-MakeMKVPath
    if (-not $exe) {
        Write-CoreError "MakeMKV not found"
        Pause-Script
        return
    }

    $name = Read-Host "Movie name"
    if ([string]::IsNullOrWhiteSpace($name)) {
        $name = "bluray_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
    }

    $year = Read-Host "Year (optional)"
    if ($year -match '^\d{4}$') {
        $name = "$name [$year]"
    }

    $safe = Get-SafeName $name
    $backup   = Join-Path $Script:BackupRoot $safe
    $metaBase = Join-Path $Script:MetaRoot   $safe

    Write-UiSection -Title "MakeMKV"
    Write-Host "  Decrypting..."

    $code = Show-MakeMKVProgress $exe $Script:Drive $backup
    if ($code -ne 0) {
        Write-CoreError "MakeMKV backup failed"
        Pause-Script
        return
    }

    $stream = Get-StreamPath -RootPath $backup
    if (-not $stream) {
        Write-CoreError "No STREAM folder found"
        Pause-Script
        return
    }

    $largest = Get-LargestM2TS -Path $stream
    if (-not $largest) {
        Write-CoreError "No M2TS found"
        Pause-Script
        return
    }

    Write-UiSection -Title "Largest File"
    Write-Host "  $($largest.Name)"
    Write-Host "  $([math]::Round($largest.Length / 1GB, 2)) GB"

    try {
        $infoLines = Get-MakeMKVInfoLines -Exe $exe -Source $Script:Drive
        $titles    = ConvertFrom-MakeMKVInfo -Lines $infoLines
        $mainTitle = Get-MainTitleFromInfo -Titles $titles

        if (-not $mainTitle) {
            Write-CoreError "Could not determine main title"
            Pause-Script
            return
        }

        # Prompt for any tracks MakeMKV returned with no language code.
        Resolve-TrackLanguages -Title $mainTitle

        $meta = [pscustomobject]@{
            MovieName   = $name
            LargestM2TS = $largest.Name
            LargestPath = $largest.FullName
            Title       = $mainTitle
        }

        Save-TrackMeta -Meta $meta -BasePath $metaBase

        Write-UiSection -Title "Track Dump Saved"
        Write-Host "  JSON : $metaBase.json"
        Write-Host "  TXT  : $metaBase.tracks.txt"

        $jsonKey = [System.IO.Path]::GetFileNameWithoutExtension("$metaBase.json")
        Write-UiBlankLine
        Write-Host "  ┌─ Use this name in BREncoder ──────────────────────────"
        Write-Host "  │  $jsonKey"
        Write-Host "  └───────────────────────────────────────────────────────"
        Write-UiBlankLine
        Write-Host "  Title: $($mainTitle.TitleId) -> $($mainTitle.SourceFile)"
    }
    catch {
        Write-CoreError $_.Exception.Message
        Pause-Script
        return
    }
    finally {
        Remove-Item -LiteralPath $backup -Recurse -Force -ErrorAction SilentlyContinue
    }

    Pause-Script
}

# ── Main Loop ──────────────────────────────
Ensure-Dirs

while ($true) {
    Show-Menu
    $c = (Read-Host "Choice").ToUpper()

    switch ($c) {
        '1' { Start-TrackDump }
        'Q' { return }
        default { }
    }
}