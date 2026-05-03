# music and sound
Add-Type -AssemblyName PresentationCore
$mediaPlayer = New-Object System.Windows.Media.MediaPlayer 
$mediaPlayer.Open("$($PSScriptRoot)\Portal2-24-Robots_FTW.mp3")
$player = New-Object System.Media.SoundPlayer "$PSScriptRoot\coin.wav"
$mediaPlayer.Play()

$blipPlayer = New-Object System.Media.SoundPlayer "$PSScriptRoot\pellet.wav"
$blipPlayer.SoundLocation = "$PSScriptRoot\pellet.wav"
$blipPlayer.Load()

$powerPlayer = New-Object System.Media.SoundPlayer "$PSScriptRoot\power.wav"
$powerPlayer.SoundLocation = "$PSScriptRoot\power.wav"
$powerPlayer.Load()

$eatPlayer = New-Object System.Media.SoundPlayer "$PSScriptRoot\eat.wav"
$eatPlayer.SoundLocation = "$PSScriptRoot\eat.wav"
$eatPlayer.Load()

$global:sw = [Diagnostics.Stopwatch]::StartNew()

# setup initial ghosts
$global:game_obj = @(
    @{
        'name' = 'Player 1';
        'pos_x' = 0;
        'pos_y' = 0;
        'intended_x' = 0;
        'intended_y' = 0;
        'start_x' = 0;
        'start_y' = 0;
        'score' = 0;
        'move_dir' = 'None';
        'intended_move_dir' = 'None';
        'active' = 1;
        'powered_frame' = -1;
        'draw_char' = 'O';
        'edible' = 0; # only for multiplayer
        'color' = 'yellow';
        'team' = 'pacman';
        'config' = @{
            'joined' = 1; # player 1 is always joined
            'move_up_key' = 'UpArrow';
            'move_down_key' = 'DownArrow';
            'move_left_key' = 'LeftArrow';
            'move_right_key' = 'RightArrow';
        }
    },
    @{
        'name' = 'Blinky';
        'pos_x' = 0;
        'pos_y' = 0;
        'intended_x' = 0;
        'intended_y' = 0;
        'start_x' = 0;
        'start_y' = 0;
        'move_dir' = 'RightArrow';
        'active' = 1;
        'draw_char' = 'Ω';
        'edible' = 0;
        'color' = 'red';
        'team' = 'ghost';
    }
    @{
        'name' = 'Pinky';
        'pos_x' = 0;
        'pos_y' = 0;
        'intended_x' = 0;
        'intended_y' = 0;
        'start_x' = 0;
        'start_y' = 0;
        'move_dir' = 'LeftArrow';
        'active' = 1;
        'draw_char' = 'Ω';
        'edible' = 0;
        'color' = 'magenta';
        'team' = 'ghost';
    },
    @{
        'name' = 'Inky';
        'pos_x' = 0;
        'pos_y' = 0;
        'intended_x' = 0;
        'intended_y' = 0;
        'start_x' = 0;
        'start_y' = 0;
        'move_dir' = 'RightArrow';
        'active' = 1;
        'draw_char' = 'Ω';
        'edible' = 0;
        'color' = 'cyan';
        'team' = 'ghost';
    },
    @{
        'name' = 'Clyde';
        'pos_x' = 0;
        'pos_y' = 0;
        'intended_x' = 0;
        'intended_y' = 0;
        'start_x' = 0;
        'start_y' = 0;
        'move_dir' = 'LeftArrow';
        'active' = 1;
        'draw_char' = 'Ω';
        'edible' = 0;
        'color' = 'yellow';
        'team' = 'ghost';
    },
    @{
        'name' = 'Player 2';
        'pos_x' = 0;
        'pos_y' = 0;
        'intended_x' = 0;
        'intended_y' = 0;
        'start_x' = 0;
        'start_y' = 0;
        'move_dir' = 'None';
        'score' = 0;
        'intended_move_dir' = 'None';
        'active' = 1;
        'draw_char' = 'O';
        'powered_frame' = -1;
        'edible' = 0; # only for multiplayer
        'color' = 'cyan';
        'team' = 'pacman';
        'config' = @{
            'joined' = 0;
            'move_up_key' = 'w';
            'move_down_key' = 's';
            'move_left_key' = 'a';
            'move_right_key' = 'd';
        }
    },
    @{
        'name' = 'Player 3';
        'pos_x' = 0;
        'pos_y' = 0;
        'intended_x' = 0;
        'intended_y' = 0;
        'start_x' = 0;
        'start_y' = 0;
        'score' = 0;
        'move_dir' = 'None';
        'intended_move_dir' = 'None';
        'active' = 1;
        'draw_char' = 'O';
        'powered_frame' = -1;
        'edible' = 0; # only for multiplayer
        'color' = 'green';
        'team' = 'pacman';
        'config' = @{
            'joined' = 0;
            'move_up_key' = 'i';
            'move_down_key' = 'k';
            'move_left_key' = 'j';
            'move_right_key' = 'l';
        }
    },
    @{
        'name' = 'Player 4';
        'pos_x' = 0;
        'pos_y' = 0;
        'intended_x' = 0;
        'intended_y' = 0;
        'start_x' = 0;
        'start_y' = 0;
        'score' = 0;
        'move_dir' = 'None';
        'intended_move_dir' = 'None';
        'active' = 1;
        'powered_frame' = -1;
        'draw_char' = 'O';
        'edible' = 0; # only for multiplayer
        'color' = 'magenta';
        'team' = 'pacman';
        'config' = @{
            'joined' = 0;
            'move_up_key' = 'NumPad8';
            'move_down_key' = 'NumPad5';
            'move_left_key' = 'NumPad4';
            'move_right_key' = 'NumPad6';
        }
    }
)

[console]::CursorVisible = 0
$global:pending_death = -1
$global:mode_key = 's'
$global:game_over = 0

$global:power_pellet_mode = 0
$global:mode_frame_counter = 0
$global:lives = 3
$global:active_players = 1
$global:game_over_message = ''


$global:show_debug = 0

$global:maze_wall_color = 'blue'
$global:pellet_count = 0

function PosWrite (

    [string] $str,
    [int] $x = 0,
    [int] $y = 0,
    [string] $bgc = [console]::BackgroundColor,
    [string] $fgc = [Console]::ForegroundColor)
{
        if($x -lt 0 -or $y -lt 0)
        {
            return
            [console]::setcursorposition(0,0)
            Write-Host -Object $str -BackgroundColor $bgc -ForegroundColor $fgc -NoNewline
            [console]::setcursorposition(0,1)
            Write-Host -Object "ATTEMPTING TO WRITE TO A NEGATIVE POSITION: $($x) $($y)" -BackgroundColor $bgc -ForegroundColor $fgc -NoNewline
            return
            
        }
        [console]::setcursorposition($x,$y)
        Write-Host -Object $str -BackgroundColor $bgc -ForegroundColor $fgc -NoNewline
        #[console]::setcursorposition(0,$saveY)
}


# This function always reads until last key presssed and returnst hat one
# it's not suitable for multiplayer gameplay where multiple people are pressing
# buttons at the same time
function Get-KeySilent
{
    if([console]::KeyAvailable)
    {
        while([console]::KeyAvailable)
        {
            $key = [console]::readkey('noecho').Key
        }
    }
    else
    {
        $key = 'nokey'
    }
    $key
}

function StartScreen
{
    $logo = @(
         '            PPPPPPPPPPPPPPPPP                  AAA                       CCCCCCCCCCCCC',
         '            P::::::::::::::::P                A:::A                   CCC::::::::::::C',
         '            P::::::PPPPPP:::::P              A:::::A                CC:::::::::::::::C',
         '            PP:::::P     P:::::P            A:::::::A              C:::::CCCCCCCC::::C',
         '              P::::P     P:::::P           A:::::::::A            C:::::C       CCCCCC',
         '              P::::P     P:::::P          A:::::A:::::A          C:::::C              ',
         '              P::::PPPPPP:::::P          A:::::A A:::::A         C:::::C              ',
         '              P:::::::::::::PP          A:::::A   A:::::A        C:::::C              ',
         '              P::::PPPPPPPPP           A:::::A     A:::::A       C:::::C              ',
         '              P::::P                  A:::::AAAAAAAAA:::::A      C:::::C              ',
         '              P::::P                 A:::::::::::::::::::::A     C:::::C              ',
         '              P::::P                A:::::AAAAAAAAAAAAA:::::A     C:::::C       CCCCCC',
         '            PP::::::PP             A:::::A             A:::::A     C:::::CCCCCCCC::::C',
         '            P::::::::P            A:::::A               A:::::A     CC:::::::::::::::C',
         '            P::::::::P           A:::::A                 A:::::A      CCC::::::::::::C',
         '            PPPPPPPPPP          AAAAAAA                   AAAAAAA        CCCCCCCCCCCCC',
         '',
         '     MMMMMMMM               MMMMMMMM               AAA               NNNNNNNN        NNNNNNNN',
         '     M:::::::M             M:::::::M              A:::A              N:::::::N       N::::::N',
         '     M::::::::M           M::::::::M             A:::::A             N::::::::N      N::::::N',
         '     M:::::::::M         M:::::::::M            A:::::::A            N:::::::::N     N::::::N',
         '     M::::::::::M       M::::::::::M           A:::::::::A           N::::::::::N    N::::::N',
         '     M:::::::::::M     M:::::::::::M          A:::::A:::::A          N:::::::::::N   N::::::N',
         '     M:::::::M::::M   M::::M:::::::M         A:::::A A:::::A         N:::::::N::::N  N::::::N',
         '     M::::::M M::::M M::::M M::::::M        A:::::A   A:::::A        N::::::N N::::N N::::::N',
         '     M::::::M  M::::M::::M  M::::::M       A:::::A     A:::::A       N::::::N  N::::N:::::::N',
         '     M::::::M   M:::::::M   M::::::M      A:::::AAAAAAAAA:::::A      N::::::N   N:::::::::::N',
         '     M::::::M    M:::::M    M::::::M     A:::::::::::::::::::::A     N::::::N    N::::::::::N',
         '     M::::::M     MMMMM     M::::::M    A:::::AAAAAAAAAAAAA:::::A    N::::::N     N:::::::::N',
         '     M::::::M               M::::::M   A:::::A             A:::::A   N::::::N      N::::::::N',
         '     M::::::M               M::::::M  A:::::A               A:::::A  N::::::N       N:::::::N',
         '     M::::::M               M::::::M A:::::A                 A:::::A N::::::N        N::::::N',
         '     MMMMMMMM               MMMMMMMMAAAAAAA                   AAAAAAANNNNNNNN         NNNNNNN'
    )


    $colors = @(
        #'Black',
        'Blue',
        'Cyan',
        #'DarkBlue',
        #'DarkCyan',
        #'DarkGray',
        #'DarkGreen',
        #'DarkMagenta',
        #'DarkRed',
        #'DarkYellow',
        'Gray',
        'Green',
        'Magenta',
        'Red',
        'White',
        'Yellow'
    )


    $start_x = 5;
    $start_y = 5;
    for($r = 0; $r -lt $logo.Length; $r++)
    {
        $logo[$r] = $logo[$r].ToCharArray();

        for($c = 0; $c -lt $logo[$r].Length; $c++)
        {
            if($logo[$r][$c] -eq ':')
            {
                $color = 'yellow'
            }
            else
            {
                $color = 'darkred'
            }

            $x = $c + $stat_x
            $y = $r + $start_y
            PosWrite $logo[$r][$c] $x $y 'black' $color
        }

    }
    PosWrite '                                  [s]ingle player   [m]ultiplayer' 0 39 'black' 'yellow'

    $color_index = 0
    $active_color = 0
    while(1)
    {
        $start_x = 5;
        $start_y = 5;
        for($r = 0; $r -lt $logo.Length; $r++)
        {
            for($c = 0; $c -lt $logo[$r].Length; $c++)
            {
                if($logo[$r][$c] -eq ':')
                {
                    continue
                }
                else
                {
                    $color_index %= $colors.Length
                    $color = $colors[$color_index]
                }

                $x = $c + $stat_x
                $y = $r + $start_y
                PosWrite $logo[$r][$c] $x $y 'black' $color

                # check for key input
                $key = Get-KeySilent
                if($key -eq "s" -or $key -eq "m")
                {
                    Clear-Host
                    $mediaPlayer.Stop()
                    $global:mode_key = $key
                    return
                }

            }
        }
        $color_index++


        Start-Sleep -m 66
    }

}

function GameOverScreen
{
    Clear-Host
    PosWrite $global:game_over_message 25 16 'black' 'yellow'

    Start-Sleep -m 4000
    Clear-Host
}

function PrintPlayerSetup($start_x, $start_y, $player_index)
{
    if($global:game_obj[$player_index]['config']['joined'])
    {
        $color = $global:game_obj[$player_index]['color']
    }
    else
    {
        $color = 'gray'
    }

    PosWrite '╔════════════════════════════════════╗' $start_x $start_y 'black' $color
    $start_y++
    PosWrite '║       ', $global:game_obj[$player_index]['name'], 'Setup              ║' $start_x $start_y 'black' $color
    $start_y++
    PosWrite '╚╦══════════════════════════════════╦╝' $start_x $start_y 'black' $color
    $start_y++
    
    if($global:game_obj[$player_index]['config']['joined'])
    {
        PosWrite ' ║          ** JOINED **            ║' $start_x $start_y 'black' $color
        $start_y++
        PosWrite ' ║                                  ║' $start_x $start_y 'black' $color
        $start_y++
        
        $str = ' ║        Move Up: ' + $global:game_obj[$player_index]['config']['move_up_key']
        $fill_num = 36 - $str.Length
        $fill = ' ' * $fill_num
        $str += $fill + '║'
        PosWrite $str $start_x $start_y 'black' $color
        $start_y++
        PosWrite ' ║                                  ║' $start_x $start_y 'black' $color
        $start_y++


        $str = ' ║        Move Down: ' + $global:game_obj[$player_index]['config']['move_down_key']
        $fill_num = 36 - $str.Length
        $fill = ' ' * $fill_num
        $str += $fill + '║'
        PosWrite $str $start_x $start_y 'black' $color
        $start_y++
        PosWrite ' ║                                  ║' $start_x $start_y 'black' $color
        $start_y++

        $str = ' ║        Move Left: ' + $global:game_obj[$player_index]['config']['move_left_key']
        $fill_num = 36 - $str.Length
        $fill = ' ' * $fill_num
        $str += $fill + '║'
        PosWrite $str $start_x $start_y 'black' $color
        $start_y++
        PosWrite ' ║                                  ║' $start_x $start_y 'black' $color
        $start_y++


        $str = ' ║        Move Right: ' + $global:game_obj[$player_index]['config']['move_right_key']
        $fill_num = 36 - $str.Length
        $fill = ' ' * $fill_num
        $str += $fill + '║'
        PosWrite $str $start_x $start_y 'black' $color
        $start_y++


        PosWrite ' ║                                  ║' $start_x $start_y 'black' $color
        $start_y++
        PosWrite ' ║                                  ║' $start_x $start_y 'black' $color
        $start_y++
        PosWrite ' ╚══════════════════════════════════╝' $start_x $start_y 'black' $color
    }
    else
    {
        PosWrite ' ║         * PRESS START *          ║' $start_x $start_y 'black' $color
        $start_y++
        PosWrite ' ║                                  ║' $start_x $start_y 'black' $color
        $start_y++
        PosWrite ' ║                                  ║' $start_x $start_y 'black' $color
        $start_y++
        PosWrite ' ║                                  ║' $start_x $start_y 'black' $color
        $start_y++
        PosWrite ' ║                                  ║' $start_x $start_y 'black' $color
        $start_y++
        PosWrite ' ║                                  ║' $start_x $start_y 'black' $color
        $start_y++
        PosWrite ' ║                                  ║' $start_x $start_y 'black' $color
        $start_y++
        PosWrite ' ║                                  ║' $start_x $start_y 'black' $color
        $start_y++
        PosWrite ' ║                                  ║' $start_x $start_y 'black' $color
        $start_y++
        PosWrite ' ║                                  ║' $start_x $start_y 'black' $color
        $start_y++
        PosWrite ' ║                                  ║' $start_x $start_y 'black' $color
        $start_y++
        PosWrite ' ╚══════════════════════════════════╝' $start_x $start_y 'black' $color
    }

}

function MultiplayerSetupScreen
{
    Clear-Host

    $player.SoundLocation = "$PSScriptRoot\coin.wav"
    $player.Load()
    
    while(1)
    {
        #cheating a little here with hard coded indexes
        PrintPlayerSetup 5 5 0
        PrintPlayerSetup 55 5 5
        PrintPlayerSetup 5 25 6
        PrintPlayerSetup 55 25 7

        while(1)
        {

            $key = Get-KeySilent

            $start_keys = @{
                'D1' = 0;
                'D2' = 5;
                'D3' = 6;
                'D4' = 7;
            }

            $key = $key.ToString()
            if(@('Enter', 'D1', 'D2', 'D3', 'D4') -contains $key)
            {
                if($key -eq 'Enter')
                {
                    if($global:active_players -eq 0)
                    {
                        break;
                    }
                    $global:active_players = 0
                    for($i = 0; $i -lt $global:game_obj.Length; $i++)
                    {
                        if($global:game_obj[$i]['team'] -eq 'pacman')
                        {
                            if($global:game_obj[$i]['config']['joined'] -eq 0)
                            {
                                RemovePlayer $i

                            }
                            else
                            {
                                $global:active_players++

                            }
                        }
                    }
                    Clear-Host
                    return
                }

                $player_index = $start_keys[$key]
                #if($key -eq 'D1')
                #{
                    #PosWrite 'KEY WORKS'  0 18 'black' 'yellow'
                #}
                #PosWrite 'start key value: ', $start_keys['D1']  0 11 'black' 'yellow'
                #PosWrite 'key value: ', $key  0 12 'black' 'yellow'
                #PosWrite 'player index: ', $start_keys[$key.ToString()]  0 13 'black' 'yellow'
                #PosWrite 'player index: ', $player_index  0 14 'black' 'yellow'
                $global:game_obj[$player_index]['config']['joined'] = !$global:game_obj[$player_index]['config']['joined']
                if($global:game_obj[$player_index]['config']['joined'])
                {
                    $global:active_players++
                    $player.Play() 

                }
                else
                {
                    $global:active_players--
                }

                break;
            }
            Start-Sleep -m 66
        }
    }
}

function CheckForEndOfGame
{

    if($global:mode_key -eq 's')
    {
        if($global:lives -eq -1)
        {
            $global:game_over_message = 'Game Over'
            return 1
        }
        else
        {
            return 0
        }
    }
    else
    {
        # multiplayer ends when one player is left
        if($global:active_players -eq 1)
        {
            # who is the last player?
            $winning_player = ''
            for($i = 0; $i -lt $global:game_obj.Length; $i++)
            {
                if($global:game_obj[$i]['team'] -eq 'pacman' -and $global:game_obj[$i]['active'])
                {
                    $winning_player = $global:game_obj[$i]['name']
                    break
                }
            }
            
            $global:game_over_message = 'Congratulation,', $winning_player, '!'
            return 1
        }
        else
        {
            return 0
        }
    }    
}

# single player only!
function HandleDeaths
{
    $mediaPlayer.Open("$($PSScriptRoot)\Pacman-death-sound.mp3")
    
    Start-Sleep -m 500
    PosWrite 'o' $global:game_obj[$global:pending_death]['pos_x'] $global:game_obj[$global:pending_death]['pos_y'] 'black' 'yellow'
    $mediaPlayer.Play()
    Start-Sleep -m 500
    PosWrite '.' $global:game_obj[$global:pending_death]['pos_x'] $global:game_obj[$global:pending_death]['pos_y'] 'black' 'yellow'
    Start-Sleep -m 500
    PosWrite '*' $global:game_obj[$global:pending_death]['pos_x'] $global:game_obj[$global:pending_death]['pos_y'] 'black' 'yellow'
    Start-Sleep -m 500
    PosWrite ' ' $global:game_obj[$global:pending_death]['pos_x'] $global:game_obj[$global:pending_death]['pos_y'] 'black' 'yellow'

    if($global:mode_key -eq 's')
    {
        $global:lives--
    }
    else
    {
        # multiplayer ends when one player is left
        RemovePlayer $global:pending_death
        $global:active_players--
    }
}

# used to remove a player from the game
# only used in game setup
function RemovePlayer($index)
{
    #$global:game_obj[$index]['config']['joined'] = 0
    $global:game_obj[$index]['pos_x'] = -1
    $global:game_obj[$index]['pos_y'] = -1
    $global:game_obj[$index]['intended_x'] = -1
    $global:game_obj[$index]['intended_y'] = -1
    $global:game_obj[$index]['move_pos'] = 'None'
    $global:game_obj[$index]['intended_move_pos'] = 'None'
    $global:game_obj[$index]['active'] = 0
}

function ResetScores
{
    for($i = 0; $i -lt $global:game_obj.Length; $i++)
    {
        if($global:game_obj[$i]['team'] -eq 'pacman')
        {
            $global:game_obj[$i]['score'] = 0
        }
    }
}


function SetupGame
{
    $global:pellet_count = 0
    $global:pending_death = -1

    $global:power_pellet_mode = 0
    $global:mode_frame_counter = 80

    for($i = 0; $i -lt $global:game_obj.Length; $i++)
    {
        if($global:game_obj[$i]['team'] -eq 'ghost')
        {
            $global:game_obj[$i]['edible'] = 0
        }
    }



    if($global:mode_key -eq 's')
    {
        $global:mapArray = @(
            @('╔═════════════════════╦═╦═════════════════════╗'),
            @('║ ·#·#·#·#·#·#·#·#·#· ║ ║ ·#·#·#·#·#·#·#·#·#· ║'),
            @('║ · ╔═══╗ · ╔═════╗ · ║ ║ · ╔═════╗ · ╔═══╗ · ║'),
            @('║ ∙ ╚═══╝ · ╚═════╝ · ╚═╝ · ╚═════╝ · ╚═══╝ ∙ ║'),
            @('║ ·#·#·#·#·#·#·#·#·#·#·#·#·#·#·#·#·#·#·#·#·#· ║'),
            @('║ · ═════ · ╔═╗ · ════╦═╦════ · ╔═╗ · ═════ · ║'),
            @('║ ·#·#·#·#· ║ ║ ·#·#· ║ ║ ·#·#· ║ ║ ·#·#·#·#· ║'),
            @('╚═══════╗ · ║ ╠════ # ╚═╝ # ════╣ ║ · ╔═══════╝'),
            @('        ║ · ║ ║ ########1###### ║ ║ · ║        '),
            @('        ║ · ║ ║ # ╔═══-#-═══╗ # ║ ║ · ║        '),
            @('════════╝ · ╚═╝ # ║ ####### ║ # ╚═╝ · ╚════════'),
            @('##########·###### ║ 234#### ║ ######·##########'),
            @('════════╗ · ╔═╗ # ║ ####### ║ # ╔═╗ · ╔════════'),
            @('        ║ · ║ ║ # ╚═════════╝ # ║ ║ · ║        '),
            @('        ║ · ║ ║ ############### ║ ║ · ║        '),
            @('╔═══════╝ · ╚═╝ # ════╦═╦════ # ╚═╝ · ╚═══════╗'),
            @('║ ·#·#·#·#·#·#·#·#·#· ║ ║ ·#·#·#·#·#·#·#·#·#· ║'),
            @('║ · ══╦═╗ · ═══════ · ╚═╝ · ═══════ · ╔═╦══ · ║'),
            @('║ ∙#· ║ ║ ·#·#·#·#·#·#·0·#·#·#·#·#·#· ║ ║ ·#∙ ║'),
            @('╠══ · ╚═╝ · ╔═╗ · ════╦═╦════ · ╔═╗ · ╚═╝ · ══╣'),
            @('║ ·#·#·#·#· ║ ║ ·#·#· ║ ║ ·#·#· ║ ║ ·#·#·#·#· ║'),
            @('║ · ════════╩═╩════ · ╚═╝ · ════╩═╩════════ · ║'),
            @('║ ·#·#·#·#·#·#·#·#·#·#·#·#·#·#·#·#·#·#·#·#·#· ║'),
            @('╚═════════════════════════════════════════════╝') 
        )

        $global:game_obj[5]['config']['joined'] = 0
        RemovePlayer(5)
        $global:game_obj[6]['config']['joined'] = 0
        RemovePlayer(6)
        $global:game_obj[7]['config']['joined'] = 0
        RemovePlayer(7)
    }
    else
    {
        # I know this probably needs a refactor, but...
        # 0 = player 1
        # 1 = Blinky
        # 2 = Pinky
        # 3 = Inky
        # 4 = Clyde
        # 5 = Player 2
        # 6 = Player 3
        # 7 = Player 4


        $global:mapArray = @(
            @('╔═════════════════════╦═╦═════════════════════╗'),
            @('║ 0#·#·#·#·#·#·#·#·#· ║ ║ ·#·#·#·#·#·#·#·#·#5 ║'),
            @('║ · ╔═══╗ · ╔═════╗ · ║ ║ · ╔═════╗ · ╔═══╗ · ║'),
            @('║ ∙ ╚═══╝ · ╚═════╝ · ╚═╝ · ╚═════╝ · ╚═══╝ ∙ ║'),
            @('║ ·#·#·#·#·#·#·#·#·#·#·#·#·#·#·#·#·#·#·#·#·#· ║'),
            @('║ · ═════ · ╔═╗ · ════╦═╦════ · ╔═╗ · ═════ · ║'),
            @('║ ·#·#·#·#· ║ ║ ·#·#· ║ ║ ·#·#· ║ ║ ·#·#·#·#· ║'),
            @('╚═══════╗ · ║ ╠════ # ╚═╝ # ════╣ ║ · ╔═══════╝'),
            @('        ║ · ║ ║ ########1###### ║ ║ · ║        '),
            @('        ║ · ║ ║ # ╔═══-#-═══╗ # ║ ║ · ║        '),
            @('════════╝ · ╚═╝ # ║ ####### ║ # ╚═╝ · ╚════════'),
            @('##########·###### ║ 234#### ║ ######·##########'),
            @('════════╗ · ╔═╗ # ║ ####### ║ # ╔═╗ · ╔════════'),
            @('        ║ · ║ ║ # ╚═════════╝ # ║ ║ · ║        '),
            @('        ║ · ║ ║ ############### ║ ║ · ║        '),
            @('╔═══════╝ · ╚═╝ # ════╦═╦════ # ╚═╝ · ╚═══════╗'),
            @('║ ·#·#·#·#·#·#·#·#·#· ║ ║ ·#·#·#·#·#·#·#·#·#· ║'),
            @('║ · ══╦═╗ · ═══════ · ╚═╝ · ═══════ · ╔═╦══ · ║'),
            @('║ ∙#· ║ ║ ·#·#·#·#·#·#·#·#·#·#·#·#·#· ║ ║ ·#∙ ║'),
            @('╠══ · ╚═╝ · ╔═╗ · ════╦═╦════ · ╔═╗ · ╚═╝ · ══╣'),
            @('║ ·#·#·#·#· ║ ║ ·#·#· ║ ║ ·#·#· ║ ║ ·#·#·#·#· ║'),
            @('║ · ════════╩═╩════ · ╚═╝ · ════╩═╩════════ · ║'),
            @('║ 6#·#·#·#·#·#·#·#·#·#·#·#·#·#·#·#·#·#·#·#·#7 ║'),
            @('╚═════════════════════════════════════════════╝') 
        )
    }

    for($y = 0; $y -lt $global:mapArray.Length; $y++)
    {
        # convert to character arrays
        $global:mapArray[$y] = $global:mapArray[$y].ToCharArray()
        for($x = 0; $x -lt $global:mapArray[$y].Length; $x++)
        {
            if(@('0', '1', '2', '3', '4', '5', '6', '7') -contains $global:mapArray[$y][$x])
            {
                $index = [int]::Parse($global:mapArray[$y][$x])
                $team = $global:game_obj[$index]['team']
                if($team -eq 'ghost' -or ($team -eq 'pacman' -and $global:game_obj[$index]['config']['joined']))
                {
                    $global:game_obj[$index]['pos_x'] = $x
                    $global:game_obj[$index]['pos_y'] = $y

                    $global:game_obj[$index]['intended_x'] = $x
                    $global:game_obj[$index]['intended_y'] = $y

                    $global:game_obj[$index]['start_x'] = $x
                    $global:game_obj[$index]['start_y'] = $y

                    $global:game_obj[$index]['active'] = 1

                }
                $global:mapArray[$y][$x] = '#'
            }

            if(@('·', '∙') -contains $global:mapArray[$y][$x])
            {
                $global:pellet_count++
            }
        }
    }

}

function ResetPositions
{
    $global:power_pellet_mode = 0
    $global:mode_frame_counter = 0
    for($i = 0; $i -lt $global:game_obj.Length; $i++)
    {
        if($global:game_obj[$i]['team'] -eq 'pacman' -and $global:game_obj[$i]['config']['joined'] -eq 0)
        {
            continue
        }

        $mapChar = $global:mapArray[$global:game_obj[$i]['pos_y']][$global:game_obj[$i]['pos_x']]
        if($mapChar -eq '#')
        {
            $mapChar = ' '
        }

        # clear current position on display    
        PosWrite $mapChar $global:game_obj[$i]['pos_x'] $global:game_obj[$i]['pos_y'] 'black' 'white'
        $global:game_obj[$i]['pos_x'] = $global:game_obj[$i]['start_x']
        $global:game_obj[$i]['pos_y'] = $global:game_obj[$i]['start_y']
        $global:game_obj[$i]['intended_x'] = $global:game_obj[$i]['start_x']
        $global:game_obj[$i]['intended_y'] = $global:game_obj[$i]['start_y']
        $global:game_obj[$i]['edible'] = 0

        if($global:game_obj[$i]['team'] -eq 'pacman')
        {
            $global:game_obj[$i]['move_dir'] = 'None'
            $global:game_obj[$i]['intended_move_dir'] = 'None'
        }
    }

}


function DrawMap
{
    # first pass for blue walls
    $row = 0;
    foreach($line in $global:mapArray)
    {
        $str = $line -Join ""
        $str = $str -replace "#", " "
        $str = $str -replace "∙", " "
        $str = $str -replace "·", " "

        PosWrite $str 0 $row 'black' 'blue'
        $row++
    }
}

function DrawPellets
{
    $row = 0;
    foreach($line in $global:mapArray)
    {
        $column = 0;
        foreach($char in $line)
        {
            if($char -eq '∙' -or $char -eq '·')
            {
                PosWrite $char $column $row 'black' 'white'
            }

            $column++
        }
        $row++
    }
}

function FlashMap
{
    for($i = 1; $i -lt 10; $i++)
    {
        if($i % 2)
        {
            $color = "blue"
        }
        else
        {
            $color = "white"
        }

        $row = 0;
        foreach($line in $global:mapArray)
        {
            # make a string for faster drawing
            $str = $line -Join ""
            $str = $str -replace "#", " "

            PosWrite $str 0 $row 'black' $color
            $row++
        }

        Start-Sleep -m 500
    }
}


function GetOppositeDirectionString([string] $dir)
{
    switch($dir)
    {
        'LeftArrow'
        {
            return 'RightArrow'
        }

        'RightArrow'
        {
            return 'LeftArrow'
        }

        'UpArrow'
           {
            return 'DownArrow'
        }

        'DownArrow' 
        {
            return 'UpArrow'
        }
    }
}

function ReverseAllGhostDirection()
{
    for($i = 0; $i -lt $global:game_obj.Length; $i++)
    {
        if($global:game_obj[$i]['team'] -eq 'ghost')
        {
            $global:game_obj[$i]['move_dir'] = GetOppositeDirectionString $global:game_obj[$i]['move_dir']
        }
    }
}

function DrawCharacters
{
    # clear character from old spots, add map char
    for($i = 0; $i -lt $global:game_obj.Length; $i++)
    {
        if($global:game_obj[$i]['team'] -eq 'pacman')
        {
            if($global:game_obj[$i]['config']['joined'] -eq 0 -or $global:game_obj[$i]['active'] -eq 0)
            {
                continue
            }
        }

        # redraw appropriate character in old spot
        $mapChar = $global:mapArray[$global:game_obj[$i]['pos_y']][$global:game_obj[$i]['pos_x']]
        if($mapChar -eq '#')
        {
            $mapChar = ' '
        }

        # TODO: just a safety check, this can eventually be removed
        if(-not (@(' ', '∙', '#', '·') -contains $mapChar))
        {
            PosWrite 'ERROR: Char was ', $mapChar 0 48 'black' 'white'
            PosWrite 'ERROR: index was ', $i 0 49 'black' 'white'
        }

        PosWrite $mapChar $global:game_obj[$i]['pos_x'] $global:game_obj[$i]['pos_y'] 'black' 'white'

        # update the new position
        $global:game_obj[$i]['pos_x'] = $global:game_obj[$i]['intended_x']
        $global:game_obj[$i]['pos_y'] = $global:game_obj[$i]['intended_y']

    }

    for($i = 0; $i -lt $global:game_obj.Length; $i++)
    {
        if($global:game_obj[$i]['team'] -eq 'pacman')
        {
            if($global:game_obj[$i]['config']['joined'] -eq 0 -or $global:game_obj[$i]['active'] -eq 0)
            {
                continue
            }
        }

        if($global:game_obj[$i]['edible'] -and $global:game_obj[$i]['team'] -eq 'ghost')
        {
            if($global:mode_frame_counter -ge 40)
            {

                if($global:mode_frame_counter % 2)
                {
                    $fore_color = $global:game_obj[$i]['color']
                    $back_color = 'black'
                }
                else
                {
                    $fore_color = 'white'
                    $back_color = 'blue'
                }
                
            }
            else
            {
                $fore_color = 'white'
                $back_color = 'blue'
            }
        }
        else
        {
            $fore_color = $global:game_obj[$i]['color']
            $back_color = 'black'
        }


        if($global:game_obj[$i]['team'] -eq 'pacman')
        {
            if($global:game_obj[$i]['config']['joined'] -eq 0 -or $global:game_obj[$i]['active'] -eq 0)
            {
                continue
            }

            if($global:game_obj[$i]['powered_frame'] -gt -1)
            {
                PosWrite 'Θ' $global:game_obj[$i]['pos_x'] $global:game_obj[$i]['pos_y'] $back_color $fore_color
            }
            else
            {
                PosWrite 'O' $global:game_obj[$i]['pos_x'] $global:game_obj[$i]['pos_y'] $back_color $fore_color
            }
        }
        else
        {
            PosWrite $global:game_obj[$i]['draw_char'] $global:game_obj[$i]['pos_x'] $global:game_obj[$i]['pos_y'] $back_color $fore_color
        }
    }
}

function isValidMoveDir([string] $dirKey, [int] $current_x, [int] $current_y)
{
    $intended_x = $current_x;
    $intended_y = $current_y;

    switch($dirKey)
    {
        'LeftArrow'
        {
            $intended_x += -1

            # check for tunnels
            if($current_x -eq 0)
            {
                return 1
            }
        }

        'RightArrow'
        {
            $intended_x += 1

            # check for tunnels
            if($current_x -eq $global:mapArray[0].Length - 1)
            {
                return 1
            }
        }

        'UpArrow'
        {
            $intended_y += -1
        }

        'DownArrow'
        {
            $intended_y += 1
        }
        default
        {
            return 0
        }
    }

    # check if a path square
    if($global:mapArray[$intended_y][$intended_x] -eq '#' -or $global:mapArray[$intended_y][$intended_x] -eq '∙' -or $global:mapArray[$intended_y][$intended_x] -eq '·')
    {
        return 1
    }

    return 0
}


function HandleMoveInput
{
    if([console]::KeyAvailable)
    {
        while([console]::KeyAvailable)
        {
            $key = [console]::readkey('noecho').Key

            for($p = 0; $p -lt $global:game_obj.Length; $p++)
            {
                if($global:game_obj[$p]['team'] -eq 'pacman' -and $global:game_obj[$p]['config']['joined'] -and $global:game_obj[$p]['active'])
                {
                    if($global:game_obj[$p]['config']['move_up_key'] -eq $key)
                    {
                        $global:game_obj[$p]['intended_move_dir'] = 'UpArrow'
                    }
                    elseif($global:game_obj[$p]['config']['move_down_key'] -eq $key)
                    {
                        $global:game_obj[$p]['intended_move_dir'] = 'DownArrow'
                    }
                    elseif($global:game_obj[$p]['config']['move_right_key'] -eq $key)
                    {
                        $global:game_obj[$p]['intended_move_dir'] = 'RightArrow'
                    }
                    elseif($global:game_obj[$p]['config']['move_left_key'] -eq $key)
                    {
                        $global:game_obj[$p]['intended_move_dir'] = 'LeftArrow'
                    }
                }
            }
        }
    }


    <#
    if($moveKeys -contains $key)
    {
        $global:pacman_last_pushed_dir = $key
    }
    #>

    if($key -eq 'Tab')
    {
        $global:show_debug = !$global:show_debug
    }
}


# little hacky, but we live with it
function ValidGhostMoves([string] $currentDir)
{
    switch($currentDir)
    {
        'LeftArrow'
        {
            return @(
                'LeftArrow',
                'UpArrow',
                'DownArrow'
            )
        }

        'RightArrow'
        {
            return @(
                'RightArrow',
                'UpArrow',
                'DownArrow'
            )
        }

        'UpArrow'
        {
            return @(
                'LeftArrow',
                'RightArrow',
                'UpArrow'
            )
        }

        'DownArrow'
        {
            return @(
                'LeftArrow',
                'RightArrow',
                'DownArrow'
            )
        }
    }
}


function UpdateIntendedPositions
{
    # right now the ghosts are just indexes 1-4, this is a hack, fix later
    # ...perhaps just check if team -eq 'ghost', but this is more efficient for now
    for($i = 0; $i -lt $global:game_obj.Length; $i++)
    {
        if(-not($global:game_obj[$i]['active']))
        {
            continue
        }

        # update ghost AI movement
        if($global:game_obj[$i]['team'] -eq 'ghost')
        {
            # ghosts only move every other update when 'edible'
            if($global:game_obj[$i]['edible'] -and $global:mode_frame_counter % 2 -eq 0)
            {
                continue
            }

            # this removes the opposite direction
            $moveDirs = ValidGhostMoves($global:game_obj[$i]['move_dir'])

            $validMoves = @()
            foreach($moveDir in $moveDirs)
            {
                if(isValidMoveDir $moveDir $global:game_obj[$i]['pos_x'] $global:game_obj[$i]['pos_y'])
                {
                    $validMoves += $moveDir
                }
            }

            #select a direction randomly
            $max = $validMoves.Length # not minusing one, because max is not inclusive in random
            
            # this should never happen, but I've seen it occasionally... patchity hack.
            if($max -eq 0)
            {
                $global:game_obj[$i]['intended_x'] = $global:game_obj[$i]['pos_x']
                $global:game_obj[$i]['intended_y'] = $global:game_obj[$i]['pos_y']
                continue
            }

            if($validMoves.Length -eq 1)
            {
                $index = 0
            }
            else
            {
                $seed = Get-Random
                $index = Get-Random -minimum 0 -maximum $max -SetSeed $seed
            }

            $move_dir = $validMoves[$index]

            #adjust the x,y coordinates for this ghost
            $global:game_obj[$i]['move_dir'] = $move_dir
        }
        elseif($global:game_obj[$i]['team'] -eq 'pacman' -and $global:game_obj[$i]['config']['joined'] -and $global:game_obj[$i]['active'])
        {
            if($global:game_obj[$i]['active'] -eq 0)
            {
                continue
            }

            if(isValidMoveDir $global:game_obj[$i]['intended_move_dir'] $global:game_obj[$i]['pos_x'] $global:game_obj[$i]['pos_y'])
            {
                $global:game_obj[$i]['move_dir'] = $game_obj[$i]['intended_move_dir']
            }

            if(-not (isValidMoveDir $global:game_obj[$i]['move_dir'] $global:game_obj[$i]['pos_x'] $global:game_obj[$i]['pos_y']))
            {
                continue
                #CommonIntendedPosition $i $global:game_obj[0]['move_dir']
            }
            $move_dir = $global:game_obj[$i]['move_dir']
        }


        $intended_x = $global:game_obj[$i]['pos_x']
        $intended_y = $global:game_obj[$i]['pos_y']

        switch($move_dir)
        {
            'LeftArrow'
            {
                $intended_x += -1
            }

            'RightArrow'
            {
                $intended_x += 1
            }

            'UpArrow'
            {
                $intended_y += -1
            }

            'DownArrow'
            {
                $intended_y += 1
            }
        }

        # wrap around for tunnels
        if($intended_x -lt 0)
        {
            $intended_x = $global:mapArray[0].Length - 1
        }

        # last 
        if($intended_x -gt $global:mapArray[0].Length - 1)
        {
            $intended_x = 0;
        }
        
        $global:game_obj[$i]['intended_x'] = $intended_x
        $global:game_obj[$i]['intended_y'] = $intended_y
        
    }
}


function HandleCollisions
{
    #TODO: change this so if a game object has collided, don't continue to check them
    for($x = 0; $x -lt $global:game_obj.Length; $x++)
    {
        # inactive game objects are not collidable
        if($global:game_obj[$x]['active'] -eq 0 -or ($global:game_obj[$x]['team'] -eq 'pacman' -and $global:game_obj[$x]['config']['joined'] -eq 0))
        {
            continue
        }

        for($y = 0; $y -lt $global:game_obj.Length; $y++)
        {
            # inactive game objects are not collidable
            if($global:game_obj[$y]['active'] -eq 0 -or ($global:game_obj[$y]['team'] -eq 'pacman' -and $global:game_obj[$y]['config']['joined'] -eq 0))
            {
                continue
            }

            # can't collide with yourself
            if($x -eq $y)
            {
                continue
            }

            # both landing on the same position?
            if($global:game_obj[$x]['intended_x'] -eq $global:game_obj[$y]['intended_x'] -and $global:game_obj[$x]['intended_y'] -eq $global:game_obj[$y]['intended_y'])
            {
                # two ghosts don't collide, everyone else does
                if(-not($global:game_obj[$x]['team'] -eq $global:game_obj[$y]['team'] -and $global:game_obj[$y]['team'] -eq 'ghost'))
                {
                    $eaten = CheckEatenCollision $x $y
                    if($eaten)
                    {
                        $global:sw.Reset()
                        $global:sw.Start()

                        $eatPlayer.Play()
                        break
                    }

                    # invalidate just the current actors move?
                    $global:game_obj[$x]['intended_x'] = $global:game_obj[$x]['pos_x']
                    $global:game_obj[$x]['intended_y'] = $global:game_obj[$x]['pos_y']

                    # both pacman?
                    if($global:game_obj[$x]['team'] -eq 'pacman' -and $global:game_obj[$y]['team'] -eq 'pacman')
                    {
                        $global:game_obj[$x]['intended_x'] = $global:game_obj[$x]['pos_x']
                        $global:game_obj[$x]['intended_y'] = $global:game_obj[$x]['pos_y']
                    }
                    elseif($global:game_obj[$x]['team'] -eq 'pacman')
                    {
                        $global:pending_death = $x
                    }
                    else
                    {
                        $global:pending_death = $y
                    }
                        
                    break                
                }
            }

            # This is a special check for head on collisions, so they don't
            # pass each other instead of colliding.

            # you are moving to where they were last frame...
            $x_cross = $global:game_obj[$x]['intended_x'] -eq $global:game_obj[$y]['pos_x'] -and $global:game_obj[$x]['intended_y'] -eq $global:game_obj[$y]['pos_y']
            
            # ...and they are moving to where you were last frame
            $y_cross = $global:game_obj[$y]['intended_x'] -eq $global:game_obj[$x]['pos_x'] -and $global:game_obj[$y]['intended_y'] -eq $global:game_obj[$x]['pos_y']
            
            if($x_cross -and $y_cross)
            {
                # two ghosts don't collide, everyone else does
                if(-not($global:game_obj[$x]['team'] -eq $global:game_obj[$y]['team'] -and $global:game_obj[$y]['team'] -eq 'ghost'))
                {
                    $eaten = CheckEatenCollision $x $y
                    if($eaten)
                    {
                        $eatPlayer.Play()
                        break
                    }

                    # both moves are invalidated
                    $global:game_obj[$x]['intended_x'] = $global:game_obj[$x]['pos_x']
                    $global:game_obj[$x]['intended_y'] = $global:game_obj[$x]['pos_y']
                
                    $global:game_obj[$y]['intended_x'] = $global:game_obj[$y]['pos_x']
                    $global:game_obj[$y]['intended_y'] = $global:game_obj[$y]['pos_y']

                    # both pacman?
                    if($global:game_obj[$x]['team'] -eq 'pacman' -and $global:game_obj[$y]['team'] -eq 'pacman')
                    {
                        $global:game_obj[$x]['intended_x'] = $global:game_obj[$x]['pos_x']
                        $global:game_obj[$x]['intended_y'] = $global:game_obj[$x]['pos_y']
                    }
                    elseif($global:game_obj[$y]['team'] -eq 'pacman')
                    {
                        $global:pending_death = $y
                    }
                    else
                    {
                        $global:pending_death = $x
                    }
                    break
                }
            }
        }
    }
}

function CheckEatenCollision($x, $y)
{
    $eaten = -1

    $ghost = $global:game_obj[$x]['team'] -eq 'ghost' -or $global:game_obj[$y]['team'] -eq 'ghost'
    #if one is ghost and the other is pacman, if the ghost is edible, we have an "eaten" collision
    if($ghost)
    {
        if($global:game_obj[$x]['edible'])
        {
            $eaten = $x
            $scored = $y
        }
        elseif($global:game_obj[$y]['edible'])
        {
            $eaten = $y
            $scored = $x
        }
    }

    #if both are pacman
    else
    {
        if($global:game_obj[$x]['powered_frame'] -gt -1)
        {
            $eaten = $y
            $scored = $x
        }
        elseif($global:game_obj[$y]['powered_frame'] -gt -1)
        {
            $eaten = $x
            $scored = $y
        }
    }

    if($eaten -gt -1)
    {
        # for multiplayer only
        if($global:game_obj[$eaten]['team'] -eq 'pacman')
        {
            RemovePlayer($eaten)
            $global:active_players--
        }

        #$global:game_obj[$eaten]['pos_x'] = $global:game_obj[$eaten]['start_x']
        #$global:game_obj[$eaten]['pos_y'] = $global:game_obj[$eaten]['start_y']
        $global:game_obj[$eaten]['intended_x'] = $global:game_obj[$eaten]['start_x']
        $global:game_obj[$eaten]['intended_y'] = $global:game_obj[$eaten]['start_y']

        #$global:game_obj[$eaten]['move_dir'] = 'None'
        $global:game_obj[$eaten]['intended_move_dir'] = 'None'

        $global:game_obj[$eaten]['edible'] = 0
        $global:game_obj[$scored]['score'] += 200
        #$global:score += 200
        return 1
    }
    return 0

}


# pellet scoring must occur after collisions resolved
function HandlePellets
{
    for($i = 0; $i -lt $global:game_obj.Length; $i++)
    {
        if($global:game_obj[$i]['team'] -eq 'pacman')
        {
            $mapChar = $global:mapArray[$global:game_obj[$i]['pos_y']][$global:game_obj[$i]['pos_x']]
            if($mapChar -eq '·')
            {
                if(-not($global:sw.get_IsRunning) -or $global:sw.ElapsedMilliseconds -gt 500)
                {
                    $global:sw.Stop()

                    $blipPlayer.Play()
                }

            }

            if($mapChar -eq '∙')
            {
                $global:sw.Reset()
                $global:sw.Start()
                $powerPlayer.Play()
            }

            if($mapChar -eq '∙' -or $mapChar -eq '·')
            {

                $global:game_obj[$i]['score'] += 10
                $global:mapArray[$global:game_obj[$i]['pos_y']][$global:game_obj[$i]['pos_x']] = '#'
                $global:pellet_count--
            }
 
            if($mapChar -eq '∙')
            {
                $global:power_pellet_mode = 1
                $global:game_obj[$i]['powered_frame'] = 0
                for($g = 0; $g -lt $global:game_obj.Length; $g++)
                {
                    if($global:game_obj[$g]['team'] -eq 'ghost')
                    {
                        $global:game_obj[$g]['edible'] = 1
                    }
                }

                $global:mode_frame_counter = 0
                ReverseAllGhostDirection
            }
        }
    }
 }

function PrintDebugConsole
{
    $start_line = 26
    $column2 = 45

    if(-not($global:show_debug))
    {
        for($i = $start_line; $i -le 50; $i++)
        {
            PosWrite '                                                                                           ' 0 $i 'black' 'white'
        }
        return
    }

    PosWrite 'Active players: ', $global:active_players,'     ' 1 $start_line 'black' 'white'
    $start_line++
    PosWrite 'Frame counter: ', $global:mode_frame_counter,'     ' 1 $start_line 'black' 'white'
    $start_line++
    PosWrite 'Pellet count: ', $global:pellet_count,'     ' 1 $start_line 'black' 'white'
    $start_line++
    PosWrite '                                                     ' 1 $start_line 'black' 'white'
    $start_line++

    PosWrite 'Player 1 x: ', $global:game_obj[0]['pos_x'],'     ' 1 $start_line 'black' 'white'
    $start_line++
    PosWrite 'Player 1 y: ', $global:game_obj[0]['pos_y'],'     ' 1 $start_line 'black' 'white'
    $start_line++
    PosWrite 'Player 1 move dir: ', $global:game_obj[0]['move_dir'],'     ' 1 $start_line 'black' 'white'
    $start_line++
    PosWrite 'Player 1 intended move dir: ', $global:game_obj[0]['intended_move_dir'],'     ' 1 $start_line 'black' 'white'
    $start_line++
    PosWrite 'power frame: ', $global:game_obj[0]['powered_frame'],'     ' 1 $start_line 'black' 'white'
    $start_line++
    PosWrite 'joined: ', $global:game_obj[0]['config']['joined'],'     ' 1 $start_line 'black' 'white'
    $start_line++
    PosWrite 'active: ', $global:game_obj[0]['active'],'     ' 1 $start_line 'black' 'white'
    $start_line++
    PosWrite '                                                     ' 1 $start_line 'black' 'white'
    $start_line -= 4

    PosWrite 'Player 2 x: ', $global:game_obj[5]['pos_x'],'     ' $column2 $start_line 'black' 'white'
    $start_line++
    PosWrite 'Player 2 y: ', $global:game_obj[5]['pos_y'],'     ' $column2 $start_line 'black' 'white'
    $start_line++
    PosWrite 'Player 2 move dir: ', $global:game_obj[5]['move_dir'],'     ' $column2 $start_line 'black' 'white'
    $start_line++
    PosWrite 'Player 2 intended move dir: ', $global:game_obj[5]['intended_move_dir'],'     ' $column2 $start_line 'black' 'white'
    $start_line++
    PosWrite 'joined: ', $global:game_obj[5]['config']['joined'],'     ' $column2 $start_line 'black' 'white'
    $start_line++
    PosWrite 'active: ', $global:game_obj[5]['active'],'     ' $column2 $start_line 'black' 'white'
    $start_line++
    PosWrite '                                                     ' $column2 $start_line 'black' 'white'
    $start_line++

    PosWrite 'Player 3 x: ', $global:game_obj[6]['pos_x'],'     ' 1 $start_line 'black' 'white'
    $start_line++
    PosWrite 'Player 3 y: ', $global:game_obj[6]['pos_y'],'     ' 1 $start_line 'black' 'white'
    $start_line++
    PosWrite 'Player 3 move dir: ', $global:game_obj[6]['move_dir'],'     ' 1 $start_line 'black' 'white'
    $start_line++
    PosWrite 'Player 3 intended move dir: ', $global:game_obj[6]['intended_move_dir'],'     ' 1 $start_line 'black' 'white'
    $start_line++
    PosWrite '                                                     ' 1 $start_line 'black' 'white'
    $start_line -= 4

    PosWrite 'Player 4 x: ', $global:game_obj[7]['pos_x'],'     ' $column2 $start_line 'black' 'white'
    $start_line++
    PosWrite 'Player 4 y: ', $global:game_obj[7]['pos_y'],'     ' $column2 $start_line 'black' 'white'
    $start_line++
    PosWrite 'Player 4 move dir: ', $global:game_obj[7]['move_dir'],'     ' $column2 $start_line 'black' 'white'
    $start_line++
    PosWrite 'Player 4 intended move dir: ', $global:game_obj[7]['intended_move_dir'],'     ' $column2 $start_line 'black' 'white'
    $start_line += 2



    PosWrite 'Blinky x: ', $global:game_obj[1]['pos_x'],'     ' 1 $start_line 'black' 'white'
    $start_line++
    PosWrite 'Blinky y: ', $global:game_obj[1]['pos_y'],'     ' 1 $start_line 'black' 'white'
    $start_line++
    PosWrite 'Blinky move dir: ', $global:game_obj[1]['move_dir'],'     ' 1 $start_line 'black' 'white'
    $start_line++
    PosWrite '                                                     ' 1 $start_line 'black' 'white'
    $start_line -= 3

    PosWrite 'Pinky x: ', $global:game_obj[2]['pos_x'],'     ' $column2 $start_line 'black' 'white'
    $start_line++
    PosWrite 'Pinky y: ', $global:game_obj[2]['pos_y'],'     ' $column2 $start_line 'black' 'white'
    $start_line++
    PosWrite 'Pinky move dir: ', $global:game_obj[2]['move_dir'],'     ' $column2 $start_line 'black' 'white'
    $start_line++
    PosWrite '                                                     ' $column2 $start_line 'black' 'white'
    $start_line++

    PosWrite 'Inky x: ', $global:game_obj[3]['pos_x'],'     ' 1 $start_line 'black' 'white'
    $start_line++
    PosWrite 'Inky y: ', $global:game_obj[3]['pos_y'],'     ' 1 $start_line 'black' 'white'
    $start_line++
    PosWrite 'Inky move dir: ', $global:game_obj[3]['move_dir'],'     ' 1 $start_line 'black' 'white'
    $start_line++
    PosWrite '                                                     ' 1 $start_line 'black' 'white'
    $start_line -= 3

    PosWrite 'Clyde x: ', $global:game_obj[4]['pos_x'],'     ' $column2 $start_line 'black' 'white'
    $start_line++
    PosWrite 'Clyde y: ', $global:game_obj[4]['pos_y'],'     ' $column2 $start_line 'black' 'white'
    $start_line++
    PosWrite 'Clyde move dir: ', $global:game_obj[4]['move_dir'],'     ' $column2 $start_line 'black' 'white'
    $start_line++
    PosWrite '                                                     ' $column2 $start_line 'black' 'white'
    $start_line++



}

function DrawScoreBar
{
    # color for each player
    $x_pos = 1
    for($i = 0; $i -lt $global:game_obj.Length; $i++)
    {
        if($global:game_obj[$i]['team'] -eq 'pacman' -and $global:game_obj[$i]['config']['joined'])
        {
            if($global:game_obj[$i]['config']['joined'])
            {
                PosWrite $global:game_obj[$i]['score'] $x_pos 24 'black' $global:game_obj[$i]['color']
            }
            $x_pos += 10
        }
    }

    if($global:mode_key -eq 's')
    {
        $lives_str = "O " * $global:lives
        $lives_str += "              "
        PosWrite $lives_str 15 24 'black' 'yellow'
    }
}



# TODO: put draw map back in the game logic after a drawing function has been created
Clear-Host
[Console]::WindowWidth = 120
[Console]::WindowHeight = 50
[Console]::BufferWidth = 120
[Console]::BufferHeight = 50

while(1)
{
    StartScreen
    if($global:mode_key -eq 'm')
    {
        MultiplayerSetupScreen
    }
    else
    {
        $global:lives = 3
    }

    ResetScores
    SetupGame
    DrawMap
    DrawPellets

    while(1)
    {
        HandleMoveInput
        UpdateIntendedPositions
 
        HandleCollisions

        DrawCharacters
        HandlePellets
    

        if($global:pending_death -gt -1)
        {
            HandleDeaths
            ResetPositions
            $global:pending_death = -1
        }
        
        if(CheckForEndOfGame)
        {
            if($global:mode_key -eq 'm')
            {
                FlashMap
            }
            GameOverScreen
            break
        }


        DrawScoreBar
        #PrintDebugConsole
 
        if($global:power_pellet_mode)
        {
            $global:mode_frame_counter++
            if($global:mode_frame_counter -gt 60)
            {
                #TODO: Alternate ghost flashing when the frame counter is the near the end
                for($i = 0; $i -lt $global:game_obj.Length; $i++)
                {
                    if($global:game_obj[$i]['team'] -eq 'ghost')
                    {
                        $global:game_obj[$i]['edible'] = 0
                    }
                    $global:power_pellet_mode = 0 # need this for power pellet music?
                }
            }

            # check individual powered up frames, important for multiplayer
            for($i = 0; $i -lt $global:game_obj.Length; $i++)
            {
                if($global:game_obj[$i]['team'] -eq 'pacman' -and $global:game_obj[$i]['powered_frame'] -gt -1)
                {
                    $global:game_obj[$i]['powered_frame']++
                    if($global:game_obj[$i]['powered_frame'] -gt 60)
                    {
                        $global:game_obj[$i]['powered_frame'] = -1
                    }
                }
            }

        }

        if($global:pellet_count -eq 0)
        {
            FlashMap
            SetupGame
            DrawMap
            DrawPellets  
        }

        Start-Sleep -m 66
    }
}
