#--------------------------------------------
# file:     systeminfo-menu.ps1
# author:   Mike Redd
# version:  2.1
# created:  2026-03-30
# updated:  2026-04-01
# desc:     System info dump | Full hardware, devices & performance snapshot
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

$ScriptName    = "System Info Dump"
$ScriptVersion = "2.1"
$ScriptAuthor  = "Mike Redd"

# ── Header Helper ─────────────────────────────────────────────
function Show-Header {
    Clear-UiScreen
    $w = Get-UiBoxWidth -MaxWidth 60 -MinWidth 44

    Write-UiHeader -Title $ScriptName -Subtitle "v$ScriptVersion  by $ScriptAuthor" -Width $w
    Write-UiRow "User" "$env:USERNAME@$env:COMPUTERNAME"
    Write-UiRow "Version" "v$ScriptVersion  by $ScriptAuthor" $global:UI_GRY
    Write-UiBlankLine
}

# ── Section Helper ────────────────────────────────────────────
function Section($icon, $title) {
    Write-UiBlankLine
    Write-Host "  $($global:UI_MAG)$($global:UI_B)$icon  $title$($global:UI_R)"
    Write-Host "  $($global:UI_GRY)  ----------------------------------------------------$($global:UI_R)"
}

# ── Row Helpers ───────────────────────────────────────────────
function Row($label, $value) {
    if ($value -and "$value" -ne "" -and "$value" -ne "Unknown") {
        $lbl = $label.PadRight(26)
        Write-Host "    $($global:UI_DIM)$($global:UI_WHT)$lbl$($global:UI_R)  $($global:UI_GRN)$value$($global:UI_R)"
    }
}

function RowWarn($label, $value) {
    $lbl = $label.PadRight(26)
    Write-Host "    $($global:UI_DIM)$($global:UI_WHT)$lbl$($global:UI_R)  $($global:UI_YLW)$value$($global:UI_R)"
}

function RowAlert($label, $value) {
    $lbl = $label.PadRight(26)
    Write-Host "    $($global:UI_DIM)$($global:UI_WHT)$lbl$($global:UI_R)  $($global:UI_RED)$value$($global:UI_R)"
}

# ── Divider Helper ────────────────────────────────────────────
function Divider {
    Write-Host "  $($global:UI_GRY)  ....................................................$($global:UI_R)"
}

# ── Usage Bar Helper ──────────────────────────────────────────
function MakeBar($pct, $len) {
    $filled = [Math]::Round($pct / 100 * $len)
    if ($filled -lt 0) { $filled = 0 }
    if ($filled -gt $len) { $filled = $len }
    $empty = $len - $filled
    $bc = if ($pct -ge 85) { $global:UI_RED } elseif ($pct -ge 60) { $global:UI_YLW } else { $global:UI_GRN }
    return "${bc}" + ("#" * $filled) + "$($global:UI_GRY)" + ("-" * $empty) + "$($global:UI_R)"
}

# ── Footer Helper ─────────────────────────────────────────────
function Footer {
    Write-UiBlankLine
    Write-Host "  $($global:UI_CYN)$($global:UI_B)+==============================================================+$($global:UI_R)"
    Write-Host "  $($global:UI_CYN)$($global:UI_B)|$($global:UI_R)  $($global:UI_GRY)Report complete.                                            $($global:UI_R)$($global:UI_CYN)$($global:UI_B)|$($global:UI_R)"
    Write-Host "  $($global:UI_CYN)$($global:UI_B)|$($global:UI_R)  $($global:UI_YLW)Tip: Run as Administrator for full device detail.            $($global:UI_R)$($global:UI_CYN)$($global:UI_B)|$($global:UI_R)"
    Write-Host "  $($global:UI_CYN)$($global:UI_B)+==============================================================+$($global:UI_R)"
    Write-UiBlankLine
}

# ── Pause ─────────────────────────────────────────────────────
function Pause-Script {
    Pause-Core "Press Enter to return to menu..."
}

# ── Main Menu ─────────────────────────────────────────────────
function Show-Menu {
    Show-Header
    $w = Get-UiBoxWidth -MaxWidth 60 -MinWidth 44
    Write-UiBoxTitle -Title "SELECT A SECTION" -Width $w

    Write-Host "  $($global:UI_GRN)$($global:UI_B)  A)$($global:UI_R)  Run Full Report (all sections)"
    Write-UiBlankLine
    Write-Host "  $($global:UI_YLW)     -- Individual Sections --$($global:UI_R)"
    Write-Host "  $($global:UI_GRN)  1)$($global:UI_R)  System Overview"
    Write-Host "  $($global:UI_GRN)  2)$($global:UI_R)  Processor (CPU)"
    Write-Host "  $($global:UI_GRN)  3)$($global:UI_R)  Memory (RAM)"
    Write-Host "  $($global:UI_GRN)  4)$($global:UI_R)  Storage"
    Write-Host "  $($global:UI_GRN)  5)$($global:UI_R)  Display Adapters (GPU)"
    Write-Host "  $($global:UI_GRN)  6)$($global:UI_R)  Monitors"
    Write-Host "  $($global:UI_GRN)  7)$($global:UI_R)  Audio Devices"
    Write-Host "  $($global:UI_GRN)  8)$($global:UI_R)  Input Devices (Keyboard / Mouse)"
    Write-Host "  $($global:UI_GRN)  9)$($global:UI_R)  USB & Connected Devices"
    Write-Host "  $($global:UI_GRN) 10)$($global:UI_R)  Bluetooth"
    Write-Host "  $($global:UI_GRN) 11)$($global:UI_R)  Network"
    Write-Host "  $($global:UI_GRN) 12)$($global:UI_R)  Battery"
    Write-Host "  $($global:UI_GRN) 13)$($global:UI_R)  Cameras"
    Write-Host "  $($global:UI_GRN) 14)$($global:UI_R)  Printers"
    Write-Host "  $($global:UI_GRN) 15)$($global:UI_R)  Performance Snapshot"
    Write-UiBlankLine
    Write-Host "  $($global:UI_RED)  Q)$($global:UI_R)  Quit"
    Write-UiBlankLine
}

# ── System Overview ───────────────────────────────────────────
function Show-SystemOverview {
    Show-Header
    $w = Get-UiBoxWidth -MaxWidth 60 -MinWidth 44
    Write-UiBoxTitle -Title "SYSTEM OVERVIEW" -Width $w
    try {
        $cs  = Get-CimInstance Win32_ComputerSystem
        $os  = Get-CimInstance Win32_OperatingSystem
        $bio = Get-CimInstance Win32_BIOS
        $enc = Get-CimInstance Win32_SystemEnclosure

        Section ">>" "MACHINE"
        Row "Hostname"            $env:COMPUTERNAME
        Row "Manufacturer"        $cs.Manufacturer
        Row "Model"               $cs.Model
        Row "System Type"         $cs.SystemType
        Row "Domain / Workgroup"  $(if ($cs.PartOfDomain) { $cs.Domain } else { "$($cs.Workgroup) (Workgroup)" })
        Row "Logged-in User"      "$($cs.UserName)"

        Divider
        Row "OS Name"             $os.Caption
        Row "OS Version"          $os.Version
        Row "Build Number"        $os.BuildNumber
        Row "OS Architecture"     $os.OSArchitecture
        Row "Install Date"        ($os.InstallDate).ToString("yyyy-MM-dd")
        Row "Last Boot"           ($os.LastBootUpTime).ToString("yyyy-MM-dd HH:mm:ss")
        $uptime = (Get-Date) - $os.LastBootUpTime
        Row "Uptime"              ("{0}d {1}h {2}m" -f $uptime.Days, $uptime.Hours, $uptime.Minutes)

        Divider
        Row "BIOS Manufacturer"   $bio.Manufacturer
        Row "BIOS Version"        $bio.SMBIOSBIOSVersion
        Row "BIOS Date"           ($bio.ReleaseDate).ToString("yyyy-MM-dd")
        Row "Serial Number"       $bio.SerialNumber

        $chassisType = switch ($enc.ChassisTypes[0]) {
            1  { "Other" }
            3  { "Desktop" }
            4  { "Low Profile Desktop" }
            8  { "Portable" }
            9  { "Laptop" }
            10 { "Notebook" }
            11 { "Hand Held" }
            12 { "Docking Station" }
            13 { "All in One" }
            14 { "Sub Notebook" }
            default { "Type $($enc.ChassisTypes[0])" }
        }
        Row "Chassis Type" $chassisType
    } catch {
		Write-CoreError "Could not retrieve system info: $($_)"
    }
}

# ── CPU ───────────────────────────────────────────────────────
function Show-CPU {
    Show-Header
    $w = Get-UiBoxWidth -MaxWidth 60 -MinWidth 44
    Write-UiBoxTitle -Title "PROCESSOR" -Width $w
    try {
        $cpus = Get-CimInstance Win32_Processor
        $i = 1
        foreach ($cpu in $cpus) {
            Section ">>" "CPU $i"
            Row "Name"             $cpu.Name.Trim()
            Row "Manufacturer"     $cpu.Manufacturer
            $arch = switch ($cpu.Architecture) {
                0 { "x86" }
                5 { "ARM" }
                6 { "ia64" }
                9 { "x64" }
                default { "Unknown" }
            }
            Row "Architecture"     $arch
            Row "Cores (Physical)" $cpu.NumberOfCores
            Row "Logical Procs"    $cpu.NumberOfLogicalProcessors
            Row "Base Speed"       "$($cpu.MaxClockSpeed) MHz"
            Row "L2 Cache"         "$($cpu.L2CacheSize) KB"
            Row "L3 Cache"         "$($cpu.L3CacheSize) KB"
            Row "Socket"           $cpu.SocketDesignation
            $load = $cpu.LoadPercentage
            $bar  = MakeBar $load 30
            Write-Host "    $($global:UI_DIM)$($global:UI_WHT)Current Load               $($global:UI_R)  [$bar] ${load}%$($global:UI_R)"
            $i++
        }
    } catch {
		Write-CoreError "Could not retrieve CPU info: $($_)"
    }
}

# ── Memory ────────────────────────────────────────────────────
function Show-Memory {
    Show-Header
    $w = Get-UiBoxWidth -MaxWidth 60 -MinWidth 44
    Write-UiBoxTitle -Title "MEMORY (RAM)" -Width $w
    try {
        $os2     = Get-CimInstance Win32_OperatingSystem
        $totGB   = [Math]::Round($os2.TotalVisibleMemorySize / 1MB, 2)
        $freeGB  = [Math]::Round($os2.FreePhysicalMemory / 1MB, 2)
        $usedGB  = [Math]::Round($totGB - $freeGB, 2)
        $usedPct = [Math]::Round(($usedGB / $totGB) * 100, 1)

        Section ">>" "OVERVIEW"
        Row "Total RAM" "${totGB} GB"
        Row "Used"      "${usedGB} GB  (${usedPct}%)"
        Row "Free"      "${freeGB} GB"
        $bar = MakeBar $usedPct 40
        Write-Host "    $($global:UI_DIM)$($global:UI_WHT)Usage                      $($global:UI_R)  [$bar] ${usedPct}%$($global:UI_R)"

        Divider
        $sticks = Get-CimInstance Win32_PhysicalMemory
        $n = 1
        foreach ($s in $sticks) {
            $gb = [Math]::Round($s.Capacity / 1GB, 1)
            $memType = switch ($s.SMBIOSMemoryType) {
                20 { "DDR" }
                21 { "DDR2" }
                24 { "DDR3" }
                26 { "DDR4" }
                34 { "DDR5" }
                default { "Unknown" }
            }
            Section ">>" "Slot $n  --  $($s.DeviceLocator)"
            Row "Capacity"     "${gb} GB"
            Row "Type"         $memType
            Row "Speed"        "$($s.Speed) MHz"
            Row "Manufacturer" $s.Manufacturer
            Row "Part Number"  $s.PartNumber.Trim()
            Row "Bank"         $s.BankLabel
            $n++
        }
    } catch {
		Write-CoreError "Could not retrieve memory info: $($_)"
    }
}

# ── Storage ───────────────────────────────────────────────────
function Show-Storage {
    Show-Header
    $w = Get-UiBoxWidth -MaxWidth 60 -MinWidth 44
    Write-UiBoxTitle -Title "STORAGE" -Width $w
    try {
        $disks = Get-CimInstance Win32_DiskDrive
        foreach ($disk in $disks) {
            $sizeGB = [Math]::Round($disk.Size / 1GB, 1)
            Section ">>" "$($disk.Caption)"
            Row "Disk Index" "Disk $($disk.Index)"
            Row "Size"       "${sizeGB} GB"
            Row "Interface"  $disk.InterfaceType
            Row "Media Type" $disk.MediaType
            Row "Serial"     $disk.SerialNumber.Trim()
            Row "Firmware"   $disk.FirmwareRevision
            Row "Partitions" $disk.Partitions

            $parts = Get-CimAssociatedInstance -InputObject $disk -ResultClassName Win32_DiskPartition -ErrorAction SilentlyContinue
            if (-not $parts) {
                $letters = Get-Partition -DiskNumber $disk.Index -ErrorAction SilentlyContinue | Where-Object { $_.DriveLetter }
                foreach ($ltr in $letters) {
                    $vol = Get-Volume -DriveLetter $ltr.DriveLetter -ErrorAction SilentlyContinue
                    if ($vol) {
                        $totV  = [Math]::Round($ltr.Size / 1GB, 1)
                        $freeV = [Math]::Round($vol.SizeRemaining / 1GB, 1)
                        $usedV = [Math]::Round($totV - $freeV, 1)
                        $pct   = if ($totV -gt 0) { [Math]::Round(($usedV / $totV) * 100, 1) } else { 0 }
                        $bar   = MakeBar $pct 30
                        Write-UiBlankLine
                        Write-Host "    $($global:UI_BLU)$($global:UI_B)  $($ltr.DriveLetter): $($vol.FileSystemLabel)$($global:UI_R)"
                        Row "  File System" $vol.FileSystem
                        Row "  Total" "${totV} GB"
                        Row "  Used" "${usedV} GB  (${pct}%)"
                        Row "  Free" "${freeV} GB"
                        Write-Host "    $($global:UI_DIM)$($global:UI_WHT)  Usage                    $($global:UI_R)  [$bar]"
                    }
                }
                continue
            }

            foreach ($part in $parts) {
                $vols = Get-CimAssociatedInstance -InputObject $part -ResultClassName Win32_LogicalDisk -ErrorAction SilentlyContinue
                foreach ($vol in $vols) {
                    $totV  = [Math]::Round($vol.Size / 1GB, 1)
                    $freeV = [Math]::Round($vol.FreeSpace / 1GB, 1)
                    $usedV = [Math]::Round($totV - $freeV, 1)
                    $pct   = if ($totV -gt 0) { [Math]::Round(($usedV / $totV) * 100, 1) } else { 0 }
                    $bar   = MakeBar $pct 30
                    Write-UiBlankLine
                    Write-Host "    $($global:UI_BLU)$($global:UI_B)  $($vol.DeviceID) $($vol.VolumeName)$($global:UI_R)"
                    Row "  File System" $vol.FileSystem
                    Row "  Total" "${totV} GB"
                    Row "  Used" "${usedV} GB  (${pct}%)"
                    Row "  Free" "${freeV} GB"
                    Write-Host "    $($global:UI_DIM)$($global:UI_WHT)  Usage                    $($global:UI_R)  [$bar]"
                }
            }
        }
    } catch {
		Write-CoreError "Could not retrieve storage info: $($_)"
    }
}

# ── GPU ───────────────────────────────────────────────────────
function Show-GPU {
    Show-Header
    $w = Get-UiBoxWidth -MaxWidth 60 -MinWidth 44
    Write-UiBoxTitle -Title "DISPLAY ADAPTERS" -Width $w
    try {
        $gpus = Get-CimInstance Win32_VideoController
        foreach ($gpu in $gpus) {
            Section ">>" "$($gpu.Caption)"
            Row "Name"           $gpu.Caption
            Row "Driver Version" $gpu.DriverVersion
            $ddate = if ($gpu.DriverDate) { ($gpu.DriverDate).ToString("yyyy-MM-dd") } else { "N/A" }
            Row "Driver Date"    $ddate
            $vram = if ($gpu.AdapterRAM -gt 0) { "$([Math]::Round($gpu.AdapterRAM/1GB,1)) GB" } else { "Shared/N/A" }
            Row "VRAM"           $vram
            Row "Resolution"     "$($gpu.CurrentHorizontalResolution) x $($gpu.CurrentVerticalResolution)"
            Row "Refresh Rate"   "$($gpu.CurrentRefreshRate) Hz"
            Row "Bit Depth"      "$($gpu.CurrentBitsPerPixel)-bit color"
            Row "Processor"      $gpu.VideoProcessor
        }
    } catch {
		Write-CoreError "Could not retrieve GPU info: $($_)"
    }
}

# ── Monitors ──────────────────────────────────────────────────
function Show-Monitors {
    Show-Header
    $w = Get-UiBoxWidth -MaxWidth 60 -MinWidth 44
    Write-UiBoxTitle -Title "MONITORS" -Width $w
    try {
        $monitors = Get-CimInstance -Namespace root\wmi -ClassName WmiMonitorID -ErrorAction Stop
        $i = 1
        foreach ($mon in $monitors) {
            Section ">>" "Monitor $i"
            $mfr = ($mon.ManufacturerName | Where-Object { $_ -ne 0 } | ForEach-Object { [char]$_ }) -join ""
            $prd = ($mon.ProductCodeID    | Where-Object { $_ -ne 0 } | ForEach-Object { [char]$_ }) -join ""
            $sn  = ($mon.SerialNumberID   | Where-Object { $_ -ne 0 } | ForEach-Object { [char]$_ }) -join ""
            $nm  = ($mon.UserFriendlyName | Where-Object { $_ -ne 0 } | ForEach-Object { [char]$_ }) -join ""
            Row "Friendly Name" $nm
            Row "Manufacturer" $mfr
            Row "Product Code"  $prd
            Row "Serial Number" $sn
            Row "Year of Mfr"   $mon.YearOfManufacture
            Row "Week of Mfr"   $mon.WeekOfManufacture
            $i++
        }

        try {
            $sizes = Get-CimInstance -Namespace root\wmi -ClassName WmiMonitorBasicDisplayParams -ErrorAction Stop
            $j = 1
            foreach ($sz in $sizes) {
                $wcm = $sz.MaxHorizontalImageSize
                $hcm = $sz.MaxVerticalImageSize
                if ($wcm -gt 0 -and $hcm -gt 0) {
                    $diag = [Math]::Round([Math]::Sqrt($wcm*$wcm + $hcm*$hcm) / 2.54, 1)
                    Write-Host "    $($global:UI_DIM)$($global:UI_WHT)Monitor $j Physical Size   $($global:UI_R)  $($global:UI_GRN)${wcm}cm x ${hcm}cm  (~${diag} inch diagonal)$($global:UI_R)"
                }
                $j++
            }
        } catch {}
    } catch {
        Write-Host "    $($global:UI_YLW)  WMI monitor data unavailable. Trying fallback...$($global:UI_R)"
        try {
            Add-Type -AssemblyName System.Windows.Forms -ErrorAction SilentlyContinue
            $screens = [System.Windows.Forms.Screen]::AllScreens
            $i = 1
            foreach ($scr in $screens) {
                Section ">>" "Screen $i"
                Row "Name" $scr.DeviceName
                Row "Primary" $scr.Primary
                Row "Resolution" "$($scr.Bounds.Width) x $($scr.Bounds.Height)"
                $i++
            }
        } catch {}
    }
}

# ── Audio ─────────────────────────────────────────────────────
function Show-Audio {
    Show-Header
    $w = Get-UiBoxWidth -MaxWidth 60 -MinWidth 44
    Write-UiBoxTitle -Title "AUDIO DEVICES" -Width $w
    try {
        $audio = Get-CimInstance Win32_SoundDevice
        foreach ($a in $audio) {
            Section ">>" "$($a.Name)"
            Row "Manufacturer" $a.Manufacturer
            Row "Status" $a.Status
            Row "Device ID" $a.DeviceID
        }

        $pnpAudio = Get-PnpDevice -Class AudioEndpoint -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq "OK" }
        if ($pnpAudio) {
            Divider
            Write-Host "    $($global:UI_BLU)$($global:UI_B)  Active Audio Endpoints:$($global:UI_R)"
            foreach ($ep in $pnpAudio) {
                Write-Host "    $($global:UI_GRN)  * $($ep.FriendlyName)$($global:UI_R)"
            }
        }
    } catch {
		Write-CoreError "Could not retrieve audio info: $($_)"
    }
}

# ── Input Devices ─────────────────────────────────────────────
function Show-Input {
    Show-Header
    $w = Get-UiBoxWidth -MaxWidth 60 -MinWidth 44
    Write-UiBoxTitle -Title "INPUT DEVICES" -Width $w

    Section ">>" "KEYBOARDS"
    try {
        $kbs = Get-PnpDevice -Class Keyboard -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq "OK" }
        if ($kbs) {
            foreach ($kb in $kbs) {
                Write-Host "    $($global:UI_GRN)  * $($kb.FriendlyName)$($global:UI_R)"
            }
        } else {
            $kbs2 = Get-CimInstance Win32_Keyboard
            foreach ($kb in $kbs2) { Row "Description" $kb.Description }
        }
    } catch {
		Write-CoreError "Could not retrieve keyboard info: $($_)"
    }

    Section ">>" "MICE / POINTING DEVICES"
    try {
        $mice = Get-PnpDevice -Class Mouse -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq "OK" }
        if ($mice) {
            foreach ($m in $mice) {
                Write-Host "    $($global:UI_GRN)  * $($m.FriendlyName)$($global:UI_R)"
            }
        } else {
            $mice2 = Get-CimInstance Win32_PointingDevice
            foreach ($m in $mice2) { Row "Name" $m.Name }
        }
    } catch {
		Write-CoreError "Could not retrieve mouse info: $($_)"
    }
}

# ── USB Devices ───────────────────────────────────────────────
function Show-USB {
    Show-Header
    $w = Get-UiBoxWidth -MaxWidth 60 -MinWidth 44
    Write-UiBoxTitle -Title "USB & CONNECTED DEVICES" -Width $w
    try {
        Section ">>" "USB CONTROLLERS"
        $usb = Get-CimInstance Win32_USBController
        foreach ($u in $usb) {
            Write-Host "    $($global:UI_GRN)  * $($u.Name)$($global:UI_R)  $($global:UI_GRY)[Status: $($u.Status)]$($global:UI_R)"
        }

        Divider
        Section ">>" "USB CONNECTED DEVICES"
        $usbDev = Get-PnpDevice | Where-Object {
            $_.InstanceId -like "USB\*" -and $_.Status -eq "OK" -and
            $_.FriendlyName -notmatch "Hub|Root|Composite|Generic"
        } | Sort-Object FriendlyName | Select-Object -Unique FriendlyName

        if ($usbDev) {
            foreach ($d in $usbDev) {
                Write-Host "    $($global:UI_GRN)  * $($d.FriendlyName)$($global:UI_R)"
            }
        } else {
            Write-Host "    $($global:UI_GRY)  No extra USB devices found (try running as Admin).$($global:UI_R)"
        }
    } catch {
		Write-CoreError "Could not retrieve USB info: $($_)"
    }
}

# ── Bluetooth ─────────────────────────────────────────────────
function Show-Bluetooth {
    Show-Header
    $w = Get-UiBoxWidth -MaxWidth 60 -MinWidth 44
    Write-UiBoxTitle -Title "BLUETOOTH" -Width $w
    try {
        $bt = Get-PnpDevice -Class Bluetooth -ErrorAction SilentlyContinue
        if ($bt) {
            Section ">>" "BLUETOOTH DEVICES"
            foreach ($b in $bt) {
                $sc = if ($b.Status -eq "OK") { $global:UI_GRN } else { $global:UI_YLW }
                Write-Host "    ${sc}  * $($b.FriendlyName)$($global:UI_R)  $($global:UI_GRY)[$($b.Status)]$($global:UI_R)"
            }
        } else {
            Write-Host "    $($global:UI_GRY)  No Bluetooth devices found.$($global:UI_R)"
        }
    } catch {
        Write-Host "    $($global:UI_YLW)  Bluetooth query may need Admin.$($global:UI_R)"
    }
}

# ── Network ───────────────────────────────────────────────────
function Show-Network {
    Show-Header
    $w = Get-UiBoxWidth -MaxWidth 60 -MinWidth 44
    Write-UiBoxTitle -Title "NETWORK" -Width $w
    try {
        $nics = Get-CimInstance Win32_NetworkAdapterConfiguration | Where-Object { $_.IPEnabled -eq $true }
        foreach ($nic in $nics) {
            Section ">>" "$($nic.Description)"
            Row "MAC Address"     $nic.MACAddress
            $ipv4 = $nic.IPAddress | Where-Object { $_ -match '^\d+\.\d+\.\d+\.\d+$' } | Select-Object -First 1
            $ipv6 = $nic.IPAddress | Where-Object { $_ -match ':' } | Select-Object -First 1
            Row "IPv4 Address"    $ipv4
            Row "IPv6 Address"    $ipv6
            Row "Subnet Mask"     ($nic.IPSubnet | Select-Object -First 1)
            Row "Default Gateway" ($nic.DefaultIPGateway | Select-Object -First 1)
            Row "DNS Servers"     ($nic.DNSServerSearchOrder -join ", ")
            Row "DHCP Enabled"    $nic.DHCPEnabled
            Row "DHCP Server"     $nic.DHCPServer
        }

        try {
            $wifi = netsh wlan show interfaces 2>$null
            if ($wifi -match "SSID") {
                Divider
                Write-Host "    $($global:UI_BLU)$($global:UI_B)  Wi-Fi Details:$($global:UI_R)"
                $wifi | Where-Object { $_ -match "^\s+(SSID|Signal|Radio type|Authentication|Channel)\s+:" } | ForEach-Object {
                    $parts = $_ -split ":", 2
                    if ($parts.Count -eq 2) {
                        Row $parts[0].Trim() $parts[1].Trim()
                    }
                }
            }
        } catch {}
    } catch {
		Write-CoreError "Could not retrieve network info: $($_)"
    }
}

# ── Battery ───────────────────────────────────────────────────
function Show-Battery {
    Show-Header
    $w = Get-UiBoxWidth -MaxWidth 60 -MinWidth 44
    Write-UiBoxTitle -Title "BATTERY" -Width $w
    try {
        $bat = Get-CimInstance Win32_Battery
        if ($bat) {
            foreach ($b in $bat) {
                Section ">>" "Battery"
                Row "Name" $b.Name
                $pct = $b.EstimatedChargeRemaining
                $bar = MakeBar $pct 40
                Write-Host "    $($global:UI_DIM)$($global:UI_WHT)Charge Level               $($global:UI_R)  [$bar] ${pct}%$($global:UI_R)"
                $status = switch ($b.BatteryStatus) {
                    1  { "Discharging" }
                    2  { "AC Power" }
                    3  { "Fully Charged" }
                    4  { "Low" }
                    5  { "Critical" }
                    6  { "Charging" }
                    11 { "Partially Charged" }
                    default { "Unknown" }
                }
                if ($b.BatteryStatus -in 4,5) { RowAlert "Status" $status }
                elseif ($b.BatteryStatus -eq 1) { RowWarn "Status" $status }
                else { Row "Status" $status }
                Row "Est. Runtime" "$($b.EstimatedRunTime) min"
                Row "Voltage"      "$($b.DesignVoltage) mV"
                $chem = switch ($b.Chemistry) {
                    3 { "Lead Acid" }
                    4 { "NiCd" }
                    5 { "NiMH" }
                    6 { "Lithium-ion" }
                    8 { "LiPo" }
                    default { "Unknown" }
                }
                Row "Chemistry" $chem
            }

            try {
                $null = powercfg /batteryreport /output "$env:TEMP\battreport.xml" /XML 2>$null
                if (Test-Path "$env:TEMP\battreport.xml") {
                    [xml]$rep = Get-Content "$env:TEMP\battreport.xml"
                    $bi = $rep.BatteryReport.Batteries.Battery | Select-Object -First 1
                    if ($bi) {
                        Divider
                        Row "Design Capacity" "$($bi.DesignCapacity) mWh"
                        Row "Full Charge Cap" "$($bi.FullChargeCapacity) mWh"
                        if ([int]$bi.DesignCapacity -gt 0) {
                            $health = [Math]::Round(([int]$bi.FullChargeCapacity / [int]$bi.DesignCapacity) * 100, 1)
                            $hc = if ($health -ge 80) { $global:UI_GRN } elseif ($health -ge 50) { $global:UI_YLW } else { $global:UI_RED }
                            Write-Host "    $($global:UI_DIM)$($global:UI_WHT)Battery Health             $($global:UI_R)  ${hc}$($global:UI_B)${health}% of original capacity$($global:UI_R)"
                        }
                        Row "Cycle Count" $bi.CycleCount
                    }
                    Remove-Item "$env:TEMP\battreport.xml" -Force -ErrorAction SilentlyContinue
                }
            } catch {}
        } else {
            Write-Host "    $($global:UI_GRY)  No battery detected (desktop or VM).$($global:UI_R)"
        }
    } catch {
		Write-CoreError "Could not retrieve battery info: $($_)"
    }
}

# ── Cameras ───────────────────────────────────────────────────
function Show-Cameras {
    Show-Header
    $w = Get-UiBoxWidth -MaxWidth 60 -MinWidth 44
    Write-UiBoxTitle -Title "CAMERAS" -Width $w
    try {
        $cams = Get-PnpDevice -Class Camera -ErrorAction SilentlyContinue
        if (-not $cams -or $cams.Count -eq 0) {
            $cams = Get-PnpDevice -Class Image -ErrorAction SilentlyContinue
        }
        if ($cams) {
            Section ">>" "CAMERAS & IMAGING"
            foreach ($c in $cams) {
                $sc = if ($c.Status -eq "OK") { $global:UI_GRN } else { $global:UI_YLW }
                Write-Host "    ${sc}  * $($c.FriendlyName)$($global:UI_R)  $($global:UI_GRY)[$($c.Status)]$($global:UI_R)"
            }
        } else {
            Write-Host "    $($global:UI_GRY)  No cameras detected.$($global:UI_R)"
        }
    } catch {
        Write-Host "    $($global:UI_GRY)  Camera query unavailable.$($global:UI_R)"
    }
}

# ── Printers ──────────────────────────────────────────────────
function Show-Printers {
    Show-Header
    $w = Get-UiBoxWidth -MaxWidth 60 -MinWidth 44
    Write-UiBoxTitle -Title "PRINTERS" -Width $w
    try {
        $printers = Get-CimInstance Win32_Printer
        if ($printers) {
            Section ">>" "INSTALLED PRINTERS"
            foreach ($p in $printers) {
                $def = if ($p.Default) { "$($global:UI_YLW)[DEFAULT]  $($global:UI_R)" } else { "" }
                Write-Host "    $($global:UI_GRN)  * $($p.Name)$($global:UI_R)  $def$($global:UI_GRY)[$($p.PortName)]$($global:UI_R)"
                Row "  Driver" $p.DriverName
                Row "  Network" $p.Network
            }
        } else {
            Write-Host "    $($global:UI_GRY)  No printers installed.$($global:UI_R)"
        }
    } catch {
        Write-Host "    $($global:UI_GRY)  Printer query unavailable.$($global:UI_R)"
    }
}

# ── Performance Snapshot ──────────────────────────────────────
function Show-Performance {
    Show-Header
    $w = Get-UiBoxWidth -MaxWidth 60 -MinWidth 44
    Write-UiBoxTitle -Title "PERFORMANCE SNAPSHOT" -Width $w
    try {
        Section ">>" "LIVE METRICS"
        $cpuLoad = (Get-CimInstance Win32_Processor | Measure-Object -Property LoadPercentage -Average).Average
        $bar = MakeBar $cpuLoad 40
        Write-Host "    $($global:UI_DIM)$($global:UI_WHT)CPU Usage                  $($global:UI_R)  [$bar] ${cpuLoad}%$($global:UI_R)"

        $os3    = Get-CimInstance Win32_OperatingSystem
        $totGB  = [Math]::Round($os3.TotalVisibleMemorySize / 1MB, 2)
        $freeGB = [Math]::Round($os3.FreePhysicalMemory / 1MB, 2)
        $ramPct = [Math]::Round((($totGB - $freeGB) / $totGB) * 100, 1)
        $bar    = MakeBar $ramPct 40
        Write-Host "    $($global:UI_DIM)$($global:UI_WHT)RAM Usage                  $($global:UI_R)  [$bar] ${ramPct}%$($global:UI_R)"

        Divider
        Write-Host "    $($global:UI_BLU)$($global:UI_B)  Top 5 Processes by CPU Time:$($global:UI_R)"
        Get-Process | Sort-Object CPU -Descending | Select-Object -First 5 | ForEach-Object {
            $cpuS  = [Math]::Round($_.CPU, 1)
            $memMB = [Math]::Round($_.WorkingSet64 / 1MB, 1)
            $name  = $_.ProcessName.PadRight(25)
            Write-Host "    $($global:UI_GRN)  $name$($global:UI_R)  CPU: $($global:UI_YLW)${cpuS}s$($global:UI_R)   RAM: $($global:UI_CYN)${memMB} MB$($global:UI_R)"
        }
    } catch {
		Write-CoreError "Could not retrieve performance info: $($_)"
    }
}

# ── Full Report Runner ────────────────────────────────────────
function Show-All {
    Show-SystemOverview
    Show-CPU
    Show-Memory
    Show-Storage
    Show-GPU
    Show-Monitors
    Show-Audio
    Show-Input
    Show-USB
    Show-Bluetooth
    Show-Network
    Show-Battery
    Show-Cameras
    Show-Printers
    Show-Performance
    Footer
}

# ── Main Loop ─────────────────────────────────────────────────
while ($true) {
    Show-Menu
    $choice = (Read-UiChoice "Choice:").Trim().ToUpper()

    switch ($choice) {
        "A"  { Show-All; Footer; Pause-Script }
        "1"  { Show-SystemOverview; Footer; Pause-Script }
        "2"  { Show-CPU; Footer; Pause-Script }
        "3"  { Show-Memory; Footer; Pause-Script }
        "4"  { Show-Storage; Footer; Pause-Script }
        "5"  { Show-GPU; Footer; Pause-Script }
        "6"  { Show-Monitors; Footer; Pause-Script }
        "7"  { Show-Audio; Footer; Pause-Script }
        "8"  { Show-Input; Footer; Pause-Script }
        "9"  { Show-USB; Footer; Pause-Script }
        "10" { Show-Bluetooth; Footer; Pause-Script }
        "11" { Show-Network; Footer; Pause-Script }
        "12" { Show-Battery; Footer; Pause-Script }
        "13" { Show-Cameras; Footer; Pause-Script }
        "14" { Show-Printers; Footer; Pause-Script }
        "15" { Show-Performance; Footer; Pause-Script }

        "Q"  {
            Write-UiBlankLine
            Write-Host "  $($global:UI_CYN)  Goodbye.$($global:UI_R)"
            Write-UiBlankLine
            return
        }

        default {
            Write-CoreError "Invalid choice."
            Start-Sleep -Seconds 1
        }
    }
}