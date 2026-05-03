#--------------------------------------------
# file:     m2ts-largest-copy.ps1
# author:   Mike Redd
# version:  2.3
# created:  2026-04-11
# updated:  2026-04-11
# desc:     ToolMenu-friendly MakeMKV wrapper.
#           Decrypts Blu-ray to temp backup,
#           finds the largest .m2ts, copies it
#           to G:\Rip\m2ts, then removes temp
#           backup.
#--------------------------------------------

param()

$ErrorActionPreference = 'Stop'

# ── Load UI ─────────────────────────────────
$uiPath = "$env:USERPROFILE\PS\profile.d\ui.ps1"
if (Test-Path -LiteralPath $uiPath) {
    . $uiPath
}
else {
    Write-Host "Missing ui.ps1"
    return
}

$corePath = "$env:USERPROFILE\PS\profile.d\core.ps1"
if (Test-Path -LiteralPath $corePath) {
    . $corePath
}
else {
    Write-Host "Missing core.ps1"
    return
}

$ScriptName    = "M2TS Largest Copy"
$ScriptVersion = "2.3"
$ScriptAuthor  = "Mike Redd"

# ── Config ─────────────────────────────────
$Script:RootPath   = "G:\Rip"
$Script:BackupRoot = Join-Path $Script:RootPath "bluray"
$Script:M2TSRoot   = Join-Path $Script:RootPath "m2ts"
$Script:Drive      = "disc:0"

# ── Header ─────────────────────────────────
function Show-Header {
    Clear-UiScreen
    Write-UiHeader -Title $ScriptName -Subtitle "v$ScriptVersion by $ScriptAuthor"
    Write-UiRow "Drive"  $Script:Drive
    Write-UiRow "Output" $Script:M2TSRoot -ValueColor $global:UI_GRY
    Write-UiBlankLine
}

function Pause-Script {
    Pause-UiReturn "Press Enter to return..."
}

function Ensure-Dirs {
    foreach ($p in @($Script:RootPath, $Script:BackupRoot, $Script:M2TSRoot)) {
        if (-not (Test-Path -LiteralPath $p)) {
            New-Item -ItemType Directory -Path $p -Force | Out-Null
        }
    }
}

function Get-SafeName {
    param([string]$Name)

    $safe = ($Name -replace '[\\\/:\*\?"<>\|]', '_').Trim()
    if ([string]::IsNullOrWhiteSpace($safe)) {
        $safe = "bluray_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
    }

    return $safe
}

function Get-MakeMKVPath {
    $paths = @(
        "C:\Program Files\MakeMKV\makemkvcon.exe",
        "C:\Program Files (x86)\MakeMKV\makemkvcon.exe"
    )

    foreach ($p in $paths) {
        if (Test-Path -LiteralPath $p) {
            return $p
        }
    }

    return $null
}

function Get-StreamPath {
    param([Parameter(Mandatory)][string]$RootPath)

    $dirs = Get-ChildItem -LiteralPath $RootPath -Recurse -Directory -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -ieq "STREAM" }

    foreach ($d in $dirs) {
        $m = Get-ChildItem -LiteralPath $d.FullName -Filter *.m2ts -File -ErrorAction SilentlyContinue
        if ($m -and $m.Count -gt 0) {
            return $d.FullName
        }
    }

    return $null
}

function Get-LargestM2TS {
    param([Parameter(Mandatory)][string]$Path)

    Get-ChildItem -LiteralPath $Path -Filter *.m2ts -File -ErrorAction SilentlyContinue |
    Sort-Object Length -Descending |
    Select-Object -First 1
}

# ── MakeMKV Progress ───────────────────────
function Show-MakeMKVProgress {
    param($exe, $drive, $dest)

    $args = "backup --decrypt --cache=512 -r --progress=-same $drive `"$dest`""

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $exe
    $psi.Arguments = $args
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError  = $true
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow  = $true

    $p = New-Object System.Diagnostics.Process
    $p.StartInfo = $psi
    $null = $p.Start()

    $percent = 0

    while (-not $p.HasExited) {
        while (-not $p.StandardOutput.EndOfStream) {
            $line = $p.StandardOutput.ReadLine()

            if ($line -match 'PRGV:(\d+),(\d+),(\d+)') {
                $cur = [double]$matches[2]
                $tot = [double]$matches[3]
                if ($tot -gt 0) {
                    $percent = [math]::Floor(($cur / $tot) * 100)
                }
            }
        }

        $filled = [math]::Floor($percent / 4)
        if ($filled -lt 0) { $filled = 0 }
        if ($filled -gt 25) { $filled = 25 }

        $bar = ('#' * $filled).PadRight(25, '-')
        Write-Host "`r [$bar] $percent%" -NoNewline
        Start-Sleep -Milliseconds 200
    }

    Write-Host ""
    $p.WaitForExit()
    return $p.ExitCode
}

# ── Menu ───────────────────────────────────
function Show-Menu {
    Show-Header
    Write-UiSection -Title "Actions"
    Write-Host "  1) Grab largest .m2ts"
    Write-UiDivider
    Write-Host "  Q) Return"
}

# ── Main Action ────────────────────────────
function Start-Copy {
    Show-Header

    $exe = Get-MakeMKVPath
    if (-not $exe) {
        Write-CoreError "MakeMKV not found"
        Pause-Script
        return
    }

    $name = Read-Host "Movie name"
    $year = Read-Host "Year (optional)"

    if ($year -match '^\d{4}$') {
        $name = "$name [$year]"
    }

    $safe = Get-SafeName $name

    $backup = Join-Path $Script:BackupRoot $safe
    $dest   = Join-Path $Script:M2TSRoot "$safe.m2ts"

    Write-UiSection -Title "MakeMKV"
    Write-Host "  Decrypting..."

    $code = Show-MakeMKVProgress $exe $Script:Drive $backup

    if ($code -ne 0) {
        Write-CoreError "MakeMKV failed"
        Pause-Script
        return
    }

    $stream = Get-StreamPath -RootPath $backup
    if (-not $stream) {
        Write-CoreError "No STREAM folder found"
        Pause-Script
        return
    }

    $largest = Get-LargestM2TS -Path $stream
    if (-not $largest) {
        Write-CoreError "No M2TS found"
        Pause-Script
        return
    }

    Write-UiSection -Title "Copy"
    Write-Host "  $($largest.Name)"

    Copy-Item -LiteralPath $largest.FullName -Destination $dest -Force -ErrorAction Stop

    Remove-Item -LiteralPath $backup -Recurse -Force -ErrorAction SilentlyContinue

    Write-UiSection -Title "Done"
    Write-Host "  Saved: $dest"

    Pause-Script
}

# ── Main Loop ──────────────────────────────
Ensure-Dirs

while ($true) {
    Show-Menu
    $c = (Read-Host "Choice").ToUpper()

    switch ($c) {
        '1' { Start-Copy }
        'Q' { return }
    }
}