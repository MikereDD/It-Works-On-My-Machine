#--------------------------------------------
# file:     ui.ps1
# author:   Mike Redd
# version:  1.3.1
# created:  2026-03-31
# updated:  2026-09-13
# desc:     Shared terminal UI and theme engine for Netzach PowerShell scripts
#--------------------------------------------

<#
.SYNOPSIS
    Canonical terminal UI/theme layer for Netzach PowerShell scripts.

.DESCRIPTION
    Defines the shared ANSI palette, semantic theme roles, layout helpers,
    prompts, rows, borders, and status helpers used by maintained console
    scripts under Netzach/PowerShell.

    Scripts should prefer semantic theme roles such as Accent, Success,
    Warning, Error, Muted, Text, and Secondary instead of choosing raw ANSI
    colors themselves. The legacy UI_* color globals remain available for
    compatibility while older scripts are migrated.

    GUI applications may keep their own visual systems; this module is for
    terminal/console presentation.

.NOTES
    Loaded by the main PowerShell profile, but safe to dot-source directly.

    Module metadata uses UI-prefixed variable names so dot-sourcing this file
    cannot overwrite a caller's generic $ScriptName/$ScriptVersion variables.

    Design goals:
      - one visual language across maintained console scripts
      - semantic colors rather than script-specific color choices
      - backwards compatibility during migration
      - no hard-coded user paths
#>

$UiScriptName    = "UI Core"
$UiScriptVersion = "1.3.1"
$UiScriptAuthor  = "Mike Redd"

# ── ANSI foundation ──────────────────────────────────────────
$global:ESC = [char]27

function C {
    param(
        [Parameter(Mandatory)]
        [string]$Code
    )

    return "$global:ESC[${Code}m"
}

# Raw ANSI tokens are intentionally centralized here. Scripts should normally
# consume $global:UI_Theme semantic roles rather than selecting these directly.
$global:UI_R   = C "0"
$global:UI_B   = C "1"
$global:UI_DIM = C "2"

$global:UI_CYN = C "96"
$global:UI_YLW = C "93"
$global:UI_GRN = C "92"
$global:UI_RED = C "91"
$global:UI_GRY = C "90"
$global:UI_WHT = C "97"
$global:UI_MAG = C "95"
$global:UI_BLU = C "94"

# ── Canonical Netzach terminal theme ─────────────────────────
# Semantic roles let the entire script collection change appearance from this
# one file without rewriting individual tools.
$global:UI_Theme = [ordered]@{
    Name      = "Netzach"
    Accent    = $global:UI_CYN
    Title     = $global:UI_YLW
    Success   = $global:UI_GRN
    Warning   = $global:UI_YLW
    Error     = $global:UI_RED
    Muted     = $global:UI_GRY
    Text      = $global:UI_WHT
    Secondary = $global:UI_MAG
    Info      = $global:UI_BLU
    Reset     = $global:UI_R
    Bold      = $global:UI_B
    Dim       = $global:UI_DIM
}

function Get-UiThemeColor {
    param(
        [Parameter(Mandatory)]
        [ValidateSet(
            "Accent",
            "Title",
            "Success",
            "Warning",
            "Error",
            "Muted",
            "Text",
            "Secondary",
            "Info",
            "Reset",
            "Bold",
            "Dim"
        )]
        [string]$Role
    )

    return $global:UI_Theme[$Role]
}

# ── Terminal/layout helpers ──────────────────────────────────
function Get-UiTerminalWidth {
    try {
        return [Console]::WindowWidth
    }
    catch {
        return 80
    }
}

function Get-UiBoxWidth {
    param(
        [int]$MaxWidth = 60,
        [int]$MinWidth = 40
    )

    $termWidth = Get-UiTerminalWidth
    $width = [math]::Min($MaxWidth, $termWidth - 4)
    return [math]::Max($MinWidth, $width)
}

function Get-UiLeftPad {
    param(
        [int]$ContentWidth
    )

    $termWidth = Get-UiTerminalWidth
    return [math]::Max(0, [math]::Floor(($termWidth - $ContentWidth) / 2))
}

function Write-UiBlankLine {
    Write-Host ""
}

function Get-UiPadString {
    param(
        [int]$Width,
        [switch]$Centered
    )

    if ($Centered) {
        $leftPad = Get-UiLeftPad $Width
        return (" " * $leftPad)
    }

    return ""
}

# ── Shared presentation helpers ──────────────────────────────
function Write-UiBoxBorder {
    param(
        [int]$Width = 60,
        [switch]$Centered
    )

    $pad = Get-UiPadString -Width ($Width + 2) -Centered:$Centered
    $accent = $global:UI_Theme.Accent

    Write-Host $pad -NoNewline
    Write-Host "${accent}${global:UI_B}+$((("=" * $Width)))+${global:UI_R}"
}

function Write-UiBoxText {
    param(
        [string]$Text,
        [int]$Width = 60,
        [string]$TextColor = $global:UI_Theme.Title,
        [switch]$Bold,
        [switch]$Centered
    )

    if ($null -eq $Text) {
        $Text = ""
    }

    if ($Text.Length -gt $Width) {
        $Text = $Text.Substring(0, $Width)
    }

    $padLeft  = [math]::Floor(($Width - $Text.Length) / 2)
    $padRight = $Width - $Text.Length - $padLeft
    $pad      = Get-UiPadString -Width ($Width + 2) -Centered:$Centered
    $weight   = if ($Bold) { $global:UI_B } else { "" }
    $accent   = $global:UI_Theme.Accent

    Write-Host $pad -NoNewline
    Write-Host "${accent}${global:UI_B}|${global:UI_R}$(" " * $padLeft)${TextColor}${weight}$Text${global:UI_R}$(" " * $padRight)${accent}${global:UI_B}|${global:UI_R}"
}

function Write-UiHeader {
    param(
        [string]$Title,
        [string]$Subtitle = "",
        [int]$Width = 60,
        [switch]$Centered
    )

    Write-UiBlankLine
    Write-UiBoxBorder -Width $Width -Centered:$Centered
    Write-UiBoxText -Text $Title -Width $Width -TextColor $global:UI_Theme.Title -Bold -Centered:$Centered

    if (-not [string]::IsNullOrWhiteSpace($Subtitle)) {
        Write-UiBoxText -Text $Subtitle -Width $Width -TextColor $global:UI_Theme.Muted -Centered:$Centered
    }

    Write-UiBoxBorder -Width $Width -Centered:$Centered
    Write-UiBlankLine
}

function Write-UiBoxTitle {
    param(
        [string]$Title,
        [int]$Width = 60,
        [switch]$Centered
    )

    Write-UiBoxBorder -Width $Width -Centered:$Centered
    Write-UiBoxText -Text $Title -Width $Width -TextColor $global:UI_Theme.Title -Bold -Centered:$Centered
    Write-UiBoxBorder -Width $Width -Centered:$Centered
    Write-UiBlankLine
}

function Write-UiSection {
    param(
        [string]$Title,
        [string]$Color = $global:UI_Theme.Secondary
    )

    Write-Host "  ${Color}${global:UI_B}-- $Title --${global:UI_R}"
}

function Write-UiRow {
    param(
        [string]$Label,
        [string]$Value,
        [string]$ValueColor = $global:UI_Theme.Success,
        [int]$LabelWidth = 20
    )

    Write-Host "  ${global:UI_Theme.Dim}$($Label.PadRight($LabelWidth))${global:UI_R}  ${ValueColor}$Value${global:UI_R}"
}

function Write-UiDivider {
    param(
        [int]$Width = 52
    )

    Write-Host "  ${global:UI_Theme.Muted}$(('-' * $Width))${global:UI_R}"
}

function Write-UiStatus {
    param(
        [Parameter(Mandatory)]
        [ValidateSet("Info", "Success", "Warning", "Error")]
        [string]$Status,

        [Parameter(Mandatory)]
        [string]$Message
    )

    $color = switch ($Status) {
        "Success" { $global:UI_Theme.Success }
        "Warning" { $global:UI_Theme.Warning }
        "Error"   { $global:UI_Theme.Error }
        default   { $global:UI_Theme.Info }
    }

    Write-Host "  ${color}${global:UI_B}[$Status]${global:UI_R} ${global:UI_Theme.Text}$Message${global:UI_R}"
}

function Read-UiChoice {
    param(
        [string]$Prompt = "Choice:"
    )

    Write-Host -NoNewline "  ${global:UI_Theme.Warning}${global:UI_B}$Prompt${global:UI_R} "
    return Read-Host
}

function Pause-UiReturn {
    param(
        [string]$Prompt = "Press Enter to return..."
    )

    Write-UiBlankLine
    Write-Host -NoNewline "  ${global:UI_Theme.Muted}$Prompt${global:UI_R}"
    Read-Host | Out-Null
}

function Clear-UiScreen {
    Clear-Host
}
