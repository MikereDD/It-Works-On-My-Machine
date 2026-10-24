# Typezero ThemeEngine - Windows Terminal Font Provider
# v0.1: read-only font discovery and theme planning.
# No configuration writes or font installation.

function Get-TypezeroInstalledFontFamilies {
    Add-Type -AssemblyName System.Drawing -ErrorAction Stop

    $collection = [System.Drawing.Text.InstalledFontCollection]::new()
    try {
        $collection.Families |
            ForEach-Object { $_.Name } |
            Sort-Object -Unique
    }
    finally {
        $collection.Dispose()
    }
}

function Get-TypezeroTerminalFontStatus {
    $path = Join-Path $env:LOCALAPPDATA `
        'Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json'

    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw 'Windows Terminal settings not found.'
    }

    $settings = Get-Content -LiteralPath $path -Raw -ErrorAction Stop |
        ConvertFrom-Json -ErrorAction Stop

    $guid = '{574e775e-4f2a-5b96-ac1e-a2962a402336}'
    $profiles = @($settings.profiles.list |
        Where-Object { $_.guid -eq $guid })

    if ($profiles.Count -ne 1) {
        throw 'Expected exactly one PowerShell 7 Terminal profile.'
    }

    $profileFont = $profiles[0].font
    $defaultFont = $settings.profiles.defaults.font

    $face = if ($null -ne $profileFont.face) {
        $profileFont.face
    } elseif ($null -ne $defaultFont.face) {
        $defaultFont.face
    } else {
        'Cascadia Mono'
    }

    $size = if ($null -ne $profileFont.size) {
        $profileFont.size
    } elseif ($null -ne $defaultFont.size) {
        $defaultFont.size
    } else {
        12
    }

    $weight = if ($null -ne $profileFont.weight) {
        $profileFont.weight
    } elseif ($null -ne $defaultFont.weight) {
        $defaultFont.weight
    } else {
        'normal'
    }

    [pscustomobject]@{
        Profile       = 'PowerShell 7'
        Face          = $face
        Size          = $size
        Weight        = $weight
        HasOverride   = ($null -ne $profileFont)
        SettingsPath  = $path
    }
}

function Get-TypezeroThemeFontPlan {
    param(
        [string]$RepositoryRoot,
        [string]$InstalledThemesRoot,
        [Parameter(Mandatory)]
        [ValidatePattern('^[a-z0-9][a-z0-9-]*$')]
        [string]$ThemeId
    )

    $path = if ($InstalledThemesRoot) {
        Join-Path $InstalledThemesRoot "$ThemeId\theme.conf"
    } elseif ($RepositoryRoot) {
        Join-Path $RepositoryRoot "ThemeEngine\themes\$ThemeId\theme.conf"
    } else {
        throw 'RepositoryRoot or InstalledThemesRoot is required.'
    }

    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Theme not found: $ThemeId"
    }

    $values = @{}

    foreach ($line in Get-Content -LiteralPath $path) {
        if ($line -match '^\s*(FONT_FAMILY|FONT_STYLE)=(.*)$') {
            $values[$matches[1]] = $matches[2].Trim().Trim('"')
        }
    }

    $family = $values['FONT_FAMILY']
    $style = $values['FONT_STYLE']

    if ([string]::IsNullOrWhiteSpace($family) -or
        [string]::IsNullOrWhiteSpace($style)) {
        throw "Incomplete font metadata: $ThemeId"
    }

    $installed = @(Get-TypezeroInstalledFontFamilies)
    $exactMatch = @($installed |
        Where-Object { $_ -eq $family }).Count -gt 0

    [pscustomobject]@{
        Theme               = $ThemeId
        RequestedFamily     = $family
        RequestedStyle      = $style
        ExactGdiFamilyMatch = $exactMatch
        Action              = 'READ ONLY - no changes'
    }
}

function Get-TypezeroTerminalFontSwitchPlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidatePattern('^[a-z0-9][a-z0-9-]*$')]
        [string]$ThemeId,

        [string]$ConfigPath
    )

    $config = if ($PSBoundParameters.ContainsKey('ConfigPath')) {
        Get-TypezeroWindowsFontMappings -Path $ConfigPath
    } else {
        Get-TypezeroWindowsFontMappings
    }

    if (-not $config.Mappings.ContainsKey($ThemeId)) {
        throw "No font mapping configured for: $ThemeId"
    }

    $current = Get-TypezeroTerminalFontStatus
    $mapping = $config.Mappings[$ThemeId]

    if ($config.Version -eq 1) {
        $family = [string]$mapping
        $size = [double]$current.Size
        $weight = [string]$current.Weight
    }
    elseif ($config.Version -eq 2) {
        $family = [string]$mapping.Family
        $size = [double]$mapping.Size
        $weight = [string]$mapping.Weight
    }
    else {
        throw "Unsupported mapping version: $($config.Version)"
    }

    $installed = @(Get-TypezeroInstalledFontFamilies)

    # The existing Terminal default was verified live.
    # GDI uses a different name for this Nerd Font.
    $knownTerminalFace = 'JetBrainsMono Nerd Font'

    $recognized = (
        $family -ceq $knownTerminalFace -or
        $family -ceq $current.Face -or
        @($installed | Where-Object { $_ -ceq $family }).Count -gt 0
    )

    if (-not $recognized) {
        throw "Unrecognized Windows Terminal font: $family"
    }

    $wouldChange = (
        $current.Face -cne $family -or
        [double]$current.Size -ne $size -or
        [string]$current.Weight -cne $weight
    )

    [pscustomobject]@{
        Theme              = $ThemeId
        MappingVersion     = $config.Version
        IntegrationEnabled = $config.Enabled
        CurrentFont        = $current.Face
        RequestedFont      = $family
        CurrentSize        = $current.Size
        RequestedSize      = $size
        CurrentWeight      = $current.Weight
        RequestedWeight    = $weight
        WouldChange        = $wouldChange
        Action             = 'PREVIEW ONLY - no changes'
    }
}
