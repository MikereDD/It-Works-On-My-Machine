# Offline integration regressions for the shell and existing preview's actions.
# Retains uniquely named fixtures; never reads/writes live Terminal settings.
# Run: pwsh -NoProfile -File .\tests\Test-TypezeroAppearanceActions.ps1 -FixtureParent <workspace>
[CmdletBinding()]
param([string]$FixtureParent = [IO.Path]::GetTempPath(), [string]$RepositoryRoot)

$ErrorActionPreference = 'Stop'
$engineSource = Split-Path -Parent $PSScriptRoot
if (-not $RepositoryRoot) {
    $candidate = $engineSource
    while ($candidate) {
        if (Test-Path -LiteralPath (Join-Path $candidate 'ThemeEngine\themes\gruvbox\theme.conf') -PathType Leaf) {
            $RepositoryRoot = $candidate
            break
        }
        $candidate = Split-Path -Parent $candidate
    }
}
$originalLocalAppData = $env:LOCALAPPDATA
$root = Join-Path ([IO.Path]::GetFullPath($FixtureParent)) ('typezero-actions-' + [guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($root) | Out-Null
$script:passed = 0
$script:caseNumber = 0
$targetGuid = '{574e775e-4f2a-5b96-ac1e-a2962a402336}'
. (Join-Path $engineSource 'AppearanceSelection-WindowsTerminal.ps1')

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

function Get-BytesSnapshot {
    param([string]$Path)
    [Convert]::ToBase64String([IO.File]::ReadAllBytes($Path))
}

function Get-TreeSnapshot {
    param([string]$Path)
    @((Get-ChildItem -LiteralPath $Path -Recurse -File | Sort-Object FullName) |
        ForEach-Object { $_.FullName.Substring($Path.Length) + ':' + (Get-BytesSnapshot $_.FullName) }) -join "`n"
}

function Read-TargetProfile {
    param([string]$Path)
    $settings = [IO.File]::ReadAllText($Path) | ConvertFrom-Json -AsHashtable
    @($settings.profiles.list | Where-Object { $_.guid -ieq $targetGuid })[0]
}

function Assert-Choice {
    param([string]$Path, [string]$Family, [double]$Size, [string]$Weight)
    $font = (Read-TargetProfile $Path).font
    Assert-True ($font.face -ceq $Family -and $font.size -eq $Size -and $font.weight -ceq $Weight) 'Terminal did not receive the complete requested font tuple.'
}

function New-Selection {
    param([hashtable]$Override = @{})
    $snapshot = Get-TypezeroTerminalFontPreview -Family 'Consolas' -Size 14.25 -Weight 'semi-bold'
    $data = [ordered]@{ Action='Preview'; Theme='gruvbox'; PresetName='desk'; Family='Consolas';
        Size=[double]14.25; Weight='semi-bold'; ExpectedSha256=$snapshot.ExpectedSha256; PreviewOnly=$true; SettingsChanged=$false }
    foreach ($key in $Override.Keys) { $data[$key] = $Override[$key] }
    [pscustomobject]$data
}

function New-ActionFixture {
    $script:caseNumber++
    $folder = Join-Path $root ('case-' + $script:caseNumber)
    $localData = Join-Path $folder 'local-app-data'
    $env:LOCALAPPDATA = $localData
    $themes = Join-Path $localData 'Typezero\ThemeEngine\themes'
    $terminal = Join-Path $localData 'Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json'
    $config = Join-Path $localData 'Typezero\ThemeEngine\font-windows-terminal.json'
    $presets = Join-Path $localData 'Typezero\ThemeEngine\custom-presets.json'
    $fakeEngine = Join-Path $folder 'fake engine with spaces'
    foreach ($path in @((Split-Path -Parent $terminal), $fakeEngine)) {
        [IO.Directory]::CreateDirectory($path) | Out-Null
    }
    foreach ($id in @('gruvbox','nord')) {
        $themeFolder = Join-Path $themes $id
        [IO.Directory]::CreateDirectory($themeFolder) | Out-Null
        $lines = @("THEME_ID=$id", "THEME_NAME=Fixture $id", 'FONT_FAMILY=Base Theme Font', 'FONT_STYLE=Regular')
        foreach ($role in @('BG','SURFACE','SURFACE_ALT','BORDER','TEXT','BRIGHT','MUTED',
            'ACCENT','ACCENT_BRIGHT','SECONDARY','INFO','SELECTION','CURSOR','FOCUS','SUCCESS','WARNING','ERROR',
            'ANSI_BLACK','ANSI_RED','ANSI_GREEN','ANSI_YELLOW','ANSI_BLUE','ANSI_PURPLE','ANSI_CYAN','ANSI_WHITE',
            'ANSI_BRIGHT_BLACK','ANSI_BRIGHT_RED','ANSI_BRIGHT_GREEN','ANSI_BRIGHT_YELLOW','ANSI_BRIGHT_BLUE',
            'ANSI_BRIGHT_PURPLE','ANSI_BRIGHT_CYAN','ANSI_BRIGHT_WHITE')) {
            $color = if ($id -ceq 'gruvbox') { '#282828' } else { '#2e3440' }
            $lines += "$role=$color"
        }
        Write-FixtureText (Join-Path $themeFolder 'theme.conf') (($lines -join "`n") + "`n")
    }
    $settings = @'
{
  // disposable settings; preserve Netzach → Ω and all unrelated bytes
  "copyOnSelect" : false,
  "profiles": {
    "defaults": { "font": {"face":"Default Mono","size":10}, "opacity":82 },
    "list": [
      { "guid":"{574e775e-4f2a-5b96-ac1e-a2962a402336}", "name":"Renamed PowerShell",
        "colorScheme":"User Colors", "font": {"face":"Original Mono","size":11,"weight":"normal", "features":{"ss01":1}, "axes":{"wdth":90}},
        "backgroundImage":"C:\\fixture\\image.png" },
      { "guid":"{11111111-1111-1111-1111-111111111111}", "name":"Other Profile", "font":{"face":"Keep Me","size":9}, "colorScheme":"Other Colors" }
    ]
  },
  "schemes":[{"name":"User Colors","background":"#abcdef","foreground":"#fedcba"}],
  "theme":"system",
  "actions":[{"command":"copy","keys":"ctrl+shift+c"}]
}
'@
    Write-FixtureText $terminal ($settings + "`n")
    Write-FixtureText $config @'
{"Version":2,"Enabled":false,"ManualOverride":null,"Mappings":{"gruvbox":{"family":"Saved Gruvbox Mono","size":13,"weight":"normal"},"nord":{"family":"Saved Nord Mono","size":16,"weight":"semi-bold"}}}
'@
    $current = Join-Path (Split-Path -Parent $config) 'current-theme'
    Write-FixtureText $current 'gruvbox'
    Write-FixtureText (Join-Path $fakeEngine 'ThemeEngine.ps1') @'
[CmdletBinding()]
param([Parameter(Mandatory)][string]$Command,
    [Parameter(Mandatory)][string]$Theme,
    [Parameter(Mandatory)][System.Collections.IDictionary]$TerminalFont, [string]$ExpectedSettingsSha256)
$entry = [ordered]@{Command=$Command;Theme=$Theme;TerminalFont=$TerminalFont;BoundKeys=@($PSBoundParameters.Keys | Sort-Object)}
[IO.File]::WriteAllText((Join-Path $PSScriptRoot 'apply-log.json'), ($entry | ConvertTo-Json -Depth 6))
if (Test-Path -LiteralPath (Join-Path $PSScriptRoot 'throw-on-apply')) { throw 'Fixture theme failure.' }
$settings = Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json'
if (-not (Test-Path -LiteralPath (Join-Path $PSScriptRoot 'skip-font'))) {
    $null = Set-TypezeroTerminalFontChoice -SettingsPath $settings -Family $TerminalFont['face'] -Size $TerminalFont['size'] -Weight $TerminalFont['weight']
}
[IO.File]::WriteAllText((Join-Path $PSScriptRoot 'theme-applied'), $Theme)
'@
    Copy-Item -LiteralPath (Join-Path $engineSource 'ThemePresentation.ps1') -Destination $fakeEngine
    [pscustomobject]@{ Root=$folder; LocalData=$localData; Themes=$themes; Settings=$terminal; Mapping=$config;
        Presets=$presets; Engine=$fakeEngine; Marker=$current; ApplyLog=(Join-Path $fakeEngine 'apply-log.json') }
}

function Invoke-ActualCli {
    param([string]$Action, [string[]]$Arguments, [string]$ExpectedSha256)
    $params = @{Command='font';Theme=$Action;WallpaperArgs=$Arguments}
    if ($ExpectedSha256) { $params.ExpectedSettingsSha256=$ExpectedSha256 }
    & (Join-Path $engineSource 'ThemeEngine.ps1') @params
}

function Invoke-FixtureCommand {
    param([psobject]$Fixture, [string]$Action, [string[]]$Arguments)
    Invoke-TypezeroFontCommand -Action $Action -Arguments $Arguments -EngineRoot $Fixture.Engine -ThemesRoot $Fixture.Themes
}

function Copy-RepositoryThemes {
    param([psobject]$Fixture)
    foreach ($id in @('gruvbox','nord')) {
        Copy-Item -LiteralPath (Join-Path $RepositoryRoot "ThemeEngine\themes\$id\theme.conf") `
            -Destination (Join-Path $Fixture.Themes "$id\theme.conf") -Force
    }
}

function New-ActualTerminalFunctions {
    param([psobject]$Fixture)
    $tokens=$null; $errors=$null
    $ast = [Management.Automation.Language.Parser]::ParseFile((Join-Path $engineSource 'ThemeEngine.ps1'),[ref]$tokens,[ref]$errors)
    Assert-True ($errors.Count -eq 0) 'ThemeEngine has parser errors.'
    $definitions = foreach ($name in @('Get-WindowsTerminalSettingsPath','Read-ThemeFile','Set-WindowsTerminalTheme')) {
        $matches = @($ast.FindAll({ param($node)
            $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -ceq $name
        },$false))
        Assert-True ($matches.Count -eq 1) "Expected one actual engine function: $name"
        $matches[0].Extent.Text
    }
    $wrapper = Join-Path $Fixture.Engine 'actual-terminal-functions.ps1'
    Write-FixtureText $wrapper ($definitions -join "`n`n")
    foreach ($module in @('FontMapping-WindowsTerminal.ps1','TerminalSettings-WindowsTerminal.ps1','FontWeights-WindowsTerminal.ps1')) {
        Copy-Item -LiteralPath (Join-Path $engineSource $module) -Destination $Fixture.Engine
    }
    $wrapper
}

try {
    Invoke-Regression 'CLI font preview reads the target tuple and creates no files' {
        $f = New-ActionFixture
        $before = Get-TreeSnapshot $f.Root
        $preview = Invoke-ActualCli preview-font @('Consolas','14.25','semi-bold')
        Assert-True ($preview.Family -ceq 'Consolas' -and $preview.Size -eq 14.25 -and $preview.Weight -ceq 'semi-bold') 'CLI preview omitted selected values.'
        Assert-True ($preview.CurrentFamily -ceq 'Original Mono' -and $preview.PreviewOnly -and -not $preview.SettingsChanged) 'CLI preview did not identify current font or read-only state.'
        Assert-True ($preview.ExpectedSha256 -cmatch '\A[A-F0-9]{64}\z' -and $preview.WouldChange) 'Preview did not include the settings snapshot/change plan.'
        Assert-True ((Get-TreeSnapshot $f.Root) -ceq $before) 'Preview changed fixture settings, preferences or files.'
    }

    Invoke-Regression 'CLI apply-font activates only font with exact backup and no theme or preference changes' {
        $f = New-ActionFixture
        $mapping = Get-BytesSnapshot $f.Mapping; $themes = Get-TreeSnapshot $f.Themes
        $marker = Get-BytesSnapshot $f.Marker; $settings = Get-BytesSnapshot $f.Settings
        $preview = Invoke-ActualCli preview-font @('Consolas','14.25','semi-bold')
        $result = Invoke-ActualCli apply-font @('Consolas','14.25','semi-bold') $preview.ExpectedSha256
        Assert-True ($result.Status -ceq 'FontApplied' -and $result.FontActivated -and $result.SettingsChanged) 'CLI apply-font did not report activation.'
        Assert-Choice $f.Settings 'Consolas' 14.25 'semi-bold'
        Assert-True ((Get-BytesSnapshot $result.BackupPath) -ceq $settings) 'Font Apply backup differs from the exact original.'
        Assert-True ((Get-BytesSnapshot $f.Mapping) -ceq $mapping -and (Get-TreeSnapshot $f.Themes) -ceq $themes -and (Get-BytesSnapshot $f.Marker) -ceq $marker) 'Font Apply changed saved mappings, base themes or current theme.'
        Assert-True (-not (Test-Path -LiteralPath $f.Presets) -and -not (Test-Path -LiteralPath $f.ApplyLog)) 'Font Apply saved choices or invoked theme application.'
        $text = [IO.File]::ReadAllText($f.Settings)
        foreach ($fragment in @('// disposable settings; preserve Netzach → Ω and all unrelated bytes',
            '"colorScheme":"User Colors"', '"features":{"ss01":1}', '"axes":{"wdth":90}',
            '"theme":"system"', '"actions":[{"command":"copy","keys":"ctrl+shift+c"}]',
            '{ "guid":"{11111111-1111-1111-1111-111111111111}", "name":"Other Profile", "font":{"face":"Keep Me","size":9}, "colorScheme":"Other Colors" }')) {
            Assert-True ($text.Contains($fragment)) "Font Apply changed unrelated Terminal text: $fragment"
        }
    }

    Invoke-Regression 'Repeated font Apply is a no-op without a second backup' {
        $f = New-ActionFixture
        $null = Invoke-ActualCli apply-font @('Consolas','14.25','semi-bold')
        $before = Get-TreeSnapshot $f.Root
        $again = Invoke-ActualCli apply-font @('Consolas','14.25','semi-bold')
        Assert-True ($again.FontActivated -and -not $again.Changed -and -not $again.SettingsChanged -and -not $again.BackupPath) 'Idempotent Apply made a second change.'
        Assert-True ((Get-TreeSnapshot $f.Root) -ceq $before) 'No-op Apply wrote an extra file.'
    }

    Invoke-Regression 'CLI Save creates only the separate named preset and lists the saved tuple' {
        $f = New-ActionFixture
        $before = Get-TreeSnapshot $f.Root
        $saved = Invoke-ActualCli save-preset @('desk','nord','Consolas','14.25','semi-bold')
        Assert-True ($saved.Status -ceq 'PresetSaved') 'CLI Save did not report persistence.'
        $listed = @(Invoke-ActualCli presets @())
        Assert-True ($listed.Count -eq 1 -and $listed[0].Name -ceq 'desk' -and $listed[0].Theme -ceq 'nord' -and $listed[0].Family -ceq 'Consolas' -and $listed[0].Size -eq 14.25 -and $listed[0].Weight -ceq 'semi-bold') 'CLI presets omitted saved choices.'
        $withoutPreset = @(Get-ChildItem -LiteralPath $f.Root -Recurse -File | Where-Object { $_.FullName -ine $f.Presets } | Sort-Object FullName |
            ForEach-Object { $_.FullName.Substring($f.Root.Length) + ':' + (Get-BytesSnapshot $_.FullName) }) -join "`n"
        Assert-True ($withoutPreset -ceq $before) 'Save changed settings, base themes, mappings or another file.'
        Assert-True (-not (Test-Path -LiteralPath $f.ApplyLog)) 'Save activated the theme.'
    }

    Invoke-Regression 'Preset replacement requires explicit --replace and backs up prior choices' {
        $f = New-ActionFixture
        $null = Invoke-ActualCli save-preset @('desk','gruvbox','Consolas','14.25','semi-bold')
        $before = Get-TreeSnapshot $f.Root; $original = Get-BytesSnapshot $f.Presets
        Assert-Throws { Invoke-ActualCli save-preset @('desk','nord','Courier New','15','normal') } 'Duplicate Save silently replaced choices.'
        Assert-True ((Get-TreeSnapshot $f.Root) -ceq $before) 'Rejected duplicate Save wrote a file.'
        $replaced = Invoke-ActualCli save-preset @('desk','nord','Courier New','15','normal','--replace')
        Assert-True ((Get-BytesSnapshot $replaced.BackupPath) -ceq $original) 'Replacement backup lost previous choices.'
        $listed = @(Invoke-ActualCli presets @())
        Assert-True ($listed.Count -eq 1 -and $listed[0].Theme -ceq 'nord' -and $listed[0].Family -ceq 'Courier New') 'Explicit replacement duplicated or lost the preset.'
    }

    Invoke-Regression 'Shared Save replaces a preset only with explicit Boolean intent and preserves appearance' {
        $f = New-ActionFixture
        $null = Invoke-TypezeroAppearanceSelection -Selection (New-Selection @{Action='SavePreset';ReplacePreset=$false}) -EngineRoot $f.Engine -ThemesRoot $f.Themes
        $before = Get-TreeSnapshot $f.Root; $original = Get-BytesSnapshot $f.Presets
        $settings = Get-BytesSnapshot $f.Settings; $themes = Get-TreeSnapshot $f.Themes
        $mapping = Get-BytesSnapshot $f.Mapping; $marker = Get-BytesSnapshot $f.Marker
        foreach ($intent in @($false,'true',1,$null)) {
            Assert-Throws { Invoke-TypezeroAppearanceSelection -Selection (New-Selection @{
                Action='SavePreset';ReplacePreset=$intent;Theme='nord';Family='Courier New';Size=[double]15;Weight='normal'
            }) -EngineRoot $f.Engine -ThemesRoot $f.Themes } 'Duplicate shared Save accepted false or malformed replacement intent.'
            Assert-True ((Get-TreeSnapshot $f.Root) -ceq $before) 'Rejected replacement intent wrote a file.'
        }
        $replaced = Invoke-TypezeroAppearanceSelection -Selection (New-Selection @{
            Action='SavePreset';ReplacePreset=$true;Theme='nord';Family='Courier New';Size=[double]15;Weight='normal'
        }) -EngineRoot $f.Engine -ThemesRoot $f.Themes
        Assert-True ($replaced.Status -ceq 'PresetSaved' -and (Get-BytesSnapshot $replaced.BackupPath) -ceq $original) 'Shared replacement did not preserve the exact prior preset bytes.'
        $listed = @(Get-TypezeroAppearancePresets)
        Assert-True ($listed.Count -eq 1 -and $listed[0].Name -ceq 'desk' -and $listed[0].Theme -ceq 'nord' -and $listed[0].Family -ceq 'Courier New' -and $listed[0].Size -eq 15 -and $listed[0].Weight -ceq 'normal') 'Shared replacement did not persist the complete requested tuple.'
        Assert-True ((Get-BytesSnapshot $f.Settings) -ceq $settings -and (Get-TreeSnapshot $f.Themes) -ceq $themes -and (Get-BytesSnapshot $f.Mapping) -ceq $mapping -and (Get-BytesSnapshot $f.Marker) -ceq $marker -and -not (Test-Path -LiteralPath $f.ApplyLog)) 'Shared replacement activated appearance or changed base themes, mappings or current theme.'
    }

    Invoke-Regression 'CLI preview-preset shows its base palette and custom font without writes' {
        $f = New-ActionFixture
        $null = Invoke-ActualCli save-preset @('desk','nord','Consolas','14.25','semi-bold')
        $before = Get-TreeSnapshot $f.Root
        $records = @(Invoke-ActualCli preview-preset @('desk') 6>&1)
        $preview = @($records | Where-Object { $_.PSObject.Properties['ExpectedSha256'] })
        Assert-True ($preview.Count -eq 1 -and $preview[0].Family -ceq 'Consolas' -and $preview[0].Size -eq 14.25 -and $preview[0].Weight -ceq 'semi-bold') 'Preset preview did not return custom typography.'
        Assert-True (($records -join "`n").Contains('THEME: Fixture nord (nord)')) 'Preset preview omitted selected base palette.'
        Assert-True ((Get-TreeSnapshot $f.Root) -ceq $before) 'Preset preview wrote settings or preferences.'
    }

    Invoke-Regression 'CLI apply-preset handler passes an unsaved one-use font override through shared actions' {
        $f = New-ActionFixture
        $null = Invoke-FixtureCommand $f save-preset @('desk','nord','Consolas','14.25','semi-bold')
        $mapping = Get-BytesSnapshot $f.Mapping; $themes = Get-TreeSnapshot $f.Themes; $presets = Get-BytesSnapshot $f.Presets
        $applied = Invoke-FixtureCommand $f apply-preset @('desk')
        Assert-True ($applied.Status -ceq 'ThemeApplied' -and $applied.Theme -ceq 'nord' -and $applied.FontActivated) 'Preset Apply did not report verified activation.'
        $log = [IO.File]::ReadAllText($f.ApplyLog) | ConvertFrom-Json
        Assert-True ($log.Command -ceq 'apply' -and $log.Theme -ceq 'nord' -and ($log.BoundKeys -join ',') -ceq 'Command,ExpectedSettingsSha256,TerminalFont,Theme') 'Preset Apply did not use the focused theme entry point.'
        Assert-True ($log.TerminalFont.face -ceq 'Consolas' -and $log.TerminalFont.size -eq 14.25 -and $log.TerminalFont.weight -ceq 'semi-bold') 'Preset Apply lost the one-use font tuple.'
        Assert-Choice $f.Settings 'Consolas' 14.25 'semi-bold'
        Assert-True ((Get-BytesSnapshot $f.Mapping) -ceq $mapping -and (Get-TreeSnapshot $f.Themes) -ceq $themes -and (Get-BytesSnapshot $f.Presets) -ceq $presets) 'Preset Apply rewrote saved preferences or base themes.'
    }

    Invoke-Regression 'Shared GUI action Preview, Save and ApplyFont have distinct effects' {
        $f = New-ActionFixture
        $before = Get-TreeSnapshot $f.Root
        $preview = Invoke-TypezeroAppearanceSelection -Selection (New-Selection) -EngineRoot $f.Engine -ThemesRoot $f.Themes
        Assert-True ($preview.PreviewOnly -and -not $preview.SettingsChanged -and (Get-TreeSnapshot $f.Root) -ceq $before) 'Shared Preview wrote changes.'
        $saved = Invoke-TypezeroAppearanceSelection -Selection (New-Selection @{Action='SavePreset'}) -EngineRoot $f.Engine -ThemesRoot $f.Themes
        Assert-True ($saved.Status -ceq 'PresetSaved') 'Shared Save failed.'
        Assert-Choice $f.Settings 'Original Mono' 11 'normal'
        $presets = Get-BytesSnapshot $f.Presets
        $applied = Invoke-TypezeroAppearanceSelection -Selection (New-Selection @{Action='ApplyFont';ExpectedSha256=$preview.ExpectedSha256}) -EngineRoot $f.Engine -ThemesRoot $f.Themes
        Assert-True ($applied.Status -ceq 'FontApplied') 'Shared ApplyFont failed.'
        Assert-Choice $f.Settings 'Consolas' 14.25 'semi-bold'
        Assert-True ((Get-BytesSnapshot $f.Presets) -ceq $presets -and -not (Test-Path -LiteralPath $f.ApplyLog)) 'Shared ApplyFont persisted choices or activated a theme.'
    }

    Invoke-Regression 'Intervening settings edits reject both CLI and shared Apply without writes' {
        $f = New-ActionFixture
        $preview = Invoke-ActualCli preview-font @('Consolas','14.25','semi-bold')
        [IO.File]::AppendAllText($f.Settings,"`n// edited after preview`n")
        $before = Get-TreeSnapshot $f.Root
        Assert-Throws { Invoke-ActualCli apply-font @('Consolas','14.25','semi-bold') $preview.ExpectedSha256 } 'CLI applied a stale preview.'
        Assert-Throws { Invoke-TypezeroAppearanceSelection -Selection (New-Selection @{Action='ApplyTheme';ExpectedSha256=$preview.ExpectedSha256}) -EngineRoot $f.Engine -ThemesRoot $f.Themes } 'Shared theme Apply accepted a stale preview.'
        Assert-True ((Get-TreeSnapshot $f.Root) -ceq $before) 'Rejected stale Apply changed files.'
    }

    Invoke-Regression 'WhatIf keeps font Apply, theme Apply and preset Save read-only' {
        $f = New-ActionFixture
        $before = Get-TreeSnapshot $f.Root
        foreach ($action in @('ApplyFont','ApplyTheme','SavePreset')) {
            $null = Invoke-TypezeroAppearanceSelection -Selection (New-Selection @{Action=$action}) -EngineRoot $f.Engine -ThemesRoot $f.Themes -WhatIf
        }
        Assert-True ((Get-TreeSnapshot $f.Root) -ceq $before) 'WhatIf wrote settings, preferences or a theme marker.'
    }

    Invoke-Regression 'Shared Apply requires the preview snapshot instead of silently refreshing it' {
        $f = New-ActionFixture
        $before = Get-TreeSnapshot $f.Root
        foreach ($action in @('ApplyFont','ApplyTheme')) {
            foreach ($snapshot in @('','not-a-hash',('0' * 64))) {
                Assert-Throws { Invoke-TypezeroAppearanceSelection -Selection (New-Selection @{Action=$action;ExpectedSha256=$snapshot}) -EngineRoot $f.Engine -ThemesRoot $f.Themes } "$action accepted absent or invalid preview evidence."
            }
        }
        Assert-True ((Get-TreeSnapshot $f.Root) -ceq $before) 'Apply without a valid preview changed files.'
    }

    Invoke-Regression 'Incomplete base Terminal palettes fail before invoking theme effects' {
        $f = New-ActionFixture
        Write-FixtureText (Join-Path $f.Themes 'gruvbox\theme.conf') "THEME_ID=gruvbox`nTHEME_NAME=No ANSI`nBG=#282828`nTEXT=#eeeeee`n"
        $before = Get-TreeSnapshot $f.Root
        Assert-Throws { Invoke-TypezeroAppearanceSelection -Selection (New-Selection @{Action='ApplyTheme'}) -EngineRoot $f.Engine -ThemesRoot $f.Themes } 'An incomplete Terminal theme claimed successful Apply.'
        Assert-True ((Get-TreeSnapshot $f.Root) -ceq $before -and -not (Test-Path -LiteralPath $f.ApplyLog)) 'Incomplete palette caused appearance effects before rejection.'
    }

    Invoke-Regression 'Invalid action, read-only flags, tuple values and CLI usage reject without writes' {
        $f = New-ActionFixture
        $before = Get-TreeSnapshot $f.Root
        foreach ($override in @(@{Action='applyfont'},@{PreviewOnly=$false},@{SettingsChanged=$true},
            @{PreviewOnly='true'},@{SettingsChanged=0},@{Size='14.25'},@{Size=5},@{Size=36.01},
            @{Size=14.255},@{Size=[double]::NaN},@{Family=' Consolas'},@{Family="Fixture`nMono"},@{Weight='heavy'})) {
            Assert-Throws { Invoke-TypezeroAppearanceSelection -Selection (New-Selection $override) -EngineRoot $f.Engine -ThemesRoot $f.Themes } "Invalid selection was accepted: $($override | ConvertTo-Json -Compress)"
        }
        foreach ($case in @(@{Action='preview-font';Args=@('Consolas','14,25','normal')},
            @{Action='apply-font';Args=@('Consolas','14','normal','unexpected')},
            @{Action='presets';Args=@('unexpected')},@{Action='apply-preset';Args=@('missing')},
            @{Action='save-preset';Args=@('../bad','nord','Consolas','14','normal')},
            @{Action='save-preset';Args=@('desk','missing','Consolas','14','normal')})) {
            Assert-Throws { Invoke-ActualCli $case.Action $case.Args } "Invalid CLI arguments were accepted for $($case.Action)."
        }
        Assert-True ((Get-TreeSnapshot $f.Root) -ceq $before) 'Invalid input wrote settings or preferences.'
    }

    Invoke-Regression 'Missing preset base theme rejects Preview and Apply without writes' {
        $f = New-ActionFixture
        $null = Invoke-FixtureCommand $f save-preset @('desk','nord','Consolas','14.25','semi-bold')
        # Relocate only the explicit fixture base file; no recursive deletion.
        Move-Item -LiteralPath (Join-Path $f.Themes 'nord\theme.conf') -Destination (Join-Path $f.Root 'removed-theme.conf')
        $before = Get-TreeSnapshot $f.Root
        foreach ($action in @('preview-preset','apply-preset')) {
            Assert-Throws { Invoke-FixtureCommand $f $action @('desk') } "Preset with a missing base theme accepted $action."
        }
        Assert-True ((Get-TreeSnapshot $f.Root) -ceq $before) 'Missing base theme rejection wrote files.'
    }

    Invoke-Regression 'Theme failure and incorrect font readback never claim successful activation' {
        foreach ($sentinel in @('throw-on-apply','skip-font')) {
            $f = New-ActionFixture
            Write-FixtureText (Join-Path $f.Engine $sentinel) 'fixture'
            Assert-Throws { Invoke-TypezeroAppearanceSelection -Selection (New-Selection @{Action='ApplyTheme'}) -EngineRoot $f.Engine -ThemesRoot $f.Themes } "Shared Apply claimed success after $sentinel."
            Assert-True (Test-Path -LiteralPath $f.ApplyLog) 'Theme fixture was not called.'
        }
    }

    Invoke-Regression 'Actual Terminal theme path honors one-use override then retains saved Gruvbox -> Nord -> Gruvbox behavior' {
        $f = New-ActionFixture
        if ($RepositoryRoot) { Copy-RepositoryThemes $f }
        $wrapper = New-ActualTerminalFunctions $f
        . $wrapper
        $ThemesRoot = $f.Themes
        $mapping = Get-BytesSnapshot $f.Mapping; $themes = Get-TreeSnapshot $f.Themes
        $gruvbox = Read-ThemeFile gruvbox
        $nord = Read-ThemeFile nord
        $original = Get-BytesSnapshot $f.Settings
        $null = Set-WindowsTerminalTheme $gruvbox -TerminalFont ([ordered]@{face='Consolas';size=15.5;weight='semi-bold'})
        Assert-Choice $f.Settings 'Consolas' 15.5 'semi-bold'
        $backups = @(Get-ChildItem -LiteralPath (Split-Path -Parent $f.Settings) -File | Where-Object { $_.Name -ne 'settings.json' })
        Assert-True ($backups.Count -eq 1 -and (Get-BytesSnapshot $backups[0].FullName) -ceq $original) 'Actual override apply did not preserve exact backup.'
        foreach ($step in @(@{Theme=$gruvbox;Family='Saved Gruvbox Mono';Size=13;Weight='normal'},
            @{Theme=$nord;Family='Saved Nord Mono';Size=16;Weight='semi-bold'},
            @{Theme=$gruvbox;Family='Saved Gruvbox Mono';Size=13;Weight='normal'})) {
            $null = Set-WindowsTerminalTheme $step.Theme
            Assert-Choice $f.Settings $step.Family $step.Size $step.Weight
            Assert-True ((Read-TargetProfile $f.Settings).colorScheme -ceq "Typezero $($step.Theme.THEME_NAME)") 'Actual theme apply did not switch the requested base palette.'
        }
        Assert-True ((Get-BytesSnapshot $f.Mapping) -ceq $mapping -and (Get-TreeSnapshot $f.Themes) -ceq $themes) 'One-use override changed saved mapping or base theme definitions.'
    }

    if ($RepositoryRoot) {
        Invoke-Regression 'Real Gruvbox -> Nord -> Gruvbox presets preview and apply through shared public actions' {
            $f = New-ActionFixture
            Copy-RepositoryThemes $f
            $baseHashes = @{}
            foreach ($id in @('gruvbox','nord')) {
                $baseHashes[$id] = (Get-FileHash -LiteralPath (Join-Path $RepositoryRoot "ThemeEngine\themes\$id\theme.conf") -Algorithm SHA256).Hash
            }
            $themes = Get-TreeSnapshot $f.Themes; $mapping = Get-BytesSnapshot $f.Mapping
            $choices = @(@{Theme='gruvbox';Name='warm-desk';Family='JetBrainsMono NF';Size='13';Weight='normal';Label='Gruvbox Dark'},
                @{Theme='nord';Name='cool-desk';Family='JetBrainsMono NF';Size='11';Weight='semi-bold';Label='Nord'})
            foreach ($choice in $choices) {
                $null = Invoke-FixtureCommand $f save-preset @($choice.Name,$choice.Theme,$choice.Family,$choice.Size,$choice.Weight)
            }
            $presets = Get-BytesSnapshot $f.Presets
            foreach ($choice in @($choices[0],$choices[1],$choices[0])) {
                $before = Get-TreeSnapshot $f.Root
                $records = @(Invoke-FixtureCommand $f preview-preset @($choice.Name) 6>&1)
                $preview = @($records | Where-Object { $_.PSObject.Properties['ExpectedSha256'] })[0]
                Assert-True (($records -join "`n").Contains("THEME: $($choice.Label) ($($choice.Theme))")) 'Repository theme preset did not preview its actual base palette.'
                Assert-True ($preview.Family -ceq $choice.Family -and $preview.Size -eq [double]$choice.Size -and $preview.Weight -ceq $choice.Weight) 'Repository theme preset preview lost exact typography.'
                Assert-True ((Get-TreeSnapshot $f.Root) -ceq $before) 'Repository theme preset preview wrote a file.'
                $applied = Invoke-FixtureCommand $f apply-preset @($choice.Name)
                Assert-True ($applied.Status -ceq 'ThemeApplied' -and $applied.Theme -ceq $choice.Theme) 'Repository base theme failed shared Apply validation.'
                Assert-Choice $f.Settings $choice.Family ([double]$choice.Size) $choice.Weight
            }
            $gruvbox = Read-TypezeroAppearanceBaseTheme -Theme gruvbox -ThemesRoot $f.Themes
            Assert-True ($gruvbox.SELECTION -ceq $gruvbox.BORDER -and $gruvbox.CURSOR -ceq $gruvbox.ACCENT_BRIGHT -and $gruvbox.FOCUS -ceq $gruvbox.ACCENT) 'Established fallback interaction colors changed for Gruvbox.'
            Assert-True ((Get-TreeSnapshot $f.Themes) -ceq $themes -and (Get-BytesSnapshot $f.Mapping) -ceq $mapping -and (Get-BytesSnapshot $f.Presets) -ceq $presets) 'Repository preset Apply rewrote immutable themes or saved preferences.'
            foreach ($id in @('gruvbox','nord')) {
                Assert-True ((Get-FileHash -LiteralPath (Join-Path $RepositoryRoot "ThemeEngine\themes\$id\theme.conf") -Algorithm SHA256).Hash -ceq $baseHashes[$id]) 'Source repository base theme bytes changed.'
            }
        }
    }
    else { Write-Host 'Repository theme fixture test skipped: pass -RepositoryRoot when running a staged copy.' }

    Write-Host "All $script:passed appearance action regressions passed. Fixtures: $root"
}
finally {
    $env:LOCALAPPDATA = $originalLocalAppData
}
