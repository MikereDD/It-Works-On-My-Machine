#Requires -Version 7.0
<#
.SYNOPSIS
    Display a compact Windows system-information panel beside the infocat ASCII art.

.DESCRIPTION
    PowerShell companion to infocat-pi for the Netzach Windows workstation.

    The script takes a lightweight snapshot of the current Windows session and
    hardware, formats that data into an InfoCat panel, and renders it next
    to the preserved cat artwork.

    It is intentionally standalone: it does not require profile.d, ui.ps1, or
    hard-coded user paths.

.PARAMETER NoColor
    Disable ANSI color sequences. Useful when redirecting output or running in a
    host that does not render virtual-terminal colors correctly.

.PARAMETER Compact
    Short summary with the original cat art. Skips app, drive, monitor, pagefile,
    font, and live CPU frequency discovery to reduce collection overhead.

.PARAMETER Timing
    Append elapsed milliseconds for selected native collectors (read only).

.NOTES
    Machine:      Netzach / Windows
    PowerShell:   7.0+
    Dependencies: Built-in PowerShell cmdlets, CIM/WMI providers, Windows Forms,
                  and the Windows networking cmdlets.

    Design notes:
      - Native Windows APIs and PowerShell only; Fastfetch is not required.
      - Hardware queries are collected once and reused where practical.
      - Logical drives are discovered dynamically; disconnected drive letters are
        omitted instead of being displayed as "Not connected".
      - Individual probes fail soft so one unavailable subsystem does not prevent
        the rest of the panel from rendering.
      - Additional battery, pagefile, GPU and display details are opportunistic.
      - Default playback audio endpoint is read via Windows Core Audio.
      - Display refresh uses rational rates where Windows exposes them.
      - Optional monitor names/advanced color and GPU memory use Windows APIs.
      - CPU clock is a CIM-reported processor figure, not turbo/live telemetry.
      - Adaptive value wrapping avoids terminal line overflow without clipping.
      - Small integrated-GPU local allocations are distinguished from shared memory.
      - Windows theme, accent, and full kernel build are retrieved from native registry keys.
      - Windows Terminal font reads the active profile's JSONC settings (read only).
      - Physical Ethernet/Wi-Fi and positively identified VPNs are separate rows.
      - CPU nominal clock and optional Windows performance frequency are not turbo claims.
      - Compact mode skips expensive full-view collectors; default output remains Full.
      - Separate label contrast from cat shading without changing the artwork.
      - Optional timings report measures collector wall time, not device benchmarks.
      - Narrow terminals stack the panel, suppressing oversized art only below 45 columns.
      - Native topology retries with CPU-set fallback and actionable diagnostics.
      - .NET network enumeration bypasses slower NetAdapter queries when reliable.
      - Existing native/CIM and network-cmdlet collectors remain fallbacks.
      - Compact footer is aligned below the intact cat artwork.
#>

# =============================================================================
# File:        infocat.ps1
# Author:      Mike Redd
# Version:     1.8.1
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
    [switch]$NoColor,
    [switch]$Compact,
    [switch]$Timing
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
$Gray  = Get-Ansi '90' # Reserved for the original cat shading.
$LabelColor = Get-Ansi '37' # Normal gray, readable on dark backgrounds.
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


# The display configuration API exposes a rational refresh rate (e.g. 5995/100),
# while EnumDisplaySettings.dmDisplayFrequency is only an integer. Map the active
# path's source GDI name back to the screen device name for stable per-monitor
# matching, then fall back to EnumDisplaySettings if Windows has no rational rate.
function Get-DisplayRefreshRates {
    try {
        if (-not ('InfoCatDisplayConfig' -as [type])) {
            Add-Type -ErrorAction Stop -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;

public static class InfoCatDisplayConfig {
    private const uint QDC_ONLY_ACTIVE_PATHS = 2;
    private const int ERROR_INSUFFICIENT_BUFFER = 122;

    [StructLayout(LayoutKind.Sequential)]
    public struct LUID { public uint LowPart; public int HighPart; }

    [StructLayout(LayoutKind.Sequential)]
    public struct RATIONAL { public uint Numerator; public uint Denominator; }

    [StructLayout(LayoutKind.Sequential)]
    public struct SOURCE_INFO {
        public LUID adapterId;
        public uint id;
        public uint modeInfoIdx;
        public uint statusFlags;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct TARGET_INFO {
        public LUID adapterId;
        public uint id;
        public uint modeInfoIdx;
        public uint outputTechnology;
        public uint rotation;
        public uint scaling;
        public RATIONAL refreshRate;
        public uint scanLineOrdering;
        [MarshalAs(UnmanagedType.Bool)] public bool targetAvailable;
        public uint statusFlags;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct PATH_INFO {
        public SOURCE_INFO sourceInfo;
        public TARGET_INFO targetInfo;
        public uint flags;
    }

    // DISPLAYCONFIG_MODE_INFO is a 64-byte native struct. Its mode union is
    // not read here; QueryDisplayConfig still requires a correctly sized array.
    [StructLayout(LayoutKind.Explicit, Size = 64)]
    public struct MODE_INFO { [FieldOffset(0)] public uint infoType; }

    [StructLayout(LayoutKind.Sequential)]
    public struct DEVICE_INFO_HEADER {
        public uint type;
        public uint size;
        public LUID adapterId;
        public uint id;
    }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    public struct SOURCE_DEVICE_NAME {
        public DEVICE_INFO_HEADER header;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)]
        public string viewGdiDeviceName;
    }

    [DllImport("user32.dll")]
    private static extern int GetDisplayConfigBufferSizes(uint flags, out uint pathCount, out uint modeCount);

    [DllImport("user32.dll")]
    private static extern int QueryDisplayConfig(uint flags,
        ref uint pathCount, [Out] PATH_INFO[] paths,
        ref uint modeCount, [Out] MODE_INFO[] modes, IntPtr topologyId);

    [DllImport("user32.dll", EntryPoint = "DisplayConfigGetDeviceInfo")]
    private static extern int GetDeviceInfo(ref SOURCE_DEVICE_NAME info);

    public static Dictionary<string, double> GetRates() {
        var rates = new Dictionary<string, double>(StringComparer.OrdinalIgnoreCase);
        // Refuse native calls if the interop layout differs from the Windows SDK.
        if (Marshal.SizeOf(typeof(PATH_INFO)) != 72 ||
            Marshal.SizeOf(typeof(MODE_INFO)) != 64) return rates;
        for (int attempt = 0; attempt < 3; attempt++) {
            uint pathCount, modeCount;
            if (GetDisplayConfigBufferSizes(QDC_ONLY_ACTIVE_PATHS, out pathCount, out modeCount) != 0)
                break;
            if (pathCount == 0 || pathCount > 128 || modeCount == 0 || modeCount > 512)
                break;
            var paths = new PATH_INFO[(int)pathCount];
            var modes = new MODE_INFO[(int)modeCount];
            int status = QueryDisplayConfig(QDC_ONLY_ACTIVE_PATHS,
                ref pathCount, paths, ref modeCount, modes, IntPtr.Zero);
            if (status == ERROR_INSUFFICIENT_BUFFER) continue;
            if (status != 0) break;
            for (int i = 0; i < pathCount; i++) {
                if ((paths[i].flags & 1) == 0) continue;
                var hz = paths[i].targetInfo.refreshRate;
                if (hz.Denominator == 0) continue;
                double value = (double)hz.Numerator / hz.Denominator;
                if (value < 10 || value > 1000) continue;
                var name = new SOURCE_DEVICE_NAME();
                name.header.type = 1; // DISPLAYCONFIG_DEVICE_INFO_GET_SOURCE_NAME
                name.header.size = (uint)Marshal.SizeOf(typeof(SOURCE_DEVICE_NAME));
                name.header.adapterId = paths[i].sourceInfo.adapterId;
                name.header.id = paths[i].sourceInfo.id;
                if (GetDeviceInfo(ref name) == 0 &&
                    !String.IsNullOrWhiteSpace(name.viewGdiDeviceName)) {
                    if (!rates.ContainsKey(name.viewGdiDeviceName))
                        rates.Add(name.viewGdiDeviceName, value);
                }
            }
            break;
        }
        return rates;
    }
}
'@
        }
        return [InfoCatDisplayConfig]::GetRates()
    }
    catch {
        return @{}
    }
}

# Query monitor friendly names and Windows Advanced Color state by active
# DISPLAYCONFIG path. The GDI source name ties each target back to its screen.
# Advanced Color can mean HDR or wide-color; do not label it "HDR enabled"
# unless Windows exposes an unambiguous HDR-specific result in a future probe.
function Get-DisplayMetadata {
    try {
        if (-not ('InfoCatMonitorMetadata' -as [type])) {
            Add-Type -ErrorAction Stop -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;

public static class InfoCatMonitorMetadata {
    private const uint QDC_ONLY_ACTIVE_PATHS = 2;
    private const int ERROR_INSUFFICIENT_BUFFER = 122;

    [StructLayout(LayoutKind.Sequential)]
    public struct LUID { public uint LowPart; public int HighPart; }
    [StructLayout(LayoutKind.Sequential)]
    public struct RATIONAL { public uint Numerator; public uint Denominator; }
    [StructLayout(LayoutKind.Sequential)]
    public struct SOURCE_INFO {
        public LUID adapterId; public uint id; public uint modeInfoIdx; public uint statusFlags;
    }
    [StructLayout(LayoutKind.Sequential)]
    public struct TARGET_INFO {
        public LUID adapterId; public uint id; public uint modeInfoIdx;
        public uint outputTechnology; public uint rotation; public uint scaling;
        public RATIONAL refreshRate; public uint scanLineOrdering;
        [MarshalAs(UnmanagedType.Bool)] public bool targetAvailable;
        public uint statusFlags;
    }
    [StructLayout(LayoutKind.Sequential)]
    public struct PATH_INFO {
        public SOURCE_INFO sourceInfo; public TARGET_INFO targetInfo; public uint flags;
    }
    [StructLayout(LayoutKind.Explicit, Size = 64)]
    public struct MODE_INFO { [FieldOffset(0)] public uint infoType; }
    [StructLayout(LayoutKind.Sequential)]
    public struct DEVICE_INFO_HEADER {
        public uint type; public uint size; public LUID adapterId; public uint id;
    }
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    public struct SOURCE_NAME {
        public DEVICE_INFO_HEADER header;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)]
        public string viewGdiDeviceName;
    }
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    public struct TARGET_NAME {
        public DEVICE_INFO_HEADER header;
        public uint flags; public uint outputTechnology;
        public ushort edidManufactureId; public ushort edidProductCodeId;
        public uint connectorInstance;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 64)]
        public string monitorFriendlyDeviceName;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)]
        public string monitorDevicePath;
    }
    [StructLayout(LayoutKind.Sequential)]
    public struct ADVANCED_COLOR {
        public DEVICE_INFO_HEADER header;
        public uint value; public uint colorEncoding; public uint bitsPerColorChannel;
    }
    public sealed class DisplayEntry {
        public string FriendlyName { get; set; }
        public bool ColorKnown { get; set; }
        public bool ColorSupported { get; set; }
        public bool ColorEnabled { get; set; }
    }

    [DllImport("user32.dll")]
    private static extern int GetDisplayConfigBufferSizes(uint flags, out uint pathCount, out uint modeCount);
    [DllImport("user32.dll")]
    private static extern int QueryDisplayConfig(uint flags, ref uint pathCount,
        [Out] PATH_INFO[] paths, ref uint modeCount, [Out] MODE_INFO[] modes, IntPtr topology);
    [DllImport("user32.dll", EntryPoint = "DisplayConfigGetDeviceInfo")]
    private static extern int DeviceInfo(ref SOURCE_NAME info);
    [DllImport("user32.dll", EntryPoint = "DisplayConfigGetDeviceInfo")]
    private static extern int DeviceInfo(ref TARGET_NAME info);
    [DllImport("user32.dll", EntryPoint = "DisplayConfigGetDeviceInfo")]
    private static extern int DeviceInfo(ref ADVANCED_COLOR info);

    public static Dictionary<string, DisplayEntry> GetMetadata() {
        var found = new Dictionary<string, DisplayEntry>(StringComparer.OrdinalIgnoreCase);
        if (Marshal.SizeOf(typeof(PATH_INFO)) != 72 ||
            Marshal.SizeOf(typeof(MODE_INFO)) != 64) return found;
        for (int attempt = 0; attempt < 3; ++attempt) {
            uint pc, mc;
            if (GetDisplayConfigBufferSizes(QDC_ONLY_ACTIVE_PATHS, out pc, out mc) != 0) break;
            if (pc == 0 || pc > 128 || mc == 0 || mc > 512) break;
            var paths = new PATH_INFO[(int)pc];
            var modes = new MODE_INFO[(int)mc];
            int rc = QueryDisplayConfig(QDC_ONLY_ACTIVE_PATHS, ref pc, paths,
                ref mc, modes, IntPtr.Zero);
            if (rc == ERROR_INSUFFICIENT_BUFFER) continue;
            if (rc != 0) break;
            for (int i = 0; i < pc; ++i) {
                var path = paths[i];
                if ((path.flags & 1) == 0) continue;
                var source = new SOURCE_NAME();
                source.header.type = 1; // GET_SOURCE_NAME
                source.header.size = (uint)Marshal.SizeOf(typeof(SOURCE_NAME));
                source.header.adapterId = path.sourceInfo.adapterId;
                source.header.id = path.sourceInfo.id;
                if (DeviceInfo(ref source) != 0 ||
                    String.IsNullOrWhiteSpace(source.viewGdiDeviceName)) continue;
                var entry = new DisplayEntry();
                var target = new TARGET_NAME();
                target.header.type = 2; // GET_TARGET_NAME
                target.header.size = (uint)Marshal.SizeOf(typeof(TARGET_NAME));
                target.header.adapterId = path.targetInfo.adapterId;
                target.header.id = path.targetInfo.id;
                if (DeviceInfo(ref target) == 0 &&
                    !String.IsNullOrWhiteSpace(target.monitorFriendlyDeviceName)) {
                    entry.FriendlyName = target.monitorFriendlyDeviceName.Trim('\0', ' ');
                }
                var color = new ADVANCED_COLOR();
                color.header.type = 9; // GET_ADVANCED_COLOR_INFO
                color.header.size = (uint)Marshal.SizeOf(typeof(ADVANCED_COLOR));
                color.header.adapterId = path.targetInfo.adapterId;
                color.header.id = path.targetInfo.id;
                if (DeviceInfo(ref color) == 0) {
                    entry.ColorKnown = true;
                    entry.ColorSupported = (color.value & 1) != 0;
                    entry.ColorEnabled = (color.value & 2) != 0;
                }
                if (!found.ContainsKey(source.viewGdiDeviceName))
                    found.Add(source.viewGdiDeviceName, entry);
            }
            break;
        }
        return found;
    }
}
'@
        }
        return [InfoCatMonitorMetadata]::GetMetadata()
    }
    catch {
        return @{}
    }
}

# Native display modes: query Windows directly. This is not a Fastfetch call.
# EnumDisplaySettingsW returns physical mode resolution and frequency for each
# Screen.DeviceName (\\.\DISPLAY1 etc.) without assuming monitor ordering.
function Get-DisplayDetails {
    try {
        Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
        if (-not ('InfoCatWin32Display' -as [type])) {
            Add-Type -ErrorAction Stop -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

public static class InfoCatWin32Display {
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    public struct DEVMODE {
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string dmDeviceName;
        public ushort dmSpecVersion;
        public ushort dmDriverVersion;
        public ushort dmSize;
        public ushort dmDriverExtra;
        public uint dmFields;
        public int dmPositionX;
        public int dmPositionY;
        public uint dmDisplayOrientation;
        public uint dmDisplayFixedOutput;
        public short dmColor;
        public short dmDuplex;
        public short dmYResolution;
        public short dmTTOption;
        public short dmCollate;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string dmFormName;
        public ushort dmLogPixels;
        public uint dmBitsPerPel;
        public uint dmPelsWidth;
        public uint dmPelsHeight;
        public uint dmDisplayFlags;
        public uint dmDisplayFrequency;
        public uint dmICMMethod;
        public uint dmICMIntent;
        public uint dmMediaType;
        public uint dmDitherType;
        public uint dmReserved1;
        public uint dmReserved2;
        public uint dmPanningWidth;
        public uint dmPanningHeight;
    }
    [DllImport("user32.dll", CharSet = CharSet.Unicode, EntryPoint = "EnumDisplaySettingsW")]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool EnumDisplaySettings(string deviceName, int modeNum, ref DEVMODE devMode);
}
'@
        }
        $screens = @([System.Windows.Forms.Screen]::AllScreens)
        $refresh = Get-DisplayRefreshRates
        $metadata = Get-DisplayMetadata
        $index = 0
        foreach ($screen in $screens) {
            $index++
            $mode = [InfoCatWin32Display+DEVMODE]::new()
            $mode.dmSize = [uint16][System.Runtime.InteropServices.Marshal]::SizeOf($mode)
            $resolved = [InfoCatWin32Display]::EnumDisplaySettings(
                [string]$screen.DeviceName, -1, [ref]$mode
            )
            $width = if ($resolved -and $mode.dmPelsWidth -gt 0) {
                [int]$mode.dmPelsWidth
            } else { [int]$screen.Bounds.Width }
            $height = if ($resolved -and $mode.dmPelsHeight -gt 0) {
                [int]$mode.dmPelsHeight
            } else { [int]$screen.Bounds.Height }

            $rate = ''
            $device = [string]$screen.DeviceName
            if ($refresh -and $refresh.ContainsKey($device)) {
                $hz = [double]$refresh[$device]
                $rate = ' @ {0} Hz' -f $hz.ToString('0.##',
                    [System.Globalization.CultureInfo]::InvariantCulture)
            }
            elseif ($resolved -and $mode.dmDisplayFrequency -gt 1 -and
                $mode.dmDisplayFrequency -lt 1000) {
                # Integer-only fallback; preserve the reported value rather than
                # pretending a 59 Hz DEVMODE field is exactly 60 Hz.
                $rate = ' @ {0} Hz' -f $mode.dmDisplayFrequency
            }
            $primary = if ($screen.Primary) { ' [Primary]' } else { '' }
            $name = ''
            $color = ''
            if ($metadata -and $metadata.ContainsKey($device)) {
                $entry = $metadata[$device]
                if (-not [string]::IsNullOrWhiteSpace($entry.FriendlyName)) {
                    $name = "$($entry.FriendlyName) - "
                }
                if ($entry.ColorKnown -and $entry.ColorEnabled) {
                    $color = ' [Adv.Color: On]'
                }
                elseif ($entry.ColorKnown -and $entry.ColorSupported) {
                    $color = ' [Adv.Color: Available]'
                }
            }
            [pscustomobject]@{
                Label = "Display $index"
                Value = '{0}{1}x{2}{3}{4}{5}' -f $name, $width, $height, $rate, $primary, $color
                Kind  = 'Normal'
            }
        }
    }
    catch {
        # If Windows Forms or user32 is unavailable, the caller uses the
        # existing primary-resolution summary, rather than blocking the cat.
        return
    }
}

# GetSystemPowerStatus separates external AC power from battery charging.
# Combine it with the already used Win32_Battery status when available.
function Get-BatterySummary {
    try {
        $batteries = @(Get-CimInstance Win32_Battery -ErrorAction Stop)
        if ($batteries.Count -eq 0) { return $null }
        if (-not ('InfoCatPowerStatus' -as [type])) {
            Add-Type -ErrorAction Stop -TypeDefinition @'
using System.Runtime.InteropServices;
public static class InfoCatPowerStatus {
    [StructLayout(LayoutKind.Sequential)]
    public struct SYSTEM_POWER_STATUS {
        public byte ACLineStatus;
        public byte BatteryFlag;
        public byte BatteryLifePercent;
        public byte SystemStatusFlag;
        public uint BatteryLifeTime;
        public uint BatteryFullLifeTime;
    }
    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern bool GetSystemPowerStatus(out SYSTEM_POWER_STATUS status);
}
'@
        }
        $power = [InfoCatPowerStatus+SYSTEM_POWER_STATUS]::new()
        $gotPower = [InfoCatPowerStatus]::GetSystemPowerStatus([ref]$power)
        foreach ($battery in $batteries) {
            $charge = if ($gotPower -and $power.BatteryLifePercent -le 100) {
                [int]$power.BatteryLifePercent
            }
            elseif ($null -ne $battery.EstimatedChargeRemaining) {
                [int]$battery.EstimatedChargeRemaining
            } else { -1 }
            $level = if ($charge -ge 0 -and $charge -le 100) {
                "$charge%"
            } else { 'Unknown charge' }
            $ac = if (-not $gotPower) { 'AC unknown' }
                  elseif ($power.ACLineStatus -eq 1) { 'AC connected' }
                  elseif ($power.ACLineStatus -eq 0) { 'On battery' }
                  else { 'AC unknown' }
            $state = if ($gotPower -and ($power.BatteryFlag -band 8)) { 'Charging' }
                     else {
                         switch ([int]$battery.BatteryStatus) {
                             1 { 'Discharging' }
                             2 { 'Not charging' }
                             3 { 'Fully charged' }
                             4 { 'Low' }
                             5 { 'Critical' }
                             { $_ -in 6, 7, 8, 9 } { 'Charging' }
                             11 { 'Partially charged' }
                             default { 'Status unknown' }
                         }
                     }
            if ($ac -eq 'On battery' -and $state -eq 'Discharging') {
                return "$level (Discharging)"
            }
            if ($ac -eq 'AC unknown') { return "$level ($state)" }
            return "$level ($ac, $state)"
        }
    }
    catch { return $null }
}

function Get-PageFileSummary {
    try {
        # AllocatedBaseSize and CurrentUsage are in MiB, not bytes.
        $pages = @(Get-CimInstance Win32_PageFileUsage -ErrorAction Stop)
        if ($pages.Count -eq 0) { return $null }
        $allocatedMiB = 0.0
        $usedMiB = 0.0
        foreach ($page in $pages) {
            $allocatedMiB += [double]$page.AllocatedBaseSize
            $usedMiB += [double]$page.CurrentUsage
        }
        if ($allocatedMiB -le 0) { return $null }
        $used = Format-Bytes ($usedMiB * 1MB)
        $allocated = Format-Bytes ($allocatedMiB * 1MB)
        return "$used / $allocated"
    }
    catch { return $null }
}

# DXGI 1.1 reports SIZE_T-sized dedicated video memory. Win32_VideoController
# AdapterRAM is a 32-bit value and can truncate modern 8+ GiB GPUs, so we
# deliberately do not substitute it when DXGI is unavailable.
function Get-DxgiAdapters {
    try {
        if (-not ('InfoCatDxgi' -as [type])) {
            Add-Type -ErrorAction Stop -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;

public static class InfoCatDxgi {
    private static readonly Guid IID_IDXGIFactory1 =
        new Guid("770AAE78-F26F-4DBA-A829-253C83D1B387");
    [StructLayout(LayoutKind.Sequential)]
    private struct LUID { public uint LowPart; public int HighPart; }
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct DXGI_ADAPTER_DESC1 {
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)]
        public string Description;
        public uint VendorId;
        public uint DeviceId;
        public uint SubSysId;
        public uint Revision;
        public UIntPtr DedicatedVideoMemory;
        public UIntPtr DedicatedSystemMemory;
        public UIntPtr SharedSystemMemory;
        public LUID AdapterLuid;
        public uint Flags;
    }
    public sealed class AdapterEntry {
        public string Name { get; set; }
        public uint VendorId { get; set; }
        public uint DeviceId { get; set; }
        public ulong DedicatedBytes { get; set; }
        public ulong SharedBytes { get; set; }
    }
    [DllImport("dxgi.dll", ExactSpelling = true)]
    private static extern int CreateDXGIFactory1(ref Guid riid, out IntPtr factory);
    [UnmanagedFunctionPointer(CallingConvention.StdCall)]
    private delegate int EnumAdapters1Fn(IntPtr factory, uint index, out IntPtr adapter);
    [UnmanagedFunctionPointer(CallingConvention.StdCall)]
    private delegate int GetDesc1Fn(IntPtr adapter, out DXGI_ADAPTER_DESC1 desc);

    private static T Method<T>(IntPtr obj, int slot) where T : class {
        IntPtr vtable = Marshal.ReadIntPtr(obj);
        IntPtr method = Marshal.ReadIntPtr(vtable, slot * IntPtr.Size);
        return (T)(object)Marshal.GetDelegateForFunctionPointer(method, typeof(T));
    }
    public static AdapterEntry[] GetAdapters() {
        var result = new List<AdapterEntry>();
        if (IntPtr.Size != 8 || Marshal.SizeOf(typeof(DXGI_ADAPTER_DESC1)) != 312)
            return result.ToArray();
        IntPtr factory = IntPtr.Zero;
        Guid iid = IID_IDXGIFactory1;
        if (CreateDXGIFactory1(ref iid, out factory) != 0 || factory == IntPtr.Zero)
            return result.ToArray();
        try {
            var getAdapter = Method<EnumAdapters1Fn>(factory, 12);
            for (uint i = 0; i < 32; i++) {
                IntPtr adapter = IntPtr.Zero;
                int rc = getAdapter(factory, i, out adapter);
                if (rc != 0 || adapter == IntPtr.Zero) break;
                try {
                    var describe = Method<GetDesc1Fn>(adapter, 10);
                    DXGI_ADAPTER_DESC1 desc;
                    if (describe(adapter, out desc) != 0) continue;
                    if ((desc.Flags & 2) != 0) continue; // software renderer
                    result.Add(new AdapterEntry {
                        Name = desc.Description,
                        VendorId = desc.VendorId,
                        DeviceId = desc.DeviceId,
                        DedicatedBytes = desc.DedicatedVideoMemory.ToUInt64(),
                        SharedBytes = desc.SharedSystemMemory.ToUInt64()
                    });
                }
                finally { Marshal.Release(adapter); }
            }
        }
        finally { Marshal.Release(factory); }
        return result.ToArray();
    }
}
'@
        }
        return [InfoCatDxgi]::GetAdapters()
    }
    catch {
        return @()
    }
}

function Get-GpuRows {
    param([object[]]$Controllers)
    $adapters = @(Get-DxgiAdapters)
    $index = 0
    foreach ($controller in $Controllers) {
        if (-not $controller -or [string]::IsNullOrWhiteSpace([string]$controller.Name)) {
            continue
        }
        $index++
        $name = ([string]$controller.Name -replace '\s+', ' ').Trim()
        $value = $name
        $matched = $null
        $pnp = [string]$controller.PNPDeviceID
        if ($pnp -match '(?i)VEN_([0-9A-F]{4})&DEV_([0-9A-F]{4})') {
            $vendor = [Convert]::ToUInt32($Matches[1], 16)
            $deviceId = [Convert]::ToUInt32($Matches[2], 16)
            $matched = $adapters | Where-Object {
                $_.VendorId -eq $vendor -and $_.DeviceId -eq $deviceId
            } | Select-Object -First 1
        }
        if (-not $matched) {
            # GPU names can vary between WMI and DXGI (TM/R trademark notation).
            $key = ($name -replace '(?i)\(R\)|\(TM\)|[^a-z0-9]', '').ToLowerInvariant()
            $matched = $adapters | Where-Object {
                $other = (([string]$_.Name) -replace '(?i)\(R\)|\(TM\)|[^a-z0-9]', '').ToLowerInvariant()
                $key -eq $other
            } | Select-Object -First 1
        }
        if ($matched -and $matched.DedicatedBytes -gt 0) {
            # DXGI shared memory is an upper capacity, not VRAM or current usage.
            # Small local allocations (typical of iGPUs) must not imply that
            # this is the complete graphics memory available to the adapter.
            if ($matched.DedicatedBytes -le 512MB -and $matched.SharedBytes -ge 1GB) {
                $value = '{0} [{1} local, up to {2} shared]' -f $name, `
                    (Format-Bytes ([double]$matched.DedicatedBytes)), `
                    (Format-Bytes ([double]$matched.SharedBytes))
            }
            else {
                $value = '{0} [{1} dedicated]' -f $name, `
                    (Format-Bytes ([double]$matched.DedicatedBytes))
            }
        }
        [pscustomobject]@{
            Label = "GPU $index"
            Value = $value
            Kind = 'Normal'
        }
    }
}

# This queries the Windows default multimedia playback endpoint rather than
# grabbing an arbitrary Win32_SoundDevice instance (which may be HDMI audio).
function Get-DefaultPlaybackDevice {
    try {
        if (-not ('InfoCatAudioEndpoint' -as [type])) {
            Add-Type -ErrorAction Stop -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

[ComImport, Guid("BCDE0395-E52F-467C-8E3D-C4579291692E")]
public class InfoCatMMDeviceEnumeratorClass { }

[ComImport, Guid("A95664D2-9614-4F35-A746-DE8DB63617E6"),
 InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
public interface InfoCatIMMDeviceEnumerator {
    void EnumAudioEndpoints(int dataFlow, uint stateMask, out IntPtr devices);
    void GetDefaultAudioEndpoint(int dataFlow, int role, out InfoCatIMMDevice device);
    void GetDevice([MarshalAs(UnmanagedType.LPWStr)] string id, out InfoCatIMMDevice device);
    void RegisterEndpointNotificationCallback(IntPtr client);
    void UnregisterEndpointNotificationCallback(IntPtr client);
}

[ComImport, Guid("D666063F-1587-4E43-81F1-B948E807363F"),
 InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
public interface InfoCatIMMDevice {
    void Activate(ref Guid iid, uint clsCtx, IntPtr activationParams, out IntPtr iface);
    void OpenPropertyStore(uint stgmAccess, out InfoCatIPropertyStore properties);
    void GetId(out IntPtr id);
    void GetState(out uint state);
}

[StructLayout(LayoutKind.Sequential)]
public struct InfoCatPropertyKey { public Guid fmtid; public uint pid; }

[StructLayout(LayoutKind.Explicit)]
public struct InfoCatPropVariant {
    [FieldOffset(0)] public ushort variantType;
    [FieldOffset(8)] public IntPtr pointerValue;
}

[ComImport, Guid("886D8EEB-8CF2-4446-8D02-CDBA1DBDCF99"),
 InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
public interface InfoCatIPropertyStore {
    void GetCount(out uint count);
    void GetAt(uint index, out InfoCatPropertyKey key);
    void GetValue(ref InfoCatPropertyKey key, out InfoCatPropVariant value);
    void SetValue(ref InfoCatPropertyKey key, ref InfoCatPropVariant value);
    void Commit();
}

public static class InfoCatAudioEndpoint {
    [DllImport("ole32.dll")]
    private static extern int PropVariantClear(ref InfoCatPropVariant value);

    public static string GetDefaultName() {
        object obj = null;
        InfoCatIMMDevice device = null;
        InfoCatIPropertyStore properties = null;
        try {
            obj = new InfoCatMMDeviceEnumeratorClass();
            var enumerator = (InfoCatIMMDeviceEnumerator)obj;
            // eRender = 0, eMultimedia = 1
            enumerator.GetDefaultAudioEndpoint(0, 1, out device);
            if (device == null) return null;
            device.OpenPropertyStore(0, out properties); // STGM_READ
            if (properties == null) return null;
            var key = new InfoCatPropertyKey {
                fmtid = new Guid("A45C254E-DF1C-4EFD-8020-67D146A850E0"), pid = 14
            }; // PKEY_Device_FriendlyName
            InfoCatPropVariant value;
            properties.GetValue(ref key, out value);
            try {
                if (value.variantType == 31 && value.pointerValue != IntPtr.Zero)
                    return Marshal.PtrToStringUni(value.pointerValue);
                return null;
            }
            finally { PropVariantClear(ref value); }
        }
        finally {
            if (properties != null) Marshal.ReleaseComObject(properties);
            if (device != null) Marshal.ReleaseComObject(device);
            if (obj != null) Marshal.ReleaseComObject(obj);
        }
    }
}
'@
        }
        $name = [InfoCatAudioEndpoint]::GetDefaultName()
        if (-not [string]::IsNullOrWhiteSpace($name)) {
            return $name.Trim()
        }
        return 'Unavailable (default endpoint)'
    }
    catch {
        return 'Unavailable (default endpoint)'
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

# Validate individual registry values without enumerating other registry entries.
# Some Windows installations contain binary processor metadata that causes the
# Get-ItemProperty registry provider to throw while materializing the entire key.
# RawName must be a string; the MHz value is optional and is never a turbo claim.
function ConvertTo-InfoCatCpuRegistryValues {
    param(
        [AllowNull()][object]$RawName,
        [AllowNull()][object]$RawMHz
    )
    $name = $null
    $mhz = 0
    if ($RawName -is [string]) {
        $name = ($RawName -replace '\s+', ' ').Trim()
        if (-not $name) { $name = $null }
    }
    if ($RawMHz -is [int] -or $RawMHz -is [long] -or $RawMHz -is [uint32]) {
        $asLong = [long]$RawMHz
        if ($asLong -gt 0 -and $asLong -le 20000) { $mhz = [int]$asLong }
    }
    $details = if (-not $name) {
        'Registry CPU model missing or invalid'
    } elseif ($mhz -gt 0) {
        'Managed registry CPU model and ~MHz read'
    } else {
        'Managed registry CPU model read; ~MHz missing or invalid'
    }
    [pscustomobject]@{ Name = $name; MaxClockSpeed = $mhz; Details = $details }
}

# v1.8.3 read-only CPU collector. Keep verified native Windows topology and CIM
# fallback; read *only* the required processor registry values using .NET.
function Get-InfoCatCpuNative {
    param([switch]$Diagnostics)
    $report = [ordered]@{
        Usable = $false
        Name = $null
        NumberOfCores = 0
        NumberOfLogicalProcessors = 0
        MaxClockSpeed = 0
        Method = 'None'
        ApiDetails = 'Not attempted'
        RegistryDetails = 'Not attempted'
        Reason = 'Not evaluated'
    }
    try {
        if (-not ('InfoCatCpuTopologyV182' -as [type])) {
            Add-Type -ErrorAction Stop -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;

public sealed class InfoCatCpuProbeV182 {
    public int Cores { get; set; }
    public int Threads { get; set; }
    public string Method { get; set; }
    public string Details { get; set; }
}

public static class InfoCatCpuTopologyV182 {
    private const int InsufficientBuffer = 122;
    private const int MaxBytes = 4194304;

    [DllImport("kernel32.dll", EntryPoint="GetLogicalProcessorInformationEx", SetLastError=true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool GetLogicalProcessorInformationEx(
        int relationshipType, IntPtr buffer, ref int returnedLength);

    [DllImport("kernel32.dll", EntryPoint="GetActiveProcessorCount", SetLastError=true)]
    private static extern uint GetActiveProcessorCount(ushort groupNumber);

    [DllImport("kernel32.dll", EntryPoint="GetSystemCpuSetInformation", SetLastError=true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool GetSystemCpuSetInformation(
        IntPtr information, int bufferLength, out int returnedLength,
        IntPtr process, uint flags);

    // Each variable-size SYSTEM_LOGICAL_PROCESSOR_INFORMATION_EX record begins
    // with Relationship (DWORD) and Size (DWORD). RelationProcessorCore = 0.
    private static int ParseProcessorCoreRecords(IntPtr buffer, int bytes) {
        int offset = 0, cores = 0;
        while (offset < bytes) {
            if (bytes - offset < 8) return 0;
            int relation = Marshal.ReadInt32(buffer, offset);
            int size = Marshal.ReadInt32(buffer, offset + 4);
            if (size < 8 || size > bytes - offset) return 0;
            if (relation == 0) cores++;
            offset += size;
        }
        return offset == bytes ? cores : 0;
    }

    // CPU_SET_INFORMATION (Type=CpuSetInformation, 0):
    // Size@0, Type@4, Id@8, Group@12, LogicalProcessorIndex@14,
    // CoreIndex@15. Group + CoreIndex is a physical core identifier.
    private static int[] ParseCpuSetRecords(IntPtr buffer, int bytes) {
        var cores = new HashSet<string>(StringComparer.Ordinal);
        var logical = new HashSet<string>(StringComparer.Ordinal);
        int offset = 0;
        while (offset < bytes) {
            if (bytes - offset < 8) return new int[] {0, 0};
            int size = Marshal.ReadInt32(buffer, offset);
            int type = Marshal.ReadInt32(buffer, offset + 4);
            if (size < 8 || size > bytes - offset) return new int[] {0, 0};
            if (type == 0) {
                if (size < 20) return new int[] {0, 0};
                int group = (ushort)Marshal.ReadInt16(buffer, offset + 12);
                int logicalIndex = Marshal.ReadByte(buffer, offset + 14);
                int coreIndex = Marshal.ReadByte(buffer, offset + 15);
                cores.Add(group.ToString() + ":" + coreIndex.ToString());
                logical.Add(group.ToString() + ":" + logicalIndex.ToString());
            }
            offset += size;
        }
        if (offset != bytes) return new int[] {0, 0};
        return new int[] {cores.Count, logical.Count};
    }

    public static bool SelfTestRecordParsers() {
        // Three logical CPUs: two threads of one core, one of a second core.
        IntPtr cpuSets = Marshal.AllocHGlobal(3 * 32);
        IntPtr ex = Marshal.AllocHGlobal(2 * 16);
        try {
            for (int i = 0; i < 3; i++) {
                int o = i * 32;
                for (int b = 0; b < 32; b++) Marshal.WriteByte(cpuSets, o + b, 0);
                Marshal.WriteInt32(cpuSets, o, 32);
                Marshal.WriteInt32(cpuSets, o + 4, 0);
                Marshal.WriteInt16(cpuSets, o + 12, 0);
                Marshal.WriteByte(cpuSets, o + 14, (byte)i);
                Marshal.WriteByte(cpuSets, o + 15, (byte)(i == 2 ? 8 : 7));
            }
            for (int i = 0; i < 2; i++) {
                int o = i * 16;
                Marshal.WriteInt32(ex, o, 0);
                Marshal.WriteInt32(ex, o + 4, 16);
            }
            int[] parsed = ParseCpuSetRecords(cpuSets, 96);
            return parsed[0] == 2 && parsed[1] == 3 &&
                   ParseProcessorCoreRecords(ex, 32) == 2 &&
                   ParseProcessorCoreRecords(ex, 31) == 0 &&
                   ParseCpuSetRecords(cpuSets, 95)[0] == 0;
        }
        finally { Marshal.FreeHGlobal(cpuSets); Marshal.FreeHGlobal(ex); }
    }

    private static int ReadEx(out string detail) {
        detail = "";
        int length = 0;
        bool initial = GetLogicalProcessorInformationEx(0, IntPtr.Zero, ref length);
        int error = Marshal.GetLastWin32Error();
        if (initial || error != InsufficientBuffer || length < 8 || length > MaxBytes) {
            detail = "Core API size query: error=" + error + ", bytes=" + length;
            return 0;
        }
        for (int attempt = 0; attempt < 3; attempt++) {
            IntPtr buffer = Marshal.AllocHGlobal(length);
            try {
                int capacity = length;
                if (GetLogicalProcessorInformationEx(0, buffer, ref length)) {
                    int count = ParseProcessorCoreRecords(buffer, length);
                    detail = "Core API records=" + count + ", bytes=" + length;
                    return count;
                }
                error = Marshal.GetLastWin32Error();
                detail = "Core API read: error=" + error + ", bytes=" + length;
                if (error != InsufficientBuffer || length <= capacity || length > MaxBytes) return 0;
            }
            finally { Marshal.FreeHGlobal(buffer); }
        }
        return 0;
    }

    private static int[] ReadCpuSets(out string detail) {
        detail = "";
        int length;
        bool initial = GetSystemCpuSetInformation(IntPtr.Zero, 0, out length, IntPtr.Zero, 0);
        int error = Marshal.GetLastWin32Error();
        if (initial || error != InsufficientBuffer || length < 20 || length > MaxBytes) {
            detail = "CPU-set size query: error=" + error + ", bytes=" + length;
            return new int[] {0, 0};
        }
        for (int attempt = 0; attempt < 3; attempt++) {
            IntPtr buffer = Marshal.AllocHGlobal(length);
            try {
                int capacity = length;
                int written;
                if (GetSystemCpuSetInformation(buffer, capacity, out written, IntPtr.Zero, 0)) {
                    int[] parsed = ParseCpuSetRecords(buffer, written);
                    detail = "CPU-set records: cores=" + parsed[0] + ", logical=" + parsed[1];
                    return parsed;
                }
                error = Marshal.GetLastWin32Error();
                detail = "CPU-set read: error=" + error + ", bytes=" + written;
                if (error != InsufficientBuffer || written <= capacity || written > MaxBytes) return new int[] {0, 0};
                length = written;
            }
            finally { Marshal.FreeHGlobal(buffer); }
        }
        return new int[] {0, 0};
    }

    public static InfoCatCpuProbeV182 Probe() {
        var p = new InfoCatCpuProbeV182();
        p.Method = "None";
        int active = 0;
        try { active = (int)GetActiveProcessorCount(65535); }
        catch (Exception e) { p.Details = "Active processor count: " + e.GetType().Name; }
        string exDetail = "", setDetail = "";
        int exCores = 0;
        try { exCores = ReadEx(out exDetail); }
        catch (Exception e) { exDetail = "Core API exception: " + e.GetType().Name + " " + e.Message; }
        int[] sets = new int[] {0, 0};
        if (exCores <= 0 || active <= 0 || exCores > active) {
            try { sets = ReadCpuSets(out setDetail); }
            catch (Exception e) { setDetail = "CPU-set API exception: " + e.GetType().Name + " " + e.Message; }
        }
        int threads = active > 0 ? active : sets[1];
        if (exCores > 0 && threads >= exCores) {
            p.Cores = exCores; p.Threads = threads; p.Method = "GetLogicalProcessorInformationEx";
        } else if (sets[0] > 0 && threads >= sets[0] &&
                   (active <= 0 || sets[1] == active)) {
            p.Cores = sets[0]; p.Threads = threads; p.Method = "GetSystemCpuSetInformation";
        }
        p.Details = "Active logical=" + active + "; " + exDetail +
                    (setDetail.Length > 0 ? "; " + setDetail : "");
        return p;
    }
}
'@
        }
        $native = [InfoCatCpuTopologyV182]::Probe()
        $report.ApiDetails = [string]$native.Details
        $report.Method = [string]$native.Method
        $report.NumberOfCores = [int]$native.Cores
        $report.NumberOfLogicalProcessors = [int]$native.Threads
        $cpuRegKey = $null
        try {
            $cpuRegKey = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey(
                'HARDWARE\DESCRIPTION\System\CentralProcessor\0', $false
            )
            if ($null -eq $cpuRegKey) { throw 'Processor registry key is unavailable' }
            # GetValue reads only the requested entry; unlike Get-ItemProperty,
            # it never tries to coerce unrelated REG_BINARY values to integers.
            $registryInfo = ConvertTo-InfoCatCpuRegistryValues `
                -RawName ($cpuRegKey.GetValue('ProcessorNameString')) `
                -RawMHz ($cpuRegKey.GetValue('~MHz'))
            $report.Name = $registryInfo.Name
            $report.MaxClockSpeed = $registryInfo.MaxClockSpeed
            $report.RegistryDetails = $registryInfo.Details
        }
        catch {
            $report.RegistryDetails = ('Managed registry CPU read failed: {0}' -f $_.Exception.Message)
        }
        finally {
            if ($null -ne $cpuRegKey) { $cpuRegKey.Close() }
        }
        if ([string]::IsNullOrWhiteSpace($report.Name)) {
            $report.Reason = 'Registry CPU model missing'
        }
        elseif ($report.NumberOfCores -le 0 -or $report.NumberOfLogicalProcessors -lt $report.NumberOfCores) {
            $report.Reason = 'Native physical/logical CPU topology unavailable or inconsistent'
        }
        else {
            $report.Usable = $true
            $report.Reason = 'OK'
        }
    }
    catch {
        $report.Reason = ('Native CPU exception: {0}' -f $_.Exception.Message)
    }
    if ($Diagnostics) { return [pscustomobject]$report }
    if (-not $report.Usable) { return $null }
    [pscustomobject]@{
        Name = $report.Name
        NumberOfCores = $report.NumberOfCores
        NumberOfLogicalProcessors = $report.NumberOfLogicalProcessors
        MaxClockSpeed = $report.MaxClockSpeed
        InfoCatCpuSource = $report.Method
    }
}

# Return only confidently classified interfaces. If no physical LAN/Wi-Fi is
# available, fall back to the v1.7 NetAdapter collector rather than inventing
# a network label. Classify known VPN signatures before interface type because
# VPN drivers can present themselves as Ethernet adapters.
function Get-InfoCatInterfaceKind {
    param([string]$Alias, [string]$Description, [string]$InterfaceType)
    $signature = "$Alias $Description"
    if ($signature -match '(?i)proton|wireguard|wintun|openvpn|nordlynx|tailscale|zerotier|anyconnect|tunnel|tap-windows|\bvpn\b') {
        return 'VPN'
    }
    if ($signature -match '(?i)virtual|hyper-v|vEthernet|loopback|bluetooth|docker|vmware|virtualbox|npcap|container|pseudo') {
        return $null
    }
    if ($InterfaceType -eq 'Wireless80211') { return 'Wi-Fi' }
    if ($InterfaceType -in @('Ethernet', 'GigabitEthernet', 'FastEthernetFx', 'FastEthernetT')) {
        return 'LAN'
    }
    return $null
}

function Get-InfoCatNetworkRowsFast {
    $entries = [System.Collections.Generic.List[object]]::new()
    try {
        $nics = [System.Net.NetworkInformation.NetworkInterface]::GetAllNetworkInterfaces()
        foreach ($nic in $nics) {
            if ($nic.OperationalStatus -ne [System.Net.NetworkInformation.OperationalStatus]::Up) {
                continue
            }
            $kind = Get-InfoCatInterfaceKind -Alias ([string]$nic.Name) `
                -Description ([string]$nic.Description) `
                -InterfaceType ([string]$nic.NetworkInterfaceType)
            if (-not $kind) { continue }
            $props = $nic.GetIPProperties()
            $ipv4 = @($props.UnicastAddresses | Where-Object {
                $_.Address.AddressFamily -eq [System.Net.Sockets.AddressFamily]::InterNetwork -and
                -not [System.Net.IPAddress]::IsLoopback($_.Address) -and
                -not ([string]$_.Address).StartsWith('169.254.')
            } | Select-Object -First 1)
            if ($ipv4.Count -eq 0) { continue }
            $gateway = @($props.GatewayAddresses | Where-Object {
                $_.Address.AddressFamily -eq [System.Net.Sockets.AddressFamily]::InterNetwork -and
                -not $_.Address.Equals([System.Net.IPAddress]::Any)
            }).Count -gt 0
            $entries.Add([pscustomobject]@{
                Kind = $kind
                IP = [string]$ipv4[0].Address
                Alias = [string]$nic.Name
                GatewayRank = if ($gateway) { 0 } else { 1 }
            })
        }
    }
    catch { return @() }
    if (@($entries | Where-Object { $_.Kind -in @('LAN', 'Wi-Fi') }).Count -eq 0) {
        return @()
    }
    $rows = [System.Collections.Generic.List[object]]::new()
    foreach ($category in @('LAN', 'Wi-Fi', 'VPN')) {
        $selected = $entries | Where-Object { $_.Kind -eq $category } |
            Sort-Object GatewayRank, Alias | Select-Object -First 1
        if ($selected) {
            $rows.Add([pscustomobject]@{
                Label = $category
                Value = ('{0} ({1})' -f $selected.IP, $selected.Alias)
                Kind = 'Normal'
            })
        }
    }
    return $rows.ToArray()
}

# -----------------------------------------------------------------------------
# v1.7 Windows integration: native registry and Windows Terminal configuration.
# Every enrichment fails soft: a missing key or inaccessible settings.json must
# never stop the existing InfoCat collectors or create a Fastfetch dependency.
# -----------------------------------------------------------------------------
function Get-InfoCatWindowsThemeInfo {
    $result = [ordered]@{
        Name   = (Get-WindowsTheme)
        Mode   = $null
        Accent = $null
    }
    try {
        $current = Get-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes' `
            -Name CurrentTheme -ErrorAction Stop
        if (-not [string]::IsNullOrWhiteSpace([string]$current.CurrentTheme)) {
            $stem = [System.IO.Path]::GetFileNameWithoutExtension(
                [Environment]::ExpandEnvironmentVariables([string]$current.CurrentTheme))
            # Windows built-in resource names are not necessarily the visible
            # theme. Keep the v1.6.1 Dark/Light label for those cases.
            if ($stem -and $stem -notmatch '^(aero|aerolite|theme[0-9]*|custom)$') {
                $result.Name = $stem
            }
        }
    } catch { }
    try {
        $mode = Get-ItemProperty -Path `
            'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' -ErrorAction Stop
        $appMode = if ($null -ne $mode.AppsUseLightTheme) {
            if ([int]$mode.AppsUseLightTheme -eq 0) { 'Dark' } else { 'Light' }
        } else { $null }
        $systemMode = if ($null -ne $mode.SystemUsesLightTheme) {
            if ([int]$mode.SystemUsesLightTheme -eq 0) { 'Dark' } else { 'Light' }
        } else { $null }
        if ($appMode -and $systemMode) {
            $result.Mode = "System $systemMode / Apps $appMode"
        } elseif ($appMode) {
            $result.Mode = "Apps $appMode"
        } elseif ($systemMode) {
            $result.Mode = "System $systemMode"
        }
    } catch { }
    try {
        # DWM ColorizationColor uses ARGB; the last 24 bits are RGB.
        $dwm = Get-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\DWM' `
            -Name ColorizationColor -ErrorAction Stop
        if ($null -ne $dwm.ColorizationColor) {
            $rgb = [uint32]([long]$dwm.ColorizationColor -band 0xFFFFFF)
            $result.Accent = '#{0:X6}' -f $rgb
        }
    } catch { }
    return [pscustomobject]$result
}

function Get-InfoCatWindowsBuild {
    param([object]$OperatingSystem)
    $buildNumber = Get-FirstValue { $OperatingSystem.BuildNumber }
    $kernelVersion = Get-FirstValue { $OperatingSystem.Version }
    try {
        $buildKey = Get-ItemProperty -Path `
            'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -Name UBR -ErrorAction Stop
        $ubr = [int]$buildKey.UBR
        if ($ubr -ge 0 -and $ubr -le 999999 -and $buildNumber -match '^\d+$') {
            $buildNumber = "$buildNumber.$ubr"
            if ($kernelVersion -match '^\d+\.\d+\.\d+$') {
                $kernelVersion = "$kernelVersion.$ubr"
            }
        }
    } catch { }
    return [pscustomobject]@{ Build = $buildNumber; Kernel = $kernelVersion }
}

function Read-InfoCatJsonc {
    param([Parameter(Mandatory)][string]$Path)
    # Windows Terminal settings is JSON with comments and trailing commas.
    # Parse it as data; never execute or rewrite the settings file.
    $json = Get-Content -Raw -LiteralPath $Path -ErrorAction Stop
    $options = [System.Text.Json.JsonDocumentOptions]::new()
    $options.AllowTrailingCommas = $true
    $options.CommentHandling = [System.Text.Json.JsonCommentHandling]::Skip
    $document = [System.Text.Json.JsonDocument]::Parse($json, $options)
    try {
        # Re-emit valid JSON from the parsed DOM. The writer removes comments
        # and trailing commas without corrupting quoted strings or escapes.
        # Avoid JsonSerializer.Serialize(JsonElement): its generic overload is
        # not reliably bound by PowerShell 7 on Windows.
        $stream = [System.IO.MemoryStream]::new()
        try {
            $writerOptions = [System.Text.Json.JsonWriterOptions]::new()
            $writer = [System.Text.Json.Utf8JsonWriter]::new(
                [System.IO.Stream]$stream, $writerOptions
            )
            try {
                $document.RootElement.WriteTo($writer)
                $writer.Flush()
                $clean = [System.Text.Encoding]::UTF8.GetString($stream.ToArray())
                return ConvertFrom-Json -InputObject $clean -AsHashtable -Depth 100 -ErrorAction Stop
            }
            finally { $writer.Dispose() }
        }
        finally { $stream.Dispose() }
    }
    finally { $document.Dispose() }
}

function Get-InfoCatWindowsTerminalFont {
    if (-not $env:WT_SESSION -or -not $env:LOCALAPPDATA) { return $null }
    # WT_PROFILE_ID, when present, uniquely identifies the profile in use.
    # Without it we cannot assume that the configured default is active.
    $activeId = [string]$env:WT_PROFILE_ID
    if ([string]::IsNullOrWhiteSpace($activeId)) { return $null }
    $activeId = $activeId.Trim('{}')
    $candidates = @(
        'Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json',
        'Packages\Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe\LocalState\settings.json',
        'Microsoft\Windows Terminal\settings.json'
    )
    foreach ($relative in $candidates) {
        $path = Join-Path $env:LOCALAPPDATA $relative
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { continue }
        try {
            $settings = Read-InfoCatJsonc -Path $path
            if (-not $settings -or -not $settings['profiles']) { continue }
            $profiles = $settings['profiles']
            $list = @($profiles['list'])
            $active = $list | Where-Object {
                $_ -and $_['guid'] -and
                ([string]$_['guid']).Trim('{}') -ieq $activeId
            } | Select-Object -First 1
            if (-not $active) { continue }
            $defaults = $profiles['defaults']
            $profileFont = if ($active['font'] -is [System.Collections.IDictionary]) {
                $active['font']
            } else { @{} }
            $defaultFont = if ($defaults -and
                $defaults['font'] -is [System.Collections.IDictionary]) {
                $defaults['font']
            } else { @{} }
            $face = $null
            $size = $null
            $weight = $null
            foreach ($field in @('face', 'size', 'weight')) {
                $value = $null
                if ($profileFont.Contains($field)) { $value = $profileFont[$field] }
                elseif ($defaultFont.Contains($field)) { $value = $defaultFont[$field] }
                else {
                    $legacyKey = switch ($field) {
                        'face' { 'fontFace' }
                        'size' { 'fontSize' }
                        'weight' { 'fontWeight' }
                    }
                    if ($active.Contains($legacyKey)) { $value = $active[$legacyKey] }
                    elseif ($defaults -and $defaults.Contains($legacyKey)) {
                        $value = $defaults[$legacyKey]
                    }
                }
                switch ($field) {
                    'face' { $face = $value }
                    'size' { $size = $value }
                    'weight' { $weight = $value }
                }
            }
            if ([string]::IsNullOrWhiteSpace([string]$face)) { return $null }
            $details = [string]$face
            $sizePoints = 0.0
            if ($null -ne $size -and [double]::TryParse(
                [string]$size, [ref]$sizePoints) -and $sizePoints -gt 0) {
                $details += ' ({0:0.##}pt)' -f $sizePoints
            }
            if ($weight -and [string]$weight -notin @('normal', '400')) {
                $details += " [$weight]"
            }
            return $details
        } catch { continue }
    }
    return $null
}

function Get-InfoCatCpuPerformanceFrequency {
    # ProcessorFrequency is a Windows performance-provider snapshot; it is not
    # a guaranteed turbo ceiling or instantaneous per-core hardware reading.
    try {
        $counters = @(Get-CimInstance `
            -ClassName Win32_PerfFormattedData_Counters_ProcessorInformation `
            -Filter "Name='_Total'" -ErrorAction Stop)
        $entry = $counters | Select-Object -First 1
        if ($entry -and $null -ne $entry.ProcessorFrequency) {
            $mhz = [double]$entry.ProcessorFrequency
            if ($mhz -ge 100 -and $mhz -le 10000) {
                return '{0:0.00} GHz (Windows perf)' -f ($mhz / 1000)
            }
        }
    } catch { }
    return $null
}

function Get-InfoCatNetworkRows {
    param([string]$FallbackLAN)
    $entries = @()
    try {
        $configs = @(Get-NetIPConfiguration -All -ErrorAction Stop)
        $adapters = @(Get-NetAdapter -IncludeHidden -ErrorAction SilentlyContinue)
        foreach ($config in $configs) {
            if (-not $config.NetAdapter -or $config.NetAdapter.Status -ne 'Up') {
                continue
            }
            $ipv4 = @($config.IPv4Address) |
                Where-Object { $_ -and $_.IPAddress -and
                    $_.IPAddress -notlike '127.*' -and
                    $_.IPAddress -notlike '169.254.*' } |
                Select-Object -First 1
            if (-not $ipv4) { continue }
            $index = [int]$config.NetAdapter.ifIndex
            $adapter = $adapters | Where-Object { $_.ifIndex -eq $index } |
                Select-Object -First 1
            if (-not $adapter) {
                $adapter = Get-NetAdapter -InterfaceIndex $index -ErrorAction SilentlyContinue
            }
            $alias = [string]$config.InterfaceAlias
            $description = if ($adapter) { [string]$adapter.InterfaceDescription } else { '' }
            $signature = "$alias $description"
            $isVpn = $signature -match '(?i)proton|wireguard|wintun|openvpn|nordlynx|tailscale|zerotier|anyconnect|tunnel|tap-windows|\bvpn\b'
            $isPhysical = $adapter -and [bool]$adapter.HardwareInterface
            $isWifi = $isPhysical -and $signature -match '(?i)wi-?fi|wireless|802\.11|wlan'
            if ($isVpn) { $kind = 'VPN' }
            elseif ($isPhysical -and $isWifi) { $kind = 'Wi-Fi' }
            elseif ($isPhysical) { $kind = 'LAN' }
            else { continue }
            $metric = [int]::MaxValue
            if ($config.NetIPv4Interface -and
                $null -ne $config.NetIPv4Interface.InterfaceMetric) {
                $metric = [int]$config.NetIPv4Interface.InterfaceMetric
            }
            $gatewayRank = if ($config.IPv4DefaultGateway) { 0 } else { 1 }
            $entries += [pscustomobject]@{
                Kind = $kind; IP = [string]$ipv4.IPAddress
                Alias = $alias; Metric = $metric; GatewayRank = $gatewayRank
            }
        }
    } catch { }
    $rows = [System.Collections.Generic.List[object]]::new()
    foreach ($category in @('LAN', 'Wi-Fi', 'VPN')) {
        $selected = $entries | Where-Object Kind -eq $category |
            Sort-Object GatewayRank, Metric | Select-Object -First 1
        if ($selected) {
            $rows.Add([pscustomobject]@{
                Label = $category; Value = ('{0} ({1})' -f $selected.IP, $selected.Alias)
                Kind = 'Normal'
            })
        }
    }
    if (@($entries | Where-Object { $_.Kind -in 'LAN', 'Wi-Fi' }).Count -eq 0) {
        $rows.Insert(0, [pscustomobject]@{
            Label = 'LAN'; Value = $FallbackLAN; Kind = 'Normal'
        })
    }
    return $rows.ToArray()
}

# Probe timing is opt-in for display, but the wrapper is always lightweight.
# These are collection durations; they are NOT CPU/GPU performance benchmarks.
$script:InfoCatTimings = [ordered]@{}
$script:InfoCatRunTimer = [System.Diagnostics.Stopwatch]::StartNew()
function Invoke-InfoCatProbe {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][scriptblock]$Script
    )
    $timer = [System.Diagnostics.Stopwatch]::StartNew()
    try { & $Script }
    finally {
        $timer.Stop()
        if ($Timing) {
            $script:InfoCatTimings[$Name] = [Math]::Round($timer.Elapsed.TotalMilliseconds, 1)
        }
    }
}

# -----------------------------------------------------------------------------
# System snapshot
# -----------------------------------------------------------------------------
# Collect each CIM class once. Reusing these objects avoids repeated WMI/CIM
# round trips while the panel is being assembled.
$computerSystem = Invoke-InfoCatProbe 'CIM computer' {
    Get-CimInstance Win32_ComputerSystem -ErrorAction SilentlyContinue
}
$operatingSystem = Invoke-InfoCatProbe 'CIM OS' {
    Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
}
$processor = Invoke-InfoCatProbe 'CPU native' { Get-InfoCatCpuNative }
if (-not $processor) {
    $processor = Invoke-InfoCatProbe 'CIM CPU fallback' {
        Get-CimInstance Win32_Processor -ErrorAction SilentlyContinue |
            Select-Object -First 1
    }
}
$videoControllers = @(Invoke-InfoCatProbe 'CIM GPU' {
    Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue
})
$logicalDrives = @()
if (-not $Compact) {
    $logicalDrives = @(Invoke-InfoCatProbe 'CIM drives' {
        Get-CimInstance Win32_LogicalDisk -ErrorAction SilentlyContinue |
            Where-Object DeviceID |
            Sort-Object DeviceID
    })
}

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

$themeInfo = Invoke-InfoCatProbe 'Theme' { Get-InfoCatWindowsThemeInfo }
$theme = $themeInfo.Name
$terminalFont = $null
if (-not $Compact) {
    $terminalFont = Invoke-InfoCatProbe 'Terminal font' {
        Get-InfoCatWindowsTerminalFont
    }
}
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

$appCount = $null
$resolution = $null
if (-not $Compact) {
    $appCount = Invoke-InfoCatProbe 'Installed apps' { Get-InstalledAppCount }
    $resolution = Invoke-InfoCatProbe 'Resolution' { Get-ScreenResolution }
}

$osName = Get-FirstValue { $operatingSystem.Caption -replace '^Microsoft\s+', '' }
$buildInfo = Get-InfoCatWindowsBuild -OperatingSystem $operatingSystem
$build = $buildInfo.Build
$machine = Get-FirstValue { '{0} {1}' -f $computerSystem.Manufacturer.Trim(), $computerSystem.Model.Trim() }
$cpu = Get-FirstValue {
    $name = ($processor.Name -replace '\s+', ' ').Trim()
    '{0} / {1}C {2}T' -f $name, $processor.NumberOfCores, $processor.NumberOfLogicalProcessors
}

# CIM MaxClockSpeed or registry ~MHz are reported values, not reliable turbo
# ceilings, current clocks, or the processor's documented base frequency.
$cpuMaxClock = $null
try {
    if ($processor -and $processor.MaxClockSpeed -gt 0) {
        $clockSource = if ($processor.PSObject.Properties['InfoCatCpuSource']) {
            'registry ~MHz'
        } else { 'CIM reported' }
        $cpuMaxClock = '{0:0.00} GHz ({1})' -f `
            ([double]$processor.MaxClockSpeed / 1000), $clockSource
    }
}
catch { $cpuMaxClock = $null }

$gpu = Get-FirstValue {
    $names = $videoControllers |
        Where-Object Name |
        Select-Object -ExpandProperty Name -Unique
    (@($names) | Select-Object -First 2) -join ' + '
}

$audio = Invoke-InfoCatProbe 'Audio endpoint' { Get-DefaultPlaybackDevice }

$memory = Get-FirstValue {
    $totalBytes = [double]$operatingSystem.TotalVisibleMemorySize * 1KB
    $freeBytes = [double]$operatingSystem.FreePhysicalMemory * 1KB
    $usedBytes = $totalBytes - $freeBytes
    '{0} / {1}' -f (Format-Bytes $usedBytes), (Format-Bytes $totalBytes)
}

# Use the native multi-adapter collector first; avoid querying the same network
# interfaces twice unless Windows cannot identify a physical LAN or Wi-Fi.
$networkDetails = @(Invoke-InfoCatProbe 'Network native' {
    Get-InfoCatNetworkRowsFast
})
if ($networkDetails.Count -eq 0) {
    $networkDetails = @(Invoke-InfoCatProbe 'Network fallback' {
        Get-InfoCatNetworkRows -FallbackLAN 'Unavailable'
    })
}
foreach ($networkRow in $networkDetails) {
    if ($networkRow.Label -eq 'LAN' -and $networkRow.Value -eq 'Unavailable') {
        $networkRow.Value = Invoke-InfoCatProbe 'LAN fallback' {
            Get-PrimaryIPv4
        }
    }
}
$displayDetails = @()
if (-not $Compact) {
    $displayDetails = @(Invoke-InfoCatProbe 'Displays' { Get-DisplayDetails })
}
$gpuDetails = @(Invoke-InfoCatProbe 'GPU memory' {
    Get-GpuRows -Controllers $videoControllers
})
$battery = Invoke-InfoCatProbe 'Battery' { Get-BatterySummary }
$pagefile = $null
if (-not $Compact) {
    $pagefile = Invoke-InfoCatProbe 'Pagefile' { Get-PageFileSummary }
}
$kernel = $buildInfo.Kernel
$cpuPerfClock = $null
if (-not $Compact) {
    $cpuPerfClock = Invoke-InfoCatProbe 'CPU perf' {
        Get-InfoCatCpuPerformanceFrequency
    }
}

# Optional rows only appear when Windows exposes reliable information.
$optionalBattery = if ($battery) {
    [pscustomobject]@{ Label = 'Battery'; Value = $battery; Kind = 'Normal' }
}
$optionalCpuClock = if ($cpuMaxClock) {
    [pscustomobject]@{ Label = 'CPU Clock'; Value = $cpuMaxClock; Kind = 'Normal' }
}
$optionalThemeMode = if ($themeInfo.Mode) {
    [pscustomobject]@{ Label = 'Color Mode'; Value = $themeInfo.Mode; Kind = 'Normal' }
}
$optionalAccent = if ($themeInfo.Accent) {
    [pscustomobject]@{ Label = 'Accent'; Value = $themeInfo.Accent; Kind = 'Normal' }
}
$optionalTerminalFont = if ($terminalFont) {
    [pscustomobject]@{ Label = 'Term Font'; Value = $terminalFont; Kind = 'Normal' }
}
$optionalCpuPerfClock = if ($cpuPerfClock -and
    $cpuPerfClock -ne ($cpuMaxClock -replace '\s*\(CIM reported\)', ' (Windows perf)')) {
    [pscustomobject]@{ Label = 'CPU Perf'; Value = $cpuPerfClock; Kind = 'Normal' }
}
$optionalSwap = if ($pagefile) {
    [pscustomobject]@{ Label = 'Pagefile'; Value = $pagefile; Kind = 'Normal' }
}
$optionalDisplays = if ($displayDetails.Count -gt 0) {
    $displayDetails
} else {
    [pscustomobject]@{ Label = 'Resolution'; Value = $resolution; Kind = 'Normal' }
}
$optionalGpus = if ($gpuDetails.Count -gt 0) {
    $gpuDetails
} else {
    [pscustomobject]@{ Label = 'GPU'; Value = $gpu; Kind = 'Normal' }
}

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

if ($Compact) {
    $details = @(
        [pscustomobject]@{ Label = '';        Value = 'the cat';                Kind = 'Title' }
        [pscustomobject]@{ Label = '';        Value = '';                       Kind = 'Blank' }
        [pscustomobject]@{ Label = 'Time';    Value = "$timeNow - $dateNow";     Kind = 'Normal' }
        [pscustomobject]@{ Label = 'User';    Value = "$userName @ $hostName";   Kind = 'User' }
        [pscustomobject]@{ Label = '';        Value = '';                       Kind = 'Blank' }
        [pscustomobject]@{ Label = 'Theme';   Value = $theme;                   Kind = 'Normal' }
        [pscustomobject]@{ Label = 'Shell';   Value = $shell;                   Kind = 'Normal' }
        [pscustomobject]@{ Label = 'Uptime';  Value = $uptime;                  Kind = 'Normal' }
        [pscustomobject]@{ Label = 'OS';      Value = $osName;                  Kind = 'Normal' }
        [pscustomobject]@{ Label = 'Machine'; Value = $machine;                 Kind = 'Normal' }
        [pscustomobject]@{ Label = 'CPU';     Value = $cpu;                     Kind = 'Normal' }
        $optionalGpus
        [pscustomobject]@{ Label = 'Memory';  Value = $memory;                  Kind = 'Normal' }
        $optionalBattery
        $networkDetails
        [pscustomobject]@{ Label = '';        Value = '';                       Kind = 'Blank' }
        [pscustomobject]@{ Label = '';        Value = 'the cat';                Kind = 'Footer' }
    )
}
else {
    $details = @(
        [pscustomobject]@{ Label = '';            Value = 'the cat';                    Kind = 'Title' }
        [pscustomobject]@{ Label = '';            Value = '';                           Kind = 'Blank' }
        [pscustomobject]@{ Label = 'Time';        Value = "$timeNow - $dateNow";         Kind = 'Normal' }
        [pscustomobject]@{ Label = 'User';        Value = "$userName @ $hostName";       Kind = 'User' }
        [pscustomobject]@{ Label = '';            Value = '';                           Kind = 'Blank' }
        [pscustomobject]@{ Label = 'Theme';       Value = $theme;                       Kind = 'Normal' }
        $optionalThemeMode
        $optionalAccent
        [pscustomobject]@{ Label = 'Terminal';    Value = $terminal;                    Kind = 'Normal' }
        $optionalTerminalFont
        [pscustomobject]@{ Label = 'Shell';       Value = $shell;                       Kind = 'Normal' }
        [pscustomobject]@{ Label = 'Uptime';      Value = $uptime;                      Kind = 'Normal' }
        $driveDetails
        $opticalDetails
        [pscustomobject]@{ Label = 'Apps';        Value = "$appCount installed";         Kind = 'Normal' }
        $optionalDisplays
        [pscustomobject]@{ Label = 'OS';          Value = $osName;                      Kind = 'Normal' }
        [pscustomobject]@{ Label = 'Build';       Value = $build;                       Kind = 'Normal' }
        [pscustomobject]@{ Label = 'Kernel';      Value = $kernel;                      Kind = 'Normal' }
        [pscustomobject]@{ Label = 'Machine';     Value = $machine;                     Kind = 'Normal' }
        [pscustomobject]@{ Label = 'CPU';         Value = $cpu;                         Kind = 'Normal' }
        $optionalCpuClock
        $optionalCpuPerfClock
        $optionalGpus
        [pscustomobject]@{ Label = 'Audio';       Value = $audio;                       Kind = 'Normal' }
        [pscustomobject]@{ Label = 'Memory';      Value = $memory;                      Kind = 'Normal' }
        $optionalSwap
        $optionalBattery
        $networkDetails
        [pscustomobject]@{ Label = '';            Value = '';                           Kind = 'Blank' }
        [pscustomobject]@{ Label = '';            Value = 'the cat';                    Kind = 'Footer' }
    )

}

# -----------------------------------------------------------------------------
# Render
# -----------------------------------------------------------------------------
# No external layout engine: keep InfoCat's original artwork intact, but
# prevent a single long monitor/GPU row from overflowing the terminal width.
function Get-InfoCatTerminalWidth {
    try {
        $cols = [int]$Host.UI.RawUI.WindowSize.Width
        if ($cols -ge 24) { return $cols }
    }
    catch { }
    try {
        $cols = [int][Console]::WindowWidth
        if ($cols -ge 24) { return $cols }
    }
    catch { }
    return 120
}

function Get-InfoCatLayout {
    param([ValidateRange(24, 1000)][int]$TerminalWidth)
    $artColumn = 52
    $labelColumn = 14
    $stacked = $TerminalWidth -lt ($artColumn + $labelColumn + 22)
    $width = if ($stacked) {
        [Math]::Max(8, $TerminalWidth - $labelColumn - 1)
    } else {
        [Math]::Max(8, $TerminalWidth - $artColumn - $labelColumn - 1)
    }
    [pscustomobject]@{
        Stacked = $stacked
        ShowArt = $TerminalWidth -ge 45
        ValueWidth = [Math]::Min(1000, $width)
    }
}

function Split-InfoCatText {
    param(
        [AllowEmptyString()][string]$Text,
        [ValidateRange(8, 1000)][int]$Width
    )
    $result = [System.Collections.Generic.List[string]]::new()
    $remaining = $Text
    while ($remaining.Length -gt $Width) {
        $cut = $remaining.LastIndexOf(' ', $Width)
        if ($cut -le 0) { $cut = $Width }
        $result.Add($remaining.Substring(0, $cut).TrimEnd())
        $remaining = $remaining.Substring($cut).TrimStart()
    }
    $result.Add($remaining)
    return $result.ToArray()
}

function Expand-InfoCatRows {
    param([object[]]$Rows, [int]$ValueWidth)
    $expanded = [System.Collections.Generic.List[object]]::new()
    foreach ($row in $Rows) {
        if ($null -eq $row) { continue }
        if ($row.Kind -ne 'Normal') {
            $expanded.Add($row)
            continue
        }
        $lines = @(Split-InfoCatText -Text ([string]$row.Value) -Width $ValueWidth)
        $expanded.Add([pscustomobject]@{
            Label = $row.Label; Value = $lines[0]; Kind = 'Normal'
        })
        for ($j = 1; $j -lt $lines.Count; $j++) {
            $expanded.Add([pscustomobject]@{
                Label = ''; Value = $lines[$j]; Kind = 'Continuation'
            })
        }
    }
    return $expanded.ToArray()
}

function Write-InfoCatDetail {
    param([object]$Detail)
    if ($null -eq $Detail) { Write-Host ''; return }
    switch ($Detail.Kind) {
        { $_ -in 'Title', 'Footer' } {
            Write-Host "${White}the ${Blue}cat${Reset}"
        }
        'Blank' { Write-Host '' }
        'User' { Write-Host "${Cyan}$($Detail.Value)$Reset" }
        'Continuation' {
            Write-Host "${LabelColor}$(' ' * 12)  ${Blue}$($Detail.Value)$Reset"
        }
        default {
            $label = ([string]$Detail.Label).PadRight(12)
            Write-Host "${LabelColor}$label${White}» ${Blue}$($Detail.Value)$Reset"
        }
    }
}

# Two spaces + 50 columns of cat art; labels use 12 columns plus '» '.
$terminalWidth = Get-InfoCatTerminalWidth
$layout = Get-InfoCatLayout -TerminalWidth $terminalWidth
$rows = @(Expand-InfoCatRows -Rows $details -ValueWidth $layout.ValueWidth)

# In side-by-side Compact view, keep the footer below the *whole* original cat
# rather than halfway down its tail. Full and stacked layouts are unchanged.
if ($Compact -and -not $layout.Stacked -and $rows.Count -le $catArt.Count -and
    $rows.Count -gt 0 -and $rows[-1].Kind -eq 'Footer') {
    $footer = $rows[-1]
    $padded = [System.Collections.Generic.List[object]]::new()
    for ($i = 0; $i -lt ($rows.Count - 1); $i++) { $padded.Add($rows[$i]) }
    while ($padded.Count -le $catArt.Count) {
        $padded.Add([pscustomobject]@{ Label = ''; Value = ''; Kind = 'Blank' })
    }
    $padded.Add($footer)
    $rows = $padded.ToArray()
}

Write-Host ''
Write-Host $Bold -NoNewline

if ($layout.Stacked) {
    # On narrow widths, show the intact art above the data when it fits.
    # Below 45 columns, replace only the rendering with a short wordmark;
    # the original cat artwork data remains untouched.
    if ($layout.ShowArt) {
        for ($i = 0; $i -lt $catArt.Count; $i++) {
            $artColor = if ($i -ge 15) { $Gray } else { $White }
            Write-Host "${artColor}  $($catArt[$i])$Reset"
        }
    }
    else { Write-Host "${White}the ${Blue}cat$Reset" }
    Write-Host ''
    foreach ($detail in $rows) { Write-InfoCatDetail -Detail $detail }
}
else {
    $lineCount = [Math]::Max($catArt.Count, $rows.Count)
    for ($i = 0; $i -lt $lineCount; $i++) {
        $art = if ($i -lt $catArt.Count) { $catArt[$i] } else { '' }
        $detail = if ($i -lt $rows.Count) { $rows[$i] } else { $null }
        $artColor = if ($i -ge 15) { $Gray } else { $White }
        Write-Host -NoNewline "$artColor  $($art.PadRight(50))$Reset"
        Write-InfoCatDetail -Detail $detail
    }
}

Write-Host $Reset -NoNewline
Write-Host ''

if ($Timing) {
    $script:InfoCatRunTimer.Stop()
    Write-Host ''
    Write-Host "${White}InfoCat collection timings (${Blue}ms${White})$Reset"
    foreach ($name in $script:InfoCatTimings.Keys) {
        $elapsed = [double]$script:InfoCatTimings[$name]
        Write-Host ('  {0,-18} {1,8:N1} ms' -f $name, $elapsed)
    }
    Write-Host ('  {0,-18} {1,8:N1} ms' -f 'Total elapsed',
        $script:InfoCatRunTimer.Elapsed.TotalMilliseconds)
}
