#--------------------------------------------
# file:     procs-menu.ps1
# author:   Mike Redd
# version:  2.3
# created:  2026-03-30
# updated:  2026-04-01
# desc:     Process management utility
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

$ScriptName    = "Processes Menu"
$ScriptVersion = "2.3"
$ScriptAuthor  = "Mike Redd"

# ── Win32 suspend/resume API ──────────────────────────────────
Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class ProcUtil {
    [DllImport("kernel32.dll")]
    public static extern IntPtr OpenThread(int dwDesiredAccess, bool bInheritHandle, uint dwThreadId);
    [DllImport("kernel32.dll")]
    public static extern uint SuspendThread(IntPtr hThread);
    [DllImport("kernel32.dll")]
    public static extern int ResumeThread(IntPtr hThread);
    [DllImport("kernel32.dll")]
    public static extern bool CloseHandle(IntPtr hHandle);
}
"@ -ErrorAction SilentlyContinue

# ── Header ────────────────────────────────────────────────────
function Show-Header {
    Clear-UiScreen
    $w = Get-UiBoxWidth -MaxWidth 52 -MinWidth 40

    Write-UiHeader -Title $ScriptName -Subtitle "v$ScriptVersion  by $ScriptAuthor" -Width $w
    Write-UiRow "User" "$env:USERNAME@$env:COMPUTERNAME"
    Write-UiRow "Version" "v$ScriptVersion  by $ScriptAuthor" $global:UI_GRY
    Write-UiBlankLine
}

# ── Menu ──────────────────────────────────────────────────────
function Show-Menu {
    Write-UiDivider
    Write-Host "  $($global:UI_GRN)  1)$($global:UI_R)  Top CPU processes"
    Write-Host "  $($global:UI_GRN)  2)$($global:UI_R)  Top memory processes"
    Write-Host "  $($global:UI_GRN)  3)$($global:UI_R)  Search process by name"
    Write-Host "  $($global:UI_GRN)  4)$($global:UI_R)  Process details by PID"
    Write-Host "  $($global:UI_GRN)  5)$($global:UI_R)  Child processes by parent PID"
    Write-Host "  $($global:UI_GRN)  6)$($global:UI_R)  Process by port"
    Write-Host "  $($global:UI_GRN)  7)$($global:UI_R)  Processes started in last X minutes"
    Write-Host "  $($global:UI_GRN)  8)$($global:UI_R)  Process command line by name"
    Write-Host "  $($global:UI_GRN)  9)$($global:UI_R)  Processes outside expected paths"
    Write-UiDivider
    Write-Host "  $($global:UI_RED) 10)$($global:UI_R)  Kill process by name"
    Write-Host "  $($global:UI_RED) 11)$($global:UI_R)  Kill process by PID"
    Write-Host "  $($global:UI_YLW) 12)$($global:UI_R)  Suspend process by PID"
    Write-Host "  $($global:UI_YLW) 13)$($global:UI_R)  Resume process by PID"
    Write-UiDivider
    Write-Host "  $($global:UI_CYN) 14)$($global:UI_R)  Export top CPU to CSV"
    Write-Host "  $($global:UI_CYN) 15)$($global:UI_R)  Export top memory to CSV"
    Write-UiDivider
    Write-Host "  $($global:UI_GRY)  Q)$($global:UI_R)  Quit"
    Write-UiBlankLine
}

# ── Pause ─────────────────────────────────────────────────────
function Pause-Script {
    Pause-Core "Press Enter to return to menu..."
}

# ── Confirm ───────────────────────────────────────────────────
function Confirm-Action($message) {
    return (Confirm-Core $message)
}

# ── Format process row ────────────────────────────────────────
function Format-ProcRow($name, $procId, $cpu, $memMB, $extra = "") {
    $cpuColor = if ($cpu -ge 50) { $global:UI_RED } elseif ($cpu -ge 10) { $global:UI_YLW } else { $global:UI_GRN }
    $memColor = if ($memMB -ge 1000) { $global:UI_RED } elseif ($memMB -ge 300) { $global:UI_YLW } else { $global:UI_GRN }
    $nameStr  = $name.PadRight(28)
    $pidStr   = "$procId".PadRight(7)
    $cpuStr   = ("{0:N1}" -f $cpu).PadRight(8)
    $memStr   = ("{0:N1}" -f $memMB).PadRight(8)

    Write-Host "  $($global:UI_WHT)  $nameStr$($global:UI_R)  $($global:UI_GRY)$pidStr$($global:UI_R)  ${cpuColor}$cpuStr$($global:UI_R)  ${memColor}$memStr MB$($global:UI_R)  $($global:UI_GRY)$extra$($global:UI_R)"
}

# ── 1 — Top CPU ───────────────────────────────────────────────
function Show-TopCPU {
    Show-Header
    $w = Get-UiBoxWidth -MaxWidth 52 -MinWidth 40
    Write-UiBoxTitle -Title "TOP CPU PROCESSES" -Width $w
    Write-UiBlankLine
    Write-Host "  $($global:UI_GRY)  Name                         PID      CPU(s)   RAM$($global:UI_R)"
    Write-Host "  $($global:UI_GRY)  ---------------------------  -------  -------  ---$($global:UI_R)"
    try {
        Get-Process | Sort-Object CPU -Descending | Select-Object -First 20 | ForEach-Object {
            $cpu = if ($_.CPU) { [Math]::Round($_.CPU, 1) } else { 0 }
            $mem = [Math]::Round($_.WorkingSet64 / 1MB, 1)
            Format-ProcRow $_.ProcessName $_.Id $cpu $mem
        }
    } catch {
        Write-CoreError "Failed: $($_.Exception.Message)"
    }
}

# ── 2 — Top Memory ────────────────────────────────────────────
function Show-TopMemory {
    Show-Header
    $w = Get-UiBoxWidth -MaxWidth 52 -MinWidth 40
    Write-UiBoxTitle -Title "TOP MEMORY PROCESSES" -Width $w
    Write-UiBlankLine
    Write-Host "  $($global:UI_GRY)  Name                         PID      CPU(s)   RAM$($global:UI_R)"
    Write-Host "  $($global:UI_GRY)  ---------------------------  -------  -------  ---$($global:UI_R)"
    try {
        Get-Process | Sort-Object WorkingSet64 -Descending | Select-Object -First 20 | ForEach-Object {
            $cpu = if ($_.CPU) { [Math]::Round($_.CPU, 1) } else { 0 }
            $mem = [Math]::Round($_.WorkingSet64 / 1MB, 1)
            Format-ProcRow $_.ProcessName $_.Id $cpu $mem
        }
    } catch {
        Write-CoreError "Failed: $($_.Exception.Message)"
    }
}

# ── 3 — Search by Name ────────────────────────────────────────
function Search-ProcessByName {
    Show-Header
    $w = Get-UiBoxWidth -MaxWidth 52 -MinWidth 40
    Write-UiBoxTitle -Title "SEARCH PROCESS BY NAME" -Width $w
    Write-UiBlankLine
    Write-Host -NoNewline "  $($global:UI_YLW)  Name or keyword: $($global:UI_R)"
    $name = Read-Host
    if (-not $name) { Write-Host "  $($global:UI_GRY)  No input.$($global:UI_R)"; return }

    try {
        $procs = Get-Process | Where-Object { $_.ProcessName -like "*$name*" }
        if (-not $procs) { Write-Host "  $($global:UI_GRY)  No matching processes found.$($global:UI_R)"; return }

        Write-UiBlankLine
        Write-Host "  $($global:UI_GRY)  Found $($procs.Count) match(es)$($global:UI_R)"
        Write-UiBlankLine
        Write-Host "  $($global:UI_GRY)  Name                         PID      CPU(s)   RAM$($global:UI_R)"
        Write-Host "  $($global:UI_GRY)  ---------------------------  -------  -------  ---$($global:UI_R)"
        $procs | ForEach-Object {
            $cpu = if ($_.CPU) { [Math]::Round($_.CPU, 1) } else { 0 }
            $mem = [Math]::Round($_.WorkingSet64 / 1MB, 1)
            Format-ProcRow $_.ProcessName $_.Id $cpu $mem
        }
    } catch {
        Write-CoreError "Failed: $($_.Exception.Message)"
    }
}

# ── 4 — Process Details ───────────────────────────────────────
function Show-ProcessDetails {
    Show-Header
    $w = Get-UiBoxWidth -MaxWidth 52 -MinWidth 40
    Write-UiBoxTitle -Title "PROCESS DETAILS" -Width $w
    Write-UiBlankLine
    Write-Host -NoNewline "  $($global:UI_YLW)  PID: $($global:UI_R)"
    $pidInput = Read-Host
    if (-not $pidInput) { Write-Host "  $($global:UI_GRY)  No PID entered.$($global:UI_R)"; return }

    try {
        $proc = Get-Process -Id ([int]$pidInput) -ErrorAction Stop
        $cim  = Get-CimInstance Win32_Process -Filter "ProcessId = $pidInput" -ErrorAction SilentlyContinue

        Write-Host "  $($global:UI_GRY)  ----------------------------------------------------$($global:UI_R)"
        Write-Host "  $($global:UI_DIM)$($global:UI_WHT)  Name          $($global:UI_R)  $($global:UI_GRN)$($proc.ProcessName)$($global:UI_R)"
        Write-Host "  $($global:UI_DIM)$($global:UI_WHT)  PID           $($global:UI_R)  $($global:UI_GRN)$($proc.Id)$($global:UI_R)"
        Write-Host "  $($global:UI_DIM)$($global:UI_WHT)  CPU (s)       $($global:UI_R)  $(if ($proc.CPU) { $c = [Math]::Round($proc.CPU,2); if ($c -ge 50) { "$($global:UI_RED)$c$($global:UI_R)" } else { "$($global:UI_GRN)$c$($global:UI_R)" } } else { "$($global:UI_GRY)0$($global:UI_R)" })"
        Write-Host "  $($global:UI_DIM)$($global:UI_WHT)  RAM (MB)      $($global:UI_R)  $($global:UI_GRN)$([Math]::Round($proc.WorkingSet64/1MB,1)) MB$($global:UI_R)"
        Write-Host "  $($global:UI_DIM)$($global:UI_WHT)  Start Time    $($global:UI_R)  $($global:UI_GRY)$($proc.StartTime)$($global:UI_R)"
        Write-Host "  $($global:UI_DIM)$($global:UI_WHT)  Path          $($global:UI_R)  $($global:UI_GRY)$($proc.Path)$($global:UI_R)"
        if ($cim) {
            Write-Host "  $($global:UI_DIM)$($global:UI_WHT)  Parent PID    $($global:UI_R)  $($global:UI_GRY)$($cim.ParentProcessId)$($global:UI_R)"
            $cmdLine = if ($cim.CommandLine) { $cim.CommandLine } else { "(unavailable)" }
            Write-Host "  $($global:UI_DIM)$($global:UI_WHT)  Command Line  $($global:UI_R)  $($global:UI_GRY)$cmdLine$($global:UI_R)"
        }
        Write-Host "  $($global:UI_GRY)  ----------------------------------------------------$($global:UI_R)"
    } catch {
        Write-CoreError "Failed: $($_.Exception.Message)"
    }
}

# ── 5 — Child Processes ───────────────────────────────────────
function Show-ChildrenByParentPID {
    Show-Header
    $w = Get-UiBoxWidth -MaxWidth 52 -MinWidth 40
    Write-UiBoxTitle -Title "CHILD PROCESSES BY PARENT PID" -Width $w
    Write-UiBlankLine
    Write-Host -NoNewline "  $($global:UI_YLW)  Parent PID: $($global:UI_R)"
    $pidInput = Read-Host
    if (-not $pidInput) { Write-Host "  $($global:UI_GRY)  No PID entered.$($global:UI_R)"; return }

    try {
        $children = Get-CimInstance Win32_Process -Filter "ParentProcessId = $pidInput" -ErrorAction Stop
        if (-not $children) { Write-Host "  $($global:UI_GRY)  No child processes found.$($global:UI_R)"; return }

        Write-UiBlankLine
        Write-Host "  $($global:UI_GRY)  Found $($children.Count) child process(es)$($global:UI_R)"
        Write-UiBlankLine
        Write-Host "  $($global:UI_GRY)  Name                         PID      Parent   Path$($global:UI_R)"
        Write-Host "  $($global:UI_GRY)  ---------------------------  -------  -------  ----$($global:UI_R)"
        foreach ($c in $children | Sort-Object Name) {
            $nameStr = $c.Name.PadRight(28)
            $pidStr  = "$($c.ProcessId)".PadRight(7)
            $ppStr   = "$($c.ParentProcessId)".PadRight(7)
            $path    = if ($c.ExecutablePath) { $c.ExecutablePath } else { "(unknown)" }
            Write-Host "  $($global:UI_WHT)  $nameStr$($global:UI_R)  $($global:UI_GRY)$pidStr  $ppStr$($global:UI_R)  $($global:UI_GRY)$path$($global:UI_R)"
        }
    } catch {
        Write-CoreError "Failed: $($_.Exception.Message)"
    }
}

# ── 6 — Process by Port ───────────────────────────────────────
function Show-ProcessByPort {
    Show-Header
    $w = Get-UiBoxWidth -MaxWidth 52 -MinWidth 40
    Write-UiBoxTitle -Title "PROCESS BY PORT" -Width $w
    Write-UiBlankLine
    Write-Host -NoNewline "  $($global:UI_YLW)  Port: $($global:UI_R)"
    $port = Read-Host
    if (-not $port) { Write-Host "  $($global:UI_GRY)  No port entered.$($global:UI_R)"; return }

    try {
        $conns = Get-NetTCPConnection -LocalPort ([int]$port) -ErrorAction SilentlyContinue
        if (-not $conns) { Write-Host "  $($global:UI_GRY)  Nothing found on port $port.$($global:UI_R)"; return }

        Write-UiBlankLine
        foreach ($conn in $conns) {
            $proc     = Get-Process -Id $conn.OwningProcess -ErrorAction SilentlyContinue
            $procName = if ($proc) { $proc.ProcessName } else { "Unknown" }
            Write-Host "  $($global:UI_GRY)  ----------------------------------------------------$($global:UI_R)"
            Write-Host "  $($global:UI_DIM)$($global:UI_WHT)  Port     $($global:UI_R)  $($global:UI_GRN)$($conn.LocalPort)$($global:UI_R)"
            Write-Host "  $($global:UI_DIM)$($global:UI_WHT)  State    $($global:UI_R)  $($global:UI_GRN)$($conn.State)$($global:UI_R)"
            Write-Host "  $($global:UI_DIM)$($global:UI_WHT)  PID      $($global:UI_R)  $($global:UI_GRY)$($conn.OwningProcess)$($global:UI_R)"
            Write-Host "  $($global:UI_DIM)$($global:UI_WHT)  Process  $($global:UI_R)  $($global:UI_WHT)$procName$($global:UI_R)"
            Write-Host "  $($global:UI_DIM)$($global:UI_WHT)  Remote   $($global:UI_R)  $($global:UI_GRY)$($conn.RemoteAddress):$($conn.RemotePort)$($global:UI_R)"
        }
        Write-Host "  $($global:UI_GRY)  ----------------------------------------------------$($global:UI_R)"
    } catch {
        Write-CoreError "Failed: $($_.Exception.Message)"
    }
}

# ── 7 — Recently Started ──────────────────────────────────────
function Show-ProcessesStartedRecently {
    Show-Header
    $w = Get-UiBoxWidth -MaxWidth 52 -MinWidth 40
    Write-UiBoxTitle -Title "PROCESSES STARTED IN LAST X MINUTES" -Width $w
    Write-UiBlankLine
    Write-Host -NoNewline "  $($global:UI_YLW)  Minutes (default 10): $($global:UI_R)"
    $minuteStr = Read-Host
    $minutes   = if ($minuteStr -match '^\d+$') { [int]$minuteStr } else { 10 }

    try {
        $cutoff = (Get-Date).AddMinutes(-$minutes)
        $procs  = Get-Process -ErrorAction SilentlyContinue |
            Where-Object { try { $_.StartTime -ge $cutoff } catch { $false } } |
            Sort-Object StartTime -Descending

        if (-not $procs) { Write-Host "  $($global:UI_GRY)  No processes started in the last $minutes minute(s).$($global:UI_R)"; return }

        Write-UiBlankLine
        Write-Host "  $($global:UI_GRY)  Found $($procs.Count) process(es) started in the last $minutes minute(s)$($global:UI_R)"
        Write-UiBlankLine
        Write-Host "  $($global:UI_GRY)  Name                         PID      Started              RAM$($global:UI_R)"
        Write-Host "  $($global:UI_GRY)  ---------------------------  -------  -------------------  ---$($global:UI_R)"
        foreach ($p in $procs) {
            $nameStr  = $p.ProcessName.PadRight(28)
            $pidStr   = "$($p.Id)".PadRight(7)
            $startStr = $p.StartTime.ToString("yyyy-MM-dd HH:mm:ss").PadRight(20)
            $mem      = [Math]::Round($p.WorkingSet64 / 1MB, 1)
            Write-Host "  $($global:UI_GRN)  $nameStr$($global:UI_R)  $($global:UI_GRY)$pidStr  $startStr $($global:UI_R)$($global:UI_GRN)$mem MB$($global:UI_R)"
        }
    } catch {
        Write-CoreError "Failed: $($_.Exception.Message)"
    }
}

# ── 8 — Command Line by Name ──────────────────────────────────
function Show-ProcessCommandLineByName {
    Show-Header
    $w = Get-UiBoxWidth -MaxWidth 52 -MinWidth 40
    Write-UiBoxTitle -Title "PROCESS COMMAND LINE BY NAME" -Width $w
    Write-UiBlankLine
    Write-Host -NoNewline "  $($global:UI_YLW)  Name or keyword: $($global:UI_R)"
    $name = Read-Host
    if (-not $name) { Write-Host "  $($global:UI_GRY)  No input.$($global:UI_R)"; return }

    try {
        $matches = Get-CimInstance Win32_Process -ErrorAction Stop |
            Where-Object { $_.Name -like "*$name*" }
        if (-not $matches) { Write-Host "  $($global:UI_GRY)  No matching processes found.$($global:UI_R)"; return }

        Write-UiBlankLine
        foreach ($m in $matches) {
            Write-Host "  $($global:UI_GRY)  ----------------------------------------------------$($global:UI_R)"
            Write-Host "  $($global:UI_DIM)$($global:UI_WHT)  Name       $($global:UI_R)  $($global:UI_WHT)$($m.Name)$($global:UI_R)"
            Write-Host "  $($global:UI_DIM)$($global:UI_WHT)  PID        $($global:UI_R)  $($global:UI_GRY)$($m.ProcessId)$($global:UI_R)"
            Write-Host "  $($global:UI_DIM)$($global:UI_WHT)  Parent PID $($global:UI_R)  $($global:UI_GRY)$($m.ParentProcessId)$($global:UI_R)"
            Write-Host "  $($global:UI_DIM)$($global:UI_WHT)  Path       $($global:UI_R)  $($global:UI_GRY)$($m.ExecutablePath)$($global:UI_R)"
            $cmd = if ($m.CommandLine) { $m.CommandLine } else { "(unavailable)" }
            Write-Host "  $($global:UI_DIM)$($global:UI_WHT)  Cmd Line   $($global:UI_R)  $($global:UI_GRN)$cmd$($global:UI_R)"
        }
        Write-Host "  $($global:UI_GRY)  ----------------------------------------------------$($global:UI_R)"
    } catch {
        Write-CoreError "Failed: $($_.Exception.Message)"
    }
}

# ── 9 — Outside Expected Paths ────────────────────────────────
function Show-ProcessesOutsideExpectedPaths {
    Show-Header
    $w = Get-UiBoxWidth -MaxWidth 52 -MinWidth 40
    Write-UiBoxTitle -Title "PROCESSES OUTSIDE EXPECTED PATHS" -Width $w
    Write-UiBlankLine

    $allowed = @(
        "$env:SystemRoot",
        "C:\Program Files",
        "C:\Program Files (x86)",
        $env:LOCALAPPDATA,
        $env:ProgramData,
        $env:APPDATA
    ) | Where-Object { $_ }

    try {
        $procs = Get-CimInstance Win32_Process -ErrorAction Stop | Where-Object {
            $p = $_
            $p.ExecutablePath -and
            -not ($allowed | Where-Object {
                $_ -and $p.ExecutablePath.StartsWith($_, [System.StringComparison]::OrdinalIgnoreCase)
            })
        } | Sort-Object Name

        if (-not $procs) {
            Write-Host "  $($global:UI_GRN)  No processes found outside expected paths.$($global:UI_R)"
            return
        }

        Write-Host "  $($global:UI_YLW)  Found $($procs.Count) process(es) outside expected paths:$($global:UI_R)"
        Write-UiBlankLine
        Write-Host "  $($global:UI_GRY)  Name                         PID      Path$($global:UI_R)"
        Write-Host "  $($global:UI_GRY)  ---------------------------  -------  ----$($global:UI_R)"
        foreach ($p in $procs) {
            $nameStr = $p.Name.PadRight(28)
            $pidStr  = "$($p.ProcessId)".PadRight(7)
            Write-Host "  $($global:UI_YLW)  $nameStr$($global:UI_R)  $($global:UI_GRY)$pidStr$($global:UI_R)  $($global:UI_WHT)$($p.ExecutablePath)$($global:UI_R)"
        }
    } catch {
        Write-CoreError "Failed: $($_.Exception.Message)"
    }
}

# ── 10 — Kill by Name ─────────────────────────────────────────
function Kill-ProcessByName {
    Show-Header
    $w = Get-UiBoxWidth -MaxWidth 52 -MinWidth 40
    Write-UiBoxTitle -Title "KILL PROCESS BY NAME" -Width $w
    Write-UiBlankLine
    Write-Host -NoNewline "  $($global:UI_YLW)  Process name: $($global:UI_R)"
    $name = Read-Host
    if (-not $name) { Write-Host "  $($global:UI_GRY)  No input.$($global:UI_R)"; return }

    try {
        $procs = Get-Process -Name $name -ErrorAction SilentlyContinue
        if (-not $procs) { Write-Host "  $($global:UI_GRY)  No process found: $name$($global:UI_R)"; return }

        Write-UiBlankLine
        foreach ($p in $procs) {
            Write-Host "  $($global:UI_YLW)  $($p.ProcessName)  PID $($p.Id)  $([Math]::Round($p.WorkingSet64/1MB,1)) MB$($global:UI_R)"
        }

        if (-not (Confirm-Action "Kill all '$name' process(es)?")) {
            Write-Host "  $($global:UI_GRY)  Cancelled.$($global:UI_R)"
            return
        }
        $procs | Stop-Process -Force -ErrorAction Stop
        Write-CoreSuccess "Done."
    } catch {
        Write-Host "  $($global:UI_RED)  Failed: $($_.Exception.Message)$($global:UI_R)"
    }
}

# ── 11 — Kill by PID ──────────────────────────────────────────
function Kill-ProcessByPID {
    Show-Header
    $w = Get-UiBoxWidth -MaxWidth 52 -MinWidth 40
    Write-UiBoxTitle -Title "KILL PROCESS BY PID" -Width $w
    Write-UiBlankLine
    Write-Host -NoNewline "  $($global:UI_YLW)  PID: $($global:UI_R)"
    $pidInput = Read-Host
    if (-not $pidInput) { Write-Host "  $($global:UI_GRY)  No PID entered.$($global:UI_R)"; return }

    try {
        $proc = Get-Process -Id ([int]$pidInput) -ErrorAction Stop
        Write-UiBlankLine
        Write-Host "  $($global:UI_YLW)  $($proc.ProcessName)  PID $($proc.Id)  $([Math]::Round($proc.WorkingSet64/1MB,1)) MB$($global:UI_R)"

        if (-not (Confirm-Action "Kill PID $pidInput?")) {
            Write-Host "  $($global:UI_GRY)  Cancelled.$($global:UI_R)"
            return
        }
        Stop-Process -Id ([int]$pidInput) -Force -ErrorAction Stop
        Write-CoreSuccess "Done."
    } catch {
        Write-CoreError "Failed: $($_.Exception.Message)"
    }
}

# ── 12 — Suspend ──────────────────────────────────────────────
function Suspend-ProcessByPID {
    Show-Header
    $w = Get-UiBoxWidth -MaxWidth 52 -MinWidth 40
    Write-UiBoxTitle -Title "SUSPEND PROCESS BY PID" -Width $w
    Write-UiBlankLine
    Write-Host -NoNewline "  $($global:UI_YLW)  PID: $($global:UI_R)"
    $pidInput = Read-Host
    if (-not $pidInput) { Write-Host "  $($global:UI_GRY)  No PID entered.$($global:UI_R)"; return }

    try {
        $proc = Get-Process -Id ([int]$pidInput) -ErrorAction Stop
        Write-Host "  $($global:UI_WHT)  Found: $($proc.ProcessName) (PID $($proc.Id))$($global:UI_R)"

        if (-not (Confirm-Action "Suspend PID $pidInput?")) {
            Write-Host "  $($global:UI_GRY)  Cancelled.$($global:UI_R)"
            return
        }
        foreach ($thread in $proc.Threads) {
            $h = [ProcUtil]::OpenThread(0x0002, $false, [uint32]$thread.Id)
            if ($h -ne [IntPtr]::Zero) {
                [ProcUtil]::SuspendThread($h) | Out-Null
                [ProcUtil]::CloseHandle($h) | Out-Null
            }
        }
        Write-CoreSuccess "Process suspended."
    } catch {
        Write-CoreError "Failed: $($_.Exception.Message)"
    }
}

# ── 13 — Resume ───────────────────────────────────────────────
function Resume-ProcessByPID {
    Show-Header
    $w = Get-UiBoxWidth -MaxWidth 52 -MinWidth 40
    Write-UiBoxTitle -Title "RESUME PROCESS BY PID" -Width $w
    Write-UiBlankLine
    Write-Host -NoNewline "  $($global:UI_YLW)  PID: $($global:UI_R)"
    $pidInput = Read-Host
    if (-not $pidInput) { Write-Host "  $($global:UI_GRY)  No PID entered.$($global:UI_R)"; return }

    try {
        $proc = Get-Process -Id ([int]$pidInput) -ErrorAction Stop
        Write-Host "  $($global:UI_WHT)  Found: $($proc.ProcessName) (PID $($proc.Id))$($global:UI_R)"

        if (-not (Confirm-Action "Resume PID $pidInput?")) {
            Write-Host "  $($global:UI_GRY)  Cancelled.$($global:UI_R)"
            return
        }
        foreach ($thread in $proc.Threads) {
            $h = [ProcUtil]::OpenThread(0x0002, $false, [uint32]$thread.Id)
            if ($h -ne [IntPtr]::Zero) {
                while ([ProcUtil]::ResumeThread($h) -gt 0) { }
                [ProcUtil]::CloseHandle($h) | Out-Null
            }
        }
        Write-CoreSuccess "Process resumed."
    } catch {
        Write-CoreError "Failed: $($_.Exception.Message)"
    }
}

# ── 14 — Export Top CPU CSV ───────────────────────────────────
function Export-TopCPUToCsv {
    Show-Header
    $w = Get-UiBoxWidth -MaxWidth 52 -MinWidth 40
    Write-UiBoxTitle -Title "EXPORT TOP CPU TO CSV" -Width $w
    Write-UiBlankLine
    $defaultFile = Join-Path $HOME "top_cpu_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"
    Write-Host "  $($global:UI_GRY)  Default: $defaultFile$($global:UI_R)"
    Write-Host -NoNewline "  $($global:UI_YLW)  Output path (Enter for default): $($global:UI_R)"
    $outFile = Read-Host
    if (-not $outFile) { $outFile = $defaultFile }

    try {
        $data = Get-Process | Sort-Object CPU -Descending | Select-Object -First 20 |
            Select-Object ProcessName, Id,
                @{N="CPU_s";  E={ if ($_.CPU) { [Math]::Round($_.CPU,2) } else { 0 } }},
                @{N="RAM_MB"; E={ [Math]::Round($_.WorkingSet64/1MB,2) }},
                StartTime
        $data | Export-Csv -Path $outFile -NoTypeInformation
        Write-CoreSuccess "Exported to: $outFile"
    } catch {
        Write-CoreError "Failed: $($_.Exception.Message)"
    }
}

# ── 15 — Export Top Memory CSV ────────────────────────────────
function Export-TopMemoryToCsv {
    Show-Header
    $w = Get-UiBoxWidth -MaxWidth 52 -MinWidth 40
    Write-UiBoxTitle -Title "EXPORT TOP MEMORY TO CSV" -Width $w
    Write-UiBlankLine
    $defaultFile = "$HOME\top_memory_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"
    Write-Host "  $($global:UI_GRY)  Default: $defaultFile$($global:UI_R)"
    Write-Host -NoNewline "  $($global:UI_YLW)  Output path (Enter for default): $($global:UI_R)"
    $outFile = Read-Host
    if (-not $outFile) { $outFile = $defaultFile }

    try {
        $data = Get-Process | Sort-Object WorkingSet64 -Descending | Select-Object -First 20 |
            Select-Object ProcessName, Id,
                @{N="RAM_MB"; E={ [Math]::Round($_.WorkingSet64/1MB,2) }},
                @{N="CPU_s";  E={ if ($_.CPU) { [Math]::Round($_.CPU,2) } else { 0 } }},
                StartTime
        $data | Export-Csv -Path $outFile -NoTypeInformation
        Write-CoreSuccess "Exported to: $outFile"
    } catch {
        Write-CoreError "Failed: $($_.Exception.Message)"
    }
}

# ── Main Loop ─────────────────────────────────────────────────
while ($true) {
    Show-Header
    Show-Menu
    $choice = (Read-UiChoice "Choice:").Trim().ToUpper()

    switch ($choice) {
        "1"  { Show-TopCPU;                        Pause-Script }
        "2"  { Show-TopMemory;                     Pause-Script }
        "3"  { Search-ProcessByName;               Pause-Script }
        "4"  { Show-ProcessDetails;                Pause-Script }
        "5"  { Show-ChildrenByParentPID;           Pause-Script }
        "6"  { Show-ProcessByPort;                 Pause-Script }
        "7"  { Show-ProcessesStartedRecently;      Pause-Script }
        "8"  { Show-ProcessCommandLineByName;      Pause-Script }
        "9"  { Show-ProcessesOutsideExpectedPaths; Pause-Script }
        "10" { Kill-ProcessByName;                 Pause-Script }
        "11" { Kill-ProcessByPID;                  Pause-Script }
        "12" { Suspend-ProcessByPID;               Pause-Script }
        "13" { Resume-ProcessByPID;                Pause-Script }
        "14" { Export-TopCPUToCsv;                 Pause-Script }
        "15" { Export-TopMemoryToCsv;              Pause-Script }

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