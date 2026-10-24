# Named weight regressions: disposable LOCALAPPDATA, no native appearance apply.
# Run: pwsh -NoProfile -STA -File .\tests\Test-TypezeroFontWeights.ps1
[CmdletBinding()]
param([string]$FixtureParent = [IO.Path]::GetTempPath())
$ErrorActionPreference = 'Stop'
if ([Threading.Thread]::CurrentThread.ApartmentState -ne 'STA') { throw 'Run with pwsh -STA.' }
$source = Split-Path -Parent $PSScriptRoot
$originalLocalAppData = $env:LOCALAPPDATA
$root = Join-Path ([IO.Path]::GetFullPath($FixtureParent)) ('typezero-font-weights-' + [guid]::NewGuid().ToString('N'))
$script:passed = 0
function Assert-True { param([bool]$Value,[string]$Message) if (-not $Value) { throw "FAIL: $Message" } }
function Assert-Throws { param([scriptblock]$Action,[string]$Message) $thrown=$false; try { & $Action | Out-Null } catch { $thrown=$true }; Assert-True $thrown $Message }
function Case { param([string]$Name,[scriptblock]$Action) & $Action; $script:passed++; Write-Host "PASS [$script:passed] $Name" }
function Snapshot { param([string]$Path) (@(Get-ChildItem -LiteralPath $Path -Recurse -File | Sort-Object FullName | ForEach-Object { $_.FullName + ':' + (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash }) -join "`n") }
function Write-Text { param([string]$Path,[string]$Text) [IO.File]::WriteAllText($Path,$Text,[Text.UTF8Encoding]::new($false)) }
$expected = [ordered]@{'thin'=100;'extra-light'=200;'light'=300;'semi-light'=350;'normal'=400;'medium'=500;'semi-bold'=600;'bold'=700;'extra-bold'=800;'black'=900;'extra-black'=950}
try {
    $env:LOCALAPPDATA = Join-Path $root 'local-app-data'
    $themes = Join-Path $env:LOCALAPPDATA 'Typezero\ThemeEngine\themes'
    $settings = Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json'
    $presets = Join-Path $env:LOCALAPPDATA 'Typezero\ThemeEngine\custom-presets.json'
    $mapping = Join-Path $env:LOCALAPPDATA 'Typezero\ThemeEngine\font-windows-terminal.json'
    foreach ($path in @((Join-Path $themes 'fixture'),(Split-Path -Parent $settings))) { [IO.Directory]::CreateDirectory($path) | Out-Null }
    Write-Text (Join-Path $themes 'fixture\theme.conf') "THEME_ID=fixture`nTHEME_NAME=Fixture`nBG=#101010`nTEXT=#eeeeee`nACCENT=#88c0d0`n"
    Write-Text (Join-Path (Split-Path -Parent $themes) 'current-theme') 'fixture'
    Add-Type -AssemblyName PresentationFramework
    . (Join-Path $source 'TerminalFontControl-WindowsTerminal.ps1')
    . (Join-Path $source 'FontMapping-WindowsTerminal.ps1')
    . (Join-Path $source 'FontMappingV2-WindowsTerminal.ps1')
    . (Join-Path $source 'ThemeFontPreview-WindowsTerminal.ps1')
    $installed = @(Get-TypezeroInstalledFontFamilies)
    $family = @([Windows.Media.Fonts]::SystemFontFamilies | ForEach-Object {[string]$_.Source} | Where-Object { $_ -cin $installed } | Sort-Object -Unique)[0]
    Assert-True (-not [string]::IsNullOrWhiteSpace($family)) 'An installed family shared by GDI and WPF is required.'
    Write-Text $settings ([ordered]@{profiles=[ordered]@{defaults=[ordered]@{font=[ordered]@{face=$family;size=12;weight='normal'}};list=@([ordered]@{guid='{574e775e-4f2a-5b96-ac1e-a2962a402336}';name='PowerShell 7';colorScheme='Untouched'})};schemes=@([ordered]@{name='Untouched';background='#101010'})} | ConvertTo-Json -Depth 10)
    $themesBefore = Snapshot $themes
    Case 'All standard names map to their exact OpenType values' {
        $actual = Get-TypezeroTerminalFontWeights
        Assert-True ($actual.Count -eq $expected.Count) 'Unexpected weight count.'
        foreach ($weight in $expected.Keys) {
            $null = Assert-TypezeroTerminalFontChoice -Family $family -Size 13.25 -Weight $weight
            Assert-True ($actual[$weight] -eq $expected[$weight]) "Wrong OpenType weight for $weight."
            Assert-True ((ConvertTo-TypezeroWpfFontWeight $weight).ToOpenTypeWeight() -eq $expected[$weight]) "WPF lost $weight."
        }
    }
    Case 'Preview and font-only writer round-trip every name while preserving colors' {
        foreach ($weight in $expected.Keys) {
            $before = Snapshot $root
            $preview = Get-TypezeroTerminalFontPreview -Family $family -Size 13.25 -Weight $weight -ValidateInstalled
            Assert-True ($preview.Weight -ceq $weight -and $preview.PreviewOnly -and (Snapshot $root) -ceq $before) "Preview wrote files or lost $weight."
            $result = Set-TypezeroTerminalFontChoice -Family $family -Size 13.25 -Weight $weight -ExpectedSha256 $preview.ExpectedSha256 -ValidateInstalled -Confirm:$false
            $data = [IO.File]::ReadAllText($settings) | ConvertFrom-Json -AsHashtable
            Assert-True ($result.FontActivated -and $data.profiles.list[0].font.weight -ceq $weight -and $data.profiles.list[0].colorScheme -ceq 'Untouched' -and $data.schemes[0].background -ceq '#101010') "Writer lost $weight or changed colors."
        }
    }
    Case 'Custom presets and per-theme v2 mappings round-trip every named weight' {
        foreach ($weight in $expected.Keys) {
            $null = Save-TypezeroAppearancePreset -Name ('weight-' + $weight) -Theme fixture -Family $family -Size 14.5 -Weight $weight -Confirm:$false
            $saved = @(Get-TypezeroAppearancePresets | Where-Object Name -CEQ ('weight-' + $weight))
            Assert-True ($saved.Count -eq 1 -and $saved[0].Weight -ceq $weight) "Preset lost $weight."
            $null = Set-TypezeroWindowsFontMappingV2 -ThemeId fixture -FontFamily $family -Size 14.5 -Weight $weight -ThemesRoot $themes -ConfigPath $mapping -Confirm:$false
            Assert-True ((Get-TypezeroWindowsFontMappings -Path $mapping).Mappings.fixture.Weight -ceq $weight) "v2 mapping reader/writer disagree for $weight."
        }
        Assert-True ((Snapshot $themes) -ceq $themesBefore) 'Weight saves changed a base theme.'
    }
    Case 'Unsupported names and case variants fail before writes' {
        $before = Snapshot $root
        foreach ($weight in @('heavy','Medium','500','regular','semi bold')) {
            Assert-Throws { Set-TypezeroTerminalFontChoice -Family $family -Size 13 -Weight $weight -Confirm:$false } "Accepted $weight."
            Assert-Throws { Save-TypezeroAppearancePreset -Name invalid -Theme fixture -Family $family -Size 13 -Weight $weight -Confirm:$false } "Saved $weight."
        }
        Assert-True ((Snapshot $root) -ceq $before) 'Invalid weight wrote files.'
    }
    Case 'WPF dropdown, loaded preset and specimen represent every named weight including medium' {
        $before = Snapshot $root
        $seen = @{}
        $result = Show-TypezeroThemeFontPreview -ThemesRoot $themes -OnLoaded {
            param($window,$c)
            Assert-True ($c.WeightBox.Items.Count -eq $expected.Count) 'WPF dropdown is incomplete.'
            foreach ($weight in $expected.Keys) {
                $c.PresetBox.SelectedItem = @($c.PresetBox.Items | Where-Object { $_.Tag -ceq ('weight-' + $weight) })[0]
                $seen[$weight] = [string]$c.WeightBox.SelectedItem.Tag
                Assert-True ($window.FindName('PreviewText').FontWeight.ToOpenTypeWeight() -eq $expected[$weight]) "WPF specimen lost $weight."
            }
            $c.PresetBox.SelectedItem = @($c.PresetBox.Items | Where-Object { $_.Tag -ceq 'weight-medium' })[0]
            $c.ApplyFontButton.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent))
        }
        Assert-True ($seen.Count -eq $expected.Count -and $result.Weight -ceq 'medium') 'WPF action lost loaded medium.'
        Assert-True ((Snapshot $root) -ceq $before) 'WPF initialized preview changed files.'
    }
    Case 'Numeric Terminal weight 500 initializes medium in WPF and configure' {
        $data=[IO.File]::ReadAllText($settings)|ConvertFrom-Json -AsHashtable
        $data.profiles.list[0].font.weight=500
        Write-Text $settings ($data|ConvertTo-Json -Depth 10)
        Write-Text $mapping '{"Version":2,"Enabled":false,"ManualOverride":null,"Mappings":{}}'
        $before=Snapshot $root; $seen=@{}
        $result=Show-TypezeroThemeFontPreview -ThemesRoot $themes -OnLoaded {
            param($window,$c)
            $seen.Weight=[string]$c.WeightBox.SelectedItem.Tag
            $seen.OpenType=$window.FindName('PreviewText').FontWeight.ToOpenTypeWeight()
        }
        . (Join-Path $source 'Configure-WindowsTerminal.ps1')
        $configured=Invoke-TypezeroThemeConfigure -ThemesRoot $themes -ReadInput {'q'} -WriteOutput {param($Text)}
        Assert-True ($null -eq $result -and $seen.Weight -ceq 'medium' -and $seen.OpenType -eq 500 -and $configured.Weight -ceq 'medium') 'Numeric current weight was not represented as medium.'
        Assert-True ((Snapshot $root) -ceq $before) 'Current numeric weight initialization wrote files.'
    }
    Write-Host "All $script:passed named weight regression groups passed. Fixtures: $root"
}
finally {
    if ($null -eq $originalLocalAppData) { Remove-Item Env:\LOCALAPPDATA -ErrorAction SilentlyContinue } else { $env:LOCALAPPDATA = $originalLocalAppData }
}
