#--------------------------------------------
# file:     watch-menu.ps1
# author:   Mike Redd
# version:  2.3
# created:  2026-03-30
# updated:  2026-04-01
# desc:     Repeating watch utility for common admin tasks
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

$ScriptName    = "Watch Menu"
$ScriptVersion = "2.3"
$ScriptAuthor  = "Mike Redd"

# ── Header & menu ─────────────────────────────────────────────
function Show-Header {
    Clear-UiScreen
    $w = Get-UiBoxWidth -MaxWidth 52 -MinWidth 40

    Write-UiHeader -Title $ScriptName -Subtitle "v$ScriptVersion  by $ScriptAuthor" -Width $w
    Write-UiRow "User" "$env:USERNAME@$env:COMPUTERNAME"
    Write-UiRow "Version" "v$ScriptVersion  by $ScriptAuthor" $global:UI_Theme.Muted
    Write-UiBlankLine
}

function Show-Menu {
    Write-UiDivider
    Write-Host "  $($global:UI_Theme.Accent)  1)$($global:UI_Theme.Reset)  Watch top CPU processes"
    Write-Host "  $($global:UI_Theme.Accent)  2)$($global:UI_Theme.Reset)  Watch top memory processes"
    Write-Host "  $($global:UI_Theme.Accent)  3)$($global:UI_Theme.Reset)  Watch active TCP connections"
    Write-Host "  $($global:UI_Theme.Accent)  4)$($global:UI_Theme.Reset)  Watch listening ports"
    Write-Host "  $($global:UI_Theme.Accent)  5)$($global:UI_Theme.Reset)  Watch drive usage"
    Write-Host "  $($global:UI_Theme.Accent)  6)$($global:UI_Theme.Reset)  Watch service status"
    Write-Host "  $($global:UI_Theme.Accent)  7)$($global:UI_Theme.Reset)  Watch recent System errors"
    Write-Host "  $($global:UI_Theme.Accent)  8)$($global:UI_Theme.Reset)  Watch custom command"
    Write-UiDivider
    Write-Host "  $($global:UI_Theme.Muted)  Q)$($global:UI_Theme.Reset)  Quit"
    Write-UiBlankLine
}

# ── Usage bar helper ──────────────────────────────────────────
function MakeBar($pct, $len = 20) {
    $filled = [Math]::Min($len, [Math]::Round($pct / 100 * $len))
    $empty  = $len - $filled
    $bc     = if ($pct -ge 90) { $global:UI_Theme.Error } elseif ($pct -ge 70) { $global:UI_Theme.Warning } else { $global:UI_Theme.Success }
    return "${bc}" + ("#" * $filled) + "$($global:UI_Theme.Muted)" + ("-" * $empty) + "$($global:UI_Theme.Reset)"
}

# ── Refresh interval helper ───────────────────────────────────
function Get-Interval($default = 2) {
    Write-Host -NoNewline "  $($global:UI_Theme.Warning)  Refresh interval seconds (default $default): $($global:UI_Theme.Reset)"
    $s = Read-Host
    if ($s -match '^\d+$' -and [int]$s -gt 0) { return [int]$s }
    return $default
}

# ── Confirm ───────────────────────────────────────────────────
function Confirm-Action($message) {
    return (Confirm-Core $message)
}

# ── Watch loop engine ─────────────────────────────────────────
function Invoke-WatchLoop {
    param(
        [scriptblock]$CommandBlock,
        [string]$Title = "WATCH",
        [int]$IntervalSeconds = 2
    )

    $orig = [Console]::TreatControlCAsInput
    [Console]::TreatControlCAsInput = $true

    try {
        while ($true) {
            Clear-UiScreen
            $w = Get-UiBoxWidth -MaxWidth 52 -MinWidth 40
            Write-UiHeader -Title "$ScriptName -- $Title" -Width $w

            $ts = Get-Date -Format "HH:mm:ss"
            Write-Host "  $($global:UI_Theme.Muted)  $ts  |  Refreshing every ${IntervalSeconds}s  |  Ctrl+C to return to menu$($global:UI_Theme.Reset)"
            Write-UiBlankLine

            try {
                & $CommandBlock
            } catch {
                Write-CoreError "Command failed: $($_.Exception.Message)"
            }

            $end = (Get-Date).AddSeconds($IntervalSeconds)
            while ((Get-Date) -lt $end) {
                Start-Sleep -Milliseconds 100
                while ([Console]::KeyAvailable) {
                    $key = [Console]::ReadKey($true)
                    if ($key.Key -eq [ConsoleKey]::C -and ($key.Modifiers -band [ConsoleModifiers]::Control)) {
                        return
                    }
                }
            }
        }
    } finally {
        [Console]::TreatControlCAsInput = $orig
    }
}

# ── 1 — Watch Top CPU ─────────────────────────────────────────
function Watch-TopCPU {
    $interval = Get-Interval 2
    Invoke-WatchLoop -Title "Top CPU" -IntervalSeconds $interval -CommandBlock {
        Write-Host "  $($global:UI_Theme.Muted)  Name                         PID      CPU(s)    RAM$($global:UI_Theme.Reset)"
        Write-Host "  $($global:UI_Theme.Muted)  ---------------------------  -------  --------  ---$($global:UI_Theme.Reset)"
        Get-Process | Sort-Object CPU -Descending | Select-Object -First 15 | ForEach-Object {
            $cpu      = if ($_.CPU) { [Math]::Round($_.CPU,1) } else { 0 }
            $mem      = [Math]::Round($_.WorkingSet64 / 1MB, 1)
            $cpuColor = if ($cpu -ge 50) { $global:UI_Theme.Error } elseif ($cpu -ge 10) { $global:UI_Theme.Warning } else { $global:UI_Theme.Success }
            $memColor = if ($mem -ge 1000) { $global:UI_Theme.Error } elseif ($mem -ge 300) { $global:UI_Theme.Warning } else { $global:UI_Theme.Success }
            $nameStr  = $_.ProcessName.PadRight(28)
            $pidStr   = "$($_.Id)".PadRight(7)
            $cpuStr   = ("{0:N1}" -f $cpu).PadRight(8)
            Write-Host "  $($global:UI_Theme.Text)  $nameStr$($global:UI_Theme.Reset)  $($global:UI_Theme.Muted)$pidStr$($global:UI_Theme.Reset)  ${cpuColor}$cpuStr$($global:UI_Theme.Reset)  ${memColor}$mem MB$($global:UI_Theme.Reset)"
        }
    }
}

# ── 2 — Watch Top Memory ──────────────────────────────────────
function Watch-TopMemory {
    $interval = Get-Interval 2
    Invoke-WatchLoop -Title "Top Memory" -IntervalSeconds $interval -CommandBlock {
        Write-Host "  $($global:UI_Theme.Muted)  Name                         PID      RAM       CPU(s)$($global:UI_Theme.Reset)"
        Write-Host "  $($global:UI_Theme.Muted)  ---------------------------  -------  --------  ------$($global:UI_Theme.Reset)"
        Get-Process | Sort-Object WorkingSet64 -Descending | Select-Object -First 15 | ForEach-Object {
            $cpu      = if ($_.CPU) { [Math]::Round($_.CPU,1) } else { 0 }
            $mem      = [Math]::Round($_.WorkingSet64 / 1MB, 1)
            $memColor = if ($mem -ge 1000) { $global:UI_Theme.Error } elseif ($mem -ge 300) { $global:UI_Theme.Warning } else { $global:UI_Theme.Success }
            $cpuColor = if ($cpu -ge 50) { $global:UI_Theme.Error } elseif ($cpu -ge 10) { $global:UI_Theme.Warning } else { $global:UI_Theme.Success }
            $nameStr  = $_.ProcessName.PadRight(28)
            $pidStr   = "$($_.Id)".PadRight(7)
            $memStr   = ("{0:N1} MB" -f $mem).PadRight(8)
            Write-Host "  $($global:UI_Theme.Text)  $nameStr$($global:UI_Theme.Reset)  $($global:UI_Theme.Muted)$pidStr$($global:UI_Theme.Reset)  ${memColor}$memStr$($global:UI_Theme.Reset)  ${cpuColor}$cpu$($global:UI_Theme.Reset)"
        }
    }
}

# ── 3 — Watch TCP Connections ─────────────────────────────────
function Watch-TcpConnections {
    $interval = Get-Interval 3
    Invoke-WatchLoop -Title "TCP Connections" -IntervalSeconds $interval -CommandBlock {
        Write-Host "  $($global:UI_Theme.Muted)  LocalAddr         LPort  RemoteAddr        RPort  State         Process$($global:UI_Theme.Reset)"
        Write-Host "  $($global:UI_Theme.Muted)  ----------------  -----  ----------------  -----  ------------  -------$($global:UI_Theme.Reset)"
        Get-NetTCPConnection -ErrorAction SilentlyContinue |
            Where-Object { $_.State -ne "Listen" } |
            Sort-Object State, LocalPort |
            Select-Object -First 25 | ForEach-Object {
                $proc      = Get-Process -Id $_.OwningProcess -ErrorAction SilentlyContinue
                $procName  = if ($proc) { $proc.ProcessName } else { "?" }
                $stateColor = switch ($_.State) {
                    "Established" { $global:UI_Theme.Success }
                    "TimeWait"    { $global:UI_Theme.Warning }
                    "CloseWait"   { $global:UI_Theme.Warning }
                    default       { $global:UI_Theme.Muted }
                }
                $la = $_.LocalAddress.PadRight(16)
                $ra = $_.RemoteAddress.PadRight(16)
                $lp = "$($_.LocalPort)".PadRight(5)
                $rp = "$($_.RemotePort)".PadRight(5)
                $st = "$($_.State)".PadRight(12)
                Write-Host "  $($global:UI_Theme.Dim)  $la  $lp  $ra  $rp  $($global:UI_Theme.Reset)${stateColor}$st$($global:UI_Theme.Reset)  $($global:UI_Theme.Text)$procName$($global:UI_Theme.Reset)"
            }
    }
}

# ── 4 — Watch Listening Ports ─────────────────────────────────
function Watch-ListeningPorts {
    $interval = Get-Interval 3
    Invoke-WatchLoop -Title "Listening Ports" -IntervalSeconds $interval -CommandBlock {
        Write-Host "  $($global:UI_Theme.Muted)  Port   Address           Process$($global:UI_Theme.Reset)"
        Write-Host "  $($global:UI_Theme.Muted)  -----  ----------------  -------$($global:UI_Theme.Reset)"
        Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue |
            Sort-Object LocalPort | ForEach-Object {
                $proc     = Get-Process -Id $_.OwningProcess -ErrorAction SilentlyContinue
                $procName = if ($proc) { $proc.ProcessName } else { "?" }
                $port     = "$($_.LocalPort)".PadRight(5)
                $addr     = $_.LocalAddress.PadRight(16)
                Write-Host "  $($global:UI_Theme.Accent)  $port$($global:UI_Theme.Reset)  $($global:UI_Theme.Muted)$addr$($global:UI_Theme.Reset)  $($global:UI_Theme.Text)$procName$($global:UI_Theme.Reset)"
            }
    }
}

# ── 5 — Watch Drive Usage ─────────────────────────────────────
function Watch-DriveUsage {
    $interval = Get-Interval 5
    Invoke-WatchLoop -Title "Drive Usage" -IntervalSeconds $interval -CommandBlock {
        Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3" | ForEach-Object {
            $totalGB = [Math]::Round($_.Size / 1GB, 2)
            $freeGB  = [Math]::Round($_.FreeSpace / 1GB, 2)
            $usedGB  = [Math]::Round($totalGB - $freeGB, 2)
            $pct     = if ($totalGB -gt 0) { [Math]::Round(($usedGB / $totalGB) * 100, 1) } else { 0 }

            $bar      = MakeBar $pct
            $usedColor = if ($pct -ge 90) { $global:UI_Theme.Error } elseif ($pct -ge 70) { $global:UI_Theme.Warning } else { $global:UI_Theme.Success }

            Write-Host "  $($global:UI_Theme.Secondary)$($global:UI_Theme.Bold)  $($_.DeviceID)  $($_.VolumeName)$($global:UI_Theme.Reset)  $($global:UI_Theme.Muted)[$($_.FileSystem)]$($global:UI_Theme.Reset)"
            Write-Host "  $($global:UI_Theme.Dim)$($global:UI_Theme.Text)  $("Used".PadRight(8))$($global:UI_Theme.Reset)  ${usedColor}$usedGB GB  ($pct%)$($global:UI_Theme.Reset)  [$bar]"
            Write-Host "  $($global:UI_Theme.Dim)$($global:UI_Theme.Text)  $("Free".PadRight(8))$($global:UI_Theme.Reset)  $($global:UI_Theme.Success)$freeGB GB$($global:UI_Theme.Reset)  $($global:UI_Theme.Muted)Total: $totalGB GB$($global:UI_Theme.Reset)"
            Write-UiBlankLine
        }
    }
}

# ── 6 — Watch Service ─────────────────────────────────────────
function Watch-ServiceStatus {
    Show-Header
    Write-Host -NoNewline "  $($global:UI_Theme.Warning)  Service name: $($global:UI_Theme.Reset)"
    $serviceName = Read-Host
    if (-not $serviceName) {
        Write-Host "  $($global:UI_Theme.Muted)  No service entered.$($global:UI_Theme.Reset)"
        Start-Sleep -Seconds 1
        return
    }

    $interval = Get-Interval 3
    Invoke-WatchLoop -Title "Service: $serviceName" -IntervalSeconds $interval -CommandBlock {
        try {
            $svc = Get-Service -Name $serviceName -ErrorAction Stop
            $cim = Get-CimInstance Win32_Service -Filter "Name='$($svc.Name)'" -ErrorAction SilentlyContinue
            $statusColor = switch ("$($svc.Status)") {
                "Running" { $global:UI_Theme.Success }
                "Stopped" { $global:UI_Theme.Error }
                "Paused"  { $global:UI_Theme.Warning }
                default   { $global:UI_Theme.Muted }
            }
            Write-Host "  $($global:UI_Theme.Dim)$($global:UI_Theme.Text)  Name         $($global:UI_Theme.Reset)  $($global:UI_Theme.Text)$($svc.Name)$($global:UI_Theme.Reset)"
            Write-Host "  $($global:UI_Theme.Dim)$($global:UI_Theme.Text)  Display Name $($global:UI_Theme.Reset)  $($global:UI_Theme.Text)$($svc.DisplayName)$($global:UI_Theme.Reset)"
            Write-Host "  $($global:UI_Theme.Dim)$($global:UI_Theme.Text)  Status       $($global:UI_Theme.Reset)  ${statusColor}$($global:UI_Theme.Bold)$($svc.Status)$($global:UI_Theme.Reset)"
            Write-Host "  $($global:UI_Theme.Dim)$($global:UI_Theme.Text)  Startup Type $($global:UI_Theme.Reset)  $($global:UI_Theme.Muted)$(if ($cim) { $cim.StartMode } else { 'Unknown' })$($global:UI_Theme.Reset)"
        } catch {
            Write-CoreError "Service not found: $serviceName"
        }
    }
}

# ── 7 — Watch System Errors ───────────────────────────────────
function Watch-SystemErrors {
    $interval = Get-Interval 10
    Invoke-WatchLoop -Title "System Errors" -IntervalSeconds $interval -CommandBlock {
        $events = Get-WinEvent -LogName System -MaxEvents 50 -ErrorAction SilentlyContinue |
            Where-Object { $_.LevelDisplayName -eq "Error" } | Select-Object -First 10

        if (-not $events) {
            Write-Host "  $($global:UI_Theme.Success)  No recent errors.$($global:UI_Theme.Reset)"
            return
        }

        Write-Host "  $($global:UI_Theme.Muted)  Time                  ID      Source$($global:UI_Theme.Reset)"
        Write-Host "  $($global:UI_Theme.Muted)  -------------------   -----   ------$($global:UI_Theme.Reset)"
        foreach ($e in $events) {
            $time = $e.TimeCreated.ToString("yyyy-MM-dd HH:mm:ss")
            $id   = "$($e.Id)".PadRight(5)
            Write-Host "  $($global:UI_Theme.Error)  $time   $id$($global:UI_Theme.Reset)   $($global:UI_Theme.Text)$($e.ProviderName)$($global:UI_Theme.Reset)"
        }
    }
}

# ── 8 — Watch Custom Command ──────────────────────────────────
function Watch-CustomCommand {
    Show-Header
    Write-Host -NoNewline "  $($global:UI_Theme.Warning)  PowerShell command to watch: $($global:UI_Theme.Reset)"
    $cmd = Read-Host
    if (-not $cmd) {
        Write-Host "  $($global:UI_Theme.Muted)  No command entered.$($global:UI_Theme.Reset)"
        Start-Sleep -Seconds 1
        return
    }

    $interval = Get-Interval 2
    Invoke-WatchLoop -Title "Custom" -IntervalSeconds $interval -CommandBlock {
        Invoke-Expression $cmd
    }
}

# ── Main Loop ─────────────────────────────────────────────────
while ($true) {
    Show-Header
    Show-Menu
    $choice = (Read-UiChoice "Choice:").Trim().ToUpper()

    switch ($choice) {
        "1" { Watch-TopCPU }
        "2" { Watch-TopMemory }
        "3" { Watch-TcpConnections }
        "4" { Watch-ListeningPorts }
        "5" { Watch-DriveUsage }
        "6" { Watch-ServiceStatus }
        "7" { Watch-SystemErrors }
        "8" { Watch-CustomCommand }

        "Q" {
            Write-UiBlankLine
            Write-Host "  $($global:UI_Theme.Accent)  Bye.$($global:UI_Theme.Reset)"
            Write-UiBlankLine
            return
        }

        default {
            Write-CoreError "Invalid option."
            Start-Sleep -Seconds 1
        }
    }
}