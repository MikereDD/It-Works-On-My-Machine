# Interactive shell over the same read-only selection and explicit actions as WPF.
. (Join-Path $PSScriptRoot 'AppearanceSelection-WindowsTerminal.ps1')
. (Join-Path $PSScriptRoot 'ThemePresentation.ps1')

function Select-TypezeroConfigureItem {
    param([string]$Label, [AllowEmptyCollection()][string[]]$Items,
        [scriptblock]$ReadInput, [scriptblock]$WriteOutput)
    $filter = ''; $page = 0; $pageSize = 15
    while ($true) {
        $visible = @($Items | Where-Object { $_.IndexOf($filter,[StringComparison]::OrdinalIgnoreCase) -ge 0 })
        $pages = [math]::Max(1,[math]::Ceiling($visible.Count / $pageSize))
        $page = [math]::Min($page,$pages-1)
        & $WriteOutput "$Label ($($visible.Count) matches; page $($page+1)/$pages). Number/name, /search, n/p, Enter/q back."
        for ($i = $page*$pageSize; $i -lt [math]::Min(($page+1)*$pageSize,$visible.Count); $i++) {
            & $WriteOutput ('  {0}. {1}' -f ($i+1),$visible[$i])
        }
        $answer = & $ReadInput $Label
        if ($null -eq $answer) { return [pscustomobject]@{EndOfInput=$true;Value=$null} }
        $answer = ([string]$answer).Trim()
        if (-not $answer -or $answer -in @('q','cancel')) { return }
        if ($answer.StartsWith('/')) { $filter=$answer.Substring(1); $page=0; continue }
        if ($answer -eq 'n') { $page=[math]::Min($page+1,$pages-1); continue }
        if ($answer -eq 'p') { $page=[math]::Max(0,$page-1); continue }
        if ($answer -match '^\d+$') {
            $number = 0
            if ([int]::TryParse($answer,[ref]$number) -and $number -ge 1 -and $number -le $visible.Count) {
                return [pscustomobject]@{EndOfInput=$false;Value=$visible[$number-1]}
            }
            & $WriteOutput 'Invalid selection number.'
            continue
        }
        $exact = @($Items | Where-Object { $_ -ieq $answer })
        if ($exact.Count -eq 1) { return [pscustomobject]@{EndOfInput=$false;Value=$exact[0]} }
        $filter=$answer; $page=0
    }
}

function Invoke-TypezeroThemeConfigure {
    [CmdletBinding()]
    param([string]$EngineRoot=$PSScriptRoot,
        [string]$ThemesRoot=(Join-Path $env:LOCALAPPDATA 'Typezero\ThemeEngine\themes'),
        # These hooks keep console interaction testable without changing appearance.
        [scriptblock]$ReadInput={ param($Prompt) Read-Host $Prompt },
        [scriptblock]$WriteOutput={ param($Text) Write-Host $Text })
    $themes = @(Get-ChildItem -LiteralPath $ThemesRoot -Directory | Where-Object {
        $_.Name -cmatch '\A[a-z0-9][a-z0-9-]*\z' -and
        (Test-Path -LiteralPath (Join-Path $_.FullName 'theme.conf') -PathType Leaf)
    } | Sort-Object Name | ForEach-Object Name)
    if (-not $themes.Count) { throw 'No installed base themes. Run bootstrap first.' }
    $fonts = @(Get-TypezeroInstalledFontFamilies)
    if (-not $fonts.Count) { & $WriteOutput 'No installed fonts found. Shell and Desktop operations remain available.' }
    $marker = Join-Path (Split-Path -Parent $ThemesRoot) 'current-theme'
    $current = if (Test-Path -LiteralPath $marker -PathType Leaf) { [IO.File]::ReadAllText($marker).Trim() } else { '' }
    $id = if ($current -cin $themes) { $current } else { $themes[0] }
    if ($id -cne $current) { & $WriteOutput "No installed current theme recorded; starting with $id (not applied)." }
    $state = [pscustomobject]@{Action='Preview';Theme=$id;Family='';Size=[double]12;Weight='normal';
        PresetName='';ReplacePreset=$false;ExpectedSha256='';PreviewOnly=$true;SettingsChanged=$false}
    try {
        $font = Get-TypezeroTerminalFontStatus
        $state.Family=[string]$font.Face; $state.Size=[double]$font.Size; $state.Weight=[string]$font.Weight
        # Terminal also accepts numeric OpenType weights. Keep an equivalent named choice.
        foreach ($name in (Get-TypezeroTerminalFontWeights).Keys) {
            if ($state.Weight -ceq [string](Get-TypezeroTerminalFontWeights)[$name]) { $state.Weight=$name; break }
        }
    } catch { & $WriteOutput "Current Terminal font unavailable: $($_.Exception.Message). Select a family before applying." }
    $sessionChanged=$false; $preferencesSaved=$false; $mayHaveChanged=$false; $lastError=''; $lastResult=$null
    while ($true) {
        & $WriteOutput "`nTheme: $($state.Theme) | Font: $($state.Family) | $($state.Size) pt | $($state.Weight) | Preset: $($state.PresetName)"
        & $WriteOutput '1 Theme  2 Font family  3 Size  4 Weight  5 Preview  6 Apply Font  7 Apply All'
        & $WriteOutput '8 Save preset  9 List presets  10 Load preset  11 Apply preset (All)'
        & $WriteOutput '12 Apply Shell  13 Apply Desktop  14 Apply Shell+Font  15 Apply Desktop+Shell  q Cancel/exit'
        $answer = & $ReadInput 'Action'
        if ($null -eq $answer -or ([string]$answer).Trim() -in @('q','cancel','exit','')) {
            return [pscustomobject]@{Status='Cancelled';SessionChanged=$sessionChanged;PreferencesSaved=$preferencesSaved;
                AppearanceMayHaveChanged=($sessionChanged -or $mayHaveChanged);LastError=$lastError;LastResult=$lastResult;
                Theme=$state.Theme;Family=$state.Family;Size=$state.Size;Weight=$state.Weight;PresetName=$state.PresetName;
                Message='Configure closed. Unsaved choices discarded; completed actions remain in effect.'}
        }
        try {
            switch (([string]$answer).Trim()) {
                { $_ -in @('1','2','4') } {
                    $label = switch ($_) { '1' {'Theme'} '2' {'Font family'} '4' {'Weight'} }
                    $items = switch ($_) { '1' {$themes} '2' {$fonts} '4' {@((Get-TypezeroTerminalFontWeights).Keys)} }
                    $choice = Select-TypezeroConfigureItem -Label $label -Items $items -ReadInput $ReadInput -WriteOutput $WriteOutput
                    if ($choice.EndOfInput) { $ReadInput={ $null }; continue }
                    if ($null -ne $choice) {
                        switch ($label) { 'Theme' {$state.Theme=$choice.Value} 'Font family' {$state.Family=$choice.Value} 'Weight' {$state.Weight=$choice.Value} }
                        $state.ExpectedSha256=''; $state.PresetName=''
                    }
                }
                '3' {
                    $value = & $ReadInput 'Size 6-36, at most two decimals (Enter/q back)'
                    if ($null -eq $value) { $ReadInput={ $null }; continue }
                    $value=([string]$value).Trim()
                    if (-not $value -or $value -in @('q','cancel')) { continue }
                    $size=0.0
                    if (-not [double]::TryParse($value,[Globalization.NumberStyles]::AllowDecimalPoint,
                        [Globalization.CultureInfo]::InvariantCulture,[ref]$size) -or
                        -not [double]::IsFinite($size) -or $size -lt 6 -or $size -gt 36 -or $size -ne [math]::Round($size,2)) {
                        throw 'Select a size from 6 to 36 with at most two decimal places; use a decimal point.'
                    }
                    $state.Size=$size; $state.ExpectedSha256=''; $state.PresetName=''
                }
                { $_ -in @('5','6','7','8','12','13','14','15') } {
                    $state.Action = switch ($_) { '5' {'Preview'} '6' {'ApplyFont'} '7' {'ApplyTheme'} '8' {'SavePreset'} '12' {'ApplyShell'} '13' {'ApplyDesktop'} '14' {'ApplyShellFont'} '15' {'ApplyDesktopShell'} }
                    $state.ReplacePreset=$false
                    if ($_ -eq '8') {
                        $name = & $ReadInput 'Preset name (lowercase letters/digits/hyphens; Enter/q back)'
                        if ($null -eq $name) { $ReadInput={ $null }; continue }
                        if (-not $name -or $name -in @('q','cancel')) { continue }
                        $state.PresetName=[string]$name
                        if (@(Get-TypezeroAppearancePresets | Where-Object Name -CEQ $name).Count) {
                            $replace = & $ReadInput "Preset '$name' exists. Type replace to overwrite, otherwise cancel"
                            if ($null -eq $replace) { $ReadInput={ $null }; continue }
                            if ($replace -cne 'replace') { continue }
                            $state.ReplacePreset=$true
                        }
                    }
                    if ($state.Action -in @('ApplyFont','ApplyTheme','ApplyAll','ApplyShell','ApplyShellFont','ApplyDesktopShell') -and -not $state.ExpectedSha256) {
                        $state.ExpectedSha256=Get-TypezeroAppearanceSettingsSnapshot
                    }
                    $result = Invoke-TypezeroAppearanceSelection -Selection $state -EngineRoot $EngineRoot -ThemesRoot $ThemesRoot
                    if ($state.Action -eq 'Preview') {
                        $palette=Read-TypezeroAppearanceBaseTheme -Theme $state.Theme -ThemesRoot $ThemesRoot
                        & $WriteOutput (Format-TypezeroThemePreview -Theme $palette -Id $state.Theme)
                        $state.ExpectedSha256=$result.ExpectedSha256
                        & $WriteOutput "Current font: $($result.CurrentFamily), $($result.CurrentSize) pt, $($result.CurrentWeight)."
                        & $WriteOutput 'Shell preview uses the current terminal font. Use font theme-preview for a WPF font specimen.'
                    }
                    & $WriteOutput $result.Message
                    if ($state.Action -eq 'SavePreset') { $preferencesSaved=$true }
                    if ($state.Action -like 'Apply*') {
                        $lastResult=$result
                        $sessionChanged=$sessionChanged -or [bool]$result.Changed
                        $mayHaveChanged=$mayHaveChanged -or [bool]$result.AppearanceMayHaveChanged
                        if ($result.PSObject.Properties['Complete'] -and -not $result.Complete) {
                            $lastError=$result.Message
                        }
                        $state.ExpectedSha256=''
                    }
                }
                '9' {
                    $presets=@(Get-TypezeroAppearancePresets)
                    if (-not $presets.Count) { & $WriteOutput 'No custom presets saved.' }
                    foreach ($preset in $presets) { & $WriteOutput "$($preset.Name): $($preset.Theme) | $($preset.Family), $($preset.Size) pt, $($preset.Weight)" }
                }
                { $_ -in @('10','11') } {
                    $apply = $_ -eq '11'
                    $choice=Select-TypezeroConfigureItem -Label 'Preset' -Items @(Get-TypezeroAppearancePresets | ForEach-Object Name) -ReadInput $ReadInput -WriteOutput $WriteOutput
                    if ($choice.EndOfInput) { $ReadInput={ $null }; continue }
                    if ($null -eq $choice) { continue }
                    $loaded=Invoke-TypezeroFontCommand -Action load-preset -Arguments @($choice.Value) -EngineRoot $EngineRoot -ThemesRoot $ThemesRoot
                    foreach ($key in @('Theme','Family','Size','Weight','PresetName')) { $state.$key=$loaded.$key }
                    $state.ExpectedSha256=''
                    & $WriteOutput "Loaded preset '$($state.PresetName)' into the choices."
                    if ($apply) {
                        $state.Action='ApplyTheme'
                        $state.ExpectedSha256=(Get-TypezeroTerminalFontPreview -Family $state.Family -Size $state.Size -Weight $state.Weight).ExpectedSha256
                        $result=Invoke-TypezeroAppearanceSelection -Selection $state -EngineRoot $EngineRoot -ThemesRoot $ThemesRoot
                        & $WriteOutput $result.Message
                        $lastResult=$result
                        $sessionChanged=$sessionChanged -or [bool]$result.Changed
                        $mayHaveChanged=$mayHaveChanged -or [bool]$result.AppearanceMayHaveChanged
                        if ($result.PSObject.Properties['Complete'] -and -not $result.Complete) { $lastError=$result.Message }
                        $state.ExpectedSha256=''
                    }
                }
                default { & $WriteOutput 'Choose a listed action number, or q to cancel.' }
            }
        } catch {
            $lastError=$_.Exception.Message
            if ($lastError -like '*appearance may be partial*') { $mayHaveChanged=$true }
            & $WriteOutput "Error: $lastError"; $state.ExpectedSha256=''
        }
    }
}
