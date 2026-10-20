# Synthetic snapshots and inert legacy provider stubs only. Never invokes live writers.
[CmdletBinding()]
param([string]$FixtureParent = [IO.Path]::GetTempPath())
$ErrorActionPreference = 'Stop'
$engine = Split-Path -Parent $PSScriptRoot
foreach ($name in @('TerminalReplace-WindowsTerminal.ps1','FontWriter-WindowsTerminal.ps1',
    'FontActivationReadinessV2-WindowsTerminal.ps1','FontActivationV2-WindowsTerminal.ps1')) {
    . (Join-Path $engine $name)
}
$root = Join-Path $FixtureParent ('typezero-readiness-v2-' + [guid]::NewGuid().ToString('N'))
$null = [IO.Directory]::CreateDirectory($root)
$configPath = Join-Path $root 'font-windows-terminal.json'
$settingsPath = Join-Path $root 'settings.json'
$utf8 = [Text.UTF8Encoding]::new($false)
$script:checks = 0
function Assert-Test([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw "FAIL: $Message" }
}
function Get-Inventory {
    @((Get-ChildItem -LiteralPath $root -Recurse -Force | Sort-Object FullName | ForEach-Object {
        if ($_.PSIsContainer) { $_.FullName } else {
            $_.FullName + '|' + (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash
        }
    })) -join "`n"
}
function Invoke-Check([string]$Name, [scriptblock]$Action) {
    & $Action
    $script:checks++
    Write-Host "PASS [$script:checks] $Name"
}
function Assert-ReadOnlyRefusal([scriptblock]$Action) {
    $before = Get-Inventory
    $refused = $false
    try { & $Action | Out-Null } catch { $refused = $true }
    Assert-Test $refused 'Malformed/stale input was accepted.'
    Assert-Test ((Get-Inventory) -ceq $before) 'Refusal modified files or directories.'
}
function Write-Config([string]$Json) { [IO.File]::WriteAllText($configPath, $Json, $utf8) }
function Invoke-Readiness {
    Get-TypezeroTerminalFontActivationReadinessV2 -ThemeId gruvbox -ConfigPath $configPath -SettingsPath $settingsPath @args
}
$valid = '{"Version":2,"Enabled":false,"ManualOverride":null,"Mappings":{"gruvbox":{"family":"Fixture Font","size":14.25,"weight":"semi-bold"}}}'
$settings = '{"profiles":{"defaults":{},"list":[{"guid":"{574e775e-4f2a-5b96-ac1e-a2962a402336}","name":"PowerShell"}]},"unrelated":[1,2,3]}'
Write-Config $valid
[IO.File]::WriteAllText($settingsPath, $settings, $utf8)

Invoke-Check 'Selected V2 preference and full snapshot hashes are read without effects' {
    $before = Get-Inventory
    $result = Invoke-Readiness
    Assert-Test ($result.Status -ceq 'BLOCKED' -and $result.Preference.Family -ceq 'Fixture Font' -and
        $result.Preference.Size -eq 14.25 -and $result.Preference.Weight -ceq 'semi-bold') 'Wrong selected preference.'
    Assert-Test ($result.ConfigSha256 -ceq (Get-FileHash $configPath -Algorithm SHA256).Hash -and
        $result.SettingsSha256 -ceq (Get-FileHash $settingsPath -Algorithm SHA256).Hash) 'Snapshot hash mismatch.'
    Assert-Test ($result.Blockers -ccontains 'INTEGRATION_DISABLED') 'Disabled integration was omitted.'
    Assert-Test ((Get-Inventory) -ceq $before) 'Readiness changed fixture bytes/tree.'
}
Invoke-Check 'Enabled mappings never authorize live activation or recovery' {
    foreach ($enabled in @('false','true')) {
        Write-Config ($valid.Replace('"Enabled":false', '"Enabled":' + $enabled))
        $before = Get-Inventory
        $result = Invoke-Readiness
        Assert-Test ($result.ReadOnly -and -not $result.SettingsChanged -and -not $result.FontActivated -and
            -not $result.RecoveryAllowed -and -not $result.RecoveryAuthorized -and
            -not $result.ReplayProtectionEstablished -and -not $result.LiveActivationAuthorized -and
            $result.OperationPhase -ceq 'UNKNOWN' -and $result.Blockers.Count -ge 4) 'Readiness granted authority.'
        Assert-Test ((Get-Inventory) -ceq $before) 'Enabled readiness wrote files.'
    }
    Write-Config $valid
}
Invoke-Check 'Expected hashes bind the saved selection and settings snapshot' {
    $configHash = (Get-FileHash $configPath -Algorithm SHA256).Hash
    $settingsHash = (Get-FileHash $settingsPath -Algorithm SHA256).Hash
    $result = Get-TypezeroTerminalFontActivationReadinessV2 -ThemeId gruvbox -ConfigPath $configPath `
        -SettingsPath $settingsPath -ExpectedConfigSha256 $configHash.ToLowerInvariant() -ExpectedSettingsSha256 $settingsHash
    Assert-Test ($result.Status -ceq 'BLOCKED') 'Hash-bound inspection changed decision.'
    Write-Config ($valid.Replace('14.25','15'))
    Assert-ReadOnlyRefusal { Get-TypezeroTerminalFontActivationReadinessV2 -ThemeId gruvbox -ConfigPath $configPath -SettingsPath $settingsPath -ExpectedConfigSha256 $configHash }
    Write-Config $valid
    [IO.File]::WriteAllText($settingsPath, $settings + "`n", $utf8)
    Assert-ReadOnlyRefusal { Get-TypezeroTerminalFontActivationReadinessV2 -ThemeId gruvbox -ConfigPath $configPath -SettingsPath $settingsPath -ExpectedSettingsSha256 $settingsHash }
    [IO.File]::WriteAllText($settingsPath, $settings, $utf8)
}
Invoke-Check 'Strict V2 schema rejects ambiguity, coercions, unsupported overrides, and invalid typography' {
    $badConfigs = @(
        $valid.Replace('"Version":2', '"Version":2,"Version":2'),
        $valid.Replace('"Version":2', '"Version":2,"version":2'),
        $valid.Replace('"Version":2', '"Version":"2"'),
        $valid.Replace('"Version":2', '"Version":2.0'),
        $valid.Replace('"Enabled":false', '"Enabled":"false"'),
        $valid.Replace('"ManualOverride":null', '"ManualOverride":{}'),
        $valid.Replace('"ManualOverride":null,', ''),
        $valid.Replace('"Version":2', '"Unexpected":true,"Version":2'),
        $valid.Replace('"size":14.25', '"size":14.25,"Size":14.25'),
        $valid.Replace('"size":14.25', '"size":"14.25"'),
        $valid.Replace('14.25', '1e999'), $valid.Replace('14.25','5.99'),
        $valid.Replace('14.25', '36.01'), $valid.Replace('14.25','14.251'),
        $valid.Replace('Fixture Font', ' Fixture Font'), $valid.Replace('Fixture Font','Fixture\nFont'),
        $valid.Replace('semi-bold','Normal'), $valid.Replace('"gruvbox"','"gruvbox\n"'),
        $valid.Replace('"gruvbox"','"missing"'),
        $valid.Replace('"Mappings":{', '"Mappings":{"gruvbox":{"family":"Other","size":12,"weight":"normal"},')
    )
    foreach ($bad in $badConfigs) {
        Write-Config $bad
        Assert-ReadOnlyRefusal { Invoke-Readiness }
    }
    Write-Config $valid
    Assert-ReadOnlyRefusal { Get-TypezeroTerminalFontActivationReadinessV2 -ThemeId "gruvbox`n" -ConfigPath $configPath -SettingsPath $settingsPath }
}
Invoke-Check 'Existing V2 ownership and foreign profile font block activation without recovery' {
    foreach ($text in @($settings.Replace('{"profiles"','{/* TYPEZERO_FONT_V2 */"profiles"'),
        $settings.Replace('"name":"PowerShell"', '"name":"PowerShell","font":{"face":"Foreign Font","size":12,"weight":"normal"}'))) {
        [IO.File]::WriteAllText($settingsPath, $text, $utf8)
        $before = Get-Inventory
        $result = Invoke-Readiness
        Assert-Test ($result.Blockers -ccontains 'V2_OWNERSHIP_REQUIRES_AUTHORIZED_RECOVERY' -or
            $result.Blockers -ccontains 'EXISTING_PROFILE_FONT_REQUIRES_OWNERSHIP_REVIEW') 'Ownership blocker omitted.'
        Assert-Test (-not $result.RecoveryAllowed -and -not $result.LiveActivationAuthorized -and
            (Get-Inventory) -ceq $before) 'Ownership inspection authorized or modified settings.'
    }
    [IO.File]::WriteAllText($settingsPath, $settings, $utf8)
}
Invoke-Check 'Malformed or ambiguous Terminal JSON and UTF-8 BOM refuse without effects' {
    foreach ($text in @('{invalid', $settings.Replace('"profiles":', '"profiles":{},"profiles":'),
        $settings.Replace('"defaults":{}','"defaults":{},"Defaults":{}'), '{}')) {
        [IO.File]::WriteAllText($settingsPath, $text, $utf8)
        Assert-ReadOnlyRefusal { Invoke-Readiness }
    }
    [IO.File]::WriteAllText($settingsPath, $settings, [Text.UTF8Encoding]::new($true))
    Assert-ReadOnlyRefusal { Invoke-Readiness }
    [IO.File]::WriteAllText($settingsPath, $settings, $utf8)
    [IO.File]::WriteAllBytes($configPath, [byte[]]@(255,254,253))
    Assert-ReadOnlyRefusal { Invoke-Readiness }
    Write-Config $valid
}
Invoke-Check 'Readiness has no execution or caller authorization switches' {
    foreach ($parameter in @('Execute','RecoveryAuthorized','LiveActivationAuthorized','ReplayProtectionEstablished')) {
        Assert-Test (-not (Get-Command Get-TypezeroTerminalFontActivationReadinessV2).Parameters.ContainsKey($parameter)) 'Readiness accepts caller authority.'
    }
    Assert-ReadOnlyRefusal { Invoke-Readiness -Execute }
}
# Inert stubs make reaching any legacy planning/provider path observable.
$script:planCalls = 0
$script:providerCalls = 0
function Get-TypezeroTerminalFontSwitchPlan {
    param($ThemeId, $ConfigPath)
    $script:planCalls++
    [pscustomobject]@{ MappingVersion = 2; IntegrationEnabled = $true; WouldChange = $true }
}
function Get-TypezeroTerminalFontStatus {
    $script:providerCalls++
    throw 'FAIL: Legacy live provider was reached.'
}
Invoke-Check 'Legacy V2 Execute and WhatIf refuse before planning, provider lookup, confirmation, or writes' {
    foreach ($whatIf in @($false,$true)) {
        Assert-ReadOnlyRefusal { Invoke-TypezeroTerminalFontSwitchV2 -ThemeId gruvbox -ConfigPath $configPath -Execute -Confirm:$false -WhatIf:$whatIf }
        Assert-ReadOnlyRefusal { Restore-TypezeroTerminalFontSwitchV2 -BackupDirectory (Join-Path $root 'nonexistent-backup') -Execute -Confirm:$false -WhatIf:$whatIf }
    }
    Assert-Test ($script:planCalls -eq 0 -and $script:providerCalls -eq 0) 'Execute reached a legacy provider or planner.'
}
Invoke-Check 'Legacy V2 dry planning remains available without settings writes' {
    $before = Get-Inventory
    $result = Invoke-TypezeroTerminalFontSwitchV2 -ThemeId gruvbox -ConfigPath $configPath
    Assert-Test ($result.MappingVersion -eq 2 -and $script:planCalls -eq 1 -and $script:providerCalls -eq 0) 'Legacy preview contract changed.'
    Assert-Test ((Get-Inventory) -ceq $before) 'Legacy preview changed fixture.'
}
Invoke-Check 'Missing and oversized config snapshots refuse without creating output' {
    Assert-ReadOnlyRefusal { Get-TypezeroTerminalFontActivationReadinessV2 -ThemeId gruvbox -ConfigPath (Join-Path $root 'missing.json') -SettingsPath $settingsPath }
    $oversized = Join-Path $root 'oversized.json'
    [IO.File]::WriteAllText($oversized, (' ' * 1048577), $utf8)
    Assert-ReadOnlyRefusal { Get-TypezeroTerminalFontActivationReadinessV2 -ThemeId gruvbox -ConfigPath $oversized -SettingsPath $settingsPath }
}
Invoke-Check 'Redirected input ancestors and hard-linked config snapshots refuse' {
    # Retain link fixtures at the end; do not remove or mutate unsafe evidence.
    $redirect = Join-Path $FixtureParent ('typezero-readiness-link-' + [guid]::NewGuid().ToString('N'))
    $null = New-Item -ItemType Junction -Path $redirect -Target ([IO.Path]::GetFullPath($root)) -ErrorAction Stop
    Assert-ReadOnlyRefusal { Get-TypezeroTerminalFontActivationReadinessV2 -ThemeId gruvbox -ConfigPath (Join-Path $redirect 'font-windows-terminal.json') -SettingsPath $settingsPath }
    $alias = Join-Path $root 'hardlinked-config.json'
    $null = New-Item -ItemType HardLink -Path $alias -Target ([IO.Path]::GetFullPath($configPath)) -ErrorAction Stop
    Assert-ReadOnlyRefusal { Invoke-Readiness }
    Assert-ReadOnlyRefusal { Get-TypezeroTerminalFontActivationReadinessV2 -ThemeId gruvbox -ConfigPath $alias -SettingsPath $settingsPath }
}
Write-Host "PASS: $script:checks/$script:checks V2 activation readiness/legacy guard groups."
Write-Host 'RecoveryAuthorized=False; LiveActivationAuthorized=False'
Write-Host "Fixture retained: $root"
