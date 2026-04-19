#--------------------------------------------
# file:     core.ps1
# author:   Mike Redd
# version:  1.2
# created:  2026-04-01
# updated:  2026-04-01
# desc:     Shared core helpers (logic, safety, logging)
#--------------------------------------------

# ── Load UI (optional but recommended) ────────────────────────
$uiPath = "$env:USERPROFILE\PS\profile.d\ui.ps1"
if (Test-Path $uiPath) {
    try {
        . $uiPath
    } catch {}
}

# ── Fallback UI values if ui.ps1 is unavailable ───────────────
if (-not $global:UI_R)   { $global:UI_R   = "" }
if (-not $global:UI_B)   { $global:UI_B   = "" }
if (-not $global:UI_DIM) { $global:UI_DIM = "" }

if (-not $global:UI_CYN) { $global:UI_CYN = "" }
if (-not $global:UI_YLW) { $global:UI_YLW = "" }
if (-not $global:UI_GRN) { $global:UI_GRN = "" }
if (-not $global:UI_RED) { $global:UI_RED = "" }
if (-not $global:UI_GRY) { $global:UI_GRY = "" }
if (-not $global:UI_WHT) { $global:UI_WHT = "" }
if (-not $global:UI_MAG) { $global:UI_MAG = "" }
if (-not $global:UI_BLU) { $global:UI_BLU = "" }

# ── Logging toggle ────────────────────────────────────────────
$global:CORE_LOG_ENABLED = $false
$global:CORE_LOG_FILE    = "$env:USERPROFILE\PS\logs\toolkit.log"

# ── Enable logging ────────────────────────────────────────────
function Enable-CoreLogging {
    param(
        [string]$Path = "$env:USERPROFILE\PS\logs\toolkit.log"
    )

    $global:CORE_LOG_ENABLED = $true
    $global:CORE_LOG_FILE    = $Path

    $dir = Split-Path -Path $Path -Parent
    if ($dir -and -not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
}

# ── Write log entry ───────────────────────────────────────────
function Write-CoreLog {
    param(
        [string]$Message
    )

    if (-not $global:CORE_LOG_ENABLED) { return }

    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Add-Content -Path $global:CORE_LOG_FILE -Value "[$ts] $Message"
}

# ── Success output ────────────────────────────────────────────
function Write-CoreSuccess {
    param(
        [string]$Message
    )

    Write-Host "  $($global:UI_GRN)$Message$($global:UI_R)"
    Write-CoreLog "SUCCESS: $Message"
}

# ── Error output ──────────────────────────────────────────────
function Write-CoreError {
    param(
        [string]$Message
    )

    Write-Host "  $($global:UI_RED)$Message$($global:UI_R)"
    Write-CoreLog "ERROR: $Message"
}

# ── Safe command execution ────────────────────────────────────
function Invoke-Safe {
    param(
        [scriptblock]$Script,
        [string]$ErrorMessage = "Operation failed"
    )

    try {
        & $Script
        Write-CoreLog "SUCCESS: $ErrorMessage"
        return $true
    } catch {
        Write-Host "  $($global:UI_RED)${ErrorMessage}: $($_.Exception.Message)$($global:UI_R)"
        Write-CoreLog "ERROR: $ErrorMessage :: $($_.Exception.Message)"
        return $false
    }
}

# ── Confirm wrapper ───────────────────────────────────────────
function Confirm-Core {
    param(
        [string]$Message
    )

    Write-Host ""
    Write-Host -NoNewline "  $($global:UI_YLW)$Message (y/n): $($global:UI_R)"
    $c = Read-Host
    return $c -match '^[Yy]$'
}

# ── Pause wrapper ─────────────────────────────────────────────
function Pause-Core {
    param(
        [string]$Message = "Press Enter to continue..."
    )

    if (Get-Command Pause-UiReturn -ErrorAction SilentlyContinue) {
        Pause-UiReturn $Message
    } else {
        Write-Host ""
        Read-Host "  $Message" | Out-Null
    }
}

# ── Export helper ─────────────────────────────────────────────
function Export-CoreData {
    param(
        [Parameter(Mandatory)]
        $Data,

        [string]$Name = "export",
        [string]$Format = "txt"
    )

    $ts   = Get-Date -Format "yyyyMMdd_HHmmss"
    $path = "$env:USERPROFILE\PS\exports\${Name}_$ts.$Format"

    $dir = Split-Path -Path $path -Parent
    if ($dir -and -not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }

    switch ($Format.ToLower()) {
        "json"  { $Data | ConvertTo-Json -Depth 5 | Out-File $path }
        "csv"   { $Data | Export-Csv -NoTypeInformation -Path $path }
        default { $Data | Out-File $path }
    }

    Write-Host "  $($global:UI_GRN)Saved to:$($global:UI_R) $path"
    Write-CoreLog "EXPORT: $path"
}