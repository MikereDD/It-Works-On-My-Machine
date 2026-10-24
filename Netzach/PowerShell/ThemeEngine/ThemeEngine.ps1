#--------------------------------------------
# file:     ThemeEngine.ps1
# author:   Mike Redd
# version:  0.1-dev
# desc:     Typezero ThemeEngine — Netzach PowerShell renderer
#--------------------------------------------

[CmdletBinding(PositionalBinding = $false)]
param(
    [Parameter(Position = 0)]
    [ValidateSet("bootstrap","list","current","status","preview","apply","apply-shell","apply-font","apply-desktop","apply-shell-font","apply-desktop-shell","apply-all","reload","rollback","wallpaper","font","configure","doctor","doctor-view","help")]
    [string]$Command = "help",

    [Parameter(Position = 1)]
    [string]$Theme,

    [string]$RepoRoot,

    # An explicit, unsaved Terminal font for this apply only.
    [System.Collections.IDictionary]$TerminalFont,

    # Optional snapshot from font preview, used to reject intervening edits.
    [string]$ExpectedSettingsSha256,


    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$WallpaperArgs
)

$ErrorActionPreference = "Stop"

if ($PSBoundParameters.ContainsKey('TerminalFont') -and $Command -cnotin @('apply','apply-font','apply-shell-font','apply-all')) {
    throw 'TerminalFont is allowed only with apply, apply-font, apply-shell-font, or apply-all.'
}
if ($PSBoundParameters.ContainsKey('ExpectedSettingsSha256') -and
    $Command -cnotin @('apply','apply-shell','apply-font','apply-shell-font','apply-desktop-shell','apply-all') -and
    ($Command -cne 'font' -or $Theme -cnotin @('apply-font','apply-theme','apply-preset'))) {
    throw 'ExpectedSettingsSha256 is allowed only with an operation that requests Terminal settings.'
}
if ($ExpectedSettingsSha256 -and $ExpectedSettingsSha256 -cnotmatch '\A[A-Fa-f0-9]{64}\z') {
    throw 'ExpectedSettingsSha256 must be a SHA-256 snapshot.'
}


$EngineRoot   = Join-Path $env:LOCALAPPDATA "Typezero\ThemeEngine"
$ThemesRoot   = Join-Path $EngineRoot "themes"
$TemplatesRoot = Join-Path $EngineRoot "templates"
$CurrentFile  = Join-Path $EngineRoot "current-theme"
$PreviousFile = Join-Path $EngineRoot "previous-theme"
$CurrentPs1   = Join-Path $EngineRoot "current.ps1"

# Read-only commands, including font Preview, must not create configuration.
if ($Command -in @('bootstrap','apply','reload','rollback')) {
    New-Item -ItemType Directory -Force -Path $EngineRoot | Out-Null
}

function Read-ThemeFile {
    param([Parameter(Mandatory)][string]$Id)

    $path = Join-Path (Join-Path $ThemesRoot $Id) "theme.conf"
    if (-not (Test-Path -LiteralPath $path)) {
        throw "Theme not found: $Id"
    }

    $result = [ordered]@{}
    foreach ($raw in Get-Content -LiteralPath $path) {
        $line = $raw.Trim()
        if (-not $line -or $line.StartsWith("#") -or -not $line.Contains("=")) { continue }

        $idx = $line.IndexOf("=")
        $key = $line.Substring(0, $idx).Trim()
        $val = $line.Substring($idx + 1).Trim()

        if (($val.StartsWith('"') -and $val.EndsWith('"')) -or
            ($val.StartsWith("'") -and $val.EndsWith("'"))) {
            $val = $val.Substring(1, $val.Length - 2)
        }

        $result[$key] = $val
    }

    # Interaction-state roles extend the semantic palette without breaking
    # existing themes. Missing values inherit the exact roles ThemeEngine
    # historically used for these surfaces.
    if (-not $result.Contains("SELECTION") -or -not $result["SELECTION"]) {
        $result["SELECTION"] = $result["BORDER"]
    }
    if (-not $result.Contains("CURSOR") -or -not $result["CURSOR"]) {
        $result["CURSOR"] = $result["ACCENT_BRIGHT"]
    }
    if (-not $result.Contains("FOCUS") -or -not $result["FOCUS"]) {
        $result["FOCUS"] = $result["ACCENT"]
    }

    return $result
}

function Write-ThemeTemplate {
    param(
        [Parameter(Mandatory)][string]$Source,
        [Parameter(Mandatory)][string]$Destination,
        [Parameter(Mandatory)][System.Collections.IDictionary]$Theme
    )

    # Shared templates use {{ROLE}} tokens matching theme.conf keys. Rendering
    # from the parsed theme dictionary keeps consumer files palette-agnostic
    # and gives Windows the same template contract used by Arakiel.
    if (-not (Test-Path -LiteralPath $Source)) {
        throw "Theme template not found: $Source"
    }

    $content = Get-Content -LiteralPath $Source -Raw
          # Vim runtime files must use deterministic LF endings on every platform.
    # Normalizing template input here prevents carriage returns from surviving
    # rendering as literal ^M characters that Vim interprets as command text.
    $content = $content -replace "`r`n", "`n"
    $content = $content -replace "`r", "`n"

    foreach ($key in $Theme.Keys) {
        $content = $content.Replace("{{$key}}", [string]$Theme[$key])
    }

    $parent = Split-Path -Parent $Destination
    New-Item -ItemType Directory -Force -Path $parent | Out-Null
    Set-Content -LiteralPath $Destination -Value $content -NoNewline -Encoding utf8
}
function Convert-HexToAnsi {
    param([Parameter(Mandatory)][string]$Hex)

    $h = $Hex.TrimStart("#")
    if ($h.Length -ne 6) { throw "Invalid RGB color: $Hex" }

    $r = [Convert]::ToInt32($h.Substring(0, 2), 16)
    $g = [Convert]::ToInt32($h.Substring(2, 2), 16)
    $b = [Convert]::ToInt32($h.Substring(4, 2), 16)

    return "$([char]27)[38;2;$r;$g;$($b)m"
}

function Write-CurrentTheme {
    param([Parameter(Mandatory)][System.Collections.IDictionary]$T)

    $name      = $T["THEME_NAME"].Replace("'", "''")
    $id        = $T["THEME_ID"].Replace("'", "''")

    $accent    = Convert-HexToAnsi $T["ACCENT"]
    $accentHi  = Convert-HexToAnsi $T["ACCENT_BRIGHT"]
    $success   = Convert-HexToAnsi $T["SUCCESS"]
    $warning   = Convert-HexToAnsi $T["WARNING"]
    $error     = Convert-HexToAnsi $T["ERROR"]
    $muted     = Convert-HexToAnsi $T["MUTED"]
    $text      = Convert-HexToAnsi $T["TEXT"]
    $bright    = Convert-HexToAnsi $T["BRIGHT"]
    $secondary = Convert-HexToAnsi $T["SECONDARY"]
    $info      = Convert-HexToAnsi $T["INFO"]

    $content = @"
# Generated by Typezero ThemeEngine — $name
`$esc = [char]27
`$global:TE_Theme = [ordered]@{
    Id           = '$id'
    Name         = '$name'
    Accent       = '$accent'
    AccentBright = '$accentHi'
    Success      = '$success'
    Warning      = '$warning'
    Error        = '$error'
    Muted        = '$muted'
    Text         = '$text'
    Bright       = '$bright'
    Secondary    = '$secondary'
    Info         = '$info'
    Reset        = "`$esc[0m"
    Bold         = "`$esc[1m"
    Dim          = "`$esc[2m"
}
"@

    Set-Content -LiteralPath $CurrentPs1 -Value $content -Encoding utf8
}

function Get-WindowsTerminalSettingsPath {
    # Windows Terminal's packaged settings location. ThemeEngine deliberately
    # manages only the named Typezero scheme and the PowerShell profile's
    # colorScheme and saved font; unrelated Terminal settings remain untouched.
    $packagePath = Join-Path $env:LOCALAPPDATA `
        "Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json"

    if (Test-Path -LiteralPath $packagePath) {
        return $packagePath
    }

    return $null
}

function Set-WindowsTerminalTheme {
    param([Parameter(Mandatory)][System.Collections.IDictionary]$T,
        [System.Collections.IDictionary]$TerminalFont,
        [ValidateSet('Shell','Font','ShellFont','All')][string]$Operation = 'All',
        [string]$ExpectedSettingsSha256,
        [switch]$PassThru)

    $settingsPath = Get-WindowsTerminalSettingsPath
    if (-not $settingsPath) {
        if ($PassThru) { throw 'Windows Terminal settings were not found; no Terminal changes applied.' }
        return $false
    }

    # A complete ANSI palette is required before ThemeEngine touches Terminal.
    # Themes without one remain valid for other renderers and are simply
    # skipped here rather than receiving guessed or partially mapped colors.
    $ansiKeys = @(
        "ANSI_BLACK",
        "ANSI_RED",
        "ANSI_GREEN",
        "ANSI_YELLOW",
        "ANSI_BLUE",
        "ANSI_PURPLE",
        "ANSI_CYAN",
        "ANSI_WHITE",
        "ANSI_BRIGHT_BLACK",
        "ANSI_BRIGHT_RED",
        "ANSI_BRIGHT_GREEN",
        "ANSI_BRIGHT_YELLOW",
        "ANSI_BRIGHT_BLUE",
        "ANSI_BRIGHT_PURPLE",
        "ANSI_BRIGHT_CYAN",
        "ANSI_BRIGHT_WHITE"
    )

    foreach ($key in $ansiKeys) {
        if ($Operation -cne 'Font' -and (-not $T.Contains($key) -or $T[$key] -cnotmatch '\A#[A-Fa-f0-9]{6}\z')) {
            if ($PassThru) { throw "Theme has no complete Terminal palette ($key)." }
            Write-Host "Windows Terminal: skipped (theme has no complete ANSI palette)"
            return $false
        }
    }
    if ($Operation -cne 'Font') {
        foreach ($key in @('BG','TEXT','CURSOR','SELECTION')) {
            if ($T[$key] -cnotmatch '\A#[A-Fa-f0-9]{6}\z') { throw "Invalid Terminal palette role: $key" }
        }
    }

    $schemeName = "Typezero $($T['THEME_NAME'])"

    $scheme = [ordered]@{
        name                = $schemeName
        background          = $T["BG"]
        foreground          = $T["TEXT"]
        cursorColor         = $T["CURSOR"]
        selectionBackground = $T["SELECTION"]
        black               = $T["ANSI_BLACK"]
        red                 = $T["ANSI_RED"]
        green               = $T["ANSI_GREEN"]
        yellow              = $T["ANSI_YELLOW"]
        blue                = $T["ANSI_BLUE"]
        purple              = $T["ANSI_PURPLE"]
        cyan                = $T["ANSI_CYAN"]
        white               = $T["ANSI_WHITE"]
        brightBlack         = $T["ANSI_BRIGHT_BLACK"]
        brightRed           = $T["ANSI_BRIGHT_RED"]
        brightGreen         = $T["ANSI_BRIGHT_GREEN"]
        brightYellow        = $T["ANSI_BRIGHT_YELLOW"]
        brightBlue          = $T["ANSI_BRIGHT_BLUE"]
        brightPurple        = $T["ANSI_BRIGHT_PURPLE"]
        brightCyan          = $T["ANSI_BRIGHT_CYAN"]
        brightWhite         = $T["ANSI_BRIGHT_WHITE"]
    }

    $terminalThemeName = "Typezero ThemeEngine"

    $terminalTheme = [ordered]@{
        name = $terminalThemeName
        window = [ordered]@{
            applicationTheme = "dark"
        }
        tab = [ordered]@{
            background          = "terminalBackground"
            unfocusedBackground = $T["BG"]
            showCloseButton      = "hover"
        }
        tabRow = [ordered]@{
            background          = $T["BG"]
            unfocusedBackground = $T["BG"]
        }
    }

    . (Join-Path $PSScriptRoot 'FontMapping-WindowsTerminal.ps1')
    . (Join-Path $PSScriptRoot 'TerminalSettings-WindowsTerminal.ps1')
    $font = $null
    $id = [string]$T['THEME_ID']
    if ($Operation -ceq 'Shell') {
        # Do not even read saved font mappings for a colors-only request.
    }
    elseif ($null -ne $TerminalFont) {
        $font = $TerminalFont
    }
    else {
        $config = Get-TypezeroWindowsFontMappings
        if ($config.Mappings.ContainsKey($id)) {
            $saved = $config.Mappings[$id]
            # Explicit theme apply uses that theme's saved preference. The legacy
            # Enabled flag gates old fixture planners, not this requested operation.
            $font = if ($config.Version -eq 2) {
                [ordered]@{ face=[string]$saved.Family; size=[double]$saved.Size; weight=[string]$saved.Weight }
            } else {
                # Old mappings contain only a family; retain the user's size/weight.
                [ordered]@{ face=[string]$saved }
            }
        }
    }
    # Status comparison and replacement share one snapshot, including direct
    # commands with no preview hash. An intervening edit is rejected by writer.
    $beforeBytes = [IO.File]::ReadAllBytes($settingsPath)
    $beforeHash = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($beforeBytes))
    if ($ExpectedSettingsSha256 -and $beforeHash -ine $ExpectedSettingsSha256) {
        throw 'Terminal settings changed since the expected snapshot.'
    }
    $offset = if ($beforeBytes.Length -ge 3 -and $beforeBytes[0] -eq 239 -and $beforeBytes[1] -eq 187 -and $beforeBytes[2] -eq 191) {3} else {0}
    $beforeText = [Text.UTF8Encoding]::new($false,$true).GetString($beforeBytes,$offset,$beforeBytes.Length-$offset)
    $fontChanged = $null -ne $font -and (New-TypezeroTerminalFontText -Text $beforeText -Font $font) -cne $beforeText
    $shellChanged = $false
    if ($Operation -cne 'Font') {
        $chrome = if ($Operation -ceq 'All') { $terminalTheme } else { $null }
        $shellChanged = (New-TypezeroTerminalThemeText -Text $beforeText -Scheme $scheme -TerminalTheme $chrome -Font $null) -cne $beforeText
    }
    if ($Operation -ceq 'Font') {
        $update = if ($null -ne $font) {
            Set-TypezeroWindowsTerminalFont -Path $settingsPath -Font $font -ExpectedSha256 $beforeHash
        } else {
            # An unmapped font is an explicit no-op, but invalid/ambiguous
            # settings are still a failure of the requested Terminal target.
            $null = Get-TypezeroJsoncTree $beforeText
            $settings = ConvertFrom-Json -InputObject $beforeText -AsHashtable
            $profiles = @($settings.profiles.list | Where-Object { $_.guid -ieq '{574e775e-4f2a-5b96-ac1e-a2962a402336}' })
            if ($profiles.Count -ne 1 -or ($profiles[0].Contains('font') -and $profiles[0].font -isnot [System.Collections.IDictionary])) {
                throw 'Expected exactly one valid PowerShell 7 Terminal profile.'
            }
            if ((Get-FileHash -LiteralPath $settingsPath -Algorithm SHA256).Hash -ine $beforeHash) { throw 'Terminal settings changed during no-op assessment.' }
            [pscustomobject]@{Changed=$false;BackupPath=$null;Path=$settingsPath}
        }
    }
    else {
        # Scoped shell operations own only schemes/profile colors. The original
        # full apply continues to own Terminal tab/window chrome as before.
        $chrome = if ($Operation -ceq 'All') { $terminalTheme } else { $null }
        $update = Set-TypezeroWindowsTerminalAppearance -Path $settingsPath `
            -Scheme $scheme -TerminalTheme $chrome -Font $font -ExpectedSha256 $beforeHash
        Write-Host "Windows Terminal: $schemeName"
    }
    if ($null -ne $font) { Write-Host ("Windows Terminal font: " + ($font | ConvertTo-Json -Compress)) }
    if ($update.Changed) { Write-Host "Windows Terminal backup: $($update.BackupPath)" }
    if ($PassThru) {
        $update | Add-Member -NotePropertyName FontSkipped -NotePropertyValue ($null -eq $font) -Force
        $update | Add-Member -NotePropertyName FontChanged -NotePropertyValue ([bool]$fontChanged) -Force
        $update | Add-Member -NotePropertyName ShellChanged -NotePropertyValue ([bool]$shellChanged) -Force
        return $update
    }
    return $true
}
function Set-Theme {
    param(
        [Parameter(Mandatory)][string]$Id,
        [System.Collections.IDictionary]$TerminalFont,
        [ValidateSet('Shell','Font','Desktop','ShellFont','DesktopShell','All')][string]$Operation = 'All',
        [string]$ExpectedSettingsSha256,
        [switch]$NoHistory
    )


    if ($null -ne $TerminalFont -and $Operation -cnotin @('Font','ShellFont','All')) {
        throw 'This operation preserves the Terminal font; a font override is not allowed.'
    }
    if ($null -ne $TerminalFont) {
        if ($TerminalFont.Count -ne 3 -or @($TerminalFont.Keys | Where-Object { $_ -cnotin @('face','size','weight') }).Count) {
            throw 'A one-use Terminal font requires exactly face, size, and weight.'
        }
        . (Join-Path $PSScriptRoot 'TerminalFontControl-WindowsTerminal.ps1')
        $choice = Assert-TypezeroTerminalFontChoice -Family $TerminalFont['face'] `
            -Size $TerminalFont['size'] -Weight $TerminalFont['weight']
        $TerminalFont = [ordered]@{face=$choice.Family;size=$choice.Size;weight=$choice.Weight}
    }
    if ($Id -cnotmatch '\A[a-z0-9][a-z0-9-]*\z') { throw 'Invalid theme ID.' }
    $t = Read-ThemeFile $Id
    $hasShell = $Operation -cin @('Shell','ShellFont','DesktopShell','All')
    $hasFont = $Operation -cin @('Font','ShellFont','All')
    $hasDesktop = $Operation -cin @('Desktop','DesktopShell','All')
    if ($ExpectedSettingsSha256) {
        if (-not ($hasShell -or $hasFont) -or $ExpectedSettingsSha256 -cnotmatch '\A[A-Fa-f0-9]{64}\z') {
            throw 'A valid Terminal snapshot requires an operation that includes Terminal.'
        }
        $settings = Get-WindowsTerminalSettingsPath
        if (-not $settings -or (Get-FileHash -LiteralPath $settings -Algorithm SHA256).Hash -ine $ExpectedSettingsSha256) {
            throw 'Terminal settings changed since Preview; preview these choices again. No targets were applied.'
        }
    }
    $targets = [Collections.Generic.List[object]]::new()
    function Add-ApplyTarget {
        param([string]$Target,[string]$Status,[bool]$Changed,[string]$Message,[string]$BackupPath)
        $targets.Add([pscustomobject]@{Target=$Target;Status=$Status;Changed=$Changed;Message=$Message;BackupPath=$BackupPath})
    }
    # Each requested target is independent. A native activation timeout cannot
    # prevent Terminal or an enabled DisplayFusion mapping from being attempted.
    if ($hasDesktop) {
        try {
            $provider = Join-Path $PSScriptRoot 'WindowsAppearance.ps1'
            if (-not (Test-Path -LiteralPath $provider -PathType Leaf)) { throw 'Native Windows appearance provider is missing.' }
            . $provider
            $null = Set-TypezeroWindowsNativeTheme -Id $t['THEME_ID'] -Name $t['THEME_NAME'] -Accent $t['ACCENT']
            Add-ApplyTarget Desktop Applied $true 'Native Windows theme activation confirmed.'
        }
        catch { Add-ApplyTarget Desktop Failed $false $_.Exception.Message }
        try {
            $mapping = Join-Path $PSScriptRoot 'WallpaperMapping-DisplayFusion.ps1'
            if (-not (Test-Path -LiteralPath $mapping -PathType Leaf)) {
                $configured = Join-Path $env:LOCALAPPDATA 'Typezero\ThemeEngine\wallpaper-displayfusion.json'
                if (Test-Path -LiteralPath $configured) { throw 'Wallpaper mapping provider is missing; configured wallpaper could not be assessed.' }
                Add-ApplyTarget Wallpaper Skipped $false 'No DisplayFusion mapping is configured.'
            }
            else {
                . $mapping
                $config = Get-TypezeroWallpaperMappings
                if (-not $config.Enabled -or -not $config.Profiles.ContainsKey($Id)) {
                    Add-ApplyTarget Wallpaper Skipped $false 'DisplayFusion mapping is disabled or this theme is unmapped.'
                }
                else {
                    $provider = Join-Path $PSScriptRoot 'WallpaperProvider-DisplayFusion.ps1'
                    if (-not (Test-Path -LiteralPath $provider -PathType Leaf)) { throw 'Configured DisplayFusion wallpaper provider is missing.' }
                    . $provider
                    $state = Test-TypezeroWallpaperThemeMapping -ThemeId $Id
                    switch ($state.Action) {
                        'ALREADY ACTIVE - no changes' { Add-ApplyTarget Wallpaper NoChange $false 'Configured DisplayFusion profile is already active.' }
                        'ELIGIBLE FOR EXPLICIT SWITCH' {
                            $wallpaper = Invoke-TypezeroWallpaperThemeMapping -ThemeId $Id -Execute -Confirm:$false -ErrorAction Stop
                            if ($null -eq $wallpaper -or $wallpaper.Status -notin @('VERIFIED','VERIFIED - COMMAND TIMEOUT','NO CHANGE')) {
                                throw 'DisplayFusion wallpaper activation did not return verified success.'
                            }
                            $changed = $wallpaper.Status -cne 'NO CHANGE'
                            Add-ApplyTarget Wallpaper $(if ($changed) {'Applied'} else {'NoChange'}) $changed "DisplayFusion profile: $($wallpaper.ProfileName) [$($wallpaper.Status)]" $wallpaper.BackupPath
                        }
                        default { throw "Configured DisplayFusion wallpaper could not be applied: $($state.Action)" }
                    }
                }
            }
        }
        catch { Add-ApplyTarget Wallpaper Failed $false $_.Exception.Message }
    }
    if ($hasShell -or $hasFont) {
        try {
            $terminalOperation = if ($Operation -ceq 'All') {'All'} elseif ($hasShell -and $hasFont) {'ShellFont'} elseif ($hasShell) {'Shell'} else {'Font'}
            $terminal = Set-WindowsTerminalTheme $t -TerminalFont $TerminalFont -Operation $terminalOperation `
                -ExpectedSettingsSha256 $ExpectedSettingsSha256 -PassThru
            if ($hasShell) {
                Add-ApplyTarget Shell $(if ($terminal.ShellChanged) {'Applied'} else {'NoChange'}) ([bool]$terminal.ShellChanged) 'Windows Terminal scheme/colors verified.' $terminal.BackupPath
            }
            if ($hasFont) {
                $fontStatus = if ($terminal.FontSkipped) {'Skipped'} elseif ($terminal.FontChanged) {'Applied'} else {'NoChange'}
                $fontMessage = if ($terminal.FontSkipped) {'No saved font mapping or explicit font; existing font preserved.'} else {'Requested Terminal font fields verified.'}
                Add-ApplyTarget Font $fontStatus ([bool]$terminal.FontChanged) $fontMessage $terminal.BackupPath
            }
        }
        catch {
            # Scheme and font share one verified settings replacement, so a
            # failed combined write cannot be reported as two successful steps.
            if ($hasShell) { Add-ApplyTarget Shell Failed $false $_.Exception.Message }
            if ($hasFont) { Add-ApplyTarget Font Failed $false $_.Exception.Message }
        }
    }
    if ($Operation -ceq 'All') {
        foreach ($consumer in @(
            @{Target='Vim';Template='shared\vim-colors.vim.tpl';Destination='config\vim\colors\typezero.vim'},
            @{Target='Lightline';Template='shared\vim-lightline.vim.tpl';Destination='config\vim\autoload\lightline\colorscheme\typezero.vim'}
        )) {
            try {
                $destination = Join-Path $HOME $consumer.Destination
                $before = if (Test-Path -LiteralPath $destination -PathType Leaf) {(Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash} else {''}
                Write-ThemeTemplate -Source (Join-Path $TemplatesRoot $consumer.Template) -Destination $destination -Theme $t
                $after = if (Test-Path -LiteralPath $destination -PathType Leaf) {(Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash} else {''}
                $changed = $before -cne $after
                Add-ApplyTarget $consumer.Target $(if ($changed) {'Applied'} else {'NoChange'}) $changed 'Generated integration completed.'
            }
            catch { Add-ApplyTarget $consumer.Target Failed $false $_.Exception.Message }
        }
        # Full-theme history describes a complete full apply. Scoped and partial
        # operations never overwrite it or the generated PowerShell palette.
        if (@($targets | Where-Object Status -ceq 'Failed').Count -eq 0) {
            $metadataBefore = @()
            try {
                foreach ($metadataPath in @($CurrentPs1,$PreviousFile,$CurrentFile) | Where-Object { $_ }) {
                    $exists = Test-Path -LiteralPath $metadataPath -PathType Leaf
                    $metadataBytes = [byte[]]@()
                    if ($exists) { $metadataBytes = [IO.File]::ReadAllBytes($metadataPath) }
                    $metadataBefore += [pscustomobject]@{Path=$metadataPath;Exists=$exists;Bytes=$metadataBytes}
                }
                $old = if (Test-Path -LiteralPath $CurrentFile) {(Get-Content -LiteralPath $CurrentFile -Raw).Trim()} else {''}
                Write-CurrentTheme $t
                if (-not $NoHistory -and $old -and $old -cne $Id) {
                    Set-Content -LiteralPath $PreviousFile -Value $old -Encoding ascii
                }
                Set-Content -LiteralPath $CurrentFile -Value $Id -Encoding ascii
                $metadataChanged = $false
                foreach ($snapshot in $metadataBefore) {
                    $exists = Test-Path -LiteralPath $snapshot.Path -PathType Leaf
                    if ($exists -ne $snapshot.Exists -or ($exists -and
                        [Convert]::ToBase64String([IO.File]::ReadAllBytes($snapshot.Path)) -cne
                        [Convert]::ToBase64String([byte[]]$snapshot.Bytes))) {
                        $metadataChanged = $true
                    }
                }
                Add-ApplyTarget CurrentTheme $(if ($metadataChanged) {'Applied'} else {'NoChange'}) $metadataChanged 'Complete theme history and PowerShell palette recorded.'
            }
            catch {
                $metadataError = $_.Exception.Message
                foreach ($snapshot in $metadataBefore) {
                    try {
                        if ($snapshot.Exists) { [IO.File]::WriteAllBytes($snapshot.Path,[byte[]]$snapshot.Bytes) }
                        elseif (Test-Path -LiteralPath $snapshot.Path -PathType Leaf) { Remove-Item -LiteralPath $snapshot.Path -Force }
                    }
                    catch { $metadataError += " Metadata restore failed for '$($snapshot.Path)': $($_.Exception.Message)" }
                }
                Add-ApplyTarget CurrentTheme Failed $false $metadataError
            }
        }
        else { Add-ApplyTarget CurrentTheme Skipped $false 'Full-theme history preserved because one or more requested targets failed.' }
    }
    $failed = @($targets | Where-Object Status -ceq 'Failed').Count
    $succeeded = @($targets | Where-Object Status -cin @('Applied','NoChange')).Count
    $changed = @($targets | Where-Object Changed).Count -gt 0
    $status = if ($failed) {if ($succeeded) {'Partial'} else {'Failed'}} elseif ($changed) {'Applied'} else {'NoChange'}
    foreach ($target in $targets) { Write-Host ("{0}: {1} - {2}" -f $target.Target,$target.Status,$target.Message) }
    if ($failed) { Write-Warning "$status theme operation '$Operation' for '$Id'; requested targets are incomplete." }
    elseif ($Operation -ceq 'All') { Write-Host "Applied theme: $($t['THEME_NAME'])" }
    [pscustomobject]@{Status=$status;Operation=$Operation;Theme=$Id;Complete=($failed -eq 0);Changed=$changed;
        AppearanceMayHaveChanged=($changed -or $failed -gt 0);Targets=@($targets.ToArray())}
}


switch ($Command) {
    "configure" {
        if ($Theme -or $WallpaperArgs) { throw 'Usage: themeengine configure' }
        . (Join-Path $PSScriptRoot 'Configure-WindowsTerminal.ps1')
        return Invoke-TypezeroThemeConfigure -EngineRoot $PSScriptRoot -ThemesRoot $ThemesRoot
    }
    "bootstrap" {
        if (-not $RepoRoot) { $RepoRoot = (Get-Location).Path }
        $themeSource = Join-Path $RepoRoot "ThemeEngine\themes"
        $templateSource = Join-Path $RepoRoot "ThemeEngine\templates"

        if (-not (Test-Path -LiteralPath $themeSource)) {
            throw "ThemeEngine\themes not found under: $RepoRoot"
        }
        if (-not (Test-Path -LiteralPath $templateSource)) {
            throw "ThemeEngine\templates not found under: $RepoRoot"
        }

        # Bootstrap themes and templates together so normal operation uses
        # installed ThemeEngine data rather than the development repository.
        foreach ($installRoot in @($ThemesRoot, $TemplatesRoot)) {
            if (Test-Path -LiteralPath $installRoot) {
                Remove-Item -LiteralPath $installRoot -Recurse -Force
            }
            New-Item -ItemType Directory -Force -Path $installRoot | Out-Null
        }

        Copy-Item -Path (Join-Path $themeSource "*") -Destination $ThemesRoot -Recurse -Force
        Copy-Item -Path (Join-Path $templateSource "*") -Destination $TemplatesRoot -Recurse -Force

        Write-Host "ThemeEngine themes installed under $ThemesRoot"
        Write-Host "ThemeEngine templates installed under $TemplatesRoot"
    }

    "list" {
        if (-not (Test-Path -LiteralPath $ThemesRoot)) {
            throw "No themes installed. Run ThemeEngine.ps1 bootstrap -RepoRoot <repo-root>"
        }

        $current = if (Test-Path -LiteralPath $CurrentFile) {
            (Get-Content -LiteralPath $CurrentFile -Raw).Trim()
        } else { "" }

        $presentationModule = Join-Path $PSScriptRoot 'ThemePresentation.ps1'

        if (Test-Path -LiteralPath $presentationModule -PathType Leaf) {
            . $presentationModule

            $entries = @(
                Get-ChildItem -LiteralPath $ThemesRoot -Directory |
                    Sort-Object Name |
                    ForEach-Object {
                        [pscustomobject]@{
                            Id = $_.Name
                            Theme = Read-ThemeFile $_.Name
                        }
                    }
            )

            if ($entries.Count -eq 0) {
                Write-Host 'No themes found.'
            }
            else {
                Write-Host (
                    Format-TypezeroThemeCatalog `
                        -Entries $entries -CurrentId $current
                )
            }
        }
        else {
            Write-Warning 'Visual catalog unavailable; using classic list.'

            Get-ChildItem -LiteralPath $ThemesRoot -Directory |
                ForEach-Object {
                    $prefix = if ($_.Name -eq $current) { "*" } else { " " }
                    Write-Host "$prefix $($_.Name)"
                }
        }
    }

    "current" {
        if (Test-Path -LiteralPath $CurrentFile) {
            (Get-Content -LiteralPath $CurrentFile -Raw).Trim()
        } else {
            "none"
        }
    }

    "status" {
        if ($Theme -or $WallpaperArgs) {
            throw 'Usage: ThemeEngine.ps1 status'
        }

        $presentationModule = Join-Path $PSScriptRoot 'ThemePresentation.ps1'

        if (-not (Test-Path -LiteralPath $presentationModule -PathType Leaf)) {
            throw 'Current-theme presentation module is missing.'
        }

        . $presentationModule

        $selected = if (
            Test-Path -LiteralPath $CurrentFile -PathType Leaf
        ) {
            (Get-Content -LiteralPath $CurrentFile -Raw).Trim()
        } else {
            ''
        }

        if ($selected -and
            $selected -cnotmatch '^[A-Za-z0-9][A-Za-z0-9_-]*$') {
            throw 'Invalid selected theme ID.'
        }

        if ($selected) {
            $themeData = Read-ThemeFile $selected

            Write-Host (
                Format-TypezeroCurrentTheme `
                    -Id $selected -Theme $themeData
            )
        }
        else {
            Write-Host (Format-TypezeroCurrentTheme)
        }
    }

    "preview" {
        if (-not $Theme) {
            if (-not (Test-Path -LiteralPath $CurrentFile)) {
                throw "No theme selected."
            }

            $Theme = (Get-Content -LiteralPath $CurrentFile -Raw).Trim()
        }

        $t = Read-ThemeFile $Theme
        $presentationModule = Join-Path $PSScriptRoot 'ThemePresentation.ps1'

        if (Test-Path -LiteralPath $presentationModule -PathType Leaf) {
            . $presentationModule

            Write-Host (
                Format-TypezeroThemePreview -Theme $t -Id $Theme
            )
        }
        else {
            Write-Warning 'Grouped preview unavailable; using classic preview.'

            Write-Host ""
            Write-Host "  $($t['THEME_NAME'])"
            Write-Host ""

            foreach ($role in @(
                "ACCENT", "ACCENT_BRIGHT", "SELECTION",
                "CURSOR", "FOCUS", "TEXT", "MUTED",
                "SUCCESS", "WARNING", "ERROR",
                "SECONDARY", "INFO"
            )) {
                $c = Convert-HexToAnsi $t[$role]

                Write-Host (
                    "$c  $($role.PadRight(14)) $($t[$role])$([char]27)[0m"
                )
            }

            Write-Host ""
        }
    }


    { $_ -in @('apply','apply-shell','apply-font','apply-desktop','apply-shell-font','apply-desktop-shell','apply-all') } {
        if (-not $Theme -or $WallpaperArgs) { throw "Usage: ThemeEngine.ps1 $Command <theme> [-TerminalFont <tuple>]" }
        $operation = switch ($Command) {
            'apply-shell' {'Shell'}
            'apply-font' {'Font'}
            'apply-desktop' {'Desktop'}
            'apply-shell-font' {'ShellFont'}
            'apply-desktop-shell' {'DesktopShell'}
            default {'All'}
        }
        Set-Theme -Id $Theme -Operation $operation -TerminalFont $TerminalFont -ExpectedSettingsSha256 $ExpectedSettingsSha256
    }
    "reload" {
        if (-not (Test-Path -LiteralPath $CurrentFile)) { throw "No current theme." }
        $id = (Get-Content -LiteralPath $CurrentFile -Raw).Trim()
        Set-Theme $id -NoHistory
    }

    "rollback" {
        if (-not (Test-Path -LiteralPath $PreviousFile)) { throw "No previous theme." }
        $id = (Get-Content -LiteralPath $PreviousFile -Raw).Trim()
        Set-Theme $id
    }

    "font" {
        $fontProvider = Join-Path $PSScriptRoot 'FontProvider-WindowsTerminal.ps1'

        if (-not (Test-Path -LiteralPath $fontProvider -PathType Leaf)) {
            throw "Font provider missing: $fontProvider"
        }

        . $fontProvider

        $mappingModule = Join-Path $PSScriptRoot 'FontMapping-WindowsTerminal.ps1'
        if (-not (Test-Path -LiteralPath $mappingModule -PathType Leaf)) {
            throw "Font mapping module missing: $mappingModule"
        }
        . $mappingModule

        $action = if ($Theme) { $Theme.ToLowerInvariant() } else { 'help' }

        if ($action -ceq 'configure') {
            if ($WallpaperArgs) { throw 'Usage: themeengine font configure' }
            . (Join-Path $PSScriptRoot 'Configure-WindowsTerminal.ps1')
            return Invoke-TypezeroThemeConfigure -EngineRoot $PSScriptRoot -ThemesRoot $ThemesRoot
        }

        if ($action -in @('preview-font','apply-font','preview-theme','apply-theme','save-preset','presets','load-preset','preview-preset','apply-preset')) {
            . (Join-Path $PSScriptRoot 'AppearanceSelection-WindowsTerminal.ps1')
            return Invoke-TypezeroFontCommand -Action $action -Arguments $WallpaperArgs `
                -EngineRoot $PSScriptRoot -ThemesRoot $ThemesRoot -ExpectedSha256 $ExpectedSettingsSha256
        }

        switch ($action) {
            'theme-preview' {
                if ($WallpaperArgs -and $WallpaperArgs.Count -gt 0) {
                    throw 'Usage: themeengine font theme-preview'
                }
                $previewModule = Join-Path $PSScriptRoot 'ThemeFontPreview-WindowsTerminal.ps1'
                if (-not (Test-Path -LiteralPath $previewModule -PathType Leaf)) {
                    throw "Theme/font preview module missing: $previewModule"
                }
                . $previewModule
                $result = Show-TypezeroThemeFontPreview -ThemesRoot $ThemesRoot
                if ($null -ne $result) {
                    if ($result.PreviewOnly -ne $true -or $result.SettingsChanged -ne $false) {
                        throw 'Preview-only invariant violated.'
                    }
                    $selectionModule = Join-Path $PSScriptRoot 'AppearanceSelection-WindowsTerminal.ps1'
                    if (-not (Test-Path -LiteralPath $selectionModule -PathType Leaf)) {
                        throw "Theme/font selection workflow missing: $selectionModule"
                    }
                    . $selectionModule
                    $activation = Invoke-TypezeroAppearanceSelection -Selection $result `
                        -EngineRoot $PSScriptRoot -ThemesRoot $ThemesRoot
                    if ($activation.Status -in @('PreferenceFailed','PreferenceNotSaved','ThemeFailed','ThemeAppliedFontUnverified')) {
                        Write-Warning $activation.Message
                    } else {
                        Write-Host $activation.Message
                    }
                    return $activation
                }
            }

            'picker' {
                if ($WallpaperArgs -and $WallpaperArgs.Count -gt 0) {
                    throw 'Usage: themeengine font picker'
                }

                $pickerModule = Join-Path $PSScriptRoot `
                    'FontPicker-WindowsTerminal.ps1'

                if (-not (Test-Path -LiteralPath $pickerModule -PathType Leaf)) {
                    throw "Font picker module missing: $pickerModule"
                }

                . $pickerModule

                $selection = Invoke-TypezeroFontPicker `
                    -EngineRoot $PSScriptRoot

                if ($null -eq $selection) {
                    throw 'Font picker returned no selection.'
                }

                if ($selection.PreviewOnly -ne $true -or
                    $selection.SettingsChanged -ne $false) {
                    throw 'Font picker violated preview-only requirements.'
                }

                return $selection
            }

            'list' {
                if ($WallpaperArgs) { throw 'Usage: themeengine font list' }
                Get-TypezeroInstalledFontFamilies
            }
            'current' {
                if ($WallpaperArgs) { throw 'Usage: themeengine font current' }
                Get-TypezeroTerminalFontStatus
            }
            'test' {
                if (-not $WallpaperArgs -or $WallpaperArgs.Count -ne 1) {
                    throw 'Usage: themeengine font test <theme-id>'
                }

                Get-TypezeroThemeFontPlan `
                    -InstalledThemesRoot $ThemesRoot `
                    -ThemeId $WallpaperArgs[0]
            }
            'plan' {
                if (-not $WallpaperArgs -or $WallpaperArgs.Count -ne 1) {
                    throw 'Usage: themeengine font plan <theme-id>'
                }

                Get-TypezeroTerminalFontSwitchPlan `
                    -ThemeId $WallpaperArgs[0]
            }
            'preview' {
                if (-not $WallpaperArgs -or $WallpaperArgs.Count -ne 1) {
                    throw 'Usage: themeengine font preview <theme-id>'
                }

                $presentationModule = Join-Path $PSScriptRoot 'FontPresentation-WindowsTerminal.ps1'

                if (-not (Test-Path -LiteralPath $presentationModule -PathType Leaf)) {
                    throw "Font presentation module missing: $presentationModule"
                }

                . $presentationModule

                $fontPlan = Get-TypezeroTerminalFontSwitchPlan `
                    -ThemeId $WallpaperArgs[0]

                Format-TypezeroTerminalFontPlan -Plan $fontPlan
            }
            'status' {
                if ($WallpaperArgs) { throw 'Usage: themeengine font status' }
                $config = Get-TypezeroWindowsFontMappings
                $current = Get-TypezeroTerminalFontStatus

                [pscustomobject]@{
                    Provider           = 'Windows Terminal'
                    IntegrationEnabled = $config.Enabled
                    MappedThemeCount   = $config.Mappings.Count
                    CurrentFont        = $current.Face
                    CurrentSize        = $current.Size
                    CurrentWeight      = $current.Weight
                    HasOverride        = $current.HasOverride
                    ConfigPath         = $config.Path
                }
            }
            'mappings' {
                if ($WallpaperArgs) { throw 'Usage: themeengine font mappings' }
                $config = Get-TypezeroWindowsFontMappings
                if ($config.Mappings.Count -eq 0) {
                    'No font mappings configured.'
                } else {
                    foreach ($id in @($config.Mappings.Keys | Sort-Object)) {
                        [pscustomobject]@{
                            Theme               = $id
                            Font                = $config.Mappings[$id]
                            IntegrationEnabled  = $config.Enabled
                        }
                    }
                }
            }
            'map' {
                if (-not $WallpaperArgs -or $WallpaperArgs.Count -ne 2) {
                    throw 'Usage: themeengine font map <theme-id> "<font family>"'
                }

                Set-TypezeroWindowsFontMapping `
                    -ThemeId $WallpaperArgs[0] `
                    -FontFamily $WallpaperArgs[1] `
                    -ThemesRoot $ThemesRoot
            }
            'map-v2' {
                if (-not $WallpaperArgs -or $WallpaperArgs.Count -ne 4) {
                    throw 'Usage: themeengine font map-v2 <theme-id> "<font family>" <size> <weight>'
                }

                $mappingV2 = Join-Path $PSScriptRoot 'FontMappingV2-WindowsTerminal.ps1'

                if (-not (Test-Path -LiteralPath $mappingV2 -PathType Leaf)) {
                    throw "Font V2 writer missing: $mappingV2"
                }

                . $mappingV2

                $sizeValue = 0.0

                if (-not [double]::TryParse(
                    [string]$WallpaperArgs[2],
                    [Globalization.NumberStyles]::Float,
                    [Globalization.CultureInfo]::InvariantCulture,
                    [ref]$sizeValue
                )) {
                    throw 'Invalid font size.'
                }

                Set-TypezeroWindowsFontMappingV2 `
                    -ThemeId $WallpaperArgs[0] `
                    -FontFamily $WallpaperArgs[1] `
                    -Size $sizeValue `
                    -Weight $WallpaperArgs[3] `
                    -ThemesRoot $ThemesRoot
            }
            'check-apply' {
                if (-not $WallpaperArgs -or $WallpaperArgs.Count -ne 1) {
                    throw 'Usage: themeengine font check-apply <theme-id>'
                }

                $id = [string]$WallpaperArgs[0]

                if ($id -cnotmatch '^[a-z0-9][a-z0-9-]*$') {
                    throw 'Invalid theme ID.'
                }

                $writer = Join-Path $PSScriptRoot 'FontWriter-WindowsTerminal.ps1'

                if (-not (Test-Path -LiteralPath $writer -PathType Leaf)) {
                    throw "Font writer missing: $writer"
                }

                . $writer

                $config = Get-TypezeroWindowsFontMappings

                if (-not $config.Mappings.ContainsKey($id)) {
                    throw "No font mapping for theme: $id"
                }

                $entry = $config.Mappings[$id]
                $current = Get-TypezeroTerminalFontStatus

                if ($config.Version -eq 1) {
                    $family = [string]$entry
                    $size = [double]$current.Size
                    $weight = [string]$current.Weight
                }
                elseif ($config.Version -eq 2) {
                    $family = [string]$entry.Family
                    $size = [double]$entry.Size
                    $weight = [string]$entry.Weight
                }
                else {
                    throw 'Unsupported font mapping version.'
                }

                $settings = Join-Path $env:LOCALAPPDATA (
                    'Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe' +
                    '\LocalState\settings.json'
                )

                $utf8 = [Text.UTF8Encoding]::new($false, $true)
                $text = [IO.File]::ReadAllText($settings, $utf8)

                $candidate = New-TypezeroMappedFontOverrideText `
                    -Text $text `
                    -Family $family `
                    -Size $size `
                    -Weight $weight

                $snapshot = Get-TypezeroFontProfileTextSnapshot `
                    -Text $candidate

                $restored = Restore-TypezeroMappedFontOverrideText `
                    -Text $candidate

                if ($restored -cne $text -or
                    $snapshot.Face -cne $family -or
                    $snapshot.Size -ne $size -or
                    $snapshot.Weight -cne $weight) {
                    throw 'Font apply dry-run verification failed.'
                }

                [pscustomobject]@{
                    Action             = 'CHECK APPLY'
                    Theme              = $id
                    Family             = $family
                    Size               = $size
                    Weight             = $weight
                    MappingVersion     = $config.Version
                    IntegrationEnabled = $config.Enabled
                    PreviewOnly        = $true
                    Verified           = $true
                    SettingsChanged    = $false
                }
            }
            'check-restore' {
                if ($WallpaperArgs) {
                    throw 'Usage: themeengine font check-restore'
                }

                $writer = Join-Path $PSScriptRoot 'FontWriter-WindowsTerminal.ps1'

                if (-not (Test-Path -LiteralPath $writer -PathType Leaf)) {
                    throw "Font writer missing: $writer"
                }

                . $writer

                $settings = Join-Path $env:LOCALAPPDATA (
                    'Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe' +
                    '\LocalState\settings.json'
                )

                $utf8 = [Text.UTF8Encoding]::new($false, $true)
                $text = [IO.File]::ReadAllText($settings, $utf8)

                $marker = '/* TYPEZERO_FONT_V2 */'

                if (-not $text.Contains($marker)) {
                    [pscustomobject]@{
                        Action          = 'CHECK RESTORE'
                        Restorable      = $false
                        Reason          = 'No managed font override is active.'
                        PreviewOnly     = $true
                        SettingsChanged = $false
                    }
                }
                else {
                    $restored = Restore-TypezeroMappedFontOverrideText `
                        -Text $text

                    $snapshot = Get-TypezeroFontProfileTextSnapshot `
                        -Text $restored

                    if ($snapshot.HasFont -or
                        $restored.Contains($marker)) {
                        throw 'Font restore dry-run verification failed.'
                    }

                    [pscustomobject]@{
                        Action          = 'CHECK RESTORE'
                        Restorable      = $true
                        Verified        = $true
                        PreviewOnly     = $true
                        SettingsChanged = $false
                    }
                }
            }
            default {
                'Usage: themeengine font <list|current|test|plan|preview|status|mappings|map|check-apply|check-restore>'
            }
        }
    }

    # BEGIN TYPEZERO WALLPAPER CLI (Stage 7)
    "wallpaper" {
        $cliPath = Join-Path $PSScriptRoot 'WallpaperCLI-DisplayFusion.ps1'
        if (-not (Test-Path -LiteralPath $cliPath -PathType Leaf)) {
            throw "Wallpaper CLI module not installed: $cliPath"
        }
        . $cliPath
        Invoke-TypezeroWallpaperCli -Action $Theme -ExtraArgs $WallpaperArgs -InstalledThemesRoot $ThemesRoot -ProviderDirectory $PSScriptRoot
    }
    # END TYPEZERO WALLPAPER CLI (Stage 7)

    "doctor-view" {
        # Preserve existing diagnostic logic and legacy output.
        if (-not $PSCommandPath) {
            throw 'ThemeEngine script path unavailable.'
        }

        . (Join-Path $PSScriptRoot 'ThemePresentation.ps1')

        # Capture the legacy Doctor Information stream.
        $records = @(& $PSCommandPath -Command 'doctor' 6>&1)

        $lines = @(
            foreach ($record in $records) {
                if ($record -is [System.Management.Automation.InformationRecord]) {
                    $data = $record.MessageData

                    if ($null -ne $data -and
                        $null -ne $data.PSObject.Properties['Message']) {
                        [string]$data.Message
                    }
                    else {
                        [string]$data
                    }
                }
                elseif ($record -is [string]) {
                    $record
                }
                else {
                    throw (
                        'Unexpected diagnostic record type: ' +
                        $record.GetType().FullName
                    )
                }
            }
        )

        $sections = @(
            ConvertTo-TypezeroDoctorSections -Lines $lines
        )

        Write-Host (Format-TypezeroDoctor -Sections $sections)
    }
    "doctor" {
        Write-Host "ThemeEngine doctor"
        Write-Host ""
        Write-Host ("  themes        " + $(if (Test-Path $ThemesRoot) { "PASS" } else { "MISSING" }))
        Write-Host ("  current       " + $(if (Test-Path $CurrentFile) { (Get-Content $CurrentFile -Raw).Trim() } else { "none" }))
        Write-Host ("  renderer      PowerShell $($PSVersionTable.PSVersion)")
        Write-Host ("  current.ps1   " + $(if (Test-Path $CurrentPs1) { "PASS" } else { "MISSING" }))
        $terminalSettings = Get-WindowsTerminalSettingsPath
        Write-Host ("  terminal      " + $(if ($terminalSettings) { "PASS" } else { "NOT FOUND" }))
        Write-Host ""
        Write-Host "  Windows Appearance"

        $providerPath = Join-Path $PSScriptRoot 'WindowsAppearance.ps1'
        $providerExists = Test-Path -LiteralPath $providerPath

        Write-Host ("  native provider    " + $(
            if ($providerExists) { "PASS" } else { "MISSING" }
        ))

        # Expected policy is persisted as a plain text file; default is theme.
        $policyPath = Join-Path $env:LOCALAPPDATA 'Typezero\ThemeEngine\windows-accent-policy'
        $accentPolicy = 'theme'
        if (Test-Path -LiteralPath $policyPath) {
            $accentPolicy = (Get-Content -LiteralPath $policyPath -Raw).Trim().ToLowerInvariant()
        }
        $expectedAuto = if ($accentPolicy -eq 'automatic') { '1' } elseif ($accentPolicy -eq 'theme') { '0' } else { $null }
        Write-Host ("  accent policy      " + $(if ($expectedAuto) { $accentPolicy } else { "INVALID ($accentPolicy)" }))
        $activeTheme = $null
        $accentMode = "UNKNOWN"
        $windowsTheme = "UNKNOWN"

        try {
            $activeTheme = (Get-ItemProperty `
                'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes' `
                -ErrorAction Stop).CurrentTheme

            if ($activeTheme -and (Test-Path -LiteralPath $activeTheme)) {
                $themeContents = Get-Content -LiteralPath $activeTheme -Raw

                if ($themeContents -match '(?m)^AutoColorization=1\s*$') {
                    $accentMode = $(if ($expectedAuto -eq '1') { "PASS (Automatic, saved theme)" } else { "WARN (Automatic; policy expects theme)" })
                }
                elseif ($themeContents -match '(?m)^AutoColorization=0\s*$') {
                    $accentMode = $(if ($expectedAuto -eq '0') { "PASS (Theme-defined, saved theme)" } else { "WARN (Manual; policy expects automatic)" })
                }

                if ($themeContents -match '(?m)^DisplayName=(.+)$') {
                    $windowsTheme = $Matches[1].Trim()
                }
            }
        }
        catch {
            $windowsTheme = "UNKNOWN"
        }

        Write-Host ("  accent mode        " + $accentMode)
        Write-Host ("  windows theme      " + $windowsTheme)

        $appearance = $null

        try {
            $personalize = Get-ItemProperty `
                'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' `
                -ErrorAction Stop

            $dwm = Get-ItemProperty `
                'HKCU:\Software\Microsoft\Windows\DWM' `
                -ErrorAction Stop

            $appearance = [pscustomobject]@{
                Transparency = $personalize.EnableTransparency
                Titlebar     = $dwm.ColorPrevalence
                Taskbar      = $personalize.ColorPrevalence
            }
        }
        catch {
            $appearance = $null
        }

        if ($null -ne $appearance) {
            Write-Host ("  transparency       " + $(if ($appearance.Transparency -eq 1) { "ON" } elseif ($appearance.Transparency -eq 0) { "OFF" } else { "UNKNOWN" }))
            Write-Host ("  titlebar accent    " + $(if ($appearance.Titlebar -eq 1) { "ON" } elseif ($appearance.Titlebar -eq 0) { "OFF" } else { "UNKNOWN" }))
            Write-Host ("  taskbar accent     " + $(if ($appearance.Taskbar -eq 1) { "ON" } elseif ($appearance.Taskbar -eq 0) { "OFF" } else { "UNKNOWN" }))
        }
        else {
            Write-Host "  transparency       UNKNOWN"
            Write-Host "  titlebar accent    UNKNOWN"
            Write-Host "  taskbar accent     UNKNOWN"
        }

        $displayFusion = Get-Process -Name 'DisplayFusion' -ErrorAction SilentlyContinue

        Write-Host ("  DisplayFusion      " + $(
            if ($displayFusion) { "RUNNING" } else { "NOT DETECTED" }
        ))
		        Write-Host ""
        Write-Host "  Wallpaper Integration"

        $wpCli = Join-Path $PSScriptRoot 'WallpaperCLI-DisplayFusion.ps1'
        $wpProvider = Join-Path $PSScriptRoot 'WallpaperProvider-DisplayFusion.ps1'
        $wpMapping = Join-Path $PSScriptRoot 'WallpaperMapping-DisplayFusion.ps1'

        Write-Host ("  CLI module          " + $(
            if (Test-Path -LiteralPath $wpCli -PathType Leaf) { 'PASS' } else { 'MISSING' }
        ))

        if ((Test-Path -LiteralPath $wpProvider -PathType Leaf) -and
            (Test-Path -LiteralPath $wpMapping -PathType Leaf)) {
            try {
                . $wpProvider
                . $wpMapping

                $wpConfig = Get-TypezeroWallpaperMappings
                $wpActive = @(Get-TypezeroDisplayFusionProfiles | Where-Object Current)

                Write-Host ("  integration         " + $(if ($wpConfig.Enabled) { 'ENABLED' } else { 'DISABLED' }))
                Write-Host ("  mapped themes       " + $wpConfig.Profiles.Count)
                Write-Host ("  active profile      " + $(if ($wpActive.Count -eq 1) { $wpActive[0].Name } else { 'UNKNOWN' }))
            }
            catch {
                Write-Host "  wallpaper status    ERROR: $($_.Exception.Message)"
            }
        }
        else {
            Write-Host "  wallpaper provider  MISSING"
        }
    }

    default {
        @"
Typezero ThemeEngine

usage:
  ThemeEngine.ps1 bootstrap -RepoRoot <repo-root>
  ThemeEngine.ps1 list
  ThemeEngine.ps1 current
  ThemeEngine.ps1 status
  ThemeEngine.ps1 configure
  ThemeEngine.ps1 font configure
  ThemeEngine.ps1 preview [theme]
  ThemeEngine.ps1 apply <theme>                  # full apply (alias of apply-all)
  ThemeEngine.ps1 apply-shell <theme>            # Terminal scheme/colors only
  ThemeEngine.ps1 apply-font <theme>             # saved font only
  ThemeEngine.ps1 apply-desktop <theme>          # native Windows + configured wallpaper
  ThemeEngine.ps1 apply-shell-font <theme>       # Terminal colors + saved/chosen font
  ThemeEngine.ps1 apply-desktop-shell <theme>    # desktop + Terminal colors, preserve font
  ThemeEngine.ps1 apply-all <theme>              # all existing integrations
  # Font/ShellFont/All may take -TerminalFont @{face='Consolas';size=14;weight='normal'}.
  # Scoped operations preserve full-theme history; results include per-target status.
  ThemeEngine.ps1 reload
  ThemeEngine.ps1 rollback
  ThemeEngine.ps1 font list
  ThemeEngine.ps1 font current
  ThemeEngine.ps1 font test <theme-id>
  ThemeEngine.ps1 font plan <theme-id>
  ThemeEngine.ps1 font preview <theme-id>
  ThemeEngine.ps1 font status
  ThemeEngine.ps1 font mappings
  ThemeEngine.ps1 font map <theme-id> "<font family>"
  ThemeEngine.ps1 font map-v2 <theme-id> "<font family>" <size> <weight>
  ThemeEngine.ps1 font theme-preview
  ThemeEngine.ps1 font preview-font "<family>" <size> <weight>
  ThemeEngine.ps1 font apply-font "<family>" <size> <weight>
  ThemeEngine.ps1 font preview-theme <theme> "<family>" <size> <weight>
  ThemeEngine.ps1 font apply-theme <theme> "<family>" <size> <weight>
  ThemeEngine.ps1 font save-preset <name> <theme> "<family>" <size> <weight> [--replace]
  ThemeEngine.ps1 font presets
  ThemeEngine.ps1 font load-preset <name>
  ThemeEngine.ps1 font preview-preset <name>
  ThemeEngine.ps1 font apply-preset <name>
  ThemeEngine.ps1 wallpaper <subcommand>
  ThemeEngine.ps1 doctor
  ThemeEngine.ps1 doctor-view

Weights: thin, extra-light, light, semi-light, normal, medium, semi-bold,
         bold, extra-bold, black, extra-black (font rendering depends on installed faces).
"@
    }
}
