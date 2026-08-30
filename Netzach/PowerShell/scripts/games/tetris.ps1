#--------------------------------------------
# file:     tetris.ps1
# author:   Mike Redd
# version:  1.9
# created:  2026-03-30
# updated:  2026-03-30
# desc:     Tetris - PowerShell Edition
#--------------------------------------------

$ScriptName    = "TETRIS - PowerShell Edition"
$ScriptVersion = "1.9"
$ScriptAuthor  = "Mike Redd"

$ESC = [char]27
function C($code) { return "$ESC[${code}m" }

# Color palette matching the script suite
$R   = C "0";   $B   = C "1";   $DIM = C "2"
$CYN = C "96";  $YLW = C "93";  $GRN = C "92"
$RED = C "91";  $MAG = C "95";  $BLU = C "94"
$WHT = C "97";  $GRY = C "90";  $ORG = C "33"

# Piece colors (ANSI background + foreground for block rendering)
$PIECE_COLORS = @{
    "I" = "$ESC[96m"   # Cyan
    "O" = "$ESC[93m"   # Yellow
    "T" = "$ESC[95m"   # Magenta
    "S" = "$ESC[92m"   # Green
    "Z" = "$ESC[91m"   # Red
    "J" = "$ESC[94m"   # Blue
    "L" = "$ESC[33m"   # Orange
}

# ── Board dimensions ──────────────────────────────────────────
$BOARD_W  = 10
$BOARD_H  = 20
$BLOCK    = "[]"   # Two chars per cell

# ── Tetromino definitions (rotations as [row][col] offsets) ──
$PIECES = @{
    "I" = @(
        @(@(0,0),@(0,1),@(0,2),@(0,3)),
        @(@(0,0),@(1,0),@(2,0),@(3,0)),
        @(@(0,0),@(0,1),@(0,2),@(0,3)),
        @(@(0,0),@(1,0),@(2,0),@(3,0))
    )
    "O" = @(
        @(@(0,0),@(0,1),@(1,0),@(1,1)),
        @(@(0,0),@(0,1),@(1,0),@(1,1)),
        @(@(0,0),@(0,1),@(1,0),@(1,1)),
        @(@(0,0),@(0,1),@(1,0),@(1,1))
    )
    "T" = @(
        @(@(0,1),@(1,0),@(1,1),@(1,2)),
        @(@(0,0),@(1,0),@(1,1),@(2,0)),
        @(@(1,0),@(1,1),@(1,2),@(2,1)),
        @(@(0,1),@(1,0),@(1,1),@(2,1))
    )
    "S" = @(
        @(@(0,1),@(0,2),@(1,0),@(1,1)),
        @(@(0,0),@(1,0),@(1,1),@(2,1)),
        @(@(0,1),@(0,2),@(1,0),@(1,1)),
        @(@(0,0),@(1,0),@(1,1),@(2,1))
    )
    "Z" = @(
        @(@(0,0),@(0,1),@(1,1),@(1,2)),
        @(@(0,1),@(1,0),@(1,1),@(2,0)),
        @(@(0,0),@(0,1),@(1,1),@(1,2)),
        @(@(0,1),@(1,0),@(1,1),@(2,0))
    )
    "J" = @(
        @(@(0,0),@(1,0),@(1,1),@(1,2)),
        @(@(0,0),@(0,1),@(1,0),@(2,0)),
        @(@(1,0),@(1,1),@(1,2),@(2,2)),
        @(@(0,1),@(1,1),@(2,0),@(2,1))
    )
    "L" = @(
        @(@(0,2),@(1,0),@(1,1),@(1,2)),
        @(@(0,0),@(1,0),@(2,0),@(2,1)),
        @(@(1,0),@(1,1),@(1,2),@(2,0)),
        @(@(0,0),@(0,1),@(1,1),@(2,1))
    )
}

$PIECE_TYPES = @("I","O","T","S","Z","J","L")

# ── Cursor movement helpers ───────────────────────────────────
function Move-Cursor($row, $col) {
    Write-Host -NoNewline "$ESC[${row};${col}H"
}

function Hide-Cursor { Write-Host -NoNewline "$ESC[?25l" }
function Show-Cursor { Write-Host -NoNewline "$ESC[?25h" }
function Clear-Screen { Write-Host -NoNewline "$ESC[2J$ESC[H" }

# ── Game state ────────────────────────────────────────────────
function New-Board {
    $board = New-Object 'string[,]' $BOARD_H, $BOARD_W
    for ($i = 0; $i -lt $BOARD_H; $i++) {
        for ($j = 0; $j -lt $BOARD_W; $j++) {
            $board[$i,$j] = ""
        }
    }
    return $board
}

function New-Piece {
    $type = $PIECE_TYPES[(Get-Random -Maximum $PIECE_TYPES.Count)]
    return @{
        Type    = $type
        Rot     = 0
        Row     = 0
        Col     = 3
        Color   = $PIECE_COLORS[$type]
    }
}

function Get-Cells($piece) {
    return $PIECES[$piece.Type][$piece.Rot]
}

function Get-AbsCells($piece) {
    $cells = Get-Cells $piece
    $absCells = New-Object System.Collections.ArrayList

    foreach ($offset in $cells) {
        [void]$absCells.Add([PSCustomObject]@{
            Row = [int]$piece.Row + [int]$offset[0]
            Col = [int]$piece.Col + [int]$offset[1]
        })
    }

    return $absCells
}

function Test-Valid($board, $piece) {
    $cells = Get-AbsCells $piece
    foreach ($cell in $cells) {
        $testRow = $cell.Row
        $testCol = $cell.Col

        if ($testRow -lt 0 -or $testRow -ge $BOARD_H) { return $false }
        if ($testCol -lt 0 -or $testCol -ge $BOARD_W) { return $false }
        if ($board[$testRow][$testCol] -ne "") { return $false }   # ← changed
    }
    return $true
}

function Lock-Piece($board, $piece) {
    $cells = Get-AbsCells $piece
    foreach ($cell in $cells) {
        $board[$cell.Row][$cell.Col] = $piece.Color   # ← changed
    }
}

function Clear-Lines($board) {
    $cleared = 0
    $newBoard = New-Object object[] $BOARD_H
    for ($i = 0; $i -lt $BOARD_H; $i++) {
        $newBoard[$i] = New-Object string[] $BOARD_W
    }

    $writeRow = $BOARD_H - 1

    for ($i = $BOARD_H - 1; $i -ge 0; $i--) {
        $full = $true
        for ($j = 0; $j -lt $BOARD_W; $j++) {
            if ($board[$i][$j] -eq "") { $full = $false; break }   # ← changed
        }
        if (-not $full) {
            for ($j = 0; $j -lt $BOARD_W; $j++) {
                $newBoard[$writeRow][$j] = $board[$i][$j]           # ← changed
            }
            $writeRow--
        } else {
            $cleared++
        }
    }
    for ($i = $writeRow; $i -ge 0; $i--) {
        for ($j = 0; $j -lt $BOARD_W; $j++) {
            $newBoard[$i][$j] = ""                                  # ← changed
        }
    }
    return @{ Board = $newBoard; Cleared = $cleared }
}

function Draw-Board($board) {
    for ($boardRow = 0; $boardRow -lt $BOARD_H; $boardRow++) {
        $row = $BOARD_TOP + 1 + $boardRow
        Move-Cursor $row ($BOARD_LEFT + 1)
        $line = ""
        for ($col = 0; $col -lt $BOARD_W; $col++) {
            if ($board[$boardRow][$col] -ne "") {                   # ← changed
                $line += "$($board[$boardRow][$col])${B}$BLOCK${R}"
            } else {
                $line += "${GRY}..${R}"
            }
        }
        Write-Host -NoNewline $line
    }
}

# ── Layout constants (1-indexed for ANSI) ────────────────────
$BOARD_LEFT   = 4
$BOARD_TOP    = 4
$PANEL_LEFT   = 28

# ── Drawing ───────────────────────────────────────────────────
function Draw-StaticUI {
    Clear-Screen

    # Title
    Move-Cursor 1 1
    Write-Host "  ${CYN}${B}+================================================+${R}"
    Move-Cursor 2 1
    Write-Host "  ${CYN}${B}|${R}        ${YLW}${B}$ScriptName v$ScriptVersion ${CYN}${B}       ${R}${CYN}${B}|${R}"
    Move-Cursor 3 1
    Write-Host "  ${CYN}${B}+================================================+${R}"

    # Board border top
    Move-Cursor $BOARD_TOP 1
    Write-Host -NoNewline "   ${CYN}${B}+"
    Write-Host -NoNewline ("=" * ($BOARD_W * 2))
    Write-Host -NoNewline "+${R}"

    # Board border sides
    for ($boardRow = 0; $boardRow -lt $BOARD_H; $boardRow++) {
        $row = $BOARD_TOP + 1 + $boardRow
        Move-Cursor $row 1
        Write-Host -NoNewline "   ${CYN}${B}|${R}"
        Move-Cursor $row ($BOARD_LEFT + $BOARD_W * 2 + 1)
        Write-Host -NoNewline "${CYN}${B}|${R}"
    }

    # Board border bottom
    $botRow = $BOARD_TOP + $BOARD_H + 1
    Move-Cursor $botRow 1
    Write-Host -NoNewline "   ${CYN}${B}+"
    Write-Host -NoNewline ("=" * ($BOARD_W * 2))
    Write-Host -NoNewline "+${R}"

    # Panel labels
    Move-Cursor ($BOARD_TOP)     $PANEL_LEFT; Write-Host "${CYN}${B}+====================+${R}"
    Move-Cursor ($BOARD_TOP + 1) $PANEL_LEFT; Write-Host "${CYN}${B}|${R}  ${YLW}${B}NEXT PIECE${R}        ${CYN}${B}|${R}"
    Move-Cursor ($BOARD_TOP + 2) $PANEL_LEFT; Write-Host "${CYN}${B}|${R}                    ${CYN}${B}|${R}"
    Move-Cursor ($BOARD_TOP + 3) $PANEL_LEFT; Write-Host "${CYN}${B}|${R}                    ${CYN}${B}|${R}"
    Move-Cursor ($BOARD_TOP + 4) $PANEL_LEFT; Write-Host "${CYN}${B}|${R}                    ${CYN}${B}|${R}"
    Move-Cursor ($BOARD_TOP + 5) $PANEL_LEFT; Write-Host "${CYN}${B}|${R}                    ${CYN}${B}|${R}"
    Move-Cursor ($BOARD_TOP + 6) $PANEL_LEFT; Write-Host "${CYN}${B}+====================+${R}"

    Move-Cursor ($BOARD_TOP + 8)  $PANEL_LEFT; Write-Host "${CYN}${B}+====================+${R}"
    Move-Cursor ($BOARD_TOP + 9)  $PANEL_LEFT; Write-Host "${CYN}${B}|${R}  ${WHT}${B}SCORE${R}             ${CYN}${B}|${R}"
    Move-Cursor ($BOARD_TOP + 10) $PANEL_LEFT; Write-Host "${CYN}${B}|${R}  ${GRN}                  ${R}${CYN}${B}|${R}"
    Move-Cursor ($BOARD_TOP + 11) $PANEL_LEFT; Write-Host "${CYN}${B}+====================+${R}"
    Move-Cursor ($BOARD_TOP + 12) $PANEL_LEFT; Write-Host "${CYN}${B}|${R}  ${WHT}${B}LEVEL${R}             ${CYN}${B}|${R}"
    Move-Cursor ($BOARD_TOP + 13) $PANEL_LEFT; Write-Host "${CYN}${B}|${R}  ${YLW}                  ${R}${CYN}${B}|${R}"
    Move-Cursor ($BOARD_TOP + 14) $PANEL_LEFT; Write-Host "${CYN}${B}+====================+${R}"
    Move-Cursor ($BOARD_TOP + 15) $PANEL_LEFT; Write-Host "${CYN}${B}|${R}  ${WHT}${B}LINES${R}             ${CYN}${B}|${R}"
    Move-Cursor ($BOARD_TOP + 16) $PANEL_LEFT; Write-Host "${CYN}${B}|${R}  ${MAG}                  ${R}${CYN}${B}|${R}"
    Move-Cursor ($BOARD_TOP + 17) $PANEL_LEFT; Write-Host "${CYN}${B}+====================+${R}"

    # Controls
    Move-Cursor ($BOARD_TOP + 19) $PANEL_LEFT; Write-Host "${GRY}  LEFT/RIGHT  Move${R}"
    Move-Cursor ($BOARD_TOP + 20) $PANEL_LEFT; Write-Host "${GRY}  UP          Rotate${R}"
    Move-Cursor ($BOARD_TOP + 21) $PANEL_LEFT; Write-Host "${GRY}  DOWN        Soft drop${R}"
    Move-Cursor ($BOARD_TOP + 22) $PANEL_LEFT; Write-Host "${GRY}  SPACE       Hard drop${R}"
    Move-Cursor ($BOARD_TOP + 23) $PANEL_LEFT; Write-Host "${GRY}  P           Pause${R}"
    Move-Cursor ($BOARD_TOP + 24) $PANEL_LEFT; Write-Host "${GRY}  Q           Quit${R}"
}

# ── Board (now jagged array - fixes the slice error) ─────────────
function New-Board {
    $board = New-Object object[] $BOARD_H
    for ($i = 0; $i -lt $BOARD_H; $i++) {
        $board[$i] = New-Object string[] $BOARD_W
        for ($j = 0; $j -lt $BOARD_W; $j++) {
            $board[$i][$j] = ""
        }
    }
    return $board
}

function Draw-Piece($piece, $erase = $false) {
    $cells = Get-AbsCells $piece
    foreach ($cell in $cells) {
        $pieceRow = $cell.Row          # ← fixed
        $pieceCol = $cell.Col          # ← fixed

        if ($pieceRow -ge 0 -and $pieceRow -lt $BOARD_H -and $pieceCol -ge 0 -and $pieceCol -lt $BOARD_W) {
            $row = $BOARD_TOP + 1 + $pieceRow
            $col = $BOARD_LEFT + 1 + $pieceCol * 2
            Move-Cursor $row $col
            if ($erase) {
                Write-Host -NoNewline "${GRY}..${R}"
            } else {
                Write-Host -NoNewline "$($piece.Color)${B}$BLOCK${R}"
            }
        }
    }
}

function Draw-Ghost($board, $piece) {
    $dropRow = $piece.Row
    while ($true) {
        $testRow = $dropRow + 1
        $test = @{
            Type  = $piece.Type
            Rot   = $piece.Rot
            Row   = $testRow
            Col   = $piece.Col
            Color = $piece.Color
        }
        if (Test-Valid $board $test) {
            $dropRow = $testRow
        } else {
            break
        }
    }

    $ghostPiece = @{
        Type  = $piece.Type
        Rot   = $piece.Rot
        Row   = $dropRow
        Col   = $piece.Col
        Color = $piece.Color
    }

    if ($dropRow -ne $piece.Row) {
        $cells = Get-AbsCells $ghostPiece
        foreach ($cell in $cells) {
            $pieceRow = $cell.Row      # ← fixed
            $pieceCol = $cell.Col      # ← fixed

            if ($pieceRow -ge 0 -and $pieceRow -lt $BOARD_H) {
                $row = $BOARD_TOP + 1 + $pieceRow
                $col = $BOARD_LEFT + 1 + $pieceCol * 2
                Move-Cursor $row $col
                Write-Host -NoNewline "${GRY}${DIM}[]${R}"
            }
        }
    }
    return $ghostPiece
}

function Erase-Ghost($ghost) {
    $cells = Get-AbsCells $ghost
    foreach ($cell in $cells) {
        $pieceRow = $cell.Row          # ← fixed
        $pieceCol = $cell.Col          # ← fixed

        if ($pieceRow -ge 0 -and $pieceRow -lt $BOARD_H) {
            $row = $BOARD_TOP + 1 + $pieceRow
            $col = $BOARD_LEFT + 1 + $pieceCol * 2
            Move-Cursor $row $col
            Write-Host -NoNewline "${GRY}..${R}"
        }
    }
}

function Draw-NextPiece($piece) {
    for ($i = 0; $i -lt 4; $i++) {
        Move-Cursor ($BOARD_TOP + 2 + $i) ($PANEL_LEFT + 2)
        Write-Host -NoNewline "                  "
    }
    $cells = $PIECES[$piece.Type][0]
    foreach ($cell in $cells) {
        $pieceRow = $cell[0]; $pieceCol = $cell[1]
        Move-Cursor ($BOARD_TOP + 2 + $pieceRow) ($PANEL_LEFT + 4 + $pieceCol * 2)
        Write-Host -NoNewline "$($piece.Color)${B}$BLOCK${R}"
    }
}

function Update-Score($score, $level, $lines) {
    Move-Cursor ($BOARD_TOP + 10) ($PANEL_LEFT + 2)
    Write-Host -NoNewline "${GRN}${B}$("$score".PadRight(18))${R}"
    Move-Cursor ($BOARD_TOP + 13) ($PANEL_LEFT + 2)
    Write-Host -NoNewline "${YLW}${B}$("$level".PadRight(18))${R}"
    Move-Cursor ($BOARD_TOP + 16) ($PANEL_LEFT + 2)
    Write-Host -NoNewline "${MAG}${B}$("$lines".PadRight(18))${R}"
}

function Flash-Lines($board, $fullRows) {
    for ($flash = 0; $flash -lt 3; $flash++) {
        foreach ($fullRow in $fullRows) {
            $row = $BOARD_TOP + 1 + $fullRow
            Move-Cursor $row ($BOARD_LEFT + 1)
            if ($flash % 2 -eq 0) {
                Write-Host -NoNewline "${WHT}${B}$("[]" * $BOARD_W)${R}"
            } else {
                Write-Host -NoNewline "${CYN}${B}$("[]" * $BOARD_W)${R}"
            }
        }
        Start-Sleep -Milliseconds 80
    }
}

function Show-Pause {
    $midRow = $BOARD_TOP + $BOARD_H / 2
    $midCol = $BOARD_LEFT + 1
    Move-Cursor $midRow     $midCol; Write-Host "${YLW}${B}   *** PAUSED ***    ${R}"
    Move-Cursor ($midRow+1) $midCol; Write-Host "${GRY}   Press P to resume ${R}"
}

function Show-GameOver($score, $level, $lines) {
    Clear-Screen
    $msg = @(
        "",
        "  ${CYN}${B}+============================================+${R}",
        "  ${CYN}${B}|${R}${RED}${B}              G A M E  O V E R              ${R}${CYN}${B}|${R}",
        "  ${CYN}${B}+============================================+${R}",
        "",
        "  ${DIM}${WHT}  Score       ${R}  ${GRN}${B}$score${R}",
        "  ${DIM}${WHT}  Level       ${R}  ${YLW}${B}$level${R}",
        "  ${DIM}${WHT}  Lines       ${R}  ${MAG}${B}$lines${R}",
        "",
        "  ${GRY}  Press R to play again or Q to quit${R}",
        ""
    )
    Move-Cursor 5 1
    $msg | ForEach-Object { Write-Host $_ }
}

# ── Score calculation ─────────────────────────────────────────
function Calc-Score($cleared, $level) {
    switch ($cleared) {
        1 { return 100  * ($level + 1) }
        2 { return 300  * ($level + 1) }
        3 { return 500  * ($level + 1) }
        4 { return 800  * ($level + 1) }
        default { return 0 }
    }
}

# ── Fall speed by level (ms) ──────────────────────────────────
function Get-Speed($level) {
    $speeds = @(800,720,630,550,470,380,300,220,130,100,80,70,60,50,40,30)
    $idx = [Math]::Min($level, $speeds.Count - 1)
    return $speeds[$idx]
}

function Find-FullRows($board) {
    $rows = @()
    for ($i = 0; $i -lt $BOARD_H; $i++) {
        $full = $true
        for ($j = 0; $j -lt $BOARD_W; $j++) {
            if ($board[$i][$j] -eq "") { $full = $false; break }   # ← changed
        }
        if ($full) { $rows += $i }
    }
    return $rows
}

# ════════════════════════════════════════════════════════════
#  MAIN GAME LOOP
# ════════════════════════════════════════════════════════════
function Start-Tetris {
    Hide-Cursor
    $host.UI.RawUI.WindowTitle = "TETRIS - PowerShell Edition"

    :gameLoop while ($true) {

        # ── Init ─────────────────────────────────────────────
        $board    = New-Board
        $current  = New-Piece
        $next     = New-Piece
        $score    = 0
        $level    = 0
        $lines    = 0
        $paused   = $false
        $gameOver = $false
        $ghost    = $null

        Draw-StaticUI
        Draw-Board $board
        Draw-NextPiece $next
        Update-Score $score $level $lines

        $lastFall  = [DateTime]::UtcNow
        $fallSpeed = Get-Speed $level

        # Initial piece + ghost
        $ghost = Draw-Ghost $board $current
        Draw-Piece $current

        # ── Game tick loop ───────────────────────────────────
        while (-not $gameOver) {

            # ── Input ────────────────────────────────────────
            if ([Console]::KeyAvailable) {
                $key = [Console]::ReadKey($true)

                if ($paused) {
                    if ($key.Key -eq [ConsoleKey]::P) { 
                        $paused = $false
                        Draw-Board $board
                        $ghost = Draw-Ghost $board $current
                        Draw-Piece $current
                    }
                    continue
                }

                switch ($key.Key) {
                    ([ConsoleKey]::Q) {
                        Show-Cursor
                        Clear-Screen
                        Move-Cursor 1 1
                        Write-Host "  ${CYN}  Thanks for playing Tetris!${R}`n"
                        return
                    }
                    ([ConsoleKey]::P) {
                        $paused = $true
                        Show-Pause
                        continue
                    }
                    ([ConsoleKey]::LeftArrow) {
                        $moved = @{ Type=$current.Type; Rot=$current.Rot; Row=$current.Row; Col=$current.Col-1; Color=$current.Color }
                        if (Test-Valid $board $moved) {
                            if ($ghost -and $ghost.Row -ne $current.Row) { Erase-Ghost $ghost }
                            Draw-Piece $current $true
                            $current = $moved
                            $ghost = Draw-Ghost $board $current
                            Draw-Piece $current
                        }
                    }
                    ([ConsoleKey]::RightArrow) {
                        $moved = @{ Type=$current.Type; Rot=$current.Rot; Row=$current.Row; Col=$current.Col+1; Color=$current.Color }
                        if (Test-Valid $board $moved) {
                            if ($ghost -and $ghost.Row -ne $current.Row) { Erase-Ghost $ghost }
                            Draw-Piece $current $true
                            $current = $moved
                            $ghost = Draw-Ghost $board $current
                            Draw-Piece $current
                        }
                    }
                    ([ConsoleKey]::UpArrow) {
                        $newRot  = ($current.Rot + 1) % 4
                        $rotated = @{ Type=$current.Type; Rot=$newRot; Row=$current.Row; Col=$current.Col; Color=$current.Color }
                        $kicks = @(0, -1, 1, -2, 2)
                        foreach ($kick in $kicks) {
                            $testCol = $rotated.Col + $kick
                            $test = @{ Type=$rotated.Type; Rot=$rotated.Rot; Row=$rotated.Row; Col=$testCol; Color=$rotated.Color }
                            if (Test-Valid $board $test) {
                                if ($ghost -and $ghost.Row -ne $current.Row) { Erase-Ghost $ghost }
                                Draw-Piece $current $true
                                $current = $test
                                $ghost = Draw-Ghost $board $current
                                Draw-Piece $current
                                break
                            }
                        }
                    }
                    ([ConsoleKey]::DownArrow) {
                        $droppedRow = $current.Row + 1
                        $dropped = @{ Type=$current.Type; Rot=$current.Rot; Row=$droppedRow; Col=$current.Col; Color=$current.Color }
                        if (Test-Valid $board $dropped) {
                            if ($ghost -and $ghost.Row -ne $current.Row) { Erase-Ghost $ghost }
                            Draw-Piece $current $true
                            $current = $dropped
                            $ghost = Draw-Ghost $board $current
                            Draw-Piece $current
                            $lastFall = [DateTime]::UtcNow
                            $score += 1
                            Update-Score $score $level $lines
                        }
                    }
                    ([ConsoleKey]::Spacebar) {
                        # Hard drop
                        $dropDist = 0
                        $dropRow = $current.Row
                        while ($true) {
                            $testRow = $dropRow + 1
                            $test = @{
                                Type  = $current.Type
                                Rot   = $current.Rot
                                Row   = $testRow
                                Col   = $current.Col
                                Color = $current.Color
                            }
                            if (Test-Valid $board $test) {
                                $dropRow = $testRow
                                $dropDist++
                            } else {
                                break
                            }
                        }
                        $dropped = @{
                            Type  = $current.Type
                            Rot   = $current.Rot
                            Row   = $dropRow
                            Col   = $current.Col
                            Color = $current.Color
                        }

                        if ($ghost -and $ghost.Row -ne $current.Row) { Erase-Ghost $ghost }
                        Draw-Piece $current $true
                        $current = $dropped
                        Draw-Piece $current
                        $score += $dropDist * 2
                        Update-Score $score $level $lines

                        Lock-Piece $board $current
                        $fullRows = Find-FullRows $board
                        if ($fullRows.Count -gt 0) {
                            Flash-Lines $board $fullRows
                        }
                        $result  = Clear-Lines $board
                        $board   = $result.Board
                        $cleared = $result.Cleared
                        $lines  += $cleared
                        $score  += Calc-Score $cleared $level
                        $level   = [Math]::Floor($lines / 10)
                        $fallSpeed = Get-Speed $level
                        Update-Score $score $level $lines

                        Draw-Board $board

                        $current = $next
                        $next    = New-Piece
                        $ghost   = $null
                        Draw-NextPiece $next

                        if (-not (Test-Valid $board $current)) { $gameOver = $true }
                        else {
                            $ghost = Draw-Ghost $board $current
                            Draw-Piece $current
                        }
                        $lastFall = [DateTime]::UtcNow
                    }
                    ([ConsoleKey]::R) {
                        continue gameLoop
                    }
                }
            }

            # ── Gravity ──────────────────────────────────────
            $now = [DateTime]::UtcNow
            if (-not $paused -and ($now - $lastFall).TotalMilliseconds -ge $fallSpeed) {
                $droppedRow = $current.Row + 1
                $dropped = @{ Type=$current.Type; Rot=$current.Rot; Row=$droppedRow; Col=$current.Col; Color=$current.Color }

                if (Test-Valid $board $dropped) {
                    if ($ghost -and $ghost.Row -ne $current.Row) { Erase-Ghost $ghost }
                    Draw-Piece $current $true
                    $current = $dropped
                    $ghost = Draw-Ghost $board $current
                    Draw-Piece $current
                } else {
                    Draw-Piece $current
                    Lock-Piece $board $current

                    $fullRows = Find-FullRows $board
                    if ($fullRows.Count -gt 0) {
                        Flash-Lines $board $fullRows
                    }

                    $result  = Clear-Lines $board
                    $board   = $result.Board
                    $cleared = $result.Cleared
                    $lines  += $cleared
                    $score  += Calc-Score $cleared $level
                    $level   = [Math]::Floor($lines / 10)
                    $fallSpeed = Get-Speed $level
                    Update-Score $score $level $lines

                    Draw-Board $board

                    $current = $next
                    $next    = New-Piece
                    $ghost   = $null
                    Draw-NextPiece $next

                    if (-not (Test-Valid $board $current)) {
                        $gameOver = $true
                    } else {
                        $ghost = Draw-Ghost $board $current
                        Draw-Piece $current
                    }
                }
                $lastFall = [DateTime]::UtcNow
            }

            Start-Sleep -Milliseconds 16
        }

        # ── Game over ────────────────────────────────────────
        Show-GameOver $score $level $lines

        $waiting = $true
        while ($waiting) {
            if ([Console]::KeyAvailable) {
                $key = [Console]::ReadKey($true)
                switch ($key.Key) {
                    ([ConsoleKey]::R) { $waiting = $false }
                    ([ConsoleKey]::Q) {
                        Show-Cursor
                        Clear-Screen
                        Move-Cursor 1 1
                        Write-Host "  ${CYN}  Thanks for playing Tetris!${R}`n"
                        return
                    }
                }
            }
            Start-Sleep -Milliseconds 50
        }
    }

    Show-Cursor
}

# ── Launch ────────────────────────────────────────────────────
try {
    $minWidth  = 55
    $minHeight = 32
    $w = $host.UI.RawUI.WindowSize.Width
    $h = $host.UI.RawUI.WindowSize.Height
    if ($w -lt $minWidth -or $h -lt $minHeight) {
        try {
            $host.UI.RawUI.WindowSize = New-Object System.Management.Automation.Host.Size([Math]::Max($w,$minWidth), [Math]::Max($h,$minHeight))
        } catch {}
    }
    Start-Tetris
} finally {
    Show-Cursor
    [Console]::TreatControlCAsInput = $false
}