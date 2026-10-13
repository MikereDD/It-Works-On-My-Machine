# Typezero ThemeEngine - Windows Terminal Font Mapping
# v0.1: local opt-in configuration; no Terminal settings writes.

function Get-TypezeroWindowsFontMappings {
    [CmdletBinding()]
    param(
        [string]$Path = (Join-Path $env:LOCALAPPDATA `
            'Typezero\ThemeEngine\font-windows-terminal.json')
    )

    $version = 1
    $enabled = $false
    $manualOverride = $null
    $mappings = @{}

    if (Test-Path -LiteralPath $Path -PathType Leaf) {
        $data = Get-Content -LiteralPath $Path -Raw -ErrorAction Stop |
            ConvertFrom-Json -ErrorAction Stop

        if ($null -eq $data -or
            ($data.Version -ne 1 -and $data.Version -ne 2) -or
            $data.Enabled -isnot [bool] -or
            $data.Mappings -isnot [pscustomobject]) {
            throw "Invalid Windows font configuration: $Path"
        }

        $version = [int]$data.Version
        $enabled = $data.Enabled

        if ($version -eq 2) {
            if (-not $data.PSObject.Properties['ManualOverride']) {
                throw 'v2 configuration lacks ManualOverride.'
            }

            if ($null -ne $data.ManualOverride) {
                throw 'Manual override support is not implemented yet.'
            }
        }

        foreach ($entry in $data.Mappings.PSObject.Properties) {
            $id = [string]$entry.Name

            if ($id -cnotmatch '^[a-z0-9][a-z0-9-]*$') {
                throw "Invalid theme ID: $id"
            }

            if ($version -eq 1) {
                if ($entry.Value -isnot [string] -or
                    [string]::IsNullOrWhiteSpace($entry.Value)) {
                    throw "Invalid v1 font mapping: $id"
                }

                $mappings[$id] = [string]$entry.Value
                continue
            }

            $value = $entry.Value

            if ($value -isnot [pscustomobject] -or
                $null -eq $value.PSObject.Properties['family'] -or
                $null -eq $value.PSObject.Properties['size'] -or
                $null -eq $value.PSObject.Properties['weight']) {
                throw "Invalid v2 mapping structure: $id"
            }

            $family = $value.family
            $size = $value.size
            $weight = $value.weight

            if ($family -isnot [string] -or
                [string]::IsNullOrWhiteSpace($family)) {
                throw "Invalid font family: $id"
            }

            if (($size -isnot [int] -and
                 $size -isnot [long] -and
                 $size -isnot [double]) -or
                $size -lt 6 -or $size -gt 36) {
                throw "Invalid font size: $id"
            }

            if ($weight -cnotin @('normal', 'semi-bold')) {
                throw "Unsupported font weight: $id"
            }

            $mappings[$id] = [pscustomobject]@{
                Family = $family
                Size   = $size
                Weight = $weight
            }
        }
    }

    [pscustomobject]@{
        Version        = $version
        Enabled        = $enabled
        ManualOverride = $manualOverride
        Mappings       = $mappings
        Path           = $Path
    }
}

function Set-TypezeroWindowsFontMapping {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory)]
        [ValidatePattern('^[a-z0-9][a-z0-9-]*$')]
        [string]$ThemeId,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$FontFamily,

        [Parameter(Mandatory)]
        [string]$ThemesRoot
    )

    $themeFile = Join-Path $ThemesRoot "$ThemeId\theme.conf"

    if (-not (Test-Path -LiteralPath $themeFile -PathType Leaf)) {
        throw "Theme does not exist: $ThemeId"
    }

    $available = @(Get-TypezeroInstalledFontFamilies)

    if (@($available | Where-Object { $_ -ceq $FontFamily }).Count -ne 1) {
        throw "Font family was not found by exact name: $FontFamily"
    }

    $config = Get-TypezeroWindowsFontMappings

    if ($config.Version -ne 1) {
        throw 'v2 font mapping writes are not implemented yet.'
    }

    if ($PSCmdlet.ShouldProcess($ThemeId, "Map Windows font '$FontFamily'")) {
        $config.Mappings[$ThemeId] = $FontFamily

        $ordered = [ordered]@{}

        foreach ($id in @($config.Mappings.Keys | Sort-Object)) {
            $ordered[$id] = $config.Mappings[$id]
        }

        $content = [ordered]@{
            Version  = 1
            Enabled  = $config.Enabled
            Mappings = $ordered
        } | ConvertTo-Json -Depth 10

        $path = $config.Path
        $folder = Split-Path -Parent $path

        New-Item -ItemType Directory -Path $folder -Force | Out-Null

        if (Test-Path -LiteralPath $path) {
            $stamp = Get-Date -Format 'yyyyMMdd-HHmmss-fffffff'
            Copy-Item -LiteralPath $path `
                -Destination "$path.$stamp.bak" -ErrorAction Stop
        }

        $temp = Join-Path $folder ([IO.Path]::GetRandomFileName())

        try {
            [IO.File]::WriteAllText(
                $temp,
                $content + "`n",
                [Text.UTF8Encoding]::new($false)
            )

            Move-Item -LiteralPath $temp -Destination $path -Force
        }
        finally {
            if (Test-Path -LiteralPath $temp) {
                Remove-Item -LiteralPath $temp -Force
            }
        }

        Get-TypezeroWindowsFontMappings
    }
}
