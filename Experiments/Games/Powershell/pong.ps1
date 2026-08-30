#--------------------------------------------
# file:     pong.ps1
# author:   Mike Redd
# version:  1.1
# created:  2026-03-30
# updated:  2026-03-30
# desc:     Simple Pong game for PowerShell
#--------------------------------------------

$ScriptName    = "Pong"
$ScriptVersion = "1.0"
$ScriptAuthor  = "Mike Redd"

# ----- ANSI -----
$ESC = [char]27
function C($code) { return "$ESC[${code}m" }

$R   = C "0";  $B   = C "1"; $DIM = C "2"
$CYN = C "96"; $YLW = C "93"; $GRN = C "92"
$RED = C "91"; $GRY = C "90"; $WHT = C "97"
$MAG = C "95"

# ----- GAME SETTINGS -----
$BoardWidth   = 40
$BoardHeight  = 18
$PaddleSize   = 4
$TickMs       = 55
$WinScore     = 7

$WallChar     = "█"
$BallChar     = "●"
$PaddleChar   = "█"
$EmptyChar    = " "

# ----- CONSOLE SETUP -----
[Console]::CursorVisible = $false
$originalTreatControlCAsInput = [Console]::TreatControlCAsInput
[Console]::TreatControlCAsInput = $true

function Show-Header {
    Write-Host "  ${CYN}${B}+======================================+${R}"
    Write-Host "  ${CYN}${B}|${R}  ${YLW}${B}$ScriptName${R} v$ScriptVersion$((" " * (25 - $ScriptVersion.Length)))${CYN}${B}|${R}"
    Write-Host "  ${CYN}${B}+======================================+${R}"
    Write-Host "  ${DIM}  W/S or Arrow Keys to move${R}"
    Write-Host "  ${DIM}  Q to quit${R}"
    Write-Host ""
}

function Draw-Game {
    param(
        [int]$PlayerY,
        [int]$CpuY,
        [int]$BallX,
        [int]$BallY,
        [int]$PlayerScore,
        [int]$CpuScore
    )

    [Console]::SetCursorPosition(0, 0)
    Show-Header
    Write-Host "  ${GRN}Player:${R} $PlayerScore   ${RED}CPU:${R} $CpuScore"
    Write-Host ""

    for ($y = 0; $y -le $BoardHeight; $y++) {
        Write-Host -NoNewline "  "

        for ($x = 0; $x -le $BoardWidth; $x++) {
            $isTopBottomWall = ($y -eq 0 -or $y -eq $BoardHeight)
            $isLeftRightWall = ($x -eq 0 -or $x -eq $BoardWidth)

            if ($isTopBottomWall) {
                Write-Host -NoNewline "${CYN}${WallChar}${R}"
                continue
            }

            if ($isLeftRightWall) {
                Write-Host -NoNewline "${GRY}${WallChar}${R}"
                continue
            }

            if ($x -eq 2 -and $y -ge $PlayerY -and $y -lt ($PlayerY + $PaddleSize)) {
                Write-Host -NoNewline "${GRN}${PaddleChar}${R}"
                continue
            }

            if ($x -eq ($BoardWidth - 2) -and $y -ge $CpuY -and $y -lt ($CpuY + $PaddleSize)) {
                Write-Host -NoNewline "${RED}${PaddleChar}${R}"
                continue
            }

            if ($x -eq $BallX -and $y -eq $BallY) {
                Write-Host -NoNewline "${YLW}${BallChar}${R}"
                continue
            }

            if ($x -eq [math]::Floor($BoardWidth / 2)) {
                Write-Host -NoNewline "${GRY}│${R}"
                continue
            }

            Write-Host -NoNewline $EmptyChar
        }

        Write-Host ""
    }
}

function Reset-Ball {
    param([int]$Direction)

    return [PSCustomObject]@{
        X  = [math]::Floor($BoardWidth / 2)
        Y  = [math]::Floor($BoardHeight / 2)
        VX = $Direction
        VY = (Get-Random -Minimum -1 -Maximum 2)
    }
}

function Show-EndScreen {
    param(
        [string]$Winner,
        [int]$PlayerScore,
        [int]$CpuScore
    )

    Write-Host ""
    if ($Winner -eq "Player") {
        Write-Host "  ${GRN}${B}You Win!${R}"
    } else {
        Write-Host "  ${RED}${B}CPU Wins!${R}"
    }

    Write-Host "  ${GRN}Player:${R} $PlayerScore   ${RED}CPU:${R} $CpuScore"
    Write-Host ""
    Write-Host "  ${GRY}Press Enter to exit...${R}"
    Read-Host | Out-Null
}

try {
    Clear-Host

    $playerY = [math]::Floor(($BoardHeight - $PaddleSize) / 2)
    $cpuY    = [math]::Floor(($BoardHeight - $PaddleSize) / 2)

    if ((Get-Random -Minimum 0 -Maximum 2) -eq 0) {
		$dir = -1
	} else {
		$dir = 1
	}

$ball = Reset-Ball -Direction $dir

    $playerScore = 0
    $cpuScore    = 0

    while ($true) {
        # ----- INPUT -----
        while ([Console]::KeyAvailable) {
            $key = [Console]::ReadKey($true)

            switch ($key.Key) {
                "W"       { if ($playerY -gt 1) { $playerY-- } }
                "S"       { if (($playerY + $PaddleSize) -lt $BoardHeight) { $playerY++ } }
                "UpArrow" { if ($playerY -gt 1) { $playerY-- } }
                "DownArrow" { if (($playerY + $PaddleSize) -lt $BoardHeight) { $playerY++ } }
                "Q"       { return }
            }
        }

        # ----- CPU -----
        $cpuCenter = $cpuY + [math]::Floor($PaddleSize / 2)
        if ($ball.Y -lt $cpuCenter -and $cpuY -gt 1) {
            $cpuY--
        } elseif ($ball.Y -gt $cpuCenter -and ($cpuY + $PaddleSize) -lt $BoardHeight) {
            $cpuY++
        }

        # ----- MOVE BALL -----
        $nextX = $ball.X + $ball.VX
        $nextY = $ball.Y + $ball.VY

        # Top / bottom bounce
        if ($nextY -le 1 -or $nextY -ge ($BoardHeight - 1)) {
            $ball.VY *= -1
            $nextY = $ball.Y + $ball.VY
        }

        # Player paddle collision
        if ($nextX -eq 2 -and $nextY -ge $playerY -and $nextY -lt ($playerY + $PaddleSize)) {
            $ball.VX = 1

            $hitPos = $nextY - $playerY
            switch ($hitPos) {
                0 { $ball.VY = -1 }
                1 { $ball.VY = 0 }
                2 { $ball.VY = 0 }
                3 { $ball.VY = 1 }
                default { $ball.VY = 0 }
            }

            $nextX = $ball.X + $ball.VX
            $nextY = $ball.Y + $ball.VY
        }

        # CPU paddle collision
        if ($nextX -eq ($BoardWidth - 2) -and $nextY -ge $cpuY -and $nextY -lt ($cpuY + $PaddleSize)) {
            $ball.VX = -1

            $hitPos = $nextY - $cpuY
            switch ($hitPos) {
                0 { $ball.VY = -1 }
                1 { $ball.VY = 0 }
                2 { $ball.VY = 0 }
                3 { $ball.VY = 1 }
                default { $ball.VY = 0 }
            }

            $nextX = $ball.X + $ball.VX
            $nextY = $ball.Y + $ball.VY
        }

        $ball.X = $nextX
        $ball.Y = $nextY

        # ----- SCORING -----
        if ($ball.X -le 1) {
            $cpuScore++
            if ($cpuScore -ge $WinScore) {
                Draw-Game -PlayerY $playerY -CpuY $cpuY -BallX $ball.X -BallY $ball.Y -PlayerScore $playerScore -CpuScore $cpuScore
                Show-EndScreen -Winner "CPU" -PlayerScore $playerScore -CpuScore $cpuScore
                break
            }
            $ball = Reset-Ball -Direction 1
        }
        elseif ($ball.X -ge ($BoardWidth - 1)) {
            $playerScore++
            if ($playerScore -ge $WinScore) {
                Draw-Game -PlayerY $playerY -CpuY $cpuY -BallX $ball.X -BallY $ball.Y -PlayerScore $playerScore -CpuScore $cpuScore
                Show-EndScreen -Winner "Player" -PlayerScore $playerScore -CpuScore $cpuScore
                break
            }
            $ball = Reset-Ball -Direction -1
        }

        Draw-Game -PlayerY $playerY -CpuY $cpuY -BallX $ball.X -BallY $ball.Y -PlayerScore $playerScore -CpuScore $cpuScore
        Start-Sleep -Milliseconds $TickMs
    }
}
finally {
    [Console]::CursorVisible = $true
    [Console]::TreatControlCAsInput = $originalTreatControlCAsInput
}