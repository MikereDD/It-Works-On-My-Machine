# Standalone offline regressions. All executable theme/provider code is a fixture.
# Run: pwsh -NoProfile -STA -File .\tests\Test-TypezeroThemeFontSelection.ps1
[CmdletBinding()]
param([string]$FixtureParent = [IO.Path]::GetTempPath())

$ErrorActionPreference = 'Stop'
$engineSource = Split-Path -Parent $PSScriptRoot
$source = Join-Path $engineSource 'ThemeFontSelection-WindowsTerminal.ps1'
$originalLocalAppData = $env:LOCALAPPDATA
$originalTemp = $env:TEMP
$root = Join-Path $FixtureParent (
    'typezero-selection-regression-' + [guid]::NewGuid().ToString('N')
)
$script:passed = 0
$script:caseNumber = 0
$script:fixtures = [Collections.Generic.List[object]]::new()

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "FAIL: $Message" }
}

function Assert-Throws {
    param([scriptblock]$Action, [string]$Message)
    $rejected = $false
    try { & $Action | Out-Null } catch { $rejected = $true }
    Assert-True $rejected $Message
}

function Invoke-Regression {
    param([string]$Name, [scriptblock]$Action)
    & $Action
    $script:passed++
    Write-Host "PASS [$script:passed] $Name"
}

function Write-FixtureText {
    param([string]$Path, [string]$Text)
    [IO.File]::WriteAllText($Path, $Text, [Text.UTF8Encoding]::new($false))
}

function New-Selection {
    param([hashtable]$Override = @{})
    $data = [ordered]@{
        Accepted = $true
        ThemeApplyConsent = $true
        SaveFontPreferenceConsent = $false
        Theme = 'gruvbox'
        Family = 'Fixture Font'
        Size = [double]14.25
        Weight = 'semi-bold'
        PreviewOnly = $true
        SettingsChanged = $false
    }
    foreach ($key in $Override.Keys) { $data[$key] = $Override[$key] }
    [pscustomobject]$data
}

function New-SelectionFixture {
    $script:caseNumber++
    $caseRoot = Join-Path $root ('case-' + $script:caseNumber)
    $localData = Join-Path $caseRoot 'local-app-data'
    $env:LOCALAPPDATA = $localData
    $fakeEngine = Join-Path $caseRoot 'fake engine with spaces'
    $themes = Join-Path $localData 'Typezero\ThemeEngine\themes'
    $terminal = Join-Path $localData 'Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json'
    $config = Join-Path $localData 'Typezero\ThemeEngine\font-windows-terminal.json'
    foreach ($folder in @($fakeEngine, (Join-Path $themes 'gruvbox'),
        (Join-Path $themes 'nord'), (Split-Path -Parent $terminal))) {
        New-Item -ItemType Directory -Path $folder -Force | Out-Null
    }
    Write-FixtureText (Join-Path $themes 'gruvbox\theme.conf') "BG=#101010`nTEXT=#eeeeee`n"
    Write-FixtureText (Join-Path $themes 'nord\theme.conf') "BG=#202020`nTEXT=#ffffff`n"
    Write-FixtureText $terminal "{`n  // fixture only; unrelated bytes must survive`n  `"fixture`": true`n}`n"
    $fakeEngineText = @'
[CmdletBinding()]
param([Parameter(Mandatory)][string]$Command,
      [Parameter(Mandatory)][string]$Theme)
$ErrorActionPreference = 'Stop'
$fontConfig = Get-TypezeroWindowsFontMappings
$entry = [ordered]@{
    Command = $Command
    Theme = $Theme
    BoundKeys = @($PSBoundParameters.Keys | Sort-Object)
    MappingAtApply = $fontConfig.Mappings[$Theme]
}
Add-Content -LiteralPath (Join-Path $PSScriptRoot 'apply-log.jsonl') -Value (
    $entry | ConvertTo-Json -Compress
) -Encoding utf8
[IO.File]::WriteAllText((Join-Path $PSScriptRoot 'appearance-applied.txt'), $Theme)
if (Test-Path -LiteralPath (Join-Path $PSScriptRoot 'throw-on-apply')) {
    throw 'Simulated failure after one appearance effect.'
}
if ($fontConfig.Mappings.ContainsKey($Theme) -and
    -not (Test-Path -LiteralPath (Join-Path $PSScriptRoot 'wrong-font-readback'))) {
    $mapped = $fontConfig.Mappings[$Theme]
    $font = if ($fontConfig.Version -eq 1) {
        [ordered]@{ Family = [string]$mapped; Size = 11; Weight = 'normal' }
    } else { $mapped }
    [IO.File]::WriteAllText((Join-Path $PSScriptRoot 'applied-font.json'), ($font | ConvertTo-Json))
}
if (Test-Path -LiteralPath (Join-Path $PSScriptRoot 'partial-on-apply')) {
    [pscustomobject]@{Status='Partial';Complete=$false;Changed=$true;AppearanceMayHaveChanged=$true;Targets=@(
        [pscustomobject]@{Target='Desktop';Status='Failed';Message='Fixture native activation failed'}
        [pscustomobject]@{Target='Font';Status='Applied';Message='Fixture font readback verified'}
    )}
}
'@
    Write-FixtureText (Join-Path $fakeEngine 'ThemeEngine.ps1') $fakeEngineText
    Write-FixtureText (Join-Path $fakeEngine 'FontProvider-WindowsTerminal.ps1') @'
function Get-TypezeroInstalledFontFamilies { @('Fixture Font', 'Cascadia Mono') }
function Get-TypezeroTerminalFontStatus {
    $path = Join-Path $PSScriptRoot 'applied-font.json'
    if (Test-Path -LiteralPath $path) {
        $font = [IO.File]::ReadAllText($path) | ConvertFrom-Json
        [pscustomobject]@{ Face = $font.Family; Size = $font.Size; Weight = $font.Weight; SettingsPath = 'fixture-only' }
    } else {
        [pscustomobject]@{ Face = 'Fixture Current Font'; Size = 11; Weight = 'normal'; SettingsPath = 'fixture-only' }
    }
}
'@
    foreach ($name in @('FontMapping-WindowsTerminal.ps1','FontMappingV2-WindowsTerminal.ps1','FontWeights-WindowsTerminal.ps1')) {
        Copy-Item -LiteralPath (Join-Path $engineSource $name) -Destination $fakeEngine
    }
    $fixture = [pscustomobject]@{
        Root = $caseRoot
        EngineRoot = $fakeEngine
        ThemesRoot = $themes
        ConfigPath = $config
        TerminalPath = $terminal
        TerminalHash = (Get-FileHash -LiteralPath $terminal -Algorithm SHA256).Hash
        LogPath = Join-Path $fakeEngine 'apply-log.jsonl'
    }
    $script:fixtures.Add($fixture)
    $fixture
}

function Get-FixtureSnapshot {
    param($Fixture)
    $entries = @(Get-ChildItem -LiteralPath $Fixture.Root -Recurse | Sort-Object FullName)
    (@($entries | ForEach-Object {
        if ($_.PSIsContainer) { 'D:' + $_.FullName }
        else { 'F:' + $_.FullName + ':' + (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash }
    }) -join "`n")
}

function Invoke-FixtureSelection {
    param($Fixture, [AllowNull()][object]$Selection, [switch]$WhatIf)
    Invoke-TypezeroThemeFontSelection -Selection $Selection `
        -EngineRoot $Fixture.EngineRoot -ThemesRoot $Fixture.ThemesRoot `
        -ConfigPath $Fixture.ConfigPath -WhatIf:$WhatIf -Confirm:$false
}

function Assert-NoEffects {
    param($Fixture, [string]$Before)
    Assert-True ((Get-FixtureSnapshot $Fixture) -ceq $Before) 'Refused selection changed fixture files.'
}

function Assert-OneApply {
    param($Fixture)
    $log = @(Get-Content -LiteralPath $Fixture.LogPath | ForEach-Object { $_ | ConvertFrom-Json })
    Assert-True ($log.Count -eq 1) 'Expected exactly one existing theme apply invocation.'
    Assert-True ($log[0].Command -ceq 'apply' -and $log[0].Theme -ceq 'gruvbox') 'Theme apply arguments differ.'
    Assert-True (($log[0].BoundKeys -join ',') -ceq 'Command,Theme') 'Unexpected apply/recovery/bypass arguments.'
}

function Assert-NoActivation {
    param($Result)
    Assert-True ($Result.FontActivated -is [bool] -and -not $Result.FontActivated) 'Result claims live font activation.'
}

function Assert-Activation {
    param($Result)
    Assert-True ($Result.FontActivated -is [bool] -and $Result.FontActivated) $Result.Message
}

function Write-V1Config {
    param($Fixture, [bool]$Enabled)
    Write-FixtureText $Fixture.ConfigPath (([ordered]@{
        Version = 1
        Enabled = $Enabled
        Mappings = [ordered]@{ gruvbox = 'Cascadia Mono'; nord = 'Fixture Current Font' }
    } | ConvertTo-Json -Depth 10) + "`n")
}

try {
    New-Item -ItemType Directory -Path $root -Force | Out-Null
    $env:TEMP = Join-Path $root 'temp'
    New-Item -ItemType Directory -Path $env:TEMP -Force | Out-Null
    # Dot-source only the side-effect-free selection helper, never the real engine.
    . $source
    . (Join-Path $engineSource 'FontMapping-WindowsTerminal.ps1')

    Invoke-Regression 'Null/cancelled selections and refused theme consent make no changes' {
        foreach ($selection in @($null, (New-Selection @{ Accepted = $false }),
            (New-Selection @{ ThemeApplyConsent = $false; SaveFontPreferenceConsent = $true }))) {
            $fixture = New-SelectionFixture
            $before = Get-FixtureSnapshot $fixture
            $result = Invoke-FixtureSelection $fixture $selection
            Assert-True ($result.Status -ceq 'Cancelled' -and -not $result.ThemeApplied -and
                -not $result.ThemeMayHaveChanged -and -not $result.FontPreferenceSaved) 'Cancelled result is inaccurate.'
            Assert-NoActivation $result
            Assert-NoEffects $fixture $before
        }
    }

    Invoke-Regression 'Every consent must be a present Boolean, including optional preference consent' {
        foreach ($field in @('Accepted','ThemeApplyConsent','SaveFontPreferenceConsent')) {
            foreach ($bad in @('missing', 'string', 'null', 'number')) {
                $fixture = New-SelectionFixture
                $selection = New-Selection
                switch ($bad) {
                    'missing' { $selection.PSObject.Properties.Remove($field) }
                    'string' { $selection.$field = 'true' }
                    'null' { $selection.$field = $null }
                    'number' { $selection.$field = 1 }
                }
                $before = Get-FixtureSnapshot $fixture
                Assert-Throws { Invoke-FixtureSelection $fixture $selection } "Accepted malformed $field ($bad)."
                Assert-NoEffects $fixture $before
            }
        }
    }

    Invoke-Regression 'WhatIf creates no apply, configuration, lock, backup, or directory' {
        foreach ($existingPreference in @($false, $true)) {
            $fixture = New-SelectionFixture
            if ($existingPreference) { Write-V1Config $fixture $false }
            $before = Get-FixtureSnapshot $fixture
            $result = Invoke-FixtureSelection $fixture (New-Selection @{ SaveFontPreferenceConsent = $true }) -WhatIf
            Assert-True ($result.Status -ceq 'NotExecuted' -and -not $result.ThemeMayHaveChanged -and
                -not $result.ThemeApplied -and -not $result.FontPreferenceSaved) 'WhatIf outcome is inaccurate.'
            Assert-NoActivation $result
            Assert-NoEffects $fixture $before
        }
    }

    Invoke-Regression 'Theme-only selection invokes the public apply command and creates no preference' {
        $fixture = New-SelectionFixture
        $result = Invoke-FixtureSelection $fixture (New-Selection)
        Assert-OneApply $fixture
        Assert-True ($result.Status -ceq 'ThemeApplied' -and $result.ThemeApplied -and
            $result.ThemeMayHaveChanged -and -not $result.FontPreferenceSaved) 'Theme-only outcome is inaccurate.'
        Assert-True (-not (Test-Path -LiteralPath $fixture.ConfigPath) -and
            -not (Test-Path -LiteralPath "$($fixture.ConfigPath).lock")) 'Theme-only use created font configuration.'
        Assert-True ($result.Message -match 'No saved font') 'Theme-only message claims an unsaved font change.'
        Assert-NoActivation $result
    }

    Invoke-Regression 'Theme-only selection preserves existing preference bytes and Enabled state' {
        $fixture = New-SelectionFixture
        Write-V1Config $fixture $true
        $before = (Get-FileHash -LiteralPath $fixture.ConfigPath -Algorithm SHA256).Hash
        $result = Invoke-FixtureSelection $fixture (New-Selection)
        Assert-OneApply $fixture
        Assert-True ((Get-FileHash -LiteralPath $fixture.ConfigPath -Algorithm SHA256).Hash -ceq $before) 'Unchecked preference option changed existing mapping.'
        Assert-True (@(Get-ChildItem -LiteralPath (Split-Path -Parent $fixture.ConfigPath) -Filter '*.bak' -File).Count -eq 0) 'Theme-only use backed up/changed configuration.'
        Assert-Activation $result
    }

    Invoke-Regression 'Explicit preference consent saves before apply and verifies the selected tuple' {
        $fixture = New-SelectionFixture
        $result = Invoke-FixtureSelection $fixture (New-Selection @{ SaveFontPreferenceConsent = $true })
        Assert-OneApply $fixture
        Assert-True ($result.FontPreferenceSaved) ("Preference was not saved: " + $result.Message)
        $config = Get-Content -LiteralPath $fixture.ConfigPath -Raw | ConvertFrom-Json
        Assert-True ($result.Status -ceq 'ThemeAppliedPreferenceSaved' -and $result.ThemeApplied -and
            $result.FontPreferenceSaved) 'Preference creation was not reported accurately.'
        Assert-True ($config.Version -eq 2 -and $config.Enabled -is [bool] -and -not $config.Enabled -and
            $null -eq $config.ManualOverride -and $config.Mappings.gruvbox.family -ceq 'Fixture Font' -and
            $config.Mappings.gruvbox.size -eq 14.25 -and $config.Mappings.gruvbox.weight -ceq 'semi-bold') 'Created V2 mapping differs from selected preference.'
        $log = Get-Content -LiteralPath $fixture.LogPath -Raw | ConvertFrom-Json
        Assert-True ($log.MappingAtApply.Family -ceq 'Fixture Font' -and $log.MappingAtApply.Size -eq 14.25 -and
            $log.MappingAtApply.Weight -ceq 'semi-bold') 'Public apply did not see the newly saved tuple.'
        Assert-True ($result.Message -match 'font verified') 'Saved mapping lacks actual font verification.'
        Assert-Activation $result
    }

    Invoke-Regression 'V1 migration preserves both Enabled values, other mappings, and exact original backups' {
        foreach ($enabled in @($false, $true)) {
            $fixture = New-SelectionFixture
            Write-V1Config $fixture $enabled
            $before = (Get-FileHash -LiteralPath $fixture.ConfigPath -Algorithm SHA256).Hash
            $result = Invoke-FixtureSelection $fixture (New-Selection @{ SaveFontPreferenceConsent = $true })
            Assert-OneApply $fixture
            $config = Get-Content -LiteralPath $fixture.ConfigPath -Raw | ConvertFrom-Json
            Assert-True ($result.FontPreferenceSaved -and $config.Version -eq 2 -and $config.Enabled -eq $enabled) 'Migration enabled/disabled font integration.'
            Assert-True ($config.Mappings.gruvbox.family -ceq 'Fixture Font' -and
                $config.Mappings.gruvbox.size -eq 14.25 -and $config.Mappings.gruvbox.weight -ceq 'semi-bold' -and
                $config.Mappings.nord.family -ceq 'Fixture Current Font' -and
                $config.Mappings.nord.size -eq 12 -and $config.Mappings.nord.weight -ceq 'normal') 'Migration changed another mapping or lost the selected typography.'
            $backups = @(Get-ChildItem -LiteralPath (Split-Path -Parent $fixture.ConfigPath) -Filter '*.bak' -File)
            Assert-True ($backups.Count -eq 1 -and
                (Get-FileHash -LiteralPath $backups[0].FullName -Algorithm SHA256).Hash -ceq $before) 'Migration did not preserve an exact original backup.'
            Assert-Activation $result
        }
    }

    Invoke-Regression 'Existing V2 preference update preserves unrelated typography and Enabled' {
        $fixture = New-SelectionFixture
        Write-FixtureText $fixture.ConfigPath @'
{"Version":2,"Enabled":true,"ManualOverride":null,"Mappings":{"gruvbox":{"family":"Cascadia Mono","size":12,"weight":"normal"},"nord":{"family":"Cascadia Mono","size":16.5,"weight":"semi-bold"}}}
'@
        $before = (Get-FileHash -LiteralPath $fixture.ConfigPath -Algorithm SHA256).Hash
        $result = Invoke-FixtureSelection $fixture (New-Selection @{ SaveFontPreferenceConsent = $true })
        $config = Get-Content -LiteralPath $fixture.ConfigPath -Raw | ConvertFrom-Json
        Assert-True ($result.FontPreferenceSaved -and $config.Enabled -eq $true -and
            $config.Mappings.nord.family -ceq 'Cascadia Mono' -and $config.Mappings.nord.size -eq 16.5 -and
            $config.Mappings.nord.weight -ceq 'semi-bold') 'V2 update changed an unrelated preference/integration flag.'
        $backups = @(Get-ChildItem -LiteralPath (Split-Path -Parent $fixture.ConfigPath) -Filter '*.bak' -File)
        Assert-True ($backups.Count -eq 1 -and
            (Get-FileHash -LiteralPath $backups[0].FullName -Algorithm SHA256).Hash -ceq $before) 'V2 update backup differs from the original.'
        Assert-Activation $result
    }

    Invoke-Regression 'Theme failure reports possible partial appearance and retains the already saved mapping' {
        $fixture = New-SelectionFixture
        Write-V1Config $fixture $false
        $before = (Get-FileHash -LiteralPath $fixture.ConfigPath -Algorithm SHA256).Hash
        Write-FixtureText (Join-Path $fixture.EngineRoot 'throw-on-apply') 'fail after effect'
        $result = Invoke-FixtureSelection $fixture (New-Selection @{ SaveFontPreferenceConsent = $true })
        Assert-OneApply $fixture
        Assert-True ($result.Status -ceq 'ThemeFailed' -and -not $result.ThemeApplied -and
            $result.ThemeMayHaveChanged -and $result.FontPreferenceSaved -and
            $result.Message -match 'may be partial' -and $result.Message -match 'font preference was saved') 'Partial theme failure was reported as success or as unchanged.'
        Assert-True ((Get-FileHash -LiteralPath $fixture.ConfigPath -Algorithm SHA256).Hash -cne $before -and
            (Get-TypezeroWindowsFontMappings -Path $fixture.ConfigPath).Mappings.gruvbox.Family -ceq 'Fixture Font') 'The mapping was not saved before theme application.'
        Assert-NoActivation $result
    }

    Invoke-Regression 'Structured partial apply preserves successful targets without claiming full application' {
        foreach ($save in @($false,$true)) {
            $fixture = New-SelectionFixture
            Write-V1Config $fixture $false
            Write-FixtureText (Join-Path $fixture.EngineRoot 'partial-on-apply') 'partial result'
            $result = Invoke-FixtureSelection $fixture (New-Selection @{SaveFontPreferenceConsent=$save})
            Assert-OneApply $fixture
            Assert-True ($result.Status -ceq 'Partial' -and -not $result.ThemeApplied -and
                $result.ThemeMayHaveChanged -and $result.FontActivated -and
                $result.FontPreferenceSaved -eq $save -and $result.Targets.Count -eq 2 -and
                $result.Message -match 'Desktop: Failed' -and $result.Message -match 'full theme was not recorded') 'Partial result was concealed or lost successful targets.'
        }
    }

    Invoke-Regression 'Preference failure prevents apply and preserves exact damaged configuration' {
        $fixture = New-SelectionFixture
        Write-FixtureText $fixture.ConfigPath '{ invalid json; preserve for investigation'
        $before = (Get-FileHash -LiteralPath $fixture.ConfigPath -Algorithm SHA256).Hash
        $result = Invoke-FixtureSelection $fixture (New-Selection @{ SaveFontPreferenceConsent = $true })
        Assert-True (-not (Test-Path -LiteralPath $fixture.LogPath)) 'Invalid preference still invoked theme application.'
        Assert-True ($result.Status -ceq 'PreferenceFailed' -and -not $result.ThemeApplied -and
            -not $result.ThemeMayHaveChanged -and -not $result.FontPreferenceSaved -and
            $result.Message -match 'theme was not applied') 'Preference failure incorrectly reports theme application.'
        Assert-True ((Get-FileHash -LiteralPath $fixture.ConfigPath -Algorithm SHA256).Hash -ceq $before) 'Preference failure replaced damaged configuration.'
        Assert-NoActivation $result
    }

    Invoke-Regression 'Provider rejection cannot save an unrecognized font' {
        $fixture = New-SelectionFixture
        $result = Invoke-FixtureSelection $fixture (New-Selection @{
            SaveFontPreferenceConsent = $true; Family = 'Unknown Fixture Font'
        })
        Assert-True (-not (Test-Path -LiteralPath $fixture.LogPath)) 'Provider rejection still invoked theme application.'
        Assert-True ($result.Status -ceq 'PreferenceFailed' -and -not $result.ThemeApplied -and
            -not $result.FontPreferenceSaved -and -not (Test-Path -LiteralPath $fixture.ConfigPath)) 'Unrecognized font was saved.'
        Assert-NoActivation $result
    }

    Invoke-Regression 'Existing font ownership comment does not block public apply or attempt recovery' {
        foreach ($save in @($false, $true)) {
            $fixture = New-SelectionFixture
            Write-V1Config $fixture $false
            Write-FixtureText $fixture.TerminalPath "{`n /* TYPEZERO_FONT_V2 */`n `"unrelated`": [1,2,3]`n}`n"
            $fixture.TerminalHash = (Get-FileHash -LiteralPath $fixture.TerminalPath -Algorithm SHA256).Hash
            $result = Invoke-FixtureSelection $fixture (New-Selection @{ SaveFontPreferenceConsent = $save })
            Assert-OneApply $fixture
            Assert-True ($result.ThemeApplied -and $result.FontPreferenceSaved -eq $save) 'A preserved font comment blocked the public apply path.'
            Assert-Activation $result
        }
    }

    Invoke-Regression 'Two saved themes select distinct full font tuples without rewriting their mappings' {
        $fixture = New-SelectionFixture
        Write-FixtureText $fixture.ConfigPath '{"Version":2,"Enabled":false,"ManualOverride":null,"Mappings":{"gruvbox":{"family":"Fixture Font","size":14.25,"weight":"semi-bold"},"nord":{"family":"Cascadia Mono","size":18,"weight":"normal"}}}'
        $before = (Get-FileHash -LiteralPath $fixture.ConfigPath -Algorithm SHA256).Hash
        foreach ($id in @('gruvbox','nord')) {
            $result = Invoke-FixtureSelection $fixture (New-Selection @{ Theme = $id })
            Assert-Activation $result
            $mapped = (Get-TypezeroWindowsFontMappings -Path $fixture.ConfigPath).Mappings[$id]
            $actual = Get-Content -LiteralPath (Join-Path $fixture.EngineRoot 'applied-font.json') -Raw | ConvertFrom-Json
            Assert-True ($actual.Family -ceq $mapped.Family -and $actual.Size -eq $mapped.Size -and
                $actual.Weight -ceq $mapped.Weight) 'The selected theme did not resolve its complete saved tuple.'
        }
        Assert-True ((Get-FileHash -LiteralPath $fixture.ConfigPath -Algorithm SHA256).Hash -ceq $before) 'Unchecked preference save rewrote mappings.'
    }

    Invoke-Regression 'Failed font readback reports the limitation without claiming activation' {
        $fixture = New-SelectionFixture
        Write-FixtureText (Join-Path $fixture.EngineRoot 'wrong-font-readback') 'fixture readback mismatch'
        $result = Invoke-FixtureSelection $fixture (New-Selection @{ SaveFontPreferenceConsent = $true })
        Assert-OneApply $fixture
        Assert-True ($result.Status -ceq 'ThemeAppliedFontUnverified' -and $result.ThemeApplied -and
            $result.FontPreferenceSaved -and -not $result.FontActivated) 'Wrong font readback was reported as activation.'
    }

    Invoke-Regression 'Malformed font sizes, IDs, weights, and preview flags fail before every write' {
        $invalid = @(
            @{ Size = [double]::NaN }, @{ Size = [double]::PositiveInfinity },
            @{ Size = [double]::NegativeInfinity }, @{ Size = '14' },
            @{ Size = $null }, @{ Size = $true }, @{ Size = 5.99 },
            @{ Size = 36.01 }, @{ Size = 12.001 },
            @{ Theme = '../gruvbox' }, @{ Theme = 'Gruvbox' },
            @{ Theme = "gruvbox`n" }, @{ Theme = 'not-installed' },
            @{ Theme = 'gruvbox;anything' }, @{ Theme = '' },
            @{ Family = ' Fixture Font' }, @{ Family = '' },
            @{ Weight = 'Normal' }, @{ Weight = 'heavy' },
            @{ PreviewOnly = $false }, @{ PreviewOnly = 'true' },
            @{ SettingsChanged = $true }, @{ SettingsChanged = 'false' }
        )
        foreach ($override in $invalid) {
            $fixture = New-SelectionFixture
            $selection = New-Selection $override
            $before = Get-FixtureSnapshot $fixture
            Assert-Throws { Invoke-FixtureSelection $fixture $selection } ('Invalid selection was accepted: ' + ($override | ConvertTo-Json -Compress))
            Assert-NoEffects $fixture $before
        }
        foreach ($field in @('Theme','Family','Size','Weight','PreviewOnly','SettingsChanged')) {
            $fixture = New-SelectionFixture
            $selection = New-Selection
            $selection.PSObject.Properties.Remove($field)
            $before = Get-FixtureSnapshot $fixture
            Assert-Throws { Invoke-FixtureSelection $fixture $selection } "Missing $field was accepted."
            Assert-NoEffects $fixture $before
        }
    }

    Invoke-Regression 'A theme root different from the public apply installation is refused' {
        $fixture = New-SelectionFixture
        $otherRoot = Join-Path $fixture.Root 'other-themes'
        New-Item -ItemType Directory -Path (Join-Path $otherRoot 'gruvbox') -Force | Out-Null
        Write-FixtureText (Join-Path $otherRoot 'gruvbox\theme.conf') 'BG=#000000'
        $before = Get-FixtureSnapshot $fixture
        Assert-Throws {
            Invoke-TypezeroThemeFontSelection -Selection (New-Selection) -EngineRoot $fixture.EngineRoot `
                -ThemesRoot $otherRoot -ConfigPath $fixture.ConfigPath -Confirm:$false
        } 'A custom validation tree was accepted even though public apply would read another installation.'
        Assert-NoEffects $fixture $before
        Assert-Throws {
            Invoke-TypezeroThemeFontSelection -Selection (New-Selection) -EngineRoot $fixture.EngineRoot `
                -ThemesRoot $fixture.ThemesRoot -ConfigPath (Join-Path $fixture.Root 'other-fonts.json') -Confirm:$false
        } 'A custom configuration was accepted even though public apply reads another path.'
        Assert-NoEffects $fixture $before
    }

    Invoke-Regression 'Source parses and the WPF preview loads saved typography before explicit application' {
        foreach ($file in @($source, (Join-Path $engineSource 'ThemeFontPreview-WindowsTerminal.ps1'),
            (Join-Path $engineSource 'ThemeEngine.ps1'))) {
            $parseTokens = $null
            $parseErrors = $null
            $null = [Management.Automation.Language.Parser]::ParseFile($file, [ref]$parseTokens, [ref]$parseErrors)
            Assert-True (@($parseErrors).Count -eq 0) "PowerShell syntax errors in $file."
        }
        $ui = [IO.File]::ReadAllText((Join-Path $engineSource 'ThemeFontPreview-WindowsTerminal.ps1'))
        $match = [regex]::Match($ui, '(?s)\$xaml\s*=\s*@''\r?\n(?<xml>.*?)\r?\n''@')
        Assert-True $match.Success 'Preview XAML could not be located without executing the preview.'
        $xml = [xml]$match.Groups['xml'].Value
        Assert-True ($null -eq $xml.SelectSingleNode('//*[@Name="SaveFontPreferenceBox"]')) 'Preview still couples saving a mapping with applying a theme.'
        foreach ($label in @('Preview','Apply Font','Save Preset')) {
            Assert-True ($null -ne $xml.SelectSingleNode("//*[local-name()='Button' and @Content='$label']")) "Explicit action button missing: $label"
        }
        Assert-True ($ui -notmatch 'Live Terminal font activation remains disabled' -and
            $ui -match 'Get-TypezeroWindowsFontMappings' -and
            $ui -match '\$themeBox\.Add_SelectionChanged\(\{ & \$loadSavedFont \}' -and
            $ui -match '\$points = \[double\]\$mapped.Size' -and
            $ui -match 'PreviewOnly\s*=\s*\$true' -and $ui -match 'SettingsChanged\s*=\s*\$false') 'Preview omits read-only/effect boundaries.'
        if ([Threading.Thread]::CurrentThread.ApartmentState -eq 'STA') {
            Add-Type -AssemblyName PresentationFramework
            $window = [Windows.Markup.XamlReader]::Parse($match.Groups['xml'].Value)
            try {
                Assert-True ($null -ne $window.Content) 'Loaded WPF has no preview content.'
                Assert-True ($null -eq $window.FindName('SaveFontPreferenceBox')) 'Loaded WPF still combines saving and activation.'
            }
            finally { $window.Close() }
        } else {
            Write-Host 'NOTE: XML/static checks passed; run with -STA to additionally load the WPF window without displaying it.'
        }
    }

    Invoke-Regression 'Selection uses public apply without a second font writer or recovery operation' {
        $realEngine = [IO.File]::ReadAllText((Join-Path $engineSource 'ThemeEngine.ps1'))
        Assert-True ($realEngine -match '(?s)if\s*\(\$WallpaperArgs\.Count\s+-ne\s+2\s+-or\s+\$WallpaperArgs\[1\]\s+-cne\s+''--fixture''\)\s*\{\s*throw\s+''LIVE FONT APPLY DISABLED\.') 'Live font apply guard was removed or weakened.'
        Assert-True ($realEngine -match '(?s)if\s*\(\$WallpaperArgs\.Count\s+-ne\s+2\s+-or\s+\$WallpaperArgs\[0\]\s+-cne\s+''--fixture''\)\s*\{\s*throw\s+''LIVE FONT RESTORE DISABLED\.') 'Live font restore guard was removed or weakened.'
        $tokens = $null
        $errors = $null
        $ast = [Management.Automation.Language.Parser]::ParseFile($source, [ref]$tokens, [ref]$errors)
        $commands = @($ast.FindAll({ param($node) $node -is [Management.Automation.Language.CommandAst] }, $true))
        foreach ($command in $commands) {
            $name = $command.GetCommandName()
            Assert-True ($name -notmatch '(?i)(Restore|Recover|Activat|FontSwitch|Integration|Candidate|SettingsChange)') "Selection invokes a second writer/recovery command: $name"
        }
    }

    Invoke-Regression 'WPF theme changes load each saved tuple, including fractional size, without displaying or writing' {
        if ([Threading.Thread]::CurrentThread.ApartmentState -ne 'STA') {
            throw 'Run this offline preview test with pwsh -STA.'
        }
        $fixture = New-SelectionFixture
        Add-Type -AssemblyName PresentationFramework
        $families = @([Windows.Media.Fonts]::SystemFontFamilies | ForEach-Object { [string]$_.Source } | Sort-Object -Unique | Select-Object -First 2)
        Assert-True ($families.Count -eq 2) 'Two installed fonts are needed for the preview fixture.'
        $mapping = [ordered]@{
            Version = 2; Enabled = $false; ManualOverride = $null
            Mappings = [ordered]@{
                gruvbox = [ordered]@{ family = $families[0]; size = 14.25; weight = 'semi-bold' }
                nord = [ordered]@{ family = $families[1]; size = 18; weight = 'normal' }
            }
        }
        Write-FixtureText $fixture.ConfigPath ($mapping | ConvertTo-Json -Depth 10)
        $previewSource = [IO.File]::ReadAllText((Join-Path $engineSource 'ThemeFontPreview-WindowsTerminal.ps1'))
        # Replace only the modal display in a disposable copy. All real preview
        # setup and theme selection handlers run; the window is never shown.
        $observe = @'
    $observed = [Collections.Generic.List[object]]::new()
    foreach ($themeId in @('gruvbox','nord')) {
        $themeBox.SelectedItem = & $getChoice $themeBox $themeId
        $observed.Add([pscustomobject]@{
            Theme = [string]$themeBox.SelectedItem.Tag
            Family = [string]$fontBox.SelectedItem.Tag
            Size = [string]$sizeBox.SelectedItem.Tag
            Weight = [string]$weightBox.SelectedItem.Tag
            CanUse = ($null -ne $fontBox.SelectedItem -and $null -ne $sizeBox.SelectedItem -and $null -ne $weightBox.SelectedItem)
        })
    }
    $window.Tag = $observed.ToArray()
    $window.Close()
'@
        Assert-True ($previewSource.Contains('    $null = $window.ShowDialog()')) 'Modal display hook not found.'
        $previewSource = $previewSource.Replace('    $null = $window.ShowDialog()', $observe)
        $previewPath = Join-Path $fixture.EngineRoot 'ThemeFontPreview-WindowsTerminal.ps1'
        Write-FixtureText $previewPath $previewSource
        foreach ($dependency in @('AppearanceSelection-WindowsTerminal.ps1','TerminalFontControl-WindowsTerminal.ps1','TerminalSettings-WindowsTerminal.ps1','FontProvider-WindowsTerminal.ps1','FontWeights-WindowsTerminal.ps1')) {
            Copy-Item -LiteralPath (Join-Path $engineSource $dependency) -Destination (Join-Path $fixture.EngineRoot $dependency)
        }
        $before = Get-FixtureSnapshot $fixture
        . $previewPath
        $observed = @(Show-TypezeroThemeFontPreview -ThemesRoot $fixture.ThemesRoot)
        Assert-True ($observed.Count -eq 2) 'Expected two preview theme observations.'
        for ($i = 0; $i -lt 2; $i++) {
            $id = @('gruvbox','nord')[$i]
            $expected = $mapping.Mappings[$id]
            Assert-True ($observed[$i].Theme -ceq $id -and $observed[$i].Family -ceq $expected.family -and
                [double]$observed[$i].Size -eq $expected.size -and $observed[$i].Weight -ceq $expected.weight -and
                $observed[$i].CanUse) 'The WPF preview did not load the selected theme font tuple.'
        }
        Assert-NoEffects $fixture $before
    }

    Invoke-Regression 'Every Terminal fixture remains byte-identical after all workflow tests' {
        foreach ($fixture in $script:fixtures) {
            Assert-True ((Get-FileHash -LiteralPath $fixture.TerminalPath -Algorithm SHA256).Hash -ceq $fixture.TerminalHash) "Terminal fixture changed: $($fixture.TerminalPath)"
        }
    }
    Write-Host "PASS: $script:passed/$script:passed safe selection regression groups ($script:caseNumber isolated fixtures)."
    Write-Host "Fixture evidence retained: $root"
}
finally {
    if ($null -eq $originalLocalAppData) { Remove-Item Env:\LOCALAPPDATA -ErrorAction SilentlyContinue }
    else { $env:LOCALAPPDATA = $originalLocalAppData }
    if ($null -eq $originalTemp) { Remove-Item Env:\TEMP -ErrorAction SilentlyContinue }
    else { $env:TEMP = $originalTemp }
}
