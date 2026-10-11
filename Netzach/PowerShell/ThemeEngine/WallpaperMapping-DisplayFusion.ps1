# Typezero ThemeEngine - DisplayFusion theme/profile mapping v0.4
# Opt-in; config lives under LOCALAPPDATA, never in the repository.
# No wallpaper change occurs without an explicit -Execute and confirmation.
function Get-TypezeroWallpaperMappingPath {
    Join-Path $env:LOCALAPPDATA 'Typezero\ThemeEngine\wallpaper-displayfusion.json'
}

function Get-TypezeroWallpaperMappings {
    [CmdletBinding()]
    param()
    $path = Get-TypezeroWallpaperMappingPath
    $enabled = $false
    $mappings = @{}
    if (Test-Path -LiteralPath $path) {
        $data = Get-Content -LiteralPath $path -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
        if ($null -eq $data -or $data.Version -ne 1 -or $null -eq $data.Profiles) { throw "Invalid wallpaper mapping configuration: $path" }
        $enabled = $data.Enabled -eq $true
        foreach ($property in $data.Profiles.PSObject.Properties) {
            $mappings[[string]$property.Name] = [string]$property.Value
        }
    }
    [pscustomobject]@{ Enabled = $enabled; Profiles = $mappings; Path = $path }
}

function Save-TypezeroWallpaperMappings {
    [CmdletBinding()]
    param([Parameter(Mandatory)][bool]$Enabled, [Parameter(Mandatory)][hashtable]$Profiles)
    $path = Get-TypezeroWallpaperMappingPath
    $dir = Split-Path -Parent $path
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    $ordered = [ordered]@{}
    foreach ($name in @($Profiles.Keys | Sort-Object)) { $ordered[$name] = $Profiles[$name] }
    $content = [ordered]@{ Version = 1; Enabled = $Enabled; Profiles = $ordered } | ConvertTo-Json -Depth 8
    $temp = Join-Path $dir ([IO.Path]::GetRandomFileName())
    try {
        [IO.File]::WriteAllText($temp, $content + "`n", [Text.UTF8Encoding]::new($false))
        Move-Item -LiteralPath $temp -Destination $path -Force
    } finally { if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Force } }
    Get-TypezeroWallpaperMappings
}

function Set-TypezeroWallpaperProfileMapping {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory)][ValidatePattern('^[a-z0-9][a-z0-9-]*$')][string]$ThemeId,
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$ProfileName
    )
    $matches = @(Get-TypezeroDisplayFusionProfiles | Where-Object { $_.Name -eq $ProfileName })
    if ($matches.Count -ne 1) { throw "Exactly one DisplayFusion profile named '$ProfileName' must exist (found $($matches.Count))." }
    $config = Get-TypezeroWallpaperMappings
    if ($PSCmdlet.ShouldProcess($ThemeId, "Map theme to DisplayFusion profile '$ProfileName'")) {
        $config.Profiles[$ThemeId] = $ProfileName
        Save-TypezeroWallpaperMappings -Enabled $config.Enabled -Profiles $config.Profiles
    }
}

function Set-TypezeroWallpaperMappingEnabled {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param([Parameter(Mandatory)][bool]$Enabled)
    $config = Get-TypezeroWallpaperMappings
    if ($PSCmdlet.ShouldProcess('DisplayFusion wallpaper integration', "Set enabled=$Enabled")) {
        Save-TypezeroWallpaperMappings -Enabled $Enabled -Profiles $config.Profiles
    }
}

function Test-TypezeroWallpaperThemeMapping {
    [CmdletBinding()]
    param([Parameter(Mandatory)][ValidatePattern('^[a-z0-9][a-z0-9-]*$')][string]$ThemeId)
    $config = Get-TypezeroWallpaperMappings
    $name = if ($config.Profiles.ContainsKey($ThemeId)) { $config.Profiles[$ThemeId] } else { $null }
    $matches = if ($name) { @(Get-TypezeroDisplayFusionProfiles | Where-Object { $_.Name -eq $name }) } else { @() }
    $active = @(Get-TypezeroDisplayFusionProfiles | Where-Object Current)
    [pscustomobject]@{
        ThemeId = $ThemeId
        IntegrationEnabled = $config.Enabled
        MappedProfile = $name
        ProfileFound = $matches.Count -eq 1
        CurrentProfile = if ($active.Count -eq 1) { $active[0].Name } else { $null }
        Action = if (-not $config.Enabled) { 'DISABLED - no changes' } elseif (-not $name) { 'UNMAPPED - no changes' } elseif ($matches.Count -ne 1) { 'INVALID PROFILE - no changes' } elseif ($matches[0].Current) { 'ALREADY ACTIVE - no changes' } else { 'ELIGIBLE FOR EXPLICIT SWITCH' }
    }
}

function Invoke-TypezeroWallpaperThemeMapping {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory)][ValidatePattern('^[a-z0-9][a-z0-9-]*$')][string]$ThemeId,
        [switch]$Execute
    )
    $test = Test-TypezeroWallpaperThemeMapping -ThemeId $ThemeId
    if (-not $Execute) { return $test }
    if (-not $test.IntegrationEnabled) { throw 'Wallpaper integration is disabled; explicitly enable it first.' }
    if (-not $test.MappedProfile -or -not $test.ProfileFound) { throw 'No unique valid profile mapped to this theme.' }
    if ($test.Action -eq 'ALREADY ACTIVE - no changes') { return $test }
    if ($PSCmdlet.ShouldProcess("Theme '$ThemeId'", "Switch to DisplayFusion profile '$($test.MappedProfile)'")) {
        # The guarded provider independently prompts, backs up, and verifies the active profile.
        Invoke-TypezeroDisplayFusionProfileSwitch -ProfileName $test.MappedProfile -Execute -Confirm:$false
    }
}
