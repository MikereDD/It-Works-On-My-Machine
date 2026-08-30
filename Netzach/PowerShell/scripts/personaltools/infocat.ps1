#Requires -Version 7.0
<#
.SYNOPSIS
    Windows system information cat.

.DESCRIPTION
    Rebuilt PowerShell companion to infocat-pi.
    Standalone: does not require profile.d, ui.ps1, or hard-coded user paths.
#>

#--------------------------------------------
# file:     infocat.ps1
# author:   Mike Redd
# version:  1.2
# restored: 2026-07-12
# desc:     Windows / PowerShell system info cat
#--------------------------------------------

[CmdletBinding()]
param(
    [switch]$NoColor
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'SilentlyContinue'
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)

$ESC = [char]27
function Get-Ansi {
    param([Parameter(Mandatory)][string]$Code)
    if ($NoColor -or -not $Host.UI.SupportsVirtualTerminal) { return '' }
    return "$ESC[$Code" + 'm'
}

$Reset  = Get-Ansi '0'
$Bold   = Get-Ansi '1'
$White  = Get-Ansi '97'
$Gray   = Get-Ansi '90'
$Blue   = Get-Ansi '94'
$Cyan   = Get-Ansi '96'
$Green  = Get-Ansi '92'
$Yellow = Get-Ansi '93'

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

function Get-LogicalDrive {
    param([Parameter(Mandatory)][string]$DriveName)

    try {
        $deviceId = "$($DriveName.ToUpperInvariant()):"

        return Get-CimInstance Win32_LogicalDisk |
            Where-Object DeviceID -eq $deviceId |
            Select-Object -First 1
    }
    catch {
        return $null
    }
}

function Get-DriveUsage {
    param([Parameter(Mandatory)][string]$DriveName)

    $drive = Get-LogicalDrive -DriveName $DriveName
    if (-not $drive) { return 'Not connected' }

    # DriveType:
    # 2 = Removable, 3 = Local disk, 4 = Network, 5 = Optical
    if ($drive.DriveType -eq 5) {
        if (-not $drive.Size -or [double]$drive.Size -le 0) {
            return 'Optical - Empty'
        }

        $label = if ($drive.VolumeName) { $drive.VolumeName } else { 'Media' }
        return 'Optical - {0} ({1})' -f $label, (Format-Bytes ([double]$drive.Size))
    }

    if (-not $drive.Size -or [double]$drive.Size -le 0) {
        return 'Detected - Unavailable'
    }

    $total = [double]$drive.Size
    $free = [double]$drive.FreeSpace
    $used = $total - $free
    $pct = [math]::Round(($used / $total) * 100)

    return '{0} / {1} ({2}%)' -f (
        Format-Bytes $used
    ), (
        Format-Bytes $total
    ), $pct
}

function Get-OpticalDriveStatus {
    param([Parameter(Mandatory)][string]$DriveName)

    $drive = Get-LogicalDrive -DriveName $DriveName
    if (-not $drive) { return 'Not detected' }

    if ($drive.DriveType -ne 5) {
        return 'Detected - not optical'
    }

    if (-not $drive.Size -or [double]$drive.Size -le 0) {
        return 'Optical - Empty'
    }

    $label = if ($drive.VolumeName) { $drive.VolumeName } else { 'Media' }
    return 'Optical - {0} ({1})' -f $label, (Format-Bytes ([double]$drive.Size))
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
    $paths = @(
        'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )

    try {
        $names = foreach ($path in $paths) {
            Get-ItemProperty $path -ErrorAction SilentlyContinue |
                Where-Object DisplayName |
                Select-Object -ExpandProperty DisplayName
        }

        return @($names | Sort-Object -Unique).Count
    }
    catch {
        return 0
    }
}

function Get-PrimaryIPv4 {
    try {
        $config = Get-NetIPConfiguration |
            Where-Object {
                $_.NetAdapter.Status -eq 'Up' -and
                $_.IPv4Address -and
                $_.IPv4DefaultGateway
            } |
            Sort-Object { $_.NetAdapter.InterfaceMetric } |
            Select-Object -First 1

        if ($config) {
            return '{0} ({1})' -f $config.IPv4Address.IPAddress, $config.InterfaceAlias
        }

        $fallback = Get-NetIPAddress -AddressFamily IPv4 |
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

$computerSystem = Get-CimInstance Win32_ComputerSystem
$operatingSystem = Get-CimInstance Win32_OperatingSystem
$processor = Get-CimInstance Win32_Processor | Select-Object -First 1
$videoControllers = Get-CimInstance Win32_VideoController
$soundDevice = Get-CimInstance Win32_SoundDevice |
    Where-Object Status -eq 'OK' |
    Select-Object -First 1

$timeNow = Get-Date -Format 'HH:mm'
$dateNow = Get-Date -Format 'ddd dd MMM'
$userName = if ($env:USERNAME) { $env:USERNAME } else { [Environment]::UserName }
$hostName = if ($env:COMPUTERNAME) { $env:COMPUTERNAME.ToLowerInvariant() } else { [Environment]::MachineName.ToLowerInvariant() }

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

$driveUsage = [ordered]@{
    'C' = Get-DriveUsage 'C'
    'E' = Get-DriveUsage 'E'
    'F' = Get-DriveUsage 'F'
    'G' = Get-DriveUsage 'G'
    'H' = Get-DriveUsage 'H'
    'P' = Get-DriveUsage 'P'
}

$opticalDriveStatus = Get-OpticalDriveStatus 'D'

$appCount = Get-InstalledAppCount
$resolution = Get-ScreenResolution

$osName = Get-FirstValue { $operatingSystem.Caption -replace '^Microsoft\s+', '' }
$build = Get-FirstValue { '{0}.{1}' -f $operatingSystem.Version, $operatingSystem.BuildNumber }
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
    [pscustomobject]@{ Label = 'C: Drive';    Value = $driveUsage['C'];              Kind = 'Normal' }
    [pscustomobject]@{ Label = 'E: Drive';    Value = $driveUsage['E'];              Kind = 'Normal' }
    [pscustomobject]@{ Label = 'F: Drive';    Value = $driveUsage['F'];              Kind = 'Normal' }
    [pscustomobject]@{ Label = 'G: Drive';    Value = $driveUsage['G'];              Kind = 'Normal' }
    [pscustomobject]@{ Label = 'H: Drive';    Value = $driveUsage['H'];              Kind = 'Normal' }
    [pscustomobject]@{ Label = 'P: Drive';    Value = $driveUsage['P'];              Kind = 'Normal' }
    [pscustomobject]@{ Label = 'D: Optical';  Value = $opticalDriveStatus;           Kind = 'Normal' }
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
        'Title' {
            Write-Host "${White}the ${Blue}cat${Reset}"
        }
        'Footer' {
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
