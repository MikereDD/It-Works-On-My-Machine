#--------------------------------------------
# file:     snake.ps1
# author:   Mike Redd
# version:  1.0
# created:  2026-03-30
# updated:  2026-03-30
# desc:     Simple Snake game for PowerShell
#--------------------------------------------

$ScriptName    = "Snake"
$ScriptVersion = "1.0"
$ScriptAuthor  = "Mike Redd"

# ----- ANSI -----
$ESC = [char]27
function C($code) { return "$ESC[${code}m" }

$R   = C "0"; $B   = C "1"; $DIM = C "2"
$CYN = C "96"; $YLW = C "93"; $GRN = C "92"
$RED = C "91"; $GRY = C "90"; $WHT = C "97"
$MAG = C "95"

# ----- GAME SETTINGS -----
$BoardWidth  = 20
$BoardHeight = 12
$TickMs      = 120

# Characters
$WallChar  = "██"
$SnakeChar = "██"
$FoodChar  = "██"
$EmptyChar = "  "

# ----- INPUT / CONSOLE SETUP -----
[Console]::CursorVisible = $false
$originalTreatControlCAsInput = [Console]::TreatControlCAsInput
[Console]::TreatControlCAsInput = $true

function Show-Header {
    Write-Host "  ${CYN}${B}+======================================+${R}"
    Write-Host "  ${CYN}${B}|${R}  ${YLW}${B}$ScriptName${R} v$ScriptVersion$((" " * (24 - $ScriptVersion.Length)))${CYN}${B}|${R}"
    Write-Host "  ${CYN}${B}+======================================+${R}"
    Write-Host "  ${DIM}  W/A/S/D or Arrow Keys to move${R}"
    Write-Host "  ${DIM}  Q to quit${R}"
    Write-Host ""
}

function New-Point {
    param([int]$X, [int]$Y)
    [PSCustomObject]@{ X = $X; Y = $Y }
}

function Test-PointEqual {
    param($A, $B)
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
    Write-Host "  ${GRN}Score:${R} $Score   ${MAG}Level:${R} $Level"
    Write-Host ""

    for ($y = 0; $y -le $BoardHeight; $y++) {
        Write-Host -NoNewline "  "

        for ($x = 0; $x -le $BoardWidth; $x++) {
            $isWall = ($x -eq 0 -or $x -eq $BoardWidth -or $y -eq 0 -or $y -eq $BoardHeight)

            if ($isWall) {
                Write-Host -NoNewline "${CYN}${WallChar}${R}"
                continue
            }

            $point = New-Point -X $x -Y $y

            if (Test-PointEqual $point $Food) {
                Write-Host -NoNewline "${RED}${FoodChar}${R}"
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
                    Write-Host -NoNewline "${YLW}${SnakeChar}${R}"
                } else {
                    Write-Host -NoNewline "${GRN}${SnakeChar}${R}"
                }
            } else {
                Write-Host -NoNewline $EmptyChar
            }
        }

        Write-Host ""
    }
}

function Show-GameOver {
    param([int]$Score)

    Write-Host ""
    Write-Host "  ${RED}${B}Game Over${R}"
    Write-Host "  ${WHT}Final Score:${R} $Score"
    Write-Host ""
    Write-Host "  ${GRY}Press Enter to exit...${R}"
    Read-Host | Out-Null
}

try {
    Clear-Host

    $snake = New-Object System.Collections.ArrayList
    [void]$snake.Add((New-Point -X 5 -Y 5))
    [void]$snake.Add((New-Point -X 4 -Y 5))
    [void]$snake.Add((New-Point -X 3 -Y 5))

    $direction = "Right"
    $nextDirection = "Right"

    $food = Get-RandomFood -Snake $snake
    $score = 0
    $level = 1

    while ($true) {
        # ----- INPUT -----
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

        # ----- MOVE HEAD -----
        $head = $snake[0]
        $newHead = New-Point -X $head.X -Y $head.Y

        switch ($direction) {
            "Up"    { $newHead.Y-- }
            "Down"  { $newHead.Y++ }
            "Left"  { $newHead.X-- }
            "Right" { $newHead.X++ }
        }

        # ----- COLLISION: WALL -----
        if ($newHead.X -le 0 -or $newHead.X -ge $BoardWidth -or $newHead.Y -le 0 -or $newHead.Y -ge $BoardHeight) {
            Draw-Game -Snake $snake -Food $food -Score $score -Level $level
            Show-GameOver -Score $score
            break
        }

        # ----- COLLISION: SELF -----
        foreach ($segment in $snake) {
            if (Test-PointEqual $newHead $segment) {
                Draw-Game -Snake $snake -Food $food -Score $score -Level $level
                Show-GameOver -Score $score
                break 2
            }
        }

        # Insert new head
        [void]$snake.Insert(0, $newHead)

        # ----- FOOD -----
        if (Test-PointEqual $newHead $food) {
            $score += 10
            $level = [math]::Floor($score / 50) + 1

            # speed up a little, but keep playable
            $TickMs = [math]::Max(60, 120 - (($level - 1) * 8))

            $food = Get-RandomFood -Snake $snake
        }
        else {
            # remove tail
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