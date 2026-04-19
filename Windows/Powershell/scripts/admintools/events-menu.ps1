#--------------------------------------------
# file:     events-menu.ps1
# author:   Mike Redd
# version:  2.4
# created:  2026-03-30
# updated:  2026-04-19
# desc:     Windows event log utility
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

$ScriptName    = "Events Menu"
$ScriptVersion = "2.4"
$ScriptAuthor  = "Mike Redd"

# ── Header ────────────────────────────────────────────────────
function Show-Header {
    Clear-UiScreen
    $w = Get-UiBoxWidth -MaxWidth 52 -MinWidth 40

    Write-UiHeader -Title $ScriptName -Subtitle "v$ScriptVersion  by $ScriptAuthor" -Width $w
    Write-UiRow "User" "$env:USERNAME@$env:COMPUTERNAME"
    Write-UiBlankLine
}

# ── Menu ──────────────────────────────────────────────────────
function Show-Menu {
    Write-UiDivider
    Write-Host "  $($global:UI_GRN)  1)$($global:UI_R)  Recent System errors"
    Write-Host "  $($global:UI_GRN)  2)$($global:UI_R)  Recent Application errors"
    Write-Host "  $($global:UI_GRN)  3)$($global:UI_R)  Recent warnings  $($global:UI_GRY)(System + Application)$($global:UI_R)"
    Write-Host "  $($global:UI_GRN)  4)$($global:UI_R)  Recent PowerShell errors"
    Write-Host "  $($global:UI_GRN)  5)$($global:UI_R)  Failed logons  $($global:UI_GRY)(requires Admin)$($global:UI_R)"
    Write-Host "  $($global:UI_GRN)  6)$($global:UI_R)  Reboot / shutdown events"
    Write-UiDivider
    Write-Host "  $($global:UI_CYN)  7)$($global:UI_R)  Export errors to CSV  $($global:UI_GRY)(choose log)$($global:UI_R)"
    Write-UiDivider
    Write-Host "  $($global:UI_GRY)  Q)$($global:UI_R)  Quit"
    Write-UiBlankLine
}

# ── Pause ─────────────────────────────────────────────────────
function Pause-Script {
    Pause-Core "Press Enter to return to menu..."
}

# ── Event level color ─────────────────────────────────────────
function Get-LevelColor($level) {
    switch ("$level".ToLower()) {
        "error"       { return $global:UI_RED }
        "critical"    { return $global:UI_RED }
        "warning"     { return $global:UI_YLW }
        "information" { return $global:UI_GRN }
        default       { return $global:UI_GRY }
    }
}

# ── Print events in colored rows ─────────────────────────────
function Show-Events($events, $title) {
    if (-not $events -or $events.Count -eq 0) {
        Write-Host "  $($global:UI_GRY)  No events found.$($global:UI_R)"
        return
    }

    Write-Host "  $($global:UI_GRY)  Found $($global:UI_R)$($global:UI_YLW)$($events.Count)$($global:UI_R)$($global:UI_GRY) event(s)$($global:UI_R)"
    Write-UiBlankLine
    Write-Host "  $($global:UI_GRY)  Time                  Level        ID      Source$($global:UI_R)"
    Write-Host "  $($global:UI_GRY)  -------------------   ----------   -----   ------$($global:UI_R)"

    foreach ($e in $events) {
        $levelColor = Get-LevelColor $e.LevelDisplayName
        $time       = $e.TimeCreated.ToString("yyyy-MM-dd HH:mm:ss")
        $level      = "$($e.LevelDisplayName)".PadRight(10)
        $id         = "$($e.Id)".PadRight(5)
        $provider   = if ($e.ProviderName.Length -gt 35) { $e.ProviderName.Substring(0,32) + "..." } else { $e.ProviderName }

        Write-Host "  $($global:UI_GRY)  $time   $($global:UI_R)$levelColor$level$($global:UI_R)   $($global:UI_GRY)$id$($global:UI_R)   $($global:UI_WHT)$provider$($global:UI_R)"
    }

    Write-UiBlankLine
    Write-Host "  $($global:UI_GRY)  -- Message preview (last 3 events) --$($global:UI_R)"
    Write-UiBlankLine

    foreach ($e in ($events | Select-Object -Last 3)) {
        $levelColor = Get-LevelColor $e.LevelDisplayName
        $msg        = if ($e.Message) { $e.Message.Split("`n")[0].Trim() } else { "(no message)" }
        if ($msg.Length -gt 110) { $msg = $msg.Substring(0,107) + "..." }

        Write-Host "  ${levelColor}  [$($e.LevelDisplayName)] $($e.TimeCreated.ToString('HH:mm:ss'))$($global:UI_R)"
        Write-Host "  $($global:UI_WHT)  $msg$($global:UI_R)"
        Write-UiBlankLine
    }
}

# ── 1 — System Errors ─────────────────────────────────────────
function Show-SystemErrors {
    Show-Header
    $w = Get-UiBoxWidth -MaxWidth 52 -MinWidth 40
    Write-UiBoxTitle -Title "RECENT SYSTEM ERRORS" -Width $w
    try {
        $events = Get-WinEvent -LogName System -MaxEvents 100 -ErrorAction Stop |
            Where-Object { $_.LevelDisplayName -eq "Error" } |
            Select-Object -First 20
        Show-Events $events "System Errors"
    } catch {
        Write-CoreError "Failed: $($_.Exception.Message)"
    }
}

# ── 2 — Application Errors ────────────────────────────────────
function Show-ApplicationErrors {
    Show-Header
    $w = Get-UiBoxWidth -MaxWidth 52 -MinWidth 40
    Write-UiBoxTitle -Title "RECENT APPLICATION ERRORS" -Width $w
    try {
        $events = Get-WinEvent -LogName Application -MaxEvents 100 -ErrorAction Stop |
            Where-Object { $_.LevelDisplayName -eq "Error" } |
            Select-Object -First 20
        Show-Events $events "Application Errors"
    } catch {
        Write-CoreError "Failed: $($_.Exception.Message)"
    }
}

# ── 3 — Warnings ──────────────────────────────────────────────
function Show-Warnings {
    Show-Header
    $w = Get-UiBoxWidth -MaxWidth 52 -MinWidth 40
    Write-UiBoxTitle -Title "RECENT WARNINGS" -Width $w
    try {
        $sys = Get-WinEvent -LogName System -MaxEvents 100 -ErrorAction Stop |
            Where-Object { $_.LevelDisplayName -eq "Warning" } | Select-Object -First 10
        $app = Get-WinEvent -LogName Application -MaxEvents 100 -ErrorAction Stop |
            Where-Object { $_.LevelDisplayName -eq "Warning" } | Select-Object -First 10
        $all = @($sys + $app) | Sort-Object TimeCreated -Descending | Select-Object -First 20
        Show-Events $all "Warnings"
    } catch {
        Write-CoreError "Failed: $($_.Exception.Message)"
    }
}

# ── 4 — PowerShell Errors ─────────────────────────────────────
function Show-PowerShellErrors {
    Show-Header
    $w = Get-UiBoxWidth -MaxWidth 52 -MinWidth 40
    Write-UiBoxTitle -Title "RECENT POWERSHELL ERRORS" -Width $w

    $logs = @("Windows PowerShell","Microsoft-Windows-PowerShell/Operational")
    foreach ($log in $logs) {
        Write-Host "  $($global:UI_MAG)$($global:UI_B)  >> $log$($global:UI_R)"
        Write-UiBlankLine
        try {
            $events = Get-WinEvent -LogName $log -MaxEvents 50 -ErrorAction Stop |
                Where-Object { $_.LevelDisplayName -eq "Error" } |
                Select-Object -First 10
            Show-Events $events $log
        } catch {
            Write-CoreError "Could not read: $($_.Exception.Message)"
        }
        Write-UiBlankLine
    }
}

# ── 5 — Failed Logons ─────────────────────────────────────────
function Show-FailedLogons {
    Show-Header
    $w = Get-UiBoxWidth -MaxWidth 52 -MinWidth 40
    Write-UiBoxTitle -Title "FAILED LOGONS" -Width $w
    Write-Host "  $($global:UI_YLW)  Security log requires Admin rights.$($global:UI_R)"
    Write-UiBlankLine

    try {
        $events = Get-WinEvent -FilterHashtable @{ LogName = 'Security'; Id = 4625 } -MaxEvents 20 -ErrorAction Stop

        if (-not $events -or $events.Count -eq 0) {
            Write-Host "  $($global:UI_GRN)  No failed logon events found.$($global:UI_R)"
            return
        }

        Write-Host "  $($global:UI_GRY)  Found $($global:UI_R)$($global:UI_YLW)$($events.Count)$($global:UI_R)$($global:UI_GRY) failed logon(s)$($global:UI_R)"
        Write-UiBlankLine
        Write-Host "  $($global:UI_GRY)  Time                  Event ID   Source$($global:UI_R)"
        Write-Host "  $($global:UI_GRY)  -------------------   --------   ------$($global:UI_R)"

        foreach ($e in $events) {
            $time = $e.TimeCreated.ToString("yyyy-MM-dd HH:mm:ss")
            Write-Host "  $($global:UI_RED)  $time   $($e.Id)        $($global:UI_R)$($global:UI_WHT)$($e.ProviderName)$($global:UI_R)"
        }

        Write-UiBlankLine
        Write-Host "  $($global:UI_GRY)  -- Details (last 3) --$($global:UI_R)"
        Write-UiBlankLine

        foreach ($e in ($events | Select-Object -Last 3)) {
            $msg = if ($e.Message) { $e.Message.Split("`n")[0..4] -join " " } else { "(no message)" }
            if ($msg.Length -gt 120) { $msg = $msg.Substring(0,117) + "..." }
            Write-Host "  $($global:UI_RED)  $($e.TimeCreated.ToString('HH:mm:ss'))$($global:UI_R)  $($global:UI_WHT)$msg$($global:UI_R)"
            Write-UiBlankLine
        }
    } catch {
        Write-CoreError "Failed: $($_.Exception.Message)"
        Write-Host "  $($global:UI_YLW)  Try running as Administrator.$($global:UI_R)"
    }
}

# ── 6 — Reboot / Shutdown ─────────────────────────────────────
function Show-RebootShutdownEvents {
    Show-Header
    $w = Get-UiBoxWidth -MaxWidth 52 -MinWidth 40
    Write-UiBoxTitle -Title "REBOOT / SHUTDOWN EVENTS" -Width $w

    $idMap = @{
        1074 = "Clean shutdown/restart"
        6005 = "Event log started (boot)"
        6006 = "Event log stopped (shutdown)"
        6008 = "Unexpected shutdown"
        41   = "Kernel power event (crash/forced restart)"
    }

    try {
        $events = Get-WinEvent -FilterHashtable @{
            LogName = 'System'; Id = 1074, 6005, 6006, 6008, 41
        } -MaxEvents 30 -ErrorAction Stop

        if (-not $events -or $events.Count -eq 0) {
            Write-Host "  $($global:UI_GRY)  No reboot/shutdown events found.$($global:UI_R)"
            return
        }

        Write-Host "  $($global:UI_GRY)  Found $($global:UI_R)$($global:UI_YLW)$($events.Count)$($global:UI_R)$($global:UI_GRY) event(s)$($global:UI_R)"
        Write-UiBlankLine
        Write-Host "  $($global:UI_GRY)  Time                  ID     Type$($global:UI_R)"
        Write-Host "  $($global:UI_GRY)  -------------------   ----   ----$($global:UI_R)"

        foreach ($e in $events) {
            $time  = $e.TimeCreated.ToString("yyyy-MM-dd HH:mm:ss")
            $desc  = if ($idMap.ContainsKey($e.Id)) { $idMap[$e.Id] } else { "Event $($e.Id)" }
            $color = switch ($e.Id) {
                6008    { $global:UI_RED }
                41      { $global:UI_RED }
                1074    { $global:UI_YLW }
                default { $global:UI_GRN }
            }

            Write-Host "  $($global:UI_GRY)  $time   $($global:UI_R)$color$($e.Id.ToString().PadRight(5))  $desc$($global:UI_R)"
        }
    } catch {
        Write-CoreError "Failed: $($_.Exception.Message)"
    }
}

# ── 7 — Export Errors CSV ─────────────────────────────────────
function Export-ErrorsCsv {
    Show-Header
    $w = Get-UiBoxWidth -MaxWidth 52 -MinWidth 40
    Write-UiBoxTitle -Title "EXPORT ERRORS TO CSV" -Width $w

    Write-Host "  $($global:UI_GRN)  1)$($global:UI_R)  System"
    Write-Host "  $($global:UI_GRN)  2)$($global:UI_R)  Application"
    Write-Host "  $($global:UI_GRN)  3)$($global:UI_R)  Both"
    Write-UiBlankLine
    Write-Host -NoNewline "  $($global:UI_YLW)  Log to export (1/2/3): $($global:UI_R)"
    $logChoice = (Read-Host).Trim()

    $logs = switch ($logChoice) {
        "1" { @("System") }
        "2" { @("Application") }
        "3" { @("System","Application") }
        default {
            Write-Host "  $($global:UI_RED)  Invalid.$($global:UI_R)"
            return
        }
    }

    $defaultFile = Join-Path $HOME "event_errors_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"
    Write-Host "  $($global:UI_GRY)  Default: $defaultFile$($global:UI_R)"
    Write-Host -NoNewline "  $($global:UI_YLW)  Output path (Enter for default): $($global:UI_R)"
    $outFile = Read-Host
    if (-not $outFile) { $outFile = $defaultFile }

    try {
        $all = foreach ($log in $logs) {
            Get-WinEvent -LogName $log -MaxEvents 100 -ErrorAction Stop |
                Where-Object { $_.LevelDisplayName -eq "Error" } |
                Select-Object TimeCreated, Id, ProviderName, LevelDisplayName,
                    @{N="Log";E={$log}},
                    @{N="Message";E={$_.Message.Split("`n")[0].Trim()}}
        }

        $all | Export-Csv -Path $outFile -NoTypeInformation
        Write-CoreSuccess "Exported $($all.Count) event(s) to: $outFile"
    } catch {
        Write-CoreError "Export failed: $($_.Exception.Message)"
    }
}

# ── Main Loop ─────────────────────────────────────────────────
while ($true) {
    Show-Header
    Show-Menu
    $choice = (Read-UiChoice "Choice:").Trim().ToUpper()

    switch ($choice) {
        "1" { Show-SystemErrors;          Pause-Script }
        "2" { Show-ApplicationErrors;     Pause-Script }
        "3" { Show-Warnings;              Pause-Script }
        "4" { Show-PowerShellErrors;      Pause-Script }
        "5" { Show-FailedLogons;          Pause-Script }
        "6" { Show-RebootShutdownEvents;  Pause-Script }
        "7" { Export-ErrorsCsv;           Pause-Script }

        "Q" {
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