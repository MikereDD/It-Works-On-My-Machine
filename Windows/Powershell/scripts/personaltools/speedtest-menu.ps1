#--------------------------------------------
# file:     speedtest-menu.ps1
# author:   Mike Redd
# version:  2.1.0
# created:  2026-03-29
# updated:  2026-06-17
# desc:     Speed test with logging, history,
#           stats, scheduled runs and color output
#           (UI / prompts via shared ui.ps1 + core.ps1)
#--------------------------------------------

# ── Load shared toolkit modules (ui + core) ───────────────────
# Prefer the profile dir the launcher forwards ($PSProfileDir); then copies next
# to this script; then $HOME\PS (where the toolkit keeps ui.ps1 / core.ps1).
$psLib = if ($PSProfileDir -and (Test-Path -LiteralPath (Join-Path $PSProfileDir 'core.ps1'))) {
    $PSProfileDir
} elseif (Test-Path -LiteralPath "$PSScriptRoot\core.ps1") {
    $PSScriptRoot
} else {
    "$HOME\PS"
}
. (Join-Path $psLib 'ui.ps1')
. (Join-Path $psLib 'core.ps1')

$ScriptName    = "Speed Test"
$ScriptVersion = "2.1.0"
$ScriptAuthor  = "Mike Redd"

# ── Local color aliases ───────────────────────────────────────
# Colors are defined once in ui.ps1; alias the short names the custom layouts
# (bars, history/stats tables) below already use so there's a single source.
$R   = $global:UI_R;   $B   = $global:UI_B;   $DIM = $global:UI_DIM
$CYN = $global:UI_CYN; $YLW = $global:UI_YLW; $GRN = $global:UI_GRN
$RED = $global:UI_RED; $MAG = $global:UI_MAG; $GRY = $global:UI_GRY
$WHT = $global:UI_WHT

# ── Log file — use $HOME so it always resolves correctly ─────
# $PSScriptRoot is empty when run interactively from a terminal
$LogDir  = "$HOME\PS\logs"
$LogFile = "$LogDir\speedtest_log.csv"

# ── Helpers ───────────────────────────────────────────────────
function Show-Banner($title) {
    Write-UiBoxTitle -Title $title -Width (Get-UiBoxWidth -MaxWidth 72 -MinWidth 48)
}

function MakeBar($value, $max, $len = 30) {
    if ($max -le 0) { $max = 1 }
    $pct    = [Math]::Min(100, [Math]::Round($value / $max * 100))
    $filled = [Math]::Round($pct / 100 * $len)
    $empty  = $len - $filled
    $bc     = if ($pct -ge 80) { $GRN } elseif ($pct -ge 40) { $YLW } else { $RED }
    return "${bc}" + ("#" * $filled) + "${GRY}" + ("-" * $empty) + "${R}"
}

function Get-LogCount {
    if (-not (Test-Path $LogFile)) { return 0 }
    return (Import-Csv $LogFile | Measure-Object).Count
}

# ── Find speedtest CLI ────────────────────────────────────────
function Get-SpeedtestPath {
    $cmd = Get-Command speedtest -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }

    # Fixed: missing comma between paths in original
    $paths = @(
        "C:\Program Files\Ookla\Speedtest\speedtest.exe",
        "C:\Program Files (x86)\Ookla\Speedtest\speedtest.exe",
        "$HOME\Apps\Ookla\Speedtest\speedtest.exe",
        "$HOME\scoop\shims\speedtest.exe",
        "$HOME\AppData\Local\Microsoft\WinGet\Packages\Ookla.Speedtest.CLI\speedtest.exe"
    )

    foreach ($p in $paths) {
        if (Test-Path $p) { return $p }
    }
    return $null
}

# ============================================================
#  HEADER & MENU
# ============================================================
function Show-Header {
    Clear-UiScreen
    $BoxWidth = Get-UiBoxWidth -MaxWidth 72 -MinWidth 48

    Write-UiHeader -Title $ScriptName -Subtitle "v$ScriptVersion  by $ScriptAuthor" -Width $BoxWidth

    Write-UiRow "User" "$env:USERNAME@$env:COMPUTERNAME"

    $count = Get-LogCount
    if ($count -gt 0) {
        Write-UiRow "Log" "$count test(s) recorded  --  $LogFile" -ValueColor $global:UI_GRY
    } else {
        Write-UiRow "Log" "No tests recorded yet" -ValueColor $global:UI_GRY
    }

    $stPath = Get-SpeedtestPath
    if ($stPath) {
        Write-UiRow "CLI" "Found  -  $stPath" -ValueColor $global:UI_GRN
    } else {
        Write-UiRow "CLI" "Not found  (see option 6)" -ValueColor $global:UI_RED
    }

    Write-UiBlankLine
}

function Show-Menu {
    Write-UiDivider
    Write-Host "  ${GRN}  1)${R}  Run Speed Test"
    Write-Host "  ${GRN}  2)${R}  View History"
    Write-Host "  ${GRN}  3)${R}  View Stats  ${GRY}(avg / min / max)${R}"
    Write-Host "  ${GRN}  4)${R}  Scheduled Run  ${GRY}(run N tests with delay)${R}"
    Write-UiDivider
    Write-Host "  ${YLW}  5)${R}  Clear Log"
    Write-Host "  ${GRN}  6)${R}  How to Install Speedtest CLI"
    Write-UiDivider
    Write-Host "  ${GRY}  Q)${R}  Quit"
    Write-UiBlankLine
}

# ============================================================
#  ENSURE LOG DIR EXISTS
# ============================================================
function Ensure-LogDir {
    if (-not (Test-Path $LogDir)) {
        New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
    }
}

# ============================================================
#  RUN ONE TEST AND RETURN RESULT OBJECT
# ============================================================
function Invoke-SingleTest($stPath) {
    Write-Host "  ${CYN}  Running speed test...${R}"
    Write-Host "  ${GRY}  This may take 20-40 seconds.${R}"
    Write-Host ""

    $raw = & $stPath --accept-license --accept-gdpr --format=json 2>$null

    if (-not $raw) { throw "No output from speedtest CLI." }

    $result = $raw | ConvertFrom-Json

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $ping      = [Math]::Round([double]$result.ping.latency, 2)
    $jitter    = [Math]::Round([double]$result.ping.jitter,  2)
    $down      = [Math]::Round(([double]$result.download.bandwidth * 8 / 1MB), 2)
    $up        = [Math]::Round(([double]$result.upload.bandwidth   * 8 / 1MB), 2)
    $server    = "$($result.server.name), $($result.server.location)"
    $isp       = $result.isp
    $url       = $result.result.url

    return [PSCustomObject]@{
        Time     = $timestamp
        ISP      = $isp
        Server   = $server
        Ping_ms  = $ping
        Jitter   = $jitter
        Download = $down
        Upload   = $up
        URL      = $url
    }
}

# ============================================================
#  DISPLAY ONE RESULT
# ============================================================
function Show-Result($r, $maxDown = 1000, $maxUp = 1000) {
    Write-UiDivider
    Write-UiRow "Time"   $r.Time
    Write-UiRow "ISP"    $r.ISP
    Write-UiRow "Server" $r.Server
    Write-Host ""

    # Ping
    $pingColor = if ($r.Ping_ms -lt 20) { $GRN } elseif ($r.Ping_ms -lt 80) { $YLW } else { $RED }
    Write-UiRow "Ping"   "$($r.Ping_ms) ms" -ValueColor $pingColor
    Write-UiRow "Jitter" "$($r.Jitter) ms"  -ValueColor $global:UI_GRY

    Write-Host ""

    $dlLabel  = "Download".PadRight(20)
    $ulLabel2 = "Upload".PadRight(20)
    $urlLabel = "Result URL".PadRight(20)

    # Download bar
    $downBar = MakeBar $r.Download $maxDown 30
    $downColor = if ($r.Download -ge 100) { $GRN } elseif ($r.Download -ge 25) { $YLW } else { $RED }
    Write-Host "  ${DIM}${WHT}$dlLabel${R}  ${downColor}${B}$($r.Download) Mbps${R}"
    $indent = " " * 24
    Write-Host "  $indent[$downBar]"

    Write-Host ""

    # Upload bar
    $upBar   = MakeBar $r.Upload $maxUp 30
    $upColor = if ($r.Upload -ge 20) { $GRN } elseif ($r.Upload -ge 5) { $YLW } else { $RED }
    Write-Host "  ${DIM}${WHT}$ulLabel2${R}  ${upColor}${B}$($r.Upload) Mbps${R}"
    Write-Host "  $indent[$upBar]"

    Write-Host ""
    if ($r.URL) {
        Write-Host "  ${DIM}${WHT}$urlLabel${R}  ${CYN}$($r.URL)${R}"
    }
    Write-UiDivider
}

# ============================================================
#  SAVE RESULT TO CSV
# ============================================================
function Save-Result($r) {
    Ensure-LogDir
    # Fixed: cast fields to correct types before saving
    $row = [PSCustomObject]@{
        Time     = $r.Time
        ISP      = $r.ISP
        Server   = $r.Server
        Ping_ms  = [double]$r.Ping_ms
        Jitter   = [double]$r.Jitter
        Download = [double]$r.Download
        Upload   = [double]$r.Upload
        URL      = $r.URL
    }
    if (-not (Test-Path $LogFile)) {
        $row | Export-Csv -Path $LogFile -NoTypeInformation
    } else {
        $row | Export-Csv -Path $LogFile -Append -NoTypeInformation
    }
}

# ============================================================
#  1 — RUN SPEED TEST
# ============================================================
function Run-Speedtest {
    Show-Header
    Show-Banner "RUN SPEED TEST"

    $stPath = Get-SpeedtestPath
    if (-not $stPath) {
        Write-CoreError "Speedtest CLI not found."
        Write-Host "  ${YLW}  Select option 6 from the menu for install instructions.${R}"
        return
    }

    try {
        $r = Invoke-SingleTest $stPath
        Show-Result $r
        Save-Result $r
        Write-CoreSuccess "Result saved to log."
    } catch {
        Write-CoreError "Speed test failed: $($_.Exception.Message)"
    }
}

# ============================================================
#  2 — VIEW HISTORY
# ============================================================
function Show-History {
    Show-Header
    Show-Banner "SPEED TEST HISTORY"

    if (-not (Test-Path $LogFile)) {
        Write-Host "  ${GRY}  No history yet. Run a speed test first.${R}"
        return
    }

    Write-Host -NoNewline "  ${YLW}  How many entries to show? (default 10): ${R}"
    $countStr = Read-Host
    $showCount = if ($countStr -match '^\d+$') { [int]$countStr } else { 10 }

    $data = Import-Csv $LogFile | Select-Object -Last $showCount

    Write-Host ""
    Write-Host "  ${GRY}  Date/Time             Down(Mbps)  Up(Mbps)  Ping(ms)  ISP${R}"
    Write-Host "  ${GRY}  -------------------   ----------  --------  --------  ---${R}"

    foreach ($row in $data) {
        $d = [double]$row.Download
        $u = [double]$row.Upload
        $p = [double]$row.Ping_ms

        $dColor = if ($d -ge 100) { $GRN } elseif ($d -ge 25) { $YLW } else { $RED }
        $uColor = if ($u -ge 20)  { $GRN } elseif ($u -ge 5)  { $YLW } else { $RED }
        $pColor = if ($p -lt 20)  { $GRN } elseif ($p -lt 80) { $YLW } else { $RED }

        $ts  = $row.Time.PadRight(21)
        $dl  = ("{0:N1}" -f $d).PadRight(10)
        $ul  = ("{0:N1}" -f $u).PadRight(8)
        $pms = ("{0:N1}" -f $p).PadRight(8)

        Write-Host "  ${GRY}  $ts  ${R}${dColor}$dl${R}  ${uColor}$ul${R}  ${pColor}$pms${R}  ${WHT}$($row.ISP)${R}"
    }

    Write-Host ""
    $total = (Import-Csv $LogFile | Measure-Object).Count
    Write-Host "  ${GRY}  Showing last $showCount of $total total entries.${R}"
}

# ============================================================
#  3 — STATS (avg / min / max)
# ============================================================
function Show-Stats {
    Show-Header
    Show-Banner "SPEED STATS"

    if (-not (Test-Path $LogFile)) {
        Write-Host "  ${GRY}  No data available. Run a speed test first.${R}"
        return
    }

    # Fixed: cast to [double] — CSV imports everything as strings
    # so Measure-Object -Average returns 0 without the cast
    $data = Import-Csv $LogFile | ForEach-Object {
        [PSCustomObject]@{
            Download = [double]$_.Download
            Upload   = [double]$_.Upload
            Ping_ms  = [double]$_.Ping_ms
            Jitter   = [double]$_.Jitter
        }
    }

    $count   = ($data | Measure-Object).Count
    $avgDown = [Math]::Round(($data.Download | Measure-Object -Average).Average, 2)
    $minDown = [Math]::Round(($data.Download | Measure-Object -Minimum).Minimum, 2)
    $maxDown = [Math]::Round(($data.Download | Measure-Object -Maximum).Maximum, 2)
    $avgUp   = [Math]::Round(($data.Upload   | Measure-Object -Average).Average, 2)
    $minUp   = [Math]::Round(($data.Upload   | Measure-Object -Minimum).Minimum, 2)
    $maxUp   = [Math]::Round(($data.Upload   | Measure-Object -Maximum).Maximum, 2)
    $avgPing = [Math]::Round(($data.Ping_ms  | Measure-Object -Average).Average, 2)
    $minPing = [Math]::Round(($data.Ping_ms  | Measure-Object -Minimum).Minimum, 2)
    $maxPing = [Math]::Round(($data.Ping_ms  | Measure-Object -Maximum).Maximum, 2)
    $avgJit  = [Math]::Round(($data.Jitter   | Measure-Object -Average).Average, 2)

    Write-Host "  ${GRY}  Based on $count test(s)${R}"
    Write-Host ""
    Write-UiDivider
    $colHeader = " " * 24
    Write-Host "  ${DIM}${WHT}${colHeader}${R}  ${CYN}Avg${R}          ${GRN}Best${R}         ${RED}Worst${R}"
    Write-UiDivider

    # Download row + bar
    $dlLabel  = "Download (Mbps)".PadRight(22)
    $dlAvgStr = "$avgDown".PadRight(12)
    $dlMaxStr = "$maxDown".PadRight(12)
    Write-Host "  ${DIM}${WHT}$dlLabel${R}  ${CYN}$dlAvgStr${R}${GRN}$dlMaxStr${R}${RED}$minDown${R}"
    $avgBar = MakeBar $avgDown $maxDown 30
    $avgLabel = "Avg".PadRight(22)
    Write-Host "  $avgLabel  [$avgBar] ${CYN}$avgDown Mbps${R}"

    Write-Host ""

    # Upload row + bar
    $ulLabel  = "Upload (Mbps)".PadRight(22)
    $ulAvgStr = "$avgUp".PadRight(12)
    $ulMaxStr = "$maxUp".PadRight(12)
    Write-Host "  ${DIM}${WHT}$ulLabel${R}  ${CYN}$ulAvgStr${R}${GRN}$ulMaxStr${R}${RED}$minUp${R}"
    $avgUpBar  = MakeBar $avgUp $maxUp 30
    Write-Host "  $avgLabel  [$avgUpBar] ${CYN}$avgUp Mbps${R}"

    Write-Host ""

    # Ping
    $pingLabel   = "Ping (ms)".PadRight(22)
    $pingAvgStr  = "$avgPing".PadRight(12)
    $pingMinStr  = "$minPing".PadRight(12)
    $jitterLabel = "Jitter (ms) avg".PadRight(22)
    Write-Host "  ${DIM}${WHT}$pingLabel${R}  ${CYN}$pingAvgStr${R}${GRN}$pingMinStr${R}${RED}$maxPing${R}"
    Write-Host "  ${DIM}${WHT}$jitterLabel${R}  ${GRY}$avgJit ms${R}"

    Write-Host ""
    Write-UiDivider
    Write-Host "  ${DIM}  Columns: Avg | Best | Worst${R}"
}

# ============================================================
#  4 — SCHEDULED RUN
# ============================================================
function Run-Scheduled {
    Show-Header
    Show-Banner "SCHEDULED RUN"

    Write-Host "  ${GRY}  Runs multiple speed tests with a delay between each.${R}"
    Write-Host "  ${GRY}  All results are logged. Press Ctrl+C to stop early.${R}"
    Write-Host ""

    $stPath = Get-SpeedtestPath
    if (-not $stPath) {
        Write-CoreError "Speedtest CLI not found."
        Write-Host "  ${YLW}  Select option 6 from the menu for install instructions.${R}"
        return
    }

    Write-Host -NoNewline "  ${YLW}  Number of tests to run: ${R}"
    $countStr = Read-Host
    if ($countStr -notmatch '^\d+$' -or [int]$countStr -lt 1) {
        Write-CoreError "Invalid number."; return
    }
    $totalRuns = [int]$countStr

    Write-Host -NoNewline "  ${YLW}  Delay between tests in minutes (default 30): ${R}"
    $delayStr = Read-Host
    $delayMin = if ($delayStr -match '^\d+$') { [int]$delayStr } else { 30 }
    $delaySec = $delayMin * 60

    Write-Host ""
    if (-not (Confirm-Core "Run $totalRuns test(s) every $delayMin minute(s)?")) {
        Write-Host "  ${GRY}  Cancelled.${R}"; return
    }

    Write-Host ""

    for ($i = 1; $i -le $totalRuns; $i++) {
        Write-Host "  ${CYN}${B}  [$i / $totalRuns]${R}  $(Get-Date -Format 'HH:mm:ss')"
        Write-Host ""

        try {
            $r = Invoke-SingleTest $stPath
            Show-Result $r
            Save-Result $r
            Write-CoreSuccess "Saved."
        } catch {
            Write-CoreError "Test $i failed: $($_.Exception.Message)"
        }

        if ($i -lt $totalRuns) {
            $nextTime = (Get-Date).AddSeconds($delaySec).ToString("HH:mm:ss")
            Write-Host ""
            Write-Host "  ${GRY}  Next test at $nextTime. Press Ctrl+C to stop.${R}"

            # Countdown with progress
            $remaining = $delaySec
            while ($remaining -gt 0) {
                $mins = [Math]::Floor($remaining / 60)
                $secs = $remaining % 60
                Write-Host -NoNewline "`r  ${GRY}  Waiting: ${YLW}${mins}m ${secs}s${GRY} remaining...   ${R}"
                Start-Sleep -Seconds 1
                $remaining--
            }
            Write-Host ""
            Write-Host ""
        }
    }

    Write-Host ""
    Write-Host "  ${GRN}${B}  All $totalRuns test(s) complete.${R}"
    Write-Host "  ${GRY}  View results with option 2 or 3.${R}"
}

# ============================================================
#  5 — CLEAR LOG
# ============================================================
function Clear-Log {
    Show-Header
    Show-Banner "CLEAR LOG"

    if (-not (Test-Path $LogFile)) {
        Write-Host "  ${GRY}  No log file found. Nothing to clear.${R}"
        return
    }

    $count = Get-LogCount
    Write-Host "  ${YLW}  Log contains $count test result(s).${R}"
    Write-Host "  ${RED}  This cannot be undone.${R}"

    if (Confirm-Core "Delete all $count log entries?") {
        Remove-Item $LogFile -Force
        Write-CoreSuccess "Log cleared."
    } else {
        Write-Host "  ${GRY}  Cancelled.${R}"
    }
}

# ============================================================
#  6 — INSTALL INSTRUCTIONS
# ============================================================
function Show-InstallInfo {
    Show-Header
    Show-Banner "HOW TO INSTALL SPEEDTEST CLI"

    Write-Host "  ${WHT}  The Ookla Speedtest CLI is required to run tests.${R}"
    Write-Host ""
    Write-Host "  ${MAG}${B}  Option A - winget (easiest, Windows 10/11):${R}"
    Write-Host "  ${GRN}    winget install Ookla.Speedtest.CLI${R}"
    Write-Host ""
    Write-Host "  ${MAG}${B}  Option B - scoop:${R}"
    Write-Host "  ${GRN}    scoop install speedtest${R}"
    Write-Host ""
    Write-Host "  ${MAG}${B}  Option C - manual download:${R}"
    Write-Host "  ${CYN}    https://www.speedtest.net/apps/cli${R}"
    Write-Host "  ${GRY}    Download the Windows zip, extract speedtest.exe${R}"
    Write-Host "  ${GRY}    Place it in one of these locations:${R}"
    Write-Host "  ${GRY}      $HOME\Apps\Ookla\Speedtest\speedtest.exe${R}"
    Write-Host "  ${GRY}      C:\Program Files\Ookla\Speedtest\speedtest.exe${R}"
    Write-Host ""
    Write-Host "  ${MAG}${B}  After installing, verify it works:${R}"
    Write-Host "  ${GRN}    speedtest --version${R}"
    Write-Host ""

    $stPath = Get-SpeedtestPath
    if ($stPath) {
        Write-Host "  ${GRN}${B}  CLI already found at: $stPath${R}"
    } else {
        Write-Host "  ${RED}  CLI not currently found. Install and restart this script.${R}"
    }
}

# ============================================================
#  MAIN LOOP
# ============================================================
while ($true) {
    Show-Header
    Show-Menu

    $choice = (Read-UiChoice "Choice:").Trim().ToUpper()

    switch ($choice) {
        "1" { Run-Speedtest;     Pause-Core "Press Enter to return to menu..." }
        "2" { Show-History;      Pause-Core "Press Enter to return to menu..." }
        "3" { Show-Stats;        Pause-Core "Press Enter to return to menu..." }
        "4" { Run-Scheduled;     Pause-Core "Press Enter to return to menu..." }
        "5" { Clear-Log;         Pause-Core "Press Enter to return to menu..." }
        "6" { Show-InstallInfo;  Pause-Core "Press Enter to return to menu..." }
        "Q" {
            Write-UiBlankLine
            Write-Host "  ${CYN}  Bye.${R}"
            Write-UiBlankLine
            exit 0
        }
        default {
            Write-CoreError "Invalid option."
            Start-Sleep -Seconds 1
        }
    }
}
