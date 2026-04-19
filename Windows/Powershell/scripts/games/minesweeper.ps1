#--------------------------------------------
# file:     minesweeper.ps1
# author:   Mike Redd
# version:  1.0
# created:  2026-03-30
# updated:  2026-03-30
# desc:     Minesweeper for PowerShell
#--------------------------------------------

$ScriptName    = "Minesweeper"
$ScriptVersion = "1.0"
$ScriptAuthor  = "Mike Redd"

# ----- ANSI -----
$ESC = [char]27
function C($code) { return "$ESC[${code}m" }

$R   = C "0"; $B   = C "1"; $DIM = C "2"
$CYN = C "96"; $YLW = C "93"; $GRN = C "92"
$RED = C "91"; $GRY = C "90"; $WHT = C "97"
$MAG = C "95"; $BLU = C "94"

function Show-Header {
    Write-Host "  ${CYN}${B}+======================================+${R}"
    Write-Host "  ${CYN}${B}|${R}  ${YLW}${B}$ScriptName${R} v$ScriptVersion$((" " * (18 - $ScriptVersion.Length)))${CYN}${B}|${R}"
    Write-Host "  ${CYN}${B}+======================================+${R}"
    Write-Host "  ${DIM}  Arrows or WASD move${R}"
    Write-Host "  ${DIM}  Space/Enter reveal  F flag  Q quit${R}"
    Write-Host ""
}

function New-Cell {
    [PSCustomObject]@{
        Mine     = $false
        Revealed = $false
        Flagged  = $false
        Adjacent = 0
    }
}

function Initialize-Board {
    param(
        [int]$Width,
        [int]$Height,
        [int]$MineCount
    )

    $board = @()
    for ($y = 0; $y -lt $Height; $y++) {
        $row = @()
        for ($x = 0; $x -lt $Width; $x++) {
            $row += New-Cell
        }
        $board += ,$row
    }

    $placed = 0
    while ($placed -lt $MineCount) {
        $mx = Get-Random -Minimum 0 -Maximum $Width
        $my = Get-Random -Minimum 0 -Maximum $Height

        if (-not $board[$my][$mx].Mine) {
            $board[$my][$mx].Mine = $true
            $placed++
        }
    }

    for ($y = 0; $y -lt $Height; $y++) {
        for ($x = 0; $x -lt $Width; $x++) {
            if ($board[$y][$x].Mine) { continue }

            $count = 0
            foreach ($n in Get-Neighbors -X $x -Y $y -Width $Width -Height $Height) {
                if ($board[$n.Y][$n.X].Mine) { $count++ }
            }
            $board[$y][$x].Adjacent = $count
        }
    }

    return ,$board
}

function Get-Neighbors {
    param(
        [int]$X,
        [int]$Y,
        [int]$Width,
        [int]$Height
    )

    $neighbors = @()

    for ($dy = -1; $dy -le 1; $dy++) {
        for ($dx = -1; $dx -le 1; $dx++) {
            if ($dx -eq 0 -and $dy -eq 0) { continue }

            $nx = $X + $dx
            $ny = $Y + $dy

            if ($nx -ge 0 -and $nx -lt $Width -and $ny -ge 0 -and $ny -lt $Height) {
                $neighbors += [PSCustomObject]@{ X = $nx; Y = $ny }
            }
        }
    }

    return $neighbors
}

function Reveal-Cell {
    param(
        [array]$Board,
        [int]$X,
        [int]$Y,
        [int]$Width,
        [int]$Height
    )

    $cell = $Board[$Y][$X]

    if ($cell.Revealed -or $cell.Flagged) { return }
    $cell.Revealed = $true

    if ($cell.Mine) { return }

    if ($cell.Adjacent -eq 0) {
        foreach ($n in Get-Neighbors -X $X -Y $Y -Width $Width -Height $Height) {
            if (-not $Board[$n.Y][$n.X].Revealed) {
                Reveal-Cell -Board $Board -X $n.X -Y $n.Y -Width $Width -Height $Height
            }
        }
    }
}

function Reveal-All-Mines {
    param([array]$Board, [int]$Width, [int]$Height)

    for ($y = 0; $y -lt $Height; $y++) {
        for ($x = 0; $x -lt $Width; $x++) {
            if ($Board[$y][$x].Mine) {
                $Board[$y][$x].Revealed = $true
            }
        }
    }
}

function Test-Win {
    param([array]$Board, [int]$Width, [int]$Height, [int]$MineCount)

    $revealedSafe = 0
    for ($y = 0; $y -lt $Height; $y++) {
        for ($x = 0; $x -lt $Width; $x++) {
            $cell = $Board[$y][$x]
            if ($cell.Revealed -and -not $cell.Mine) {
                $revealedSafe++
            }
        }
    }

    return ($revealedSafe -eq (($Width * $Height) - $MineCount))
}

function Get-NumberColor {
    param([int]$Number)

    switch ($Number) {
        1 { return $BLU }
        2 { return $GRN }
        3 { return $RED }
        4 { return $MAG }
        5 { return $YLW }
        6 { return $CYN }
        7 { return $WHT }
        8 { return $GRY }
        default { return $WHT }
    }
}

function Draw-Board {
    param(
        [array]$Board,
        [int]$Width,
        [int]$Height,
        [int]$CursorX,
        [int]$CursorY,
        [int]$MineCount,
        [string]$Status
    )

    [Console]::SetCursorPosition(0,0)
    Show-Header

    $flagCount = 0
    for ($y = 0; $y -lt $Height; $y++) {
        for ($x = 0; $x -lt $Width; $x++) {
            if ($Board[$y][$x].Flagged) { $flagCount++ }
        }
    }

    Write-Host "  ${GRN}Mines:${R} $MineCount   ${YLW}Flags:${R} $flagCount   ${MAG}Status:${R} $Status"
    Write-Host ""

    Write-Host -NoNewline "    "
    for ($x = 0; $x -lt $Width; $x++) {
        Write-Host -NoNewline ("{0,2} " -f $x)
    }
    Write-Host ""

    for ($y = 0; $y -lt $Height; $y++) {
        Write-Host -NoNewline ("  {0,2} " -f $y)

        for ($x = 0; $x -lt $Width; $x++) {
            $cell = $Board[$y][$x]
            $isCursor = ($x -eq $CursorX -and $y -eq $CursorY)

            if ($cell.Revealed) {
                if ($cell.Mine) {
                    $text = "${RED}${B}*${R}"
                } elseif ($cell.Adjacent -eq 0) {
                    $text = "${DIM}.${R}"
                } else {
                    $color = Get-NumberColor $cell.Adjacent
                    $text = "${color}$($cell.Adjacent)${R}"
                }
            } else {
                if ($cell.Flagged) {
                    $text = "${YLW}${B}F${R}"
                } else {
                    $text = "${GRY}#${R}"
                }
            }

            if ($isCursor) {
                Write-Host -NoNewline "${CYN}[${R}$text${CYN}]${R}"
            } else {
                Write-Host -NoNewline " $text "
            }
        }

        Write-Host ""
    }
}

function Start-Game {
    param(
        [int]$Width,
        [int]$Height,
        [int]$MineCount
    )

    $board = Initialize-Board -Width $Width -Height $Height -MineCount $MineCount
    $cursorX = 0
    $cursorY = 0
    $status = "Playing"
    $running = $true
    $gameOver = $false

    while ($running) {
        Draw-Board -Board $board -Width $Width -Height $Height -CursorX $cursorX -CursorY $cursorY -MineCount $MineCount -Status $status

        $key = [Console]::ReadKey($true)

        if ($gameOver) {
            switch ($key.Key) {
                ([ConsoleKey]::R) { return "Restart" }
                ([ConsoleKey]::Q) { return "Quit" }
                default { continue }
            }
        }

        switch ($key.Key) {
            ([ConsoleKey]::LeftArrow)  { if ($cursorX -gt 0) { $cursorX-- } }
            ([ConsoleKey]::RightArrow) { if ($cursorX -lt ($Width - 1)) { $cursorX++ } }
            ([ConsoleKey]::UpArrow)    { if ($cursorY -gt 0) { $cursorY-- } }
            ([ConsoleKey]::DownArrow)  { if ($cursorY -lt ($Height - 1)) { $cursorY++ } }

            ([ConsoleKey]::A) { if ($cursorX -gt 0) { $cursorX-- } }
            ([ConsoleKey]::D) { if ($cursorX -lt ($Width - 1)) { $cursorX++ } }
            ([ConsoleKey]::W) { if ($cursorY -gt 0) { $cursorY-- } }
            ([ConsoleKey]::S) { if ($cursorY -lt ($Height - 1)) { $cursorY++ } }

            ([ConsoleKey]::F) {
                $cell = $board[$cursorY][$cursorX]
                if (-not $cell.Revealed) {
                    $cell.Flagged = -not $cell.Flagged
                }
            }

            ([ConsoleKey]::Spacebar) {
                $cell = $board[$cursorY][$cursorX]
                if (-not $cell.Flagged -and -not $cell.Revealed) {
                    Reveal-Cell -Board $board -X $cursorX -Y $cursorY -Width $Width -Height $Height

                    if ($board[$cursorY][$cursorX].Mine) {
                        Reveal-All-Mines -Board $board -Width $Width -Height $Height
                        $status = "Game Over - R restart / Q quit"
                        $gameOver = $true
                    } elseif (Test-Win -Board $board -Width $Width -Height $Height -MineCount $MineCount) {
                        $status = "You Win - R restart / Q quit"
                        $gameOver = $true
                    }
                }
            }

            ([ConsoleKey]::Enter) {
                $cell = $board[$cursorY][$cursorX]
                if (-not $cell.Flagged -and -not $cell.Revealed) {
                    Reveal-Cell -Board $board -X $cursorX -Y $cursorY -Width $Width -Height $Height

                    if ($board[$cursorY][$cursorX].Mine) {
                        Reveal-All-Mines -Board $board -Width $Width -Height $Height
                        $status = "Game Over - R restart / Q quit"
                        $gameOver = $true
                    } elseif (Test-Win -Board $board -Width $Width -Height $Height -MineCount $MineCount) {
                        $status = "You Win - R restart / Q quit"
                        $gameOver = $true
                    }
                }
            }

            ([ConsoleKey]::Q) { return "Quit" }
        }
    }
}

function Select-Difficulty {
    while ($true) {
        Clear-Host
        Show-Header
        Write-Host "  ${MAG}${B}Difficulty${R}"
        Write-Host ""
        Write-Host "  ${GRN}1)${R} Small   (9x9 / 10 mines)"
        Write-Host "  ${GRN}2)${R} Medium  (12x12 / 20 mines)"
        Write-Host "  ${GRN}3)${R} Large   (16x16 / 40 mines)"
        Write-Host ""
        Write-Host "  ${GRY}Q)${R} Quit"
        Write-Host ""
        Write-Host -NoNewline "  ${YLW}${B}Choice:${R} "

        $choice = Read-Host

        switch ($choice.ToUpper()) {
            "1" { return @{ Width = 9;  Height = 9;  Mines = 10 } }
            "2" { return @{ Width = 12; Height = 12; Mines = 20 } }
            "3" { return @{ Width = 16; Height = 16; Mines = 40 } }
            "Q" { return $null }
        }
    }
}

try {
    [Console]::CursorVisible = $false
} catch {}

while ($true) {
    $difficulty = Select-Difficulty
    if (-not $difficulty) { break }

    $result = Start-Game -Width $difficulty.Width -Height $difficulty.Height -MineCount $difficulty.Mines
    if ($result -eq "Quit") { break }
}

try {
    [Console]::CursorVisible = $true
} catch {}