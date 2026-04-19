#--------------------------------------------
# file:     network-menu.ps1
# author:   Mike Redd
# version:  2.4
# created:  2026-03-30
# updated:  2026-04-01
# desc:     Network tools menu for diagnostics, connectivity checks, and adapter management
#--------------------------------------------

# ── Load custom UI ────────────────────────────────────────────
$uiPath = Join-Path $PSProfileDir "ui.ps1"
if (Test-Path $uiPath) {
    try {
        . $uiPath
    } catch {
        Write-Host "Failed to load ui.ps1: $($_.Exception.Message)"
        return
    }
} else {
    Write-Host "Missing ui.ps1: $uiPath"
    return
}

# ── Load core helper ──────────────────────────────────────────
$corePath = Join-Path $PSProfileDir "core.ps1"
if (Test-Path $corePath) {
    try {
        . $corePath
    } catch {
        Write-Host "Failed to load core.ps1: $($_.Exception.Message)"
        Pause-UiReturn "Press Enter to return..."
        return
    }
} else {
    Write-Host "Missing core.ps1: $corePath"
    Pause-UiReturn "Press Enter to return..."
    return
}

$ScriptName    = "Network Menu"
$ScriptVersion = "2.4"
$ScriptAuthor  = "Mike Redd"

# ── Helpers ───────────────────────────────────────────────────
function Row($label, $value, $color = $global:UI_GRN) {
    Write-Host "  $($global:UI_DIM)$($label.PadRight(20))$($global:UI_R)  ${color}$value$($global:UI_R)"
}

function SectionHead($title) {
    Write-UiBlankLine
    Write-Host "  $($global:UI_MAG)$($global:UI_B)>> $title$($global:UI_R)"
    Write-Host "  $($global:UI_GRY)  ----------------------------------------------------$($global:UI_R)"
}

# ── Pause ─────────────────────────────────────────────────────
function Pause-Script {
    Pause-Core "Press Enter to return to menu..."
}

# ── Confirm ───────────────────────────────────────────────────
function Confirm-Action($message) {
    return (Confirm-Core $message)
}

# ── Ping using ping.exe — consistent across all PS versions ──
function Test-PingHost($target, $count = 1) {
    $result = ping.exe -n $count -w 1000 $target 2>$null
    $ok     = $result -match "Reply from"
    $rtt    = $null
    if ($ok) {
        $match = $result | Select-String "time[=<](\d+)ms"
        if ($match) { $rtt = [int]($match.Matches[0].Groups[1].Value) }
    }
    return [PSCustomObject]@{ Success = $ok; RTT = $rtt }
}

# ── Status badge ──────────────────────────────────────────────
function Status($ok, $trueStr = "OK", $falseStr = "FAIL") {
    if ($ok) { return "$($global:UI_GRN)$($global:UI_B)  $trueStr  $($global:UI_R)" }
    else     { return "$($global:UI_RED)$($global:UI_B)  $falseStr $($global:UI_R)" }
}

# ── Header & Menu ────────────────────────────────────────────
function Show-Header {
    Clear-UiScreen
    $w = Get-UiBoxWidth -MaxWidth 52 -MinWidth 40

    Write-UiHeader -Title $ScriptName -Subtitle "v$ScriptVersion  by $ScriptAuthor" -Width $w
    Write-UiRow "User" "$env:USERNAME@$env:COMPUTERNAME"
    Write-UiBlankLine
}

function Show-Menu {
    Write-UiDivider
    Write-Host "  $($global:UI_GRN)  1)$($global:UI_R)  Quick Network Health Check"
    Write-Host "  $($global:UI_GRN)  2)$($global:UI_R)  Network Info"
    Write-Host "  $($global:UI_GRN)  3)$($global:UI_R)  Wi-Fi Details"
    Write-UiDivider
    Write-Host "  $($global:UI_GRN)  4)$($global:UI_R)  Ping Host List"
    Write-Host "  $($global:UI_GRN)  5)$($global:UI_R)  Test Port"
    Write-Host "  $($global:UI_GRN)  6)$($global:UI_R)  DNS Lookup"
    Write-Host "  $($global:UI_GRN)  7)$($global:UI_R)  Traceroute"
    Write-Host "  $($global:UI_GRN)  8)$($global:UI_R)  Public IP Lookup"
    Write-UiDivider
    Write-Host "  $($global:UI_GRN)  9)$($global:UI_R)  Active TCP Connections"
    Write-Host "  $($global:UI_GRN) 10)$($global:UI_R)  Listening Ports"
    Write-Host "  $($global:UI_GRN) 11)$($global:UI_R)  Find Process on Port"
    Write-UiDivider
    Write-Host "  $($global:UI_GRN) 12)$($global:UI_R)  Watch Connectivity"
    Write-Host "  $($global:UI_YLW) 13)$($global:UI_R)  Adapter Enable / Disable"
    Write-Host "  $($global:UI_RED) 14)$($global:UI_R)  Network Reset"
    Write-UiDivider
    Write-Host "  $($global:UI_GRY)  Q)$($global:UI_R)  Quit"
    Write-UiBlankLine
}

# ── 1 — Quick Health Check ───────────────────────────────────
function Invoke-QuickHealthCheck {
    Show-Header
    $w = Get-UiBoxWidth -MaxWidth 52 -MinWidth 40
    Write-UiBoxTitle -Title "QUICK NETWORK HEALTH CHECK" -Width $w

    try {
        # Adapters
        SectionHead "ACTIVE ADAPTERS"
        $activeAdapters = Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq "Up" }
        if ($activeAdapters) {
            foreach ($a in $activeAdapters) {
                Write-Host "  $($global:UI_GRN)  * $($a.Name)$($global:UI_R)  $($global:UI_GRY)$($a.LinkSpeed)  MAC: $($a.MacAddress)$($global:UI_R)"
            }
        } else {
            Write-Host "  $($global:UI_RED)  No active adapters found.$($global:UI_R)"
        }

        # IPs
        SectionHead "IPv4 ADDRESSES"
        $ipv4List = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
            Where-Object { $_.IPAddress -notlike "127.*" -and $_.IPAddress -notlike "169.254.*" }
        if ($ipv4List) {
            foreach ($ip in $ipv4List) {
                Row "$($ip.InterfaceAlias)" "$($ip.IPAddress)/$($ip.PrefixLength)"
            }
        } else {
            Write-Host "  $($global:UI_RED)  No routable IPv4 addresses.$($global:UI_R)"
        }

        # Gateway
        SectionHead "GATEWAY & CONNECTIVITY"
        $routes  = Get-NetRoute -DestinationPrefix "0.0.0.0/0" -ErrorAction SilentlyContinue | Sort-Object RouteMetric
        $gateway = if ($routes) { $routes[0].NextHop } else { $null }

        if ($gateway) {
            $gwPing = Test-PingHost $gateway
            $rttStr = if ($gwPing.RTT) { "  $($global:UI_GRY)($($gwPing.RTT)ms)$($global:UI_R)" } else { "" }
            Write-Host "  $($global:UI_DIM)$($global:UI_WHT)Gateway            $($global:UI_R)  $($global:UI_GRN)$gateway$($global:UI_R)  $(Status $gwPing.Success 'Reachable' 'Unreachable')$rttStr"
        } else {
            Write-Host "  $($global:UI_DIM)$($global:UI_WHT)Gateway            $($global:UI_R)  $(Status $false 'OK' 'No gateway found')"
        }

        $intPing = Test-PingHost "1.1.1.1"
        $rttStr  = if ($intPing.RTT) { "  $($global:UI_GRY)($($intPing.RTT)ms)$($global:UI_R)" } else { "" }
        Write-Host "  $($global:UI_DIM)$($global:UI_WHT)Internet (1.1.1.1)  $($global:UI_R)  $(Status $intPing.Success 'Reachable' 'Unreachable')$rttStr"

        # DNS
        try {
            $dnsTest = Resolve-DnsName "cloudflare.com" -ErrorAction Stop
            $dnsOk   = $true
        } catch { $dnsOk = $false }
        Write-Host "  $($global:UI_DIM)$($global:UI_WHT)DNS Resolution     $($global:UI_R)  $(Status $dnsOk 'Working' 'Failed')"

        # DNS servers
        SectionHead "DNS SERVERS"
        $dnsInfo = Get-DnsClientServerAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue
        if ($dnsInfo) {
            foreach ($dns in $dnsInfo) {
                if ($dns.ServerAddresses) {
                    Row "$($dns.InterfaceAlias)" ($dns.ServerAddresses -join "  ")
                }
            }
        }

        # Optional SSH test
        Write-UiBlankLine
        Write-Host -NoNewline "  $($global:UI_GRY)Optional SSH host to test (Enter to skip): $($global:UI_R)"
        $sshHost = Read-Host
        if ($sshHost) {
            try {
                $sshTest = Test-NetConnection -ComputerName $sshHost -Port 22 -WarningAction SilentlyContinue
                Write-Host "  $($global:UI_DIM)$($global:UI_WHT)SSH $sshHost :22   $($global:UI_R)  $(Status $sshTest.TcpTestSucceeded 'Open' 'Closed')"
            } catch {
                Write-Host "  $($global:UI_RED)  SSH test failed: $($_.Exception.Message)$($global:UI_R)"
            }
        }

    } catch {
        Write-Host "  $($global:UI_RED)  Health check failed: $($_.Exception.Message)$($global:UI_R)"
    }
}

# ── 2 — Network Info ─────────────────────────────────────────
function Show-NetworkInfo {
    Show-Header
    $w = Get-UiBoxWidth -MaxWidth 52 -MinWidth 40
    Write-UiBoxTitle -Title "NETWORK INFO" -Width $w

    SectionHead "ADAPTERS"
    Get-NetAdapter -ErrorAction SilentlyContinue | ForEach-Object {
        $statusColor = if ($_.Status -eq "Up") { $global:UI_GRN } else { $global:UI_GRY }
        Write-Host "  ${statusColor}$($global:UI_B)  $($_.Name)$($global:UI_R)  $($global:UI_GRY)[$($_.Status)]$($global:UI_R)"
        Row "  Speed"  $_.LinkSpeed
        Row "  MAC"    $_.MacAddress
        Write-UiBlankLine
    }

    SectionHead "IPv4 ADDRESSES"
    Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
        Where-Object { $_.IPAddress -notlike "127.*" } | ForEach-Object {
            Row "$($_.InterfaceAlias)" "$($_.IPAddress)/$($_.PrefixLength)"
        }

    SectionHead "IPv6 ADDRESSES"
    Get-NetIPAddress -AddressFamily IPv6 -ErrorAction SilentlyContinue |
        Where-Object { $_.IPAddress -notlike "::1" -and $_.PrefixOrigin -ne "WellKnown" } |
        ForEach-Object {
            Row "$($_.InterfaceAlias)" $_.IPAddress
        }

    SectionHead "DNS SERVERS"
    Get-DnsClientServerAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue | ForEach-Object {
        $servers = if ($_.ServerAddresses) { $_.ServerAddresses -join "  " } else { "None" }
        Row "$($_.InterfaceAlias)" $servers
    }

    SectionHead "DEFAULT ROUTES"
    Get-NetRoute -DestinationPrefix "0.0.0.0/0" -ErrorAction SilentlyContinue |
        Sort-Object RouteMetric | ForEach-Object {
            Write-Host "  $($global:UI_GRN)  $($_.InterfaceAlias)$($global:UI_R)  $($global:UI_GRY)via $($global:UI_R)$($global:UI_WHT)$($_.NextHop)$($global:UI_R)  $($global:UI_GRY)metric $($_.RouteMetric)$($global:UI_R)"
        }
}

# ── 3 — Wi-Fi Details ────────────────────────────────────────
function Show-WiFiDetails {
    Show-Header
    $w = Get-UiBoxWidth -MaxWidth 52 -MinWidth 40
    Write-UiBoxTitle -Title "WI-FI DETAILS" -Width $w

    try {
        $wifi = netsh wlan show interfaces 2>$null
        if (-not ($wifi -match "SSID")) {
            Write-UiBlankLine
            Write-Host "  $($global:UI_YLW)  No Wi-Fi interface found or not connected.$($global:UI_R)"
            return
        }

        SectionHead "CONNECTED INTERFACE"
        $fields = @("Name","SSID","BSSID","Network type","Authentication",
                    "Cipher","Connection mode","Channel","Receive rate","Transmit rate",
                    "Signal","Radio type","Profile")
        foreach ($field in $fields) {
            $line = $wifi | Where-Object { $_ -match "^\s+${field}\s+:" } | Select-Object -First 1
            if ($line) {
                $parts = $line -split ":", 2
                if ($parts.Count -eq 2) {
                    $val   = $parts[1].Trim()
                    $color = $global:UI_GRN
                    if ($field -eq "Signal") {
                        $sigNum = [int]($val -replace "[^0-9]","")
                        $color  = if ($sigNum -ge 80) { $global:UI_GRN } elseif ($sigNum -ge 50) { $global:UI_YLW } else { $global:UI_RED }
                    }
                    Row $field $val $color
                }
            }
        }

        # Available networks
        Write-UiBlankLine
        if (Confirm-Action "Show available Wi-Fi networks?") {
            SectionHead "AVAILABLE NETWORKS"
            $nets = netsh wlan show networks mode=bssid 2>$null
            $ssids = $nets | Select-String "SSID\s+\d+\s+:" | ForEach-Object {
                ($_ -split ":", 2)[1].Trim()
            }
            $signals = $nets | Select-String "Signal\s+:" | ForEach-Object {
                ($_ -split ":", 2)[1].Trim()
            }
            for ($i = 0; $i -lt $ssids.Count; $i++) {
                $sig      = if ($i -lt $signals.Count) { $signals[$i] } else { "?" }
                $sigNum   = [int]($sig -replace "[^0-9]","")
                $sigColor = if ($sigNum -ge 80) { $global:UI_GRN } elseif ($sigNum -ge 50) { $global:UI_YLW } else { $global:UI_RED }
                Write-Host "  $($global:UI_WHT)  $($ssids[$i].PadRight(32))$($global:UI_R)  ${sigColor}Signal: $sig$($global:UI_R)"
            }
        }
    } catch {
        Write-Host "  $($global:UI_RED)  Wi-Fi query failed: $($_.Exception.Message)$($global:UI_R)"
    }
}

# ── 4 — Ping Host List ───────────────────────────────────────
function Invoke-PingList {
    Show-Header
    $w = Get-UiBoxWidth -MaxWidth 52 -MinWidth 40
    Write-UiBoxTitle -Title "PING HOST LIST" -Width $w
    Write-Host -NoNewline "  $($global:UI_YLW)  Enter hosts separated by commas: $($global:UI_R)"
    $inputHosts = Read-Host
    if (-not $inputHosts) { Write-Host "  $($global:UI_GRY)  No hosts entered.$($global:UI_R)"; return }

    $hosts = $inputHosts.Split(",") | ForEach-Object { $_.Trim() } | Where-Object { $_ }
    Write-UiBlankLine

    foreach ($target in $hosts) {
        $ping   = Test-PingHost $target 2
        $rttStr = if ($ping.RTT) { "  $($global:UI_GRY)(RTT: $($ping.RTT)ms)$($global:UI_R)" } else { "" }
        if ($ping.Success) {
            Write-Host "  $($global:UI_GRN)  [UP]   $target$($global:UI_R)$rttStr"
        } else {
            Write-Host "  $($global:UI_RED)  [DOWN] $target$($global:UI_R)"
        }
    }
}

# ── 5 — Test Port ────────────────────────────────────────────
function Invoke-TestPort {
    Show-Header
    $w = Get-UiBoxWidth -MaxWidth 52 -MinWidth 40
    Write-UiBoxTitle -Title "TEST PORT" -Width $w
    Write-Host -NoNewline "  $($global:UI_YLW)  Host: $($global:UI_R)"; $hostName = Read-Host
    Write-Host -NoNewline "  $($global:UI_YLW)  Port: $($global:UI_R)"; $port = Read-Host

    if (-not $hostName -or -not $port) {
        Write-Host "  $($global:UI_RED)  Host and port required.$($global:UI_R)"
        return
    }

    try {
        Write-UiBlankLine
        Write-Host "  $($global:UI_CYN)  Testing $hostName : $port ...$($global:UI_R)"
        $result = Test-NetConnection -ComputerName $hostName -Port ([int]$port) -WarningAction SilentlyContinue
        Write-UiBlankLine
        Row "Host"           $hostName
        Row "Port"           $port
        Row "Remote Address" "$($result.RemoteAddress)"
        Row "Result"         ""
        Write-Host "  $($global:UI_DIM)$("Result".PadRight(20))$($global:UI_R)  $(Status $result.TcpTestSucceeded 'OPEN' 'CLOSED')"
    } catch {
        Write-Host "  $($global:UI_RED)  Port test failed: $($_.Exception.Message)$($global:UI_R)"
    }
}

# ── 6 — DNS Lookup ───────────────────────────────────────────
function Invoke-DnsLookup {
    Show-Header
    $w = Get-UiBoxWidth -MaxWidth 52 -MinWidth 40
    Write-UiBoxTitle -Title "DNS LOOKUP" -Width $w
    Write-Host -NoNewline "  $($global:UI_YLW)  Enter host/domain: $($global:UI_R)"; $name = Read-Host
    if (-not $name) { Write-Host "  $($global:UI_GRY)  No host entered.$($global:UI_R)"; return }

    Write-UiBlankLine
    try {
        $results = Resolve-DnsName $name -ErrorAction Stop
        foreach ($r in $results) {
            $type = "$($r.Type)".PadRight(8)
            switch ($r.Type) {
                "A"     { Write-Host "  $($global:UI_GRN)  [$type]$($global:UI_R)  $($global:UI_WHT)$($r.IPAddress)$($global:UI_R)" }
                "AAAA"  { Write-Host "  $($global:UI_BLU)  [$type]$($global:UI_R)  $($global:UI_WHT)$($r.IPAddress)$($global:UI_R)" }
                "CNAME" { Write-Host "  $($global:UI_YLW)  [$type]$($global:UI_R)  $($global:UI_WHT)$($r.NameHost)$($global:UI_R)" }
                "MX"    { Write-Host "  $($global:UI_MAG)  [$type]$($global:UI_R)  $($global:UI_WHT)$($r.NameExchange)  pref $($r.Preference)$($global:UI_R)" }
                "TXT"   { Write-Host "  $($global:UI_CYN)  [$type]$($global:UI_R)  $($global:UI_WHT)$($r.Strings -join ' ')$($global:UI_R)" }
                "NS"    { Write-Host "  $($global:UI_GRY)  [$type]$($global:UI_R)  $($global:UI_WHT)$($r.NameHost)$($global:UI_R)" }
                default { Write-Host "  $($global:UI_GRY)  [$type]$($global:UI_R)  $($global:UI_WHT)$r$($global:UI_R)" }
            }
        }
    } catch {
        Write-Host "  $($global:UI_RED)  DNS lookup failed: $($_.Exception.Message)$($global:UI_R)"
    }
}

# ── 7 — Traceroute ───────────────────────────────────────────
function Invoke-Traceroute {
    Show-Header
    $w = Get-UiBoxWidth -MaxWidth 52 -MinWidth 40
    Write-UiBoxTitle -Title "TRACEROUTE" -Width $w
    Write-Host -NoNewline "  $($global:UI_YLW)  Enter host/IP: $($global:UI_R)"; $target = Read-Host
    if (-not $target) { Write-Host "  $($global:UI_GRY)  No host entered.$($global:UI_R)"; return }

    Write-UiBlankLine
    Write-Host "  $($global:UI_CYN)  Tracing route to $target (max 30 hops)...$($global:UI_R)"
    Write-Host "  $($global:UI_GRY)  Press Ctrl+C to stop.$($global:UI_R)"
    Write-UiBlankLine
    Write-Host "  $($global:UI_GRY)  Hop   RTT        Address$($global:UI_R)"
    Write-Host "  $($global:UI_GRY)  ----  ---------  -------$($global:UI_R)"

    try {
        $hop = 1
        while ($hop -le 30) {
            $result = Test-NetConnection -ComputerName $target -Hops $hop -WarningAction SilentlyContinue -ErrorAction SilentlyContinue 2>$null
            break
        }
    } catch {}

    $lines = tracert.exe -d -w 1000 $target 2>$null
    foreach ($line in $lines) {
        if ($line -match "^\s*(\d+)\s+(.+)") {
            $hopNum = $Matches[1].PadLeft(4)
            $rest   = $Matches[2].Trim()

            if ($rest -match "Request timed out") {
                Write-Host "  $($global:UI_GRY)  $hopNum  * * *      Request timed out$($global:UI_R)"
            } elseif ($rest -match "(\d+)\s+ms.*?(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})") {
                $rtt  = $Matches[1]
                $addr = $Matches[2]
                $rttColor = if ([int]$rtt -lt 20) { $global:UI_GRN } elseif ([int]$rtt -lt 100) { $global:UI_YLW } else { $global:UI_RED }
                Write-Host "  $($global:UI_GRY)  $hopNum  $($global:UI_R)${rttColor}${rtt}ms$($global:UI_R)$([string]::Empty.PadRight([Math]::Max(1,9-$rtt.Length)))  $($global:UI_WHT)$addr$($global:UI_R)"
            } else {
                Write-Host "  $($global:UI_GRY)  $hopNum  $rest$($global:UI_R)"
            }
        } elseif ($line -match "Trace complete") {
            Write-UiBlankLine
            Write-Host "  $($global:UI_GRN)  Trace complete.$($global:UI_R)"
        }
    }
}

# ── 8 — Public IP ────────────────────────────────────────────
function Get-PublicIP {
    Show-Header
    $w = Get-UiBoxWidth -MaxWidth 52 -MinWidth 40
    Write-UiBoxTitle -Title "PUBLIC IP LOOKUP" -Width $w
    Write-Host "  $($global:UI_CYN)  Looking up public IP...$($global:UI_R)"

    # Find curl.exe
    $curlExe = $null
    foreach ($c in @("$env:SystemRoot\System32\curl.exe","$env:SystemRoot\SysWOW64\curl.exe")) {
        if (Test-Path $c) { $curlExe = $c; break }
    }

    try {
        if ($curlExe) {
            $raw  = & $curlExe --silent --max-time 10 "https://ipinfo.io/json"
            $info = $raw | ConvertFrom-Json
            Write-UiBlankLine
            Row "Public IP"   $info.ip
            Row "Hostname"    $info.hostname
            Row "City"        $info.city
            Row "Region"      $info.region
            Row "Country"     $info.country
            Row "ISP / Org"   $info.org
            Row "Timezone"    $info.timezone
            if ($info.loc) {
                Row "Coordinates" $info.loc
            }
        } else {
            $ip = (Invoke-RestMethod -Uri "https://api.ipify.org?format=text" -TimeoutSec 10)
            Row "Public IP" $ip
            Write-UiBlankLine
            Write-Host "  $($global:UI_GRY)  Install curl.exe for full geo info.$($global:UI_R)"
        }
    } catch {
        Write-Host "  $($global:UI_RED)  Public IP lookup failed: $($_.Exception.Message)$($global:UI_R)"
    }
}

# ── 9 — Active TCP Connections ───────────────────────────────
function Show-ActiveConnections {
    Show-Header
    $w = Get-UiBoxWidth -MaxWidth 52 -MinWidth 40
    Write-UiBoxTitle -Title "ACTIVE TCP CONNECTIONS" -Width $w

    try {
        $conns = Get-NetTCPConnection -ErrorAction Stop |
            Where-Object { $_.State -ne "Listen" } |
            Sort-Object LocalPort

        Write-Host "  $($global:UI_GRY)  LocalAddr         LPort  RemoteAddr        RPort  State         Process$($global:UI_R)"
        Write-Host "  $($global:UI_GRY)  ----------------  -----  ----------------  -----  ------------  -------$($global:UI_R)"

        foreach ($c in $conns) {
            $proc     = Get-Process -Id $c.OwningProcess -ErrorAction SilentlyContinue
            $procName = if ($proc) { $proc.ProcessName } else { "?" }
            $stateColor = switch ($c.State) {
                "Established" { $global:UI_GRN }
                "TimeWait"    { $global:UI_YLW }
                "CloseWait"   { $global:UI_YLW }
                "SynSent"     { $global:UI_CYN }
                default       { $global:UI_GRY }
            }
            $la = $c.LocalAddress.PadRight(16)
            $ra = $c.RemoteAddress.PadRight(16)
            $lp = "$($c.LocalPort)".PadRight(5)
            $rp = "$($c.RemotePort)".PadRight(5)
            $st = "$($c.State)".PadRight(12)
            Write-Host "  $($global:UI_DIM)  $la  $lp  $ra  $rp  $($global:UI_R)${stateColor}$st$($global:UI_R)  $($global:UI_WHT)$procName$($global:UI_R)"
        }
    } catch {
        Write-CoreError "Failed: $($_.Exception.Message)"
    }
}

# ── 10 — Listening Ports ─────────────────────────────────────
function Show-ListeningPorts {
    Show-Header
    $w = Get-UiBoxWidth -MaxWidth 52 -MinWidth 40
    Write-UiBoxTitle -Title "LISTENING PORTS" -Width $w

    try {
        $ports = Get-NetTCPConnection -State Listen -ErrorAction Stop | Sort-Object LocalPort

        Write-Host "  $($global:UI_GRY)  Port   Address           Process$($global:UI_R)"
        Write-Host "  $($global:UI_GRY)  -----  ----------------  -------$($global:UI_R)"

        foreach ($p in $ports) {
            $proc     = Get-Process -Id $p.OwningProcess -ErrorAction SilentlyContinue
            $procName = if ($proc) { $proc.ProcessName } else { "?" }
            $port     = "$($p.LocalPort)".PadRight(5)
            $addr     = $p.LocalAddress.PadRight(16)
            Write-Host "  $($global:UI_GRN)  $port$($global:UI_R)  $($global:UI_GRY)$addr$($global:UI_R)  $($global:UI_WHT)$procName$($global:UI_R)"
        }
    } catch {
        Write-CoreError "Failed: $($_.Exception.Message)"
    }
}

# ── 11 — Find Process on Port ────────────────────────────────
function Invoke-WhoPort {
    Show-Header
    $w = Get-UiBoxWidth -MaxWidth 52 -MinWidth 40
    Write-UiBoxTitle -Title "FIND PROCESS ON PORT" -Width $w
    Write-Host -NoNewline "  $($global:UI_YLW)  Enter local port: $($global:UI_R)"; $port = Read-Host
    if (-not $port) { Write-Host "  $($global:UI_GRY)  No port entered.$($global:UI_R)"; return }

    try {
        $conns = Get-NetTCPConnection -LocalPort ([int]$port) -ErrorAction SilentlyContinue
        if (-not $conns) {
            Write-Host "  $($global:UI_GRY)  Nothing found on port $port.$($global:UI_R)"
            return
        }

        Write-UiBlankLine
        foreach ($item in $conns) {
            $proc     = Get-Process -Id $item.OwningProcess -ErrorAction SilentlyContinue
            $procName = if ($proc) { $proc.ProcessName } else { "Unknown" }
            $procPath = if ($proc) { $proc.Path } else { "" }

            Row "Port"    "$($item.LocalPort)"
            Row "PID"     "$($item.OwningProcess)"
            Row "Process" $procName
            Row "Path"    $procPath
            Row "State"   "$($item.State)"
            Row "Remote"  "$($item.RemoteAddress):$($item.RemotePort)"
            Write-UiBlankLine
        }
    } catch {
        Write-Host "  $($global:UI_RED)  Port lookup failed: $($_.Exception.Message)$($global:UI_R)"
    }
}

# ── 12 — Watch Connectivity ─────────────────────────────────
function Invoke-WatchConnectivity {
    Show-Header
    $w = Get-UiBoxWidth -MaxWidth 52 -MinWidth 40
    Write-UiBoxTitle -Title "WATCH CONNECTIVITY" -Width $w
    Write-Host -NoNewline "  $($global:UI_YLW)  Host to watch (default: 1.1.1.1): $($global:UI_R)"
    $target = Read-Host
    if (-not $target) { $target = "1.1.1.1" }

    Write-Host -NoNewline "  $($global:UI_YLW)  Interval seconds (default: 2): $($global:UI_R)"
    $intervalStr = Read-Host
    $interval    = if ($intervalStr -match '^\d+$') { [int]$intervalStr } else { 2 }

    Write-UiBlankLine
    Write-Host "  $($global:UI_CYN)  Watching $($global:UI_B)$target$($global:UI_R)$($global:UI_CYN) every ${interval}s.  Press Ctrl+C to stop.$($global:UI_R)"
    Write-UiBlankLine
    Write-Host "  $($global:UI_GRY)  Time                  Status   RTT      Streak$($global:UI_R)"
    Write-Host "  $($global:UI_GRY)  -------------------   ------   -------  ------$($global:UI_R)"

    $upStreak   = 0
    $downStreak = 0
    $totalUp    = 0
    $totalDown  = 0

    while ($true) {
        $time = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        $ping = Test-PingHost $target

        if ($ping.Success) {
            $upStreak++
            $downStreak = 0
            $totalUp++
            $rttStr    = if ($ping.RTT) { "$($ping.RTT)ms".PadRight(7) } else { "?ms    " }
            $rttColor  = if ($ping.RTT -lt 20) { $global:UI_GRN } elseif ($ping.RTT -lt 100) { $global:UI_YLW } else { $global:UI_RED }
            $streakStr = "$($global:UI_GRN)up x$upStreak$($global:UI_R)"
            Write-Host "  $($global:UI_GRY)  $time   $($global:UI_R)$($global:UI_GRN)$($global:UI_B)[UP]  $($global:UI_R)   ${rttColor}$rttStr$($global:UI_R)  $streakStr"
        } else {
            $downStreak++
            $upStreak = 0
            $totalDown++
            $streakStr = "$($global:UI_RED)down x$downStreak$($global:UI_R)"
            Write-Host "  $($global:UI_GRY)  $time   $($global:UI_R)$($global:UI_RED)$($global:UI_B)[DOWN]$($global:UI_R)   $($global:UI_GRY)-------$($global:UI_R)  $streakStr"
        }

        Start-Sleep -Seconds $interval
    }
}

# ── 13 — Adapter Enable / Disable ────────────────────────────
function Invoke-AdapterToggle {
    Show-Header
    $w = Get-UiBoxWidth -MaxWidth 52 -MinWidth 40
    Write-UiBoxTitle -Title "ADAPTER ENABLE / DISABLE" -Width $w

    $adapters = Get-NetAdapter -ErrorAction SilentlyContinue | Sort-Object Name
    if (-not $adapters) {
        Write-Host "  $($global:UI_RED)  No adapters found.$($global:UI_R)"
        return
    }

    $i = 1
    foreach ($a in $adapters) {
        $statusColor = if ($a.Status -eq "Up") { $global:UI_GRN } else { $global:UI_GRY }
        $statusLabel = "$($a.Status)".PadRight(10)
        Write-Host "  $($global:UI_YLW)  $i)$($global:UI_R)  ${statusColor}[$statusLabel]$($global:UI_R)  $($global:UI_WHT)$($a.Name)$($global:UI_R)  $($global:UI_GRY)$($a.InterfaceDescription)$($global:UI_R)"
        $i++
    }

    Write-UiBlankLine
    Write-Host -NoNewline "  $($global:UI_YLW)  Select adapter number (or Enter to cancel): $($global:UI_R)"
    $sel = Read-Host
    if (-not $sel -or $sel -notmatch '^\d+$') { return }

    $idx     = [int]$sel - 1
    $adapter = @($adapters)[$idx]
    if (-not $adapter) {
        Write-Host "  $($global:UI_RED)  Invalid selection.$($global:UI_R)"
        return
    }

    Write-UiBlankLine
    Write-Host "  $($global:UI_WHT)  Selected: $($global:UI_YLW)$($adapter.Name)$($global:UI_R)  $($global:UI_GRY)[Status: $($adapter.Status)]$($global:UI_R)"
    Write-UiBlankLine

    if ($adapter.Status -eq "Up") {
        if (Confirm-Action "Disable $($adapter.Name)?") {
            try {
                Disable-NetAdapter -Name $adapter.Name -Confirm:$false -ErrorAction Stop
                Write-Host "  $($global:UI_YLW)  $($adapter.Name) disabled.$($global:UI_R)"
            } catch {
                Write-CoreError "Failed: $($_.Exception.Message)"
                Write-Host "  $($global:UI_YLW)  Try running as Administrator.$($global:UI_R)"
            }
        }
    } else {
        if (Confirm-Action "Enable $($adapter.Name)?") {
            try {
                Enable-NetAdapter -Name $adapter.Name -Confirm:$false -ErrorAction Stop
                Write-Host "  $($global:UI_GRN)  $($adapter.Name) enabled.$($global:UI_R)"
            } catch {
                Write-CoreError "Failed: $($_.Exception.Message)"
                Write-Host "  $($global:UI_YLW)  Try running as Administrator.$($global:UI_R)"
            }
        }
    }
}

# ── 14 — Network Reset ───────────────────────────────────────
function Invoke-NetworkReset {
    Show-Header
    $w = Get-UiBoxWidth -MaxWidth 52 -MinWidth 40
    Write-UiBoxTitle -Title "NETWORK RESET" -Width $w
    Write-Host "  $($global:UI_YLW)$($global:UI_B)  Warning:$($global:UI_R)$($global:UI_YLW) This will temporarily drop your connection.$($global:UI_R)"
    Write-Host "  $($global:UI_GRY)  Includes: flush DNS, release/renew DHCP, winsock reset.$($global:UI_R)"
    Write-Host "  $($global:UI_GRY)  A reboot may be required after winsock reset.$($global:UI_R)"
    Write-UiBlankLine

    Write-Host "  $($global:UI_GRN)  A)$($global:UI_R)  DNS flush only         $($global:UI_GRY)(safe, no disconnect)$($global:UI_R)"
    Write-Host "  $($global:UI_YLW)  B)$($global:UI_R)  DNS flush + DHCP renew $($global:UI_GRY)(brief disconnect)$($global:UI_R)"
    Write-Host "  $($global:UI_RED)  C)$($global:UI_R)  Full reset             $($global:UI_GRY)(DNS + DHCP + winsock, reboot needed)$($global:UI_R)"
    Write-Host "  $($global:UI_GRY)  Q)$($global:UI_R)  Cancel"
    Write-UiBlankLine
    $choice = (Read-UiChoice "Choice:").Trim().ToUpper()

    switch ($choice) {
        "A" {
            Write-UiBlankLine
            Write-Host "  $($global:UI_CYN)  Flushing DNS...$($global:UI_R)"
            ipconfig /flushdns
            Write-CoreSuccess "Done."
        }
        "B" {
            if (Confirm-Action "Flush DNS and renew DHCP? (brief disconnect)") {
                Write-UiBlankLine
                Write-Host "  $($global:UI_CYN)  Flushing DNS...$($global:UI_R)";   ipconfig /flushdns
                Write-Host "  $($global:UI_CYN)  Releasing DHCP...$($global:UI_R)"; ipconfig /release
                Write-Host "  $($global:UI_CYN)  Renewing DHCP...$($global:UI_R)";  ipconfig /renew
                Write-CoreSuccess "Done."
            }
        }
        "C" {
            if (Confirm-Action "Run full network reset? (reboot required after)") {
                Write-UiBlankLine
                Write-Host "  $($global:UI_CYN)  Flushing DNS...$($global:UI_R)";       ipconfig /flushdns
                Write-Host "  $($global:UI_CYN)  Releasing DHCP...$($global:UI_R)";     ipconfig /release
                Write-Host "  $($global:UI_CYN)  Renewing DHCP...$($global:UI_R)";      ipconfig /renew
                Write-Host "  $($global:UI_CYN)  Resetting winsock...$($global:UI_R)";  netsh winsock reset
                Write-Host "  $($global:UI_CYN)  Resetting IP stack...$($global:UI_R)"; netsh int ip reset
                Write-UiBlankLine
                Write-Host "  $($global:UI_YLW)$($global:UI_B)  Full reset complete. Please reboot now.$($global:UI_R)"
            }
        }
        default {
            Write-Host "  $($global:UI_GRY)  Cancelled.$($global:UI_R)"
        }
    }
}

# ── Main Loop ────────────────────────────────────────────────
while ($true) {
    Show-Header
    Show-Menu

    $choice = (Read-UiChoice "Choice:").Trim().ToUpper()

    switch ($choice) {
        "1"  { Invoke-QuickHealthCheck; Pause-Script }
        "2"  { Show-NetworkInfo;        Pause-Script }
        "3"  { Show-WiFiDetails;        Pause-Script }
        "4"  { Invoke-PingList;         Pause-Script }
        "5"  { Invoke-TestPort;         Pause-Script }
        "6"  { Invoke-DnsLookup;        Pause-Script }
        "7"  { Invoke-Traceroute;       Pause-Script }
        "8"  { Get-PublicIP;            Pause-Script }
        "9"  { Show-ActiveConnections;  Pause-Script }
        "10" { Show-ListeningPorts;     Pause-Script }
        "11" { Invoke-WhoPort;          Pause-Script }
        "12" { Invoke-WatchConnectivity }
        "13" { Invoke-AdapterToggle;    Pause-Script }
        "14" { Invoke-NetworkReset;     Pause-Script }

        "Q"  {
            Write-UiBlankLine
            Write-Host "  $($global:UI_CYN)  Bye.$($global:UI_R)"
            Write-UiBlankLine
            return
        }

        default {
            Write-CoreError "Invalid option."
            Start-Sleep -Seconds 1
        }
    }
}