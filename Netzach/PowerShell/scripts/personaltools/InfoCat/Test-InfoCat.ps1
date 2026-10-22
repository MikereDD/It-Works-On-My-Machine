#Requires -Version 7.0
<#
.SYNOPSIS
    Read-only InfoCat v2.0 release candidate regression preflight (no profile edits/installation).
#>
[CmdletBinding()]
param([switch]$Render, [switch]$HardwareProbe, [switch]$Compact)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $PSCommandPath
$target = Join-Path (Split-Path -Parent $here) 'infocat.ps1'
$baseline = Join-Path $here 'infocat-v1.4.2-original.ps1'

$tokens = $null
$parseErrors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile(
    $target, [ref]$tokens, [ref]$parseErrors
)
if ($parseErrors.Count -gt 0) {
    foreach ($err in $parseErrors) { Write-Host "FAIL: $err" -ForegroundColor Red }
    throw 'InfoCat PowerShell syntax validation failed.'
}
Write-Host 'PASS: PowerShell syntax.' -ForegroundColor Green

$commands = @($ast.FindAll({
    param($node)
    $node -is [System.Management.Automation.Language.CommandAst] -and
    $node.GetCommandName() -eq 'fastfetch'
}, $true))
if ($commands.Count -ne 0) { throw 'InfoCat must not invoke Fastfetch.' }
Write-Host 'PASS: No Fastfetch command dependency.' -ForegroundColor Green

$updated = Get-Content -Raw -LiteralPath $target
$original = Get-Content -Raw -LiteralPath $baseline
$pattern = '(?s)\$catArt\s*=\s*@''\r?\n(.*?)\r?\n''@\s*-split'
$oldArt = [regex]::Match($original, $pattern)
$newArt = [regex]::Match($updated, $pattern)
# Normalize only line endings, never whitespace, case, punctuation, or art content.
$oldBytes = $oldArt.Groups[1].Value -replace "`r`n", "`n" -replace "`r", "`n"
$newBytes = $newArt.Groups[1].Value -replace "`r`n", "`n" -replace "`r", "`n"
if (-not $oldArt.Success -or -not $newArt.Success -or $oldBytes -cne $newBytes) {
    throw 'Original InfoCat artwork was changed.'
}
Write-Host 'PASS: Original cat artwork unchanged (CRLF/LF normalized).' -ForegroundColor Green

foreach ($name in @(
    'Get-PrimaryIPv4', 'Get-InstalledAppCount', 'Get-WindowsTheme',
    'Get-DisplayDetails', 'Get-DisplayRefreshRates', 'Get-BatterySummary',
    'Get-DefaultPlaybackDevice', 'Get-PageFileSummary', 'Get-GpuRows',
    'Get-DisplayMetadata', 'Get-DxgiAdapters',
    'Split-InfoCatText', 'Expand-InfoCatRows', 'Get-InfoCatTerminalWidth',
    'Get-InfoCatWindowsThemeInfo', 'Get-InfoCatWindowsBuild',
    'Read-InfoCatJsonc', 'Get-InfoCatWindowsTerminalFont',
    'Get-InfoCatCpuPerformanceFrequency', 'Get-InfoCatNetworkRows',
    'Get-InfoCatLayout', 'Invoke-InfoCatProbe',
    'Get-InfoCatCpuNative', 'ConvertTo-InfoCatCpuRegistryValues', 'Get-InfoCatNetworkRowsFast', 'Get-InfoCatInterfaceKind'
)) {
    if ($updated -notmatch "function\s+$name\b") { throw "Missing feature: $name" }
}
foreach ($marker in @(
    'GetDefaultAudioEndpoint', 'PKEY_Device_FriendlyName',
    'GetSystemPowerStatus', 'QueryDisplayConfig', 'GetDisplayConfigBufferSizes',
    'EnumDisplaySettingsW', 'CreateDXGIFactory1', 'GetAdapters',
    'GET_ADVANCED_COLOR_INFO', 'GET_TARGET_NAME', 'Win32_Processor',
    'Windows NT\CurrentVersion', 'ColorizationColor', 'WT_PROFILE_ID',
    'JsonDocumentOptions', 'ProcessorFrequency', 'Get-NetAdapter',
    'GetLogicalProcessorInformationEx', 'GetSystemCpuSetInformation',
    'GetAllNetworkInterfaces'
)) {
    if (-not $updated.Contains($marker)) { throw "Missing native API: $marker" }
}
Write-Host 'PASS: Original and v2.0 RC native APIs/layout helpers present.' -ForegroundColor Green

# PowerShell parser success does not imply the embedded C# interop can compile.
# Compile all seven native helpers *in memory*; preflight does not call APIs.
$interopTypes = @('InfoCatDisplayConfig', 'InfoCatMonitorMetadata',
                  'InfoCatWin32Display', 'InfoCatPowerStatus',
                  'InfoCatDxgi', 'InfoCatAudioEndpoint', 'InfoCatCpuTopologyV182')
$interopMatches = [regex]::Matches(
    $updated, '(?s)Add-Type -ErrorAction Stop -TypeDefinition @''\r?\n(.*?)\r?\n''@'
)
if ($interopMatches.Count -ne $interopTypes.Count) {
    throw "Expected seven native helper definitions; got $($interopMatches.Count)."
}
for ($i = 0; $i -lt $interopMatches.Count; $i++) {
    if (-not ($interopTypes[$i] -as [type])) {
        Add-Type -TypeDefinition $interopMatches[$i].Groups[1].Value -ErrorAction Stop
    }
}
Write-Host 'PASS: Native Windows interop helpers compile in memory.' -ForegroundColor Green
if (-not [InfoCatCpuTopologyV182]::SelfTestRecordParsers()) {
    throw 'Native CPU topology record parser synthetic fixture failed.'
}
Write-Host 'PASS: Native CPU topology parser synthetic fixtures.' -ForegroundColor Green

# Synthetic values matching NETZACH's known registry types, including the
# erroneous REG_BINARY case. No real registry access in this unit test.
$registryParserAst = @($ast.FindAll({
    param($node)
    $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
    $node.Name -eq 'ConvertTo-InfoCatCpuRegistryValues'
}, $true)) | Select-Object -First 1
if (-not $registryParserAst) { throw 'Missing CPU registry value validator.' }
. ([scriptblock]::Create($registryParserAst.Extent.Text))
$fixtureCpu = ConvertTo-InfoCatCpuRegistryValues `
    -RawName ' Intel(R)  Core(TM) Ultra 9 185H ' -RawMHz ([int]3072)
if ($fixtureCpu.Name -cne 'Intel(R) Core(TM) Ultra 9 185H' -or
    $fixtureCpu.MaxClockSpeed -ne 3072) {
    throw 'CPU registry name/MHz normalization failed.'
}
$binaryMHz = ConvertTo-InfoCatCpuRegistryValues -RawName 'Test CPU' `
    -RawMHz ([byte[]]@(1, 2, 3, 4))
if ($binaryMHz.Name -cne 'Test CPU' -or $binaryMHz.MaxClockSpeed -ne 0) {
    throw 'Unexpected conversion of binary CPU registry MHz metadata.'
}
$invalidName = ConvertTo-InfoCatCpuRegistryValues `
    -RawName ([byte[]]@(65, 66)) -RawMHz ([int]3072)
if ($invalidName.Name -or $invalidName.MaxClockSpeed -ne 3072) {
    throw 'Invalid registry CPU model was incorrectly accepted.'
}
$missingMHz = ConvertTo-InfoCatCpuRegistryValues -RawName 'Test CPU' -RawMHz $null
if ($missingMHz.Name -cne 'Test CPU' -or $missingMHz.MaxClockSpeed -ne 0) {
    throw 'Missing optional registry MHz incorrectly invalidated CPU model.'
}
$cpuFn = @($ast.FindAll({
    param($node)
    $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
    $node.Name -eq 'Get-InfoCatCpuNative'
}, $true)) | Select-Object -First 1
if (-not $cpuFn -or
    $cpuFn.Extent.Text -notmatch 'LocalMachine\.OpenSubKey' -or
    @($cpuFn.FindAll({ param($node)
        $node -is [System.Management.Automation.Language.CommandAst] -and
        $node.GetCommandName() -eq 'Get-ItemProperty'
    }, $true)).Count -gt 0) {
    throw 'Native CPU registry access must read individual values through managed APIs.'
}
Write-Host 'PASS: Managed registry CPU values validated without enumerating binary metadata.' -ForegroundColor Green

# Check the pure wrapping algorithm at narrow and normal value widths.
$splitFn = @($ast.FindAll({
    param($node)
    $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
    $node.Name -eq 'Split-InfoCatText'
}, $true)) | Select-Object -First 1
if (-not $splitFn) { throw 'Missing splitter AST.' }
. ([scriptblock]::Create($splitFn.Extent.Text))
$sample = 'LG ULTRAGEAR - 2560x1440 @ 240 Hz [Primary] [Advanced Color: Available]'
foreach ($width in @(22, 38, 53, 80)) {
    $lines = @(Split-InfoCatText -Text $sample -Width $width)
    if (@($lines | Where-Object { $_.Length -gt $width }).Count -gt 0) {
        throw "Wrapping exceeded $width columns."
    }
    if (($lines -join ' ') -cne $sample) {
        throw "Wrapping changed content at width $width."
    }
}
Write-Host 'PASS: Native display row wrapping keeps full content within column widths.' -ForegroundColor Green

# Interface type alone is insufficient: VPN drivers can look like Ethernet.
$kindFn = @($ast.FindAll({
    param($node)
    $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
    $node.Name -eq 'Get-InfoCatInterfaceKind'
}, $true)) | Select-Object -First 1
if (-not $kindFn) { throw 'Missing network classifier AST.' }
. ([scriptblock]::Create($kindFn.Extent.Text))
$cases = @(
    @{ Alias='Ethernet'; Desc='Realtek PCIe Ethernet Controller'; Type='Ethernet'; Kind='LAN' },
    @{ Alias='Wi-Fi'; Desc='Intel Wireless 802.11ax'; Type='Wireless80211'; Kind='Wi-Fi' },
    @{ Alias='ProtonVPN'; Desc='WireGuard Tunnel'; Type='Ethernet'; Kind='VPN' },
    @{ Alias='vEthernet (WSL)'; Desc='Hyper-V Virtual Ethernet Adapter'; Type='Ethernet'; Kind=$null },
    @{ Alias='Bluetooth PAN'; Desc='Bluetooth Device'; Type='Ethernet'; Kind=$null }
)
foreach ($c in $cases) {
    $got = Get-InfoCatInterfaceKind -Alias $c.Alias -Description $c.Desc -InterfaceType $c.Type
    if ($got -cne $c.Kind) { throw "Network classifier mismatched $($c.Alias): got '$got', expected '$($c.Kind)'" }
}
Write-Host 'PASS: VPN/physical/virtual network classification fixture.' -ForegroundColor Green


# Test deterministic width selection separately from screen/console state.
$layoutFn = @($ast.FindAll({
    param($node)
    $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
    $node.Name -eq 'Get-InfoCatLayout'
}, $true)) | Select-Object -First 1
if (-not $layoutFn) { throw 'Missing layout AST.' }
. ([scriptblock]::Create($layoutFn.Extent.Text))
foreach ($width in @(24, 30, 44, 45, 65, 87, 88, 89, 90, 91, 120, 180)) {
    $layout = Get-InfoCatLayout -TerminalWidth $width
    if ($layout.Stacked -ne ($width -lt 91) -or
        $layout.ShowArt -ne ($width -ge 45)) {
        throw "Unexpected layout mode at $width columns."
    }
    $prefix = if ($layout.Stacked) { 17 } else { 69 }
    if (($prefix + $layout.ValueWidth) -gt $width) {
        throw "Detail text exceeds $width terminal columns."
    }
}
Write-Host 'PASS: Narrow/stacked/wide terminal layouts stay in bounds.' -ForegroundColor Green

# Release-candidate presentation tests: preserve the OEM name, remove only
# genuinely repeated prefixes, and leave Windows/ThemeEngine accents distinct.
$machineFn = @($ast.FindAll({
    param($node)
    $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
    $node.Name -eq 'Format-InfoCatMachineName'
}, $true)) | Select-Object -First 1
if (-not $machineFn) { throw 'Missing machine-name normalizer.' }
. ([scriptblock]::Create($machineFn.Extent.Text))
$machineCases = @(
    @{ Manufacturer='Alienware'; Model='Alienware m16 R2'; Expected='Alienware m16 R2' },
    @{ Manufacturer='Dell Inc.'; Model='Precision 5680'; Expected='Dell Inc. Precision 5680' },
    @{ Manufacturer='LENOVO'; Model='Lenovo Legion 7'; Expected='Lenovo Legion 7' },
    @{ Manufacturer='HP'; Model='HP-Spectre'; Expected='HP-Spectre' },
    @{ Manufacturer=''; Model='Custom Workstation'; Expected='Custom Workstation' },
    @{ Manufacturer=''; Model=''; Expected='Unknown' }
)
foreach ($case in $machineCases) {
    $actual = Format-InfoCatMachineName -Manufacturer $case.Manufacturer -Model $case.Model
    if ($actual -cne $case.Expected) {
        throw ('Machine name mismatch for {0}/{1}: {2}' -f $case.Manufacturer,$case.Model,$actual)
    }
}
if ($updated -notmatch "Label\s*=\s*'Windows Accent'" -or
    $updated -match "Label\s*=\s*'Accent'" -or
    $updated -notmatch 'PadRight\(15\)' -or
    $updated -notmatch '\$labelColumn\s*=\s*17') {
    throw 'Windows accent differentiation / fifteen-column label geometry invalid.'
}
Write-Host 'PASS: Machine-name deduplication and Windows Accent label geometry.' -ForegroundColor Green


# Benchmark output is opt-in, and the collector wrapper must preserve pipeline results.
$timerFn = @($ast.FindAll({
    param($node)
    $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
    $node.Name -eq 'Invoke-InfoCatProbe'
}, $true)) | Select-Object -First 1
if (-not $timerFn) { throw 'Missing timing helper AST.' }
. ([scriptblock]::Create($timerFn.Extent.Text))
$script:InfoCatTimings = [ordered]@{}
$Timing = $true
$timedResult = Invoke-InfoCatProbe -Name 'Synthetic fixture' -Script { 42 }
if ($timedResult -ne 42 -or
    -not $script:InfoCatTimings.Contains('Synthetic fixture') -or
    [double]$script:InfoCatTimings['Synthetic fixture'] -lt 0) {
    throw 'Probe timing wrapper changed results or failed to time a collector.'
}
Write-Host 'PASS: Optional timing wrapper preserves data and measures duration.' -ForegroundColor Green

# Compacted view should guard known expensive collectors and keep full as default.
$parameters = @($ast.ParamBlock.Parameters | ForEach-Object { $_.Name.VariablePath.UserPath })
foreach ($p in @('NoColor', 'Compact', 'Timing', 'Palette', 'ThemeRoot')) {
    if ($p -notin $parameters) { throw "Missing expected script option: $p" }
}
if ($updated -notmatch 'if\s*\(\s*-not\s+\$Compact\s*\)' -or
    $updated -notmatch 'if\s*\(\s*\$Compact\s*\)' -or
    $updated -notmatch "'Installed apps'" -or
    $updated -notmatch "'Displays'" -or
    $updated -notmatch "'GPU memory'") {
    throw 'Compact/full branch or collector instrumentation is missing.'
}
Write-Host 'PASS: Compact/full options and guarded collectors present.' -ForegroundColor Green

# Validate JSONC comments/trailing commas without accessing any live WT settings.
$readerAst = @($ast.FindAll({
    param($node)
    $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
    $node.Name -eq 'Read-InfoCatJsonc'
}, $true)) | Select-Object -First 1
if (-not $readerAst) { throw 'Missing JSONC reader AST.' }
. ([scriptblock]::Create($readerAst.Extent.Text))
$fixture = Join-Path $here 'WindowsTerminal-settings-sample.jsonc'
$parsedFixture = Read-InfoCatJsonc -Path $fixture
if ($parsedFixture['profiles']['defaults']['font']['face'] -cne 'JetBrainsMono Nerd Font' -or
    $parsedFixture['profiles']['list'][0]['guid'] -ne '{aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa}') {
    throw 'Windows Terminal JSONC fixture parse or font inheritance data failed.'
}
Write-Host 'PASS: Windows Terminal JSONC fixture (comments + trailing commas).' -ForegroundColor Green

# Guard against treating comment-like content inside quoted values as comments.
$trickyFixture = Join-Path $here 'WindowsTerminal-settings-strings-sample.jsonc'
$tricky = Read-InfoCatJsonc -Path $trickyFixture
if ($tricky['homepage'] -cne 'https://example.invalid//not-a-comment' -or
    $tricky['note'] -cne 'literal /* text */ and // text' -or
    $tricky['profiles']['defaults']['font']['face'] -cne 'JetBrainsMono Nerd Font') {
    throw 'Windows Terminal JSONC quoted-string regression failed.'
}
Write-Host 'PASS: JSONC keeps comment-like text inside strings.' -ForegroundColor Green

# Check that the build formatter has a safe fallback if UBR is missing.
$buildFn = @($ast.FindAll({
    param($node)
    $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
    $node.Name -eq 'Get-InfoCatWindowsBuild'
}, $true)) | Select-Object -First 1
$firstValueFn = @($ast.FindAll({
    param($node)
    $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
    $node.Name -eq 'Get-FirstValue'
}, $true)) | Select-Object -First 1
if (-not $buildFn -or -not $firstValueFn) { throw 'Missing build helpers.' }
. ([scriptblock]::Create($firstValueFn.Extent.Text))
. ([scriptblock]::Create($buildFn.Extent.Text))
$fakeOS = [pscustomobject]@{ BuildNumber = '26300'; Version = '10.0.26300' }
$version = Get-InfoCatWindowsBuild -OperatingSystem $fakeOS
if ($version.Build -notmatch '^26300(\.\d+)?$' -or
    $version.Kernel -notmatch '^10\.0\.26300(\.\d+)?$') {
    throw 'Windows build formatter returned invalid result.'
}
Write-Host 'PASS: Windows build/revision formatting and fallback.' -ForegroundColor Green


# ThemeEngine contract tests. Load only pure helper function ASTs, not the script
# itself: no live theme applications, profile imports or Windows modifications.
foreach ($name in @(
    'Resolve-InfoCatThemeId', 'Get-InfoCatBuiltInPalette',
    'Read-InfoCatThemeConf', 'Get-InfoCatActivePalette',
    'Get-InfoCatColorLuminance', 'Get-InfoCatReadableMuted', 'Get-InfoCatAnsiHex'
)) {
    $functionNode = @($ast.FindAll({ param($node)
        $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
        $node.Name -eq $name
    }, $true)) | Select-Object -First 1
    if (-not $functionNode) { throw "Missing palette helper: $name" }
    . ([scriptblock]::Create($functionNode.Extent.Text))
}
$themeFixtureRoot = Join-Path $here 'ThemeEngine-fixture'
$autoPalette = Get-InfoCatActivePalette -Requested Auto -Root $themeFixtureRoot `
    -WindowsThemeName 'Typezero-onedark'
if ($autoPalette.Id -cne 'nord' -or $autoPalette.Source -cne 'ThemeEngine' -or
    $autoPalette.ACCENT -cne '#81A1C1') {
    throw 'InfoCat did not follow active ThemeEngine current-theme.'
}
$manualPalette = Get-InfoCatActivePalette -Requested 'Gruvbox Dark' -Root $themeFixtureRoot `
    -WindowsThemeName 'Typezero-onedark'
if ($manualPalette.Id -cne 'gruvbox' -or $manualPalette.Source -cne 'ThemeEngine' -or
    $manualPalette.BRIGHT -cne '#FBF1C7') {
    throw 'Explicit ThemeEngine theme override failed.'
}
$themeFallback = Get-InfoCatActivePalette -Requested 'OLED Black' -Root $themeFixtureRoot
if ($themeFallback.Id -cne 'oled-black' -or $themeFallback.Source -cne 'built-in') {
    throw 'Standalone fallback palette unavailable.'
}
$invalidPalette = Read-InfoCatThemeConf -Root $themeFixtureRoot -Id 'invalid'
$traversal = Read-InfoCatThemeConf -Root $themeFixtureRoot -Id '..\\..\\Windows'
if ($null -ne $invalidPalette -or $null -ne $traversal) {
    throw 'Invalid or unsafe theme.conf accepted.'
}
# Without an installed theme and without a recognized Windows theme, preserve
# the legacy ANSI appearance exactly rather than guessing.
$legacy = Get-InfoCatActivePalette -Requested Auto -Root (Join-Path $here 'none-installed') `
    -WindowsThemeName 'Custom Unrelated Theme'
if ($null -ne $legacy) { throw 'Unrecognized Windows theme should use legacy ANSI fallback.' }
$windowsOnly = Get-InfoCatActivePalette -Requested Windows -Root $themeFixtureRoot `
    -WindowsThemeName 'Typezero-onedark'
if ($windowsOnly.Id -cne 'onedark' -or $windowsOnly.Source -cne 'built-in') {
    throw 'Explicit Windows override must ignore installed ThemeEngine current-theme.'
}
if ((Get-InfoCatReadableMuted -Muted '#4C566A' -Text '#D8DEE9' -Background '#2E3440') -cnotmatch '^#[0-9A-F]{6}$') {
    throw 'Contrast-corrected muted palette color invalid.'
}
$NoColor = $true
if (Get-InfoCatAnsiHex '#88C0D0') { throw 'NoColor should suppress true-color ANSI.' }
$NoColor = $false
Write-Host 'PASS: ThemeEngine auto/explicit selection, built-ins, invalid input, and NoColor.' -ForegroundColor Green

# Parser-based read-only policy for the script itself; rendering uses only GET APIs.
$denied = @('Remove-Item', 'Set-Item', 'Set-ItemProperty', 'New-Item',
            'Stop-Process', 'Start-Process', 'Invoke-Expression')
foreach ($command in @($ast.FindAll({
    param($node)
    $node -is [System.Management.Automation.Language.CommandAst]
}, $true))) {
    if ($command.GetCommandName() -in $denied) {
        throw "Unexpected modifying command: $($command.GetCommandName())"
    }
}
Write-Host 'PASS: No modifying commands in InfoCat script.' -ForegroundColor Green
Write-Host 'PASS: Preflight made no profile or Windows setting changes.' -ForegroundColor Green

if ($HardwareProbe) {
    # Optional active probes. Absence of an API result is reported, not faked.
    $adapters = @([InfoCatDxgi]::GetAdapters())
    if ($adapters.Count -gt 0) {
        Write-Host "PASS: DXGI enumerated $($adapters.Count) hardware GPU(s)." -ForegroundColor Green
        foreach ($gpu in $adapters) {
            Write-Host ('  GPU: {0} / dedicated {1:N0} bytes' -f $gpu.Name, $gpu.DedicatedBytes)
        }
    } else {
        Write-Warning 'DXGI returned no GPU adapters: InfoCat will show GPU names without memory.'
    }
    $displays = [InfoCatMonitorMetadata]::GetMetadata()
    if ($displays.Count -gt 0) {
        Write-Host "PASS: DisplayConfig enumerated $($displays.Count) active display source(s)." -ForegroundColor Green
        foreach ($entry in $displays.GetEnumerator()) {
            $d = $entry.Value
            Write-Host ('  Display: {0} / {1} / advanced color known={2} supported={3} enabled={4}' -f `
                $entry.Key, $d.FriendlyName, $d.ColorKnown, $d.ColorSupported, $d.ColorEnabled)
        }
    } else {
        Write-Warning 'DisplayConfig provided no monitor metadata: InfoCat will keep resolution/rate rows.'
    }
    foreach ($name in @('Get-WindowsTheme', 'Get-InfoCatWindowsThemeInfo', 'Get-InfoCatWindowsTerminalFont',
        'Get-InfoCatCpuPerformanceFrequency', 'Get-InfoCatNetworkRows',
        'ConvertTo-InfoCatCpuRegistryValues', 'Get-InfoCatCpuNative', 'Get-InfoCatNetworkRowsFast')) {
        $fn = @($ast.FindAll({
            param($node)
            $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
            $node.Name -eq $name
        }, $true)) | Select-Object -First 1
        . ([scriptblock]::Create($fn.Extent.Text))
    }
    $themeInfo = Get-InfoCatWindowsThemeInfo
    Write-Host ("INFO: Windows theme {0} / mode {1} / accent {2}" -f `
        $themeInfo.Name, $themeInfo.Mode, $themeInfo.Accent)
    $font = Get-InfoCatWindowsTerminalFont
    if ($font) { Write-Host "PASS: Active Windows Terminal profile font: $font" -ForegroundColor Green }
    else { Write-Warning 'Active Terminal profile font unavailable; optional font row will be omitted.' }
    $perf = Get-InfoCatCpuPerformanceFrequency
    if ($perf) { Write-Host "INFO: CPU performance frequency: $perf" }
    else { Write-Warning 'CPU perf frequency unavailable; optional row will be omitted.' }
    $network = @(Get-InfoCatNetworkRows -FallbackLAN 'None')
    foreach ($row in $network) { Write-Host ("INFO: Network {0}: {1}" -f $row.Label, $row.Value) }
    $cpuDiag = Get-InfoCatCpuNative -Diagnostics
    Write-Host ('INFO: CPU native API: {0}; {1}' -f $cpuDiag.Method, $cpuDiag.ApiDetails)
    Write-Host ('INFO: CPU registry: {0}' -f $cpuDiag.RegistryDetails)
    if ($cpuDiag.Usable) {
        Write-Host ('PASS: Native CPU: {0}, {1}C/{2}T, registry {3} MHz' -f `
            $cpuDiag.Name, $cpuDiag.NumberOfCores, `
            $cpuDiag.NumberOfLogicalProcessors, $cpuDiag.MaxClockSpeed) -ForegroundColor Green
        $cimCpu = Get-CimInstance Win32_Processor -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($cimCpu -and ($cpuDiag.NumberOfCores -ne $cimCpu.NumberOfCores -or `
            $cpuDiag.NumberOfLogicalProcessors -ne $cimCpu.NumberOfLogicalProcessors)) {
            Write-Warning 'Native CPU topology differs from CIM. Do not promote until investigated.'
        }
    } else {
        Write-Warning ('Native CPU probe unavailable ({0}); CIM fallback will be used.' -f $cpuDiag.Reason)
    }
    $networkFast = @(Get-InfoCatNetworkRowsFast)
    if ($networkFast.Count -gt 0) {
        foreach ($row in $networkFast) {
            Write-Host ("PASS: Fast network {0}: {1}" -f $row.Label, $row.Value) -ForegroundColor Green
        }
        foreach ($kind in @('LAN', 'Wi-Fi', 'VPN')) {
            $slowRow = $network | Where-Object Label -eq $kind | Select-Object -First 1
            $fastRow = $networkFast | Where-Object Label -eq $kind | Select-Object -First 1
            if ($slowRow -and $fastRow -and `
                (($slowRow.Value -split ' ')[0] -cne ($fastRow.Value -split ' ')[0])) {
                Write-Warning "Fast $kind IP differs from NetAdapter result; investigate before promoting."
            }
        }
    } else {
        Write-Warning 'Fast network enumeration unavailable; NetAdapter fallback will be used.'
    }
}
if ($Render) {
    Write-Host '=== INFOCAT 1.9 THEME PREVIEW ==='
    & $target -Compact:$Compact
}
