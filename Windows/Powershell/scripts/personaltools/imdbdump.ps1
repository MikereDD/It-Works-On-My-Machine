#--------------------------------------------
# file:     imdbdump.ps1
# author:   Mike Redd
# version:  1.5
# created:  2026-04-11
# updated:  2026-04-11
# desc:     OMDb / IMDb metadata lookup tool
#           for ToolMenu. Search by title
#           or IMDb ID. Display only.
#--------------------------------------------

$ErrorActionPreference = 'Stop'

$ScriptName    = "IMDbDump"
$ScriptVersion = "1.5"
$ScriptAuthor  = "Mike Redd"

# ── Load custom UI ────────────────────────────────────────────
$uiPath = "$env:USERPROFILE\PS\profile.d\ui.ps1"
if (Test-Path -LiteralPath $uiPath) {
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
if (Test-Path -LiteralPath $corePath) {
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

# ── Load config ───────────────────────────────────────────────
$configPath = "$env:USERPROFILE\PS\profile.d\minforc.ps1"
if (Test-Path -LiteralPath $configPath) {
    try {
        . $configPath
    }
    catch {
        Clear-UiScreen
        Write-UiHeader -Title $ScriptName -Subtitle "v$ScriptVersion  by $ScriptAuthor" -Width (Get-UiBoxWidth -MaxWidth 64 -MinWidth 46)
        Write-UiRow "Config" "failed to load" $global:UI_RED
        Write-UiBlankLine
        Write-Host "  $($global:UI_RED)$($_.Exception.Message)$($global:UI_R)"
        Write-UiBlankLine
        Pause-Core "Press Enter to return..."
        return
    }
}
else {
    Clear-UiScreen
    Write-UiHeader -Title $ScriptName -Subtitle "v$ScriptVersion  by $ScriptAuthor" -Width (Get-UiBoxWidth -MaxWidth 64 -MinWidth 46)
    Write-UiRow "Config" "not found" $global:UI_RED
    Write-UiBlankLine
    Write-Host "  $($global:UI_YLW)$configPath$($global:UI_R)"
    Write-UiBlankLine
    Pause-Core "Press Enter to return..."
    return
}

# ── Resolve config values ─────────────────────────────────────
$ApiKey = $global:OMDB_API_KEY

if (-not $ApiKey -or [string]::IsNullOrWhiteSpace($ApiKey) -or $ApiKey -eq "your_api_key_here") {
    Clear-UiScreen
    Write-UiHeader -Title $ScriptName -Subtitle "v$ScriptVersion  by $ScriptAuthor" -Width (Get-UiBoxWidth -MaxWidth 64 -MinWidth 46)
    Write-UiRow "Status" "OMDB API key missing" $global:UI_RED
    Write-UiBlankLine
    Write-Host "  $($global:UI_CYN)Get a free key at: https://www.omdbapi.com/apikey.aspx$($global:UI_R)"
    Write-Host "  $($global:UI_YLW)Set it in minforc.ps1$($global:UI_R)"
    Write-UiBlankLine
    Pause-Core "Press Enter to return..."
    return
}

# ── Helpers ───────────────────────────────────────────────────
function Show-IMDbDumpHeader {
    Clear-UiScreen
    $w = Get-UiBoxWidth -MaxWidth 66 -MinWidth 48
    Write-UiHeader -Title $ScriptName -Subtitle "v$ScriptVersion  by $ScriptAuthor" -Width $w
    Write-UiBlankLine
}

function Pause-Script {
    Pause-Core "Press Enter to continue..."
}

function Get-OMDbMovieData {
    param(
        [string]$Title,
        [string]$Year,
        [string]$ImdbId
    )

    if ($ImdbId) {
        $url = "http://www.omdbapi.com/?apikey=$ApiKey&i=$ImdbId&plot=full"
    }
    elseif ($Title) {
        $encodedTitle = [uri]::EscapeDataString($Title)
        $url = "http://www.omdbapi.com/?apikey=$ApiKey&t=$encodedTitle&plot=full"

        if (-not [string]::IsNullOrWhiteSpace($Year)) {
            $url += "&y=$Year"
        }
    }
    else {
        return $null
    }

    try {
        return Invoke-RestMethod -Uri $url -Method Get -ErrorAction Stop
    }
    catch {
        Write-UiBlankLine
        Write-Host "  $($global:UI_RED)Failed to contact OMDb API.$($global:UI_R)"
        Write-Host "  $($global:UI_DIM)$($_.Exception.Message)$($global:UI_R)"
        return $null
    }
}

function Show-MovieResult {
    param(
        [Parameter(Mandatory)]
        $Movie
    )

    Write-UiSection "Result"
    Write-UiRow "Title"    $Movie.Title $global:UI_GRN
    Write-UiRow "Year"     $Movie.Year
    Write-UiRow "Rated"    $Movie.Rated
    Write-UiRow "Released" $Movie.Released
    Write-UiRow "Runtime"  $Movie.Runtime
    Write-UiRow "Genre"    $Movie.Genre
    Write-UiRow "Director" $Movie.Director
    Write-UiRow "Writer"   $Movie.Writer
    Write-UiRow "Actors"   $Movie.Actors
    Write-UiRow "Language" $Movie.Language
    Write-UiRow "Country"  $Movie.Country
    Write-UiRow "Awards"   $Movie.Awards
    Write-UiRow "IMDb"     $Movie.imdbRating $global:UI_CYN
    Write-UiRow "Votes"    $Movie.imdbVotes
    Write-UiRow "IMDb ID"  $Movie.imdbID $global:UI_CYN
    Write-UiBlankLine

    Write-UiSection "Plot"
    Write-Host "  $($global:UI_WHT)$($Movie.Plot)$($global:UI_R)"
    Write-UiBlankLine
}

function Search-ByMovieName {
    Show-IMDbDumpHeader
    Write-UiSection "Search by Movie Name"

    Write-Host -NoNewline "  $($global:UI_YLW)Enter movie name: $($global:UI_R)"
    $title = Read-Host

    if ([string]::IsNullOrWhiteSpace($title)) {
        return
    }

    Write-Host -NoNewline "  $($global:UI_CYN)Enter year (optional): $($global:UI_R)"
    $year = Read-Host

    $movie = Get-OMDbMovieData -Title $title.Trim() -Year $year.Trim()

    if (-not $movie) {
        Pause-Script
        return
    }

    if ($movie.Response -eq "False") {
        Write-UiBlankLine
        Write-Host "  $($global:UI_RED)$($movie.Error)$($global:UI_R)"
        Write-UiBlankLine
        Pause-Script
        return
    }

    Write-UiBlankLine
    Show-MovieResult -Movie $movie
    Pause-Script
}

function Search-ByIMDbID {
    Show-IMDbDumpHeader
    Write-UiSection "Search by IMDb ID"

    Write-Host -NoNewline "  $($global:UI_YLW)Enter IMDb ID (example: tt0082761): $($global:UI_R)"
    $imdbId = Read-Host

    if ([string]::IsNullOrWhiteSpace($imdbId)) {
        return
    }

    $movie = Get-OMDbMovieData -ImdbId $imdbId.Trim()

    if (-not $movie) {
        Pause-Script
        return
    }

    if ($movie.Response -eq "False") {
        Write-UiBlankLine
        Write-Host "  $($global:UI_RED)$($movie.Error)$($global:UI_R)"
        Write-UiBlankLine
        Pause-Script
        return
    }

    Write-UiBlankLine
    Show-MovieResult -Movie $movie
    Pause-Script
}

function Show-MainMenu {
    Show-IMDbDumpHeader
    Write-UiSection "Lookup Menu"
    Write-Host "  $($global:UI_WHT)1.$($global:UI_R) Search by movie name"
    Write-Host "  $($global:UI_WHT)2.$($global:UI_R) Search by IMDb ID"
    Write-Host "  $($global:UI_WHT)Q.$($global:UI_R) Quit"
    Write-UiBlankLine
}

# ── Main ──────────────────────────────────────────────────────
$script:ExitTool = $false

do {
    Show-MainMenu
    $choice = (Read-Host "  Select option").Trim().ToUpper()

    switch ($choice) {
        "1" {
            Search-ByMovieName
        }

        "2" {
            Search-ByIMDbID
        }

        "Q" {
            $script:ExitTool = $true
        }

        default {
            Write-UiBlankLine
            Write-Host "  $($global:UI_RED)Invalid selection.$($global:UI_R)"
            Write-UiBlankLine
            Pause-Script
        }
    }
}
while (-not $script:ExitTool)

return