# Typezero ThemeEngine - DisplayFusion wallpaper provider
# Version: 0.1-dev (discovery only)
# This provider never writes to DisplayFusion settings or changes wallpapers.

function Get-TypezeroDisplayFusionInfo {
    [CmdletBinding()]
    param()
    $key = 'HKCU:\Software\Binary Fortress Software\DisplayFusion'
    $paths = @(
        (Join-Path $env:ProgramFiles 'DisplayFusion\DisplayFusionCommand.exe')
    )
    if (${env:ProgramFiles(x86)}) {
        $paths += Join-Path ${env:ProgramFiles(x86)} 'DisplayFusion\DisplayFusionCommand.exe'
    }
    $command = $paths | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
    $settings = Get-ItemProperty -LiteralPath $key -ErrorAction SilentlyContinue
    $process = @(Get-Process -Name DisplayFusion -ErrorAction SilentlyContinue)
    [pscustomobject]@{
        Installed        = [bool]$command
        CommandPath      = if ($command) { [string]$command } else { $null }
        Version          = if ($command) { (Get-Item -LiteralPath $command).VersionInfo.ProductVersion } else { $null }
        Running          = $process.Count -gt 0
        StartWithWindows = if ($settings) { $settings.StartWithWindows } else { $null }
        WallpaperEnabled = if ($settings) { $settings.WallpaperEnabled } else { $null }
        SlideshowEnabled = if ($settings) { $settings.WallpaperSlideshowEnabled } else { $null }
        CurrentProfileId = if ($settings) { $settings.WallpaperCurrentProfile } else { $null }
    }
}

function Get-TypezeroDisplayFusionProfiles {
    [CmdletBinding()]
    param()
    $key = 'HKCU:\Software\Binary Fortress Software\DisplayFusion\Wallpaper'
    $info = Get-TypezeroDisplayFusionInfo
    if (-not (Test-Path -LiteralPath $key)) { return }
    foreach ($subkey in @(Get-ChildItem -LiteralPath $key -ErrorAction Stop)) {
        if ($subkey.PSChildName -notmatch '^[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$') { continue }
        $p = Get-ItemProperty -LiteralPath $subkey.PSPath -ErrorAction Stop
        [pscustomobject]@{
            Id              = $subkey.PSChildName
            Name            = [string]$p.Name
            Current         = $subkey.PSChildName -eq $info.CurrentProfileId
            WallpaperSpan   = $p.WallpaperSpan
            ConfiguredSlots = @(0..15 | Where-Object {
                $null -ne $p.PSObject.Properties["Screen_${_}_Width"]
            }).Count
        }
    }
}

function Get-TypezeroDisplayFusionMonitorSummary {
    [CmdletBinding()]
    param([string]$ProfileId)
    $base = 'HKCU:\Software\Binary Fortress Software\DisplayFusion\Wallpaper'
    $info = Get-TypezeroDisplayFusionInfo
    if (-not $ProfileId) { $ProfileId = $info.CurrentProfileId }
    if (-not $ProfileId -or $ProfileId -notmatch '^[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$') {
        throw 'No valid DisplayFusion wallpaper profile ID available.'
    }
    $key = Join-Path $base $ProfileId
    if (-not (Test-Path -LiteralPath $key)) { throw "Wallpaper profile not found: $ProfileId" }
    $p = Get-ItemProperty -LiteralPath $key -ErrorAction Stop
    foreach ($i in 0..15) {
        if ($null -eq $p.PSObject.Properties["Screen_${i}_Width"]) { continue }
        [pscustomobject]@{
            Slot       = $i
            Width      = $p."Screen_${i}_Width"
            Height     = $p."Screen_${i}_Height"
            Primary    = $p."Screen_${i}_Primary"
            X          = $p."Screen_${i}_X"
            Y          = $p."Screen_${i}_Y"
            Wallpaper  = $p."Wallpaper_${i}_FileName"
            Rotation   = $p."Wallpaper_${i}_Rotate"
            Sizing     = $p."Wallpaper_${i}_Sizing"
        }
    }
}

# Typezero DisplayFusion safety API v0.2
# Backups contain private DisplayFusion configuration. Keep them local; never commit.
function Backup-TypezeroDisplayFusionWallpaperSettings {
    [CmdletBinding()]
    param()
    $regPath = 'HKEY_CURRENT_USER\Software\Binary Fortress Software\DisplayFusion\Wallpaper'
    $psPath = 'HKCU:\Software\Binary Fortress Software\DisplayFusion\Wallpaper'
    if (-not (Test-Path -LiteralPath $psPath)) { throw 'DisplayFusion wallpaper registry subtree not found.' }
    $info = Get-TypezeroDisplayFusionInfo
    if (-not $info.Installed) { throw 'DisplayFusion command utility was not detected.' }
    $root = Join-Path $env:LOCALAPPDATA 'Typezero\ThemeEngine\backups\displayfusion'
    $folder = Join-Path $root (Get-Date -Format 'yyyyMMdd-HHmmss-fffffff')
    New-Item -ItemType Directory -Path $folder -Force | Out-Null
    $regFile = Join-Path $folder 'wallpaper-profiles.reg'
    $manifest = Join-Path $folder 'manifest.json'
    # Export only Wallpaper subtree, not parent containing license/security fields.
    & reg.exe export $regPath $regFile /y | Out-Null
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $regFile) -or
        (Get-Item -LiteralPath $regFile).Length -lt 32) {
        throw "DisplayFusion wallpaper registry export failed. Inspect $folder"
    }
    $hash = (Get-FileHash -LiteralPath $regFile -Algorithm SHA256).Hash
    $metadata = [ordered]@{
        CapturedAt = (Get-Date).ToString('o')
        CurrentProfileId = $info.CurrentProfileId
        DisplayFusionVersion = $info.Version
        ProfileCount = @(Get-TypezeroDisplayFusionProfiles).Count
        RegistryExport = 'wallpaper-profiles.reg'
        SHA256 = $hash
        Note = 'Private local backup; contains wallpaper paths/settings. Not a full DisplayFusion settings backup.'
    }
    $metadata | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $manifest -Encoding utf8
    if (-not (Test-Path -LiteralPath $manifest)) { throw 'Backup manifest was not created.' }
    [pscustomobject]@{
        Status = 'PASS'
        BackupDirectory = $folder
        RegistryFile = $regFile
        SHA256 = $hash
        CurrentProfileId = $info.CurrentProfileId
    }
}

function Test-TypezeroDisplayFusionProfileSwitch {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$ProfileName)
    $info = Get-TypezeroDisplayFusionInfo
    if (-not $info.Installed) { throw 'DisplayFusion command utility not found.' }
    $profiles = @(Get-TypezeroDisplayFusionProfiles)
    $matches = @($profiles | Where-Object { $_.Name -eq $ProfileName })
    if ($matches.Count -eq 0) { throw "Profile '$ProfileName' not found. Dry run refused." }
    if ($matches.Count -gt 1) { throw "Profile name '$ProfileName' is ambiguous. Dry run refused." }
    $selection = $matches[0]
    [pscustomobject]@{
        Mode = 'DRY RUN - no changes'
        ProfileName = $selection.Name
        ProfileId = $selection.Id
        AlreadyCurrent = [bool]$selection.Current
        DisplayFusionRunning = [bool]$info.Running
        PlannedCommand = ('"{0}" -WallpaperLoadProfile "{1}"' -f $info.CommandPath, $selection.Name)
        Note = 'Informational only. Nothing was executed; a backup is required before future live switching.'
    }
}

# Typezero DisplayFusion guarded switching API v0.3
# Nothing is applied unless caller explicitly supplies -Execute and confirms.
function Invoke-TypezeroDisplayFusionProfileSwitch {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$ProfileName,
        [switch]$Execute
    )
    $info = Get-TypezeroDisplayFusionInfo
    if (-not $info.Installed -or -not $info.CommandPath -or
        -not (Test-Path -LiteralPath $info.CommandPath)) { throw 'DisplayFusion command utility not found.' }
    $profiles = @(Get-TypezeroDisplayFusionProfiles)
    $matches = @($profiles | Where-Object { $_.Name -eq $ProfileName })
    if ($matches.Count -ne 1) { throw "Expected exactly one saved profile named '$ProfileName'; found $($matches.Count)." }
    $target = $matches[0]
    if (-not $info.CurrentProfileId) { throw 'Active wallpaper profile could not be identified. Refusing switch.' }
    $previous = @($profiles | Where-Object { $_.Id -eq $info.CurrentProfileId })
    if ($previous.Count -ne 1) { throw 'Active profile not found among saved profiles. Refusing switch.' }
    if (-not $info.Running) { throw 'DisplayFusion is not running. Refusing switch.' }
    if (-not $Execute) {
        return Test-TypezeroDisplayFusionProfileSwitch -ProfileName $ProfileName
    }
    if ($target.Id -eq $previous[0].Id) {
        return [pscustomobject]@{
            Status = 'NO CHANGE'
            ProfileName = $target.Name
            ProfileId = $target.Id
            PreviousProfileName = $previous[0].Name
            BackupDirectory = $null
            Note = 'Requested wallpaper profile already active; command was not executed.'
        }
    }
    if (-not $PSCmdlet.ShouldProcess("DisplayFusion wallpaper profile '$($target.Name)'", 'Back up wallpaper registry and load saved profile')) {
        return
    }
    # Create and verify a fresh private local backup before applying any profile.
    $backup = Backup-TypezeroDisplayFusionWallpaperSettings
    if ($backup.Status -ne 'PASS' -or $backup.CurrentProfileId -ne $previous[0].Id -or
        -not (Test-Path -LiteralPath $backup.RegistryFile)) { throw 'Backup verification failed; no profile switch attempted.' }
    $actualHash = (Get-FileHash -LiteralPath $backup.RegistryFile -Algorithm SHA256).Hash
    if ($actualHash -ne $backup.SHA256) { throw 'Backup checksum mismatch; no profile switch attempted.' }
    # Recheck immediately after backup so a concurrent wallpaper-profile change cannot be missed.
    $fresh = Get-TypezeroDisplayFusionInfo
    if (-not $fresh.Running -or $fresh.CurrentProfileId -ne $previous[0].Id) {
        throw 'DisplayFusion active profile changed during backup; no switch attempted.'
    }
    $process = Start-Process -FilePath $fresh.CommandPath -ArgumentList @('-WallpaperLoadProfile', ('"' + $target.Name + '"')) -PassThru -ErrorAction Stop
    try {
        if (-not $process.WaitForExit(15000)) {
            throw 'DisplayFusion command did not exit within 15 seconds. Check DisplayFusion before retrying; switching state is unknown.'
        }
        if ($process.ExitCode -ne 0) {
            throw "DisplayFusion command returned exit code $($process.ExitCode). Check state before retrying."
        }
    } finally {
        $process.Dispose()
    }
    $observed = $false
    for ($i = 0; $i -lt 20; $i++) {
        $current = Get-TypezeroDisplayFusionInfo
        if ($current.CurrentProfileId -eq $target.Id) { $observed = $true; break }
        Start-Sleep -Milliseconds 500
    }
    if (-not $observed) {
        throw "Profile load was issued, but registry did not confirm '$($target.Name)' as active. Check DisplayFusion manually. Backup: $($backup.BackupDirectory). Previous profile: $($previous[0].Name)"
    }
    [pscustomobject]@{
        Status = 'VERIFIED'
        ProfileName = $target.Name
        ProfileId = $target.Id
        PreviousProfileName = $previous[0].Name
        PreviousProfileId = $previous[0].Id
        BackupDirectory = $backup.BackupDirectory
        Note = 'DisplayFusion active profile ID verified; visually inspect monitor wallpapers. To restore, invoke this function explicitly with the previous profile name.'
    }
}
