#--------------------------------------------
# file:     imdbdump.ps1
# author:   Mike Redd
# version:  1.12
# created:  2026-04-11
# updated:  2026-07-09
# desc:     OMDb / IMDb metadata lookup tool
#           for ToolMenu. Search by title
#           or IMDb ID. Display only.
#           v1.6: adds -Json/-NonInteractive backend mode for MiNfoCreate.
#           v1.7: adds env-driven backend lookup to avoid switch-binding issues from GUI callers.
#           v1.8: backend mode supports explicit named args first and uses
#                 the same OMDb key source as imdbthumbgrab.
#           v1.9: backend mode uses the same curl-based OMDb request path
#                 as imdbthumbgrab instead of Invoke-RestMethod.
#           v1.10: supports MiNfoCreate environment-only backend calls.
#           v1.11: normalizes IMDb IDs that arrive through title/env fallback.
#           v1.12: backend pairing for MiNfoCreate JSON handoff fix.
#--------------------------------------------

param(
    [string]$Title          = "",
    [string]$Year           = "",
    [string]$ImdbId         = "",
    [string]$ApiKey         = "",
    [switch]$Json,
    [switch]$NonInteractive,
    [switch]$Help
)

$ErrorActionPreference = 'Stop'

$ScriptName    = "IMDbDump"
$ScriptVersion = "1.12"
$ScriptAuthor  = "Mike Redd"

# ── Non-interactive backend mode ──────────────────────────────
# MediaForge / MiNfoCreate use this path as the movie metadata backend.
# Keep the original interactive menu below untouched.
$Script:IMDbDumpNonInteractive = [bool](
    $NonInteractive -or
    $Json -or
    ($env:IMDBDUMP_JSON -eq '1') -or
    ($env:MEDIAFORGE_GUI -eq '1') -or
    ($env:MEDIAFORGE_NONINTERACTIVE -eq '1')
)

if ($Script:IMDbDumpNonInteractive) {
    $Script:ConfigPaths = @(
        "$env:USERPROFILE\PS\profile.d\minforc.ps1",
        "$PSScriptRoot\minforc.ps1",
        "$HOME\.config\minforc.ps1"
    )

    $Script:ConfigLoadedFrom = ''
    foreach ($cp in $Script:ConfigPaths) {
        if (Test-Path -LiteralPath $cp) {
            try {
                . $cp
                $Script:ConfigLoadedFrom = $cp
                break
            } catch {
                throw "IMDbDump config load failed from ${cp}: $($_.Exception.Message)"
            }
        }
    }

    # Match imdbthumbgrab.ps1: explicit -ApiKey wins, otherwise use the
    # configured global key from minforc.ps1. Avoid stale local/env fallbacks
    # that can point at an old or test key.
    if (-not $ApiKey) {
        $ApiKey = $global:OMDB_API_KEY
    }

    # Backend callers such as MiNfoCreate/MediaForge can pass lookup values
    # through environment variables. This avoids a fragile nested-script switch
    # binding path where values like -Title could accidentally land in -ImdbId.
    if (-not $Title -and $env:IMDBDUMP_TITLE) { $Title = $env:IMDBDUMP_TITLE }
    if (-not $Year -and $env:IMDBDUMP_YEAR) { $Year = $env:IMDBDUMP_YEAR }
    if (-not $ImdbId -and $env:IMDBDUMP_IMDBID) { $ImdbId = $env:IMDBDUMP_IMDBID }
    if ($env:IMDBDUMP_JSON -eq '1') { $Json = $true }

    # Defensive cleanup for malformed/nested calls. MediaForge -> MiNfoCreate
    # runs through background runspaces, and older attempts could accidentally
    # pass an IMDb ID into -Title. If any lookup field contains a real tt#######
    # token, always treat that as the IMDb ID and query OMDb with i=<id>.
    function Get-IMDbIdTokenFromText {
        param([AllowNull()][string]$Value)
        if ([string]::IsNullOrWhiteSpace($Value)) { return '' }
        $m = [regex]::Match([string]$Value, 'tt\d{6,10}', 'IgnoreCase')
        if ($m.Success) { return $m.Value.ToLowerInvariant() }
        return ''
    }

    $detectedId = Get-IMDbIdTokenFromText $ImdbId
    if (-not $detectedId) { $detectedId = Get-IMDbIdTokenFromText $Title }
    if (-not $detectedId) { $detectedId = Get-IMDbIdTokenFromText $env:IMDBDUMP_IMDBID }
    if (-not $detectedId) { $detectedId = Get-IMDbIdTokenFromText $env:IMDBDUMP_TITLE }

    if ($detectedId) {
        $ImdbId = $detectedId
        if ((Get-IMDbIdTokenFromText $Title) -eq $detectedId) { $Title = '' }
    }

    # Switch tokens are never valid values. Drop them instead of querying OMDb
    # for strings like -Json, -Title, or -ImdbId.
    if ($ImdbId -match '^-' ) { $ImdbId = '' }
    if ($Title  -match '^-' ) { $Title  = '' }
    if ($Year   -match '^-' ) { $Year   = '' }

    if (-not $ApiKey -or [string]::IsNullOrWhiteSpace($ApiKey) -or $ApiKey -eq 'your_api_key_here') {
        throw 'OMDB_API_KEY not set. Set it in minforc.ps1 or pass -ApiKey.'
    }

    $Script:CurlExe = $null
    foreach ($c in @(
        "$env:SystemRoot\System32\curl.exe",
        "$env:SystemRoot\SysWOW64\curl.exe",
        'curl.exe'
    )) {
        if (-not $c) { continue }
        try {
            $cmd = Get-Command $c -ErrorAction SilentlyContinue
            if ($cmd) {
                $Script:CurlExe = $cmd.Source
                break
            }
        } catch {}
    }

    if (-not $Script:CurlExe) {
        throw 'curl.exe not found; IMDbDump backend cannot query OMDb.'
    }

    function Get-OMDbMovieDataPlain {
        param(
            [string]$Title,
            [string]$Year,
            [string]$ImdbId
        )

        $baseUrl = 'http://www.omdbapi.com/'

        if ($ImdbId) {
            $cleanId = ([regex]::Match($ImdbId, 'tt\d{6,10}', 'IgnoreCase')).Value.ToLowerInvariant()
            if (-not $cleanId) { throw "Invalid IMDb ID supplied: ${ImdbId}" }
            $url = "${baseUrl}?apikey=${ApiKey}&i=${cleanId}&plot=full"
            $lookupLabel = "IMDb ID ${cleanId}"
        } elseif ($Title) {
            $encodedTitle = [uri]::EscapeDataString($Title.Trim())
            $url = "${baseUrl}?apikey=${ApiKey}&t=${encodedTitle}&plot=full"
            if ($Year -match '^\d{4}$') { $url += "&y=$Year" }
            $lookupLabel = if ($Year -match '^\d{4}$') { "title '$($Title.Trim())' ($Year)" } else { "title '$($Title.Trim())'" }
        } else {
            throw 'A title or IMDb ID is required.'
        }

        # Keep backend behavior aligned with imdbthumbgrab.ps1. OMDb may return
        # a useful JSON error body with an HTTP error status; curl lets us read
        # that body instead of throwing a web exception before parsing it.
        $raw = & $Script:CurlExe --silent --location --max-time 15 $url
        $curlExit = $LASTEXITCODE
        if ($curlExit -ne 0) {
            throw "OMDb curl request failed for ${lookupLabel} with exit code $curlExit."
        }
        if ([string]::IsNullOrWhiteSpace($raw)) {
            throw "OMDb returned an empty response for ${lookupLabel}."
        }

        try {
            $movie = $raw | ConvertFrom-Json -ErrorAction Stop
        } catch {
            $snippet = if ($raw.Length -gt 220) { $raw.Substring(0,220) + '...' } else { $raw }
            throw "OMDb returned invalid JSON for ${lookupLabel}: $($_.Exception.Message) :: $snippet"
        }

        if ($movie.Response -ne 'True') {
            $err = if ($movie.Error) { $movie.Error } else { 'unknown OMDb error' }
            throw "OMDb Error for ${lookupLabel}: $err"
        }

        return $movie
    }

    $movie = Get-OMDbMovieDataPlain -Title $Title -Year $Year -ImdbId $ImdbId

    if ($Json) {
        $movie | ConvertTo-Json -Depth 12 -Compress
    } else {
        $movie
    }
    return
}

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