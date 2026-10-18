# Typezero ThemeEngine - Windows Terminal Font Mapping V2
# Mapping configuration only. Never modifies Terminal settings.

function Set-TypezeroWindowsFontMappingV2 {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory)]
        [ValidatePattern('^[a-z0-9][a-z0-9-]*$')]
        [string]$ThemeId,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$FontFamily,

        [Parameter(Mandatory)]
        [ValidateRange(6, 36)]
        [double]$Size,

        [Parameter(Mandatory)]
        [ValidateSet('normal', 'semi-bold')]
        [string]$Weight,

        [Parameter(Mandatory)]
        [string]$ThemesRoot,

        [string]$ConfigPath = (Join-Path $env:LOCALAPPDATA `
            'Typezero\ThemeEngine\font-windows-terminal.json'),

        [double]$MigrationSize = 12,

        [ValidateSet('normal', 'semi-bold')]
        [string]$MigrationWeight = 'normal'
    )

    if (-not (Test-Path -LiteralPath `
        (Join-Path $ThemesRoot "$ThemeId\theme.conf") -PathType Leaf)) {
        throw "Theme does not exist: $ThemeId"
    }

    if ($FontFamily -ne $FontFamily.Trim()) {
        throw 'Font family contains leading or trailing whitespace.'
    }

    $installed = @(Get-TypezeroInstalledFontFamilies)

    $knownTerminalFace = 'JetBrainsMono Nerd Font'
    $current = Get-TypezeroTerminalFontStatus

    if ($FontFamily -cne $knownTerminalFace -and
        $FontFamily -cne $current.Face -and
        @($installed | Where-Object { $_ -ceq $FontFamily }).Count -ne 1) {
        throw "Unrecognized Windows Terminal font: $FontFamily"
    }

    if ($Size -ne [math]::Round($Size, 2)) {
        throw 'Font size supports at most two decimal places.'
    }

    # Serialize mapping writes by holding an exclusive file handle.
    # The lock protects cooperating ThemeEngine writers only.
    $lock = $null

    if (-not $WhatIfPreference) {
        $lockPath = "$ConfigPath.lock"
        $lockFolder = Split-Path -Parent $lockPath

        if (-not (Test-Path -LiteralPath $lockFolder)) {
            New-Item -ItemType Directory -Path $lockFolder -Force |
                Out-Null
        }

        try {
            $lock = [IO.FileStream]::new(
                $lockPath,
                [IO.FileMode]::OpenOrCreate,
                [IO.FileAccess]::ReadWrite,
                [IO.FileShare]::None
            )
        }
        catch {
            throw "Font configuration is locked by another writer: $lockPath"
        }
    }

    try {
    $originalExists = Test-Path -LiteralPath $ConfigPath -PathType Leaf
    $originalHash = if ($originalExists) {
        (Get-FileHash -LiteralPath $ConfigPath -Algorithm SHA256).Hash
    } else {
        $null
    }

    $config = Get-TypezeroWindowsFontMappings -Path $ConfigPath

    $mappings = [ordered]@{}

    foreach ($id in @($config.Mappings.Keys | Sort-Object)) {
        $entry = $config.Mappings[$id]

        if ($config.Version -eq 1) {
            $mappings[$id] = [ordered]@{
                family = [string]$entry
                size   = $MigrationSize
                weight = $MigrationWeight
            }
        } else {
            $mappings[$id] = [ordered]@{
                family = [string]$entry.Family
                size   = [double]$entry.Size
                weight = [string]$entry.Weight
            }
        }
    }

    $mappings[$ThemeId] = [ordered]@{
        family = $FontFamily
        size   = $Size
        weight = $Weight
    }

    $document = [ordered]@{
        Version        = 2
        Enabled        = [bool]$config.Enabled
        ManualOverride = $null
        Mappings       = $mappings
    }

    $json = ($document | ConvertTo-Json -Depth 20) + "`n"

    if (-not $PSCmdlet.ShouldProcess(
        $ConfigPath,
        "Save v2 font mapping for '$ThemeId' (no Terminal activation)"
    )) {
        return
    }

    $folder = Split-Path -Parent $ConfigPath

    if (-not (Test-Path -LiteralPath $folder)) {
        New-Item -ItemType Directory -Path $folder -Force |
            Out-Null
    }

    $temp = Join-Path $folder (
        '.typezero-font-v2-' + [guid]::NewGuid().ToString('N') + '.tmp'
    )

    try {
        [IO.File]::WriteAllText(
            $temp, $json, [Text.UTF8Encoding]::new($false)
        )

        # Validate the complete candidate before replacing the original.
        $verified = Get-TypezeroWindowsFontMappings -Path $temp

        if ($verified.Version -ne 2 -or
            $verified.Enabled -ne $config.Enabled -or
            $verified.Mappings.Count -ne $mappings.Count -or
            $verified.Mappings[$ThemeId].Family -cne $FontFamily -or
            [double]$verified.Mappings[$ThemeId].Size -ne $Size -or
            $verified.Mappings[$ThemeId].Weight -cne $Weight) {
            throw 'V2 candidate verification failed.'
        }

        if ($originalExists) {
            if (-not (Test-Path -LiteralPath $ConfigPath -PathType Leaf) -or
                (Get-FileHash -LiteralPath $ConfigPath -Algorithm SHA256).Hash -cne $originalHash) {
                throw 'Configuration changed during preparation.'
            }

            $backup = "$ConfigPath.$([guid]::NewGuid().ToString('N')).bak"

            [IO.File]::Replace($temp, $ConfigPath, $backup)
        } else {
            if (Test-Path -LiteralPath $ConfigPath) {
                throw 'Configuration appeared during preparation.'
            }

            [IO.File]::Move($temp, $ConfigPath)
        }

        Get-TypezeroWindowsFontMappings -Path $ConfigPath
    }
    finally {
        if (Test-Path -LiteralPath $temp) {
            Remove-Item -LiteralPath $temp -Force
        }
    }
    }
    finally {
        if ($null -ne $lock) {
            $lock.Dispose()
        }
    }
}
