<#
    Atomic Clock for Windows
    ------------------------------------------------------------------------
    A faithful desktop clone of the "Atomic Clock" Android app (typezero /
    It-Works-On-My-Machine). Syncs to internet time servers over SNTP/NTP and
    shows true atomic time -- not the (possibly drifting) Windows wall clock --
    with live local weather.

      * SNTP client (RFC 4330): clock offset + round-trip from the four NTP
        timestamps, modelled on AOSP's SntpClient.
      * Monotonic anchoring: corrected time is pinned to a process-wide
        Stopwatch, so it stays right even if the Windows clock is wrong.
      * Best-of-N sampling per sync, with automatic fallback across servers.
      * Live weather via Open-Meteo (keyless), located by IP geolocation.
      * Sweeping-second clock face, drift / accuracy / source stats, settings.

    Windows adaptations vs. the Android original:
      * "Coarse location" -> IP-based geolocation (with manual lat/lon override).
      * The Android home-screen widget has no desktop analog and is omitted.

    Single file. Windows PowerShell 5.1+ or PowerShell 7+. No dependencies.
#>

# --- Run under STA (WinForms requirement); relaunch if needed ------------------
# WinForms needs a single-threaded apartment. Windows PowerShell (powershell.exe)
# honours -Sta reliably and runs this 5.1-compatible code, so relaunch there if
# we're not already STA. -NoProfile sidesteps any StrictMode-in-profile surprises.
if (([System.Threading.Thread]::CurrentThread.GetApartmentState() -ne 'STA') -and $PSCommandPath) {
    Start-Process -FilePath 'powershell.exe' `
        -ArgumentList @('-NoProfile', '-Sta', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`"") | Out-Null
    return
}

$ErrorActionPreference = 'Stop'
$script:Version = '0.1.0'
$script:RepoUrl = 'https://github.com/MikereDD/It-Works-On-My-Machine'

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()
[System.Windows.Forms.Application]::SetCompatibleTextRenderingDefault($false)

# Dark immersive title bar (Win10 1809+ / Win11). Harmless elsewhere.
try {
    Add-Type -Namespace Native -Name Dwm -MemberDefinition @'
[System.Runtime.InteropServices.DllImport("dwmapi.dll")]
public static extern int DwmSetWindowAttribute(System.IntPtr hwnd, int attr, ref int val, int size);
'@
} catch { }

# ==============================================================================
#  Palette  (mirrors the app's "atomic glow" dark theme)
# ==============================================================================
function C([int]$r, [int]$g, [int]$b) { return [System.Drawing.Color]::FromArgb($r, $g, $b) }
function CA([int]$a, [System.Drawing.Color]$c) { return [System.Drawing.Color]::FromArgb($a, $c.R, $c.G, $c.B) }

$Theme = @{
    Background        = (C 5 7 13)
    Surface          = (C 12 17 28)
    SurfaceHigh      = (C 20 27 42)
    OnSurface        = (C 228 233 242)
    OnSurfaceVariant = (C 147 160 184)
    Teal             = (C 57 224 208)
    Blue             = (C 108 166 255)
    Violet           = (C 155 124 255)
    Amber            = (C 255 198 92)
    Red              = (C 255 107 107)
}
$Accent = $Theme.Teal

# ==============================================================================
#  Small helpers
# ==============================================================================
function Get-MonoMs {
    # Process-wide monotonic milliseconds (comparable across runspaces).
    return [double][System.Diagnostics.Stopwatch]::GetTimestamp() /
           [double][System.Diagnostics.Stopwatch]::Frequency * 1000.0
}

function Enable-DoubleBuffer($control) {
    $prop = $control.GetType().GetProperty('DoubleBuffered',
        [System.Reflection.BindingFlags]'Instance,NonPublic')
    if ($prop) { $prop.SetValue($control, $true, $null) }
}

function New-RoundRectPath([single]$x, [single]$y, [single]$w, [single]$h, [single]$r) {
    $p = New-Object System.Drawing.Drawing2D.GraphicsPath
    $d = $r * 2.0
    if ($d -gt $w) { $d = $w }
    if ($d -gt $h) { $d = $h }
    $p.AddArc($x, $y, $d, $d, 180, 90)
    $p.AddArc($x + $w - $d, $y, $d, $d, 270, 90)
    $p.AddArc($x + $w - $d, $y + $h - $d, $d, $d, 0, 90)
    $p.AddArc($x, $y + $h - $d, $d, $d, 90, 90)
    $p.CloseFigure()
    return $p
}

$script:MeasureBmp = New-Object System.Drawing.Bitmap 1, 1
$script:MeasureGfx = [System.Drawing.Graphics]::FromImage($script:MeasureBmp)

# Reusable StringFormats (avoid per-paint GDI handle churn)
$SfCenterMid = New-Object System.Drawing.StringFormat
$SfCenterMid.Alignment = [System.Drawing.StringAlignment]::Center
$SfCenterMid.LineAlignment = [System.Drawing.StringAlignment]::Center
$SfCenterTop = New-Object System.Drawing.StringFormat
$SfCenterTop.Alignment = [System.Drawing.StringAlignment]::Center
$SfLineMid = New-Object System.Drawing.StringFormat
$SfLineMid.LineAlignment = [System.Drawing.StringAlignment]::Center

# ==============================================================================
#  Settings  (persisted to %APPDATA%\AtomicClock\settings.json)
# ==============================================================================
$Servers = @(
    @{ Name = 'GOOGLE';     Display = 'Google';     Host = 'time.google.com' }
    @{ Name = 'CLOUDFLARE'; Display = 'Cloudflare'; Host = 'time.cloudflare.com' }
    @{ Name = 'POOL';       Display = 'NTP Pool';   Host = 'pool.ntp.org' }
    @{ Name = 'APPLE';      Display = 'Apple';      Host = 'time.apple.com' }
    @{ Name = 'NIST';       Display = 'NIST (US)';  Host = 'time.nist.gov' }
)
function Get-ServerByName([string]$name) {
    foreach ($s in $Servers) { if ($s.Name -eq $name) { return $s } }
    return $Servers[0]
}

$script:SettingsDir  = Join-Path $env:APPDATA 'AtomicClock'
$script:SettingsPath = Join-Path $script:SettingsDir 'settings.json'

function New-DefaultSettings {
    $imperial = (Get-Culture).Name -match '-(US|LR|MM)$'
    return [pscustomobject]@{
        use24Hour        = $true
        showMilliseconds = $true
        server           = 'GOOGLE'
        fahrenheit       = [bool]$imperial
        windMph          = [bool]$imperial
        manualLocation   = $false
        latitude         = 0.0
        longitude        = 0.0
    }
}

function Load-Settings {
    try {
        if (Test-Path $script:SettingsPath) {
            $raw = Get-Content $script:SettingsPath -Raw -ErrorAction Stop | ConvertFrom-Json
            $def = New-DefaultSettings
            foreach ($p in $def.PSObject.Properties) {
                if ($null -ne $raw.PSObject.Properties[$p.Name]) {
                    $def.$($p.Name) = $raw.$($p.Name)
                }
            }
            return $def
        }
    } catch { }
    return New-DefaultSettings
}

function Save-Settings($settings) {
    try {
        if (-not (Test-Path $script:SettingsDir)) {
            New-Item -ItemType Directory -Path $script:SettingsDir -Force | Out-Null
        }
        $settings | ConvertTo-Json | Set-Content -Path $script:SettingsPath -Encoding UTF8
    } catch { }
}

$Settings = Load-Settings

# ==============================================================================
#  Shared state  (written by background runspaces, read by the UI timer)
# ==============================================================================
$State = [hashtable]::Synchronized(@{})
$State.SyncStatus     = 'Idle'      # Idle | Syncing | Synced | Failed
$State.Syncing        = $false
$State.Sync           = $null        # @{ Server; Stratum; NtpMs; RefMono; Offset; Rtt }
$State.LastSyncMono   = -1e15
$State.WeatherStatus  = 'Loading'   # Loading | Available | Unavailable
$State.WeatherMsg     = 'Locating...'
$State.Weather        = $null        # @{ TempC; ApparentC; Humidity; WindKmh; WindDir; Code; IsDay; Label; Icon; City }
$State.WeatherFetching = $false
$State.LastWeatherMono = -1e15

# ==============================================================================
#  SNTP client  (self-contained; runs inside a background runspace)
# ==============================================================================
$SyncBlock = {
    param($State, $PreferredHost, $AllHosts)

    function MonoMs {
        return [double][System.Diagnostics.Stopwatch]::GetTimestamp() /
               [double][System.Diagnostics.Stopwatch]::Frequency * 1000.0
    }
    function ReadU32([byte[]]$b, [int]$o) {
        return ([long]$b[$o] -shl 24) -bor ([long]$b[$o + 1] -shl 16) -bor `
               ([long]$b[$o + 2] -shl 8) -bor ([long]$b[$o + 3])
    }
    function ReadTs([byte[]]$b, [int]$o) {
        $sec  = ReadU32 $b $o
        $frac = ReadU32 $b ($o + 4)
        return ([long]($sec - 2208988800) * 1000L) + [long](($frac * 1000L) / 4294967296L)
    }
    function WriteTs([byte[]]$b, [int]$o, [long]$ms) {
        $secs = [long][math]::Floor($ms / 1000.0)
        $msRem = $ms - ($secs * 1000L)
        $secs += 2208988800L
        $b[$o]     = [byte](($secs -shr 24) -band 0xFF)
        $b[$o + 1] = [byte](($secs -shr 16) -band 0xFF)
        $b[$o + 2] = [byte](($secs -shr 8)  -band 0xFF)
        $b[$o + 3] = [byte]($secs -band 0xFF)
        $frac = [long](($msRem * 4294967296L) / 1000L)
        $b[$o + 4] = [byte](($frac -shr 24) -band 0xFF)
        $b[$o + 5] = [byte](($frac -shr 16) -band 0xFF)
        $b[$o + 6] = [byte](($frac -shr 8)  -band 0xFF)
        $b[$o + 7] = [byte](Get-Random -Minimum 0 -Maximum 256)
    }

    function Request-One([string]$ntpHost) {
        $udp = $null
        try {
            $buf = New-Object byte[] 48
            $buf[0] = 0x1B   # LI=0, VN=3, Mode=3 (client)

            $t1Wall = [System.DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
            $t1Mono = MonoMs
            WriteTs $buf 40 $t1Wall

            $udp = New-Object System.Net.Sockets.UdpClient
            $udp.Client.ReceiveTimeout = 5000
            $udp.Client.SendTimeout = 5000
            $udp.Connect($ntpHost, 123)
            [void]$udp.Send($buf, 48)

            $remote = New-Object System.Net.IPEndPoint([System.Net.IPAddress]::Any, 0)
            $resp = $udp.Receive([ref]$remote)
            $t4Mono = MonoMs
            $t4Wall = $t1Wall + ($t4Mono - $t1Mono)

            if ($resp.Length -lt 48) { return $null }
            $leap    = ($resp[0] -shr 6) -band 0x3
            $mode    = $resp[0] -band 0x7
            $stratum = $resp[1] -band 0xFF
            if ($mode -ne 4 -and $mode -ne 5) { return $null }
            if ($leap -eq 3 -or $stratum -lt 1 -or $stratum -gt 15) { return $null }

            $t1p = ReadTs $resp 24    # originate (echoed)
            $t2  = ReadTs $resp 32    # server receive
            $t3  = ReadTs $resp 40    # server transmit

            $rtt    = ($t4Mono - $t1Mono) - ($t3 - $t2)
            $offset = (($t2 - $t1p) + ($t3 - $t4Wall)) / 2.0

            return @{
                Server  = $ntpHost
                Stratum = [int]$stratum
                NtpMs   = [double]($t4Wall + $offset)
                RefMono = [double]$t4Mono
                Offset  = [double]$offset
                Rtt     = [double]$rtt
            }
        } catch {
            return $null
        } finally {
            if ($udp) { $udp.Close() }
        }
    }

    function Best-Of([string]$ntpHost, [int]$samples) {
        $best = $null
        for ($i = 0; $i -lt $samples; $i++) {
            $r = Request-One $ntpHost
            if ($r -ne $null) {
                if ($best -eq $null -or $r.Rtt -lt $best.Rtt) { $best = $r }
            }
        }
        return $best
    }

    try {
        $result = Best-Of $PreferredHost 4
        if ($result -eq $null) {
            foreach ($h in $AllHosts) {
                if ($h -eq $PreferredHost) { continue }
                $result = Request-One $h
                if ($result -ne $null) { break }
            }
        }
        if ($result -ne $null) {
            $State.Sync = $result
            $State.LastSyncMono = MonoMs
            $State.SyncStatus = 'Synced'
        } else {
            $State.SyncStatus = 'Failed'
        }
    } catch {
        $State.SyncStatus = 'Failed'
    } finally {
        $State.LastSyncMono = MonoMs
        $State.Syncing = $false
    }
}

# ==============================================================================
#  Weather  (IP geolocation + Open-Meteo; self-contained runspace block)
# ==============================================================================
$WeatherBlock = {
    param($State, $Manual, $ManualLat, $ManualLon)

    function Wmo([int]$code, [bool]$day) {
        $clear = if ($day) { 'SUN' } else { 'MOON' }
        switch ($code) {
            0 { return @('Clear', $clear) }
            1 { return @('Mainly clear', $clear) }
            2 { return @('Partly cloudy', 'CLOUD') }
            3 { return @('Overcast', 'CLOUD') }
            { $_ -in 45, 48 } { return @('Fog', 'FOG') }
            { $_ -in 51, 53, 55 } { return @('Drizzle', 'RAIN') }
            { $_ -in 56, 57 } { return @('Freezing drizzle', 'RAIN') }
            { $_ -in 61, 63, 65 } { return @('Rain', 'RAIN') }
            { $_ -in 66, 67 } { return @('Freezing rain', 'RAIN') }
            { $_ -in 71, 73, 75, 77 } { return @('Snow', 'SNOW') }
            { $_ -in 80, 81, 82 } { return @('Rain showers', 'RAIN') }
            { $_ -in 85, 86 } { return @('Snow showers', 'SNOW') }
            { $_ -in 95, 96, 99 } { return @('Thunderstorm', 'STORM') }
            default { return @('--', 'CLOUD') }
        }
    }

    try {
        [System.Net.ServicePointManager]::SecurityProtocol =
            [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12

        $lat = $null; $lon = $null; $city = $null
        if ($Manual) {
            $lat = $ManualLat; $lon = $ManualLon
        } else {
            # Primary IP geolocation
            try {
                $geo = Invoke-RestMethod -Uri 'http://ip-api.com/json/' -TimeoutSec 6
                if ($geo.status -eq 'success') {
                    $lat = [double]$geo.lat; $lon = [double]$geo.lon; $city = $geo.city
                }
            } catch { }
            # Fallback
            if ($lat -eq $null) {
                try {
                    $geo2 = Invoke-RestMethod -Uri 'https://ipapi.co/json/' -TimeoutSec 6
                    if ($geo2.latitude -ne $null) {
                        $lat = [double]$geo2.latitude; $lon = [double]$geo2.longitude; $city = $geo2.city
                    }
                } catch { }
            }
        }

        if ($lat -eq $null -or $lon -eq $null) {
            $State.WeatherStatus = 'Unavailable'
            $State.WeatherMsg = 'Tap for weather'
            return
        }

        $url = "https://api.open-meteo.com/v1/forecast?latitude=$lat&longitude=$lon" +
               '&current=temperature_2m,relative_humidity_2m,apparent_temperature,weather_code,is_day,wind_speed_10m,wind_direction_10m' +
               '&timezone=auto'
        $wx = Invoke-RestMethod -Uri $url -TimeoutSec 7
        $cur = $wx.current
        if ($cur -eq $null) {
            $State.WeatherStatus = 'Unavailable'
            $State.WeatherMsg = 'Weather unavailable'
            return
        }

        $isDay = ([int]$cur.is_day -eq 1)
        $pair = Wmo ([int]$cur.weather_code) $isDay

        $State.Weather = @{
            TempC     = [double]$cur.temperature_2m
            ApparentC = if ($cur.apparent_temperature -ne $null) { [double]$cur.apparent_temperature } else { [double]$cur.temperature_2m }
            Humidity  = if ($cur.relative_humidity_2m -ne $null) { [int]$cur.relative_humidity_2m } else { -1 }
            WindKmh   = if ($cur.wind_speed_10m -ne $null) { [double]$cur.wind_speed_10m } else { -1.0 }
            WindDir   = if ($cur.wind_direction_10m -ne $null) { [int]$cur.wind_direction_10m } else { -1 }
            Code      = [int]$cur.weather_code
            IsDay     = $isDay
            Label     = $pair[0]
            Icon      = $pair[1]
            City      = $city
        }
        $State.WeatherStatus = 'Available'
        $State.LastWeatherMono = [double][System.Diagnostics.Stopwatch]::GetTimestamp() /
                                 [double][System.Diagnostics.Stopwatch]::Frequency * 1000.0
    } catch {
        $State.WeatherStatus = 'Unavailable'
        $State.WeatherMsg = 'Weather unavailable'
    } finally {
        $State.LastWeatherMono = [double][System.Diagnostics.Stopwatch]::GetTimestamp() /
                                 [double][System.Diagnostics.Stopwatch]::Frequency * 1000.0
        $State.WeatherFetching = $false
    }
}

# ==============================================================================
#  Background runner  (fire-and-forget runspaces; reaped by the UI timer)
# ==============================================================================
$script:Jobs = New-Object System.Collections.ArrayList

function Start-Bg([scriptblock]$Code, [object[]]$Arguments) {
    $ps = [System.Management.Automation.PowerShell]::Create()
    [void]$ps.AddScript($Code.ToString())
    foreach ($a in $Arguments) { [void]$ps.AddArgument($a) }
    $handle = $ps.BeginInvoke()
    [void]$script:Jobs.Add(@{ PS = $ps; Handle = $handle })
}

function Reap-Jobs {
    $done = @()
    foreach ($j in $script:Jobs) {
        if ($j.Handle.IsCompleted) { $done += $j }
    }
    foreach ($j in $done) {
        try { $j.PS.EndInvoke($j.Handle) } catch { }
        try { $j.PS.Dispose() } catch { }
        $script:Jobs.Remove($j)
    }
}

function Trigger-Sync {
    if ($State.Syncing) { return }
    $State.Syncing = $true
    if ($State.SyncStatus -ne 'Synced' -and $State.Sync -eq $null) { $State.SyncStatus = 'Syncing' }
    elseif ($State.SyncStatus -eq 'Idle') { $State.SyncStatus = 'Syncing' }
    else { $State.SyncStatus = 'Syncing' }
    $pref = (Get-ServerByName $Settings.server).Host
    $hosts = @(); foreach ($s in $Servers) { $hosts += $s.Host }
    Start-Bg $SyncBlock @($State, $pref, $hosts)
}

function Trigger-Weather {
    if ($State.WeatherFetching) { return }
    $State.WeatherFetching = $true
    if ($State.WeatherStatus -ne 'Available') { $State.WeatherStatus = 'Loading'; $State.WeatherMsg = 'Updating weather...' }
    Start-Bg $WeatherBlock @($State, [bool]$Settings.manualLocation, [double]$Settings.latitude, [double]$Settings.longitude)
}

# ==============================================================================
#  Formatting
# ==============================================================================
function Format-Clock([double]$timeMs, [bool]$use24) {
    $dto = [System.DateTimeOffset]::FromUnixTimeMilliseconds([long]$timeMs).ToLocalTime()
    $h24 = $dto.Hour; $m = $dto.Minute; $s = $dto.Second
    $ms = [int]([long]$timeMs % 1000L)
    if ($use24) {
        $main = '{0:D2}:{1:D2}:{2:D2}' -f $h24, $m, $s
        $ampm = ''
    } else {
        $h12 = (($h24 + 11) % 12) + 1
        $main = '{0}:{1:D2}:{2:D2}' -f $h12, $m, $s
        $ampm = if ($h24 -lt 12) { 'AM' } else { 'PM' }
    }
    $date = $dto.ToString('dddd, d MMM yyyy')
    $off = $dto.Offset
    $offStr = 'UTC' + ('{0}{1:D2}:{2:D2}' -f $(if ($off.Ticks -ge 0) { '+' } else { '-' }), [math]::Abs($off.Hours), [math]::Abs($off.Minutes))
    return @{
        Main = $main; Millis = ('.{0:D3}' -f $ms); AmPm = $ampm
        Date = $date; Zone = $offStr
    }
}

function Format-Offset([double]$ms) {
    $sign = if ($ms -ge 0) { '+' } else { '-' }
    $a = [math]::Abs($ms)
    if ($a -lt 1000) { return ('{0}{1} ms' -f $sign, [int][math]::Round($a)) }
    return ('{0}{1:N2} s' -f $sign, ($a / 1000.0))
}
function Format-Accuracy([double]$rtt) { return ('+/-{0} ms' -f [int]([math]::Abs($rtt) / 2)) }

function Short-Source([string]$h) {
    $x = $h -replace '^time\.', ''
    $x = ($x -split '\.')[0]
    if ($x.Length -gt 0) { return $x.Substring(0, 1).ToUpper() + $x.Substring(1) }
    return $h
}

function Format-Temp([double]$c, [bool]$f) {
    if ($f) { return ('{0}' -f [int][math]::Round($c * 9.0 / 5.0 + 32.0)) + [char]0x00B0 + 'F' }
    return ('{0}' -f [int][math]::Round($c)) + [char]0x00B0 + 'C'
}
function Format-Deg([double]$c, [bool]$f) {
    $v = if ($f) { $c * 9.0 / 5.0 + 32.0 } else { $c }
    return ('{0}' -f [int][math]::Round($v)) + [char]0x00B0
}
function Format-Wind([double]$kmh, [bool]$mph) {
    if ($mph) { return ('{0} mph' -f [int][math]::Round($kmh * 0.621371)) }
    return ('{0} km/h' -f [int][math]::Round($kmh))
}
function Dew-Point([double]$t, [int]$h) {
    if ($h -lt 1 -or $h -gt 100) { return $null }
    $a = 17.625; $b = 243.04
    $alpha = [math]::Log($h / 100.0) + $a * $t / ($b + $t)
    return $b * $alpha / ($a - $alpha)
}
$Compass = @('N','NNE','NE','ENE','E','ESE','SE','SSE','S','SSW','SW','WSW','W','WNW','NW','NNW')
function Compass-Dir([int]$deg) {
    $i = [int][math]::Round($deg / 22.5)
    return $Compass[(($i % 16) + 16) % 16]
}

# ==============================================================================
#  Fonts
# ==============================================================================
function New-Font([string]$family, [single]$size, [int]$style) {
    try { return New-Object System.Drawing.Font($family, $size, [System.Drawing.FontStyle]$style) }
    catch { return New-Object System.Drawing.Font('Segoe UI', $size, [System.Drawing.FontStyle]$style) }
}
$FontUiTiny    = New-Font 'Segoe UI' 8.0  1   # bold
$FontUiSmall   = New-Font 'Segoe UI' 9.0  0
$FontUiSmallSB = New-Font 'Segoe UI' 9.0  1
$FontUiMed     = New-Font 'Segoe UI' 10.5 0
$FontUiMedSB   = New-Font 'Segoe UI' 11.0 1
$FontWeatherSB = New-Font 'Segoe UI Semibold' 12.5 0

# Face fonts are rebuilt on resize.
$script:FaceDiaFactor = 0.90
$script:FaceFonts = $null
$script:FaceFontSize = -1
function Rebuild-FaceFonts([int]$w, [int]$h) {
    $d = [math]::Min($w, $h)
    if ($d -eq $script:FaceFontSize) { return }
    $script:FaceFontSize = $d
    if ($script:FaceFonts) {
        foreach ($k in $script:FaceFonts.Keys) { try { $script:FaceFonts[$k].Dispose() } catch { } }
    }
    $dia = $d * $script:FaceDiaFactor
    $timeSize = [math]::Max(22.0, [math]::Min(80.0, $d * 0.165))

    # Shrink to fit so "HH:MM:SS" + ".mmm" always sits well inside the ring.
    $trial = New-Font 'Segoe UI Light' $timeSize 0
    $mainW = $script:MeasureGfx.MeasureString('00:00:00', $trial).Width
    $trial.Dispose()
    $budget = $dia * 0.66
    if ($mainW -gt $budget) { $timeSize = $timeSize * $budget / $mainW }

    $script:FaceFonts = @{
        Time   = (New-Font 'Segoe UI Light' $timeSize 0)
        Millis = (New-Font 'Segoe UI' ($timeSize * 0.26) 0)
        AmPm   = (New-Font 'Segoe UI Semibold' ($timeSize * 0.20) 0)
        Date   = (New-Font 'Segoe UI' ([math]::Max(10.0, $d * 0.036)) 0)
        Zone   = (New-Font 'Segoe UI' ([math]::Max(9.0,  $d * 0.031)) 0)
    }
}

# ==============================================================================
#  Weather glyph (compact GDI vector, mirrors the app's condition icons)
# ==============================================================================
function Draw-WeatherGlyph($g, [string]$kind, [single]$cx, [single]$cy, [single]$r, $color) {
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $pen = New-Object System.Drawing.Pen($color, [math]::Max(1.5, $r * 0.16))
    $pen.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
    $pen.EndCap = [System.Drawing.Drawing2D.LineCap]::Round
    $brush = New-Object System.Drawing.SolidBrush($color)
    try {
        switch ($kind) {
            'SUN' {
                $cr = $r * 0.5
                $g.FillEllipse($brush, $cx - $cr, $cy - $cr, $cr * 2, $cr * 2)
                for ($a = 0; $a -lt 360; $a += 45) {
                    $rad = [math]::PI * $a / 180.0
                    $x1 = $cx + [math]::Cos($rad) * ($r * 0.72); $y1 = $cy + [math]::Sin($rad) * ($r * 0.72)
                    $x2 = $cx + [math]::Cos($rad) * ($r * 1.0);  $y2 = $cy + [math]::Sin($rad) * ($r * 1.0)
                    $g.DrawLine($pen, $x1, $y1, $x2, $y2)
                }
            }
            'MOON' {
                $path = New-Object System.Drawing.Drawing2D.GraphicsPath
                $path.AddEllipse($cx - $r * 0.7, $cy - $r * 0.7, $r * 1.4, $r * 1.4)
                $reg = New-Object System.Drawing.Region($path)
                $cut = New-Object System.Drawing.Drawing2D.GraphicsPath
                $cut.AddEllipse($cx - $r * 0.25, $cy - $r * 0.85, $r * 1.4, $r * 1.4)
                $reg.Exclude($cut)
                $g.FillRegion($brush, $reg)
                $reg.Dispose(); $path.Dispose(); $cut.Dispose()
            }
            'CLOUD' { Draw-Cloud $g $brush $cx $cy $r }
            'FOG'   { Draw-Cloud $g $brush $cx $cy $r }
            'RAIN'  {
                Draw-Cloud $g $brush ($cx) ($cy - $r * 0.25) ($r * 0.85)
                for ($i = -1; $i -le 1; $i++) {
                    $x = $cx + $i * $r * 0.4
                    $g.DrawLine($pen, $x, $cy + $r * 0.5, $x - $r * 0.15, $cy + $r * 0.95)
                }
            }
            'SNOW' {
                for ($a = 0; $a -lt 180; $a += 60) {
                    $rad = [math]::PI * $a / 180.0
                    $g.DrawLine($pen, $cx - [math]::Cos($rad) * $r, $cy - [math]::Sin($rad) * $r,
                                       $cx + [math]::Cos($rad) * $r, $cy + [math]::Sin($rad) * $r)
                }
            }
            'STORM' {
                Draw-Cloud $g $brush ($cx) ($cy - $r * 0.3) ($r * 0.85)
                $pts = @(
                    (New-Object System.Drawing.PointF(($cx + $r * 0.1), ($cy + $r * 0.1))),
                    (New-Object System.Drawing.PointF(($cx - $r * 0.35), ($cy + $r * 0.6))),
                    (New-Object System.Drawing.PointF(($cx),            ($cy + $r * 0.6))),
                    (New-Object System.Drawing.PointF(($cx - $r * 0.25), ($cy + $r * 1.05)))
                )
                $g.DrawLines($pen, $pts)
            }
            default { Draw-Cloud $g $brush $cx $cy $r }
        }
    } finally { $pen.Dispose(); $brush.Dispose() }
}
function Draw-Cloud($g, $brush, [single]$cx, [single]$cy, [single]$r) {
    $g.FillEllipse($brush, $cx - $r * 0.9, $cy - $r * 0.15, $r * 0.85, $r * 0.85)
    $g.FillEllipse($brush, $cx - $r * 0.35, $cy - $r * 0.55, $r * 0.95, $r * 0.95)
    $g.FillEllipse($brush, $cx + $r * 0.15, $cy - $r * 0.2, $r * 0.8, $r * 0.8)
    $g.FillRectangle($brush, $cx - $r * 0.6, $cy + $r * 0.2, $r * 1.35, $r * 0.5)
}

# ==============================================================================
#  Build the UI
# ==============================================================================
$form = New-Object System.Windows.Forms.Form
$form.Text = 'Atomic Clock'
$form.StartPosition = 'CenterScreen'
$form.Size = New-Object System.Drawing.Size(440, 820)
$form.MinimumSize = New-Object System.Drawing.Size(380, 660)
$form.BackColor = $Theme.Background
$form.ForeColor = $Theme.OnSurface
$form.Font = $FontUiSmall

$form.Add_HandleCreated({
    try {
        $val = 1
        [Native.Dwm]::DwmSetWindowAttribute($form.Handle, 20, [ref]$val, 4) | Out-Null
    } catch { }
})

# --- Top bar -------------------------------------------------------------------
$topBar = New-Object System.Windows.Forms.Panel
$topBar.Dock = 'Top'; $topBar.Height = 56; $topBar.BackColor = $Theme.Background
$form.Controls.Add($topBar)

$chip = New-Object System.Windows.Forms.Panel
$chip.Location = New-Object System.Drawing.Point(20, 12)
$chip.Size = New-Object System.Drawing.Size(190, 34)
$chip.BackColor = $Theme.Background
Enable-DoubleBuffer $chip
$topBar.Controls.Add($chip)

$btnSettings = New-Object System.Windows.Forms.Label
$btnSettings.Text = [char]0x2699   # gear
$btnSettings.Font = New-Font 'Segoe UI' 16.0 0
$btnSettings.ForeColor = $Theme.OnSurfaceVariant
$btnSettings.AutoSize = $false
$btnSettings.TextAlign = 'MiddleCenter'
$btnSettings.Size = New-Object System.Drawing.Size(40, 40)
$btnSettings.Cursor = 'Hand'
$topBar.Controls.Add($btnSettings)
$topBar.Add_Resize({ $btnSettings.Location = New-Object System.Drawing.Point(($topBar.Width - 56), 8) })
$btnSettings.Location = New-Object System.Drawing.Point(($topBar.Width - 56), 8)

# --- Bottom panel (weather + stats + resync) -----------------------------------
$bottom = New-Object System.Windows.Forms.Panel
$bottom.Dock = 'Bottom'; $bottom.Height = 230; $bottom.BackColor = $Theme.Background
$form.Controls.Add($bottom)

$weather = New-Object System.Windows.Forms.Panel
$weather.Location = New-Object System.Drawing.Point(0, 0)
$weather.Size = New-Object System.Drawing.Size($bottom.ClientSize.Width, 84)
$weather.Anchor = 'Top,Left,Right'
$weather.BackColor = $Theme.Background
$weather.Cursor = 'Hand'
Enable-DoubleBuffer $weather
$bottom.Controls.Add($weather)

$cardsHost = New-Object System.Windows.Forms.TableLayoutPanel
$cardsHost.Location = New-Object System.Drawing.Point(0, 86)
$cardsHost.Size = New-Object System.Drawing.Size($bottom.ClientSize.Width, 78)
$cardsHost.Anchor = 'Top,Left,Right'
$cardsHost.ColumnCount = 3; $cardsHost.RowCount = 1
$cardsHost.BackColor = $Theme.Background
$cardsHost.Padding = New-Object System.Windows.Forms.Padding(20, 0, 20, 0)
for ($i = 0; $i -lt 3; $i++) {
    [void]$cardsHost.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 33.33)))
}
$bottom.Controls.Add($cardsHost)

$script:Cards = @()
$cardDefs = @(
    @{ Label = 'Drift';    Accent = $Theme.Blue }
    @{ Label = 'Accuracy'; Accent = $Theme.Teal }
    @{ Label = 'Source';   Accent = $Theme.Violet }
)
foreach ($def in $cardDefs) {
    $card = New-Object System.Windows.Forms.Panel
    $card.Dock = 'Fill'
    $card.Margin = New-Object System.Windows.Forms.Padding(6, 4, 6, 4)
    $card.BackColor = $Theme.Background
    Enable-DoubleBuffer $card
    $card | Add-Member -NotePropertyName CardLabel -NotePropertyValue $def.Label
    $card | Add-Member -NotePropertyName CardAccent -NotePropertyValue $def.Accent
    $card | Add-Member -NotePropertyName CardValue -NotePropertyValue '--'
    $card.Add_Paint({
        param($s, $e)
        $g = $e.Graphics
        $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $path = New-RoundRectPath 0.5 0.5 ($s.Width - 2) ($s.Height - 2) 16
        $bg = New-Object System.Drawing.SolidBrush($Theme.Surface)
        $g.FillPath($bg, $path); $bg.Dispose()
        $border = New-Object System.Drawing.Pen((CA 60 $Theme.SurfaceHigh), 1)
        $g.DrawPath($border, $path); $border.Dispose(); $path.Dispose()
        # accent tick before the label
        $tick = New-Object System.Drawing.SolidBrush($s.CardAccent)
        $tp = New-RoundRectPath 14 14 3 11 1.5
        $g.FillPath($tick, $tp); $tp.Dispose(); $tick.Dispose()
        $lblBrush = New-Object System.Drawing.SolidBrush($Theme.OnSurfaceVariant)
        $g.DrawString($s.CardLabel.ToUpper(), $FontUiTiny, $lblBrush, 23, 13)
        $lblBrush.Dispose()
        $valBrush = New-Object System.Drawing.SolidBrush($s.CardAccent)
        $g.DrawString($s.CardValue, $FontUiMedSB, $valBrush, 14, 33)
        $valBrush.Dispose()
    })
    [void]$cardsHost.Controls.Add($card)
    $script:Cards += $card
}

$resync = New-Object System.Windows.Forms.Label
$resync.Text = [char]0x21BB   # refresh arrow
$resync.Font = New-Font 'Segoe UI' 17.0 0
$resync.ForeColor = $Accent
$resync.BackColor = $Theme.SurfaceHigh
$resync.TextAlign = 'MiddleCenter'
$resync.Size = New-Object System.Drawing.Size(52, 52)
$resync.Cursor = 'Hand'
$rPath = New-RoundRectPath 0 0 52 52 26
$resync.Region = New-Object System.Drawing.Region($rPath)
$bottom.Add_Resize({ $resync.Location = New-Object System.Drawing.Point((($bottom.Width - 52) / 2), ($bottom.Height - 64)) })
$bottom.Controls.Add($resync)
$resync.BringToFront()
$resync.Location = New-Object System.Drawing.Point((($bottom.Width - 52) / 2), ($bottom.Height - 64))

# --- Clock face (center, fills) ------------------------------------------------
$face = New-Object System.Windows.Forms.Panel
$face.Dock = 'Fill'; $face.BackColor = $Theme.Background
Enable-DoubleBuffer $face
$form.Controls.Add($face)
$face.BringToFront()

# State the paint handlers read from
$script:NowMs = (Get-MonoMs)
$script:Frac = 0.0
$script:Parts = @{ Main = '--:--:--'; Millis = ''; AmPm = ''; Date = ''; Zone = '' }
$script:TempRect = New-Object System.Drawing.RectangleF(0, 0, 0, 0)

$face.Add_Paint({
    param($s, $e)
    $g = $e.Graphics
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::ClearTypeGridFit
    $w = $s.Width; $h = $s.Height
    Rebuild-FaceFonts $w $h
    $cx = $w / 2.0; $cy = $h / 2.0
    $dia = [math]::Min($w, $h) * $script:FaceDiaFactor
    $rad = $dia / 2.0
    $stroke = [math]::Max(4.0, $dia * 0.018)
    $rect = New-Object System.Drawing.RectangleF(($cx - $rad), ($cy - $rad), ($rad * 2), ($rad * 2))

    # Soft radial glow behind the dial for depth
    $vR = $rad * 1.08
    $vpath = New-Object System.Drawing.Drawing2D.GraphicsPath
    $vpath.AddEllipse(($cx - $vR), ($cy - $vR), ($vR * 2), ($vR * 2))
    $pgb = New-Object System.Drawing.Drawing2D.PathGradientBrush($vpath)
    $pgb.CenterPoint = New-Object System.Drawing.PointF($cx, $cy)
    $pgb.CenterColor = (CA 22 $Theme.Teal)
    $pgb.SurroundColors = @([System.Drawing.Color]::FromArgb(0, 5, 7, 13))
    $g.FillPath($pgb, $vpath)
    $pgb.Dispose(); $vpath.Dispose()

    # Faint full track
    $trackPen = New-Object System.Drawing.Pen((CA 22 $Theme.OnSurface), $stroke)
    $trackPen.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
    $trackPen.EndCap = [System.Drawing.Drawing2D.LineCap]::Round
    $g.DrawArc($trackPen, $rect, 0, 360)
    $trackPen.Dispose()

    # Bright sweeping second arc, with a soft bloom and a glowing leading dot
    $sweep = 360.0 * [math]::Max(0.0, [math]::Min(1.0, $script:Frac))
    if ($sweep -gt 0.01) {
        $bloomPen = New-Object System.Drawing.Pen((CA 34 $Theme.Teal), ($stroke * 2.6))
        $bloomPen.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
        $bloomPen.EndCap = [System.Drawing.Drawing2D.LineCap]::Round
        $g.DrawArc($bloomPen, $rect, -90, $sweep)
        $bloomPen.Dispose()

        $arcPen = New-Object System.Drawing.Pen($Accent, $stroke)
        $arcPen.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
        $arcPen.EndCap = [System.Drawing.Drawing2D.LineCap]::Round
        $g.DrawArc($arcPen, $rect, -90, $sweep)
        $arcPen.Dispose()

        if ($sweep -gt 3.0) {
            $tipRad = [math]::PI * (-90.0 + $sweep) / 180.0
            $tx = $cx + [math]::Cos($tipRad) * $rad
            $ty = $cy + [math]::Sin($tipRad) * $rad
            $halo = New-Object System.Drawing.SolidBrush((CA 70 $Theme.Teal))
            $hr = $stroke * 1.9
            $g.FillEllipse($halo, ($tx - $hr), ($ty - $hr), ($hr * 2), ($hr * 2)); $halo.Dispose()
            $core = New-Object System.Drawing.SolidBrush($Theme.Teal)
            $cr = $stroke * 0.95
            $g.FillEllipse($core, ($tx - $cr), ($ty - $cr), ($cr * 2), ($cr * 2)); $core.Dispose()
        }
    }

    # --- Centered text stack ---
    $ff = $script:FaceFonts
    $p = $script:Parts

    $mainSize = $g.MeasureString($p.Main, $ff.Time)
    $milSize = $g.MeasureString('.000', $ff.Millis)
    $hasMil = ($p.Millis -ne '')
    $milW = if ($hasMil) { $milSize.Width } else { 0 }

    # vertical layout
    $ampmH = if ($p.AmPm -ne '') { $g.MeasureString($p.AmPm, $ff.AmPm).Height } else { 0 }
    $dateH = $g.MeasureString('Xy', $ff.Date).Height
    $zoneH = $g.MeasureString('Xy', $ff.Zone).Height
    $gap1 = $dia * 0.028
    $total = $ampmH + $mainSize.Height + $gap1 + $dateH + 4 + $zoneH
    $y = $cy - $total / 2.0

    $onBrush = New-Object System.Drawing.SolidBrush($Theme.OnSurface)
    $accBrush = New-Object System.Drawing.SolidBrush($Accent)
    $subBrush = New-Object System.Drawing.SolidBrush($Theme.OnSurfaceVariant)
    try {
        if ($p.AmPm -ne '') {
            $g.DrawString($p.AmPm, $ff.AmPm, $accBrush, $cx, ($y + $ampmH / 2.0), $SfCenterMid)
            $y += $ampmH
        }
        # main time centered; millis reserved to the right so it never shifts the time
        $milGap = $dia * 0.010
        $blockW = $mainSize.Width + $milW + $milGap
        $mainLeft = $cx - $blockW / 2.0
        $g.DrawString($p.Main, $ff.Time, $onBrush, $mainLeft, $y)
        if ($hasMil) {
            $milY = $y + $mainSize.Height - $milSize.Height - ($mainSize.Height * 0.16)
            $g.DrawString($p.Millis, $ff.Millis, $accBrush, ($mainLeft + $mainSize.Width + $milGap), $milY)
        }
        $y += $mainSize.Height + $gap1
        $g.DrawString($p.Date, $ff.Date, $subBrush, $cx, ($y + $dateH / 2.0), $SfCenterMid)
        $y += $dateH + 4
        $g.DrawString($p.Zone, $ff.Zone, $subBrush, $cx, ($y + $zoneH / 2.0), $SfCenterMid)
    } finally {
        $onBrush.Dispose(); $accBrush.Dispose(); $subBrush.Dispose()
    }
})

# --- Status chip paint ---------------------------------------------------------
function Get-ChipInfo {
    $kind = $State.SyncStatus
    $label = switch ($kind) {
        'Idle'    { 'Starting...' }
        'Syncing' { 'Syncing...' }
        'Synced'  { 'Atomic time locked' }
        'Failed'  { if ($State.Sync -ne $null) { 'Offline - last sync' } else { 'No connection' } }
        default   { '' }
    }
    $color = switch ($kind) {
        'Synced'  { $Theme.Teal }
        'Syncing' { $Theme.Amber }
        'Idle'    { $Theme.Amber }
        default   { $Theme.Red }
    }
    return @{ Label = $label; Color = $color }
}

$chip.Add_Paint({
    param($s, $e)
    $g = $e.Graphics
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::ClearTypeGridFit
    $info = Get-ChipInfo
    $label = $info.Label; $color = $info.Color
    $path = New-RoundRectPath 0 0 ($s.Width - 1) ($s.Height - 1) ($s.Height / 2.0)
    $bg = New-Object System.Drawing.SolidBrush((CA 31 $color))
    $g.FillPath($bg, $path); $bg.Dispose(); $path.Dispose()
    $dot = New-Object System.Drawing.SolidBrush($color)
    $g.FillEllipse($dot, 14, ($s.Height / 2 - 4), 8, 8); $dot.Dispose()
    $tb = New-Object System.Drawing.SolidBrush($color)
    $g.DrawString($label, $FontUiSmallSB, $tb, 28, ($s.Height / 2.0), $SfLineMid)
    $tb.Dispose()
})

# --- Weather strip paint -------------------------------------------------------
$weather.Add_Paint({
    param($s, $e)
    $g = $e.Graphics
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::ClearTypeGridFit
    $cx = $s.Width / 2.0
    $sub = (CA 217 $Theme.OnSurfaceVariant)

    if ($State.WeatherStatus -ne 'Available' -or $State.Weather -eq $null) {
        $msg = $State.WeatherMsg
        $b = New-Object System.Drawing.SolidBrush($Theme.OnSurfaceVariant)
        $g.DrawString($msg, $FontUiMed, $b, $cx, 30, $SfCenterTop); $b.Dispose()
        return
    }

    $wx = $State.Weather
    $f = [bool]$Settings.fahrenheit
    $mph = [bool]$Settings.windMph

    # Headline: glyph + temp (clickable) + label
    $tempStr = Format-Temp $wx.TempC $f
    $labelStr = '  ' + [char]0x00B7 + ' ' + $wx.Label
    $tempSize = $g.MeasureString($tempStr, $FontWeatherSB)
    $labelSize = $g.MeasureString($labelStr, $FontUiMed)
    $glyphR = 11.0
    $glyphGap = 10.0
    $headW = ($glyphR * 2) + $glyphGap + $tempSize.Width + $labelSize.Width
    $startX = $cx - $headW / 2.0
    $hy = 22.0

    $glyphColor = switch ($wx.Icon) {
        'SUN'   { $Theme.Amber }
        'MOON'  { $Theme.Blue }
        'CLOUD' { $Theme.Teal }
        'FOG'   { $Theme.Teal }
        'RAIN'  { $Theme.Blue }
        'SNOW'  { $Theme.Teal }
        'STORM' { $Theme.Violet }
        default { $Theme.Teal }
    }
    Draw-WeatherGlyph $g $wx.Icon ($startX + $glyphR) $hy $glyphR $glyphColor

    $tx = $startX + ($glyphR * 2) + $glyphGap
    $tBrush = New-Object System.Drawing.SolidBrush($Theme.OnSurface)
    $g.DrawString($tempStr, $FontWeatherSB, $tBrush, $tx, ($hy - $tempSize.Height / 2.0)); $tBrush.Dispose()
    $script:TempRect = New-Object System.Drawing.RectangleF(($tx - 4), ($hy - $tempSize.Height / 2.0), ($tempSize.Width + 8), $tempSize.Height)
    $lBrush = New-Object System.Drawing.SolidBrush($Theme.OnSurfaceVariant)
    $g.DrawString($labelStr, $FontUiMed, $lBrush, ($tx + $tempSize.Width), ($hy - $labelSize.Height / 2.0)); $lBrush.Dispose()

    # Metrics line
    $parts = @()
    if ([math]::Abs($wx.ApparentC - $wx.TempC) -ge 1.0) { $parts += ('Feels ' + (Format-Deg $wx.ApparentC $f)) }
    if ($wx.Humidity -ge 0 -and $wx.Humidity -le 100) { $parts += ("$($wx.Humidity)%") }
    if ($wx.WindKmh -ge 0) {
        $wtxt = Format-Wind $wx.WindKmh $mph
        if ($wx.WindDir -ge 0 -and $wx.WindDir -le 360) { $wtxt += ' ' + (Compass-Dir $wx.WindDir) }
        $parts += $wtxt
    }
    $dp = Dew-Point $wx.TempC $wx.Humidity
    if ($dp -ne $null) { $parts += ('Dew ' + (Format-Deg $dp $f)) }
    $metrics = ($parts -join ('   ' + [char]0x00B7 + '   '))
    $mBrush = New-Object System.Drawing.SolidBrush($sub)
    $g.DrawString($metrics, $FontUiSmall, $mBrush, $cx, 44, $SfCenterTop); $mBrush.Dispose()

    if ($wx.City) {
        $cBrush = New-Object System.Drawing.SolidBrush((CA 160 $Theme.OnSurfaceVariant))
        $g.DrawString($wx.City, $FontUiSmall, $cBrush, $cx, 62, $SfCenterTop); $cBrush.Dispose()
    }
})

# ==============================================================================
#  Interactions
# ==============================================================================
$resync.Add_Click({ Trigger-Sync })

$weather.Add_MouseClick({
    param($s, $e)
    if ($State.WeatherStatus -eq 'Available' -and $script:TempRect.Contains($e.X, $e.Y)) {
        $Settings.fahrenheit = -not $Settings.fahrenheit
        Save-Settings $Settings
        $weather.Invalidate()
    } elseif ($State.WeatherStatus -ne 'Available') {
        Trigger-Weather
    }
})

# --- Settings dialog -----------------------------------------------------------
function Show-SettingsDialog {
    $dlg = New-Object System.Windows.Forms.Form
    $dlg.Text = 'Settings'
    $dlg.FormBorderStyle = 'FixedDialog'
    $dlg.StartPosition = 'CenterParent'
    $dlg.Size = New-Object System.Drawing.Size(380, 540)
    $dlg.BackColor = $Theme.Surface
    $dlg.ForeColor = $Theme.OnSurface
    $dlg.MaximizeBox = $false; $dlg.MinimizeBox = $false
    $dlg.Font = $FontUiMed
    $dlg.Add_HandleCreated({ try { $v = 1; [Native.Dwm]::DwmSetWindowAttribute($dlg.Handle, 20, [ref]$v, 4) | Out-Null } catch { } })

    function Add-Toggle([string]$text, [string]$prop) {
        $lbl = New-Object System.Windows.Forms.Label
        $lbl.Text = $text; $lbl.AutoSize = $true
        $lbl.Location = New-Object System.Drawing.Point(24, ($script:dy + 4))
        $lbl.ForeColor = $Theme.OnSurface
        $dlg.Controls.Add($lbl)
        $cb = New-Object System.Windows.Forms.CheckBox
        $cb.Checked = [bool]$Settings.$prop
        $cb.Location = New-Object System.Drawing.Point(300, $script:dy)
        $cb.AutoSize = $true
        $cb.Add_CheckedChanged({ $Settings.$prop = $cb.Checked; Save-Settings $Settings }.GetNewClosure())
        $dlg.Controls.Add($cb)
        $script:dy += 40
    }
    $script:dy = 18

    Add-Toggle '24-hour clock' 'use24Hour'
    Add-Toggle 'Show milliseconds' 'showMilliseconds'

    # Temperature segment (manual, reliable)
    $lblT = New-Object System.Windows.Forms.Label
    $lblT.Text = 'Temperature'; $lblT.AutoSize = $true
    $lblT.Location = New-Object System.Drawing.Point(24, ($script:dy + 6)); $lblT.ForeColor = $Theme.OnSurface
    $dlg.Controls.Add($lblT)
    $tC = New-Object System.Windows.Forms.Button; $tC.Text = [char]0x00B0 + 'C'; $tC.FlatStyle = 'Flat'; $tC.Size = New-Object System.Drawing.Size(66, 30); $tC.Location = New-Object System.Drawing.Point(202, $script:dy); $tC.FlatAppearance.BorderSize = 0
    $tF = New-Object System.Windows.Forms.Button; $tF.Text = [char]0x00B0 + 'F'; $tF.FlatStyle = 'Flat'; $tF.Size = New-Object System.Drawing.Size(66, 30); $tF.Location = New-Object System.Drawing.Point(268, $script:dy); $tF.FlatAppearance.BorderSize = 0
    $paintT = {
        if ($Settings.fahrenheit) { $tF.BackColor = $Theme.Teal; $tF.ForeColor = (C 4 32 28); $tC.BackColor = $Theme.SurfaceHigh; $tC.ForeColor = $Theme.OnSurfaceVariant }
        else { $tC.BackColor = $Theme.Teal; $tC.ForeColor = (C 4 32 28); $tF.BackColor = $Theme.SurfaceHigh; $tF.ForeColor = $Theme.OnSurfaceVariant }
    }
    & $paintT
    $tC.Add_Click({ $Settings.fahrenheit = $false; Save-Settings $Settings; & $paintT; $weather.Invalidate() }.GetNewClosure())
    $tF.Add_Click({ $Settings.fahrenheit = $true;  Save-Settings $Settings; & $paintT; $weather.Invalidate() }.GetNewClosure())
    $dlg.Controls.Add($tC); $dlg.Controls.Add($tF)
    $script:dy += 42

    # Wind segment
    $lblW = New-Object System.Windows.Forms.Label
    $lblW.Text = 'Wind speed'; $lblW.AutoSize = $true
    $lblW.Location = New-Object System.Drawing.Point(24, ($script:dy + 6)); $lblW.ForeColor = $Theme.OnSurface
    $dlg.Controls.Add($lblW)
    $wK = New-Object System.Windows.Forms.Button; $wK.Text = 'km/h'; $wK.FlatStyle = 'Flat'; $wK.Size = New-Object System.Drawing.Size(66, 30); $wK.Location = New-Object System.Drawing.Point(202, $script:dy); $wK.FlatAppearance.BorderSize = 0
    $wM = New-Object System.Windows.Forms.Button; $wM.Text = 'mph'; $wM.FlatStyle = 'Flat'; $wM.Size = New-Object System.Drawing.Size(66, 30); $wM.Location = New-Object System.Drawing.Point(268, $script:dy); $wM.FlatAppearance.BorderSize = 0
    $paintW = {
        if ($Settings.windMph) { $wM.BackColor = $Theme.Teal; $wM.ForeColor = (C 4 32 28); $wK.BackColor = $Theme.SurfaceHigh; $wK.ForeColor = $Theme.OnSurfaceVariant }
        else { $wK.BackColor = $Theme.Teal; $wK.ForeColor = (C 4 32 28); $wM.BackColor = $Theme.SurfaceHigh; $wM.ForeColor = $Theme.OnSurfaceVariant }
    }
    & $paintW
    $wK.Add_Click({ $Settings.windMph = $false; Save-Settings $Settings; & $paintW; $weather.Invalidate() }.GetNewClosure())
    $wM.Add_Click({ $Settings.windMph = $true;  Save-Settings $Settings; & $paintW; $weather.Invalidate() }.GetNewClosure())
    $dlg.Controls.Add($wK); $dlg.Controls.Add($wM)
    $script:dy += 50

    # Time source
    $lblSrc = New-Object System.Windows.Forms.Label
    $lblSrc.Text = 'TIME SOURCE'; $lblSrc.AutoSize = $true; $lblSrc.Font = $FontUiSmallSB
    $lblSrc.ForeColor = $Theme.OnSurfaceVariant
    $lblSrc.Location = New-Object System.Drawing.Point(24, $script:dy)
    $dlg.Controls.Add($lblSrc)
    $script:dy += 26

    $combo = New-Object System.Windows.Forms.ComboBox
    $combo.DropDownStyle = 'DropDownList'
    $combo.FlatStyle = 'Flat'
    $combo.BackColor = $Theme.SurfaceHigh; $combo.ForeColor = $Theme.OnSurface
    $combo.Location = New-Object System.Drawing.Point(24, $script:dy)
    $combo.Size = New-Object System.Drawing.Size(310, 30)
    $selIndex = 0
    for ($i = 0; $i -lt $Servers.Count; $i++) {
        [void]$combo.Items.Add($Servers[$i].Display + '  (' + $Servers[$i].Host + ')')
        if ($Servers[$i].Name -eq $Settings.server) { $selIndex = $i }
    }
    $combo.SelectedIndex = $selIndex
    $combo.Add_SelectedIndexChanged({
        $Settings.server = $Servers[$combo.SelectedIndex].Name
        Save-Settings $Settings
        Trigger-Sync
    }.GetNewClosure())
    $dlg.Controls.Add($combo)
    $script:dy += 46

    # About button
    $aboutBtn = New-Object System.Windows.Forms.Button
    $aboutBtn.Text = 'About'
    $aboutBtn.FlatStyle = 'Flat'; $aboutBtn.FlatAppearance.BorderColor = $Theme.SurfaceHigh
    $aboutBtn.BackColor = $Theme.SurfaceHigh; $aboutBtn.ForeColor = $Theme.OnSurface
    $aboutBtn.Size = New-Object System.Drawing.Size(310, 36)
    $aboutBtn.Location = New-Object System.Drawing.Point(24, $script:dy)
    $aboutBtn.Add_Click({ $dlg.Close(); Show-AboutDialog })
    $dlg.Controls.Add($aboutBtn)

    [void]$dlg.ShowDialog($form)
}

function Show-AboutDialog {
    $dlg = New-Object System.Windows.Forms.Form
    $dlg.Text = 'About'
    $dlg.FormBorderStyle = 'FixedDialog'
    $dlg.StartPosition = 'CenterParent'
    $dlg.Size = New-Object System.Drawing.Size(380, 320)
    $dlg.BackColor = $Theme.Surface; $dlg.ForeColor = $Theme.OnSurface
    $dlg.MaximizeBox = $false; $dlg.MinimizeBox = $false
    $dlg.Add_HandleCreated({ try { $v = 1; [Native.Dwm]::DwmSetWindowAttribute($dlg.Handle, 20, [ref]$v, 4) | Out-Null } catch { } })

    $title = New-Object System.Windows.Forms.Label
    $title.Text = 'Atomic Clock'; $title.Font = New-Font 'Segoe UI Semibold' 16.0 0
    $title.ForeColor = $Theme.OnSurface; $title.AutoSize = $false; $title.TextAlign = 'MiddleCenter'
    $title.Size = New-Object System.Drawing.Size(360, 34); $title.Location = New-Object System.Drawing.Point(0, 20)
    $dlg.Controls.Add($title)

    $ver = New-Object System.Windows.Forms.Label
    $ver.Text = "Version $script:Version"; $ver.ForeColor = $Theme.OnSurfaceVariant
    $ver.AutoSize = $false; $ver.TextAlign = 'MiddleCenter'
    $ver.Size = New-Object System.Drawing.Size(360, 22); $ver.Location = New-Object System.Drawing.Point(0, 54)
    $dlg.Controls.Add($ver)

    $desc = New-Object System.Windows.Forms.Label
    $desc.Text = "Precise time synced over NTP, with live local weather." + [Environment]::NewLine + [Environment]::NewLine +
                 "Time   NTP - Google, Cloudflare, NTP Pool, Apple, NIST" + [Environment]::NewLine +
                 "Weather   Open-Meteo" + [Environment]::NewLine +
                 "Built by   typezero"
    $desc.ForeColor = $Theme.OnSurfaceVariant; $desc.AutoSize = $false; $desc.TextAlign = 'MiddleCenter'
    $desc.Size = New-Object System.Drawing.Size(340, 120); $desc.Location = New-Object System.Drawing.Point(20, 84)
    $dlg.Controls.Add($desc)

    $gh = New-Object System.Windows.Forms.Button
    $gh.Text = 'View on GitHub'; $gh.FlatStyle = 'Flat'
    $gh.BackColor = $Theme.SurfaceHigh; $gh.ForeColor = $Theme.Teal; $gh.FlatAppearance.BorderSize = 0
    $gh.Size = New-Object System.Drawing.Size(200, 34); $gh.Location = New-Object System.Drawing.Point(80, 220)
    $gh.Add_Click({ try { Start-Process $script:RepoUrl } catch { } })
    $dlg.Controls.Add($gh)

    [void]$dlg.ShowDialog($form)
}

$btnSettings.Add_Click({ Show-SettingsDialog })

# ==============================================================================
#  Corrected time + the render/scheduler timer
# ==============================================================================
function Get-CorrectedMs {
    $sync = $State.Sync
    if ($sync -eq $null) { return [double][System.DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds() }
    return $sync.NtpMs + ((Get-MonoMs) - $sync.RefMono)
}

$script:LastChipKey = ''
$script:LastCardKey = ''
$script:LastWeatherKey = ''

$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 30
$timer.Add_Tick({
    Reap-Jobs

    # Drive the smooth clock
    $now = Get-CorrectedMs
    $script:NowMs = $now
    $script:Frac = ([long]$now % 1000L) / 1000.0
    $script:Parts = Format-Clock $now ([bool]$Settings.use24Hour)
    if (-not $Settings.showMilliseconds) { $script:Parts.Millis = '' }
    $face.Invalidate()

    # Chip refresh only on change
    $chipKey = "$($State.SyncStatus)|$([bool]($State.Sync -ne $null))"
    if ($chipKey -ne $script:LastChipKey) {
        $script:LastChipKey = $chipKey
        $info = Get-ChipInfo
        $tw = $script:MeasureGfx.MeasureString($info.Label, $FontUiSmallSB).Width
        $chip.Width = [int]($tw + 44)
        $chip.Invalidate()
    }

    # Cards refresh only on change
    $sync = $State.Sync
    if ($sync -ne $null) {
        $drift = Format-Offset $sync.Offset
        $acc = Format-Accuracy $sync.Rtt
        $src = (Short-Source $sync.Server) + ' - S' + $sync.Stratum
    } else { $drift = '--'; $acc = '--'; $src = '--' }
    $cardKey = "$drift|$acc|$src"
    if ($cardKey -ne $script:LastCardKey) {
        $script:LastCardKey = $cardKey
        $script:Cards[0].CardValue = $drift
        $script:Cards[1].CardValue = $acc
        $script:Cards[2].CardValue = $src
        foreach ($c in $script:Cards) { $c.Invalidate() }
    }

    # Weather refresh only on change
    $wx = $State.Weather
    $wKey = "$($State.WeatherStatus)|$($State.WeatherMsg)|$($Settings.fahrenheit)|$($Settings.windMph)|"
    if ($wx -ne $null) { $wKey += "$($wx.TempC)|$($wx.Label)|$($wx.City)|$($wx.Humidity)|$($wx.WindKmh)|$($wx.WindDir)" }
    if ($wKey -ne $script:LastWeatherKey) { $script:LastWeatherKey = $wKey; $weather.Invalidate() }

    # Schedulers
    $mono = Get-MonoMs
    if (-not $State.Syncing -and ($mono - $State.LastSyncMono) -gt (10 * 60 * 1000)) { Trigger-Sync }
    if (-not $State.WeatherFetching -and ($mono - $State.LastWeatherMono) -gt (15 * 60 * 1000)) { Trigger-Weather }
})

# ==============================================================================
#  Launch
# ==============================================================================
$form.Add_Shown({
    Trigger-Sync
    Trigger-Weather
    $timer.Start()
})
$form.Add_FormClosed({
    $timer.Stop()
    foreach ($j in $script:Jobs) { try { $j.PS.Dispose() } catch { } }
})

[System.Windows.Forms.Application]::Run($form)
