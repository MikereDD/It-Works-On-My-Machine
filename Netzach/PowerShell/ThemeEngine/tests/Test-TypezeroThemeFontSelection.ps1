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
$entry = [ordered]@{
    Command = $Command
    Theme = $Theme
    BoundKeys = @($PSBoundParameters.Keys | Sort-Object)
}
Add-Content -LiteralPath (Join-Path $PSScriptRoot 'apply-log.jsonl') -Value (
    $entry | ConvertTo-Json -Compress
) -Encoding utf8
[IO.File]::WriteAllText((Join-Path $PSScriptRoot 'appearance-applied.txt'), $Theme)
if (Test-Path -LiteralPath (Join-Path $PSScriptRoot 'throw-on-apply')) {
    throw 'Simulated failure after one appearance effect.'
}
'@
    Write-FixtureText (Join-Path $fakeEngine 'ThemeEngine.ps1') $fakeEngineText
    Write-FixtureText (Join-Path $fakeEngine 'FontProvider-WindowsTerminal.ps1') @'
function Get-TypezeroInstalledFontFamilies { @('Fixture Font', 'Cascadia Mono') }
function Get-TypezeroTerminalFontStatus {
    [pscustomobject]@{ Face = 'Fixture Current Font'; SettingsPath = 'fixture-only' }
}
'@
    foreach ($name in @('FontMapping-WindowsTerminal.ps1','FontMappingV2-WindowsTerminal.ps1')) {
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
        Assert-True ($result.Message -match 'Live Terminal font activation remains disabled') 'Theme-only message omits the font limitation.'
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
        Assert-NoActivation $result
    }

    Invoke-Regression 'Explicit preference consent creates verified V2 defaults without live activation' {
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
        Assert-True ($result.Message -match 'does not activate the font') 'Saved mapping message implies live activation.'
        Assert-NoActivation $result
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
            Assert-NoActivation $result
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
        Assert-NoActivation $result
    }

    Invoke-Regression 'Theme failure reports possible partial appearance change and skips mapping' {
        $fixture = New-SelectionFixture
        Write-V1Config $fixture $false
        $before = (Get-FileHash -LiteralPath $fixture.ConfigPath -Algorithm SHA256).Hash
        Write-FixtureText (Join-Path $fixture.EngineRoot 'throw-on-apply') 'fail after effect'
        $result = Invoke-FixtureSelection $fixture (New-Selection @{ SaveFontPreferenceConsent = $true })
        Assert-OneApply $fixture
        Assert-True ($result.Status -ceq 'ThemeFailed' -and -not $result.ThemeApplied -and
            $result.ThemeMayHaveChanged -and -not $result.FontPreferenceSaved -and
            $result.Message -match 'may be partial' -and $result.Message -match 'Font preference was not saved') 'Partial theme failure was reported as success or as unchanged.'
        Assert-True ((Get-FileHash -LiteralPath $fixture.ConfigPath -Algorithm SHA256).Hash -ceq $before -and
            -not (Test-Path -LiteralPath "$($fixture.ConfigPath).lock")) 'Theme failure still attempted preference save.'
        Assert-NoActivation $result
    }

    Invoke-Regression 'Preference failure preserves successful theme result and exact damaged configuration' {
        $fixture = New-SelectionFixture
        Write-FixtureText $fixture.ConfigPath '{ invalid json; preserve for investigation'
        $before = (Get-FileHash -LiteralPath $fixture.ConfigPath -Algorithm SHA256).Hash
        $result = Invoke-FixtureSelection $fixture (New-Selection @{ SaveFontPreferenceConsent = $true })
        Assert-OneApply $fixture
        Assert-True ($result.Status -ceq 'ThemeAppliedPreferenceFailed' -and $result.ThemeApplied -and
            $result.ThemeMayHaveChanged -and -not $result.FontPreferenceSaved -and
            $result.Message -match 'applied, but font preference save failed') 'Preference failure concealed successful theme application.'
        Assert-True ((Get-FileHash -LiteralPath $fixture.ConfigPath -Algorithm SHA256).Hash -ceq $before) 'Preference failure replaced damaged configuration.'
        Assert-NoActivation $result
    }

    Invoke-Regression 'Provider rejection cannot save an unrecognized font' {
        $fixture = New-SelectionFixture
        $result = Invoke-FixtureSelection $fixture (New-Selection @{
            SaveFontPreferenceConsent = $true; Family = 'Unknown Fixture Font'
        })
        Assert-OneApply $fixture
        Assert-True ($result.Status -ceq 'ThemeAppliedPreferenceFailed' -and $result.ThemeApplied -and
            -not $result.FontPreferenceSaved -and -not (Test-Path -LiteralPath $fixture.ConfigPath)) 'Unrecognized font was saved.'
        Assert-NoActivation $result
    }

    Invoke-Regression 'Active V2 ownership blocks apply and mapping, preserves all bytes, and attempts no recovery' {
        foreach ($save in @($false, $true)) {
            $fixture = New-SelectionFixture
            Write-V1Config $fixture $false
            Write-FixtureText $fixture.TerminalPath "{`n /* TYPEZERO_FONT_V2 */`n `"unrelated`": [1,2,3]`n}`n"
            $fixture.TerminalHash = (Get-FileHash -LiteralPath $fixture.TerminalPath -Algorithm SHA256).Hash
            $before = Get-FixtureSnapshot $fixture
            $result = Invoke-FixtureSelection $fixture (New-Selection @{ SaveFontPreferenceConsent = $save })
            Assert-True ($result.Status -ceq 'Blocked' -and -not $result.ThemeApplied -and
                -not $result.ThemeMayHaveChanged -and -not $result.FontPreferenceSaved -and
                $result.Message -match 'separately authorized recovery' -and
                $result.Message -match 'No recovery was attempted') 'V2 ownership block is inaccurate or hides recovery.'
            Assert-NoActivation $result
            Assert-NoEffects $fixture $before
        }
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
    }

    Invoke-Regression 'Source parses and the WPF checkbox/confirmation preserve explicit opt-in' {
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
        $checkBox = $xml.SelectSingleNode('//*[@Name="SaveFontPreferenceBox"]')
        Assert-True ($null -ne $checkBox -and $checkBox.GetAttribute('IsChecked') -ceq 'False') 'Saving font preferences is selected by default.'
        Assert-True ($ui -match '\[Windows\.MessageBoxButton\]::YesNo\s*,\s*\[Windows\.MessageBoxImage\]::Question\s*,\s*\[Windows\.MessageBoxResult\]::No' -and
            $ui -match 'if\s*\(\$approval\s+-ne\s+\[Windows\.MessageBoxResult\]::Yes\)\s*\{\s*return\s*\}') 'Theme confirmation does not require explicit Yes with No as the default.'
        Assert-True ($ui -match 'Saving does not activate the font' -and
            $ui -match 'PreviewOnly\s*=\s*\$true' -and $ui -match 'SettingsChanged\s*=\s*\$false') 'Preview omits read-only/effect boundaries.'
        if ([Threading.Thread]::CurrentThread.ApartmentState -eq 'STA') {
            Add-Type -AssemblyName PresentationFramework
            $window = [Windows.Markup.XamlReader]::Parse($match.Groups['xml'].Value)
            try {
                Assert-True (-not $window.FindName('SaveFontPreferenceBox').IsChecked) 'Loaded WPF checkbox is checked.'
                Assert-True ($null -ne $window.FindName('UseButton')) 'Loaded WPF has no Use Selection button.'
            }
            finally { $window.Close() }
        } else {
            Write-Host 'NOTE: XML/static checks passed; run with -STA to additionally load the WPF window without displaying it.'
        }
    }

    Invoke-Regression 'Existing live apply/restore and legacy V2 ownership safeguards remain present' {
        $realEngine = [IO.File]::ReadAllText((Join-Path $engineSource 'ThemeEngine.ps1'))
        Assert-True ($realEngine -match '(?s)if\s*\(\$WallpaperArgs\.Count\s+-ne\s+2\s+-or\s+\$WallpaperArgs\[1\]\s+-cne\s+''--fixture''\)\s*\{\s*throw\s+''LIVE FONT APPLY DISABLED\.') 'Live font apply guard was removed or weakened.'
        Assert-True ($realEngine -match '(?s)if\s*\(\$WallpaperArgs\.Count\s+-ne\s+2\s+-or\s+\$WallpaperArgs\[0\]\s+-cne\s+''--fixture''\)\s*\{\s*throw\s+''LIVE FONT RESTORE DISABLED\.') 'Live font restore guard was removed or weakened.'
        Assert-True ($realEngine -match '(?s)if\s*\(\$terminalText\.Contains\(''/\* TYPEZERO_FONT_V2 \*/''\)\)\s*\{\s*throw\s+''Legacy Terminal color writer disabled') 'Existing legacy color ownership guard was changed.'
        $tokens = $null
        $errors = $null
        $ast = [Management.Automation.Language.Parser]::ParseFile($source, [ref]$tokens, [ref]$errors)
        $commands = @($ast.FindAll({ param($node) $node -is [Management.Automation.Language.CommandAst] }, $true))
        foreach ($command in $commands) {
            $name = $command.GetCommandName()
            Assert-True ($name -notmatch '(?i)(Restore|Recover|Activat|FontSwitch|Integration)') "Selection invokes an activation/recovery command: $name"
        }
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
