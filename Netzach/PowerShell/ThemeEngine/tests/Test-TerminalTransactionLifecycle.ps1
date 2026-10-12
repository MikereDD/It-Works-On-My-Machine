param([string]$SourceDirectory = (Split-Path -Parent $PSScriptRoot))
$ErrorActionPreference = 'Stop'
if ($PSVersionTable.PSVersion.Major -lt 7) { throw 'Use PowerShell 7 or later.' }
foreach ($name in @('FontPatch-WindowsTerminal.ps1', 'TerminalColorPatch-WindowsTerminal.ps1',
    'TerminalCombinedPatch-WindowsTerminal.ps1', 'TerminalTransaction-WindowsTerminal.ps1')) {
    . (Join-Path $SourceDirectory $name)
}
$script:checks = 0
function Assert-Lifecycle([bool]$Condition, [string]$Name) {
    if (-not $Condition) { throw "FAIL: $Name" }
    $script:checks++
    Write-Output "PASS: $Name"
}
function Get-FixtureHash([string]$Path) {
    (Get-FileHash -LiteralPath $Path -Algorithm SHA256 -ErrorAction Stop).Hash
}
function Assert-RestoreBlocked([string]$Name, [string]$Expected, [string]$Directory) {
    $hash = Get-FixtureHash $settings
    $message = $null
    try {
        $null = Restore-TypezeroOfflineTerminalCombinedTransaction -TestRoot $root `
            -BackupDirectory $Directory -Execute -Confirm:$false
    }
    catch { $message = $_.Exception.Message }
    Assert-Lifecycle ($message -and $message -like "*$Expected*" -and
        (Get-FixtureHash $settings) -eq $hash) "$Name blocked without settings changes"
}
$root = Join-Path ([IO.Path]::GetTempPath()) ('typezero-terminal-txn-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $root -ErrorAction Stop | Out-Null
$paths = Get-TypezeroOfflineTerminalTransactionPaths -TestRoot $root
$settings = $paths.Settings
New-Item -ItemType Directory -Path (Split-Path -Parent $settings) -Force | Out-Null
$utf8 = [Text.UTF8Encoding]::new($false)
$original = @'
{
    // Synthetic fixture: no real settings or private configuration is copied.
    "theme":"Typezero ThemeEngine",
    "schemes":[
        {"name":"Typezero Obsidian Silver","background":"#000000","custom":"retained"},
        {"name":"Typezero Gruvbox Dark","background":"#000000"}
    ],
    "themes":[{"name":"Typezero ThemeEngine","window":{"applicationTheme":"dark","custom":"retained"},"tab":{"background":"terminalBackground"},"tabRow":{"background":"#000000"}}],
    "profiles":{"defaults":{},"list":[
        {"guid":"{574e775e-4f2a-5b96-ac1e-a2962a402336}","name":"PowerShell","colorScheme":"Typezero Obsidian Silver"},
        {"guid":"{00000000-0000-0000-0000-000000000001}","name":"Untouched","custom":"retained"}
    ]},
    "customRoot":{"preserved":"yes"}
}
'@
[IO.File]::WriteAllText($settings, $original, $utf8)
$baseline = Get-FixtureHash $settings
$theme = @{ THEME_NAME = 'Obsidian Silver'; BG = '#123456'; TEXT = '#eeeeee';
    CURSOR = '#ffffff'; SELECTION = '#445566' }
foreach ($name in @('BLACK','RED','GREEN','YELLOW','BLUE','PURPLE','CYAN','WHITE',
    'BRIGHT_BLACK','BRIGHT_RED','BRIGHT_GREEN','BRIGHT_YELLOW','BRIGHT_BLUE',
    'BRIGHT_PURPLE','BRIGHT_CYAN','BRIGHT_WHITE')) { $theme["ANSI_$name"] = '#778899' }
$font = @{ FontFace = 'JetBrainsMono Nerd Font'; FontSize = 12; FontWeight = 'semi-bold' }

$preview = Invoke-TypezeroOfflineTerminalCombinedTransaction -TestRoot $root -Theme $theme @font
Assert-Lifecycle ($preview.Status -eq 'PREVIEW' -and $preview.WouldChange) 'Preview reports candidate'
$null = Invoke-TypezeroOfflineTerminalCombinedTransaction -TestRoot $root -Theme $theme @font -Execute -WhatIf
Assert-Lifecycle ((Get-FixtureHash $settings) -eq $baseline -and
    -not (Test-Path -LiteralPath $paths.BackupRoot)) 'Preview and WhatIf create no backup or settings changes'
$first = Invoke-TypezeroOfflineTerminalCombinedTransaction -TestRoot $root -Theme $theme @font -Execute -Confirm:$false
Assert-Lifecycle ($first.Status -eq 'VERIFIED' -and $first.BeforeSha256 -eq $baseline -and
    (Get-FixtureHash $settings) -eq $first.AfterSha256) 'First transaction verifies fixture bytes'
$diag = Get-TypezeroOfflineTerminalCombinedRecoveryDiagnostic -TestRoot $root -BackupDirectory $first.BackupDirectory
Assert-Lifecycle ($diag.State -eq 'APPLIED_BYTES_PRESENT' -and $diag.ReadOnly -and
    -not $diag.RecoveryAllowed -and $diag.StageFiles.Count -eq 0) 'Actual transaction receipt diagnoses applied bytes'
$folderCount = @(Get-ChildItem -LiteralPath $paths.BackupRoot -Directory).Count
$noChange = Invoke-TypezeroOfflineTerminalCombinedTransaction -TestRoot $root -Theme $theme @font -Execute -Confirm:$false
Assert-Lifecycle ($noChange.Status -eq 'NO_CHANGE' -and
    @(Get-ChildItem -LiteralPath $paths.BackupRoot -Directory).Count -eq $folderCount -and
    (Get-FixtureHash $settings) -eq $first.AfterSha256) 'No-change transaction preserves settings and backup count'

$backupPath = Join-Path $first.BackupDirectory 'settings-original.json'
$receiptPath = Join-Path $first.BackupDirectory 'receipt.json'
$savedBackup = [IO.File]::ReadAllBytes($backupPath)
$savedReceipt = [IO.File]::ReadAllBytes($receiptPath)
try {
    [IO.File]::AppendAllText($backupPath, "`n", $utf8)
    Assert-RestoreBlocked 'Corrupt backup' 'backup checksum mismatch' $first.BackupDirectory
    Assert-Lifecycle ((Get-TypezeroOfflineTerminalCombinedRecoveryDiagnostic -TestRoot $root `
        -BackupDirectory $first.BackupDirectory).State -eq 'BACKUP_HASH_MISMATCH') 'Corrupt backup diagnostic'
    [IO.File]::WriteAllBytes($backupPath, $savedBackup)
    foreach ($test in @(
        @{ Name = 'Altered original checksum'; Field = 'BeforeSha256'; Value = ('0' * 64); Error = 'backup checksum mismatch'; State = 'BACKUP_HASH_MISMATCH' },
        @{ Name = 'Altered current checksum'; Field = 'AfterSha256'; Value = ('0' * 64); Error = 'Settings changed since transaction'; State = 'SETTINGS_CONFLICT' },
        @{ Name = 'Altered receipt destination'; Field = 'SettingsPath'; Value = 'C:\prohibited\settings.json'; Error = 'receipt does not match'; State = 'INVALID_RECEIPT' }
    )) {
        $metadata = $utf8.GetString($savedReceipt) | ConvertFrom-Json -AsHashtable
        $metadata[$test.Field] = $test.Value
        [IO.File]::WriteAllText($receiptPath, ($metadata | ConvertTo-Json -Depth 10), $utf8)
        Assert-RestoreBlocked $test.Name $test.Error $first.BackupDirectory
        Assert-Lifecycle ((Get-TypezeroOfflineTerminalCombinedRecoveryDiagnostic -TestRoot $root `
            -BackupDirectory $first.BackupDirectory).State -eq $test.State) ($test.Name + ' diagnostic')
    }
    [IO.File]::WriteAllText($receiptPath, '{"Version":', $utf8)
    Assert-RestoreBlocked 'Malformed receipt' '' $first.BackupDirectory
    Assert-Lifecycle ((Get-TypezeroOfflineTerminalCombinedRecoveryDiagnostic -TestRoot $root `
        -BackupDirectory $first.BackupDirectory).State -eq 'INVALID_RECEIPT') 'Malformed receipt diagnostic'
}
finally {
    [IO.File]::WriteAllBytes($backupPath, $savedBackup)
    [IO.File]::WriteAllBytes($receiptPath, $savedReceipt)
}

$secondTheme = $theme.Clone()
$secondTheme.THEME_NAME = 'Gruvbox Dark'
$secondTheme.BG = '#654321'
$secondFont = @{ FontFace = $font.FontFace; FontSize = 13; FontWeight = 'normal' }
$second = Invoke-TypezeroOfflineTerminalCombinedTransaction -TestRoot $root -Theme $secondTheme @secondFont -Execute -Confirm:$false
Assert-Lifecycle ($second.Status -eq 'VERIFIED' -and $second.BeforeSha256 -eq $first.AfterSha256) 'Second transaction preserves first as baseline'
Assert-RestoreBlocked 'Out-of-order restore' 'Settings changed since transaction' $first.BackupDirectory
Assert-Lifecycle ((Get-TypezeroOfflineTerminalCombinedRecoveryDiagnostic -TestRoot $root `
    -BackupDirectory $first.BackupDirectory).State -eq 'SETTINGS_CONFLICT') 'Older transaction diagnoses conflict'
$restorePreview = Restore-TypezeroOfflineTerminalCombinedTransaction -TestRoot $root -BackupDirectory $second.BackupDirectory
$null = Restore-TypezeroOfflineTerminalCombinedTransaction -TestRoot $root -BackupDirectory $second.BackupDirectory -Execute -WhatIf
Assert-Lifecycle ($restorePreview.Status -eq 'PREVIEW' -and
    (Get-FixtureHash $settings) -eq $second.AfterSha256) 'Restore preview and WhatIf preserve fixture'
$undoSecond = Restore-TypezeroOfflineTerminalCombinedTransaction -TestRoot $root -BackupDirectory $second.BackupDirectory -Execute -Confirm:$false
Assert-Lifecycle ($undoSecond.Status -eq 'RESTORED' -and
    (Get-FixtureHash $settings) -eq $first.AfterSha256) 'Second restore returns exact intermediate bytes'
Assert-Lifecycle ((Get-TypezeroOfflineTerminalCombinedRecoveryDiagnostic -TestRoot $root `
    -BackupDirectory $second.BackupDirectory).State -eq 'ORIGINAL_BYTES_PRESENT') 'Restored transaction retains phase ambiguity'
$undoFirst = Restore-TypezeroOfflineTerminalCombinedTransaction -TestRoot $root -BackupDirectory $first.BackupDirectory -Execute -Confirm:$false
Assert-Lifecycle ($undoFirst.Status -eq 'RESTORED' -and
    (Get-FixtureHash $settings) -eq $baseline) 'First restore returns original bytes exactly'

$third = Invoke-TypezeroOfflineTerminalCombinedTransaction -TestRoot $root -Theme $theme @font -Execute -Confirm:$false
$safeBytes = [IO.File]::ReadAllBytes($settings)
[IO.File]::AppendAllText($settings, "`n", $utf8)
Assert-RestoreBlocked 'External fixture modification' 'Settings changed since transaction' $third.BackupDirectory
Assert-Lifecycle ((Get-TypezeroOfflineTerminalCombinedRecoveryDiagnostic -TestRoot $root `
    -BackupDirectory $third.BackupDirectory).State -eq 'SETTINGS_CONFLICT') 'External modification diagnostic'
[IO.File]::WriteAllBytes($settings, $safeBytes)
$undoThird = Restore-TypezeroOfflineTerminalCombinedTransaction -TestRoot $root -BackupDirectory $third.BackupDirectory -Execute -Confirm:$false
Assert-Lifecycle ($undoThird.Status -eq 'RESTORED' -and
    (Get-FixtureHash $settings) -eq $baseline) 'Fixture-only conflict recovery restores exact bytes'
Write-Output "PASS: $script:checks lifecycle/regression checks. Retained disposable fixture: $root"
