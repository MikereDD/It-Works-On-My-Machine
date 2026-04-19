#--------------------------------------------
# file:     Microsoft.PowerShell_profile.ps1
# author:   Mike Redd
# version:  1.5
# created:  2026-04-02
# updated:  2026-04-19
# desc:     Main PowerShell profile loader
#--------------------------------------------

# ── Set execution policy for this session ────────────────────
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope Process -Force

# ── Base PowerShell directory ────────────────────────────────
$PSDir = Join-Path $HOME "PS"

# ── Profile.d directory ──────────────────────────────────────
$ProfileDir = Join-Path $PSDir "profile.d"

# ── Shared global paths ──────────────────────────────────────
$global:PSRootDir     = $PSDir
$global:PSProfileDir  = $ProfileDir
$global:PSScriptsDir  = Join-Path $PSDir "Scripts"

# ── Load env ─────────────────────────────────────────────────
$envFile = Join-Path $ProfileDir "env.ps1"
if (Test-Path $envFile) {
    try {
        . $envFile
    } catch {
        Write-Host "  [profile] failed to load env.ps1: $($_.Exception.Message)" -ForegroundColor Yellow
    }
} else {
    Write-Host "  [profile] env.ps1 not found at $envFile" -ForegroundColor Yellow
}

# ── Load aliases ─────────────────────────────────────────────
$aliasFile = Join-Path $ProfileDir "aliases.ps1"
if (Test-Path $aliasFile) {
    try {
        . $aliasFile
    } catch {
        Write-Host "  [profile] failed to load aliases.ps1: $($_.Exception.Message)" -ForegroundColor Yellow
    }
} else {
    Write-Host "  [profile] aliases.ps1 not found at $aliasFile" -ForegroundColor Yellow
}

# ── Load functions ───────────────────────────────────────────
$functionFile = Join-Path $ProfileDir "functions.ps1"
if (Test-Path $functionFile) {
    try {
        . $functionFile
    } catch {
        Write-Host "  [profile] failed to load functions.ps1: $($_.Exception.Message)" -ForegroundColor Yellow
    }
} else {
    Write-Host "  [profile] functions.ps1 not found at $functionFile" -ForegroundColor Yellow
}

# ── Load UI ──────────────────────────────────────────────────
$uiFile = Join-Path $ProfileDir "ui.ps1"
if (Test-Path $uiFile) {
    try {
        . $uiFile
    } catch {
        Write-Host "  [profile] failed to load ui.ps1: $($_.Exception.Message)" -ForegroundColor Yellow
    }
} else {
    Write-Host "  [profile] ui.ps1 not found at $uiFile" -ForegroundColor Yellow
}

# ── Load core ────────────────────────────────────────────────
$coreFile = Join-Path $ProfileDir "core.ps1"
if (Test-Path $coreFile) {
    try {
        . $coreFile
    } catch {
        Write-Host "  [profile] failed to load core.ps1: $($_.Exception.Message)" -ForegroundColor Yellow
    }
} else {
    Write-Host "  [profile] core.ps1 not found at $coreFile" -ForegroundColor Yellow
}

# ── Ready message ────────────────────────────────────────────
Write-Host "  profile ready" -ForegroundColor DarkCyan