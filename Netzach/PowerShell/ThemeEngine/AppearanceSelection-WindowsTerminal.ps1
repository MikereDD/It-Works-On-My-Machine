# The shell and existing WPF preview share these appearance actions.
. (Join-Path $PSScriptRoot 'TerminalFontControl-WindowsTerminal.ps1')

function Assert-TypezeroInstalledTerminalFontFamily {
    param([Parameter(Mandatory)][string]$Family)
    $installed = @(Get-TypezeroInstalledFontFamilies)
    # Preserve the existing Terminal alias, but only when its real family exists.
    $display = if ($Family -ceq 'JetBrainsMono Nerd Font') { 'JetBrainsMono NF' } else { $Family }
    if (@($installed | Where-Object { $_ -ieq $Family -or $_ -ieq $display }).Count -eq 0) {
        throw "Font family is not installed: $Family. Use font list or configure to select an installed family."
    }
}

function Read-TypezeroAppearanceBaseTheme {
    param([Parameter(Mandatory)][string]$Theme, [Parameter(Mandatory)][string]$ThemesRoot)
    if ($Theme -cnotmatch '\A[a-z0-9][a-z0-9-]*\z') { throw 'Invalid base theme ID.' }
    $conf = Join-Path $ThemesRoot "$Theme\theme.conf"
    if (-not (Test-Path -LiteralPath $conf -PathType Leaf)) { throw 'Preset base theme is no longer installed.' }
    $palette = @{}
    foreach ($line in [IO.File]::ReadAllLines($conf)) {
        if ($line -match '^\s*([A-Z_]+)\s*=\s*(.*?)\s*$') { $palette[$matches[1]]=$matches[2].Trim('"',"'") }
    }
    # Match Read-ThemeFile's established defaults for older base themes.
    foreach ($role in @(@('SELECTION','BORDER'),@('CURSOR','ACCENT_BRIGHT'),@('FOCUS','ACCENT'))) {
        if (-not $palette[$role[0]]) { $palette[$role[0]]=$palette[$role[1]] }
    }
    return $palette
}

# Capture Terminal settings independently of any selected typography. Shell-only
# operations must remain usable when an excluded font choice is unavailable.
function Get-TypezeroAppearanceSettingsSnapshot {
    $path = Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json'
    $bytes = [IO.File]::ReadAllBytes($path)
    $text = [Text.UTF8Encoding]::new($false,$true).GetString($bytes).TrimStart([char]0xfeff)
    $null = Get-TypezeroJsoncTree $text
    $data = ConvertFrom-Json -InputObject $text -AsHashtable
    if (@($data.profiles.list | Where-Object { $_.guid -ieq '{574e775e-4f2a-5b96-ac1e-a2962a402336}' }).Count -ne 1) {
        throw 'Select one PowerShell 7 Terminal profile before applying shell colors.'
    }
    [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes))
}

function Invoke-TypezeroAppearanceSelection {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [AllowNull()][psobject]$Selection,
        [string]$EngineRoot = $PSScriptRoot,
        [string]$ThemesRoot = (Join-Path $env:LOCALAPPDATA 'Typezero\ThemeEngine\themes'),
        [string]$PresetsPath = (Join-Path $env:LOCALAPPDATA 'Typezero\ThemeEngine\custom-presets.json'),
        [switch]$Force
    )
    if ($null -eq $Selection) {
        return [pscustomobject]@{Status='Cancelled';Changed=$false;Complete=$false;AppearanceMayHaveChanged=$false;Message='Cancelled; no changes requested.'}
    }
    if ($Selection.PreviewOnly -isnot [bool] -or -not $Selection.PreviewOnly -or
        $Selection.SettingsChanged -isnot [bool] -or $Selection.SettingsChanged) {
        throw 'Appearance choices must come from a read-only preview.'
    }
    $action = [string]$Selection.Action
    if ($action -cnotin @('Preview','ApplyShell','ApplyFont','ApplyDesktop','ApplyShellFont','ApplyDesktopShell','ApplyAll','ApplyTheme','SavePreset')) {
        throw 'Select Preview, an Apply operation, or Save Preset.'
    }
    $usesFont = $action -in @('Preview','ApplyFont','ApplyShellFont','ApplyAll','ApplyTheme','SavePreset')
    $usesTerminal = $action -in @('ApplyShell','ApplyFont','ApplyShellFont','ApplyDesktopShell','ApplyAll','ApplyTheme')
    $usesShell = $action -in @('ApplyShell','ApplyShellFont','ApplyDesktopShell','ApplyAll','ApplyTheme')
    $tuple = $null; $fontArgs = @{}
    if ($usesFont) {
        if ($Selection.Size -isnot [double] -and $Selection.Size -isnot [int] -and
            $Selection.Size -isnot [long] -and $Selection.Size -isnot [decimal]) { throw 'Font size must be numeric.' }
        $tuple = Assert-TypezeroTerminalFontChoice -Family $Selection.Family -Size $Selection.Size -Weight $Selection.Weight
        Assert-TypezeroInstalledTerminalFontFamily -Family $tuple.Family
        $fontArgs = @{Family=$tuple.Family;Size=$tuple.Size;Weight=$tuple.Weight}
    }
    if ($action -ceq 'SavePreset') {
        $replace = [bool]$Force
        if ($Selection.PSObject.Properties['ReplacePreset']) {
            if ($Selection.ReplacePreset -isnot [bool]) { throw 'Preset replacement must be an explicit Boolean choice.' }
            $replace = $replace -or $Selection.ReplacePreset
        }
        return Save-TypezeroAppearancePreset -Name $Selection.PresetName -Theme $Selection.Theme `
            @fontArgs -ThemesRoot $ThemesRoot -Path $PresetsPath -Force:$replace -WhatIf:$WhatIfPreference
    }
    if ($action -ceq 'Preview') { return Get-TypezeroTerminalFontPreview @fontArgs }
    $expected = ''
    if ($usesTerminal) {
        if (-not $Selection.PSObject.Properties['ExpectedSha256'] -or
            [string]$Selection.ExpectedSha256 -cnotmatch '\A[A-Fa-f0-9]{64}\z') {
            throw 'Preview these choices before applying; a settings snapshot is required.'
        }
        $expected = [string]$Selection.ExpectedSha256
        if ($expected -ine (Get-TypezeroAppearanceSettingsSnapshot)) {
            throw 'Terminal settings changed since Preview; preview the choices again.'
        }
    }
    if ($action -ceq 'ApplyFont') {
        return Set-TypezeroTerminalFontChoice @fontArgs -ExpectedSha256 $expected -WhatIf:$WhatIfPreference
    }
    $id = [string]$Selection.Theme
    $installed = Join-Path $env:LOCALAPPDATA 'Typezero\ThemeEngine\themes'
    if ($id -cnotmatch '\A[a-z0-9][a-z0-9-]*\z' -or
        -not (Test-Path -LiteralPath (Join-Path $ThemesRoot "$id\theme.conf") -PathType Leaf) -or
        [IO.Path]::GetFullPath($ThemesRoot).TrimEnd('\','/') -ine [IO.Path]::GetFullPath($installed).TrimEnd('\','/')) {
        throw 'Select a valid installed base theme.'
    }
    if ($usesShell) {
        $palette = Read-TypezeroAppearanceBaseTheme -Theme $id -ThemesRoot $ThemesRoot
        $required = @('BG','TEXT','CURSOR','SELECTION') + @(
            'BLACK','RED','GREEN','YELLOW','BLUE','PURPLE','CYAN','WHITE',
            'BRIGHT_BLACK','BRIGHT_RED','BRIGHT_GREEN','BRIGHT_YELLOW','BRIGHT_BLUE','BRIGHT_PURPLE','BRIGHT_CYAN','BRIGHT_WHITE'
        ) | ForEach-Object { if ($_ -in @('BG','TEXT','CURSOR','SELECTION')) { $_ } else { 'ANSI_' + $_ } }
        foreach ($key in $required) {
            if ($palette[$key] -cnotmatch '\A#[A-Fa-f0-9]{6}\z') {
                throw "Base theme lacks a complete Terminal palette ($key); no appearance was applied."
            }
        }
    }
    $command = switch ($action) {
        ApplyShell {'apply-shell'} ApplyDesktop {'apply-desktop'} ApplyShellFont {'apply-shell-font'}
        ApplyDesktopShell {'apply-desktop-shell'} ApplyAll {'apply-all'} ApplyTheme {'apply'}
    }
    if (-not $PSCmdlet.ShouldProcess($id, "$action; save no preferences")) {
        return [pscustomobject]@{Status='NotExecuted';Changed=$false;Complete=$false;AppearanceMayHaveChanged=$false;Message='No changes executed.'}
    }
    try {
        $arguments = @{Command=$command;Theme=$id}
        if ($usesFont) { $arguments.TerminalFont = [ordered]@{face=$tuple.Family;size=$tuple.Size;weight=$tuple.Weight} }
        # Keep the displayed snapshot through native activation and the final
        # atomic Terminal replacement, including the legacy full-apply alias.
        if ($usesTerminal) { $arguments.ExpectedSettingsSha256=$expected }
        $result = & (Join-Path $EngineRoot 'ThemeEngine.ps1') @arguments
        if ($null -ne $result -and $result.PSObject.Properties['Complete']) {
            $messages = @($result.Targets | ForEach-Object { "$($_.Target): $($_.Status)$(if ($_.Message) { ' - ' + $_.Message })" }) -join '; '
            $result | Add-Member -NotePropertyName Message -NotePropertyValue "$($result.Status): $messages" -Force
            return $result
        }
        # Retain callers of the old unstructured full-apply entry point.
        if ($usesFont) {
            $actual = Get-TypezeroTerminalFontStatus
            if ($actual.Face -cne $tuple.Family -or [double]$actual.Size -ne $tuple.Size -or $actual.Weight -cne $tuple.Weight) {
                throw 'Terminal font readback did not match the previewed choices.'
            }
        }
    }
    catch {
        throw "Theme application failed or was not verified; appearance may be partial. $($_.Exception.Message)"
    }
    [pscustomobject]@{Status='ThemeApplied';Theme=$id;Family=$tuple.Family;Size=$tuple.Size;Weight=$tuple.Weight;
        Complete=$true;Changed=$true;AppearanceMayHaveChanged=$true;FontActivated=$usesFont;
        Message="Theme '$id' applied. Preferences were not saved."}
}

function Invoke-TypezeroFontCommand {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Action, [AllowNull()][string[]]$Arguments,
        [string]$EngineRoot=$PSScriptRoot,
        [string]$ThemesRoot=(Join-Path $env:LOCALAPPDATA 'Typezero\ThemeEngine\themes'),
        [string]$ExpectedSha256)
    $argsList = @($Arguments | Where-Object { $null -ne $_ })
    $force = $false
    $selection = [pscustomobject]@{Action='Preview';Theme='';PresetName='';Family='';Size=[double]12;
        Weight='normal';ExpectedSha256=$ExpectedSha256;PreviewOnly=$true;SettingsChanged=$false}
    switch ($Action) {
        'presets' {
            if ($argsList.Count) { throw 'Usage: themeengine font presets' }
            return Get-TypezeroAppearancePresets
        }
        { $_ -in @('load-preset','preview-preset','apply-preset') } {
            if ($argsList.Count -ne 1) { throw "Usage: themeengine font $Action <name>" }
            $presets = @(Get-TypezeroAppearancePresets | Where-Object { $_.Name -ceq $argsList[0] })
            if ($presets.Count -ne 1) { throw "Custom preset not found: $($argsList[0])" }
            foreach ($key in @('Theme','Family','Size','Weight')) { $selection.$key = $presets[0].$key }
            $selection.PresetName = $presets[0].Name
            $selection.Action = if ($Action -ceq 'apply-preset') { 'ApplyTheme' } else { 'Preview' }
        }
        { $_ -in @('preview-font','apply-font','preview-theme','apply-theme','save-preset') } {
            $saving = $Action -ceq 'save-preset'
            $withTheme = $Action -in @('preview-theme','apply-theme')
            $force = $saving -and $argsList.Count -eq 6 -and $argsList[5] -ceq '--replace'
            $count = if ($saving) { 5 } elseif ($withTheme) { 4 } else { 3 }
            if ($argsList.Count -ne $count -and -not $force) {
                throw "Usage: themeengine font $Action $(if ($saving) {'<name> <theme> '} elseif ($withTheme) {'<theme> '})`"<family>`" <size> <weight>$(if ($saving) {' [--replace]'})"
            }
            $offset = if ($saving) { 2 } elseif ($withTheme) { 1 } else { 0 }
            $size = 0.0
            if (-not [double]::TryParse($argsList[$offset+1], [Globalization.NumberStyles]::AllowDecimalPoint,
                [Globalization.CultureInfo]::InvariantCulture, [ref]$size)) { throw 'Invalid font size; use a decimal point.' }
            $selection.Family=$argsList[$offset]; $selection.Size=$size; $selection.Weight=$argsList[$offset+2]
            $selection.Action = if ($saving) { 'SavePreset' } elseif ($Action -ceq 'apply-font') { 'ApplyFont' } elseif ($Action -ceq 'apply-theme') { 'ApplyTheme' } else { 'Preview' }
            if ($saving) { $selection.PresetName=$argsList[0]; $selection.Theme=$argsList[1] }
            if ($withTheme) { $selection.Theme=$argsList[0] }
        }
        default { throw "Unknown appearance action: $Action" }
    }
    if ($Action -in @('load-preset','preview-preset','apply-preset','preview-theme','apply-theme')) {
        $null = Read-TypezeroAppearanceBaseTheme -Theme $selection.Theme -ThemesRoot $ThemesRoot
        $null = Assert-TypezeroTerminalFontChoice -Family $selection.Family -Size $selection.Size -Weight $selection.Weight
        Assert-TypezeroInstalledTerminalFontFamily -Family $selection.Family
    }
    if ($Action -ceq 'load-preset') {
        # Load choices for further editing; no Terminal settings need be present.
        return $selection
    }
    if ($Action -in @('preview-preset','preview-theme')) {
        # The same base palette preview used by the shell's theme preview.
        . (Join-Path $EngineRoot 'ThemePresentation.ps1')
        $palette = Read-TypezeroAppearanceBaseTheme -Theme $selection.Theme -ThemesRoot $ThemesRoot
        Write-Host (Format-TypezeroThemePreview -Theme $palette -Id $selection.Theme)
    }
    if ($selection.Action -in @('ApplyFont','ApplyTheme') -and -not $selection.ExpectedSha256) {
        $selection.ExpectedSha256 = (Get-TypezeroTerminalFontPreview -Family $selection.Family `
            -Size $selection.Size -Weight $selection.Weight).ExpectedSha256
    }
    Invoke-TypezeroAppearanceSelection -Selection $selection -EngineRoot $EngineRoot -ThemesRoot $ThemesRoot -Force:([bool]$force)
}
