#--------------------------------------------
# file:     weatherfetch-menu.ps1
# author:   Mike Redd
# version:  2.0
# created:  2026-03-30
# updated:  2026-03-31
# desc:     DT-WeatherFetch - PowerShell
#--------------------------------------------

param(
    [Parameter(Position=0)]
    [string]$Location = "",
    [switch]$Metric
)

$ScriptName    = "DT-WeatherFetch"
$ScriptVersion = "2.0"
$ScriptAuthor  = "Mike Redd"

$ESC = [char]27
function C($code) { return "$ESC[${code}m" }
$R   = C "0"; $B = C "1"; $DIM = C "2"
$CYN = C "96"; $YLW = C "93"; $GRN = C "92"; $MAG = C "95"; $RED = C "91"; $GRY = C "90"

function Row($label, $value, $color = $GRN) {
    Write-Host "  $DIM$($label.PadRight(18))$R  $color$value$R"
}

function Header($text) {
    Write-Host "  $MAG${B}-- $text $("-" * [Math]::Max(1,(44-$text.Length)))$R"
}

function Get-BoxWidth {
    return 60
}

function Write-BoxBorder {
    param([int]$Width = 60)
    Write-Host "  $CYN${B}+$('=' * $Width)+$R"
}

function Write-BoxCenteredLine {
    param(
        [string]$Text,
        [int]$Width = 60
    )

    $innerWidth = $Width
    if ($Text.Length -gt $innerWidth) {
        $Text = $Text.Substring(0, $innerWidth)
    }

    $padLeft  = [math]::Floor(($innerWidth - $Text.Length) / 2)
    $padRight = $innerWidth - $Text.Length - $padLeft

    Write-Host "  $CYN${B}|$R$(' ' * $padLeft)$YLW${B}$Text$R$(' ' * $padRight)$CYN${B}|$R"
}

function Show-Menu {
    Clear-Host
    Write-Host ""
	$BoxWidth = Get-BoxWidth
	Write-Host ""
	Write-BoxBorder $BoxWidth
	Write-BoxCenteredLine "$ScriptName v$ScriptVersion" $BoxWidth
	Write-BoxBorder $BoxWidth
    Write-Host ""
    Write-Host "  ${MAG}${B}-- Weather Options --${R}"
    Write-Host ""
    Write-Host "  ${GRN}1)${R} Enter city"
    Write-Host "  ${GRN}2)${R} Enter ZIP code"
    Write-Host "  ${GRN}3)${R} Use last location"
    Write-Host "  ${GRY}Q)${R} Quit"
    Write-Host ""
}

function Pause-Return {
    Write-Host ""
    Write-Host -NoNewline "  ${GRY}Press Enter to return...${R}"
    Read-Host | Out-Null
}

function Get-LocationFromMenu {
    param(
        [string]$LastLocation
    )

    while ($true) {
        Show-Menu

        if ($LastLocation) {
            Write-Host "  ${DIM}Last location:${R} $LastLocation"
            Write-Host ""
        }

        Write-Host -NoNewline "  ${YLW}${B}Choice:${R} "
        $choice = Read-Host

        switch ($choice.ToUpper()) {
            "1" {
                $city = Read-Host "`n  Enter city"
                if (-not [string]::IsNullOrWhiteSpace($city)) {
                    return $city.Trim()
                }
            }
            "2" {
                $zip = Read-Host "`n  Enter ZIP code"
                if (-not [string]::IsNullOrWhiteSpace($zip)) {
                    return $zip.Trim()
                }
            }
            "3" {
                if ($LastLocation) {
                    return $LastLocation
                } else {
                    Write-Host "`n  ${RED}No last location saved.${R}"
                    Start-Sleep -Seconds 1
                }
            }
            "Q" {
                return $null
            }
            default {
                Write-Host "`n  ${RED}Invalid option.${R}"
                Start-Sleep -Seconds 1
            }
        }
    }
}

function Get-WxDesc([int]$c) {
    $m = @{
        0="Clear sky";1="Mainly clear";2="Partly cloudy";3="Overcast";45="Fog";48="Icy fog";
        51="Light drizzle";53="Moderate drizzle";55="Dense drizzle";
        61="Slight rain";63="Moderate rain";65="Heavy rain";
        71="Slight snow";73="Moderate snow";75="Heavy snow";77="Snow grains";
        80="Slight showers";81="Moderate showers";82="Heavy showers";
        85="Slight snow showers";86="Heavy snow showers";
        95="Thunderstorm";96="Thunderstorm w/ hail";99="Thunderstorm w/ heavy hail"
    }
    if ($m.ContainsKey($c)) { return $m[$c] }
    return "Unknown ($c)"
}

function Get-WxIcon([int]$c) {
    if ($c -eq 0)           { return "  [SUN]  " }
    if ($c -in 1,2)         { return " [PCSUN] " }
    if ($c -eq 3)           { return " [CLOUD] " }
    if ($c -in 45,48)       { return "  [FOG]  " }
    if ($c -in 51,53,55)    { return " [DRZL]  " }
    if ($c -in 61,63,65)    { return " [RAIN]  " }
    if ($c -in 71,73,75,77) { return " [SNOW]  " }
    if ($c -in 80,81,82)    { return "[SHWRS]  " }
    if ($c -in 85,86)       { return "[SNWSHR] " }
    if ($c -in 95,96,99)    { return "[STORM]  " }
    return "  [ ? ]  "
}

function Get-WindDir([int]$d) {
    if ($d -ge 337 -or $d -lt 23) { return "N" }
    if ($d -lt 68)  { return "NE" }
    if ($d -lt 113) { return "E"  }
    if ($d -lt 158) { return "SE" }
    if ($d -lt 203) { return "S"  }
    if ($d -lt 248) { return "SW" }
    if ($d -lt 293) { return "W"  }
    return "NW"
}

# ── Find curl.exe ─────────────────────────────────────────────
$curlExe = $null
foreach ($c in @(
    "$env:SystemRoot\System32\curl.exe",
    "$env:SystemRoot\SysWOW64\curl.exe",
    "C:\Windows\System32\curl.exe"
)) {
    if (Test-Path $c) { $curlExe = $c; break }
}

if (-not $curlExe) {
    $found = Get-Command curl.exe -ErrorAction SilentlyContinue
    if ($found) { $curlExe = $found.Source }
}

if (-not $curlExe) {
    Write-Host "  curl.exe not found. Ships with Windows 10/11 build 1803+."
    exit 1
}

function Invoke-CurlJson($url) {
    $result = & $curlExe --silent --max-time 15 $url
    if ($LASTEXITCODE -ne 0) { throw "curl failed (code $LASTEXITCODE)" }
    $parsed = $result | ConvertFrom-Json
    if ($parsed.error) { throw "API error: $($parsed.reason)" }
    return $parsed
}

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

function Invoke-WeatherFetch {
    param(
        [string]$Location
    )

    if ([string]::IsNullOrWhiteSpace($Location)) {
        throw "No location provided."
    }

    if ($Metric) {
        $TempUnit="celsius"; $WindUnit="kmh"; $TempSym="C"; $WindSym="km/h"; $PrecipUnit="mm"; $PrecipSym="mm"
    } else {
        $TempUnit="fahrenheit"; $WindUnit="mph"; $TempSym="F"; $WindSym="mph"; $PrecipUnit="inch"; $PrecipSym="in"
    }

    # ── Step 1: Geocode ──────────────────────────────────────────
    Write-Host ""
    Write-Host "  ${CYN}Looking up: ${B}$Location${R}${CYN}...${R}"

    $enc    = [System.Uri]::EscapeDataString($Location)
    $geoUrl = "https://geocoding-api.open-meteo.com/v1/search?name=$enc&count=1&language=en&format=json"

    try {
        $geoJson = Invoke-CurlJson $geoUrl
        $geo     = $geoJson.results[0]
    } catch {
        throw "Geocoding failed: $_"
    }

    if (-not $geo) {
        throw "No results for: $Location  --  try `"City, State`" format"
    }

    $lat    = [double]$geo.latitude
    $lon    = [double]$geo.longitude
    $tz     = if ($geo.timezone) { [string]$geo.timezone } else { "auto" }
    $elev   = $geo.elevation
    $locStr = $geo.name
    if ($geo.admin1)  { $locStr += ", $($geo.admin1)" }
    if ($geo.country) { $locStr += ", $($geo.country)" }

    Write-Host "  ${GRN}Found: $locStr ($lat, $lon)${R}"

    # ── Step 2: Fetch weather ────────────────────────────────────
    $wxUrl = ("https://api.open-meteo.com/v1/forecast" +
        "?latitude=$lat&longitude=$lon" +
        "&current=temperature_2m,relative_humidity_2m,apparent_temperature,weather_code," +
            "wind_speed_10m,wind_direction_10m,wind_gusts_10m,precipitation," +
            "surface_pressure,cloud_cover,visibility,uv_index,is_day" +
        "&daily=sunrise,sunset,uv_index_max," +
            "temperature_2m_max,temperature_2m_min,precipitation_sum," +
            "wind_speed_10m_max,weather_code" +
        "&temperature_unit=$TempUnit" +
        "&wind_speed_unit=$WindUnit" +
        "&precipitation_unit=$PrecipUnit" +
        "&timezone=$tz" +
        "&forecast_days=3")

    try {
        $wx = Invoke-CurlJson $wxUrl
    } catch {
        throw "Weather API failed: $_`n  URL: $wxUrl"
    }

    # ── Parse ─────────────────────────────────────────────────────
    $cur = $wx.current
    $day = $wx.daily

    $temp      = $cur.temperature_2m
    $feels     = $cur.apparent_temperature
    $humidity  = $cur.relative_humidity_2m
    $windSpd   = $cur.wind_speed_10m
    $windDeg   = [int]$cur.wind_direction_10m
    $windGust  = $cur.wind_gusts_10m
    $precip    = $cur.precipitation
    $pressure  = $cur.surface_pressure
    $cloud     = $cur.cloud_cover
    $vis       = $cur.visibility
    $uv        = $cur.uv_index
    $wxCode    = [int]$cur.weather_code
    $isDay     = $cur.is_day
    $updated   = $cur.time

    $sunrise   = "$($day.sunrise[0])" -replace '^.+T',''
    $sunset    = "$($day.sunset[0])"  -replace '^.+T',''
    $tempMax   = $day.temperature_2m_max[0]
    $tempMin   = $day.temperature_2m_min[0]
    $uvMax     = $day.uv_index_max[0]
    $precipSum = $day.precipitation_sum[0]
    $windMax   = $day.wind_speed_10m_max[0]

    $fc1Date   = $day.time[1]
    $fc1Max    = $day.temperature_2m_max[1]
    $fc1Min    = $day.temperature_2m_min[1]
    $fc1Code   = [int]$day.weather_code[1]
    $fc1Precip = $day.precipitation_sum[1]

    $fc2Date   = $day.time[2]
    $fc2Max    = $day.temperature_2m_max[2]
    $fc2Min    = $day.temperature_2m_min[2]
    $fc2Code   = [int]$day.weather_code[2]
    $fc2Precip = $day.precipitation_sum[2]

    $wxDesc    = Get-WxDesc $wxCode
    $wxIcon    = Get-WxIcon $wxCode
    $windComp  = Get-WindDir $windDeg
    $daytime   = if ($isDay -eq 1) { "Day" } else { "Night" }

    if ($Metric) {
        $visStr      = "{0:N1} km"   -f ($vis / 1000)
        $pressureStr = "{0:N1} hPa"  -f $pressure
    } else {
        $visStr      = "{0:N1} mi"   -f ($vis / 1609.34)
        $pressureStr = "{0:N2} inHg" -f ($pressure * 0.02953)
    }

    # ── Output ────────────────────────────────────────────────────
    Clear-Host
    Write-Host ""
	$BoxWidth = Get-BoxWidth
	Write-Host ""
	Write-BoxBorder $BoxWidth
	Write-BoxCenteredLine "$ScriptName v$ScriptVersion" $BoxWidth
	Write-BoxBorder $BoxWidth
    Write-Host ""
    Write-Host "  ${B}$wxIcon  $YLW$locStr$R"
    Write-Host "       $GRN${B}$wxDesc$R  $DIM($daytime)$R"
    Write-Host "       ${DIM}Updated: $updated  |  Lat: $lat  Lon: $lon  Elev: ${elev}m$R"
    Write-Host ""

    Header "CURRENT CONDITIONS"
    Write-Host ""
    Row "Temperature"    "$temp deg$TempSym  (feels like $feels deg$TempSym)"
    Row "Today High/Low" "$tempMax deg$TempSym / $tempMin deg$TempSym"
    Row "Conditions"     $wxDesc
    Row "Humidity"       "${humidity}%"
    Row "Wind"           "$windSpd $WindSym $windComp  (gusts $windGust $WindSym)"
    Row "Wind Max Today" "$windMax $WindSym"
    Row "Precipitation"  "$precip $PrecipSym now  |  $precipSum $PrecipSym today total"
    Row "Cloud Cover"    "${cloud}%"
    Row "Visibility"     $visStr
    Row "Pressure"       $pressureStr
    Row "UV Index"       "$uv now  |  $uvMax max today"
    Write-Host ""

    Header "SUN"
    Write-Host ""
    Row "Sunrise" $sunrise
    Row "Sunset"  $sunset
    Write-Host ""

    Header "2-DAY FORECAST"
    Write-Host ""
    Write-Host "  ${B}$fc1Date$R"
    Write-Host "  $(Get-WxIcon $fc1Code) $GRN${fc1Max}deg$TempSym / ${fc1Min}deg${TempSym}$R  $(Get-WxDesc $fc1Code)  ${DIM}Precip: $fc1Precip $PrecipSym$R"
    Write-Host ""
    Write-Host "  ${B}$fc2Date$R"
    Write-Host "  $(Get-WxIcon $fc2Code) $GRN${fc2Max}deg$TempSym / ${fc2Min}deg${TempSym}$R  $(Get-WxDesc $fc2Code)  ${DIM}Precip: $fc2Precip $PrecipSym$R"
    Write-Host ""

    Write-Host "  $CYN${B}+============================================================+$R"
    Write-Host "  ${DIM}  Data: open-meteo.com (free, no API key required)$R"
    Write-Host "  $CYN${B}+============================================================+$R"
    Write-Host ""
}

# direct CLI mode still works
if (-not [string]::IsNullOrWhiteSpace($Location)) {
    try {
        Invoke-WeatherFetch -Location $Location.Trim()
    } catch {
        Write-Host ""
        Write-Host "  ${RED}$($_.Exception.Message)${R}"
        exit 1
    }
    exit 0
}

# menu loop mode for unified launcher
$LastLocation = $null
while ($true) {
    $selectedLocation = Get-LocationFromMenu -LastLocation $LastLocation
    if (-not $selectedLocation) {
        break
    }

    $LastLocation = $selectedLocation

    try {
        Invoke-WeatherFetch -Location $selectedLocation
    } catch {
        Clear-Host
        Write-Host ""
        Write-Host "  ${RED}$($_.Exception.Message)${R}"
        Write-Host ""
    }

    Pause-Return
}