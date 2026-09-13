#--------------------------------------------
# file:     snake.ps1
# author:   Mike Redd
# version:  1.1
# created:  2026-03-30
# updated:  2026-09-13
# desc:     Snake game using the shared Netzach PowerShell theme engine
#--------------------------------------------

<#
.SYNOPSIS
    Classic Snake game for the PowerShell terminal.

.DESCRIPTION
    Keeps gameplay rendering local to the game while using the shared Netzach
    theme engine for all visual roles. This prevents the game from maintaining
    its own duplicate ANSI palette and keeps its chrome consistent with the
    rest of the maintained PowerShell scripts.

    Gameplay-specific roles map onto the shared semantic theme:
      - board/walls  -> Accent
      - snake head   -> Title
      - snake body   -> Success
      - food         -> Error
      - score        -> Success
      - level        -> Secondary
      - help/status  -> Muted/Text

.NOTES
    The normal PowerShell profile already loads profile.d/ui.ps1. When the game
    is launched directly, it resolves that same file relative to $PSScriptRoot
    so no username or machine-specific path is hard-coded.
#>

$ScriptName    = "Snake"
$ScriptVersion = "1.1"
$ScriptAuthor  = "Mike Redd"

# ── Shared UI/theme engine ───────────────────────────────────
# The profile normally provides these functions and theme values. Direct script
# launches need the fallback loader below.
if (-not (Get-Command Get-UiThemeColor -ErrorAction SilentlyContinue)) {
    $uiFile = Join-Path $PSScriptRoot "..\..\profile.d\ui.ps1"

    if (-not (Test-Path $uiFile)) {
        throw "Shared UI theme engine not found: $uiFile"
    }

    . $uiFile
}

# Bind the game's visual roles to the central theme once. Gameplay code below
# can stay readable without choosing raw ANSI colors of its own.
$ThemeReset     = $global:UI_Theme.Reset
$ThemeBold      = $global:UI_Theme.Bold
$ThemeAccent    = $global:UI_Theme.Accent
$ThemeTitle     = $global:UI_Theme.Title
$ThemeSuccess   = $global:UI_Theme.Success
$ThemeError     = $global:UI_Theme.Error
$ThemeMuted     = $global:UI_Theme.Muted
$ThemeText      = $global:UI_Theme.Text
$ThemeSecondary = $global:UI_Theme.Secondary
$ThemeDim       = $global:UI_Theme.Dim

# ── Game settings ────────────────────────────────────────────
$BoardWidth  = 20
$BoardHeight = 12
$TickMs      = 120

# Double-width block cells keep the board visually square in a terminal.
$WallChar  = "██"
$SnakeChar = "██"
$FoodChar  = "██"
$EmptyChar = "  "

# ── Input / console setup ────────────────────────────────────
# Cursor and Ctrl+C handling are restored in finally even if the game exits
# through Q or throws an exception.
[Console]::CursorVisible = $false
$originalTreatControlCAsInput = [Console]::TreatControlCAsInput
[Console]::TreatControlCAsInput = $true

function Show-Header {
    $width = 38
    $title = "$ScriptName v$ScriptVersion"
    $titlePadding = [math]::Max(0, $width - $title.Length - 2)

    Write-Host "  ${ThemeAccent}${ThemeBold}+$("=" * $width)+${ThemeReset}"
    Write-Host "  ${ThemeAccent}${ThemeBold}|${ThemeReset}  ${ThemeTitle}${ThemeBold}$title${ThemeReset}$(" " * $titlePadding)${ThemeAccent}${ThemeBold}|${ThemeReset}"
    Write-Host "  ${ThemeAccent}${ThemeBold}+$("=" * $width)+${ThemeReset}"
    Write-Host "  ${ThemeDim}  W/A/S/D or Arrow Keys to move${ThemeReset}"
    Write-Host "  ${ThemeDim}  Q to quit${ThemeReset}"
    Write-Host ""
}

function New-Point {
    param(
        [int]$X,
        [int]$Y
    )

    [PSCustomObject]@{
        X = $X
        Y = $Y
    }
}

function Test-PointEqual {
    param(
        $A,
        $B
    )

    return ($A.X -eq $B.X -and $A.Y -eq $B.Y)
}

function Get-RandomFood {
    param($Snake)

    while ($true) {
        $x = Get-Random -Minimum 1 -Maximum ($BoardWidth - 1)
        $y = Get-Random -Minimum 1 -Maximum ($BoardHeight - 1)

        $candidate = New-Point -X $x -Y $y

        $occupied = $false
        foreach ($segment in $Snake) {
            if (Test-PointEqual $candidate $segment) {
                $occupied = $true
                break
            }
        }

        if (-not $occupied) {
            return $candidate
        }
    }
}

function Draw-Game {
    param(
        $Snake,
        $Food,
        [int]$Score,
        [int]$Level
    )

    [Console]::SetCursorPosition(0, 0)

    Show-Header
    Write-Host "  ${ThemeSuccess}Score:${ThemeReset} $Score   ${ThemeSecondary}Level:${ThemeReset} $Level"
    Write-Host ""

    for ($y = 0; $y -le $BoardHeight; $y++) {
        Write-Host -NoNewline "  "

        for ($x = 0; $x -le $BoardWidth; $x++) {
            $isWall = (
                $x -eq 0 -or
                $x -eq $BoardWidth -or
                $y -eq 0 -or
                $y -eq $BoardHeight
            )

            if ($isWall) {
                Write-Host -NoNewline "${ThemeAccent}${WallChar}${ThemeReset}"
                continue
            }

            $point = New-Point -X $x -Y $y

            if (Test-PointEqual $point $Food) {
                Write-Host -NoNewline "${ThemeError}${FoodChar}${ThemeReset}"
                continue
            }

            $snakeIndex = -1
            for ($i = 0; $i -lt $Snake.Count; $i++) {
                if (Test-PointEqual $point $Snake[$i]) {
                    $snakeIndex = $i
                    break
                }
            }

            if ($snakeIndex -ge 0) {
                if ($snakeIndex -eq 0) {
                    Write-Host -NoNewline "${ThemeTitle}${SnakeChar}${ThemeReset}"
                }
                else {
                    Write-Host -NoNewline "${ThemeSuccess}${SnakeChar}${ThemeReset}"
                }
            }
            else {
                Write-Host -NoNewline $EmptyChar
            }
        }

        Write-Host ""
    }
}

function Show-GameOver {
    param([int]$Score)

    Write-Host ""
    Write-Host "  ${ThemeError}${ThemeBold}Game Over${ThemeReset}"
    Write-Host "  ${ThemeText}Final Score:${ThemeReset} $Score"
    Write-Host ""
    Write-Host -NoNewline "  ${ThemeMuted}Press Enter to exit...${ThemeReset}"
    Read-Host | Out-Null
}

try {
    Clear-Host

    $snake = New-Object System.Collections.ArrayList
    [void]$snake.Add((New-Point -X 5 -Y 5))
    [void]$snake.Add((New-Point -X 4 -Y 5))
    [void]$snake.Add((New-Point -X 3 -Y 5))

    $direction     = "Right"
    $nextDirection = "Right"

    $food  = Get-RandomFood -Snake $snake
    $score = 0
    $level = 1

    while ($true) {
        # ── Input ─────────────────────────────────────────────
        while ([Console]::KeyAvailable) {
            $key = [Console]::ReadKey($true)

            switch ($key.Key) {
                "UpArrow" {
                    if ($direction -ne "Down") { $nextDirection = "Up" }
                }
                "DownArrow" {
                    if ($direction -ne "Up") { $nextDirection = "Down" }
                }
                "LeftArrow" {
                    if ($direction -ne "Right") { $nextDirection = "Left" }
                }
                "RightArrow" {
                    if ($direction -ne "Left") { $nextDirection = "Right" }
                }
                "W" {
                    if ($direction -ne "Down") { $nextDirection = "Up" }
                }
                "S" {
                    if ($direction -ne "Up") { $nextDirection = "Down" }
                }
                "A" {
                    if ($direction -ne "Right") { $nextDirection = "Left" }
                }
                "D" {
                    if ($direction -ne "Left") { $nextDirection = "Right" }
                }
                "Q" {
                    return
                }
            }
        }

        $direction = $nextDirection

        # ── Move head ─────────────────────────────────────────
        $head = $snake[0]
        $newHead = New-Point -X $head.X -Y $head.Y

        switch ($direction) {
            "Up"    { $newHead.Y-- }
            "Down"  { $newHead.Y++ }
            "Left"  { $newHead.X-- }
            "Right" { $newHead.X++ }
        }

        # ── Collision: wall ───────────────────────────────────
        if (
            $newHead.X -le 0 -or
            $newHead.X -ge $BoardWidth -or
            $newHead.Y -le 0 -or
            $newHead.Y -ge $BoardHeight
        ) {
            Draw-Game -Snake $snake -Food $food -Score $score -Level $level
            Show-GameOver -Score $score
            break
        }

        # ── Collision: self ───────────────────────────────────
        foreach ($segment in $snake) {
            if (Test-PointEqual $newHead $segment) {
                Draw-Game -Snake $snake -Food $food -Score $score -Level $level
                Show-GameOver -Score $score
                break 2
            }
        }

        [void]$snake.Insert(0, $newHead)

        # ── Food / growth / speed ─────────────────────────────
        if (Test-PointEqual $newHead $food) {
            $score += 10
            $level = [math]::Floor($score / 50) + 1

            # Speed up gradually while keeping the game playable.
            $TickMs = [math]::Max(60, 120 - (($level - 1) * 8))
            $food = Get-RandomFood -Snake $snake
        }
        else {
            $snake.RemoveAt($snake.Count - 1)
        }

        Draw-Game -Snake $snake -Food $food -Score $score -Level $level
        Start-Sleep -Milliseconds $TickMs
    }
}
finally {
    [Console]::CursorVisible = $true
    [Console]::TreatControlCAsInput = $originalTreatControlCAsInput
}
