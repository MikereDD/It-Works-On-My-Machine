#--------------------------------------------
# file:     breakout.ps1
# author:   Mike Redd
# version:  1.0
# created:  2026-03-30
# updated:  2026-03-30
# desc:     Simple Breakout game for PowerShell
#--------------------------------------------

$ScriptName    = "Breakout"
$ScriptVersion = "1.0"
$ScriptAuthor  = "Mike Redd"

# ----- ANSI -----
$ESC = [char]27
function C($code) { return "$ESC[${code}m" }

$R   = C "0"; $B   = C "1"; $DIM = C "2"
$CYN = C "96"; $YLW = C "93"; $GRN = C "92"
$RED = C "91"; $GRY = C "90"; $WHT = C "97"
$MAG = C "95"; $BLU = C "94"

# ----- GAME SETTINGS -----
$BoardWidth   = 34
$BoardHeight  = 22
$PaddleWidth  = 7
$TickMs       = 65
$StartLives   = 3

$WallChar     = "█"
$PaddleChar   = "█"
$BallChar     = "●"
$BrickChar    = "█"
$EmptyChar    = " "

# ----- CONSOLE SETUP -----
try { [Console]::CursorVisible = $false } catch {}
$originalTreatControlCAsInput = [Console]::TreatControlCAsInput
[Console]::TreatControlCAsInput = $true

function Show-Header {
    Write-Host "  ${CYN}${B}+======================================+${R}"
    Write-Host "  ${CYN}${B}|${R}  ${YLW}${B}$ScriptName${R} v$ScriptVersion$((" " * (21 - $ScriptVersion.Length)))${CYN}${B}|${R}"
    Write-Host "  ${CYN}${B}+======================================+${R}"
    Write-Host "  ${DIM}  A/D or Arrow Keys move${R}"
    Write-Host "  ${DIM}  P pause  Q quit${R}"
    Write-Host ""
}

function New-Brick {
    param(
        [int]$X,
        [int]$Y,
        [string]$Color
    )

    [PSCustomObject]@{
        X      = $X
        Y      = $Y
        Color  = $Color
        Active = $true
    }
}

function Initialize-Bricks {
    $bricks = New-Object System.Collections.ArrayList

    $rows = @(
        @{ Y = 2; Color = $RED }
        @{ Y = 3; Color = $MAG }
        @{ Y = 4; Color = $YLW }
        @{ Y = 5; Color = $GRN }
        @{ Y = 6; Color = $CYN }
    )

    foreach ($row in $rows) {
        for ($x = 2; $x -lt ($BoardWidth - 1); $x += 2) {
            [void]$bricks.Add((New-Brick -X $x -Y $row.Y -Color $row.Color))
        }
    }

    return $bricks
}

function Reset-BallAndPaddle {
    return [PSCustomObject]@{
        PaddleX = [math]::Floor(($BoardWidth - $PaddleWidth) / 2)
        BallX   = [math]::Floor($BoardWidth / 2)
        BallY   = $BoardHeight - 3
        BallVX  = if ((Get-Random -Minimum 0 -Maximum 2) -eq 0) { -1 } else { 1 }
        BallVY  = -1
    }
}

function Draw-Game {
    param(
        $Bricks,
        [int]$PaddleX,
        [int]$BallX,
        [int]$BallY,
        [int]$Score,
        [int]$Lives,
        [bool]$Paused
    )

    [Console]::SetCursorPosition(0, 0)
    Show-Header
    $pauseText = if ($Paused) { "   ${YLW}Paused${R}" } else { "" }
	Write-Host "  ${GRN}Score:${R} $Score   ${RED}Lives:${R} $Lives$pauseText"
    Write-Host ""

    for ($y = 0; $y -le $BoardHeight; $y++) {
        Write-Host -NoNewline "  "

        for ($x = 0; $x -le $BoardWidth; $x++) {
            $isTopWall = ($y -eq 0)
            $isSideWall = ($x -eq 0 -or $x -eq $BoardWidth)

            if ($isTopWall -or $isSideWall) {
                Write-Host -NoNewline "${CYN}${WallChar}${R}"
                continue
            }

            # Paddle
            if ($y -eq ($BoardHeight - 1) -and $x -ge $PaddleX -and $x -lt ($PaddleX + $PaddleWidth)) {
                Write-Host -NoNewline "${GRN}${PaddleChar}${R}"
                continue
            }

            # Ball
            if ($x -eq $BallX -and $y -eq $BallY) {
                Write-Host -NoNewline "${YLW}${BallChar}${R}"
                continue
            }

            # Brick
            $brick = $Bricks | Where-Object { $_.Active -and $_.X -eq $x -and $_.Y -eq $y } | Select-Object -First 1
            if ($brick) {
                Write-Host -NoNewline "$($brick.Color)${BrickChar}${R}"
                continue
            }

            Write-Host -NoNewline $EmptyChar
        }

        Write-Host ""
    }
}

function Show-EndScreen {
    param(
        [string]$Message,
        [int]$Score
    )

    Write-Host ""
    Write-Host "  ${YLW}${B}$Message${R}"
    Write-Host "  ${GRN}Final Score:${R} $Score"
    Write-Host ""
    Write-Host "  ${GRY}Press Enter to exit...${R}"
    Read-Host | Out-Null
}

try {
    Clear-Host

    $bricks = Initialize-Bricks
    $state = Reset-BallAndPaddle

    $paddleX = $state.PaddleX
    $ballX   = $state.BallX
    $ballY   = $state.BallY
    $ballVX  = $state.BallVX
    $ballVY  = $state.BallVY

    $score = 0
    $lives = $StartLives
    $paused = $false
    $running = $true

    while ($running) {
        while ([Console]::KeyAvailable) {
            $key = [Console]::ReadKey($true)

            switch ($key.Key) {
                ([ConsoleKey]::LeftArrow) {
                    if (-not $paused -and $paddleX -gt 1) { $paddleX-- }
                }
                ([ConsoleKey]::RightArrow) {
                    if (-not $paused -and ($paddleX + $PaddleWidth - 1) -lt ($BoardWidth - 1)) { $paddleX++ }
                }
                ([ConsoleKey]::A) {
                    if (-not $paused -and $paddleX -gt 1) { $paddleX-- }
                }
                ([ConsoleKey]::D) {
                    if (-not $paused -and ($paddleX + $PaddleWidth - 1) -lt ($BoardWidth - 1)) { $paddleX++ }
                }
                ([ConsoleKey]::P) {
                    $paused = -not $paused
                }
                ([ConsoleKey]::Q) {
                    $running = $false
                }
            }
        }

        if (-not $running) { break }

        if (-not $paused) {
            $nextX = $ballX + $ballVX
            $nextY = $ballY + $ballVY

            # Wall collisions
            if ($nextX -le 1 -or $nextX -ge ($BoardWidth - 1)) {
                $ballVX *= -1
                $nextX = $ballX + $ballVX
            }

            if ($nextY -le 1) {
                $ballVY *= -1
                $nextY = $ballY + $ballVY
            }

            # Paddle collision
            if ($nextY -eq ($BoardHeight - 1) -and $nextX -ge $paddleX -and $nextX -lt ($paddleX + $PaddleWidth)) {
                $ballVY = -1

                $hit = $nextX - $paddleX
                if ($hit -le 1) {
                    $ballVX = -1
                } elseif ($hit -ge ($PaddleWidth - 2)) {
                    $ballVX = 1
                }

                $nextX = $ballX + $ballVX
                $nextY = $ballY + $ballVY
            }

            # Brick collision
            $hitBrick = $bricks | Where-Object { $_.Active -and $_.X -eq $nextX -and $_.Y -eq $nextY } | Select-Object -First 1
            if ($hitBrick) {
                $hitBrick.Active = $false
                $score += 10
                $ballVY *= -1
                $nextY = $ballY + $ballVY
            }

            $ballX = $nextX
            $ballY = $nextY

            # Ball lost
            if ($ballY -gt ($BoardHeight - 1)) {
                $lives--

                if ($lives -le 0) {
                    Draw-Game -Bricks $bricks -PaddleX $paddleX -BallX $ballX -BallY $ballY -Score $score -Lives $lives -Paused $paused
                    Show-EndScreen -Message "Game Over" -Score $score
                    break
                }

                $state = Reset-BallAndPaddle
                $paddleX = $state.PaddleX
                $ballX   = $state.BallX
                $ballY   = $state.BallY
                $ballVX  = $state.BallVX
                $ballVY  = $state.BallVY
            }

            # Win
            if (-not ($bricks | Where-Object { $_.Active })) {
                Draw-Game -Bricks $bricks -PaddleX $paddleX -BallX $ballX -BallY $ballY -Score $score -Lives $lives -Paused $paused
                Show-EndScreen -Message "You Win!" -Score $score
                break
            }
        }

        Draw-Game -Bricks $bricks -PaddleX $paddleX -BallX $ballX -BallY $ballY -Score $score -Lives $lives -Paused $paused
        Start-Sleep -Milliseconds $TickMs
    }
}
finally {
    try { [Console]::CursorVisible = $true } catch {}
    [Console]::TreatControlCAsInput = $originalTreatControlCAsInput
}