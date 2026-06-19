#--------------------------------------------
# file:     admin-menu-gui.ps1
# author:   Mike Redd
# version:  1.0.0
# created:  2026-06-19
# updated:  2026-06-19
# desc:     Unified Admin Tools dashboard (WinForms front-end for the
#           SystemInfo / Power / Updates / Network / Disk / Events /
#           Services / Watch / Processes / Logs console menus).
#           Standalone: does NOT depend on ui.ps1 / core.ps1.
#           Requires Windows PowerShell 5.1 in -STA (WinForms).
#--------------------------------------------

# ── WinForms bootstrap ────────────────────────────────────────
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

# ── Win32 thread suspend/resume (for the Processes tab) ───────
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

# ── Theme ─────────────────────────────────────────────────────
$T = @{
    Bg     = [System.Drawing.Color]::FromArgb(13,17,23)
    Panel  = [System.Drawing.Color]::FromArgb(22,27,34)
    Panel2 = [System.Drawing.Color]::FromArgb(28,33,40)
    Text   = [System.Drawing.Color]::FromArgb(201,209,217)
    Gray   = [System.Drawing.Color]::FromArgb(139,148,158)
    Green  = [System.Drawing.Color]::FromArgb(63,185,80)
    Cyan   = [System.Drawing.Color]::FromArgb(57,197,207)
    Yellow = [System.Drawing.Color]::FromArgb(210,153,34)
    Red    = [System.Drawing.Color]::FromArgb(248,81,73)
    Mag    = [System.Drawing.Color]::FromArgb(188,140,255)
    Sel    = [System.Drawing.Color]::FromArgb(33,40,48)
}
$MonoFont = New-Object System.Drawing.Font("Consolas",9.5)
$MonoBig  = New-Object System.Drawing.Font("Consolas",11,[System.Drawing.FontStyle]::Bold)
$UiFont   = New-Object System.Drawing.Font("Segoe UI",9)

# ── Admin check ───────────────────────────────────────────────
$IsAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)

# ── Small helpers ─────────────────────────────────────────────
function Format-Bytes($bytes) {
    if ($bytes -ge 1GB) { return "{0:N2} GB" -f ($bytes / 1GB) }
    if ($bytes -ge 1MB) { return "{0:N2} MB" -f ($bytes / 1MB) }
    if ($bytes -ge 1KB) { return "{0:N2} KB" -f ($bytes / 1KB) }
    return "$bytes B"
}

function New-Button($text, $accent) {
    $b = New-Object System.Windows.Forms.Button
    $b.Text = $text
    $b.Font = $UiFont
    $b.FlatStyle = "Flat"
    $b.FlatAppearance.BorderSize = 1
    $b.FlatAppearance.BorderColor = $T.Panel2
    $b.BackColor = $T.Panel2
    if ($accent) { $b.ForeColor = $accent } else { $b.ForeColor = $T.Text }
    $b.AutoSize = $false
    $b.Height = 28
    $b.Width = 150
    $b.Margin = New-Object System.Windows.Forms.Padding(3)
    $b.Cursor = "Hand"
    return $b
}

function New-Label($text, $color) {
    $l = New-Object System.Windows.Forms.Label
    $l.Text = $text
    $l.Font = $UiFont
    $l.AutoSize = $true
    if ($color) { $l.ForeColor = $color } else { $l.ForeColor = $T.Gray }
    $l.Margin = New-Object System.Windows.Forms.Padding(6,8,2,0)
    return $l
}

function New-Input($width) {
    $tb = New-Object System.Windows.Forms.TextBox
    $tb.Font = $MonoFont
    $tb.BackColor = $T.Bg
    $tb.ForeColor = $T.Text
    $tb.BorderStyle = "FixedSingle"
    if ($width) { $tb.Width = $width } else { $tb.Width = 120 }
    $tb.Margin = New-Object System.Windows.Forms.Padding(2,5,6,0)
    return $tb
}

function New-Output {
    $r = New-Object System.Windows.Forms.RichTextBox
    $r.Font = $MonoFont
    $r.BackColor = $T.Bg
    $r.ForeColor = $T.Text
    $r.BorderStyle = "None"
    $r.ReadOnly = $true
    $r.Dock = "Fill"
    $r.WordWrap = $false
    $r.DetectUrls = $false
    return $r
}

function New-Grid {
    $g = New-Object System.Windows.Forms.DataGridView
    $g.Dock = "Fill"
    $g.BackgroundColor = $T.Bg
    $g.GridColor = $T.Panel2
    $g.BorderStyle = "None"
    $g.Font = $MonoFont
    $g.ReadOnly = $true
    $g.AllowUserToAddRows = $false
    $g.AllowUserToDeleteRows = $false
    $g.AllowUserToResizeRows = $false
    $g.RowHeadersVisible = $false
    $g.SelectionMode = "FullRowSelect"
    $g.MultiSelect = $false
    $g.EnableHeadersVisualStyles = $false
    $g.AutoSizeColumnsMode = "Fill"
    $g.ColumnHeadersHeightSizeMode = "DisableResizing"
    $g.ColumnHeadersDefaultCellStyle.BackColor = $T.Panel
    $g.ColumnHeadersDefaultCellStyle.ForeColor = $T.Cyan
    $g.ColumnHeadersDefaultCellStyle.Font = $MonoFont
    $g.DefaultCellStyle.BackColor = $T.Bg
    $g.DefaultCellStyle.ForeColor = $T.Text
    $g.DefaultCellStyle.SelectionBackColor = $T.Sel
    $g.DefaultCellStyle.SelectionForeColor = $T.Green
    $g.AlternatingRowsDefaultCellStyle.BackColor = $T.Panel
    return $g
}

function New-Toolbar {
    $f = New-Object System.Windows.Forms.FlowLayoutPanel
    $f.Dock = "Top"
    $f.AutoSize = $true
    $f.AutoSizeMode = "GrowAndShrink"
    $f.WrapContents = $true
    $f.BackColor = $T.Panel
    $f.Padding = New-Object System.Windows.Forms.Padding(6,6,6,6)
    return $f
}

function New-CategoryPanel {
    $p = New-Object System.Windows.Forms.Panel
    $p.Dock = "Fill"
    $p.BackColor = $T.Bg
    $p.Visible = $false
    return $p
}

# Bind an array of PSCustomObjects to a grid.
function Set-Grid($grid, $rows) {
    $grid.DataSource = $null
    $grid.Columns.Clear()
    if (-not $rows) { return }
    $list = New-Object System.Collections.ArrayList
    foreach ($r in @($rows)) { [void]$list.Add($r) }
    if ($list.Count -eq 0) { return }
    $dt = New-Object System.Data.DataTable
    foreach ($prop in $list[0].PSObject.Properties) { [void]$dt.Columns.Add($prop.Name) }
    foreach ($item in $list) {
        $vals = @()
        foreach ($prop in $list[0].PSObject.Properties) {
            $v = $item.($prop.Name)
            if ($null -eq $v) { $vals += "" } else { $vals += [string]$v }
        }
        [void]$dt.Rows.Add($vals)
    }
    $grid.DataSource = $dt
    $grid.Tag = $list
}

# Append colored text to a RichTextBox output pane.
function Out-Line($box, $text, $color) {
    if (-not $color) { $color = $T.Text }
    $box.SelectionStart = $box.TextLength
    $box.SelectionColor = $color
    $box.AppendText("$text`n")
    $box.SelectionStart = $box.TextLength
    $box.ScrollToCaret()
}

function Set-Status($text, $color) {
    $script:StatusLabel.Text = "  $text"
    if ($color) { $script:StatusLabel.ForeColor = $color } else { $script:StatusLabel.ForeColor = $T.Gray }
    [System.Windows.Forms.Application]::DoEvents()
}

function Run-Busy($scriptblock) {
    $script:Form.Cursor = "WaitCursor"
    [System.Windows.Forms.Application]::DoEvents()
    try { & $scriptblock } finally { $script:Form.Cursor = "Default" }
}

# ── Promoted tab helpers (script scope so click handlers can see them) ──
function Write-SiHeader($out, $title) {
    $out.Clear()
    Out-Line $out "  $title" $T.Mag
    Out-Line $out "  ----------------------------------------------------" $T.Gray
}
function Write-SiRow($out, $k, $v, $c) {
    Out-Line $out ("    {0,-26}{1}" -f $k, $v) $c
}
function Confirm-Box($msg) {
    return ([System.Windows.Forms.MessageBox]::Show($msg,"Confirm","YesNo","Warning") -eq "Yes")
}
function Ensure-WUModule($out) {
    if (Get-Module -ListAvailable -Name PSWindowsUpdate) {
        Import-Module PSWindowsUpdate -ErrorAction SilentlyContinue
        return $true
    }
    Out-Line $out "  PSWindowsUpdate module not found." $T.Yellow
    return $false
}
function Show-EventLog($grid, $log, $level, $title) {
    Run-Busy {
        Set-Status "Reading $title ..." $T.Yellow
        try {
            $filter = @{ LogName = $log }
            if ($level) { $filter.Level = $level }
            $ev = Get-WinEvent -FilterHashtable $filter -MaxEvents 50 -ErrorAction Stop | ForEach-Object {
                $msg = ($_.Message -replace "`r?`n"," ")
                [PSCustomObject]@{
                    Time    = $_.TimeCreated.ToString("yyyy-MM-dd HH:mm:ss")
                    Level   = $_.LevelDisplayName
                    Id      = $_.Id
                    Source  = $_.ProviderName
                    Message = $msg.Substring(0,[Math]::Min(120,$msg.Length))
                }
            }
            Set-Grid $grid $ev
            Set-Status "$title - $($ev.Count) event(s)" $T.Green
        } catch { Set-Grid $grid @([PSCustomObject]@{ Error = $_.Exception.Message }); Set-Status "Failed" $T.Red }
    }
}
function Load-ServiceList($grid, $txtSearch, $filter) {
    Run-Busy {
        $svcs = Get-Service
        if ($filter -eq "Running") { $svcs = $svcs | Where-Object Status -eq "Running" }
        elseif ($filter -eq "Stopped") { $svcs = $svcs | Where-Object Status -eq "Stopped" }
        $q = $txtSearch.Text.Trim()
        if ($q) { $svcs = $svcs | Where-Object { $_.Name -like "*$q*" -or $_.DisplayName -like "*$q*" } }
        $rows = $svcs | Sort-Object DisplayName | ForEach-Object {
            [PSCustomObject]@{ Name=$_.Name; Status=$_.Status; StartType=$_.StartType; DisplayName=$_.DisplayName }
        }
        Set-Grid $grid $rows
        Set-Status "$($rows.Count) service(s)" $T.Green
    }
}
function Get-SelectedSvc($grid) {
    if ($grid.SelectedRows.Count -eq 0) { return $null }
    return $grid.SelectedRows[0].Cells["Name"].Value
}
function Get-ProcRows($procs) {
    return $procs | ForEach-Object {
        [PSCustomObject]@{
            Name      = $_.ProcessName
            PID       = $_.Id
            "CPU(s)"  = if ($_.CPU) { [Math]::Round($_.CPU,1) } else { 0 }
            "RAM(MB)" = [Math]::Round($_.WorkingSet64/1MB,1)
        }
    }
}
function Get-SelectedPid($grid) {
    if ($grid.SelectedRows.Count -eq 0) { return $null }
    return [int]$grid.SelectedRows[0].Cells["PID"].Value
}
function Show-LogTail($out, $txtFile, $n) {
    $f = $txtFile.Text.Trim()
    if (-not (Test-Path -LiteralPath $f)) { $out.Clear(); Out-Line $out "  Log file not found: $f" $T.Red; return }
    $out.Clear()
    $lines = if ($n -gt 0) { Get-Content -LiteralPath $f -Tail $n } else { Get-Content -LiteralPath $f }
    foreach ($l in $lines) {
        $c = $T.Text
        if ($l -match "ERROR|FAIL") { $c = $T.Red } elseif ($l -match "WARN") { $c = $T.Yellow } elseif ($l -match "OK|SUCCESS|DONE") { $c = $T.Green }
        Out-Line $out $l $c
    }
    Set-Status "$f" $T.Green
}

# ══════════════════════════════════════════════════════════════
#  FORM
# ══════════════════════════════════════════════════════════════
$Form = New-Object System.Windows.Forms.Form
$script:Form = $Form
$Form.Text = "Admin Tools" + $(if ($IsAdmin) { "  [Administrator]" } else { "" })
$Form.Size = New-Object System.Drawing.Size(1120,740)
$Form.MinimumSize = New-Object System.Drawing.Size(900,600)
$Form.StartPosition = "CenterScreen"
$Form.BackColor = $T.Bg
$Form.ForeColor = $T.Text
$Form.Font = $UiFont

# Status bar
$StatusStrip = New-Object System.Windows.Forms.Panel
$StatusStrip.Dock = "Bottom"
$StatusStrip.Height = 24
$StatusStrip.BackColor = $T.Panel
$StatusLabel = New-Object System.Windows.Forms.Label
$script:StatusLabel = $StatusLabel
$StatusLabel.Dock = "Fill"
$StatusLabel.TextAlign = "MiddleLeft"
$StatusLabel.Font = $MonoFont
$StatusLabel.ForeColor = $T.Gray
$StatusLabel.Text = "  Ready  -  $env:USERNAME@$env:COMPUTERNAME"
$StatusStrip.Controls.Add($StatusLabel)

# Left nav
$NavPanel = New-Object System.Windows.Forms.Panel
$NavPanel.Dock = "Left"
$NavPanel.Width = 196
$NavPanel.BackColor = $T.Panel

$NavTitle = New-Object System.Windows.Forms.Label
$NavTitle.Text = "  Admin Tools"
$NavTitle.Dock = "Top"
$NavTitle.Height = 40
$NavTitle.TextAlign = "MiddleLeft"
$NavTitle.Font = $MonoBig
$NavTitle.ForeColor = $T.Cyan
$NavTitle.BackColor = $T.Panel

$Nav = New-Object System.Windows.Forms.ListBox
$Nav.Dock = "Fill"
$Nav.BackColor = $T.Panel
$Nav.ForeColor = $T.Text
$Nav.Font = $MonoFont
$Nav.BorderStyle = "None"
$Nav.IntegralHeight = $false
$Nav.ItemHeight = 30
[void]$Nav.Items.AddRange(@(
    "  SystemInfo","  Power","  Updates","  Network","  Disk",
    "  Events","  Services","  Watch","  Processes","  Logs","  About"
))

$NavPanel.Controls.Add($Nav)
$NavPanel.Controls.Add($NavTitle)

# Content host
$Content = New-Object System.Windows.Forms.Panel
$Content.Dock = "Fill"
$Content.BackColor = $T.Bg

$Form.Controls.Add($Content)
$Form.Controls.Add($NavPanel)
$Form.Controls.Add($StatusStrip)

$Panels = @{}

# ══════════════════════════════════════════════════════════════
#  SYSTEMINFO TAB
# ══════════════════════════════════════════════════════════════
function Build-SystemInfo {
    $p = New-CategoryPanel
    $bar = New-Toolbar
    $out = New-Output
    $p.Controls.Add($out)
    $p.Controls.Add($bar)


    $bOverview = New-Button "System Overview" $T.Green
    $bOverview.Add_Click({
        Run-Busy {
            Write-SiHeader $out "SYSTEM OVERVIEW"
            $os = Get-CimInstance Win32_OperatingSystem
            $cs = Get-CimInstance Win32_ComputerSystem
            $bios = Get-CimInstance Win32_BIOS
            Write-SiRow $out "Computer"      $cs.Name $T.Green
            Write-SiRow $out "Manufacturer"  $cs.Manufacturer $T.Text
            Write-SiRow $out "Model"         $cs.Model $T.Text
            Write-SiRow $out "OS"            $os.Caption $T.Green
            Write-SiRow $out "Version"       "$($os.Version) (build $($os.BuildNumber))" $T.Text
            Write-SiRow $out "Architecture"  $os.OSArchitecture $T.Text
            Write-SiRow $out "BIOS"          "$($bios.Manufacturer) $($bios.SMBIOSBIOSVersion)" $T.Text
            $up = (Get-Date) - $os.LastBootUpTime
            Write-SiRow $out "Uptime"        ("{0}d {1}h {2}m" -f $up.Days, $up.Hours, $up.Minutes) $T.Yellow
            Write-SiRow $out "Logged in"     "$env:USERNAME" $T.Text
        }
        Set-Status "System overview" $T.Green
    })

    $bCpu = New-Button "Processor" $T.Green
    $bCpu.Add_Click({
        Run-Busy {
            Write-SiHeader $out "PROCESSOR (CPU)"
            foreach ($c in Get-CimInstance Win32_Processor) {
                Write-SiRow $out "Name"          $c.Name $T.Green
                Write-SiRow $out "Cores"         $c.NumberOfCores $T.Text
                Write-SiRow $out "Logical"       $c.NumberOfLogicalProcessors $T.Text
                Write-SiRow $out "Max Clock"     "$($c.MaxClockSpeed) MHz" $T.Text
                Write-SiRow $out "Current Load"  "$($c.LoadPercentage)%" $(if ($c.LoadPercentage -ge 80) { $T.Red } elseif ($c.LoadPercentage -ge 50) { $T.Yellow } else { $T.Green })
            }
        }
        Set-Status "Processor" $T.Green
    })

    $bMem = New-Button "Memory" $T.Green
    $bMem.Add_Click({
        Run-Busy {
            Write-SiHeader $out "MEMORY (RAM)"
            $os = Get-CimInstance Win32_OperatingSystem
            $totalKB = $os.TotalVisibleMemorySize
            $freeKB  = $os.FreePhysicalMemory
            $usedKB  = $totalKB - $freeKB
            $pct = [Math]::Round($usedKB / $totalKB * 100)
            Write-SiRow $out "Total"  ("{0:N1} GB" -f ($totalKB/1MB)) $T.Text
            Write-SiRow $out "Used"   ("{0:N1} GB  ({1}%)" -f ($usedKB/1MB), $pct) $(if ($pct -ge 85) { $T.Red } elseif ($pct -ge 70) { $T.Yellow } else { $T.Green })
            Write-SiRow $out "Free"   ("{0:N1} GB" -f ($freeKB/1MB)) $T.Green
            Out-Line $out "" $T.Text
            foreach ($m in Get-CimInstance Win32_PhysicalMemory) {
                $cap = [Math]::Round($m.Capacity/1GB)
                Write-SiRow $out "Module" "$cap GB @ $($m.Speed) MHz  ($($m.Manufacturer))" $T.Gray
            }
        }
        Set-Status "Memory" $T.Green
    })

    $bStorage = New-Button "Storage" $T.Green
    $bStorage.Add_Click({
        Run-Busy {
            Write-SiHeader $out "STORAGE"
            foreach ($d in Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3") {
                $totalGB = [Math]::Round($d.Size/1GB,1)
                $freeGB  = [Math]::Round($d.FreeSpace/1GB,1)
                $usedGB  = [Math]::Round(($d.Size-$d.FreeSpace)/1GB,1)
                $pct = if ($d.Size -gt 0) { [Math]::Round(($d.Size-$d.FreeSpace)/$d.Size*100) } else { 0 }
                $c = if ($pct -ge 90) { $T.Red } elseif ($pct -ge 75) { $T.Yellow } else { $T.Green }
                Out-Line $out "  $($d.DeviceID) $($d.VolumeName)" $T.Cyan
                Write-SiRow $out "  Used"  "$usedGB GB ($pct%)" $c
                Write-SiRow $out "  Free"  "$freeGB GB" $T.Green
                Write-SiRow $out "  Total" "$totalGB GB" $T.Gray
            }
        }
        Set-Status "Storage" $T.Green
    })

    $bGpu = New-Button "Display (GPU)" $T.Green
    $bGpu.Add_Click({
        Run-Busy {
            Write-SiHeader $out "DISPLAY ADAPTERS (GPU)"
            foreach ($g in Get-CimInstance Win32_VideoController) {
                Write-SiRow $out "Name"    $g.Name $T.Green
                if ($g.AdapterRAM -gt 0) { Write-SiRow $out "  VRAM" ("{0:N0} MB" -f ($g.AdapterRAM/1MB)) $T.Text }
                Write-SiRow $out "  Driver" $g.DriverVersion $T.Gray
                if ($g.CurrentHorizontalResolution) {
                    Write-SiRow $out "  Resolution" "$($g.CurrentHorizontalResolution)x$($g.CurrentVerticalResolution) @ $($g.CurrentRefreshRate)Hz" $T.Text
                }
            }
        }
        Set-Status "GPU" $T.Green
    })

    $bNet = New-Button "Network" $T.Green
    $bNet.Add_Click({
        Run-Busy {
            Write-SiHeader $out "NETWORK ADAPTERS"
            foreach ($a in Get-NetAdapter | Where-Object Status -eq "Up") {
                Out-Line $out "  $($a.Name)" $T.Cyan
                Write-SiRow $out "  Interface" $a.InterfaceDescription $T.Text
                Write-SiRow $out "  Speed"     $a.LinkSpeed $T.Text
                Write-SiRow $out "  MAC"       $a.MacAddress $T.Gray
                $ips = Get-NetIPAddress -InterfaceIndex $a.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue
                foreach ($ip in $ips) { Write-SiRow $out "  IPv4" $ip.IPAddress $T.Green }
            }
        }
        Set-Status "Network" $T.Green
    })

    $bBatt = New-Button "Battery" $T.Green
    $bBatt.Add_Click({
        Run-Busy {
            Write-SiHeader $out "BATTERY"
            $b = Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue
            if (-not $b) { Out-Line $out "  No battery detected (desktop?)." $T.Yellow; return }
            foreach ($bat in $b) {
                Write-SiRow $out "Charge"  "$($bat.EstimatedChargeRemaining)%" $(if ($bat.EstimatedChargeRemaining -le 20) { $T.Red } else { $T.Green })
                $statusMap = @{1="Discharging";2="AC Power";3="Fully Charged";4="Low";5="Critical"}
                $st = $statusMap[[int]$bat.BatteryStatus]
                if (-not $st) { $st = "Status $($bat.BatteryStatus)" }
                Write-SiRow $out "Status"  $st $T.Text
            }
        }
        Set-Status "Battery" $T.Green
    })

    $bPerf = New-Button "Performance" $T.Yellow
    $bPerf.Add_Click({
        Run-Busy {
            Write-SiHeader $out "PERFORMANCE SNAPSHOT"
            $cpu = (Get-CimInstance Win32_Processor | Measure-Object -Property LoadPercentage -Average).Average
            $os = Get-CimInstance Win32_OperatingSystem
            $memPct = [Math]::Round(($os.TotalVisibleMemorySize - $os.FreePhysicalMemory) / $os.TotalVisibleMemorySize * 100)
            Write-SiRow $out "CPU Load"     "$([Math]::Round($cpu))%" $(if ($cpu -ge 80) { $T.Red } elseif ($cpu -ge 50) { $T.Yellow } else { $T.Green })
            Write-SiRow $out "Memory Used"  "$memPct%" $(if ($memPct -ge 85) { $T.Red } elseif ($memPct -ge 70) { $T.Yellow } else { $T.Green })
            $procCount = (Get-Process).Count
            Write-SiRow $out "Processes"    $procCount $T.Text
            $thr = (Get-Process | Measure-Object -Property Threads -Sum).Sum
            if ($thr) { Write-SiRow $out "Threads" $thr $T.Gray }
        }
        Set-Status "Performance" $T.Green
    })

    $bFull = New-Button "Full Report" $T.Cyan
    $bFull.Add_Click({
        Run-Busy {
            $out.Clear()
            $bOverview.PerformClick(); Out-Line $out "" $T.Text
            $bCpu.PerformClick();      Out-Line $out "" $T.Text
            $bMem.PerformClick();      Out-Line $out "" $T.Text
            $bStorage.PerformClick();  Out-Line $out "" $T.Text
            $bGpu.PerformClick();      Out-Line $out "" $T.Text
            $bNet.PerformClick();      Out-Line $out "" $T.Text
            $bBatt.PerformClick();     Out-Line $out "" $T.Text
            $bPerf.PerformClick()
            $out.SelectionStart = 0; $out.ScrollToCaret()
        }
        Set-Status "Full report complete" $T.Green
    })

    foreach ($b in @($bFull,$bOverview,$bCpu,$bMem,$bStorage,$bGpu,$bNet,$bBatt,$bPerf)) { [void]$bar.Controls.Add($b) }
    return $p
}

# ══════════════════════════════════════════════════════════════
#  POWER TAB
# ══════════════════════════════════════════════════════════════
function Build-Power {
    $p = New-CategoryPanel
    $bar = New-Toolbar
    $out = New-Output
    $p.Controls.Add($out)
    $p.Controls.Add($bar)

    Out-Line $out "  Power controls. Destructive actions ask for confirmation." $T.Gray
    Out-Line $out "  Hibernate requires it to be enabled (powercfg /h on)." $T.Gray


    $bSleep = New-Button "Sleep" $T.Green
    $bSleep.Add_Click({
        if (Confirm-Box "Put the computer to sleep now?") {
            Set-Status "Sleeping..." $T.Yellow
            rundll32.exe powrprof.dll,SetSuspendState 0,1,0
        }
    })

    $bHib = New-Button "Hibernate" $T.Green
    $bHib.Add_Click({
        if (Confirm-Box "Hibernate now?") { Set-Status "Hibernating..." $T.Yellow; shutdown.exe /h }
    })

    $bLock = New-Button "Lock Screen" $T.Green
    $bLock.Add_Click({ rundll32.exe user32.dll,LockWorkStation; Set-Status "Locked." $T.Green })

    $bLogoff = New-Button "Log Off" $T.Mag
    $bLogoff.Add_Click({ if (Confirm-Box "Log off now? Unsaved work will be lost.") { shutdown.exe /l } })

    $bRestart = New-Button "Restart" $T.Yellow
    $bRestart.Add_Click({ if (Confirm-Box "Restart now?") { Restart-Computer -Force } })

    $bShutdown = New-Button "Shutdown" $T.Red
    $bShutdown.Add_Click({ if (Confirm-Box "Shut down now?") { Stop-Computer -Force } })

    $lblMin = New-Label "Delay (min):" $T.Gray
    $txtMin = New-Input 60
    $txtMin.Text = "10"

    $bRestartIn = New-Button "Restart in..." $T.Yellow
    $bRestartIn.Add_Click({
        $m = 0
        if ([int]::TryParse($txtMin.Text, [ref]$m) -and $m -gt 0 -and $m -le 1440) {
            $secs = $m * 60
            if (Confirm-Box "Schedule restart in $m minute(s)?") {
                shutdown.exe /r /t $secs /c "Scheduled restart via Admin GUI"
                Out-Line $out "  Restart scheduled in $m min. Use 'Cancel scheduled' to abort." $T.Green
                Set-Status "Restart scheduled ($m min)" $T.Yellow
            }
        } else { Out-Line $out "  Enter 1-1440 minutes." $T.Red }
    })

    $bShutdownIn = New-Button "Shutdown in..." $T.Red
    $bShutdownIn.Add_Click({
        $m = 0
        if ([int]::TryParse($txtMin.Text, [ref]$m) -and $m -gt 0 -and $m -le 1440) {
            $secs = $m * 60
            if (Confirm-Box "Schedule shutdown in $m minute(s)?") {
                shutdown.exe /s /t $secs /c "Scheduled shutdown via Admin GUI"
                Out-Line $out "  Shutdown scheduled in $m min. Use 'Cancel scheduled' to abort." $T.Green
                Set-Status "Shutdown scheduled ($m min)" $T.Red
            }
        } else { Out-Line $out "  Enter 1-1440 minutes." $T.Red }
    })

    $bCancel = New-Button "Cancel scheduled" $T.Cyan
    $bCancel.Add_Click({
        shutdown.exe /a 2>$null
        Out-Line $out "  Any scheduled shutdown/restart has been cancelled." $T.Green
        Set-Status "Schedule cancelled" $T.Green
    })

    foreach ($b in @($bSleep,$bHib,$bLock,$bLogoff,$bRestart,$bShutdown,$lblMin,$txtMin,$bRestartIn,$bShutdownIn,$bCancel)) {
        [void]$bar.Controls.Add($b)
    }
    return $p
}

# ══════════════════════════════════════════════════════════════
#  UPDATES TAB
# ══════════════════════════════════════════════════════════════
function Build-Updates {
    $p = New-CategoryPanel
    $bar = New-Toolbar
    $grid = New-Grid
    $out = New-Output
    $out.Dock = "Bottom"
    $out.Height = 90
    $p.Controls.Add($grid)
    $p.Controls.Add($out)
    $p.Controls.Add($bar)


    $bInstallMod = New-Button "Install Module" $T.Cyan
    $bInstallMod.Add_Click({
        Run-Busy {
            try {
                Install-Module PSWindowsUpdate -Force -Scope CurrentUser -Repository PSGallery -AllowClobber -ErrorAction Stop
                Import-Module PSWindowsUpdate -ErrorAction Stop
                Out-Line $out "  PSWindowsUpdate installed." $T.Green
            } catch { Out-Line $out "  Install failed: $($_.Exception.Message)" $T.Red }
        }
    })

    $bScan = New-Button "Scan & List" $T.Green
    $bScan.Add_Click({
        Run-Busy {
            if (-not (Ensure-WUModule $out)) { return }
            Set-Status "Scanning for updates..." $T.Yellow
            try {
                $u = Get-WindowsUpdate -ErrorAction Stop |
                    Select-Object @{n="KB";e={$_.KB}}, @{n="Size";e={$_.Size}}, Title
                if (-not $u) { Out-Line $out "  No updates available." $T.Green } else { Set-Grid $grid $u }
                Set-Status "Scan complete" $T.Green
            } catch { Out-Line $out "  Scan failed: $($_.Exception.Message)" $T.Red }
        }
    })

    $bHistory = New-Button "Update History" $T.Green
    $bHistory.Add_Click({
        Run-Busy {
            if (-not (Ensure-WUModule $out)) { return }
            try {
                $h = Get-WUHistory -ErrorAction Stop | Select-Object -First 50 Date, Result, KB, Title
                Set-Grid $grid $h
                Set-Status "History loaded" $T.Green
            } catch { Out-Line $out "  History failed: $($_.Exception.Message)" $T.Red }
        }
    })

    $bInstallAll = New-Button "Install All" $T.Yellow
    $bInstallAll.Add_Click({
        if (-not $IsAdmin) { Out-Line $out "  Requires Administrator." $T.Red; return }
        if ([System.Windows.Forms.MessageBox]::Show("Install ALL available updates? May reboot.","Confirm","YesNo","Warning") -ne "Yes") { return }
        Run-Busy {
            if (-not (Ensure-WUModule $out)) { return }
            try {
                Out-Line $out "  Installing all updates (this can take a while)..." $T.Yellow
                Install-WindowsUpdate -AcceptAll -IgnoreReboot -ErrorAction Stop | Out-Null
                Out-Line $out "  Install pass complete. Reboot may be required." $T.Green
            } catch { Out-Line $out "  Install failed: $($_.Exception.Message)" $T.Red }
        }
    })

    $bSec = New-Button "Security Only" $T.Yellow
    $bSec.Add_Click({
        if (-not $IsAdmin) { Out-Line $out "  Requires Administrator." $T.Red; return }
        if ([System.Windows.Forms.MessageBox]::Show("Install security updates only?","Confirm","YesNo","Warning") -ne "Yes") { return }
        Run-Busy {
            if (-not (Ensure-WUModule $out)) { return }
            try {
                Install-WindowsUpdate -AcceptAll -IgnoreReboot -CategoryIDs "0fa1201d-4330-4fa8-8ae9-b877473b6441" -ErrorAction Stop | Out-Null
                Out-Line $out "  Security update pass complete." $T.Green
            } catch { Out-Line $out "  Failed: $($_.Exception.Message)" $T.Red }
        }
    })

    $bReboot = New-Button "Reboot" $T.Red
    $bReboot.Add_Click({ if ([System.Windows.Forms.MessageBox]::Show("Reboot now?","Confirm","YesNo","Warning") -eq "Yes") { Restart-Computer -Force } })

    foreach ($b in @($bScan,$bHistory,$bInstallAll,$bSec,$bReboot,$bInstallMod)) { [void]$bar.Controls.Add($b) }
    return $p
}

# ══════════════════════════════════════════════════════════════
#  NETWORK TAB
# ══════════════════════════════════════════════════════════════
function Build-Network {
    $p = New-CategoryPanel
    $bar = New-Toolbar
    $out = New-Output
    $p.Controls.Add($out)
    $p.Controls.Add($bar)

    $lblHost = New-Label "Host:" $T.Gray
    $txtHost = New-Input 150
    $txtHost.Text = "1.1.1.1"
    $lblPort = New-Label "Port:" $T.Gray
    $txtPort = New-Input 60
    $txtPort.Text = "443"

    $bHealth = New-Button "Health Check" $T.Green
    $bHealth.Add_Click({
        Run-Busy {
            $out.Clear()
            Out-Line $out "  QUICK NETWORK HEALTH CHECK" $T.Mag
            Out-Line $out "  ----------------------------------------------------" $T.Gray
            $gw = (Get-NetRoute -DestinationPrefix "0.0.0.0/0" -ErrorAction SilentlyContinue | Sort-Object RouteMetric | Select-Object -First 1).NextHop
            if ($gw) {
                $gwOk = Test-Connection -ComputerName $gw -Count 1 -Quiet -ErrorAction SilentlyContinue
                Out-Line $out ("    {0,-22}{1}" -f "Gateway ($gw)", $(if ($gwOk) { "Reachable" } else { "Unreachable" })) $(if ($gwOk) { $T.Green } else { $T.Red })
            } else { Out-Line $out "    Gateway                No gateway found" $T.Red }
            $netOk = Test-Connection -ComputerName "1.1.1.1" -Count 1 -Quiet -ErrorAction SilentlyContinue
            Out-Line $out ("    {0,-22}{1}" -f "Internet (1.1.1.1)", $(if ($netOk) { "Reachable" } else { "Unreachable" })) $(if ($netOk) { $T.Green } else { $T.Red })
            $dnsOk = $false
            try { $dnsOk = [bool](Resolve-DnsName "github.com" -ErrorAction Stop) } catch { $dnsOk = $false }
            Out-Line $out ("    {0,-22}{1}" -f "DNS Resolution", $(if ($dnsOk) { "Working" } else { "Failed" })) $(if ($dnsOk) { $T.Green } else { $T.Red })
        }
        Set-Status "Health check" $T.Green
    })

    $bInfo = New-Button "Network Info" $T.Green
    $bInfo.Add_Click({
        Run-Busy {
            $out.Clear()
            Out-Line $out "  ACTIVE ADAPTERS" $T.Mag
            foreach ($a in Get-NetAdapter | Where-Object Status -eq "Up") {
                Out-Line $out "  * $($a.Name)  $($a.LinkSpeed)  MAC: $($a.MacAddress)" $T.Green
                Get-NetIPAddress -InterfaceIndex $a.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue | ForEach-Object {
                    Out-Line $out "      IPv4: $($_.IPAddress)/$($_.PrefixLength)" $T.Text
                }
            }
        }
        Set-Status "Network info" $T.Green
    })

    $bWifi = New-Button "Wi-Fi Details" $T.Green
    $bWifi.Add_Click({
        Run-Busy {
            $out.Clear()
            Out-Line $out "  WI-FI" $T.Mag
            $w = netsh wlan show interfaces 2>$null
            if ($w) { foreach ($line in $w) { if ($line.Trim()) { Out-Line $out "  $($line.TrimEnd())" $T.Text } } }
            else { Out-Line $out "  No Wi-Fi interface or netsh unavailable." $T.Yellow }
        }
        Set-Status "Wi-Fi" $T.Green
    })

    $bPing = New-Button "Ping Host" $T.Green
    $bPing.Add_Click({
        Run-Busy {
            $out.Clear()
            $target = $txtHost.Text.Trim()
            if (-not $target) { Out-Line $out "  Enter a host." $T.Red; return }
            Out-Line $out "  PING $target" $T.Mag
            try {
                $r = Test-Connection -ComputerName $target -Count 4 -ErrorAction Stop
                foreach ($x in $r) {
                    $rt = if ($x.ResponseTime -ne $null) { $x.ResponseTime } else { $x.Latency }
                    Out-Line $out "    Reply from $target : ${rt}ms" $T.Green
                }
            } catch { Out-Line $out "    Host unreachable: $($_.Exception.Message)" $T.Red }
        }
        Set-Status "Ping" $T.Green
    })

    $bPort = New-Button "Test Port" $T.Green
    $bPort.Add_Click({
        Run-Busy {
            $out.Clear()
            $h = $txtHost.Text.Trim(); $pt = 0
            if (-not [int]::TryParse($txtPort.Text, [ref]$pt)) { Out-Line $out "  Enter a numeric port." $T.Red; return }
            Out-Line $out "  TEST PORT $h : $pt" $T.Mag
            $r = Test-NetConnection -ComputerName $h -Port $pt -WarningAction SilentlyContinue
            if ($r.TcpTestSucceeded) { Out-Line $out "    Port $pt OPEN on $h" $T.Green }
            else { Out-Line $out "    Port $pt CLOSED / filtered on $h" $T.Red }
        }
        Set-Status "Port test" $T.Green
    })

    $bDns = New-Button "DNS Lookup" $T.Green
    $bDns.Add_Click({
        Run-Busy {
            $out.Clear()
            $h = $txtHost.Text.Trim()
            Out-Line $out "  DNS LOOKUP $h" $T.Mag
            try {
                Resolve-DnsName $h -ErrorAction Stop | ForEach-Object {
                    $ipVal = if ($_.IPAddress) { $_.IPAddress } else { $_.NameHost }
                    Out-Line $out "    $($_.Type)`t$ipVal" $T.Text
                }
            } catch { Out-Line $out "    Lookup failed: $($_.Exception.Message)" $T.Red }
        }
        Set-Status "DNS lookup" $T.Green
    })

    $bTrace = New-Button "Traceroute" $T.Green
    $bTrace.Add_Click({
        Run-Busy {
            $out.Clear()
            $h = $txtHost.Text.Trim()
            Out-Line $out "  TRACEROUTE $h  (up to 15 hops)" $T.Mag
            Set-Status "Tracing route..." $T.Yellow
            $i = 0
            tracert -d -h 15 $h 2>$null | ForEach-Object {
                if ($_.Trim()) { Out-Line $out "  $($_.TrimEnd())" $T.Text; $i++; if ($i % 2 -eq 0) { [System.Windows.Forms.Application]::DoEvents() } }
            }
        }
        Set-Status "Traceroute done" $T.Green
    })

    $bPubIp = New-Button "Public IP" $T.Green
    $bPubIp.Add_Click({
        Run-Busy {
            $out.Clear()
            try {
                $ip = Invoke-RestMethod -Uri "https://api.ipify.org" -TimeoutSec 8
                Out-Line $out "  Public IP: $ip" $T.Green
            } catch { Out-Line $out "  Lookup failed: $($_.Exception.Message)" $T.Red }
        }
        Set-Status "Public IP" $T.Green
    })

    $bTcp = New-Button "Active TCP" $T.Green
    $bTcp.Add_Click({
        Run-Busy {
            $out.Clear()
            Out-Line $out "  ESTABLISHED TCP CONNECTIONS" $T.Mag
            Out-Line $out ("  {0,-22}{1,-22}{2}" -f "Local","Remote","Process") $T.Gray
            Get-NetTCPConnection -State Established -ErrorAction SilentlyContinue | ForEach-Object {
                $pn = (Get-Process -Id $_.OwningProcess -ErrorAction SilentlyContinue).ProcessName
                Out-Line $out ("  {0,-22}{1,-22}{2}" -f "$($_.LocalAddress):$($_.LocalPort)", "$($_.RemoteAddress):$($_.RemotePort)", $pn) $T.Text
            }
        }
        Set-Status "Active TCP" $T.Green
    })

    $bListen = New-Button "Listening Ports" $T.Green
    $bListen.Add_Click({
        Run-Busy {
            $out.Clear()
            Out-Line $out "  LISTENING PORTS" $T.Mag
            Out-Line $out ("  {0,-8}{1,-22}{2}" -f "Port","Address","Process") $T.Gray
            Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue | Sort-Object LocalPort -Unique | ForEach-Object {
                $pn = (Get-Process -Id $_.OwningProcess -ErrorAction SilentlyContinue).ProcessName
                Out-Line $out ("  {0,-8}{1,-22}{2}" -f $_.LocalPort, $_.LocalAddress, $pn) $T.Text
            }
        }
        Set-Status "Listening ports" $T.Green
    })

    foreach ($b in @($bHealth,$bInfo,$bWifi,$lblHost,$txtHost,$lblPort,$txtPort,$bPing,$bPort,$bDns,$bTrace,$bPubIp,$bTcp,$bListen)) {
        [void]$bar.Controls.Add($b)
    }
    return $p
}

# ══════════════════════════════════════════════════════════════
#  DISK TAB
# ══════════════════════════════════════════════════════════════
function Build-Disk {
    $p = New-CategoryPanel
    $bar = New-Toolbar
    $grid = New-Grid
    $out = New-Output
    $out.Dock = "Bottom"
    $out.Height = 80
    $p.Controls.Add($grid)
    $p.Controls.Add($out)
    $p.Controls.Add($bar)

    $lblPath = New-Label "Path:" $T.Gray
    $txtPath = New-Input 200
    $txtPath.Text = "C:\"

    $bUsage = New-Button "Drive Usage" $T.Green
    $bUsage.Add_Click({
        Run-Busy {
            $rows = Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3" | ForEach-Object {
                $pct = if ($_.Size -gt 0) { [Math]::Round(($_.Size-$_.FreeSpace)/$_.Size*100) } else { 0 }
                [PSCustomObject]@{
                    Drive   = $_.DeviceID
                    Label   = $_.VolumeName
                    "Used%" = "$pct%"
                    Used    = Format-Bytes ($_.Size-$_.FreeSpace)
                    Free    = Format-Bytes $_.FreeSpace
                    Total   = Format-Bytes $_.Size
                    FS      = $_.FileSystem
                }
            }
            Set-Grid $grid $rows
        }
        Set-Status "Drive usage" $T.Green
    })

    $bFolders = New-Button "Largest Folders" $T.Green
    $bFolders.Add_Click({
        Run-Busy {
            $tp = $txtPath.Text.Trim(); if (-not $tp) { $tp = "C:\" }
            Set-Status "Scanning folders in $tp ..." $T.Yellow
            $rows = Get-ChildItem -LiteralPath $tp -Directory -ErrorAction SilentlyContinue | ForEach-Object {
                $size = (Get-ChildItem -LiteralPath $_.FullName -Recurse -File -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum
                [PSCustomObject]@{ Size = Format-Bytes ([long]$size); Bytes = [long]$size; Folder = $_.FullName }
            } | Sort-Object Bytes -Descending | Select-Object -First 20 Size, Folder
            Set-Grid $grid $rows
        }
        Set-Status "Folders scanned" $T.Green
    })

    $bFiles = New-Button "Largest Files" $T.Green
    $bFiles.Add_Click({
        Run-Busy {
            $tp = $txtPath.Text.Trim(); if (-not $tp) { $tp = "C:\Users" }
            Set-Status "Scanning files in $tp ..." $T.Yellow
            $rows = Get-ChildItem -LiteralPath $tp -Recurse -File -ErrorAction SilentlyContinue |
                Sort-Object Length -Descending | Select-Object -First 20 |
                ForEach-Object { [PSCustomObject]@{ Size = Format-Bytes $_.Length; File = $_.FullName } }
            Set-Grid $grid $rows
        }
        Set-Status "Files scanned" $T.Green
    })

    $bCleanUser = New-Button "Clean User Temp" $T.Yellow
    $bCleanUser.Add_Click({
        $tp = $env:TEMP
        $items = Get-ChildItem -LiteralPath $tp -Force -ErrorAction SilentlyContinue
        $size = ($items | Measure-Object Length -Sum).Sum
        if ([System.Windows.Forms.MessageBox]::Show("Delete $($items.Count) items (~$(Format-Bytes ([long]$size))) from`n$tp ?","Clean User Temp","YesNo","Warning") -ne "Yes") { return }
        Run-Busy {
            $del = 0
            foreach ($it in $items) {
                try { Remove-Item -LiteralPath $it.FullName -Recurse -Force -ErrorAction Stop; $del++ } catch {}
            }
            Out-Line $out "  Removed $del item(s) from user temp." $T.Green
        }
        Set-Status "User temp cleaned" $T.Green
    })

    $bCleanWin = New-Button "Clean Win Temp" $T.Yellow
    $bCleanWin.Add_Click({
        if (-not $IsAdmin) { Out-Line $out "  Requires Administrator." $T.Red; return }
        $tp = Join-Path $env:SystemRoot "Temp"
        $items = Get-ChildItem -LiteralPath $tp -Force -ErrorAction SilentlyContinue
        $size = ($items | Measure-Object Length -Sum).Sum
        if ([System.Windows.Forms.MessageBox]::Show("Delete $($items.Count) items (~$(Format-Bytes ([long]$size))) from`n$tp ?","Clean Windows Temp","YesNo","Warning") -ne "Yes") { return }
        Run-Busy {
            $del = 0
            foreach ($it in $items) {
                try { Remove-Item -LiteralPath $it.FullName -Recurse -Force -ErrorAction Stop; $del++ } catch {}
            }
            Out-Line $out "  Removed $del item(s) from Windows temp." $T.Green
        }
        Set-Status "Windows temp cleaned" $T.Green
    })

    $bRecycle = New-Button "Empty Recycle Bin" $T.Red
    $bRecycle.Add_Click({
        if ([System.Windows.Forms.MessageBox]::Show("Empty the Recycle Bin?","Confirm","YesNo","Warning") -ne "Yes") { return }
        try { Clear-RecycleBin -Force -ErrorAction Stop; Out-Line $out "  Recycle Bin emptied." $T.Green }
        catch { Out-Line $out "  Failed: $($_.Exception.Message)" $T.Red }
    })

    $bExport = New-Button "Export CSV" $T.Cyan
    $bExport.Add_Click({
        $dlg = New-Object System.Windows.Forms.SaveFileDialog
        $dlg.Filter = "CSV (*.csv)|*.csv"
        $dlg.FileName = "drive-usage.csv"
        if ($dlg.ShowDialog() -ne "OK") { return }
        Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3" | ForEach-Object {
            [PSCustomObject]@{ Drive=$_.DeviceID; Label=$_.VolumeName; TotalBytes=$_.Size; FreeBytes=$_.FreeSpace; FileSystem=$_.FileSystem }
        } | Export-Csv -Path $dlg.FileName -NoTypeInformation
        Out-Line $out "  Exported to $($dlg.FileName)" $T.Green
        Set-Status "CSV exported" $T.Green
    })

    foreach ($b in @($bUsage,$lblPath,$txtPath,$bFolders,$bFiles,$bCleanUser,$bCleanWin,$bRecycle,$bExport)) { [void]$bar.Controls.Add($b) }
    return $p
}

# ══════════════════════════════════════════════════════════════
#  EVENTS TAB
# ══════════════════════════════════════════════════════════════
function Build-Events {
    $p = New-CategoryPanel
    $bar = New-Toolbar
    $grid = New-Grid
    $p.Controls.Add($grid)
    $p.Controls.Add($bar)


    $bSysErr = New-Button "System Errors" $T.Green
    $bSysErr.Add_Click({ Show-EventLog $grid "System" 2 "System errors" })
    $bAppErr = New-Button "App Errors" $T.Green
    $bAppErr.Add_Click({ Show-EventLog $grid "Application" 2 "Application errors" })
    $bWarn = New-Button "Warnings" $T.Green
    $bWarn.Add_Click({ Show-EventLog $grid "System" 3 "System warnings" })
    $bPsErr = New-Button "PowerShell Errors" $T.Green
    $bPsErr.Add_Click({ Show-EventLog $grid "Windows PowerShell" 2 "PowerShell errors" })

    $bLogon = New-Button "Failed Logons" $T.Green
    $bLogon.Add_Click({
        if (-not $IsAdmin) { Set-Grid $grid @([PSCustomObject]@{ Note = "Failed logons require Administrator." }); return }
        Run-Busy {
            try {
                $ev = Get-WinEvent -FilterHashtable @{ LogName="Security"; Id=4625 } -MaxEvents 50 -ErrorAction Stop | ForEach-Object {
                    [PSCustomObject]@{ Time=$_.TimeCreated.ToString("yyyy-MM-dd HH:mm:ss"); Id=$_.Id; Source=$_.ProviderName }
                }
                Set-Grid $grid $ev
                Set-Status "Failed logons - $($ev.Count)" $T.Green
            } catch { Set-Grid $grid @([PSCustomObject]@{ Note = "No failed logons or access denied." }) }
        }
    })

    $bReboot = New-Button "Reboot/Shutdown" $T.Green
    $bReboot.Add_Click({
        Run-Busy {
            try {
                $ev = Get-WinEvent -FilterHashtable @{ LogName="System"; Id=1074,1076,6005,6006,6008 } -MaxEvents 50 -ErrorAction Stop | ForEach-Object {
                    $desc = switch ($_.Id) { 6005 {"Event log started (boot)"} 6006 {"Event log stopped (shutdown)"} 6008 {"Unexpected shutdown"} 1074 {"Shutdown initiated"} 1076 {"Shutdown reason"} default {"Power event"} }
                    [PSCustomObject]@{ Time=$_.TimeCreated.ToString("yyyy-MM-dd HH:mm:ss"); Id=$_.Id; Type=$desc }
                }
                Set-Grid $grid $ev
                Set-Status "Power events - $($ev.Count)" $T.Green
            } catch { Set-Grid $grid @([PSCustomObject]@{ Note = "None found." }) }
        }
    })

    $bExport = New-Button "Export CSV" $T.Cyan
    $bExport.Add_Click({
        if (-not $grid.Tag) { Set-Status "Nothing to export." $T.Yellow; return }
        $dlg = New-Object System.Windows.Forms.SaveFileDialog
        $dlg.Filter = "CSV (*.csv)|*.csv"; $dlg.FileName = "events.csv"
        if ($dlg.ShowDialog() -ne "OK") { return }
        $grid.Tag | Export-Csv -Path $dlg.FileName -NoTypeInformation
        Set-Status "Exported to $($dlg.FileName)" $T.Green
    })

    foreach ($b in @($bSysErr,$bAppErr,$bWarn,$bPsErr,$bLogon,$bReboot,$bExport)) { [void]$bar.Controls.Add($b) }
    return $p
}

# ══════════════════════════════════════════════════════════════
#  SERVICES TAB
# ══════════════════════════════════════════════════════════════
function Build-Services {
    $p = New-CategoryPanel
    $bar = New-Toolbar
    $grid = New-Grid
    $out = New-Output
    $out.Dock = "Bottom"; $out.Height = 70
    $p.Controls.Add($grid)
    $p.Controls.Add($out)
    $p.Controls.Add($bar)

    $lblSearch = New-Label "Filter:" $T.Gray
    $txtSearch = New-Input 150



    $bRunning = New-Button "Running" $T.Green
    $bRunning.Add_Click({ Load-ServiceList $grid $txtSearch "Running" })
    $bStopped = New-Button "Stopped" $T.Green
    $bStopped.Add_Click({ Load-ServiceList $grid $txtSearch "Stopped" })
    $bAll = New-Button "All" $T.Green
    $bAll.Add_Click({ Load-ServiceList $grid $txtSearch "All" })

    $bStart = New-Button "Start" $T.Yellow
    $bStart.Add_Click({
        $n = Get-SelectedSvc $grid; if (-not $n) { Out-Line $out "  Select a service first." $T.Yellow; return }
        try { Start-Service -Name $n -ErrorAction Stop; Out-Line $out "  Started $n" $T.Green } catch { Out-Line $out "  Failed: $($_.Exception.Message)" $T.Red }
    })
    $bStop = New-Button "Stop" $T.Yellow
    $bStop.Add_Click({
        $n = Get-SelectedSvc $grid; if (-not $n) { Out-Line $out "  Select a service first." $T.Yellow; return }
        try { Stop-Service -Name $n -Force -ErrorAction Stop; Out-Line $out "  Stopped $n" $T.Green } catch { Out-Line $out "  Failed: $($_.Exception.Message)" $T.Red }
    })
    $bRestart = New-Button "Restart" $T.Yellow
    $bRestart.Add_Click({
        $n = Get-SelectedSvc $grid; if (-not $n) { Out-Line $out "  Select a service first." $T.Yellow; return }
        try { Restart-Service -Name $n -Force -ErrorAction Stop; Out-Line $out "  Restarted $n" $T.Green } catch { Out-Line $out "  Failed: $($_.Exception.Message)" $T.Red }
    })

    $cmbStart = New-Object System.Windows.Forms.ComboBox
    $cmbStart.DropDownStyle = "DropDownList"
    $cmbStart.Font = $MonoFont; $cmbStart.Width = 110
    $cmbStart.BackColor = $T.Bg; $cmbStart.ForeColor = $T.Text
    [void]$cmbStart.Items.AddRange(@("Automatic","Manual","Disabled"))
    $cmbStart.SelectedIndex = 1
    $cmbStart.Margin = New-Object System.Windows.Forms.Padding(2,5,4,0)

    $bSetStart = New-Button "Set Startup" $T.Yellow
    $bSetStart.Add_Click({
        $n = Get-SelectedSvc $grid; if (-not $n) { Out-Line $out "  Select a service first." $T.Yellow; return }
        try { Set-Service -Name $n -StartupType $cmbStart.SelectedItem -ErrorAction Stop; Out-Line $out "  $n startup set to $($cmbStart.SelectedItem)" $T.Green }
        catch { Out-Line $out "  Failed: $($_.Exception.Message)" $T.Red }
    })

    foreach ($b in @($bRunning,$bStopped,$bAll,$lblSearch,$txtSearch,$bStart,$bStop,$bRestart,$cmbStart,$bSetStart)) { [void]$bar.Controls.Add($b) }
    return $p
}

# ══════════════════════════════════════════════════════════════
#  PROCESSES TAB
# ══════════════════════════════════════════════════════════════
function Build-Processes {
    $p = New-CategoryPanel
    $bar = New-Toolbar
    $grid = New-Grid
    $out = New-Output
    $out.Dock = "Bottom"; $out.Height = 70
    $p.Controls.Add($grid)
    $p.Controls.Add($out)
    $p.Controls.Add($bar)

    $lblName = New-Label "Name:" $T.Gray
    $txtName = New-Input 130
    $lblPort = New-Label "Port:" $T.Gray
    $txtPort = New-Input 60


    $bCpu = New-Button "Top CPU" $T.Green
    $bCpu.Add_Click({ Run-Busy { Set-Grid $grid (Get-ProcRows (Get-Process | Sort-Object CPU -Descending | Select-Object -First 25)) }; Set-Status "Top CPU" $T.Green })
    $bMem = New-Button "Top Memory" $T.Green
    $bMem.Add_Click({ Run-Busy { Set-Grid $grid (Get-ProcRows (Get-Process | Sort-Object WorkingSet64 -Descending | Select-Object -First 25)) }; Set-Status "Top memory" $T.Green })

    $bSearch = New-Button "Search" $T.Green
    $bSearch.Add_Click({
        $q = $txtName.Text.Trim(); if (-not $q) { Out-Line $out "  Enter a name." $T.Yellow; return }
        Run-Busy {
            $procs = Get-Process -Name "*$q*" -ErrorAction SilentlyContinue
            if (-not $procs) { Out-Line $out "  No matches for '$q'." $T.Yellow; Set-Grid $grid @(); return }
            Set-Grid $grid (Get-ProcRows $procs)
        }
        Set-Status "Search done" $T.Green
    })

    $bByPort = New-Button "By Port" $T.Green
    $bByPort.Add_Click({
        $pt = 0; if (-not [int]::TryParse($txtPort.Text, [ref]$pt)) { Out-Line $out "  Enter a port number." $T.Yellow; return }
        Run-Busy {
            $conns = Get-NetTCPConnection -LocalPort $pt -ErrorAction SilentlyContinue
            if (-not $conns) { Out-Line $out "  Nothing on port $pt." $T.Yellow; return }
            $procs = $conns | ForEach-Object { Get-Process -Id $_.OwningProcess -ErrorAction SilentlyContinue } | Sort-Object Id -Unique
            Set-Grid $grid (Get-ProcRows $procs)
        }
        Set-Status "Port lookup" $T.Green
    })

    $bDetails = New-Button "Details" $T.Cyan
    $bDetails.Add_Click({
        $procPid = Get-SelectedPid $grid; if (-not $procPid) { Out-Line $out "  Select a row." $T.Yellow; return }
        try {
            $proc = Get-Process -Id $procPid -ErrorAction Stop
            $cim = Get-CimInstance Win32_Process -Filter "ProcessId=$procPid" -ErrorAction SilentlyContinue
            $out.Clear()
            Out-Line $out "  $($proc.ProcessName) (PID $procPid)" $T.Cyan
            Out-Line $out "    Path: $($proc.Path)" $T.Gray
            Out-Line $out "    RAM:  $([Math]::Round($proc.WorkingSet64/1MB,1)) MB    Threads: $($proc.Threads.Count)" $T.Text
            if ($cim) { Out-Line $out "    Cmd:  $($cim.CommandLine)" $T.Gray }
        } catch { Out-Line $out "  Failed: $($_.Exception.Message)" $T.Red }
    })

    $bKill = New-Button "Kill" $T.Red
    $bKill.Add_Click({
        $procPid = Get-SelectedPid $grid; if (-not $procPid) { Out-Line $out "  Select a row." $T.Yellow; return }
        if ([System.Windows.Forms.MessageBox]::Show("Kill PID $procPid ?","Confirm","YesNo","Warning") -ne "Yes") { return }
        try { Stop-Process -Id $procPid -Force -ErrorAction Stop; Out-Line $out "  Killed PID $procPid" $T.Green } catch { Out-Line $out "  Failed: $($_.Exception.Message)" $T.Red }
    })

    $bSuspend = New-Button "Suspend" $T.Yellow
    $bSuspend.Add_Click({
        $procPid = Get-SelectedPid $grid; if (-not $procPid) { Out-Line $out "  Select a row." $T.Yellow; return }
        try {
            $proc = Get-Process -Id $procPid -ErrorAction Stop
            foreach ($th in $proc.Threads) {
                $h = [ProcUtil]::OpenThread(0x0002, $false, [uint32]$th.Id)
                if ($h -ne [IntPtr]::Zero) { [ProcUtil]::SuspendThread($h) | Out-Null; [ProcUtil]::CloseHandle($h) | Out-Null }
            }
            Out-Line $out "  Suspended PID $procPid" $T.Green
        } catch { Out-Line $out "  Failed: $($_.Exception.Message)" $T.Red }
    })

    $bResume = New-Button "Resume" $T.Yellow
    $bResume.Add_Click({
        $procPid = Get-SelectedPid $grid; if (-not $procPid) { Out-Line $out "  Select a row." $T.Yellow; return }
        try {
            $proc = Get-Process -Id $procPid -ErrorAction Stop
            foreach ($th in $proc.Threads) {
                $h = [ProcUtil]::OpenThread(0x0002, $false, [uint32]$th.Id)
                if ($h -ne [IntPtr]::Zero) { [ProcUtil]::ResumeThread($h) | Out-Null; [ProcUtil]::CloseHandle($h) | Out-Null }
            }
            Out-Line $out "  Resumed PID $procPid" $T.Green
        } catch { Out-Line $out "  Failed: $($_.Exception.Message)" $T.Red }
    })

    $bExport = New-Button "Export CSV" $T.Cyan
    $bExport.Add_Click({
        if (-not $grid.Tag) { Out-Line $out "  Nothing to export." $T.Yellow; return }
        $dlg = New-Object System.Windows.Forms.SaveFileDialog
        $dlg.Filter = "CSV (*.csv)|*.csv"; $dlg.FileName = "processes.csv"
        if ($dlg.ShowDialog() -ne "OK") { return }
        $grid.Tag | Export-Csv -Path $dlg.FileName -NoTypeInformation
        Out-Line $out "  Exported to $($dlg.FileName)" $T.Green
    })

    foreach ($b in @($bCpu,$bMem,$lblName,$txtName,$bSearch,$lblPort,$txtPort,$bByPort,$bDetails,$bKill,$bSuspend,$bResume,$bExport)) { [void]$bar.Controls.Add($b) }
    return $p
}

# ══════════════════════════════════════════════════════════════
#  WATCH TAB  (live refresh via timer)
# ══════════════════════════════════════════════════════════════
function Build-Watch {
    $p = New-CategoryPanel
    $bar = New-Toolbar
    $grid = New-Grid
    $p.Controls.Add($grid)
    $p.Controls.Add($bar)

    $lblWhat = New-Label "Watch:" $T.Gray
    $cmbWhat = New-Object System.Windows.Forms.ComboBox
    $cmbWhat.DropDownStyle = "DropDownList"; $cmbWhat.Font = $MonoFont; $cmbWhat.Width = 160
    $cmbWhat.BackColor = $T.Bg; $cmbWhat.ForeColor = $T.Text
    [void]$cmbWhat.Items.AddRange(@("Top CPU","Top Memory","Active TCP","Listening Ports","Drive Usage","System Errors"))
    $cmbWhat.SelectedIndex = 0
    $cmbWhat.Margin = New-Object System.Windows.Forms.Padding(2,5,6,0)

    $lblInt = New-Label "Interval (s):" $T.Gray
    $numInt = New-Object System.Windows.Forms.NumericUpDown
    $numInt.Minimum = 1; $numInt.Maximum = 60; $numInt.Value = 3
    $numInt.Font = $MonoFont; $numInt.Width = 55
    $numInt.BackColor = $T.Bg; $numInt.ForeColor = $T.Text
    $numInt.Margin = New-Object System.Windows.Forms.Padding(2,5,6,0)

    $timer = New-Object System.Windows.Forms.Timer
    $script:WatchTimer = $timer

    $refresh = {
        switch ($cmbWhat.SelectedItem) {
            "Top CPU" {
                Set-Grid $grid (Get-Process | Sort-Object CPU -Descending | Select-Object -First 15 |
                    ForEach-Object { [PSCustomObject]@{ Name=$_.ProcessName; PID=$_.Id; "CPU(s)"=if($_.CPU){[Math]::Round($_.CPU,1)}else{0}; "RAM(MB)"=[Math]::Round($_.WorkingSet64/1MB,1) } })
            }
            "Top Memory" {
                Set-Grid $grid (Get-Process | Sort-Object WorkingSet64 -Descending | Select-Object -First 15 |
                    ForEach-Object { [PSCustomObject]@{ Name=$_.ProcessName; PID=$_.Id; "RAM(MB)"=[Math]::Round($_.WorkingSet64/1MB,1); "CPU(s)"=if($_.CPU){[Math]::Round($_.CPU,1)}else{0} } })
            }
            "Active TCP" {
                Set-Grid $grid (Get-NetTCPConnection -State Established -ErrorAction SilentlyContinue | Select-Object -First 30 |
                    ForEach-Object { [PSCustomObject]@{ Local="$($_.LocalAddress):$($_.LocalPort)"; Remote="$($_.RemoteAddress):$($_.RemotePort)"; Process=(Get-Process -Id $_.OwningProcess -ErrorAction SilentlyContinue).ProcessName } })
            }
            "Listening Ports" {
                Set-Grid $grid (Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue | Sort-Object LocalPort -Unique |
                    ForEach-Object { [PSCustomObject]@{ Port=$_.LocalPort; Address=$_.LocalAddress; Process=(Get-Process -Id $_.OwningProcess -ErrorAction SilentlyContinue).ProcessName } })
            }
            "Drive Usage" {
                Set-Grid $grid (Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3" |
                    ForEach-Object { $pct = if ($_.Size -gt 0) { [Math]::Round(($_.Size-$_.FreeSpace)/$_.Size*100) } else { 0 }
                        [PSCustomObject]@{ Drive=$_.DeviceID; "Used%"="$pct%"; Free=Format-Bytes $_.FreeSpace; Total=Format-Bytes $_.Size } })
            }
            "System Errors" {
                try {
                    Set-Grid $grid (Get-WinEvent -FilterHashtable @{LogName="System";Level=2} -MaxEvents 15 -ErrorAction Stop |
                        ForEach-Object { [PSCustomObject]@{ Time=$_.TimeCreated.ToString("HH:mm:ss"); Id=$_.Id; Source=$_.ProviderName } })
                } catch {}
            }
        }
        Set-Status "Watching: $($cmbWhat.SelectedItem)  -  $(Get-Date -Format HH:mm:ss)" $T.Cyan
    }
    $timer.Add_Tick($refresh)

    $bStart = New-Button "Start" $T.Green
    $bStart.Add_Click({
        $timer.Interval = [int]$numInt.Value * 1000
        & $refresh
        $timer.Start()
        Set-Status "Watching: $($cmbWhat.SelectedItem)" $T.Cyan
    })
    $bStop = New-Button "Stop" $T.Red
    $bStop.Add_Click({ $timer.Stop(); Set-Status "Watch stopped" $T.Gray })

    foreach ($b in @($lblWhat,$cmbWhat,$lblInt,$numInt,$bStart,$bStop)) { [void]$bar.Controls.Add($b) }
    return $p
}

# ══════════════════════════════════════════════════════════════
#  LOGS TAB  (toolkit log file viewer)
# ══════════════════════════════════════════════════════════════
function Build-Logs {
    $p = New-CategoryPanel
    $bar = New-Toolbar
    $out = New-Output
    $p.Controls.Add($out)
    $p.Controls.Add($bar)

    $lblFile = New-Label "Log file:" $T.Gray
    $txtFile = New-Input 300
    # Best-effort default; user can Browse to the real toolkit log.
    $guess = Join-Path $env:USERPROFILE "PS\logs\toolkit.log"
    $txtFile.Text = $guess

    $bBrowse = New-Button "Browse" $T.Cyan
    $bBrowse.Add_Click({
        $dlg = New-Object System.Windows.Forms.OpenFileDialog
        $dlg.Filter = "Log files (*.log;*.txt)|*.log;*.txt|All files (*.*)|*.*"
        if ($dlg.ShowDialog() -eq "OK") { $txtFile.Text = $dlg.FileName }
    })


    $b25 = New-Button "Last 25" $T.Green
    $b25.Add_Click({ Show-LogTail $out $txtFile 25 })
    $b100 = New-Button "Last 100" $T.Green
    $b100.Add_Click({ Show-LogTail $out $txtFile 100 })
    $bFull = New-Button "Full Log" $T.Green
    $bFull.Add_Click({ Show-LogTail $out $txtFile 0 })

    $bInfo = New-Button "Log Info" $T.Cyan
    $bInfo.Add_Click({
        $f = $txtFile.Text.Trim(); $out.Clear()
        if (-not (Test-Path -LiteralPath $f)) { Out-Line $out "  Does not exist: $f" $T.Red; return }
        $fi = Get-Item -LiteralPath $f
        $lc = (Get-Content -LiteralPath $f | Measure-Object -Line).Lines
        Out-Line $out "  Path     : $($fi.FullName)" $T.Text
        Out-Line $out "  Size     : $(Format-Bytes $fi.Length)" $T.Green
        Out-Line $out "  Lines    : $lc" $T.Green
        Out-Line $out "  Modified : $($fi.LastWriteTime)" $T.Gray
    })

    $bClear = New-Button "Clear Log" $T.Red
    $bClear.Add_Click({
        $f = $txtFile.Text.Trim()
        if (-not (Test-Path -LiteralPath $f)) { Out-Line $out "  Does not exist." $T.Yellow; return }
        if ([System.Windows.Forms.MessageBox]::Show("Erase all entries in`n$f ?","Confirm","YesNo","Warning") -ne "Yes") { return }
        Clear-Content -LiteralPath $f
        Out-Line $out "  Log cleared." $T.Green
    })

    $bTest = New-Button "Test Entries" $T.Yellow
    $bTest.Add_Click({
        $f = $txtFile.Text.Trim()
        $dir = Split-Path $f -Parent
        if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        Add-Content -LiteralPath $f -Value "[$ts] [INFO] Test entry from Admin GUI"
        Add-Content -LiteralPath $f -Value "[$ts] [WARN] Sample warning"
        Add-Content -LiteralPath $f -Value "[$ts] [ERROR] Sample error"
        Out-Line $out "  Appended 3 test entries to $f" $T.Green
    })

    foreach ($b in @($lblFile,$txtFile,$bBrowse,$b25,$b100,$bFull,$bInfo,$bClear,$bTest)) { [void]$bar.Controls.Add($b) }
    return $p
}

# ══════════════════════════════════════════════════════════════
#  ABOUT TAB
# ══════════════════════════════════════════════════════════════
function Build-About {
    $p = New-CategoryPanel
    $out = New-Output
    $out.Dock = "Fill"
    $p.Controls.Add($out)
    Out-Line $out "" $T.Text
    Out-Line $out "  Admin Tools  -  GUI dashboard" $T.Cyan
    Out-Line $out "  v1.0.0  by Mike Redd" $T.Gray
    Out-Line $out "" $T.Text
    Out-Line $out "  A single front-end for the admin console menus:" $T.Text
    Out-Line $out "    SystemInfo - Power - Updates - Network - Disk" $T.Green
    Out-Line $out "    Events - Services - Watch - Processes - Logs" $T.Green
    Out-Line $out "" $T.Text
    $adminTxt = if ($IsAdmin) { "  Running elevated (Administrator)." } else { "  Not elevated - some actions need Administrator." }
    Out-Line $out $adminTxt $(if ($IsAdmin) { $T.Green } else { $T.Yellow })
    if (-not $IsAdmin) {
        $btn = New-Button "Relaunch as Administrator" $T.Yellow
        $btn.Width = 220
        $btn.Location = New-Object System.Drawing.Point(20,200)
        $btn.Add_Click({
            try {
                Start-Process powershell.exe -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -STA -File `"$PSCommandPath`""
                $Form.Close()
            } catch { Out-Line $out "  Elevation cancelled." $T.Red }
        })
        $p.Controls.Add($btn)
        $btn.BringToFront()
    }
    return $p
}

# ══════════════════════════════════════════════════════════════
#  WIRE UP
# ══════════════════════════════════════════════════════════════
$Panels["SystemInfo"] = Build-SystemInfo
$Panels["Power"]      = Build-Power
$Panels["Updates"]    = Build-Updates
$Panels["Network"]    = Build-Network
$Panels["Disk"]       = Build-Disk
$Panels["Events"]     = Build-Events
$Panels["Services"]   = Build-Services
$Panels["Watch"]      = Build-Watch
$Panels["Processes"]  = Build-Processes
$Panels["Logs"]       = Build-Logs
$Panels["About"]      = Build-About

foreach ($key in $Panels.Keys) { $Content.Controls.Add($Panels[$key]) }

function Switch-Panel($name) {
    foreach ($key in $Panels.Keys) { $Panels[$key].Visible = $false }
    if ($Panels.ContainsKey($name)) { $Panels[$name].Visible = $true; $Panels[$name].BringToFront() }
    if ($script:WatchTimer -and $name -ne "Watch") { $script:WatchTimer.Stop() }
}

$Nav.Add_SelectedIndexChanged({
    if ($Nav.SelectedItem) {
        $name = ([string]$Nav.SelectedItem).Trim()
        Switch-Panel $name
        Set-Status $name $T.Gray
    }
})

$Form.Add_FormClosing({ if ($script:WatchTimer) { $script:WatchTimer.Stop(); $script:WatchTimer.Dispose() } })

$Nav.SelectedIndex = 0

# ── Run ───────────────────────────────────────────────────────
[void]$Form.ShowDialog()
