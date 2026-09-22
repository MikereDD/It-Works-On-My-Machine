#--------------------------------------------
# file:     power-menu.ps1
# author:   Mike Redd
# version:  2.4
# created:  2026-03-30
# updated:  2026-04-01
# desc:     Power menu
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

$ScriptName = "Power Menu"
$Version    = "2.4"
$Author     = "Mike Redd"

# ── Uptime helper ─────────────────────────────────────────────
function Get-Uptime {
    try {
        $os     = Get-CimInstance Win32_OperatingSystem
        $uptime = (Get-Date) - $os.LastBootUpTime
        return ("{0}d {1}h {2}m" -f $uptime.Days, $uptime.Hours, $uptime.Minutes)
    } catch {
        return "Unknown"
    }
}

# ── Hibernate availability check ──────────────────────────────
function Test-HibernateAvailable {
    try {
        $result = powercfg /a 2>&1
        return ($result -join "") -match "Hibernation"
    } catch {
        return $false
    }
}

# ── Header ────────────────────────────────────────────────────
function Show-Header {
    Clear-UiScreen
    $w = Get-UiBoxWidth -MaxWidth 52 -MinWidth 40

    Write-UiHeader -Title $ScriptName -Subtitle "v$Version  by $Author" -Width $w

    $ts     = Get-Date -Format "ddd MMM dd yyyy  |  HH:mm:ss"
    $uptime = Get-Uptime

    Write-UiRow "User"   "$env:USERNAME@$env:COMPUTERNAME"
    Write-UiRow "Time"   $ts $global:UI_Theme.Muted
    Write-UiRow "Uptime" $uptime $global:UI_Theme.Muted
    Write-UiRow "Version" "v$Version  by $Author" $global:UI_Theme.Muted
    Write-UiBlankLine
}

# ── Menu ──────────────────────────────────────────────────────
function Show-Menu($hibernateOK) {
    Write-UiDivider
    Write-Host "  $($global:UI_Theme.Accent)  1)$($global:UI_Theme.Reset)  Sleep"

    if ($hibernateOK) {
        Write-Host "  $($global:UI_Theme.Accent)  2)$($global:UI_Theme.Reset)  Hibernate"
    } else {
        Write-Host "  $($global:UI_Theme.Muted)  2)  Hibernate  $($global:UI_Theme.Dim)(unavailable on this system)$($global:UI_Theme.Reset)"
    }

    Write-Host "  $($global:UI_Theme.Accent)  3)$($global:UI_Theme.Reset)  Lock Screen"
    Write-UiDivider
    Write-Host "  $($global:UI_Theme.Warning)  4)$($global:UI_Theme.Reset)  Restart"
    Write-Host "  $($global:UI_Theme.Warning)  5)$($global:UI_Theme.Reset)  Restart in...  $($global:UI_Theme.Dim)(delayed)$($global:UI_Theme.Reset)"
    Write-Host "  $($global:UI_Theme.Error)  6)$($global:UI_Theme.Reset)  Shutdown"
    Write-Host "  $($global:UI_Theme.Error)  7)$($global:UI_Theme.Reset)  Shutdown in... $($global:UI_Theme.Dim)(delayed)$($global:UI_Theme.Reset)"
    Write-UiDivider
    Write-Host "  $($global:UI_Theme.Secondary)  8)$($global:UI_Theme.Reset)  Log Off"
    Write-UiDivider
    Write-Host "  $($global:UI_Theme.Muted)  Q)$($global:UI_Theme.Reset)  Quit"
    Write-UiBlankLine
}

# ── Countdown abort window ────────────────────────────────────
function Start-Countdown($action, $seconds = 5) {
    Write-UiBlankLine
    Write-Host "  $($global:UI_Theme.Warning)$($global:UI_Theme.Bold)  $action in $seconds seconds.  Press any key to cancel...$($global:UI_Theme.Reset)"
    Write-UiBlankLine

    $elapsed = 0
    while ($elapsed -lt $seconds) {
        if ([Console]::KeyAvailable) {
            $null = [Console]::ReadKey($true)
            Write-CoreSuccess "Cancelled."
            Start-Sleep -Milliseconds 800
            return $false
        }

        $remaining = $seconds - $elapsed
        Write-Host -NoNewline "`r  $($global:UI_Theme.Error)$($global:UI_Theme.Bold)  $remaining...  $($global:UI_Theme.Reset)   "
        Start-Sleep -Seconds 1
        $elapsed++
    }

    Write-Host -NoNewline "`r  $($global:UI_Theme.Error)$($global:UI_Theme.Bold)  Executing...   $($global:UI_Theme.Reset)"
    Write-Host ""
    return $true
}

# ── Delayed shutdown/restart prompt ───────────────────────────
function Get-DelayMinutes($action) {
    Write-UiBlankLine
    Write-Host "  $($global:UI_Theme.Warning)  $action in how many minutes?$($global:UI_Theme.Reset)"
    Write-Host "  $($global:UI_Theme.Muted)  (Enter 0 to cancel, max 1440)$($global:UI_Theme.Reset)"
    Write-UiBlankLine
    Write-Host -NoNewline "  $($global:UI_Theme.Warning)  Minutes: $($global:UI_Theme.Reset)"
    $input = Read-Host

    if ($input -match '^\d+$') {
        $mins = [int]$input
        if ($mins -eq 0) { return $null }

        if ($mins -gt 1440) {
            Write-Host "  $($global:UI_Theme.Error)  Max is 1440 minutes (24 hours).$($global:UI_Theme.Reset)"
            Start-Sleep -Seconds 2
            return $null
        }

        return $mins
    }

    Write-CoreError "Invalid input."
    Start-Sleep -Seconds 1
    return $null
}

# ── Confirm prompt ────────────────────────────────────────────
function Confirm($message) {
    return (Confirm-Core $message)
}

# ── Cancel scheduled shutdown ─────────────────────────────────
function Cancel-Scheduled {
    shutdown.exe /a 2>$null
    Write-Host "  $($global:UI_Theme.Success)  Any scheduled shutdown/restart has been cancelled.$($global:UI_Theme.Reset)"
    Start-Sleep -Seconds 2
}

# ── Main Loop ────────────────────────────────────────────────
$hibernateOK = Test-HibernateAvailable

while ($true) {
    Show-Header
    Show-Menu $hibernateOK

    $choice = (Read-UiChoice "Choice:").Trim().ToUpper()

    switch ($choice) {

        # ── Sleep ──────────────────────────────────────────────
        "1" {
            if (Confirm "Put system to sleep?") {
                if (Start-Countdown "Sleeping") {
                    rundll32.exe powrprof.dll,SetSuspendState 0,1,0
                }
            }
        }

        # ── Hibernate ──────────────────────────────────────────
        "2" {
            if (-not $hibernateOK) {
                Write-Host "  $($global:UI_Theme.Error)  Hibernate is not available on this system.$($global:UI_Theme.Reset)"
                Start-Sleep -Seconds 2
                continue
            }

            if (Confirm "Hibernate system?") {
                if (Start-Countdown "Hibernating") {
                    shutdown.exe /h
                }
            }
        }

        # ── Lock Screen ────────────────────────────────────────
        "3" {
            Write-Host "  $($global:UI_Theme.Accent)  Locking screen...$($global:UI_Theme.Reset)"
            Start-Sleep -Milliseconds 500
            rundll32.exe user32.dll,LockWorkStation
        }

        # ── Restart ────────────────────────────────────────────
        "4" {
            if (Confirm "Restart system?") {
                if (Start-Countdown "Restarting") {
                    Restart-Computer -Force
                }
            }
        }

        # ── Restart with delay ─────────────────────────────────
        "5" {
            $mins = Get-DelayMinutes "Restart"
            if ($null -ne $mins) {
                $secs = $mins * 60
                $when = (Get-Date).AddMinutes($mins).ToString("HH:mm")
                if (Confirm "Schedule restart in $mins minute(s) at $when?") {
                    shutdown.exe /r /t $secs /c "Scheduled restart via Power Menu"
                    Write-Host "  $($global:UI_Theme.Success)  Restart scheduled for $when  ($mins min).$($global:UI_Theme.Reset)"
                    Write-Host "  $($global:UI_Theme.Muted)  Run this script again and choose option 5 again to cancel.$($global:UI_Theme.Reset)"
                    Start-Sleep -Seconds 3
                }
            }
        }

        # ── Shutdown ───────────────────────────────────────────
        "6" {
            if (Confirm "Shutdown system?") {
                if (Start-Countdown "Shutting down") {
                    Stop-Computer -Force
                }
            }
        }

        # ── Shutdown with delay ────────────────────────────────
        "7" {
            $mins = Get-DelayMinutes "Shutdown"
            if ($null -ne $mins) {
                $secs = $mins * 60
                $when = (Get-Date).AddMinutes($mins).ToString("HH:mm")
                if (Confirm "Schedule shutdown in $mins minute(s) at $when?") {
                    shutdown.exe /s /t $secs /c "Scheduled shutdown via Power Menu"
                    Write-Host "  $($global:UI_Theme.Success)  Shutdown scheduled for $when  ($mins min).$($global:UI_Theme.Reset)"
                    Write-Host "  $($global:UI_Theme.Muted)  Run this script again and choose option 7 again to cancel.$($global:UI_Theme.Reset)"
                    Start-Sleep -Seconds 3
                }
            }
        }

        # ── Log Off ────────────────────────────────────────────
        "8" {
            if (Confirm "Log off $env:USERNAME?") {
                if (Start-Countdown "Logging off") {
                    shutdown.exe /l
                }
            }
        }

        # ── Quit ───────────────────────────────────────────────
        "Q" {
            Write-UiBlankLine
            return
        }

        # ── Invalid Option ─────────────────────────────────────
        default {
            Write-CoreError "Invalid option."
            Start-Sleep -Seconds 1
        }
    }
}