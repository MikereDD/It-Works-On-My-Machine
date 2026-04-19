#--------------------------------------------
# file:     ui.ps1
# author:   Mike Redd
# version:  1.2
# created:  2026-03-31
# updated:  2026-04-01
# desc:     Shared UI helpers for PowerShell scripts
#--------------------------------------------

$ScriptName    = "UI Core"
$ScriptVersion = "1.2"
$ScriptAuthor  = "Mike Redd"

# ── ANSI ────────────────────────────────────────────
$global:ESC = [char]27
function C($code) { return "$global:ESC[${code}m" }

# ── Shared colors ───────────────────────────────────
$global:UI_R   = C "0"; $global:UI_B   = C "1"; $global:UI_DIM = C "2"

$global:UI_CYN = C "96"; $global:UI_YLW = C "93"; $global:UI_GRN = C "92"
$global:UI_RED = C "91"; $global:UI_GRY = C "90"; $global:UI_WHT = C "97"
$global:UI_MAG = C "95"; $global:UI_BLU = C "94"

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

function Write-UiBoxBorder {
    param(
        [int]$Width = 60,
        [switch]$Centered
    )

    $pad = Get-UiPadString -Width ($Width + 2) -Centered:$Centered

    Write-Host $pad -NoNewline
    Write-Host "${global:UI_CYN}${global:UI_B}+$(("=" * $Width))+${global:UI_R}"
}

function Write-UiBoxText {
    param(
        [string]$Text,
        [int]$Width = 60,
        [string]$TextColor = $global:UI_YLW,
        [switch]$Bold,
        [switch]$Centered
    )

    if ($null -eq $Text) { $Text = "" }

    if ($Text.Length -gt $Width) {
        $Text = $Text.Substring(0, $Width)
    }

    $padLeft  = [math]::Floor(($Width - $Text.Length) / 2)
    $padRight = $Width - $Text.Length - $padLeft
    $pad      = Get-UiPadString -Width ($Width + 2) -Centered:$Centered
    $weight   = if ($Bold) { $global:UI_B } else { "" }

    Write-Host $pad -NoNewline
    Write-Host "${global:UI_CYN}${global:UI_B}|${global:UI_R}$(" " * $padLeft)${TextColor}${weight}$Text${global:UI_R}$(" " * $padRight)${global:UI_CYN}${global:UI_B}|${global:UI_R}"
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
    Write-UiBoxText -Text $Title -Width $Width -TextColor $global:UI_YLW -Bold -Centered:$Centered

    if (-not [string]::IsNullOrWhiteSpace($Subtitle)) {
        Write-UiBoxText -Text $Subtitle -Width $Width -TextColor $global:UI_GRY -Centered:$Centered
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
    Write-UiBoxText -Text $Title -Width $Width -TextColor $global:UI_YLW -Bold -Centered:$Centered
    Write-UiBoxBorder -Width $Width -Centered:$Centered
    Write-UiBlankLine
}

function Write-UiSection {
    param(
        [string]$Title,
        [string]$Color = $global:UI_MAG
    )

    Write-Host "  ${Color}${global:UI_B}-- $Title --${global:UI_R}"
}

function Write-UiRow {
    param(
        [string]$Label,
        [string]$Value,
        [string]$ValueColor = $global:UI_GRN,
        [int]$LabelWidth = 20
    )

    Write-Host "  ${global:UI_DIM}$($Label.PadRight($LabelWidth))${global:UI_R}  ${ValueColor}$Value${global:UI_R}"
}

function Write-UiDivider {
    param(
        [int]$Width = 52
    )

    Write-Host "  ${global:UI_GRY}$(('-' * $Width))${global:UI_R}"
}

function Read-UiChoice {
    param(
        [string]$Prompt = "Choice:"
    )

    Write-Host -NoNewline "  ${global:UI_YLW}${global:UI_B}$Prompt${global:UI_R} "
    return Read-Host
}

function Pause-UiReturn {
    param(
        [string]$Prompt = "Press Enter to return..."
    )

    Write-UiBlankLine
    Write-Host -NoNewline "  ${global:UI_GRY}$Prompt${global:UI_R}"
    Read-Host | Out-Null
}

function Clear-UiScreen {
    Clear-Host
}