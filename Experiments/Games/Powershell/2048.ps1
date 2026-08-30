#--------------------------------------------
# file:     2048.ps1
# author:   Mike Redd
# version:  1.1
# created:  2026-03-30
# updated:  2026-03-30
# desc:     2048 game for PowerShell
#--------------------------------------------

$ScriptName    = "2048"
$ScriptVersion = "1.1"
$ScriptAuthor  = "Mike Redd"

# ----- ANSI -----
$ESC = [char]27
function C($code) { return "$ESC[${code}m" }

$R   = C "0"; $B   = C "1"; $DIM = C "2"
$CYN = C "96"; $YLW = C "93"; $GRN = C "92"
$RED = C "91"; $GRY = C "90"; $WHT = C "97"
$MAG = C "95"

# ----- BOARD -----
$Size = 4
$Board = @()
for ($i = 0; $i -lt $Size; $i++) {
    $Board += ,(@(0,0,0,0))
}

$Score = 0

function Show-Header {
    Write-Host "  ${CYN}${B}+======================================+${R}"
    Write-Host "  ${CYN}${B}|${R}  ${YLW}${B}$ScriptName${R} v$ScriptVersion$((" " * (25 - $ScriptVersion.Length)))${CYN}${B}|${R}"
    Write-Host "  ${CYN}${B}+======================================+${R}"
    Write-Host "  ${DIM}  Use arrows or WASD${R}"
    Write-Host "  ${DIM}  Q to quit${R}"
    Write-Host ""
}

function Get-Color($value) {
    switch ($value) {
        0   { return $GRY }
        2   { return $DIM }
        4   { return $WHT }
        8   { return $YLW }
        16  { return $GRN }
        32  { return $CYN }
        64  { return $MAG }
        128 { return $RED }
        default { return $RED + $B }
    }
}

function Draw-Board {
    [Console]::SetCursorPosition(0,0)
    Show-Header
    Write-Host "  ${GRN}Score:${R} $Score"
    Write-Host ""

    for ($y = 0; $y -lt $Size; $y++) {
        Write-Host "  +------+------+------+------+"
        Write-Host -NoNewline "  |"

        for ($x = 0; $x -lt $Size; $x++) {
            $v = $Board[$y][$x]
            $color = Get-Color $v

            if ($v -eq 0) {
                $text = "     "
            } else {
                $text = $v.ToString().PadLeft(5)
            }

            Write-Host -NoNewline "$color$text$R|"
        }

        Write-Host ""
    }

    Write-Host "  +------+------+------+------+"
}

function Add-RandomTile {
    $empty = @()

    for ($y = 0; $y -lt $Size; $y++) {
        for ($x = 0; $x -lt $Size; $x++) {
            if ($Board[$y][$x] -eq 0) {
                $empty += ,@($x, $y)
            }
        }
    }

    if ($empty.Count -eq 0) {
        return
    }

    $pick = Get-Random -InputObject $empty
    $x = $pick[0]
    $y = $pick[1]

    $Board[$y][$x] = if ((Get-Random -Minimum 0 -Maximum 10) -lt 9) { 2 } else { 4 }
}

function Slide-And-Merge($line) {
    $new = @($line | Where-Object { $_ -ne 0 })

    for ($i = 0; $i -lt ($new.Count - 1); $i++) {
        if ($new[$i] -eq $new[$i + 1]) {
            $new[$i] *= 2
            $Score += $new[$i]
            $new[$i + 1] = 0
        }
    }

    $new = @($new | Where-Object { $_ -ne 0 })

    while ($new.Count -lt $Size) {
        $new += 0
    }

    return ,$new
}

function Reverse-Array($arr) {
    $copy = @($arr.Clone())
    [array]::Reverse($copy)
    return ,$copy
}

function Move-Left {
    for ($y = 0; $y -lt $Size; $y++) {
        $Board[$y] = Slide-And-Merge $Board[$y]
    }
}

function Move-Right {
    for ($y = 0; $y -lt $Size; $y++) {
        $rev = Reverse-Array $Board[$y]
        $rev = Slide-And-Merge $rev
        $rev = Reverse-Array $rev
        $Board[$y] = $rev
    }
}

function Move-Up {
    for ($x = 0; $x -lt $Size; $x++) {
        $col = @()
        for ($y = 0; $y -lt $Size; $y++) {
            $col += $Board[$y][$x]
        }

        $col = Slide-And-Merge $col

        for ($y = 0; $y -lt $Size; $y++) {
            $Board[$y][$x] = $col[$y]
        }
    }
}

function Move-Down {
    for ($x = 0; $x -lt $Size; $x++) {
        $col = @()
        for ($y = 0; $y -lt $Size; $y++) {
            $col += $Board[$y][$x]
        }

        $col = Reverse-Array $col
        $col = Slide-And-Merge $col
        $col = Reverse-Array $col

        for ($y = 0; $y -lt $Size; $y++) {
            $Board[$y][$x] = $col[$y]
        }
    }
}

function Boards-Equal($a, $b) {
    for ($y = 0; $y -lt $Size; $y++) {
        for ($x = 0; $x -lt $Size; $x++) {
            if ($a[$y][$x] -ne $b[$y][$x]) {
                return $false
            }
        }
    }
    return $true
}

function Copy-Board {
    $copy = @()
    for ($y = 0; $y -lt $Size; $y++) {
        $copy += ,($Board[$y].Clone())
    }
    return $copy
}

function Can-Move {
    for ($y = 0; $y -lt $Size; $y++) {
        for ($x = 0; $x -lt $Size; $x++) {
            if ($Board[$y][$x] -eq 0) { return $true }
            if ($x -lt ($Size - 1) -and $Board[$y][$x] -eq $Board[$y][$x + 1]) { return $true }
            if ($y -lt ($Size - 1) -and $Board[$y][$x] -eq $Board[$y + 1][$x]) { return $true }
        }
    }
    return $false
}

# ----- START -----
try {
    [Console]::CursorVisible = $false
} catch {}

Clear-Host

Add-RandomTile
Add-RandomTile

$running = $true

while ($running) {
    Draw-Board

    if (-not (Can-Move)) {
        Write-Host ""
        Write-Host "  ${RED}${B}Game Over${R}"
        Write-Host "  Final Score: $Score"
        Read-Host "  Press Enter" | Out-Null
        break
    }

    $key = [Console]::ReadKey($true)
    $before = Copy-Board

    switch ($key.Key) {
        ([ConsoleKey]::LeftArrow)  { Move-Left }
        ([ConsoleKey]::RightArrow) { Move-Right }
        ([ConsoleKey]::UpArrow)    { Move-Up }
        ([ConsoleKey]::DownArrow)  { Move-Down }
        ([ConsoleKey]::A)          { Move-Left }
        ([ConsoleKey]::D)          { Move-Right }
        ([ConsoleKey]::W)          { Move-Up }
        ([ConsoleKey]::S)          { Move-Down }
        ([ConsoleKey]::Q) {
            $running = $false
            continue
        }
        default { continue }
    }

    if (-not (Boards-Equal $before $Board)) {
        Add-RandomTile
    }
}

try {
    [Console]::CursorVisible = $true
} catch {}