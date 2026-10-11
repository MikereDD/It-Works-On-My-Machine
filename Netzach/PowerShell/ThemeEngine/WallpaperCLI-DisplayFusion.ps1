# Typezero ThemeEngine — optional DisplayFusion wallpaper CLI
# Thin command interface over WallpaperProvider-DisplayFusion.ps1 and WallpaperMapping-DisplayFusion.ps1.
# No wallpaper/profile changes occur by loading this module.

function Invoke-TypezeroWallpaperCli {
    [CmdletBinding()]
    param(
        [string]$Action = 'help',
        [string[]]$ExtraArgs = @(),
        [Parameter(Mandatory)][string]$InstalledThemesRoot,
        [Parameter(Mandatory)][string]$ProviderDirectory
    )

    $actionName = if ([string]::IsNullOrWhiteSpace($Action)) { 'help' } else { $Action.ToLowerInvariant() }
    $tokens = @($ExtraArgs | Where-Object { $null -ne $_ })

    if ($actionName -eq 'help') {
        return @(
            'ThemeEngine wallpaper (DisplayFusion provider)',
            '',
            '  themeengine wallpaper status',
            '  themeengine wallpaper profiles',
            '  themeengine wallpaper mappings',
            '  themeengine wallpaper map <theme-id> "<saved profile name>"',
            '  themeengine wallpaper unmap <theme-id>',
            '  themeengine wallpaper enable',
            '  themeengine wallpaper disable',
            '  themeengine wallpaper test <theme-id>',
            '  themeengine wallpaper backup',
            '  themeengine wallpaper switch "<saved profile name>"',
            '',
            'status/profiles/mappings/test are read-only. map/unmap/enable/disable change local mapping JSON.',
            'backup writes a private local settings export. switch prompts and makes a verified backup.',
            'Only enabled, mapped themes switch wallpapers during a separate themeengine apply.'
        ) -join [Environment]::NewLine
    }

    $providerPath = Join-Path $ProviderDirectory 'WallpaperProvider-DisplayFusion.ps1'
    $mappingPath = Join-Path $ProviderDirectory 'WallpaperMapping-DisplayFusion.ps1'
    if (-not (Test-Path -LiteralPath $providerPath -PathType Leaf) -or
        -not (Test-Path -LiteralPath $mappingPath -PathType Leaf)) {
        throw 'Wallpaper provider or mapping module is missing beside the renderer.'
    }
    . $providerPath
    . $mappingPath

    function Assert-WallpaperCliArgs {
        param([int]$Count, [int]$Expected, [string]$Usage)
        if ($Count -ne $Expected) { throw "Usage: themeengine wallpaper $Usage" }
    }
    function Assert-WallpaperThemeId {
        param([string]$Id)
        if ($Id -cnotmatch '^[a-z0-9][a-z0-9-]*$') { throw "Invalid theme ID: '$Id'." }
    }

    switch ($actionName) {
        'status' {
            Assert-WallpaperCliArgs $tokens.Count 0 'status'
            $cfg = Get-TypezeroWallpaperMappings
            $info = Get-TypezeroDisplayFusionInfo
            $profiles = @(Get-TypezeroDisplayFusionProfiles)
            $active = @($profiles | Where-Object { $_.Current })
            return [pscustomobject]@{
                Provider          = 'DisplayFusion'
                Installed         = $info.Installed
                Running           = $info.Running
                Version           = $info.Version
                IntegrationEnabled = $cfg.Enabled
                ActiveProfile     = if ($active.Count -eq 1) { $active[0].Name } else { 'UNKNOWN' }
                ProfileCount      = $profiles.Count
                MappedThemeCount  = $cfg.Profiles.Count
                ConfigPath        = $cfg.Path
            }
        }
        'profiles' {
            Assert-WallpaperCliArgs $tokens.Count 0 'profiles'
            return (Get-TypezeroDisplayFusionProfiles)
        }
        'mappings' {
            Assert-WallpaperCliArgs $tokens.Count 0 'mappings'
            $cfg = Get-TypezeroWallpaperMappings
            if ($cfg.Profiles.Count -eq 0) { return 'No wallpaper theme mappings configured.' }
            return @($cfg.Profiles.Keys | Sort-Object | ForEach-Object {
                [pscustomobject]@{ ThemeId = $_; ProfileName = $cfg.Profiles[$_]; IntegrationEnabled = $cfg.Enabled }
            })
        }
        'map' {
            Assert-WallpaperCliArgs $tokens.Count 2 'map <theme-id> "<saved profile name>"'
            $id = $tokens[0]
            Assert-WallpaperThemeId $id
            if (-not (Test-Path -LiteralPath (Join-Path (Join-Path $InstalledThemesRoot $id) 'theme.conf') -PathType Leaf)) {
                throw "Theme '$id' is not installed. Bootstrap themes before mapping."
            }
            return (Set-TypezeroWallpaperProfileMapping -ThemeId $id -ProfileName $tokens[1])
        }
        'unmap' {
            Assert-WallpaperCliArgs $tokens.Count 1 'unmap <theme-id>'
            $id = $tokens[0]
            Assert-WallpaperThemeId $id
            $cfg = Get-TypezeroWallpaperMappings
            if (-not $cfg.Profiles.ContainsKey($id)) { return "No mapping exists for theme '$id'." }
            [void]$cfg.Profiles.Remove($id)
            return (Save-TypezeroWallpaperMappings -Enabled $cfg.Enabled -Profiles $cfg.Profiles)
        }
        'enable' {
            Assert-WallpaperCliArgs $tokens.Count 0 'enable'
            return (Set-TypezeroWallpaperMappingEnabled -Enabled $true)
        }
        'disable' {
            Assert-WallpaperCliArgs $tokens.Count 0 'disable'
            return (Set-TypezeroWallpaperMappingEnabled -Enabled $false)
        }
        'test' {
            Assert-WallpaperCliArgs $tokens.Count 1 'test <theme-id>'
            Assert-WallpaperThemeId $tokens[0]
            return (Test-TypezeroWallpaperThemeMapping -ThemeId $tokens[0])
        }
        'backup' {
            Assert-WallpaperCliArgs $tokens.Count 0 'backup'
            return (Backup-TypezeroDisplayFusionWallpaperSettings)
        }
        'switch' {
            Assert-WallpaperCliArgs $tokens.Count 1 'switch "<saved profile name>"'
            # The existing provider performs confirmation, verified backup and profile-ID readback.
            return (Invoke-TypezeroDisplayFusionProfileSwitch -ProfileName $tokens[0] -Execute)
        }
        default {
            throw "Unknown wallpaper command '$Action'. Run: themeengine wallpaper help"
        }
    }
}
