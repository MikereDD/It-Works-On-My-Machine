# Focused offline regression: switch complete Terminal colors and fonts together.
# Only uniquely named disposable settings fixtures are written; fixtures are retained.
# Run: pwsh -NoProfile -File .\tests\Test-TypezeroTerminalAppearance.ps1
[CmdletBinding()]
param([string]$FixtureParent = [IO.Path]::GetTempPath())

$ErrorActionPreference = 'Stop'
$engineSource = Split-Path -Parent $PSScriptRoot
. (Join-Path $engineSource 'TerminalSettings-WindowsTerminal.ps1')
$root = Join-Path $FixtureParent ('typezero-appearance-' + [guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($root) | Out-Null
$script:passed = 0
$script:caseNumber = 0
$targetGuid = '{574e775e-4f2a-5b96-ac1e-a2962a402336}'

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

function New-SettingsFixture {
    param([string]$Text, [switch]$Bom)
    $script:caseNumber++
    $folder = Join-Path $root ('case-' + $script:caseNumber)
    [IO.Directory]::CreateDirectory($folder) | Out-Null
    $path = Join-Path $folder 'settings.json'
    [IO.File]::WriteAllText($path, $Text, [Text.UTF8Encoding]::new([bool]$Bom))
    $path
}

function Get-BytesSnapshot {
    param([string]$Path)
    [Convert]::ToBase64String([IO.File]::ReadAllBytes($Path))
}

function Get-DirectorySnapshot {
    param([string]$Path)
    @((Get-ChildItem -LiteralPath (Split-Path -Parent $Path) -File | Sort-Object Name) |
        ForEach-Object { $_.Name + ':' + (Get-BytesSnapshot $_.FullName) }) -join "`n"
}

function Read-SettingsFixture {
    param([string]$Path)
    [IO.File]::ReadAllText($Path) | ConvertFrom-Json -AsHashtable
}

function Get-TargetProfile {
    param([System.Collections.IDictionary]$Settings)
    $profiles = @($Settings.profiles.list | Where-Object { $_.guid -ieq $targetGuid })
    Assert-True ($profiles.Count -eq 1) 'Expected one PowerShell profile in test result.'
    $profiles[0]
}

function New-Scheme {
    param([string]$Name, [string]$Background)
    [ordered]@{
        name = $Name; background = $Background; foreground = '#eeeeee'
        cursorColor = '#dddddd'; selectionBackground = '#444444'
        black = '#101010'; red = '#aa1111'; green = '#11aa11'; yellow = '#aaaa11'
        blue = '#1111aa'; purple = '#aa11aa'; cyan = '#11aaaa'; white = '#bbbbbb'
        brightBlack = '#555555'; brightRed = '#ff5555'; brightGreen = '#55ff55'
        brightYellow = '#ffff55'; brightBlue = '#5555ff'; brightPurple = '#ff55ff'
        brightCyan = '#55ffff'; brightWhite = '#ffffff'
    }
}

function New-TerminalTheme {
    param([string]$Background)
    [ordered]@{
        name = 'Typezero ThemeEngine'
        window = [ordered]@{ applicationTheme = 'dark' }
        tab = [ordered]@{ background = 'terminalBackground'; unfocusedBackground = $Background; showCloseButton = 'hover' }
        tabRow = [ordered]@{ background = $Background; unfocusedBackground = $Background }
    }
}

function Assert-Appearance {
    param([string]$Path, [System.Collections.IDictionary]$Scheme, [AllowNull()][System.Collections.IDictionary]$Font)
    $settings = Read-SettingsFixture $Path
    $profile = Get-TargetProfile $settings
    Assert-True ($profile.colorScheme -ceq $Scheme.name) 'PowerShell color scheme did not switch.'
    $actualScheme = @($settings.schemes | Where-Object { $_.name -ceq $Scheme.name })
    Assert-True ($actualScheme.Count -eq 1) 'Expected exactly one named scheme.'
    foreach ($key in $Scheme.Keys) {
        Assert-True ($actualScheme[0][$key] -ceq $Scheme[$key]) "Color '$key' did not switch."
    }
    Assert-True ($settings.theme -ceq 'Typezero ThemeEngine') 'Terminal chrome theme is not selected.'
    $chrome = @($settings.themes | Where-Object { $_.name -ceq 'Typezero ThemeEngine' })
    Assert-True ($chrome.Count -eq 1 -and $chrome[0].tabRow.background -ceq $Scheme.background) 'Chrome colors did not switch.'
    if ($null -ne $Font) {
        foreach ($key in @('face','size','weight')) {
            Assert-True ($profile.font[$key] -ceq $Font[$key]) "Font '$key' did not switch."
        }
    }
}

function New-EngineTheme {
    param([string]$Id, [System.Collections.IDictionary]$Scheme)
    $theme = [ordered]@{
        THEME_ID = $Id; THEME_NAME = $Scheme.name.Substring('Typezero '.Length)
        BG = $Scheme.background; TEXT = $Scheme.foreground
        CURSOR = $Scheme.cursorColor; SELECTION = $Scheme.selectionBackground
        ACCENT = $Scheme.cursorColor
    }
    $ansi = [ordered]@{
        ANSI_BLACK='black'; ANSI_RED='red'; ANSI_GREEN='green'; ANSI_YELLOW='yellow'
        ANSI_BLUE='blue'; ANSI_PURPLE='purple'; ANSI_CYAN='cyan'; ANSI_WHITE='white'
        ANSI_BRIGHT_BLACK='brightBlack'; ANSI_BRIGHT_RED='brightRed'
        ANSI_BRIGHT_GREEN='brightGreen'; ANSI_BRIGHT_YELLOW='brightYellow'
        ANSI_BRIGHT_BLUE='brightBlue'; ANSI_BRIGHT_PURPLE='brightPurple'
        ANSI_BRIGHT_CYAN='brightCyan'; ANSI_BRIGHT_WHITE='brightWhite'
    }
    foreach ($key in $ansi.Keys) { $theme[$key] = $Scheme[$ansi[$key]] }
    $theme
}

function New-EngineFunctionFixture {
    param([string]$Name, [string[]]$Names)
    $folder = Join-Path $root $Name
    [IO.Directory]::CreateDirectory($folder) | Out-Null
    $tokens = $null
    $errors = $null
    $ast = [Management.Automation.Language.Parser]::ParseFile(
        (Join-Path $engineSource 'ThemeEngine.ps1'), [ref]$tokens, [ref]$errors)
    Assert-True ($errors.Count -eq 0) 'ThemeEngine source has syntax errors.'
    $definitions = foreach ($functionName in $Names) {
        $functions = @($ast.FindAll({
            param($node)
            $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -ceq $functionName
        }, $false))
        Assert-True ($functions.Count -eq 1) "Expected one actual engine function '$functionName'."
        $functions[0].Extent.Text
    }
    $wrapper = Join-Path $folder 'ActualEngineFunctions.ps1'
    [IO.File]::WriteAllText($wrapper, ($definitions -join "`r`n`r`n"), [Text.UTF8Encoding]::new($false))
    foreach ($module in @('FontMapping-WindowsTerminal.ps1', 'TerminalSettings-WindowsTerminal.ps1', 'FontWeights-WindowsTerminal.ps1')) {
        Copy-Item -LiteralPath (Join-Path $engineSource $module) -Destination $folder
    }
    $wrapper
}

function Invoke-SetThemeFixture {
    param([string]$NativeFailure = '', [string]$SettingsText, [switch]$IncompletePalette)
    # Execute the actual live control flow with only native/Vim/shell effects
    # stubbed. Real mapping reads and Terminal writes stay in this private tree.
    $wrapper = New-EngineFunctionFixture ('actual-set-theme-' + [guid]::NewGuid().ToString('N')) @(
        'Get-WindowsTerminalSettingsPath', 'Set-WindowsTerminalTheme', 'Set-Theme')
    $folder = Split-Path -Parent $wrapper
    [IO.File]::WriteAllText((Join-Path $folder 'WindowsAppearance.ps1'), @'
function Set-TypezeroWindowsNativeTheme {
    param($Id, $Name, $Accent)
    if ($script:applyFixtureNativeFailure) { throw $script:applyFixtureNativeFailure }
}
'@, [Text.UTF8Encoding]::new($false))
    . $wrapper
    function Read-ThemeFile { param($Id) $script:applyFixtureTheme }
    function Write-ThemeTemplate { param($Source, $Destination, $Theme) }
    function Write-CurrentTheme { param($T) $script:applyFixtureCurrentWrites++ }
    $script:applyFixtureNativeFailure = $NativeFailure
    $script:applyFixtureCurrentWrites = 0
    $script:applyFixtureTheme = New-EngineTheme 'fixture-b' $schemeB
    if ($IncompletePalette) { $script:applyFixtureTheme.Remove('ANSI_BLACK') }
    $TemplatesRoot = Join-Path $folder 'templates'
    $CurrentFile = Join-Path $folder 'current-theme'
    $PreviousFile = Join-Path $folder 'previous-theme'
    [IO.File]::WriteAllText($CurrentFile, 'fixture-a')
    [IO.File]::WriteAllText($PreviousFile, 'fixture-previous')
    $historyBefore = (Get-BytesSnapshot $CurrentFile) + ':' + (Get-BytesSnapshot $PreviousFile)
    $originalLocalAppData = $env:LOCALAPPDATA
    try {
        $env:LOCALAPPDATA = Join-Path $folder 'local-app-data'
        $path = Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json'
        $configPath = Join-Path $env:LOCALAPPDATA 'Typezero\ThemeEngine\font-windows-terminal.json'
        [IO.Directory]::CreateDirectory((Split-Path -Parent $path)) | Out-Null
        [IO.Directory]::CreateDirectory((Split-Path -Parent $configPath)) | Out-Null
        [IO.File]::WriteAllText($path, $SettingsText, [Text.UTF8Encoding]::new($false))
        $config = [ordered]@{ Version=2; Enabled=$false; ManualOverride=$null; Mappings=@{
            'fixture-b'=@{ Family=$fontB.face; Size=$fontB.size; Weight=$fontB.weight }
        } }
        [IO.File]::WriteAllText($configPath, ($config | ConvertTo-Json -Depth 8))
        $before = Get-DirectorySnapshot $path
        $records = [Collections.Generic.List[object]]::new()
        $failure = $null
        try { Set-Theme 'fixture-b' 6>&1 | ForEach-Object { $records.Add($_) } }
        catch { $failure = $_ }
        [pscustomobject]@{
            Path=$path; Error=$failure; Output=($records -join "`n")
            Result=@($records | Where-Object { $_.PSObject.Properties['Complete'] -and $_.PSObject.Properties['Targets'] })[-1]
            SettingsUnchanged=((Get-DirectorySnapshot $path) -ceq $before)
            HistoryUnchanged=(((Get-BytesSnapshot $CurrentFile) + ':' + (Get-BytesSnapshot $PreviousFile)) -ceq $historyBefore)
            CurrentWrites=$script:applyFixtureCurrentWrites
            Current=[IO.File]::ReadAllText($CurrentFile).Trim()
            Previous=[IO.File]::ReadAllText($PreviousFile).Trim()
        }
    }
    finally { $env:LOCALAPPDATA = $originalLocalAppData }
}

$schemeA = New-Scheme 'Typezero Fixture A' '#111122'
$schemeB = New-Scheme 'Typezero Fixture B' '#332211'
$chromeA = New-TerminalTheme $schemeA.background
$chromeB = New-TerminalTheme $schemeB.background
$fontA = [ordered]@{ face = 'Fixture Mono A'; size = 12.5; weight = 'normal' }
$fontB = [ordered]@{ face = 'Fixture Mono B'; size = 17; weight = 'semi-bold' }
$otherProfile = '{ "guid": "{11111111-1111-1111-1111-111111111111}", "name": "Other // profile", "font": {"face":"Keep Me","size":11,"weight":350}, "colorScheme":"Custom", "commandline":"echo https://example.test/a//b", }'
$defaults = '"defaults": { "font": {"face":"Default Mono", "size":10}, "opacity": 82, },'
$unrelatedScheme = '{ "name":"Custom", "background":"#abcdef", "foreground":"#fedcba", }'
$baseText = @'
{
  // Existing JSONC comments and spacing must remain, including Unicode: Netzach → Ω
  "$schema": "https://aka.ms/terminal-profiles-schema",
  "copyOnSelect" : false,
  "profiles": {
    __DEFAULTS__
    "list": [
      {
        "guid": "{574e775e-4f2a-5b96-ac1e-a2962a402336}",
        "name": "PowerShell (renamed by user)",
        "colorScheme": "Custom",
        "font": { "face": "Old Mono", "size": 11, "weight": 350, /* keep numeric weight until mapped */ "features": { "ss01": 1 }, "axes": { "wdth": 90 }, },
        "backgroundImage": "C:\\fixture\\unchanged.png",
      },
      __OTHER__
    ],
  },
  "schemes": [ __SCHEME__ ],
  "themes": [],
  "actions": [{ "command": "copy", "keys": "ctrl+shift+c" }],
}
'@
$baseText = $baseText.Replace('__DEFAULTS__', $defaults).Replace('__OTHER__', $otherProfile).Replace('__SCHEME__', $unrelatedScheme)
$baseText = ($baseText -replace "`r?`n", "`r`n") + "`r`n"

try {
    Invoke-Regression 'Two themes switch colors and complete font tuples A -> B -> A' {
        $path = New-SettingsFixture $baseText -Bom
        foreach ($choice in @(
            @{ Scheme = $schemeA; Chrome = $chromeA; Font = $fontA },
            @{ Scheme = $schemeB; Chrome = $chromeB; Font = $fontB },
            @{ Scheme = $schemeA; Chrome = $chromeA; Font = $fontA }
        )) {
            $before = Get-BytesSnapshot $path
            $result = Set-TypezeroWindowsTerminalAppearance -Path $path -Scheme $choice.Scheme -TerminalTheme $choice.Chrome -Font $choice.Font
            Assert-True $result.Changed 'Appearance switch reported no change.'
            Assert-True (Test-Path -LiteralPath $result.BackupPath -PathType Leaf) 'Appearance switch has no backup.'
            Assert-True ((Get-BytesSnapshot $result.BackupPath) -ceq $before) 'Backup does not contain exact previous bytes.'
            Assert-Appearance $path $choice.Scheme $choice.Font
            $text = [IO.File]::ReadAllText($path)
            foreach ($fragment in @($otherProfile, $defaults, $unrelatedScheme, '/* keep numeric weight until mapped */', '"features": { "ss01": 1 }', '"axes": { "wdth": 90 }', 'Netzach → Ω', '"copyOnSelect" : false')) {
                Assert-True ($text.Contains($fragment)) "Unrelated JSONC text changed: $fragment"
            }
            Assert-True (-not [regex]::IsMatch($text, '(?<!\r)\n')) 'CRLF formatting was replaced or mixed with LF.'
            $bytes = [IO.File]::ReadAllBytes($path)
            Assert-True ($bytes.Length -gt 3 -and $bytes[0] -eq 239 -and $bytes[1] -eq 187 -and $bytes[2] -eq 191) 'UTF-8 BOM was not preserved.'
        }
    }

    Invoke-Regression 'Missing font and missing defaults are supported without inventing defaults' {
        $text = '{"profiles":{"list":[{"guid":"' + $targetGuid + '","name":"Renamed shell"}]}}'
        $path = New-SettingsFixture $text
        $null = Set-TypezeroWindowsTerminalAppearance -Path $path -Scheme $schemeA -TerminalTheme $chromeA -Font $fontA
        Assert-Appearance $path $schemeA $fontA
        $settings = Read-SettingsFixture $path
        Assert-True (-not $settings.profiles.Contains('defaults')) 'Writer invented profile defaults.'
    }

    Invoke-Regression 'Partial font keeps user axes and adds the complete mapped tuple' {
        $text = '{"profiles":{"list":[{"guid":"' + $targetGuid + '","font": { "size": 9, "features": {"liga":0}, "axes": {"slnt":-4} }}]},"schemes":[],"themes":[]}'
        $path = New-SettingsFixture $text
        $null = Set-TypezeroWindowsTerminalAppearance -Path $path -Scheme $schemeB -TerminalTheme $chromeB -Font $fontB
        Assert-Appearance $path $schemeB $fontB
        $after = [IO.File]::ReadAllText($path)
        Assert-True ($after.Contains('"features": {"liga":0}') -and $after.Contains('"axes": {"slnt":-4}')) 'Partial font update changed feature/axis bytes.'
    }

    Invoke-Regression 'A theme without a mapping preserves existing font including numeric weight' {
        $path = New-SettingsFixture $baseText
        $fontFragment = '"font": { "face": "Old Mono", "size": 11, "weight": 350, /* keep numeric weight until mapped */ "features": { "ss01": 1 }, "axes": { "wdth": 90 }, }'
        $null = Set-TypezeroWindowsTerminalAppearance -Path $path -Scheme $schemeA -TerminalTheme $chromeA -Font $null
        Assert-Appearance $path $schemeA $null
        Assert-True ([IO.File]::ReadAllText($path).Contains($fontFragment)) 'Unmapped theme changed existing font bytes.'
    }

    Invoke-Regression 'Attached comments and escaped property names survive owned value replacement' {
        $text = @'
{
  "profiles": {"list":[{
    "gu\u0069d": "{574e775e-4f2a-5b96-ac1e-a2962a402336}",
    "font": {"f\u0061ce":"Old / { \" }", "size":11/*size comment*/, "weight":null//weight comment
    },
    "hidden":false/*unrelated Boolean comment*/,
    "commandline":"echo braces { } // slashes /* text */ and escaped \"quote\""
  }]},
  "schemes":[], "themes":[]
}
'@
        $path = New-SettingsFixture $text
        $null = Set-TypezeroWindowsTerminalAppearance -Path $path -Scheme $schemeA -TerminalTheme $chromeA -Font $fontA
        Assert-Appearance $path $schemeA $fontA
        $after = [IO.File]::ReadAllText($path)
        foreach ($fragment in @('/*size comment*/', '//weight comment', 'false/*unrelated Boolean comment*/', '"gu\u0069d"', '"f\u0061ce"', '"commandline":"echo braces { } // slashes /* text */ and escaped \"quote\""')) {
            Assert-True ($after.Contains($fragment)) "Attached comment or escaped JSONC text changed: $fragment"
        }
    }

    Invoke-Regression 'Owned named entries merge recursively while preserving other properties and comments' {
        $text = '{"profiles":{"list":[{"guid":"' + $targetGuid + '"}]},"schemes":[{"name":"Typezero Fixture A","background":"#000000",/* scheme keep */"customSchemeValue":42}],"themes":[{"name":"Typezero ThemeEngine","window":{"applicationTheme":"light", /* window keep */ "useMica":true},"tab":{"customTabValue":"keep"}}]}'
        $path = New-SettingsFixture $text
        $null = Set-TypezeroWindowsTerminalAppearance -Path $path -Scheme $schemeA -TerminalTheme $chromeA -Font $fontA
        Assert-Appearance $path $schemeA $fontA
        $settings = Read-SettingsFixture $path
        Assert-True ($settings.schemes[0].customSchemeValue -eq 42) 'Named scheme update removed an unrelated setting.'
        Assert-True ($settings.themes[0].window.useMica -eq $true -and $settings.themes[0].tab.customTabValue -ceq 'keep') 'Named chrome update removed an unrelated nested setting.'
        Assert-True ([IO.File]::ReadAllText($path).Contains('/* scheme keep */') -and [IO.File]::ReadAllText($path).Contains('/* window keep */')) 'Named entry comments were removed.'
    }

    Invoke-Regression 'Reapplying the same theme is byte-identical and creates no extra backup' {
        $path = New-SettingsFixture $baseText
        $null = Set-TypezeroWindowsTerminalAppearance -Path $path -Scheme $schemeA -TerminalTheme $chromeA -Font $fontA
        $before = Get-DirectorySnapshot $path
        $result = Set-TypezeroWindowsTerminalAppearance -Path $path -Scheme $schemeA -TerminalTheme $chromeA -Font $fontA
        Assert-True (-not $result.Changed) 'Idempotent update reported a change.'
        Assert-True ((Get-DirectorySnapshot $path) -ceq $before) 'Idempotent update changed settings bytes or created another backup.'
    }

    Invoke-Regression 'Restore recovers exact original bytes and rejects stale update/restore expectations' {
        $path = New-SettingsFixture $baseText -Bom
        $original = Get-BytesSnapshot $path
        $hash = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
        $result = Set-TypezeroWindowsTerminalAppearance -Path $path -Scheme $schemeA -TerminalTheme $chromeA -Font $fontA -ExpectedSha256 $hash
        $beforeReject = Get-DirectorySnapshot $path
        Assert-Throws { Set-TypezeroWindowsTerminalAppearance -Path $path -Scheme $schemeB -TerminalTheme $chromeB -Font $fontB -ExpectedSha256 $hash } 'Stale update expectation was accepted.'
        Assert-Throws { Restore-TypezeroWindowsTerminalAppearance -Path $path -BackupPath $result.BackupPath -ExpectedSha256 $hash } 'Stale restore expectation was accepted.'
        Assert-True ((Get-DirectorySnapshot $path) -ceq $beforeReject) 'Stale expectation wrote files.'
        $restored = Restore-TypezeroWindowsTerminalAppearance -Path $path -BackupPath $result.BackupPath -ExpectedSha256 $result.AfterSha256
        Assert-True $restored.Changed 'Restore reported no change.'
        Assert-True ((Get-BytesSnapshot $path) -ceq $original) 'Restore did not recover exact original bytes.'
    }

    Invoke-Regression 'Duplicate PowerShell targets fail before writing settings or backups' {
        $text = '{"profiles":{"list":[{"guid":"' + $targetGuid + '"},{"guid":"' + $targetGuid + '"}]}}'
        $path = New-SettingsFixture $text
        $before = Get-DirectorySnapshot $path
        Assert-Throws { Set-TypezeroWindowsTerminalAppearance -Path $path -Scheme $schemeA -TerminalTheme $chromeA -Font $fontA } 'Ambiguous profile target was accepted.'
        Assert-True ((Get-DirectorySnapshot $path) -ceq $before) 'Ambiguous target wrote files.'
    }

    Invoke-Regression 'Invalid JSONC fails before writing settings or backups' {
        $path = New-SettingsFixture '{"profiles":{"list":[}'
        $before = Get-DirectorySnapshot $path
        Assert-Throws { Set-TypezeroWindowsTerminalAppearance -Path $path -Scheme $schemeA -TerminalTheme $chromeA -Font $fontA } 'Invalid JSONC was accepted.'
        Assert-True ((Get-DirectorySnapshot $path) -ceq $before) 'Invalid JSONC wrote files.'
    }

    Invoke-Regression 'Actual ThemeEngine Terminal apply reads saved mappings and switches A -> B -> A' {
        # Extract only the actual Terminal apply functions, keeping their original
        # file-bound PSScriptRoot in a disposable copy. Do not invoke bootstrap,
        # Vim generation, native Windows appearance, wallpaper, or real settings.
        $engineFixture = Join-Path $root 'actual-engine-terminal-functions'
        [IO.Directory]::CreateDirectory($engineFixture) | Out-Null
        $tokens = $null
        $errors = $null
        $ast = [Management.Automation.Language.Parser]::ParseFile(
            (Join-Path $engineSource 'ThemeEngine.ps1'), [ref]$tokens, [ref]$errors)
        Assert-True ($errors.Count -eq 0) 'ThemeEngine source has syntax errors.'
        $definitions = foreach ($name in @('Get-WindowsTerminalSettingsPath', 'Set-WindowsTerminalTheme')) {
            $functions = @($ast.FindAll({
                param($node)
                $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -ceq $name
            }, $false))
            Assert-True ($functions.Count -eq 1) "Expected one actual engine function '$name'."
            $functions[0].Extent.Text
        }
        $wrapper = Join-Path $engineFixture 'TerminalApplyFunctions.ps1'
        [IO.File]::WriteAllText($wrapper, ($definitions -join "`r`n`r`n"), [Text.UTF8Encoding]::new($false))
        foreach ($module in @('FontMapping-WindowsTerminal.ps1', 'TerminalSettings-WindowsTerminal.ps1', 'FontWeights-WindowsTerminal.ps1')) {
            Copy-Item -LiteralPath (Join-Path $engineSource $module) -Destination $engineFixture
        }
        . $wrapper
        $originalLocalAppData = $env:LOCALAPPDATA
        try {
            $env:LOCALAPPDATA = Join-Path $engineFixture 'local-app-data'
            $path = Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json'
            $configPath = Join-Path $env:LOCALAPPDATA 'Typezero\ThemeEngine\font-windows-terminal.json'
            [IO.Directory]::CreateDirectory((Split-Path -Parent $path)) | Out-Null
            [IO.Directory]::CreateDirectory((Split-Path -Parent $configPath)) | Out-Null
            [IO.File]::WriteAllText($path, $baseText, [Text.UTF8Encoding]::new($true))
            $config = [ordered]@{
                Version = 2; Enabled = $false; ManualOverride = $null
                Mappings = [ordered]@{
                    'fixture-a' = [ordered]@{ Family=$fontA.face; Size=$fontA.size; Weight=$fontA.weight }
                    'fixture-b' = [ordered]@{ Family=$fontB.face; Size=$fontB.size; Weight=$fontB.weight }
                }
            }
            [IO.File]::WriteAllText($configPath, ($config | ConvertTo-Json -Depth 8), [Text.UTF8Encoding]::new($false))
            foreach ($choice in @(
                @{ Id='fixture-a'; Scheme=$schemeA; Font=$fontA },
                @{ Id='fixture-b'; Scheme=$schemeB; Font=$fontB },
                @{ Id='fixture-a'; Scheme=$schemeA; Font=$fontA }
            )) {
                Set-WindowsTerminalTheme (New-EngineTheme $choice.Id $choice.Scheme)
                Assert-Appearance $path $choice.Scheme $choice.Font
                Assert-True ([IO.File]::ReadAllText($path).Contains($otherProfile)) 'Engine apply changed another profile.'
            }
            $fontBefore = (Get-TargetProfile (Read-SettingsFixture $path)).font | ConvertTo-Json -Compress -Depth 10
            Set-WindowsTerminalTheme (New-EngineTheme 'fixture-unmapped' $schemeB)
            Assert-Appearance $path $schemeB $null
            $fontAfter = (Get-TargetProfile (Read-SettingsFixture $path)).font | ConvertTo-Json -Compress -Depth 10
            Assert-True ($fontAfter -ceq $fontBefore) 'Engine unmapped theme changed the existing font.'

            # Old mappings specify only the family. Their application must keep
            # the existing mapped size and weight, rather than guessing values.
            $v1 = [ordered]@{ Version=1; Enabled=$false; Mappings=@{ 'fixture-b'='Fixture Legacy Mono' } }
            [IO.File]::WriteAllText($configPath, ($v1 | ConvertTo-Json -Depth 8), [Text.UTF8Encoding]::new($false))
            Set-WindowsTerminalTheme (New-EngineTheme 'fixture-b' $schemeB)
            $legacy = [ordered]@{ face='Fixture Legacy Mono'; size=$fontA.size; weight=$fontA.weight }
            Assert-Appearance $path $schemeB $legacy
        }
        finally { $env:LOCALAPPDATA = $originalLocalAppData }
    }

    Invoke-Regression 'Native rejection and nonconfirmation still apply Terminal colors and saved font' {
        foreach ($nativeFailure in @('Native theme launch rejected.', 'Windows did not confirm theme within 30 seconds.')) {
            $result = Invoke-SetThemeFixture -NativeFailure $nativeFailure -SettingsText $baseText
            Assert-True ($null -eq $result.Error -and -not $result.Result.Complete -and $result.Result.Status -ceq 'Partial') 'Expected structured partial success after Terminal apply.'
            $desktop=@($result.Result.Targets | Where-Object Target -ceq 'Desktop')[0]
            Assert-True ($desktop.Status -ceq 'Failed' -and $desktop.Message.Contains($nativeFailure)) 'Original native error was lost.'
            Assert-True (@($result.Result.Targets | Where-Object { $_.Target -ceq 'Shell' -and $_.Status -ceq 'Applied' }).Count -eq 1) 'Independent Terminal success was not reported.'
            Assert-Appearance $result.Path $schemeB $fontB
            Assert-True ($result.Output.Contains('Windows Terminal font:') -and -not $result.Output.Contains('Applied theme:')) 'Terminal success or overall failure output is inaccurate.'
            Assert-True ($result.HistoryUnchanged -and $result.CurrentWrites -eq 0) 'Partial apply advanced current theme or history.'
        }
    }

    Invoke-Regression 'Actual Terminal failure remains explicit with or without native failure' {
        foreach ($nativeFailure in @('', 'Native theme launch rejected.')) {
            $result = Invoke-SetThemeFixture -NativeFailure $nativeFailure -SettingsText '{"profiles":{"list":[}'
            Assert-True ($null -eq $result.Error -and -not $result.Result.Complete) 'Terminal failure became a complete result.'
            Assert-True (@($result.Result.Targets | Where-Object { $_.Target -ceq 'Shell' -and $_.Status -ceq 'Failed' }).Count -eq 1) 'Terminal failure was not identified by target.'
            $desktop=@($result.Result.Targets | Where-Object Target -ceq 'Desktop')[0]
            if ($nativeFailure) {
                Assert-True ($desktop.Status -ceq 'Failed' -and $desktop.Message.Contains($nativeFailure)) 'Combined failure lost the native error.'
            } else {
                Assert-True ($desktop.Status -ceq 'Applied') 'Terminal-only failure was replaced with a native error.'
            }
            Assert-True ($result.SettingsUnchanged -and $result.HistoryUnchanged -and $result.CurrentWrites -eq 0) 'Failed Terminal apply changed settings, backups, current theme or history.'
            Assert-True (-not $result.Output.Contains('Windows Terminal font:') -and -not $result.Output.Contains('Applied theme:')) 'Failed Terminal apply printed success.'
        }
    }

    Invoke-Regression 'Incomplete Terminal palette is accurately failed after native rejection' {
        $result = Invoke-SetThemeFixture -NativeFailure 'Native theme launch rejected.' -SettingsText $baseText -IncompletePalette
        Assert-True ($null -eq $result.Error -and -not $result.Result.Complete -and @($result.Result.Targets | Where-Object { $_.Target -ceq 'Shell' -and $_.Status -ceq 'Failed' }).Count -eq 1) 'Incomplete Terminal palette was reported as fully applied.'
        Assert-True ($result.SettingsUnchanged -and $result.HistoryUnchanged -and $result.CurrentWrites -eq 0) 'Skipped Terminal apply changed settings or theme history.'
    }

    Invoke-Regression 'Confirmed native and Terminal apply retain full success and history behavior' {
        $result = Invoke-SetThemeFixture -SettingsText $baseText
        Assert-True ($null -eq $result.Error -and $result.Result.Complete) "Complete apply failed: $($result.Error)"
        Assert-Appearance $result.Path $schemeB $fontB
        Assert-True ($result.CurrentWrites -eq 1 -and $result.Current -ceq 'fixture-b' -and $result.Previous -ceq 'fixture-a') 'Complete apply did not update current theme and history.'
        Assert-True ($result.Output.Contains('Applied theme: Fixture B')) 'Complete apply no longer reports success.'
    }
}
finally {
    Write-Host "Disposable fixtures retained: $root"
}
Write-Host "Passed $script:passed focused Terminal appearance regressions."
