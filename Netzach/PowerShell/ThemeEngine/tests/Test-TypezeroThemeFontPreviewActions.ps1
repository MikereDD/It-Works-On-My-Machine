# Offline WPF action fixtures. The real window is initialized but never displayed.
# Run: pwsh -NoProfile -STA -File .\tests\Test-TypezeroThemeFontPreviewActions.ps1
[CmdletBinding()]
param([string]$FixtureParent = [IO.Path]::GetTempPath())
$ErrorActionPreference = 'Stop'
if ([Threading.Thread]::CurrentThread.ApartmentState -ne 'STA') { throw 'Run with pwsh -STA.' }
Add-Type -AssemblyName PresentationFramework
$engineSource = Split-Path -Parent $PSScriptRoot
. (Join-Path $engineSource 'ThemeFontPreview-WindowsTerminal.ps1')
$originalLocalAppData = $env:LOCALAPPDATA
$root = Join-Path $FixtureParent ('typezero-preview-actions-' + [guid]::NewGuid().ToString('N'))
$script:passed = 0
$script:caseNumber = 0
$families = @([Windows.Media.Fonts]::SystemFontFamilies | ForEach-Object { [string]$_.Source } | Sort-Object -Unique | Select-Object -First 2)
if ($families.Count -ne 2) { throw 'Two installed font families are required.' }
function Assert-True { param([bool]$Condition,[string]$Message) if (-not $Condition) { throw "FAIL: $Message" } }
function Invoke-Regression { param([string]$Name,[scriptblock]$Action) & $Action; $script:passed++; Write-Host "PASS [$script:passed] $Name" }
function Write-Text { param([string]$Path,[string]$Text) [IO.File]::WriteAllText($Path,$Text,[Text.UTF8Encoding]::new($false)) }
function Snapshot { param([string]$Folder) (@(Get-ChildItem -LiteralPath $Folder -Recurse -File | Sort-Object FullName | ForEach-Object { $_.FullName + ':' + (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash }) -join "`n") }
function Choose { param($Box,[string]$Value) $Box.SelectedItem = @($Box.Items | Where-Object { [string]$_.Tag -ceq $Value })[0] }
function Click { param($Button) $Button.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent)) }
function New-Fixture {
    $script:caseNumber++
    $caseRoot = Join-Path $root ('case-' + $script:caseNumber)
    $env:LOCALAPPDATA = Join-Path $caseRoot 'local-app-data'
    $themeRoot = Join-Path $env:LOCALAPPDATA 'Typezero\ThemeEngine\themes'
    $settings = Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json'
    foreach ($folder in @((Join-Path $themeRoot 'gruvbox'),(Join-Path $themeRoot 'nord'),(Split-Path -Parent $settings))) { [IO.Directory]::CreateDirectory($folder) | Out-Null }
    Write-Text (Join-Path $themeRoot 'gruvbox\theme.conf') "BG=#282828`nTEXT=#ebdbb2`nACCENT=#d79921`n"
    Write-Text (Join-Path $themeRoot 'nord\theme.conf') "BG=#2e3440`nTEXT=#d8dee9`nACCENT=#88c0d0`n"
    Write-Text (Join-Path (Split-Path -Parent $themeRoot) 'current-theme') 'gruvbox'
    $mapping = [ordered]@{ Version=2; Enabled=$false; ManualOverride=$null; Mappings=[ordered]@{
        gruvbox=[ordered]@{ family=$families[0]; size=14.25; weight='semi-bold' }
        nord=[ordered]@{ family=$families[1]; size=18; weight='normal' }
    } }
    $config = Join-Path (Split-Path -Parent $themeRoot) 'font-windows-terminal.json'
    Write-Text $config ($mapping | ConvertTo-Json -Depth 8)
    $terminal = [ordered]@{ profiles=[ordered]@{ defaults=[ordered]@{ font=[ordered]@{ face=$families[0]; size=15.25; weight='semi-bold' } }; list=@([ordered]@{guid='{574e775e-4f2a-5b96-ac1e-a2962a402336}';name='PowerShell 7';colorScheme='Keep Colors'}) } }
    Write-Text $settings ($terminal | ConvertTo-Json -Depth 8)
    $presets = Join-Path (Split-Path -Parent $themeRoot) 'custom-presets.json'
    Write-Text $presets ([ordered]@{ Version=1; Presets=@([ordered]@{ Name='fixture-custom'; Theme='nord'; Family=$families[0]; Size=17.5; Weight='semi-bold' }) } | ConvertTo-Json -Depth 8)
    [pscustomobject]@{ Root=$caseRoot; ThemesRoot=$themeRoot; Settings=$settings; Config=$config; Presets=$presets }
}
try {
    Invoke-Regression 'Theme changes retain saved full tuples and do not change files' {
        $f = New-Fixture
        $before = Snapshot $f.Root
        $observed = [Collections.Generic.List[object]]::new()
        $result = Show-TypezeroThemeFontPreview -ThemesRoot $f.ThemesRoot -PresetsPath $f.Presets -OnLoaded {
            param($window,$c)
            foreach ($id in @('gruvbox','nord','gruvbox')) {
                Choose $c.ThemeBox $id
                $observed.Add([pscustomobject]@{ Theme=[string]$c.ThemeBox.SelectedItem.Tag; Family=[string]$c.FontBox.SelectedItem.Tag; Size=[double]$c.SizeBox.SelectedItem.Tag; Weight=[string]$c.WeightBox.SelectedItem.Tag; Status=$c.StatusLabel.Text; CanApply=$c.ApplyFontButton.IsEnabled -and $c.UseButton.IsEnabled })
            }
        }
        Assert-True ($null -eq $result -and $observed.Count -eq 3) 'Visual preview produced an action.'
        for ($i=0; $i -lt 3; $i++) {
            $first = $i -ne 1
            Assert-True ($observed[$i].Family -ceq $families[$(if ($first) { 0 } else { 1 })] -and $observed[$i].Size -eq $(if ($first) {14.25} else {18}) -and $observed[$i].Weight -ceq $(if ($first) {'semi-bold'} else {'normal'}) -and $observed[$i].CanApply) ("Saved tuple/readiness differs: " + ($observed[$i] | ConvertTo-Json -Compress))
        }
        Assert-True ((Snapshot $f.Root) -ceq $before) 'Theme preview changed files.'
    }
    Invoke-Regression 'Preset load overrides the tuple loaded by its theme and Preview stays read-only' {
        $f = New-Fixture; $before = Snapshot $f.Root
        $seen = @{}
        $result = Show-TypezeroThemeFontPreview -ThemesRoot $f.ThemesRoot -PresetsPath $f.Presets -OnLoaded {
            param($window,$c)
            Choose $c.PresetBox 'fixture-custom'
            Click $c.PreviewButton
            $seen.Theme=[string]$c.ThemeBox.SelectedItem.Tag; $seen.Family=[string]$c.FontBox.SelectedItem.Tag
            $seen.Size=[double]$c.SizeBox.SelectedItem.Tag; $seen.Weight=[string]$c.WeightBox.SelectedItem.Tag
            $seen.Name=$c.PresetNameBox.Text; $seen.Tag=$window.Tag
        }
        Assert-True ($seen.Theme -ceq 'nord' -and $seen.Family -ceq $families[0] -and $seen.Size -eq 17.5 -and $seen.Weight -ceq 'semi-bold' -and $seen.Name -ceq 'fixture-custom' -and $null -eq $seen.Tag -and $null -eq $result) 'Preset tuple was reset by theme selection.'
        Assert-True ((Snapshot $f.Root) -ceq $before) 'Preset load/Preview changed files.'
    }
    Invoke-Regression 'Each action returns the visible choice without executing changes' {
        foreach ($button in @('ApplyFontButton','UseButton','SavePresetButton')) {
            $f=New-Fixture; $before=Snapshot $f.Root
            $result = Show-TypezeroThemeFontPreview -ThemesRoot $f.ThemesRoot -PresetsPath $f.Presets -OnLoaded {
                param($window,$c)
                Choose $c.PresetBox 'fixture-custom'
                $c.PresetNameBox.Text='new-fixture'
                Click $c[$button]
            }
            $action = switch ($button) { ApplyFontButton {'ApplyFont'} UseButton {'ApplyTheme'} SavePresetButton {'SavePreset'} }
            Assert-True ($result.Action -ceq $action -and $result.Theme -ceq 'nord' -and $result.Family -ceq $families[0] -and $result.Size -eq 17.5 -and $result.Weight -ceq 'semi-bold' -and $result.PresetName -ceq 'new-fixture' -and $result.PreviewOnly -and -not $result.SettingsChanged -and $result.ExpectedSha256 -match '\A[A-F0-9]{64}\z') 'Action intent or displayed tuple differs.'
            Assert-True ((Snapshot $f.Root) -ceq $before) 'An action button executed settings/preset changes inside the GUI.'
        }
    }
    Invoke-Regression 'Apply uses the displayed snapshot after an external settings edit' {
        foreach ($button in @('ApplyFontButton','UseButton')) {
            $f=New-Fixture; $expected=(Get-FileHash -LiteralPath $f.Settings -Algorithm SHA256).Hash
            $result = Show-TypezeroThemeFontPreview -ThemesRoot $f.ThemesRoot -PresetsPath $f.Presets -OnLoaded {
                param($window,$c)
                [IO.File]::AppendAllText($f.Settings,"`n// another process changed settings")
                Click $c[$button]
            }
            Assert-True ($result.ExpectedSha256 -ceq $expected -and (Get-FileHash -LiteralPath $f.Settings -Algorithm SHA256).Hash -cne $expected) 'Apply recaptured the changed settings snapshot.'
        }
    }
    Invoke-Regression 'Unreadable settings disable apply but allow visual preview and preset intent' {
        $f=New-Fixture
        Write-Text $f.Settings '{ invalid fixture settings'
        $before=Snapshot $f.Root
        $result = Show-TypezeroThemeFontPreview -ThemesRoot $f.ThemesRoot -PresetsPath $f.Presets -OnLoaded {
            param($window,$c)
            Assert-True (-not $c.ApplyFontButton.IsEnabled -and -not $c.UseButton.IsEnabled) 'Apply is enabled without a snapshot.'
            $c.PresetNameBox.Text='offline-preset'
            Assert-True $c.SavePresetButton.IsEnabled 'Save requires readable Terminal settings.'
            Click $c.SavePresetButton
        }
        Assert-True ($result.Action -ceq 'SavePreset' -and $result.PresetName -ceq 'offline-preset' -and $null -eq $result.ExpectedSha256) 'Offline Save intent differs.'
        Assert-True ((Snapshot $f.Root) -ceq $before) 'Offline Save executed changes.'
    }
    Invoke-Regression 'Invalid preset names disable Save and Cancel returns no intent' {
        $f=New-Fixture; $before=Snapshot $f.Root
        $result = Show-TypezeroThemeFontPreview -ThemesRoot $f.ThemesRoot -PresetsPath $f.Presets -OnLoaded {
            param($window,$c)
            foreach ($name in @('', 'BadName', '../escape', 'two words')) {
                $c.PresetNameBox.Text=$name
                Assert-True (-not $c.SavePresetButton.IsEnabled) 'Invalid preset name enabled Save.'
            }
            Click $c.CancelButton
        }
        Assert-True ($null -eq $result -and (Snapshot $f.Root) -ceq $before) 'Cancel changed files or produced intent.'
    }
    Invoke-Regression 'Unmapped themes initialize typography from the current Terminal profile' {
        $f=New-Fixture
        Write-Text $f.Config '{"Version":2,"Enabled":false,"ManualOverride":null,"Mappings":{}}'
        $seen=@{}
        $null = Show-TypezeroThemeFontPreview -ThemesRoot $f.ThemesRoot -PresetsPath $f.Presets -OnLoaded {
            param($window,$c)
            $seen.Family=[string]$c.FontBox.SelectedItem.Tag; $seen.Size=[double]$c.SizeBox.SelectedItem.Tag; $seen.Weight=[string]$c.WeightBox.SelectedItem.Tag
        }
        Assert-True ($seen.Family -ceq $families[0] -and $seen.Size -eq 15.25 -and $seen.Weight -ceq 'semi-bold') 'Terminal current tuple was not used.'
    }
    Invoke-Regression 'New fractional sizes use the typed value and invalid size cannot be saved' {
        $f=New-Fixture; $before=Snapshot $f.Root
        $result = Show-TypezeroThemeFontPreview -ThemesRoot $f.ThemesRoot -PresetsPath $f.Presets -OnLoaded {
            param($window,$c)
            $window.Measure([Windows.Size]::new(1100,790))
            $window.Arrange([Windows.Rect]::new(0,0,1100,790))
            $null=$c.SizeBox.ApplyTemplate()
            $edit=$c.SizeBox.Template.FindName('PART_EditableTextBox',$c.SizeBox)
            Assert-True ($null -ne $edit) 'Editable size template was not created.'
            $c.PresetNameBox.Text='typed-size'
            foreach ($bad in @('NaN','5.99','36.01','12.001','text')) {
                $edit.Text=$bad
                Assert-True (-not $c.ApplyFontButton.IsEnabled -and -not $c.UseButton.IsEnabled -and -not $c.SavePresetButton.IsEnabled) 'Invalid typed size enabled an action.'
                $c.PresetNameBox.Text='renamed-size'
                Assert-True (-not $c.SavePresetButton.IsEnabled) 'Name change enabled Save for an invalid tuple.'
            }
            $edit.Text='17.75'
            Assert-True ($c.ApplyFontButton.IsEnabled -and $c.UseButton.IsEnabled -and $c.SavePresetButton.IsEnabled) 'A new valid fractional size is unavailable.'
            Assert-True ([math]::Abs($window.FindName('PreviewText').FontSize - (17.75 * 96.0 / 72.0)) -lt 0.0001) 'Typing did not refresh the preview font size.'
            Click $c.ApplyFontButton
        }
        Assert-True ($result.Size -eq 17.75) 'Action used a selected dropdown size instead of the typed value.'
        Assert-True ((Snapshot $f.Root) -ceq $before) 'Typing a size changed files.'
    }
    Invoke-Regression 'Replacing an existing preset requires its explicit checkbox intent' {
        $f=New-Fixture; $before=Snapshot $f.Root
        $result = Show-TypezeroThemeFontPreview -ThemesRoot $f.ThemesRoot -PresetsPath $f.Presets -OnLoaded {
            param($window,$c)
            Choose $c.PresetBox 'fixture-custom'
            Assert-True (-not $c.SavePresetButton.IsEnabled -and $c.SaveHintLabel.Text -match 'exists') 'Existing preset Save did not require replacement consent.'
            $c.ReplacePresetBox.IsChecked=$true
            Assert-True $c.SavePresetButton.IsEnabled 'Explicit replacement did not enable Save.'
            $c.PresetNameBox.Text='another-name'
            Assert-True (-not $c.ReplacePresetBox.IsChecked -and $c.SavePresetButton.IsEnabled) 'Changing the name retained replacement intent.'
            $c.PresetNameBox.Text='fixture-custom'
            Assert-True (-not $c.SavePresetButton.IsEnabled) 'Changing back to an existing name bypassed replacement consent.'
            $c.ReplacePresetBox.IsChecked=$true
            Click $c.SavePresetButton
        }
        Assert-True ($result.Action -ceq 'SavePreset' -and $result.ReplacePreset -eq $true -and $result.PresetName -ceq 'fixture-custom') 'Replace checkbox did not return explicit Save intent.'
        Assert-True ((Snapshot $f.Root) -ceq $before) 'Replacement intent changed preset files inside the GUI.'
    }
    Invoke-Regression 'A preset with a missing base theme remains unready after renaming' {
        $f=New-Fixture
        $text=[IO.File]::ReadAllText($f.Presets).Replace('"nord"','"missing-theme"')
        Write-Text $f.Presets $text
        $before=Snapshot $f.Root
        $result = Show-TypezeroThemeFontPreview -ThemesRoot $f.ThemesRoot -PresetsPath $f.Presets -OnLoaded {
            param($window,$c)
            Choose $c.PresetBox 'fixture-custom'
            $c.PresetNameBox.Text='renamed-fixture'
            Assert-True (-not $c.SavePresetButton.IsEnabled -and -not $c.ApplyFontButton.IsEnabled -and -not $c.UseButton.IsEnabled) 'A missing base theme was accepted after renaming.'
        }
        Assert-True ($null -eq $result -and (Snapshot $f.Root) -ceq $before) 'Missing-theme preview changed files or returned intent.'
    }
    Write-Host "PASS: $script:passed/$script:passed GUI regression groups ($script:caseNumber disposable fixtures)."
    Write-Host "Fixture evidence retained: $root"
}
finally { if ($null -eq $originalLocalAppData) { Remove-Item Env:\LOCALAPPDATA -ErrorAction SilentlyContinue } else { $env:LOCALAPPDATA=$originalLocalAppData } }