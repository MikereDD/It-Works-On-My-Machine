#--------------------------------------------
# file:     ThemeEngine.ps1
# author:   Mike Redd
# version:  0.1-dev
# desc:     Typezero ThemeEngine — Netzach PowerShell renderer
#--------------------------------------------

[CmdletBinding(PositionalBinding = $false)]
param(
    [Parameter(Position = 0)]
    [ValidateSet("bootstrap","list","current","status","preview","apply","reload","rollback","wallpaper","font","rehearse","doctor","doctor-view","help")]
    [string]$Command = "help",

    [Parameter(Position = 1)]
    [string]$Theme,

    [string]$RepoRoot,

    # Explicit fixture-only rehearsal. These arguments are invalid for live commands.
    [string]$FixtureRoot,
    [string]$FixtureExpectedSha256,
    [switch]$PreviewMappedFont,

    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$WallpaperArgs
)

$ErrorActionPreference = "Stop"

if ($Command -cne 'rehearse' -and (
    $PSBoundParameters.ContainsKey('FixtureRoot') -or
    $PSBoundParameters.ContainsKey('FixtureExpectedSha256') -or
    $PSBoundParameters.ContainsKey('PreviewMappedFont'))) {
    throw 'Fixture arguments are allowed only with -Command rehearse.'
}

$EngineRoot   = Join-Path $env:LOCALAPPDATA "Typezero\ThemeEngine"
$ThemesRoot   = Join-Path $EngineRoot "themes"
$TemplatesRoot = Join-Path $EngineRoot "templates"
$CurrentFile  = Join-Path $EngineRoot "current-theme"
$PreviousFile = Join-Path $EngineRoot "previous-theme"
$CurrentPs1   = Join-Path $EngineRoot "current.ps1"

New-Item -ItemType Directory -Force -Path $EngineRoot | Out-Null

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
    # colorScheme property; unrelated Terminal settings remain untouched.
    $packagePath = Join-Path $env:LOCALAPPDATA `
        "Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json"

    if (Test-Path -LiteralPath $packagePath) {
        return $packagePath
    }

    return $null
}

function Set-WindowsTerminalTheme {
    param([Parameter(Mandatory)][System.Collections.IDictionary]$T)

    $settingsPath = Get-WindowsTerminalSettingsPath
    if (-not $settingsPath) {
        return
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
        if (-not $T.Contains($key) -or -not $T[$key]) {
            Write-Host "Windows Terminal: skipped (theme has no complete ANSI palette)"
            return
        }
    }

    # Temporary compatibility guard for FontEngine v2.
    # The legacy JSON serializer removes the font ownership marker.
    $terminalBeforeHash = (
        Get-FileHash -LiteralPath $settingsPath -Algorithm SHA256
    ).Hash

    $terminalText = [IO.File]::ReadAllText($settingsPath)

    if ($terminalText.Contains('/* TYPEZERO_FONT_V2 */')) {
        throw 'Legacy Terminal color writer disabled. A Typezero v2 font block is active.'
    }

    $settings = Get-Content -LiteralPath $settingsPath -Raw |
        ConvertFrom-Json

    # Preserve the user's original file before ThemeEngine's first write.
    # This is intentionally a stable backup rather than a rotating snapshot:
    # it represents the pre-ThemeEngine Windows Terminal configuration.
    $backupPath = "$settingsPath.typezero-backup"
    if (-not (Test-Path -LiteralPath $backupPath)) {
        Copy-Item -LiteralPath $settingsPath -Destination $backupPath
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

    # Replace only ThemeEngine's scheme for this theme. Other custom schemes
    # remain untouched.
    $otherSchemes = @(
        $settings.schemes |
            Where-Object { $_.name -ne $schemeName }
    )

    $settings.schemes = @($otherSchemes) + @([pscustomobject]$scheme)

    # Keep Windows Terminal's application chrome visually aligned with the
    # active Typezero palette. The active tab follows the terminal pane while
    # the surrounding tab row uses the theme background. This deliberately
    # leaves profile-specific wallpaper, opacity, typography, and other user
    # preferences untouched.
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

    $existingThemes = @(
        $settings.themes |
            Where-Object { $_.name -ne $terminalThemeName }
    )

    $settings.themes = @($existingThemes) + @([pscustomobject]$terminalTheme)
    if ($settings.PSObject.Properties["theme"]) {
        $settings.theme = $terminalThemeName
    } else {
        $settings | Add-Member -NotePropertyName theme -NotePropertyValue $terminalThemeName
    }

    # Target PowerShell 7 by its stable Windows Terminal profile GUID rather
    # than relying solely on a display name that the user may rename.
    $powerShellGuid = "{574e775e-4f2a-5b96-ac1e-a2962a402336}"
    $profile = $settings.profiles.list |
        Where-Object { $_.guid -eq $powerShellGuid } |
        Select-Object -First 1

    if (-not $profile) {
        throw "Windows Terminal PowerShell profile not found: $powerShellGuid"
    }

    if ($profile.PSObject.Properties["colorScheme"]) {
        $profile.colorScheme = $schemeName
    } else {
        $profile | Add-Member -NotePropertyName colorScheme -NotePropertyValue $schemeName
    }

    # ConvertFrom/To-Json necessarily reformats settings.json, but preserves
    # its data. ThemeEngine changes only the scheme collection described above
    # and the PowerShell profile's colorScheme association.
    $json = $settings | ConvertTo-Json -Depth 100
    # Reject concurrent changes rather than overwriting newer settings.
    if ((Get-FileHash -LiteralPath $settingsPath -Algorithm SHA256).Hash -ne
        $terminalBeforeHash) {
        throw 'Windows Terminal settings changed during color preparation.'
    }

    Set-Content -LiteralPath $settingsPath -Value $json -Encoding utf8

    Write-Host "Windows Terminal: $schemeName"
}
function Set-Theme {
    param(
        [Parameter(Mandatory)][string]$Id,
        [switch]$NoHistory,
        [string]$FixtureRoot,
        [string]$FixtureExpectedSha256,
        [switch]$PreviewMappedFont,
        [psobject]$FixtureFontConfig
    )

    # Fixture dispatcher MUST return before Vim, native Windows appearance,
    # Windows Terminal, generated current.ps1, history, or wallpaper hooks.
    # Default live Set-Theme behavior below this gate remains unchanged.
    if ($PSBoundParameters.ContainsKey('FixtureRoot') -or
        $PSBoundParameters.ContainsKey('FixtureExpectedSha256') -or
        $PSBoundParameters.ContainsKey('PreviewMappedFont') -or
        $PSBoundParameters.ContainsKey('FixtureFontConfig')) {
        if (-not $FixtureRoot -or
            $FixtureExpectedSha256 -cnotmatch '\A[A-Fa-f0-9]{64}\z' -or
            $NoHistory -or
            $Id -cnotmatch '\A[a-z0-9][a-z0-9-]*\z') {
            throw 'Invalid guarded theme rehearsal arguments.'
        }

        # Validate the destination before loading anything that could write.
        $fontWriter = Join-Path $PSScriptRoot 'FontWriter-WindowsTerminal.ps1'
        if (-not (Test-Path -LiteralPath $fontWriter -PathType Leaf)) {
            throw 'Rehearsal recovery writer missing.'
        }
        . $fontWriter
        $safeRoot = Assert-TypezeroFontRecoveryRoot -TestRoot $FixtureRoot

        foreach ($module in @(
            'TerminalColorCompat-WindowsTerminal.ps1',
            'TerminalUnified-WindowsTerminal.ps1',
            'TerminalThemeBridge-WindowsTerminal.ps1',
            'TerminalThemeFixture-WindowsTerminal.ps1'
        )) {
            $path = Join-Path $PSScriptRoot $module
            if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
                throw "Rehearsal module missing: $module"
            }
            . $path
        }

        if ($null -eq $FixtureFontConfig) {
            $mappingPath = Join-Path $PSScriptRoot 'FontMapping-WindowsTerminal.ps1'
            if (-not (Test-Path -LiteralPath $mappingPath -PathType Leaf)) {
                throw 'Rehearsal font mapping reader missing.'
            }
            . $mappingPath
            $config = Get-TypezeroWindowsFontMappings
        }
        else {
            # Injectable only from an in-process fixture test of Set-Theme;
            # the public CLI never accepts a synthetic mapping object.
            $config = $FixtureFontConfig
        }

        $fixtureTheme = Read-ThemeFile $Id
        return Invoke-TypezeroFixtureThemeSwitch `
            -TestRoot $safeRoot `
            -ExpectedSha256 $FixtureExpectedSha256 `
            -Theme $fixtureTheme `
            -FontConfig $config `
            -PreviewMappedFont:$PreviewMappedFont
    }

    $t = Read-ThemeFile $Id

    # Defer current/previous state updates until native activation and
    # application rendering succeed. A failed activation keeps history intact.
    $old = if (Test-Path -LiteralPath $CurrentFile) {
        (Get-Content -LiteralPath $CurrentFile -Raw).Trim()
    } else { '' }

    # Vim receives a generated native colorscheme from the same semantic
    # palette used by the shell and Windows Terminal. Keep the output inside
    # Netzach's established Vim config tree rather than a second runtime.
    $vimTemplate = Join-Path $TemplatesRoot 'shared\vim-colors.vim.tpl'
    $vimColors = Join-Path $HOME 'config\vim\colors\typezero.vim'
    Write-ThemeTemplate -Source $vimTemplate -Destination $vimColors -Theme $t

    # Lightline uses its own colorscheme API rather than Vim highlight groups.
    # Generate its palette beside the native Vim theme so both surfaces follow
    # the same ThemeEngine semantic roles and switch together.
    $lightlineTemplate = Join-Path $TemplatesRoot 'shared\vim-lightline.vim.tpl'
    $lightlineColors = Join-Path $HOME 'config\vim\autoload\lightline\colorscheme\typezero.vim'
    Write-ThemeTemplate -Source $lightlineTemplate -Destination $lightlineColors -Theme $t

    # Native Windows appearance integration.
    $windowsProvider = Join-Path $PSScriptRoot 'WindowsAppearance.ps1'

    if (Test-Path -LiteralPath $windowsProvider) {
        . $windowsProvider

        Set-TypezeroWindowsNativeTheme `
            -Id $t['THEME_ID'] `
            -Name $t['THEME_NAME'] `
            -Accent $t['ACCENT']
    }

    Set-WindowsTerminalTheme $t
    Write-CurrentTheme $t
    if (-not $NoHistory -and $old -and $old -ne $Id) {
        Set-Content -LiteralPath $PreviousFile -Value $old -Encoding ascii
    }
    Set-Content -LiteralPath $CurrentFile -Value $Id -Encoding ascii
    Write-Host "Applied theme: $($t['THEME_NAME'])"
}

switch ($Command) {
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

    'rehearse' {
        if (-not $Theme -or -not $FixtureRoot -or
            -not $FixtureExpectedSha256 -or
            $null -ne $WallpaperArgs -and $WallpaperArgs.Count -gt 0) {
            throw 'Usage: ThemeEngine.ps1 rehearse <theme-id> -FixtureRoot <private-temp-root> -FixtureExpectedSha256 <64-hex>'
        }
        Set-Theme -Id $Theme -FixtureRoot $FixtureRoot `
            -FixtureExpectedSha256 $FixtureExpectedSha256 `
            -PreviewMappedFont:$PreviewMappedFont
    }

    "apply" {
        if (-not $Theme) { throw "Usage: ThemeEngine.ps1 apply <theme>" }
        Set-Theme $Theme
    # BEGIN TYPEZERO DISPLAYFUSION APPLY HOOK (Stage 5)
    # The main color/theme apply has succeeded at this point. This optional
    # wallpaper action cannot undo the successful appearance application.
    try {
        $wallpaperProvider = Join-Path $PSScriptRoot 'WallpaperProvider-DisplayFusion.ps1'
        $wallpaperMapping = Join-Path $PSScriptRoot 'WallpaperMapping-DisplayFusion.ps1'
        if ((Test-Path -LiteralPath $wallpaperProvider) -and
            (Test-Path -LiteralPath $wallpaperMapping)) {
            . $wallpaperProvider
            . $wallpaperMapping
            $wallpaperState = Test-TypezeroWallpaperThemeMapping -ThemeId $Theme
            switch ($wallpaperState.Action) {
                'ELIGIBLE FOR EXPLICIT SWITCH' {
                    # Integration was expressly enabled in local config. Bypass
                    # prompts here only; guarded provider still creates a fresh
                    # backup, verifies its hash, and checks active profile ID.
                    $wallpaperResult = Invoke-TypezeroWallpaperThemeMapping -ThemeId $Theme -Execute -Confirm:$false -ErrorAction Stop
                    if ($null -eq $wallpaperResult -or $wallpaperResult.Status -notin @('VERIFIED', 'VERIFIED - COMMAND TIMEOUT', 'NO CHANGE')) {
                        Write-Warning "DisplayFusion: wallpaper activation returned no verified success for theme '$Theme'."
                    } else {
                        Write-Host "DisplayFusion wallpaper: $($wallpaperResult.ProfileName) [$($wallpaperResult.Status)]"
                    }
                }
                'INVALID PROFILE - no changes' {
                    Write-Warning "DisplayFusion: mapped wallpaper profile for '$Theme' is missing or ambiguous; colors were applied."
                }
                default {
                    # Disabled, unmapped, or already active: intentionally no-op.
                }
            }
        } else {
            # An absent optional provider is a no-op by design.
        }
    } catch {
        Write-Warning "DisplayFusion wallpaper step failed after successful theme apply: $($_.Exception.Message)"
    }
    # END TYPEZERO DISPLAYFUSION APPLY HOOK (Stage 5)
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

        switch ($action) {
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
            'apply' {
                if ($WallpaperArgs.Count -ne 2 -or
                    $WallpaperArgs[1] -cne '--fixture') {
                    throw 'LIVE FONT APPLY DISABLED. Usage: themeengine font apply <theme-id> --fixture'
                }

                $id = [string]$WallpaperArgs[0]

                if ($id -cnotmatch '^[a-z0-9][a-z0-9-]*$') {
                    throw 'Invalid theme ID.'
                }

                $writer = Join-Path $PSScriptRoot 'FontWriter-WindowsTerminal.ps1'
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
                    throw 'Unsupported mapping version.'
                }

                $fixtureText = @(
                    '{'
                    '  // Typezero fixture only'
                    '  "profiles": {'
                    '    "defaults": {"font": {"face": "Fixture Default", "size": 12, "weight": "normal"}},'
                    '    "list": ['
                    '      {'
                    '        "guid": "{574e775e-4f2a-5b96-ac1e-a2962a402336}",'
                    '        "name": "PowerShell 7",'
                    '        "colorScheme": "Typezero Fixture"'
                    '      }'
                    '    ]'
                    '  }'
                    '}'
                ) -join "`r`n"

                $fixtureText += "`r`n"

                $utf8 = [Text.UTF8Encoding]::new($false, $true)
                $bytes = $utf8.GetBytes($fixtureText)

                $root = New-TypezeroFontRecoveryFixture -Bytes $bytes
                $beforeHash = Get-TypezeroFontRecoveryHash $bytes

                $transaction = Invoke-TypezeroFontDurableFixtureChange `
                    -TestRoot $root `
                    -ExpectedSha256 $beforeHash `
                    -Mode Apply `
                    -Family $family `
                    -Size $size `
                    -Weight $weight

                $target = Join-Path $root 'settings.json'
                $afterBytes = Get-TypezeroFontRecoveryBytes $target
                $afterHash = Get-TypezeroFontRecoveryHash $afterBytes

                if (-not $transaction.Verified -or
                    -not $transaction.FixtureOnly -or
                    $afterHash -cne $transaction.AfterHash) {
                    throw 'Fixture apply verification failed.'
                }

                [pscustomobject]@{
                    Action        = 'FIXTURE APPLY'
                    Theme         = $id
                    Family        = $family
                    Size          = $size
                    Weight        = $weight
                    FixtureRoot   = $root
                    TransactionId = $transaction.TransactionId
                    BeforeHash    = $beforeHash
                    AfterHash     = $afterHash
                    Verified      = $true
                    FixtureOnly   = $true
                }
            }
            'restore' {
                if ($WallpaperArgs.Count -ne 2 -or
                    $WallpaperArgs[0] -cne '--fixture') {
                    throw 'LIVE FONT RESTORE DISABLED. Usage: themeengine font restore --fixture <test-root>'
                }

                $writer = Join-Path $PSScriptRoot 'FontWriter-WindowsTerminal.ps1'
                . $writer

                $root = Assert-TypezeroFontRecoveryRoot `
                    -TestRoot ([string]$WallpaperArgs[1])

                $target = Join-Path $root 'settings.json'
                $beforeBytes = Get-TypezeroFontRecoveryBytes $target
                $beforeHash = Get-TypezeroFontRecoveryHash $beforeBytes

                $utf8 = [Text.UTF8Encoding]::new($false, $true)

                $bom = (
                    $beforeBytes.Length -ge 3 -and
                    $beforeBytes[0] -eq 239 -and
                    $beforeBytes[1] -eq 187 -and
                    $beforeBytes[2] -eq 191
                )

                $offset = if ($bom) { 3 } else { 0 }

                $text = $utf8.GetString(
                    $beforeBytes, $offset,
                    $beforeBytes.Length - $offset
                )

                $snapshot = Get-TypezeroFontProfileTextSnapshot -Text $text

                if (-not $snapshot.HasFont -or
                    -not $text.Contains('/* TYPEZERO_FONT_V2 */')) {
                    throw 'Managed fixture font override missing.'
                }

                $transaction = Invoke-TypezeroFontDurableFixtureChange `
                    -TestRoot $root `
                    -ExpectedSha256 $beforeHash `
                    -Mode Restore

                $afterBytes = Get-TypezeroFontRecoveryBytes $target
                $afterHash = Get-TypezeroFontRecoveryHash $afterBytes

                if (-not $transaction.Verified -or
                    -not $transaction.FixtureOnly -or
                    $afterHash -cne $transaction.AfterHash) {
                    throw 'Fixture restore verification failed.'
                }

                [pscustomobject]@{
                    Action        = 'FIXTURE RESTORE'
                    FixtureRoot   = $root
                    TransactionId = $transaction.TransactionId
                    BeforeHash    = $beforeHash
                    AfterHash     = $afterHash
                    Verified      = $true
                    FixtureOnly   = $true
                }
            }
            default {
                'Usage: themeengine font <list|current|test|plan|preview|status|mappings|map|check-apply|check-restore|apply|restore> (apply/restore require fixtures)'
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
  ThemeEngine.ps1 preview [theme]
  ThemeEngine.ps1 apply <theme>
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
  ThemeEngine.ps1 wallpaper <subcommand>
  ThemeEngine.ps1 doctor
  ThemeEngine.ps1 doctor-view
"@
    }
}
