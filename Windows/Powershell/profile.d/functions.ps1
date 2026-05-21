#--------------------------------------------
# file:     functions.ps1
# author:   Mike Redd
# version:  2.4
# created:  2026-03-29
# updated:  2026-04-19
# desc:     Utility functions for every PowerShell session
#--------------------------------------------

# ── Fallback paths (if env.ps1 not loaded) ────────────────────
if (-not $global:PSScriptsDir) { 
    $global:PSScriptsDir = Join-Path $HOME "PS\scripts" 
}
if (-not $global:PSProfileDir) { 
    $global:PSProfileDir = Join-Path $HOME "PS\profile.d" 
}

# ── Admin shell ───────────────────────────────────────────────
function GoAdmin {
    Start-Process pwsh -Verb RunAs
}

# ── Navigation ────────────────────────────────────────────────
# Go up N directories  --  usage: up  or  up 3
function up {
    param([int]$levels = 1)

    $path = $PWD.Path
    for ($i = 0; $i -lt $levels; $i++) {
        $parent = Split-Path $path -Parent
        if ($parent) {
            $path = $parent
        } else {
            break
        }
    }

    Set-Location $path
}

# ── Scripts directory ─────────────────────────────────────────
# Quick jump to your scripts folder  --  usage: scripts
function scripts {
    if (-not $global:PSScriptsDir) {
        Write-Host "  PSScriptsDir not set" -ForegroundColor Yellow
        return
    }
    Set-Location $global:PSScriptsDir
}

# ── Profile directory ─────────────────────────────────────────
# Quick jump to your profile.d folder  --  usage: profiledir
function profiledir {
    if (-not $global:PSProfileDir) {
        Write-Host "  PSProfileDir not set" -ForegroundColor Yellow
        return
    }
    Set-Location $global:PSProfileDir
}

# ── Show directory tree ───────────────────────────────────────
# usage: tree  or  tree C:\path  or  tree . 3
function Show-Tree {
    param(
        [string]$Path = ".",
        [int]$MaxDepth = 99
    )

    $root = (Resolve-Path $Path).Path
    $rootDepth = $root.Split([IO.Path]::DirectorySeparatorChar).Count

    Get-ChildItem $root -Recurse -ErrorAction SilentlyContinue | ForEach-Object {
        $depth = $_.FullName.Split([IO.Path]::DirectorySeparatorChar).Count - $rootDepth
        if ($depth -le $MaxDepth) {
            $indent = "  " * $depth
            if ($_.PSIsContainer) {
                Write-Host "$indent$($_.Name)\" -ForegroundColor Cyan
            } else {
                $size = if ($_.Length -ge 1MB) {
                    " [{0:N1}MB]" -f ($_.Length / 1MB)
                } elseif ($_.Length -ge 1KB) {
                    " [{0:N1}KB]" -f ($_.Length / 1KB)
                } else {
                    " [{0}B]" -f $_.Length
                }
                Write-Host "$indent$($_.Name)$size" -ForegroundColor Gray
            }
        }
    }
}
Set-Alias -Name tree -Value Show-Tree

# ── System info quick hits ────────────────────────────────────
# Quick IP info  --  usage: myip
function Get-MyIP {
    $nics = Get-CimInstance Win32_NetworkAdapterConfiguration | Where-Object { $_.IPEnabled }

    foreach ($nic in $nics) {
        $ipv4 = $nic.IPAddress | Where-Object { $_ -match '^\d+\.\d+\.\d+\.\d+$' } | Select-Object -First 1
        if ($ipv4) {
            Write-Host "  $($nic.Description)" -ForegroundColor Cyan
            Write-Host "    IPv4 : $ipv4" -ForegroundColor Green
            Write-Host "    MAC  : $($nic.MACAddress)" -ForegroundColor Gray
        }
    }
}
Set-Alias -Name myip -Value Get-MyIP

# ── Uptime ────────────────────────────────────────────────────
# Quick uptime  --  usage: uptime
function Get-Uptime {
    $os = Get-CimInstance Win32_OperatingSystem
    $uptime = (Get-Date) - $os.LastBootUpTime

    Write-Host (
        "  Uptime: {0}d {1}h {2}m  (last boot: {3})" -f
        $uptime.Days,
        $uptime.Hours,
        $uptime.Minutes,
        $os.LastBootUpTime.ToString("yyyy-MM-dd HH:mm")
    ) -ForegroundColor Green
}
Set-Alias -Name uptime -Value Get-Uptime

# ── Disk usage summary ────────────────────────────────────────
# usage: diskuse
function Get-DiskSummary {
    $barMax = 20

    Get-PSDrive -PSProvider FileSystem | Where-Object { $_.Used -gt 0 } | ForEach-Object {
        $totalBytes = $_.Used + $_.Free
        if ($totalBytes -eq 0) { return }

        $total = [Math]::Round($totalBytes / 1GB, 1)
        $used  = [Math]::Round($_.Used / 1GB, 1)
        $free  = [Math]::Round($_.Free / 1GB, 1)
        $pct   = [Math]::Round(($_.Used / $totalBytes) * 100, 1)

        $filled = [Math]::Min($barMax, [Math]::Round($pct / 100 * $barMax))
        $empty  = $barMax - $filled
        $bar    = "#" * $filled + "-" * $empty

        $barColor = if ($pct -ge 90) {
            "Red"
        } elseif ($pct -ge 70) {
            "Yellow"
        } else {
            "Green"
        }

        Write-Host -NoNewline "  $($_.Name):  " -ForegroundColor White
        Write-Host -NoNewline "[$bar] " -ForegroundColor $barColor
        Write-Host ("{0}%  {1}GB used / {2}GB free / {3}GB total" -f $pct, $used, $free, $total) -ForegroundColor Gray
    }
}
Set-Alias -Name diskuse -Value Get-DiskSummary

# ── (rest unchanged) ──────────────────────────────────────────

# ── Load message ──────────────────────────────────────────────
if ($global:ShowProfileLoad) {
    Write-Host "  functions loaded" -ForegroundColor DarkGray
}

# ── Git functions ──────────────────────────────────────────────
function git-status { git status }
function git-log    { git log --oneline --graph --decorate -20 }
function gpf        { git push --force-with-lease }
function gca        { git commit --amend --no-edit }