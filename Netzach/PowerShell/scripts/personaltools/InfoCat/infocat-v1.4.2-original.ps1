#Requires -Version 7.0
<#
.SYNOPSIS
    Display a compact Windows system-information panel beside the infocat ASCII art.

.DESCRIPTION
    PowerShell companion to infocat-pi for the Netzach Windows workstation.

    The script takes a lightweight snapshot of the current Windows session and
    hardware, formats that data into a fastfetch-style panel, and renders it next
    to the preserved cat artwork.

    It is intentionally standalone: it does not require profile.d, ui.ps1, or
    hard-coded user paths.

.PARAMETER NoColor
    Disable ANSI color sequences. Useful when redirecting output or running in a
    host that does not render virtual-terminal colors correctly.

.NOTES
    Machine:      Netzach / Windows
    PowerShell:   7.0+
    Dependencies: Built-in PowerShell cmdlets, CIM/WMI providers, Windows Forms,
                  and the Windows networking cmdlets.

    Design notes:
      - Hardware queries are collected once and reused where practical.
      - Logical drives are discovered dynamically; disconnected drive letters are
        omitted instead of being displayed as "Not connected".
      - Individual probes fail soft so one unavailable subsystem does not prevent
        the rest of the panel from rendering.
#>

# =============================================================================
# File:        infocat.ps1
# Author:      Mike Redd
# Version:     1.4.2
# Restored:    2026-07-12
# Purpose:     Windows / PowerShell system-information cat.
#
# Output:
#   Renders system information and ASCII art directly to the current terminal.
#
# Safety:
#   Read-only. The script queries Windows state but does not modify the system.
# =============================================================================

[CmdletBinding()]
param(
    [switch]$NoColor
)

Set-StrictMode -Version Latest

# Keep unexpected script errors visible during maintenance. Individual hardware
# probes handle expected failures locally so an unavailable subsystem stays quiet.
$ErrorActionPreference = 'Continue'
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)

$ESC = [char]27
function Get-Ansi {
    param([Parameter(Mandatory)][string]$Code)
    if ($NoColor -or -not $Host.UI.SupportsVirtualTerminal) { return '' }
    return "$ESC[$Code" + 'm'
}

$Reset = Get-Ansi '0'
$Bold  = Get-Ansi '1'
$White = Get-Ansi '97'
$Gray  = Get-Ansi '90'
$Blue  = Get-Ansi '94'
$Cyan  = Get-Ansi '96'

function Get-FirstValue {
    param(
        [Parameter(Mandatory)][scriptblock]$Script,
        [string]$Fallback = 'Unknown'
    )

    try {
        $value = & $Script
        if ($null -eq $value) { return $Fallback }

        $text = "$value".Trim()
        if ([string]::IsNullOrWhiteSpace($text)) { return $Fallback }
        return $text
    }
    catch {
        return $Fallback
    }
}

function Format-Bytes {
    param([double]$Bytes)

    if ($Bytes -ge 1TB) { return ('{0:N1} TB' -f ($Bytes / 1TB)) }
    if ($Bytes -ge 1GB) { return ('{0:N1} GB' -f ($Bytes / 1GB)) }
    if ($Bytes -ge 1MB) { return ('{0:N1} MB' -f ($Bytes / 1MB)) }
    return ('{0:N0} B' -f $Bytes)
}

function Format-DriveUsage {
    param(
        [Parameter(Mandatory)]
        [object]$Drive
    )

    # Win32_LogicalDisk DriveType values:
    #   2 = removable, 3 = local disk, 4 = network, 5 = optical.
    # Optical media may report no size when the tray is empty.
    if ($Drive.DriveType -eq 5) {
        if (-not $Drive.Size -or [double]$Drive.Size -le 0) {
            return 'Optical - Empty'
        }

        $label = if ($Drive.VolumeName) { $Drive.VolumeName } else { 'Media' }
        return 'Optical - {0} ({1})' -f $label, (Format-Bytes ([double]$Drive.Size))
    }

    # A present logical drive can still be unavailable, for example a mapped
    # network drive whose remote endpoint is currently offline.
    if (-not $Drive.Size -or [double]$Drive.Size -le 0) {
        return 'Detected - Unavailable'
    }

    $total = [double]$Drive.Size
    $free = [double]$Drive.FreeSpace
    $used = $total - $free
    $pct = [math]::Round(($used / $total) * 100)

    return '{0} / {1} ({2}%)' -f (
        Format-Bytes $used
    ), (
        Format-Bytes $total
    ), $pct
}

function Get-WindowsTheme {
    try {
        $key = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize'
        $value = (Get-ItemProperty -Path $key -Name AppsUseLightTheme -ErrorAction Stop).AppsUseLightTheme
        if ($value -eq 0) { return 'Dark' }
        return 'Light'
    }
    catch {
        return 'Unknown'
    }
}

function Get-TerminalName {
    if ($env:WT_SESSION) { return 'Windows Terminal' }
    if ($env:ConEmuANSI) { return 'ConEmu' }
    if ($env:TERM_PROGRAM) { return $env:TERM_PROGRAM }
    return $Host.Name
}

function Get-ScreenResolution {
    try {
        Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
        $screens = [System.Windows.Forms.Screen]::AllScreens
        $primary = $screens | Where-Object Primary | Select-Object -First 1
        if (-not $primary) { $primary = $screens | Select-Object -First 1 }
        if (-not $primary) { return 'Unknown' }

        $suffix = if ($screens.Count -gt 1) { " +$($screens.Count - 1) display(s)" } else { '' }
        return '{0}x{1}{2}' -f $primary.Bounds.Width, $primary.Bounds.Height, $suffix
    }
    catch {
        return 'Unknown'
    }
}

function Get-InstalledAppCount {
    # Windows has separate uninstall registry views for native 64-bit apps,
    # 32-bit apps, and per-user installs. De-duplicate names across all three.
    $paths = @(
        'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )

    try {
        $names = foreach ($path in $paths) {
            Get-ItemProperty $path -ErrorAction SilentlyContinue |
                Where-Object {
                    $_.PSObject.Properties['DisplayName'] -and
                    -not [string]::IsNullOrWhiteSpace([string]$_.DisplayName)
                } |
                ForEach-Object { [string]$_.DisplayName }
        }

        return @($names | Sort-Object -Unique).Count
    }
    catch {
        return 0
    }
}

function Get-PrimaryIPv4 {
    try {
        # Prefer a real hardware-backed Ethernet/Wi-Fi interface over VPN and
        # other virtual adapters. VPN software often installs a lower-metric
        # default route, so metric alone is not a reliable definition of LAN.
        $candidates = Get-NetIPConfiguration -ErrorAction SilentlyContinue |
            Where-Object {
                $_.NetAdapter -and
                $_.NetAdapter.Status -eq 'Up' -and
                $_.IPv4Address -and
                $_.IPv4DefaultGateway
            } |
            ForEach-Object {
                $adapter = Get-NetAdapter -InterfaceIndex $_.NetAdapter.ifIndex `
                    -ErrorAction SilentlyContinue

                $metric = [int]::MaxValue
                if ($_.NetIPv4Interface -and
                    $_.NetIPv4Interface.PSObject.Properties['InterfaceMetric']) {
                    $metric = [int]$_.NetIPv4Interface.InterfaceMetric
                }

                [pscustomobject]@{
                    Config       = $_
                    PhysicalRank = if ($adapter -and $adapter.HardwareInterface) { 0 } else { 1 }
                    Metric       = $metric
                }
            }

        $selected = $candidates |
            Sort-Object PhysicalRank, Metric |
            Select-Object -First 1

        if ($selected) {
            $config = $selected.Config
            return '{0} ({1})' -f $config.IPv4Address.IPAddress, $config.InterfaceAlias
        }

        $fallback = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
            Where-Object {
                $_.IPAddress -notlike '127.*' -and
                $_.IPAddress -notlike '169.254.*'
            } |
            Select-Object -First 1

        if ($fallback) { return $fallback.IPAddress }
        return 'None'
    }
    catch {
        return 'None'
    }
}

# -----------------------------------------------------------------------------
# System snapshot
# -----------------------------------------------------------------------------
# Collect each CIM class once. Reusing these objects avoids repeated WMI/CIM
# round trips while the panel is being assembled.
$computerSystem = Get-CimInstance Win32_ComputerSystem -ErrorAction SilentlyContinue
$operatingSystem = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
$processor = Get-CimInstance Win32_Processor -ErrorAction SilentlyContinue |
    Select-Object -First 1
$videoControllers = @(
    Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue
)
$soundDevice = Get-CimInstance Win32_SoundDevice -ErrorAction SilentlyContinue |
    Where-Object Status -eq 'OK' |
    Select-Object -First 1
$logicalDrives = @(
    Get-CimInstance Win32_LogicalDisk -ErrorAction SilentlyContinue |
        Where-Object DeviceID |
        Sort-Object DeviceID
)

$timeNow = Get-Date -Format 'HH:mm'
$dateNow = Get-Date -Format 'ddd dd MMM'
$userName = if ($env:USERNAME) {
    $env:USERNAME
}
else {
    [Environment]::UserName
}
$hostName = if ($env:COMPUTERNAME) {
    $env:COMPUTERNAME.ToLowerInvariant()
}
else {
    [Environment]::MachineName.ToLowerInvariant()
}

$theme = Get-WindowsTheme
$terminal = Get-TerminalName
$shell = 'PowerShell {0}' -f $PSVersionTable.PSVersion.ToString()

$uptime = Get-FirstValue {
    $span = (Get-Date) - $operatingSystem.LastBootUpTime
    if ($span.Days -gt 0) {
        return '{0}d {1}h {2}m' -f $span.Days, $span.Hours, $span.Minutes
    }
    return '{0}h {1}m' -f $span.Hours, $span.Minutes
}

# Build rows directly from the cached logical-drive snapshot. Missing drive
# letters are absent from Win32_LogicalDisk and therefore never become rows.
$driveDetails = foreach ($drive in $logicalDrives | Where-Object DriveType -ne 5) {
    [pscustomobject]@{
        Label = "$($drive.DeviceID) Drive"
        Value = Format-DriveUsage -Drive $drive
        Kind  = 'Normal'
    }
}

# Optical drives remain visible when the hardware exists, even with an empty
# tray. If no optical drive is installed, no optical row is emitted.
$opticalDetails = foreach ($drive in $logicalDrives | Where-Object DriveType -eq 5) {
    [pscustomobject]@{
        Label = "$($drive.DeviceID) Optical"
        Value = Format-DriveUsage -Drive $drive
        Kind  = 'Normal'
    }
}

$appCount = Get-InstalledAppCount
$resolution = Get-ScreenResolution

$osName = Get-FirstValue { $operatingSystem.Caption -replace '^Microsoft\s+', '' }
$build = Get-FirstValue { $operatingSystem.BuildNumber }
$machine = Get-FirstValue { '{0} {1}' -f $computerSystem.Manufacturer.Trim(), $computerSystem.Model.Trim() }
$cpu = Get-FirstValue {
    $name = ($processor.Name -replace '\s+', ' ').Trim()
    '{0} / {1}C {2}T' -f $name, $processor.NumberOfCores, $processor.NumberOfLogicalProcessors
}

$gpu = Get-FirstValue {
    $names = $videoControllers |
        Where-Object Name |
        Select-Object -ExpandProperty Name -Unique
    (@($names) | Select-Object -First 2) -join ' + '
}

$audio = Get-FirstValue { $soundDevice.Name }

$memory = Get-FirstValue {
    $totalBytes = [double]$operatingSystem.TotalVisibleMemorySize * 1KB
    $freeBytes = [double]$operatingSystem.FreePhysicalMemory * 1KB
    $usedBytes = $totalBytes - $freeBytes
    '{0} / {1}' -f (Format-Bytes $usedBytes), (Format-Bytes $totalBytes)
}

$lan = Get-PrimaryIPv4

# -----------------------------------------------------------------------------
# Display data
# -----------------------------------------------------------------------------
# Keep the artwork unchanged; the detail list is deliberately separate so
# system-data changes do not disturb the ASCII art geometry.
$catArt = @'
                    .c0N.   .'c.
         'Okdl:'  ;OMMMMKOKNMMW:;o0l  .'.
         ;MMMMMMWWMMMMMMMMMMMMMMMMMXKWMMK
         'MMMMMMMMMMMMMMMMMMMMMMMMMMMMMMK
          NMMMMMMMMMMMMMMMMMMMMMMMMMMMMMO
          dMMMMMMMMMMMMMMMMMMMMMMMMMMMMM:
          'MMMMMMMMMMMMMMMMMMMMMMMMMMMMM.
          'MMMMMMMMMMMMMMMMMMMMMMMMMMMMM;
          lMMMMM  MMMMMMMMMM  MMMMMMMMMM,
          KMMMMM  MMMMMMMMMM  MMMMMMMMMM.
         ;WMMMMMkNMMMMMMMMMMONMMMMMMMMMW:
       oNMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMO
      .,cxKWMMMMMMMMMMMMMMMMMMMMMMMMMMMXdxo
         ;kWMMMMMMMMMMMMMMMMMMMMMMMMMMMM:
         '::'  .;ok0NMMMMWNK0kdoc;'  '::'
                   .:cc:;;.
                   .o0MMMK'
                     xMMM:
                     KMMMl
                    .MMMMo
                    ,MMMMx
                    oMMMMx
                    OMMMMO
                    .OMMMd
                      :Nl
'@ -split "`r?`n"

$details = @(
    [pscustomobject]@{ Label = '';            Value = 'the cat';                    Kind = 'Title' }
    [pscustomobject]@{ Label = '';            Value = '';                           Kind = 'Blank' }
    [pscustomobject]@{ Label = 'Time';        Value = "$timeNow - $dateNow";         Kind = 'Normal' }
    [pscustomobject]@{ Label = 'User';        Value = "$userName @ $hostName";       Kind = 'User' }
    [pscustomobject]@{ Label = '';            Value = '';                           Kind = 'Blank' }
    [pscustomobject]@{ Label = 'Theme';       Value = $theme;                       Kind = 'Normal' }
    [pscustomobject]@{ Label = 'Terminal';    Value = $terminal;                    Kind = 'Normal' }
    [pscustomobject]@{ Label = 'Shell';       Value = $shell;                       Kind = 'Normal' }
    [pscustomobject]@{ Label = 'Uptime';      Value = $uptime;                      Kind = 'Normal' }
    $driveDetails
    $opticalDetails
    [pscustomobject]@{ Label = 'Apps';        Value = "$appCount installed";         Kind = 'Normal' }
    [pscustomobject]@{ Label = 'Resolution';  Value = $resolution;                  Kind = 'Normal' }
    [pscustomobject]@{ Label = 'OS';          Value = $osName;                      Kind = 'Normal' }
    [pscustomobject]@{ Label = 'Build';       Value = $build;                       Kind = 'Normal' }
    [pscustomobject]@{ Label = 'Machine';     Value = $machine;                     Kind = 'Normal' }
    [pscustomobject]@{ Label = 'CPU';         Value = $cpu;                         Kind = 'Normal' }
    [pscustomobject]@{ Label = 'GPU';         Value = $gpu;                         Kind = 'Normal' }
    [pscustomobject]@{ Label = 'Audio';       Value = $audio;                       Kind = 'Normal' }
    [pscustomobject]@{ Label = 'Memory';      Value = $memory;                      Kind = 'Normal' }
    [pscustomobject]@{ Label = 'LAN';         Value = $lan;                         Kind = 'Normal' }
    [pscustomobject]@{ Label = '';            Value = '';                           Kind = 'Blank' }
    [pscustomobject]@{ Label = '';            Value = 'the cat';                    Kind = 'Footer' }
)

# -----------------------------------------------------------------------------
# Render
# -----------------------------------------------------------------------------
Write-Host ''
Write-Host $Bold -NoNewline

$lineCount = [Math]::Max($catArt.Count, $details.Count)
for ($i = 0; $i -lt $lineCount; $i++) {
    $art = if ($i -lt $catArt.Count) { $catArt[$i] } else { '' }
    $detail = if ($i -lt $details.Count) { $details[$i] } else { $null }

    $artColor = if ($i -ge 15) { $Gray } else { $White }
    Write-Host -NoNewline "$artColor  $($art.PadRight(50))$Reset"

    if (-not $detail) {
        Write-Host ''
        continue
    }

    switch ($detail.Kind) {
        { $_ -in 'Title', 'Footer' } {
            Write-Host "${White}the ${Blue}cat${Reset}"
        }
        'Blank' {
            Write-Host ''
        }
        'User' {
            Write-Host "${Cyan}$($detail.Value)$Reset"
        }
        default {
            $label = $detail.Label.PadRight(12)
            Write-Host "${Gray}$label${White}» ${Blue}$($detail.Value)$Reset"
        }
    }
}

Write-Host $Reset -NoNewline
Write-Host ''
