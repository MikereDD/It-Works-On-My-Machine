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
    Write-Host "  $($global:UI_Theme.Accent)  1)$($global:UI_Theme.Reset)  Recent System errors"
    Write-Host "  $($global:UI_Theme.Accent)  2)$($global:UI_Theme.Reset)  Recent Application errors"
    Write-Host "  $($global:UI_Theme.Accent)  3)$($global:UI_Theme.Reset)  Recent warnings  $($global:UI_Theme.Muted)(System + Application)$($global:UI_Theme.Reset)"
    Write-Host "  $($global:UI_Theme.Accent)  4)$($global:UI_Theme.Reset)  Recent PowerShell errors"
    Write-Host "  $($global:UI_Theme.Accent)  5)$($global:UI_Theme.Reset)  Failed logons  $($global:UI_Theme.Muted)(requires Admin)$($global:UI_Theme.Reset)"
    Write-Host "  $($global:UI_Theme.Accent)  6)$($global:UI_Theme.Reset)  Reboot / shutdown events"
    Write-UiDivider
    Write-Host "  $($global:UI_Theme.Info)  7)$($global:UI_Theme.Reset)  Export errors to CSV  $($global:UI_Theme.Muted)(choose log)$($global:UI_Theme.Reset)"
    Write-UiDivider
    Write-Host "  $($global:UI_Theme.Muted)  Q)$($global:UI_Theme.Reset)  Quit"
    Write-UiBlankLine
}

# ── Pause ─────────────────────────────────────────────────────
function Pause-Script {
    Pause-Core "Press Enter to return to menu..."
}

# ── Event level color ─────────────────────────────────────────
function Get-LevelColor($level) {
    switch ("$level".ToLower()) {
        "error"       { return $global:UI_Theme.Error }
        "critical"    { return $global:UI_Theme.Error }
        "warning"     { return $global:UI_Theme.Warning }
        "information" { return $global:UI_Theme.Info }
        default       { return $global:UI_Theme.Muted }
    }
}

# ── Print events in colored rows ─────────────────────────────
function Show-Events($events, $title) {
    if (-not $events -or $events.Count -eq 0) {
        Write-Host "  $($global:UI_Theme.Muted)  No events found.$($global:UI_Theme.Reset)"
        return
    }

    Write-Host "  $($global:UI_Theme.Muted)  Found $($global:UI_Theme.Reset)$($global:UI_Theme.Accent)$($events.Count)$($global:UI_Theme.Reset)$($global:UI_Theme.Muted) event(s)$($global:UI_Theme.Reset)"
    Write-UiBlankLine
    Write-Host "  $($global:UI_Theme.Muted)  Time                  Level        ID      Source$($global:UI_Theme.Reset)"
    Write-Host "  $($global:UI_Theme.Muted)  -------------------   ----------   -----   ------$($global:UI_Theme.Reset)"

    foreach ($e in $events) {
        $levelColor = Get-LevelColor $e.LevelDisplayName
        $time       = $e.TimeCreated.ToString("yyyy-MM-dd HH:mm:ss")
        $level      = "$($e.LevelDisplayName)".PadRight(10)
        $id         = "$($e.Id)".PadRight(5)
        $provider   = if ($e.ProviderName.Length -gt 35) { $e.ProviderName.Substring(0,32) + "..." } else { $e.ProviderName }

        Write-Host "  $($global:UI_Theme.Muted)  $time   $($global:UI_Theme.Reset)$levelColor$level$($global:UI_Theme.Reset)   $($global:UI_Theme.Muted)$id$($global:UI_Theme.Reset)   $($global:UI_Theme.Text)$provider$($global:UI_Theme.Reset)"
    }

    Write-UiBlankLine
    Write-Host "  $($global:UI_Theme.Muted)  -- Message preview (last 3 events) --$($global:UI_Theme.Reset)"
    Write-UiBlankLine

    foreach ($e in ($events | Select-Object -Last 3)) {
        $levelColor = Get-LevelColor $e.LevelDisplayName
        $msg        = if ($e.Message) { $e.Message.Split("`n")[0].Trim() } else { "(no message)" }
        if ($msg.Length -gt 110) { $msg = $msg.Substring(0,107) + "..." }

        Write-Host "  ${levelColor}  [$($e.LevelDisplayName)] $($e.TimeCreated.ToString('HH:mm:ss'))$($global:UI_Theme.Reset)"
        Write-Host "  $($global:UI_Theme.Text)  $msg$($global:UI_Theme.Reset)"
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
        Write-Host "  $($global:UI_Theme.Secondary)$($global:UI_Theme.Bold)  >> $log$($global:UI_Theme.Reset)"
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
    Write-Host "  $($global:UI_Theme.Warning)  Security log requires Admin rights.$($global:UI_Theme.Reset)"
    Write-UiBlankLine

    try {
        $events = Get-WinEvent -FilterHashtable @{ LogName = 'Security'; Id = 4625 } -MaxEvents 20 -ErrorAction Stop

        if (-not $events -or $events.Count -eq 0) {
            Write-Host "  $($global:UI_Theme.Success)  No failed logon events found.$($global:UI_Theme.Reset)"
            return
        }

        Write-Host "  $($global:UI_Theme.Muted)  Found $($global:UI_Theme.Reset)$($global:UI_Theme.Accent)$($events.Count)$($global:UI_Theme.Reset)$($global:UI_Theme.Muted) failed logon(s)$($global:UI_Theme.Reset)"
        Write-UiBlankLine
        Write-Host "  $($global:UI_Theme.Muted)  Time                  Event ID   Source$($global:UI_Theme.Reset)"
        Write-Host "  $($global:UI_Theme.Muted)  -------------------   --------   ------$($global:UI_Theme.Reset)"

        foreach ($e in $events) {
            $time = $e.TimeCreated.ToString("yyyy-MM-dd HH:mm:ss")
            Write-Host "  $($global:UI_Theme.Error)  $time   $($e.Id)        $($global:UI_Theme.Reset)$($global:UI_Theme.Text)$($e.ProviderName)$($global:UI_Theme.Reset)"
        }

        Write-UiBlankLine
        Write-Host "  $($global:UI_Theme.Muted)  -- Details (last 3) --$($global:UI_Theme.Reset)"
        Write-UiBlankLine

        foreach ($e in ($events | Select-Object -Last 3)) {
            $msg = if ($e.Message) { $e.Message.Split("`n")[0..4] -join " " } else { "(no message)" }
            if ($msg.Length -gt 120) { $msg = $msg.Substring(0,117) + "..." }
            Write-Host "  $($global:UI_Theme.Error)  $($e.TimeCreated.ToString('HH:mm:ss'))$($global:UI_Theme.Reset)  $($global:UI_Theme.Text)$msg$($global:UI_Theme.Reset)"
            Write-UiBlankLine
        }
    } catch {
        Write-CoreError "Failed: $($_.Exception.Message)"
        Write-Host "  $($global:UI_Theme.Warning)  Try running as Administrator.$($global:UI_Theme.Reset)"
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
            Write-Host "  $($global:UI_Theme.Muted)  No reboot/shutdown events found.$($global:UI_Theme.Reset)"
            return
        }

        Write-Host "  $($global:UI_Theme.Muted)  Found $($global:UI_Theme.Reset)$($global:UI_Theme.Accent)$($events.Count)$($global:UI_Theme.Reset)$($global:UI_Theme.Muted) event(s)$($global:UI_Theme.Reset)"
        Write-UiBlankLine
        Write-Host "  $($global:UI_Theme.Muted)  Time                  ID     Type$($global:UI_Theme.Reset)"
        Write-Host "  $($global:UI_Theme.Muted)  -------------------   ----   ----$($global:UI_Theme.Reset)"

        foreach ($e in $events) {
            $time  = $e.TimeCreated.ToString("yyyy-MM-dd HH:mm:ss")
            $desc  = if ($idMap.ContainsKey($e.Id)) { $idMap[$e.Id] } else { "Event $($e.Id)" }
            $color = switch ($e.Id) {
                6008    { $global:UI_Theme.Error }
                41      { $global:UI_Theme.Error }
                1074    { $global:UI_Theme.Warning }
                default { $global:UI_Theme.Info }
            }

            Write-Host "  $($global:UI_Theme.Muted)  $time   $($global:UI_Theme.Reset)$color$($e.Id.ToString().PadRight(5))  $desc$($global:UI_Theme.Reset)"
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

    Write-Host "  $($global:UI_Theme.Accent)  1)$($global:UI_Theme.Reset)  System"
    Write-Host "  $($global:UI_Theme.Accent)  2)$($global:UI_Theme.Reset)  Application"
    Write-Host "  $($global:UI_Theme.Accent)  3)$($global:UI_Theme.Reset)  Both"
    Write-UiBlankLine
    Write-Host -NoNewline "  $($global:UI_Theme.Warning)  Log to export (1/2/3): $($global:UI_Theme.Reset)"
    $logChoice = (Read-Host).Trim()

    $logs = switch ($logChoice) {
        "1" { @("System") }
        "2" { @("Application") }
        "3" { @("System","Application") }
        default {
            Write-Host "  $($global:UI_Theme.Error)  Invalid.$($global:UI_Theme.Reset)"
            return
        }
    }

    $defaultFile = Join-Path $HOME "event_errors_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"
    Write-Host "  $($global:UI_Theme.Muted)  Default: $defaultFile$($global:UI_Theme.Reset)"
    Write-Host -NoNewline "  $($global:UI_Theme.Warning)  Output path (Enter for default): $($global:UI_Theme.Reset)"
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