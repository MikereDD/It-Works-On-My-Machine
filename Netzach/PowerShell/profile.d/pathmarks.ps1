# ============================================================================
# Pathmarks for PowerShell
# ============================================================================
# Script:      pathmarks.ps1
# Component:   Typezerø shell utilities / persistent directory bookmarks
# Platform:    Windows / PowerShell 7+
# Purpose:     Save short names for frequently used directories and jump back
#              to them from any PowerShell session.
# Storage:     ~/.config/pmarks/pathmarks.json
# Dependencies: PowerShell built-ins only; no external modules required.
#
# Commands:
#   mark <name> [path] - Save the current directory, or an explicit directory.
#   jump <name>        - Change to a saved directory.
#   marks              - List saved directories and whether they still exist.
#   unmark <name>      - Remove a saved directory.
#   pathmarks-help     - Show command help and examples.
#
# Design notes:
#   - Bookmark data is machine-local rather than tracked in Git. Creating or
#     removing a bookmark must never dirty It-Works-On-My-Machine.
#   - Bookmark names are intentionally limited to letters, numbers, dot,
#     underscore, and hyphen so they remain simple and portable across shells.
#   - Writes use a temporary file followed by replacement to reduce the chance
#     of leaving a partially written bookmark database after interruption.
#   - `jump` is deliberately used instead of `go`; Go is installed on both
#     Netzach and Arakiel, so Pathmarks must not shadow the Go toolchain.
#   - Functions are loaded into the current shell because changing directory
#     from a child process cannot change the caller's working directory.
# ============================================================================

$script:PathmarksDir  = Join-Path $HOME '.config\pmarks'
$script:PathmarksFile = Join-Path $script:PathmarksDir 'pathmarks.json'

# ── Storage: read bookmark database ─────────────────────────────────────────
function Get-PathmarkTable {
    # Always return an ordered table so listing and JSON output are predictable.
    $table = [ordered]@{}

    if (-not (Test-Path -LiteralPath $script:PathmarksFile)) {
        return $table
    }

    try {
        $raw = Get-Content -LiteralPath $script:PathmarksFile -Raw -ErrorAction Stop
        if (-not [string]::IsNullOrWhiteSpace($raw)) {
            $saved = $raw | ConvertFrom-Json -ErrorAction Stop
            foreach ($property in $saved.PSObject.Properties) {
                $table[$property.Name] = [string]$property.Value
            }
        }
    }
    catch {
        Write-Warning "Pathmarks could not read its data file: $($_.Exception.Message)"
    }

    return $table
}

# ── Storage: persist bookmark database ──────────────────────────────────────
function Save-PathmarkTable {
    param(
        [Parameter(Mandatory)]
        $Table
    )

    # Write to a temporary file first, then replace the database. This avoids
    # leaving a partially written JSON file if a write is interrupted.
    New-Item -ItemType Directory -Path $script:PathmarksDir -Force | Out-Null
    $tempFile = "$($script:PathmarksFile).tmp"

    try {
        $Table | ConvertTo-Json | Set-Content -LiteralPath $tempFile -Encoding utf8 -ErrorAction Stop
        Move-Item -LiteralPath $tempFile -Destination $script:PathmarksFile -Force -ErrorAction Stop
    }
    catch {
        Remove-Item -LiteralPath $tempFile -Force -ErrorAction SilentlyContinue
        throw
    }
}

# ── Public command: mark ────────────────────────────────────────────────────
function mark {
    param(
        [Parameter(Mandatory, Position = 0)]
        [ValidatePattern('^[A-Za-z0-9._-]+$')]
        [string]$Name,

        [Parameter(Position = 1)]
        [string]$Path = (Get-Location).Path
    )

    # Resolve before saving so relative input becomes a stable absolute path.
    $resolved = Resolve-Path -LiteralPath $Path -ErrorAction SilentlyContinue
    if (-not $resolved -or -not (Test-Path -LiteralPath $resolved.Path -PathType Container)) {
        Write-Warning "Pathmark '$Name' was not saved: directory not found: $Path"
        return
    }

    # Reusing a name intentionally updates that bookmark in place.
    $table = Get-PathmarkTable
    $table[$Name] = $resolved.Path
    Save-PathmarkTable -Table $table

    Write-Host "  $($global:UI_Theme.Accent)marked$($global:UI_Theme.Reset)  " -NoNewline
    Write-Host "$Name -> $($resolved.Path)"
}

# ── Public command: jump ────────────────────────────────────────────────────
function jump {
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$Name
    )

    $table = Get-PathmarkTable
    if (-not $table.Contains($Name)) {
        Write-Warning "Unknown pathmark '$Name'. Run 'marks' to list saved marks."
        return
    }

    $target = [string]$table[$Name]
    if (-not (Test-Path -LiteralPath $target -PathType Container)) {
        Write-Warning "Pathmark '$Name' points to a missing directory: $target"
        return
    }

    # Set-Location must execute in the caller's shell; this is why Pathmarks is
    # implemented as sourced functions rather than a separate executable.
    Set-Location -LiteralPath $target
}

# ── Public command: marks ───────────────────────────────────────────────────
function marks {
    $table = Get-PathmarkTable
    if ($table.Count -eq 0) {
        Write-Host "  $($global:UI_Theme.Muted)No pathmarks saved.$($global:UI_Theme.Reset)"
        return
    }

    # Materialize the rows before piping them. A foreach statement cannot be
    # piped directly in this form; doing so prevents the entire script parsing.
    $rows = foreach ($name in ($table.Keys | Sort-Object)) {
        $target = [string]$table[$name]
        [PSCustomObject]@{
            Name   = $name
            Exists = Test-Path -LiteralPath $target -PathType Container
            Path   = $target
        }
    }

    $rows | Format-Table -AutoSize
}

# ── Public command: unmark ──────────────────────────────────────────────────
function unmark {
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$Name
    )

    $table = Get-PathmarkTable
    if (-not $table.Contains($Name)) {
        Write-Warning "Unknown pathmark '$Name'."
        return
    }

    $table.Remove($Name)
    Save-PathmarkTable -Table $table

    Write-Host "  $($global:UI_Theme.Accent)removed$($global:UI_Theme.Reset) " -NoNewline
    Write-Host $Name
}

# ── Public command: help ────────────────────────────────────────────────────
function pathmarks-help {
    @'
PATHMARKS

Persistent directory bookmarks.

  mark <name>          Save the current directory
  mark <name> <path>   Save a specific directory
  jump <name>          Jump to a saved directory
  marks                List saved directories
  unmark <name>        Remove a saved directory
  pathmarks-help       Show this help

Examples:
  mark repo
  mark music P:\Music
  jump repo
  marks
  unmark repo

Storage:
  ~/.config/pmarks/pathmarks.json
'@ | Write-Host
}
