#--------------------------------------------
# file:     disk-menu.ps1
# author:   Mike Redd
# version:  2.4
# created:  2026-03-30
# updated:  2026-04-19
# desc:     Disk and cleanup utility
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

$ScriptName    = "Disk Menu"
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
    Write-UiSection "Disk Tools"

    Write-Host "  $($global:UI_Theme.Accent)  1)$($global:UI_Theme.Reset)  Show drive usage"
    Write-Host "  $($global:UI_Theme.Accent)  2)$($global:UI_Theme.Reset)  Show largest folders in a path"
    Write-Host "  $($global:UI_Theme.Accent)  3)$($global:UI_Theme.Reset)  Show largest files in a path"
    Write-Host "  $($global:UI_Theme.Accent)  4)$($global:UI_Theme.Reset)  Show 20 biggest files on system drive"
    Write-Host "  $($global:UI_Theme.Accent)  5)$($global:UI_Theme.Reset)  Show 20 biggest files on system drive (quiet scan)"
    Write-Host "  $($global:UI_Theme.Warning)  6)$($global:UI_Theme.Reset)  Clean user temp files"
    Write-Host "  $($global:UI_Theme.Warning)  7)$($global:UI_Theme.Reset)  Clean Windows temp files"
    Write-Host "  $($global:UI_Theme.Error)  8)$($global:UI_Theme.Reset)  Empty recycle bin"
    Write-Host "  $($global:UI_Theme.Info)  9)$($global:UI_Theme.Reset)  Export drive usage to CSV"

    Write-UiDivider
    Write-Host "  $($global:UI_Theme.Muted)  Q)$($global:UI_Theme.Reset)  Quit"
    Write-UiBlankLine
}

# ── Pause ─────────────────────────────────────────────────────
function Pause-Script {
    Pause-Core "Press Enter to return to menu..."
}

# ── Confirm ───────────────────────────────────────────────────
function Confirm-Action {
    param([string]$Message)
    return (Confirm-Core $Message)
}

# ── Format bytes ──────────────────────────────────────────────
function Format-Bytes($bytes) {
    if ($bytes -ge 1GB) { return "{0:N2} GB" -f ($bytes / 1GB) }
    if ($bytes -ge 1MB) { return "{0:N2} MB" -f ($bytes / 1MB) }
    if ($bytes -ge 1KB) { return "{0:N2} KB" -f ($bytes / 1KB) }
    return "$bytes B"
}

# ── Usage bar ─────────────────────────────────────────────────
function MakeBar($pct, $len = 25) {
    $filled = [Math]::Min($len, [Math]::Round($pct / 100 * $len))
    $empty  = $len - $filled
    $bc     = if ($pct -ge 90) { $global:UI_Theme.Error } elseif ($pct -ge 70) { $global:UI_Theme.Warning } else { $global:UI_Theme.Success }
    return "${bc}" + ("#" * $filled) + "$($global:UI_Theme.Muted)" + ("-" * $empty) + "$($global:UI_Theme.Reset)"
}

# ── Folder size helper ────────────────────────────────────────
function Get-FolderSizeBytes($path) {
    try {
        $sum = (Get-ChildItem -LiteralPath $path -Force -Recurse -ErrorAction SilentlyContinue |
            Where-Object { -not $_.PSIsContainer } |
            Measure-Object -Property Length -Sum).Sum
        if ($null -eq $sum) { return 0 }
        return [double]$sum
    } catch {
        return 0
    }
}

# ── 1 — Drive Usage ───────────────────────────────────────────
function Show-DriveUsage {
    Show-Header
    $w = Get-UiBoxWidth -MaxWidth 52 -MinWidth 40
    Write-UiBoxTitle -Title "DRIVE USAGE" -Width $w
    try {
        Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3" | ForEach-Object {
            $totalGB = [Math]::Round($_.Size / 1GB, 2)
            $freeGB  = [Math]::Round($_.FreeSpace / 1GB, 2)
            $usedGB  = [Math]::Round($totalGB - $freeGB, 2)
            $pct     = if ($totalGB -gt 0) { [Math]::Round(($usedGB / $totalGB) * 100, 1) } else { 0 }
            $bar     = MakeBar $pct

            $usedColor = if ($pct -ge 90) { $global:UI_Theme.Error } elseif ($pct -ge 70) { $global:UI_Theme.Warning } else { $global:UI_Theme.Success }

            Write-Host "  $($global:UI_Theme.Secondary)$($global:UI_Theme.Bold)  $($_.DeviceID)  $($_.VolumeName)$($global:UI_Theme.Reset)  $($global:UI_Theme.Muted)[$($_.FileSystem)]$($global:UI_Theme.Reset)"
            Write-Host "  $($global:UI_Theme.Muted)  ----------------------------------------------------$($global:UI_Theme.Reset)"
            Write-Host "  $($global:UI_Theme.Dim)$($global:UI_Theme.Text)  $("Used".PadRight(10))$($global:UI_Theme.Reset)  ${usedColor}$usedGB GB  ($pct%)$($global:UI_Theme.Reset)"
            Write-Host "  $($global:UI_Theme.Dim)$($global:UI_Theme.Text)  $("Free".PadRight(10))$($global:UI_Theme.Reset)  $($global:UI_Theme.Success)$freeGB GB$($global:UI_Theme.Reset)"
            Write-Host "  $($global:UI_Theme.Dim)$($global:UI_Theme.Text)  $("Total".PadRight(10))$($global:UI_Theme.Reset)  $($global:UI_Theme.Muted)$totalGB GB$($global:UI_Theme.Reset)"
            Write-Host "  $($global:UI_Theme.Dim)$($global:UI_Theme.Text)  $("Usage".PadRight(10))$($global:UI_Theme.Reset)  [$bar] ${usedColor}$pct%$($global:UI_Theme.Reset)"
            Write-UiBlankLine
        }
    } catch {
        Write-CoreError "Failed: $($_.Exception.Message)"
    }
}

# ── 2 — Largest Folders ───────────────────────────────────────
function Show-LargestFolders {
    Show-Header
    $w = Get-UiBoxWidth -MaxWidth 52 -MinWidth 40
    Write-UiBoxTitle -Title "LARGEST FOLDERS" -Width $w
    Write-Host -NoNewline "  $($global:UI_Theme.Warning)  Path (default C:\): $($global:UI_Theme.Reset)"
    $targetPath = Read-Host
    if (-not $targetPath) { $targetPath = "C:\" }

    if (-not (Test-Path -LiteralPath $targetPath)) {
        Write-CoreError "Path not found: $targetPath"
        return
    }

    Write-UiBlankLine
    Write-Host "  $($global:UI_Theme.Info)  Scanning top-level folders in: $targetPath$($global:UI_Theme.Reset)"
    Write-Host "  $($global:UI_Theme.Muted)  This may take a moment...$($global:UI_Theme.Reset)"
    Write-UiBlankLine

    try {
        $results = Get-ChildItem -LiteralPath $targetPath -Force -Directory -ErrorAction SilentlyContinue |
            ForEach-Object {
                $sizeBytes = Get-FolderSizeBytes $_.FullName
                [PSCustomObject]@{ Folder = $_.FullName; Size = $sizeBytes }
            } | Sort-Object Size -Descending | Select-Object -First 15

        if (-not $results) {
            Write-Host "  $($global:UI_Theme.Muted)  No folders found.$($global:UI_Theme.Reset)"
            return
        }

        Write-Host "  $($global:UI_Theme.Muted)  Size          Folder$($global:UI_Theme.Reset)"
        Write-Host "  $($global:UI_Theme.Muted)  ----------    ------$($global:UI_Theme.Reset)"
        foreach ($r in $results) {
            $sizeStr = (Format-Bytes $r.Size).PadRight(12)
            Write-Host "  $($global:UI_Theme.Accent)  $sizeStr$($global:UI_Theme.Reset)  $($global:UI_Theme.Text)$($r.Folder)$($global:UI_Theme.Reset)"
        }
    } catch {
        Write-CoreError "Failed: $($_.Exception.Message)"
    }
}

# ── 3 — Largest Files ─────────────────────────────────────────
function Show-LargestFiles {
    Show-Header
    $w = Get-UiBoxWidth -MaxWidth 52 -MinWidth 40
    Write-UiBoxTitle -Title "LARGEST FILES" -Width $w
    Write-UiBlankLine
    Write-Host -NoNewline "  $($global:UI_Theme.Warning)  Path (default C:\Users): $($global:UI_Theme.Reset)"
    $targetPath = Read-Host
    if (-not $targetPath) { $targetPath = "$env:USERPROFILE" }

    if (-not (Test-Path -LiteralPath $targetPath)) {
        Write-CoreError "Path not found: $targetPath"
        return
    }

    Write-UiBlankLine
    Write-Host "  $($global:UI_Theme.Info)  Scanning: $targetPath$($global:UI_Theme.Reset)"
    Write-Host "  $($global:UI_Theme.Muted)  This may take a moment...$($global:UI_Theme.Reset)"
    Write-UiBlankLine

    try {
        $files = Get-ChildItem -LiteralPath $targetPath -Force -Recurse -File -ErrorAction SilentlyContinue |
            Sort-Object Length -Descending | Select-Object -First 20

        if (-not $files) {
            Write-Host "  $($global:UI_Theme.Muted)  No files found.$($global:UI_Theme.Reset)"
            return
        }

        Write-Host "  $($global:UI_Theme.Muted)  Size          File$($global:UI_Theme.Reset)"
        Write-Host "  $($global:UI_Theme.Muted)  ----------    ----$($global:UI_Theme.Reset)"
        foreach ($f in $files) {
            $sizeStr = (Format-Bytes $f.Length).PadRight(12)
            Write-Host "  $($global:UI_Theme.Accent)  $sizeStr$($global:UI_Theme.Reset)  $($global:UI_Theme.Text)$($f.FullName)$($global:UI_Theme.Reset)"
        }
    } catch {
        Write-CoreError "Failed: $($_.Exception.Message)"
    }
}

# ── 4 & 5 — Biggest System Drive Files ───────────────────────
function Show-BiggestSystemFiles($quiet = $false) {
    Show-Header

    $title = if ($quiet) {
        "BIGGEST FILES - SYSTEM DRIVE (QUIET)"
    } else {
        "BIGGEST FILES - SYSTEM DRIVE"
    }

    $w = Get-UiBoxWidth -MaxWidth 52 -MinWidth 40
    Write-UiBoxTitle -Title $title -Width $w

    $sysDrive = $env:SystemDrive
    $excludePrefixes = @(
        "$sysDrive\Windows\WinSxS",
        "$sysDrive\Windows\Installer",
        "$sysDrive\ProgramData",
        "$sysDrive\`$Recycle.Bin",
        "$sysDrive\System Volume Information"
    )

    Write-Host "  $($global:UI_Theme.Info)  Scanning: $sysDrive\$($global:UI_Theme.Reset)"
    if ($quiet) {
        Write-Host "  $($global:UI_Theme.Muted)  Excluding system/WinSxS folders for faster results$($global:UI_Theme.Reset)"
    }
    Write-Host "  $($global:UI_Theme.Muted)  This will take a while...$($global:UI_Theme.Reset)"
    Write-UiBlankLine

    try {
        $files = Get-ChildItem -LiteralPath "$sysDrive\" -Force -Recurse -File -ErrorAction SilentlyContinue

        if ($quiet) {
            $files = $files | Where-Object {
                $fp = $_.FullName
                -not ($excludePrefixes | Where-Object { $fp.StartsWith($_, [System.StringComparison]::OrdinalIgnoreCase) })
            }
        }

        $top = $files | Sort-Object Length -Descending | Select-Object -First 20

        Write-Host "  $($global:UI_Theme.Muted)  Size          File$($global:UI_Theme.Reset)"
        Write-Host "  $($global:UI_Theme.Muted)  ----------    ----$($global:UI_Theme.Reset)"
        foreach ($f in $top) {
            $sizeStr = (Format-Bytes $f.Length).PadRight(12)
            $sizeColor = if ($f.Length -ge 1GB) { $global:UI_Theme.Error } elseif ($f.Length -ge 500MB) { $global:UI_Theme.Warning } else { $global:UI_Theme.Success }
            Write-Host "  ${sizeColor}  $sizeStr$($global:UI_Theme.Reset)  $($global:UI_Theme.Text)$($f.FullName)$($global:UI_Theme.Reset)"
        }
    } catch {
        Write-CoreError "Failed: $($_.Exception.Message)"
    }
}

# ── 6 — Clean User Temp ───────────────────────────────────────
function Clean-UserTemp {
    Show-Header
    $w = Get-UiBoxWidth -MaxWidth 52 -MinWidth 40
    Write-UiBoxTitle -Title "CLEAN USER TEMP" -Width $w

    $tempPath = $env:TEMP
    Write-Host "  $($global:UI_Theme.Dim)$($global:UI_Theme.Text)  Path      $($global:UI_Theme.Reset)  $($global:UI_Theme.Muted)$tempPath$($global:UI_Theme.Reset)"

    $items = Get-ChildItem -LiteralPath $tempPath -Force -ErrorAction SilentlyContinue
    $count = ($items | Measure-Object).Count
    $size  = ($items | Get-ChildItem -Recurse -Force -ErrorAction SilentlyContinue |
        Measure-Object -Property Length -Sum).Sum
    Write-Host "  $($global:UI_Theme.Dim)$($global:UI_Theme.Text)  Items     $($global:UI_Theme.Reset)  $($global:UI_Theme.Warning)$count files/folders$($global:UI_Theme.Reset)"
    Write-Host "  $($global:UI_Theme.Dim)$($global:UI_Theme.Text)  Est. size $($global:UI_Theme.Reset)  $($global:UI_Theme.Warning)$(Format-Bytes $size)$($global:UI_Theme.Reset)"
    Write-UiBlankLine

    if (-not (Confirm-Action "Delete files from user temp?")) {
        Write-Host "  $($global:UI_Theme.Muted)  Cancelled.$($global:UI_Theme.Reset)"
        return
    }

    Write-UiBlankLine
    Write-Host "  $($global:UI_Theme.Info)  Cleaning...$($global:UI_Theme.Reset)"
    $deleted = 0
    $failed = 0
    foreach ($item in $items) {
        try {
            Remove-Item -LiteralPath $item.FullName -Recurse -Force -ErrorAction Stop
            $deleted++
        } catch {
            $failed++
        }
    }
    Write-CoreSuccess "Done. Removed: $deleted  |  Skipped (in use): $failed"
}

# ── 7 — Clean Windows Temp ────────────────────────────────────
function Clean-WindowsTemp {
    Show-Header
    $w = Get-UiBoxWidth -MaxWidth 52 -MinWidth 40
    Write-UiBoxTitle -Title "CLEAN WINDOWS TEMP" -Width $w

    $tempPath = Join-Path $env:SystemRoot "Temp"
    Write-Host "  $($global:UI_Theme.Dim)$($global:UI_Theme.Text)  Path      $($global:UI_Theme.Reset)  $($global:UI_Theme.Muted)$tempPath$($global:UI_Theme.Reset)"
    Write-Host "  $($global:UI_Theme.Warning)  Admin rights required for some files.$($global:UI_Theme.Reset)"

    $items = Get-ChildItem -LiteralPath $tempPath -Force -ErrorAction SilentlyContinue
    $count = ($items | Measure-Object).Count
    $size  = ($items | Get-ChildItem -Recurse -Force -ErrorAction SilentlyContinue |
        Measure-Object -Property Length -Sum).Sum
    Write-Host "  $($global:UI_Theme.Dim)$($global:UI_Theme.Text)  Items     $($global:UI_Theme.Reset)  $($global:UI_Theme.Warning)$count files/folders$($global:UI_Theme.Reset)"
    Write-Host "  $($global:UI_Theme.Dim)$($global:UI_Theme.Text)  Est. size $($global:UI_Theme.Reset)  $($global:UI_Theme.Warning)$(Format-Bytes $size)$($global:UI_Theme.Reset)"
    Write-UiBlankLine

    if (-not (Confirm-Action "Delete files from Windows temp?")) {
        Write-Host "  $($global:UI_Theme.Muted)  Cancelled.$($global:UI_Theme.Reset)"
        return
    }

    Write-UiBlankLine
    Write-Host "  $($global:UI_Theme.Info)  Cleaning...$($global:UI_Theme.Reset)"
    $deleted = 0
    $failed = 0
    foreach ($item in $items) {
        try {
            Remove-Item -LiteralPath $item.FullName -Recurse -Force -ErrorAction Stop
            $deleted++
        } catch {
            $failed++
        }
    }
    Write-CoreSuccess "Done. Removed: $deleted  |  Skipped (in use): $failed"
}

# ── 8 — Empty Recycle Bin ─────────────────────────────────────
function Empty-RecycleBin {
    Show-Header
    $w = Get-UiBoxWidth -MaxWidth 52 -MinWidth 40
    Write-UiBoxTitle -Title "EMPTY RECYCLE BIN" -Width $w

    if (-not (Confirm-Action "Empty the recycle bin?")) {
        Write-Host "  $($global:UI_Theme.Muted)  Cancelled.$($global:UI_Theme.Reset)"
        return
    }

    try {
        Clear-RecycleBin -Force -ErrorAction Stop
        Write-CoreSuccess "Recycle bin emptied."
    } catch {
        Write-CoreError "Failed: $($_.Exception.Message)"
    }
}

# ── 9 — Export CSV ────────────────────────────────────────────
function Export-DriveUsageCsv {
    Show-Header
    $w = Get-UiBoxWidth -MaxWidth 52 -MinWidth 40
    Write-UiBoxTitle -Title "EXPORT DRIVE USAGE CSV" -Width $w

    $defaultFile = "$HOME\drive_usage_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"
    Write-Host "  $($global:UI_Theme.Muted)  Default: $defaultFile$($global:UI_Theme.Reset)"
    Write-Host -NoNewline "  $($global:UI_Theme.Warning)  Output path (Enter for default): $($global:UI_Theme.Reset)"
    $outFile = Read-Host
    if (-not $outFile) { $outFile = $defaultFile }

    try {
        $data = Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3" | ForEach-Object {
            $totalGB = [Math]::Round($_.Size / 1GB, 2)
            $freeGB  = [Math]::Round($_.FreeSpace / 1GB, 2)
            [PSCustomObject]@{
                Drive      = $_.DeviceID
                Volume     = $_.VolumeName
                FileSystem = $_.FileSystem
                UsedGB     = [Math]::Round($totalGB - $freeGB, 2)
                FreeGB     = $freeGB
                TotalGB    = $totalGB
                UsedPct    = if ($totalGB -gt 0) { [Math]::Round((($totalGB - $freeGB) / $totalGB) * 100, 1) } else { 0 }
                Timestamp  = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
            }
        }
        $data | Export-Csv -Path $outFile -NoTypeInformation
        Write-CoreSuccess "Exported to: $outFile"
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
        "1" { Show-DriveUsage;                Pause-Script }
        "2" { Show-LargestFolders;            Pause-Script }
        "3" { Show-LargestFiles;              Pause-Script }
        "4" { Show-BiggestSystemFiles $false; Pause-Script }
        "5" { Show-BiggestSystemFiles $true;  Pause-Script }
        "6" { Clean-UserTemp;                 Pause-Script }
        "7" { Clean-WindowsTemp;              Pause-Script }
        "8" { Empty-RecycleBin;               Pause-Script }
        "9" { Export-DriveUsageCsv;           Pause-Script }

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