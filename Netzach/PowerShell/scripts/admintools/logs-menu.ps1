#--------------------------------------------
# file:     logs-menu.ps1
# author:   Mike Redd
# version:  1.3
# created:  2026-04-02
# updated:  2026-04-02
# desc:     Core log viewer and maintenance menu
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

$ScriptName    = "Logs Menu"
$ScriptVersion = "1.3"
$ScriptAuthor  = "Mike Redd"

# ── Log file path ─────────────────────────────────────────────
if (-not $global:CORE_LOG_FILE -or [string]::IsNullOrWhiteSpace($global:CORE_LOG_FILE)) {
    $logDir = Join-Path $PSRootDir "logs"
    $global:CORE_LOG_FILE = Join-Path $logDir "toolkit.log"
}

# ── Header ────────────────────────────────────────────────────
function Show-Header {
    Clear-UiScreen
    $w = Get-UiBoxWidth -MaxWidth 52 -MinWidth 40

    Write-UiHeader -Title $ScriptName -Subtitle "v$ScriptVersion  by $ScriptAuthor" -Width $w
    Write-UiRow "User" "$env:USERNAME@$env:COMPUTERNAME"

    if (Test-Path $global:CORE_LOG_FILE) {
        $item = Get-Item $global:CORE_LOG_FILE -ErrorAction SilentlyContinue
        if ($item) {
            $sizeKB = [Math]::Round($item.Length / 1KB, 2)
            Write-UiRow "Log File" $global:CORE_LOG_FILE $global:UI_GRY
            Write-UiRow "Log Size" "$sizeKB KB" $global:UI_GRY
        } else {
            Write-UiRow "Log File" $global:CORE_LOG_FILE $global:UI_GRY
        }
    } else {
        Write-UiRow "Log File" "Not created yet" $global:UI_YLW
        Write-UiRow "Path" $global:CORE_LOG_FILE $global:UI_GRY
    }

    Write-UiBlankLine
}

# ── Menu ──────────────────────────────────────────────────────
function Show-Menu {
    Write-UiDivider
    Write-Host "  $($global:UI_GRN)  1)$($global:UI_R)  Show last 25 log lines"
    Write-Host "  $($global:UI_GRN)  2)$($global:UI_R)  Show last 100 log lines"
    Write-Host "  $($global:UI_GRN)  3)$($global:UI_R)  Follow log (tail mode)"
    Write-Host "  $($global:UI_GRN)  4)$($global:UI_R)  Show full log"
    Write-UiDivider
    Write-Host "  $($global:UI_YLW)  5)$($global:UI_R)  Show log file info"
    Write-Host "  $($global:UI_RED)  6)$($global:UI_R)  Clear log file"
	Write-Host "  $($global:UI_CYN)  7)$($global:UI_R)  Generate test log entries"
    Write-UiDivider
    Write-Host "  $($global:UI_GRY)  Q)$($global:UI_R)  Quit"
    Write-UiBlankLine
}

# ── Confirm ───────────────────────────────────────────────────
function Confirm-Action($message) {
    return (Confirm-Core $message)
}

# ── Pause ─────────────────────────────────────────────────────
function Pause-Script {
    Pause-Core "Press Enter to return to menu..."
}

# ── Ensure log path exists ────────────────────────────────────
function Ensure-LogPath {
    $dir = Split-Path -Path $global:CORE_LOG_FILE -Parent
    if ($dir -and -not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
}

# ── Show log info ─────────────────────────────────────────────
function Show-LogInfo {
    Show-Header
    $w = Get-UiBoxWidth -MaxWidth 52 -MinWidth 40
    Write-UiBoxTitle -Title "LOG FILE INFO" -Width $w

    Ensure-LogPath

    Write-Host "  $($global:UI_DIM)$($global:UI_WHT)  Path        $($global:UI_R)  $($global:UI_GRY)$global:CORE_LOG_FILE$($global:UI_R)"

    if (Test-Path $global:CORE_LOG_FILE) {
        $item = Get-Item $global:CORE_LOG_FILE -ErrorAction Stop
        $sizeBytes = $item.Length
        $sizeKB    = [Math]::Round($sizeBytes / 1KB, 2)
        $lastWrite = $item.LastWriteTime.ToString("yyyy-MM-dd HH:mm:ss")
        $lineCount = (Get-Content $global:CORE_LOG_FILE -ErrorAction SilentlyContinue | Measure-Object -Line).Lines

        Write-Host "  $($global:UI_DIM)$($global:UI_WHT)  Exists      $($global:UI_R)  $($global:UI_GRN)Yes$($global:UI_R)"
        Write-Host "  $($global:UI_DIM)$($global:UI_WHT)  Size        $($global:UI_R)  $($global:UI_GRN)$sizeKB KB$($global:UI_R)  $($global:UI_GRY)($sizeBytes bytes)$($global:UI_R)"
        Write-Host "  $($global:UI_DIM)$($global:UI_WHT)  Lines       $($global:UI_R)  $($global:UI_GRN)$lineCount$($global:UI_R)"
        Write-Host "  $($global:UI_DIM)$($global:UI_WHT)  Modified    $($global:UI_R)  $($global:UI_GRY)$lastWrite$($global:UI_R)"
    } else {
        Write-Host "  $($global:UI_DIM)$($global:UI_WHT)  Exists      $($global:UI_R)  $($global:UI_RED)No$($global:UI_R)"
    }
}

# ── Show last N lines ─────────────────────────────────────────
function Show-LogTail {
    param(
        [int]$Lines = 25,
        [string]$Title = "LOG TAIL"
    )

    Show-Header
    $w = Get-UiBoxWidth -MaxWidth 52 -MinWidth 40
    Write-UiBoxTitle -Title $Title -Width $w

    if (-not (Test-Path $global:CORE_LOG_FILE)) {
        Write-CoreError "Log file not found."
        return
    }

    try {
        $content = Get-Content -Path $global:CORE_LOG_FILE -Tail $Lines -ErrorAction Stop
        if (-not $content) {
            Write-Host "  $($global:UI_GRY)  Log file is empty.$($global:UI_R)"
            return
        }

        foreach ($line in $content) {
            if ($line -match "ERROR:") {
                Write-Host "  $($global:UI_RED)$line$($global:UI_R)"
            } elseif ($line -match "SUCCESS:") {
                Write-Host "  $($global:UI_GRN)$line$($global:UI_R)"
            } elseif ($line -match "EXPORT:") {
                Write-Host "  $($global:UI_CYN)$line$($global:UI_R)"
            } else {
                Write-Host "  $($global:UI_GRY)$line$($global:UI_R)"
            }
        }
    } catch {
        Write-CoreError "Failed to read log: $($_.Exception.Message)"
    }
}

# ── Show full log ─────────────────────────────────────────────
function Show-FullLog {
    Show-Header
    $w = Get-UiBoxWidth -MaxWidth 52 -MinWidth 40
    Write-UiBoxTitle -Title "FULL LOG" -Width $w

    if (-not (Test-Path $global:CORE_LOG_FILE)) {
        Write-CoreError "Log file not found."
        return
    }

    try {
        $content = Get-Content -Path $global:CORE_LOG_FILE -ErrorAction Stop
        if (-not $content) {
            Write-Host "  $($global:UI_GRY)  Log file is empty.$($global:UI_R)"
            return
        }

        foreach ($line in $content) {
            if ($line -match "ERROR:") {
                Write-Host "  $($global:UI_RED)$line$($global:UI_R)"
            } elseif ($line -match "SUCCESS:") {
                Write-Host "  $($global:UI_GRN)$line$($global:UI_R)"
            } elseif ($line -match "EXPORT:") {
                Write-Host "  $($global:UI_CYN)$line$($global:UI_R)"
            } else {
                Write-Host "  $($global:UI_GRY)$line$($global:UI_R)"
            }
        }
    } catch {
        Write-CoreError "Failed to read log: $($_.Exception.Message)"
    }
}

# ── Follow log ────────────────────────────────────────────────
function Follow-Log {
    Ensure-LogPath

    if (-not (Test-Path $global:CORE_LOG_FILE)) {
        New-Item -ItemType File -Path $global:CORE_LOG_FILE -Force | Out-Null
    }

    $orig = [Console]::TreatControlCAsInput
    [Console]::TreatControlCAsInput = $true

    try {
        while ($true) {
            Clear-UiScreen
            $w = Get-UiBoxWidth -MaxWidth 52 -MinWidth 40
            Write-UiHeader -Title "$ScriptName -- FOLLOW LOG" -Width $w
            Write-Host "  $($global:UI_GRY)  Ctrl+C to return to menu$($global:UI_R)"
            Write-Host "  $($global:UI_DIM)$global:CORE_LOG_FILE$($global:UI_R)"
            Write-UiBlankLine

            try {
                $content = Get-Content -Path $global:CORE_LOG_FILE -Tail 25 -ErrorAction Stop
                if ($content) {
                    foreach ($line in $content) {
                        if ($line -match "ERROR:") {
                            Write-Host "  $($global:UI_RED)$line$($global:UI_R)"
                        } elseif ($line -match "SUCCESS:") {
                            Write-Host "  $($global:UI_GRN)$line$($global:UI_R)"
                        } elseif ($line -match "EXPORT:") {
                            Write-Host "  $($global:UI_CYN)$line$($global:UI_R)"
                        } else {
                            Write-Host "  $($global:UI_GRY)$line$($global:UI_R)"
                        }
                    }
                } else {
                    Write-Host "  $($global:UI_GRY)  Log file is empty.$($global:UI_R)"
                }
            } catch {
                Write-CoreError "Failed to follow log: $($_.Exception.Message)"
            }

            $end = (Get-Date).AddSeconds(2)
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

# ── Clear log ─────────────────────────────────────────────────
function Clear-LogFile {
    Show-Header
    $w = Get-UiBoxWidth -MaxWidth 52 -MinWidth 40
    Write-UiBoxTitle -Title "CLEAR LOG FILE" -Width $w

    Ensure-LogPath

    if (-not (Test-Path $global:CORE_LOG_FILE)) {
        Write-Host "  $($global:UI_GRY)  Log file does not exist yet.$($global:UI_R)"
        return
    }

    Write-Host "  $($global:UI_YLW)  This will erase all current log entries.$($global:UI_R)"
    Write-UiBlankLine

    if (-not (Confirm-Action "Clear the log file?")) {
        Write-Host "  $($global:UI_GRY)  Cancelled.$($global:UI_R)"
        return
    }

    try {
        Clear-Content -Path $global:CORE_LOG_FILE -ErrorAction Stop
        Write-CoreSuccess "Log file cleared."
    } catch {
        Write-CoreError "Failed to clear log: $($_.Exception.Message)"
    }
}

# ── Generate test logs ───────────────────────────────────────
function Generate-TestLogs {
    Write-CoreLog "TEST: manual log entry"
    Write-CoreSuccess "TEST SUCCESS: sample success"
    Write-CoreError "TEST ERROR: sample failure"
}

# ── Main Loop ─────────────────────────────────────────────────
while ($true) {
    Show-Header
    Show-Menu
    $choice = (Read-UiChoice "Choice:").Trim().ToUpper()

    switch ($choice) {
        "1" { Show-LogTail -Lines 25  -Title "LAST 25 LOG LINES";  Pause-Script }
        "2" { Show-LogTail -Lines 100 -Title "LAST 100 LOG LINES"; Pause-Script }
        "3" { Follow-Log }
        "4" { Show-FullLog; Pause-Script }
        "5" { Show-LogInfo; Pause-Script }
        "6" { Clear-LogFile; Pause-Script }
		"7" { Generate-TestLogs; Pause-Script }

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