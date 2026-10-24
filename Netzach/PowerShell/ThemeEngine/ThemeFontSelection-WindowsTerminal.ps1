# Typezero ThemeEngine - save a theme's font, then use the normal theme apply path.
. (Join-Path $PSScriptRoot 'FontWeights-WindowsTerminal.ps1')

function Invoke-TypezeroThemeFontSelection {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [AllowNull()][psobject]$Selection,
        [string]$EngineRoot = $PSScriptRoot,
        [string]$ThemesRoot = (Join-Path $env:LOCALAPPDATA 'Typezero\ThemeEngine\themes'),
        [string]$ConfigPath = (Join-Path $env:LOCALAPPDATA 'Typezero\ThemeEngine\font-windows-terminal.json')
    )
    $ErrorActionPreference = 'Stop'
    $result = [ordered]@{
        Status = 'Cancelled'
        Theme = $null
        ThemeApplied = $false
        ThemeMayHaveChanged = $false
        FontPreferenceSaved = $false
        FontActivated = $false
        ApplyResult = $null
        Targets = @()
        Message = 'Selection cancelled; no changes requested.'
    }
    if ($null -eq $Selection) { return [pscustomobject]$result }
    foreach ($name in @('Accepted','ThemeApplyConsent','SaveFontPreferenceConsent')) {
        if (-not $Selection.PSObject.Properties[$name] -or $Selection.$name -isnot [bool]) {
            throw "Selection lacks explicit Boolean consent: $name"
        }
    }
    if (-not $Selection.Accepted -or -not $Selection.ThemeApplyConsent) {
        return [pscustomobject]$result
    }
    foreach ($name in @('Theme','Family','Size','Weight','PreviewOnly','SettingsChanged')) {
        if (-not $Selection.PSObject.Properties[$name]) { throw "Selection field missing: $name" }
    }
    if ($Selection.PreviewOnly -isnot [bool] -or -not $Selection.PreviewOnly -or
        $Selection.SettingsChanged -isnot [bool] -or $Selection.SettingsChanged) {
        throw 'Selection must come from a read-only preview.'
    }
    $id = [string]$Selection.Theme
    $family = [string]$Selection.Family
    $weight = [string]$Selection.Weight
    $installedThemes = Join-Path $env:LOCALAPPDATA 'Typezero\ThemeEngine\themes'
    if (-not [string]::Equals([IO.Path]::GetFullPath($ThemesRoot).TrimEnd('\','/'),
        [IO.Path]::GetFullPath($installedThemes).TrimEnd('\','/'), [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Selection must use the installed theme tree used by ThemeEngine apply.'
    }
    $installedConfig = Join-Path $env:LOCALAPPDATA 'Typezero\ThemeEngine\font-windows-terminal.json'
    if (-not [string]::Equals([IO.Path]::GetFullPath($ConfigPath),
        [IO.Path]::GetFullPath($installedConfig), [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Selection must use the installed font configuration used by ThemeEngine apply.'
    }
    if ($id -cnotmatch '\A[a-z0-9][a-z0-9-]*\z' -or
        -not (Test-Path -LiteralPath (Join-Path $ThemesRoot "$id\theme.conf") -PathType Leaf)) {
        throw 'Select a valid installed theme.'
    }
    if ([string]::IsNullOrWhiteSpace($family) -or $family -cne $family.Trim() -or
        $weight -cnotin @((Get-TypezeroTerminalFontWeights).Keys) -or
        ($Selection.Size -isnot [double] -and $Selection.Size -isnot [int] -and
         $Selection.Size -isnot [long] -and $Selection.Size -isnot [decimal])) {
        throw 'Invalid font preference selection.'
    }
    $size = [double]$Selection.Size
    if ([double]::IsNaN($size) -or [double]::IsInfinity($size) -or
        $size -lt 6 -or $size -gt 36 -or $size -ne [math]::Round($size,2)) {
        throw 'Select a font size from 6 to 36 with at most two decimal places.'
    }
    $engine = Join-Path $EngineRoot 'ThemeEngine.ps1'
    if (-not (Test-Path -LiteralPath $engine -PathType Leaf)) { throw 'ThemeEngine apply command missing.' }
    $result.Theme = $id
    $action = "Apply theme '$id' using ThemeEngine.ps1 apply"
    if ($Selection.SaveFontPreferenceConsent) { $action += '; save and apply the selected font, size and weight' }
    if (-not $PSCmdlet.ShouldProcess($id, $action)) {
        $result.Status = 'NotExecuted'
        $result.Message = 'No changes executed.'
        return [pscustomobject]$result
    }
    # Save first: the public apply command reads this same configuration.
    # A failed save must not apply colors with an older font preference.
    try {
        foreach ($module in @('FontProvider-WindowsTerminal.ps1','FontMapping-WindowsTerminal.ps1')) {
            $modulePath = Join-Path $EngineRoot $module
            if (-not (Test-Path -LiteralPath $modulePath -PathType Leaf)) { throw "Required font module missing: $module" }
            . $modulePath
        }
        if ($Selection.SaveFontPreferenceConsent) {
            $modulePath = Join-Path $EngineRoot 'FontMappingV2-WindowsTerminal.ps1'
            if (-not (Test-Path -LiteralPath $modulePath -PathType Leaf)) { throw 'Required font mapping writer missing.' }
            . $modulePath
            $config = Set-TypezeroWindowsFontMappingV2 -ThemeId $id -FontFamily $family `
                -Size $size -Weight $weight -ThemesRoot $ThemesRoot -ConfigPath $ConfigPath
            if ($null -eq $config) {
                $result.Status = 'PreferenceNotSaved'
                $result.Message = 'Font preference save was declined; the theme was not applied.'
                return [pscustomobject]$result
            }
            if ($config.Version -ne 2 -or -not $config.Mappings.ContainsKey($id) -or
                $config.Mappings[$id].Family -cne $family -or
                [double]$config.Mappings[$id].Size -ne $size -or $config.Mappings[$id].Weight -cne $weight) {
                throw 'Preference writer did not return the requested font mapping; inspect the configuration before retrying.'
            }
            $result.FontPreferenceSaved = $true
        }
        else { $config = Get-TypezeroWindowsFontMappings -Path $ConfigPath }
    }
    catch {
        $result.Status = 'PreferenceFailed'
        $result.Message = "Font preference could not be prepared: $($_.Exception.Message). The theme was not applied."
        return [pscustomobject]$result
    }
    try {
        $result.ThemeMayHaveChanged = $true
        # Color and font changes share the existing public apply command.
        $applied = & $engine -Command apply -Theme $id
        if ($null -ne $applied -and $applied.PSObject.Properties['Complete']) {
            $result.ApplyResult = $applied
            $result.Targets = @($applied.Targets)
            $result.ThemeMayHaveChanged = [bool]$applied.AppearanceMayHaveChanged
            if (-not $applied.Complete) {
                $result.Status = $applied.Status
                $fontTarget = @($applied.Targets | Where-Object Target -CEQ 'Font')
                $result.FontActivated = $fontTarget.Count -eq 1 -and $fontTarget[0].Status -in @('Applied','NoChange')
                $details = @($applied.Targets | ForEach-Object { "$($_.Target): $($_.Status) ($($_.Message))" }) -join '; '
                $preferenceMessage = if ($result.FontPreferenceSaved) { 'The selected font preference was saved.' } else { 'The font preference was not changed.' }
                $result.Message = "Theme application is $($applied.Status); full theme was not recorded. $details $preferenceMessage"
                return [pscustomobject]$result
            }
        }
        $result.ThemeApplied = $true
    }
    catch {
        $result.Status = 'ThemeFailed'
        $preferenceMessage = if ($result.FontPreferenceSaved) { 'The selected font preference was saved.' } else { 'The font preference was not changed.' }
        $result.Message = "Theme application failed: $($_.Exception.Message). Appearance changes may be partial. $preferenceMessage"
        return [pscustomobject]$result
    }
    $result.Status = 'ThemeApplied'
    $result.Message = "Theme '$id' applied. No saved font is configured for this theme."
    if ($config.Mappings.ContainsKey($id)) {
        try {
            $mapped = $config.Mappings[$id]
            $expectedFamily = if ($config.Version -eq 1) { [string]$mapped } else { [string]$mapped.Family }
            $actual = Get-TypezeroTerminalFontStatus
            if ($actual.Face -cne $expectedFamily -or ($config.Version -eq 2 -and (
                [double]$actual.Size -ne [double]$mapped.Size -or [string]$actual.Weight -cne [string]$mapped.Weight))) {
                throw 'Terminal settings do not match the saved font preference.'
            }
            $result.FontActivated = $true
            $result.Status = if ($result.FontPreferenceSaved) { 'ThemeAppliedPreferenceSaved' } else { 'ThemeApplied' }
            $fontDescription = if ($config.Version -eq 2) { "$expectedFamily, $($mapped.Size) pt, $($mapped.Weight)" } else { "$expectedFamily (saved family; existing size and weight retained)" }
            $result.Message = "Theme '$id' applied. Windows Terminal font verified: $fontDescription."
        }
        catch {
            $result.Status = 'ThemeAppliedFontUnverified'
            $result.Message = "Theme '$id' applied, but the saved Windows Terminal font could not be verified: $($_.Exception.Message)."
        }
    }
    [pscustomobject]$result
}
