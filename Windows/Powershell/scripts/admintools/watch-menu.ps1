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
    Write-UiRow "Version" "v$ScriptVersion  by $ScriptAuthor" $global:UI_GRY
    Write-UiBlankLine
}

function Show-Menu {
    Write-UiDivider
    Write-Host "  $($global:UI_GRN)  1)$($global:UI_R)  Watch top CPU processes"
    Write-Host "  $($global:UI_GRN)  2)$($global:UI_R)  Watch top memory processes"
    Write-Host "  $($global:UI_GRN)  3)$($global:UI_R)  Watch active TCP connections"
    Write-Host "  $($global:UI_GRN)  4)$($global:UI_R)  Watch listening ports"
    Write-Host "  $($global:UI_GRN)  5)$($global:UI_R)  Watch drive usage"
    Write-Host "  $($global:UI_GRN)  6)$($global:UI_R)  Watch service status"
    Write-Host "  $($global:UI_GRN)  7)$($global:UI_R)  Watch recent System errors"
    Write-Host "  $($global:UI_GRN)  8)$($global:UI_R)  Watch custom command"
    Write-UiDivider
    Write-Host "  $($global:UI_GRY)  Q)$($global:UI_R)  Quit"
    Write-UiBlankLine
}

# ── Usage bar helper ──────────────────────────────────────────
function MakeBar($pct, $len = 20) {
    $filled = [Math]::Min($len, [Math]::Round($pct / 100 * $len))
    $empty  = $len - $filled
    $bc     = if ($pct -ge 90) { $global:UI_RED } elseif ($pct -ge 70) { $global:UI_YLW } else { $global:UI_GRN }
    return "${bc}" + ("#" * $filled) + "$($global:UI_GRY)" + ("-" * $empty) + "$($global:UI_R)"
}

# ── Refresh interval helper ───────────────────────────────────
function Get-Interval($default = 2) {
    Write-Host -NoNewline "  $($global:UI_YLW)  Refresh interval seconds (default $default): $($global:UI_R)"
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
            Write-Host "  $($global:UI_GRY)  $ts  |  Refreshing every ${IntervalSeconds}s  |  Ctrl+C to return to menu$($global:UI_R)"
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

# (rest of script unchanged… continues exactly as your file)