# Isolated Windows/PowerShell 7 V1 restore regression. No real Terminal access.
param(
    [Parameter(Mandatory)][string]$SourceDirectory,
    [string]$FixtureParent = [IO.Path]::GetTempPath()
)
$ErrorActionPreference = 'Stop'
if (-not $IsWindows -or $PSVersionTable.PSVersion.Major -lt 7) {
    throw 'This fixture suite requires Windows and PowerShell 7.'
}
$source = Join-Path ([IO.Path]::GetFullPath($SourceDirectory)) 'FontActivation-WindowsTerminal.ps1'
$fixtureBase = [IO.Path]::GetFullPath($FixtureParent).TrimEnd('\') + '\'
if (-not [IO.Directory]::Exists($fixtureBase)) { throw 'Fixture parent must already exist.' }
$sourceHash = (Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash
. $source
$savedLocalAppData = $env:LOCALAPPDATA
$utf8 = [Text.UTF8Encoding]::new($false, $true)
$guid = '{574e775e-4f2a-5b96-ac1e-a2962a402336}'
$script:fixtureRoots = [Collections.Generic.List[string]]::new()
$script:fixture = $null
$script:reviewMutation = $null
$script:reviewCalls = 0
$script:passed = 0

# This replaces the provider for the suite. All paths point below a newly
# generated fake LOCALAPPDATA; no real provider or font installer is loaded.
function Get-TypezeroTerminalFontStatus {
    if ($null -eq $script:fixture) { throw 'No active disposable fixture.' }
    $path = Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json'
    if ($path -cne $script:fixture.SettingsPath) { throw 'Fixture provider path mismatch.' }
    $settings = [IO.File]::ReadAllText($path) | ConvertFrom-Json -ErrorAction Stop
    $profile = @($settings.profiles.list | Where-Object { $_.guid -eq $guid })
    if ($profile.Count -ne 1) { throw 'Expected one fixture PowerShell profile.' }
    $face = if ($profile[0].font.face) { $profile[0].font.face } else { 'Cascadia Mono' }
    [pscustomobject]@{ Face = $face; SettingsPath = $path }
}
function Write-Warning {
    param([string]$Message)
    $script:reviewCalls++
    if ($script:reviewMutation) {
        $mutation = $script:reviewMutation
        $script:reviewMutation = $null
        & $mutation
    }
    Microsoft.PowerShell.Utility\Write-Warning $Message
}
function Hash-Bytes([byte[]]$Bytes) {
    [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($Bytes))
}
function Save-Receipt($Fixture) {
    [IO.File]::WriteAllText($Fixture.ReceiptPath,
        ($Fixture.Receipt | ConvertTo-Json -Depth 20), $utf8)
}
function Get-Inventory($Fixture) {
    @(Get-ChildItem -LiteralPath $Fixture.Root -Recurse -File -Force |
        Sort-Object FullName | ForEach-Object {
            $_.FullName + '|' + (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash
        }) -join "`n"
}
function Assert-True([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}
function New-Fixture {
    $root = Join-Path $fixtureBase ('typezero-v1-ownership-' + [guid]::NewGuid().ToString('N'))
    $settingsPath = Join-Path $root 'Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json'
    $backup = Join-Path $root 'Typezero\ThemeEngine\backups\font-switch\legacy'
    foreach ($path in @((Split-Path -Parent $settingsPath), $backup)) {
        New-Item -ItemType Directory -Path $path -Force -ErrorAction Stop | Out-Null
    }
    $script:fixtureRoots.Add($root)
    $before = "{`r`n  `"unrelated`": [1, 2, 3],`r`n  `"profiles`": {`"list`": [{`"guid`":`"$guid`"}]} `r`n}`r`n"
    $after = $before.Replace("`"guid`":`"$guid`"", "`"guid`":`"$guid`",`"font`":{`"face`":`"JetBrainsMono Nerd Font`"}")
    $f = [pscustomobject]@{
        Root = $root; SettingsPath = $settingsPath; BackupDirectory = $backup
        BackupPath = Join-Path $backup 'settings-original.json'
        ReceiptPath = Join-Path $backup 'receipt.json'
        BeforeBytes = $utf8.GetBytes($before); AfterBytes = $utf8.GetBytes($after)
        AfterText = $after
        Receipt = [ordered]@{
            Version = 1; ProfileGuid = $guid; Theme = 'fixture'
            RequestedFont = 'JetBrainsMono Nerd Font'; PreviousFont = 'Cascadia Mono'
            HadFontProperty = $false; OriginalFont = $null
            BeforeSha256 = Hash-Bytes ($utf8.GetBytes($before))
            AfterSha256 = Hash-Bytes ($utf8.GetBytes($after))
        }
    }
    [IO.File]::WriteAllBytes($f.SettingsPath, $f.AfterBytes)
    [IO.File]::WriteAllBytes($f.BackupPath, $f.BeforeBytes)
    Save-Receipt $f
    $script:fixture = $f
    $env:LOCALAPPDATA = $root
    $script:reviewCalls = 0
    $script:reviewMutation = $null
    $f
}
function Assert-Blocked([string]$Name, [scriptblock]$Mutate,
                        [string]$Expected = 'reserved TYPEZERO_FONT_V2 ownership',
                        [switch]$Preview, [switch]$WhatIfOnly) {
    $f = New-Fixture
    & $Mutate $f
    $before = Get-Inventory $f
    $caught = $null
    try {
        if ($Preview) { Restore-TypezeroTerminalFontSwitch -BackupDirectory $f.BackupDirectory | Out-Null }
        elseif ($WhatIfOnly) { Restore-TypezeroTerminalFontSwitch -BackupDirectory $f.BackupDirectory -Execute -WhatIf | Out-Null }
        else { Restore-TypezeroTerminalFontSwitch -BackupDirectory $f.BackupDirectory -Execute -Confirm:$false | Out-Null }
    }
    catch { $caught = $_.Exception.Message }
    Assert-True ($null -ne $caught -and $caught -match $Expected) "${Name}: unexpected refusal: $caught"
    Assert-True ((Get-Inventory $f) -ceq $before) "${Name}: changed fixture files."
    Assert-True ($script:reviewCalls -eq 0) "${Name}: ownership was checked after the confirmation boundary."
    $script:passed++
    Write-Host "PASS [$script:passed] $Name"
}

try {
    foreach ($mode in @('preview', 'execute', 'whatif')) {
        $splat = @{ Preview = ($mode -eq 'preview'); WhatIfOnly = ($mode -eq 'whatif') }
        Assert-Blocked "Forged current hash cannot authorize V2 ($mode)" {
            param($f)
            $marked = $utf8.GetBytes($f.AfterText.Insert(1, '/* TYPEZERO_FONT_V2 */'))
            [IO.File]::WriteAllBytes($f.SettingsPath, $marked)
            $f.Receipt.AfterSha256 = Hash-Bytes $marked
            Save-Receipt $f
        } @splat
    }
    Assert-Blocked 'Genuine old receipt refuses subsequent V2-owned settings' {
        param($f)
        [IO.File]::WriteAllText($f.SettingsPath, $f.AfterText.Insert(1, '/* TYPEZERO_FONT_V2 */'), $utf8)
    }
    Assert-Blocked 'Retargeted legacy receipt cannot overwrite an unrelated V2 document' {
        param($f)
        $other = $utf8.GetBytes($f.AfterText.Replace('[1, 2, 3]', '[9, 8, 7]').Insert(1, '/* TYPEZERO_FONT_V2 */'))
        [IO.File]::WriteAllBytes($f.SettingsPath, $other)
        $f.Receipt.AfterSha256 = Hash-Bytes $other
        Save-Receipt $f
    }
    foreach ($marker in @('/*TYPEZERO_FONT_V2*/', '/* TYPEZERO_FONT_V2 orphan */',
                          '/* typezero_font_v2 */', '/* TYPEZERO_FONT_V2')) {
        $script:marker = $marker
        Assert-Blocked "Malformed/orphaned token is reserved: $marker" {
            param($f)
            # The unterminated marker is carried in a JSON string, preserving
            # parseability while proving exact comment spelling is irrelevant.
            $marked = $utf8.GetBytes($f.AfterText.Replace('[1, 2, 3]', (ConvertTo-Json $script:marker -Compress)))
            [IO.File]::WriteAllBytes($f.SettingsPath, $marked)
            $f.Receipt.AfterSha256 = Hash-Bytes $marked
            Save-Receipt $f
        }
    }
    foreach ($encoding in @($utf8, [Text.UnicodeEncoding]::new($false, $true, $true),
                             [Text.UnicodeEncoding]::new($true, $true, $true),
                             [Text.UTF32Encoding]::new($false, $true, $true),
                             [Text.UTF32Encoding]::new($true, $true, $true))) {
        $script:backupEncoding = $encoding
        Assert-Blocked "V2 backup is blocked even with forged checksum ($($encoding.WebName))" {
            param($f)
            $marked = $script:backupEncoding.GetBytes('{/* TYPEZERO_FONT_V2 orphan */"font":"protected"}')
            [IO.File]::WriteAllBytes($f.BackupPath, $marked)
            $f.Receipt.BeforeSha256 = Hash-Bytes $marked
            Save-Receipt $f
        }
    }
    Assert-Blocked 'Legacy mismatched current checksum remains blocked' { param($f) $f.Receipt.AfterSha256 = 'A' * 64; Save-Receipt $f } 'changed since activation'
    Assert-Blocked 'Legacy mismatched backup checksum remains blocked' { param($f) $f.Receipt.BeforeSha256 = 'B' * 64; Save-Receipt $f } 'Original backup checksum mismatch'

    $f = New-Fixture
    $before = Get-Inventory $f
    $preview = Restore-TypezeroTerminalFontSwitch -BackupDirectory $f.BackupDirectory
    Assert-True ($preview.Action -ceq 'PREVIEW ONLY - no changes' -and -not $preview.ReceiptAuthenticated) 'Valid legacy preview contract changed.'
    Assert-True ($preview.CurrentFont -ceq 'JetBrainsMono Nerd Font' -and $preview.PreviousFont -ceq 'Cascadia Mono') 'Valid legacy preview font values changed.'
    Assert-True ((Get-Inventory $f) -ceq $before) 'Valid legacy preview wrote files.'
    $script:passed++; Write-Host "PASS [$script:passed] Valid legacy preview preserves every byte"

    Restore-TypezeroTerminalFontSwitch -BackupDirectory $f.BackupDirectory -Execute -WhatIf | Out-Null
    Assert-True ((Get-Inventory $f) -ceq $before) 'Valid legacy WhatIf wrote files.'
    $script:passed++; Write-Host "PASS [$script:passed] Valid legacy WhatIf preserves every byte"

    $restored = Restore-TypezeroTerminalFontSwitch -BackupDirectory $f.BackupDirectory -Execute -Confirm:$false
    Assert-True ($restored.Status -ceq 'RESTORED' -and $restored.Font -ceq 'Cascadia Mono') 'Valid legacy restore did not succeed.'
    Assert-True ((Hash-Bytes ([IO.File]::ReadAllBytes($f.SettingsPath))) -ceq (Hash-Bytes $f.BeforeBytes)) 'Legacy restore was not byte-exact.'
    Assert-True (@(Get-ChildItem -LiteralPath (Split-Path -Parent $f.SettingsPath) -Filter '.typezero-font-restore-*.tmp').Count -eq 0) 'Successful restore retained a stage file.'
    $script:passed++; Write-Host "PASS [$script:passed] Valid legacy restore is byte-exact"

    $f = New-Fixture
    $script:reviewMutation = {
        [IO.File]::WriteAllText($script:fixture.SettingsPath,
            $script:fixture.AfterText.Insert(1, '/* TYPEZERO_FONT_V2 */'), $utf8)
    }
    $caught = $null
    try { Restore-TypezeroTerminalFontSwitch -BackupDirectory $f.BackupDirectory -Execute -Confirm:$false | Out-Null }
    catch { $caught = $_.Exception.Message }
    Assert-True ($caught -match 'reserved TYPEZERO_FONT_V2 ownership') "Review-time V2 marker was not blocked: $caught"
    Assert-True ($script:reviewCalls -eq 1) 'Review-time mutation did not run at the review boundary.'
    Assert-True ([IO.File]::ReadAllText($f.SettingsPath).Contains('/* TYPEZERO_FONT_V2 */')) 'Restore overwrote ownership introduced during review.'
    Assert-True (@(Get-ChildItem -LiteralPath (Split-Path -Parent $f.SettingsPath) -Filter '.typezero-font-restore-*.tmp').Count -eq 0) 'Blocked restore retained a stage file.'
    $script:passed++; Write-Host "PASS [$script:passed] Ownership introduced during review is blocked before replacement"

    Assert-True ((Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash -ceq $sourceHash) 'Suite changed source bytes.'
    Write-Host "PASS: $script:passed isolated V1 restore ownership checks. Live settings, fonts, and installed modules were not accessed."
}
finally {
    $env:LOCALAPPDATA = $savedLocalAppData
    $script:reviewMutation = $null
    foreach ($root in $script:fixtureRoots) {
        $resolved = [IO.Path]::GetFullPath($root)
        if (-not $resolved.StartsWith($fixtureBase, [StringComparison]::OrdinalIgnoreCase) -or
            (Split-Path -Leaf $resolved) -notmatch '^typezero-v1-ownership-[a-f0-9]{32}$') {
            throw 'Unsafe fixture cleanup path refused.'
        }
        Remove-Item -LiteralPath $resolved -Recurse -Force -ErrorAction Stop
    }
}
