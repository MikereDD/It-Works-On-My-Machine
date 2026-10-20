# Typezero ThemeEngine - explicit theme application and optional V2 preference.
# Never activates fonts, enables integration, or performs recovery.
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
    if ($id -cnotmatch '\A[a-z0-9][a-z0-9-]*\z' -or
        -not (Test-Path -LiteralPath (Join-Path $ThemesRoot "$id\theme.conf") -PathType Leaf)) {
        throw 'Select a valid installed theme.'
    }
    if ([string]::IsNullOrWhiteSpace($family) -or $family -cne $family.Trim() -or
        $weight -cnotin @('normal','semi-bold') -or
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
    if ($Selection.SaveFontPreferenceConsent) { $action += '; save V2 font preference (no live font activation)' }
    if (-not $PSCmdlet.ShouldProcess($id, $action)) {
        $result.Status = 'NotExecuted'
        $result.Message = 'No changes executed.'
        return [pscustomobject]$result
    }
    # Fail before the broader theme command can touch Vim/native appearance.
    # The existing color writer independently retains this ownership guard.
    $terminalPath = Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json'
    try {
        if ((Test-Path -LiteralPath $terminalPath -PathType Leaf) -and
            [IO.File]::ReadAllText($terminalPath).Contains('/* TYPEZERO_FONT_V2 */')) {
            $result.Status = 'Blocked'
            $result.Message = 'Theme application blocked by the active V2 font ownership marker. Use a separately authorized recovery path before retrying. No recovery was attempted; font preference was not saved.'
            return [pscustomobject]$result
        }
        $result.ThemeMayHaveChanged = $true
        # Invoke the existing public command with bound arguments; no alternate writer.
        $null = & $engine -Command apply -Theme $id
        $result.ThemeApplied = $true
    }
    catch {
        $result.Status = 'ThemeFailed'
        $result.Message = "Theme application failed: $($_.Exception.Message). Appearance changes may be partial. Font preference was not saved; no font activation or recovery was attempted."
        return [pscustomobject]$result
    }
    $result.Status = 'ThemeApplied'
    $result.Message = "Theme '$id' applied. Font preference not saved. Live Terminal font activation remains disabled."
    if ($Selection.SaveFontPreferenceConsent) {
        try {
            foreach ($module in @('FontProvider-WindowsTerminal.ps1','FontMapping-WindowsTerminal.ps1','FontMappingV2-WindowsTerminal.ps1')) {
                $modulePath = Join-Path $EngineRoot $module
                if (-not (Test-Path -LiteralPath $modulePath -PathType Leaf)) { throw "Required preference module missing: $module" }
                . $modulePath
            }
            $saved = Set-TypezeroWindowsFontMappingV2 -ThemeId $id -FontFamily $family `
                -Size $size -Weight $weight -ThemesRoot $ThemesRoot -ConfigPath $ConfigPath
            if ($null -eq $saved) {
                $result.Message = "Theme '$id' applied. Font preference save was declined; live Terminal font activation remains disabled."
            }
            elseif ($saved.Version -ne 2 -or -not $saved.Mappings.ContainsKey($id) -or
                $saved.Mappings[$id].Family -cne $family -or
                [double]$saved.Mappings[$id].Size -ne $size -or $saved.Mappings[$id].Weight -cne $weight) {
                throw 'Preference writer did not return the requested V2 mapping; inspect the configuration before retrying.'
            }
            else {
                $result.FontPreferenceSaved = $true
                $result.Status = 'ThemeAppliedPreferenceSaved'
                $result.Message = "Theme '$id' applied. V2 font preference saved: $family, $size pt, $weight. The saved preference does not activate the font; live Terminal font activation remains disabled."
            }
        }
        catch {
            $result.Status = 'ThemeAppliedPreferenceFailed'
            $result.Message = "Theme '$id' applied, but font preference save failed or could not be verified: $($_.Exception.Message). Live Terminal font activation remains disabled."
        }
    }
    [pscustomobject]$result
}
