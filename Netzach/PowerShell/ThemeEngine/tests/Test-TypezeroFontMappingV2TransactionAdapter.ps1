# Runs only on PowerShell 7+ / Windows, using new synthetic TEMP fixtures.
# Never copy or modify live Windows Terminal settings or private config.
param([string]$SourceDirectory = (Split-Path -Parent $PSScriptRoot))
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if (-not $IsWindows -or $PSVersionTable.PSVersion.Major -lt 7) {
    throw 'V2 lifecycle tests require Windows and PowerShell 7 or later.'
}
foreach ($name in @(
    'FontPatch-WindowsTerminal.ps1',
    'TerminalColorPatch-WindowsTerminal.ps1',
    'TerminalCombinedPatch-WindowsTerminal.ps1',
    'TerminalTransaction-WindowsTerminal.ps1',
    'TerminalReplace-WindowsTerminal.ps1',
    'TerminalTransactionV2-WindowsTerminal.ps1'
)) { . (Join-Path $SourceDirectory $name) }

$script:checks = 0
function Assert-V2([bool]$Condition, [string]$Name) {
    if (-not $Condition) { throw "FAIL: $Name" }
    $script:checks++
    Write-Output "PASS: $Name"
}
function Get-V2Hash([string]$Path) {
    (Get-FileHash -LiteralPath $Path -Algorithm SHA256 -ErrorAction Stop).Hash
}
function Assert-V2Blocked([scriptblock]$Action, [string]$Match, [string]$Name) {
    $reason = $null
    try { $null = & $Action }
    catch { $reason = $_.Exception.Message }
    Assert-V2 ($null -ne $reason -and $reason -like "*$Match*") $Name
}

$local = [Environment]::GetFolderPath(
    [Environment+SpecialFolder]::LocalApplicationData
)
$live = Join-Path $local (
    'Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json'
)
$liveExists = [IO.File]::Exists($live)
$liveHash = if ($liveExists) { Get-V2Hash $live } else { $null }
$sourcePaths = @(
    'TerminalTransaction-WindowsTerminal.ps1',
    'TerminalReplace-WindowsTerminal.ps1',
    'TerminalTransactionV2-WindowsTerminal.ps1'
) | ForEach-Object { Join-Path $SourceDirectory $_ }
$sourceHashes = @{}
foreach ($path in $sourcePaths) { $sourceHashes[$path] = Get-V2Hash $path }
$fixtures = [Collections.Generic.List[string]]::new()
$utf8 = [Text.UTF8Encoding]::new($false)

$theme = @{ THEME_NAME='Obsidian Silver'; BG='#123456'; TEXT='#eeeeee';
    CURSOR='#ffffff'; SELECTION='#445566' }
foreach ($name in @('BLACK','RED','GREEN','YELLOW','BLUE','PURPLE','CYAN','WHITE',
    'BRIGHT_BLACK','BRIGHT_RED','BRIGHT_GREEN','BRIGHT_YELLOW','BRIGHT_BLUE',
    'BRIGHT_PURPLE','BRIGHT_CYAN','BRIGHT_WHITE')) { $theme["ANSI_$name"]='#778899' }
$font = @{ FontFace='JetBrainsMono Nerd Font'; FontSize=12; FontWeight='semi-bold' }
$original = @'
{
    // A wholly synthetic fixture: NOT a copy of Windows Terminal settings.
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
function New-V2Fixture {
    $root = Join-Path ([IO.Path]::GetTempPath()) (
        'typezero-terminal-txn-' + [guid]::NewGuid().ToString('N')
    )
    if (Test-Path -LiteralPath $root) { throw 'Fresh root already exists.' }
    New-Item -ItemType Directory -Path $root -ErrorAction Stop | Out-Null
    $fixtures.Add($root)
    $settings = (Get-TypezeroOfflineTerminalTransactionPaths -TestRoot $root).Settings
    New-Item -ItemType Directory -Path (Split-Path -Parent $settings) -Force | Out-Null
    [IO.File]::WriteAllText($settings, $original, $utf8)
    [pscustomobject]@{ Root=$root; Settings=$settings; Baseline=(Get-V2Hash $settings) }
}

try {
    $f = New-V2Fixture
    $preview = Invoke-TypezeroOfflineTerminalCombinedTransactionV2 `
        -TestRoot $f.Root -Theme $theme @font
    Assert-V2 ($preview.Status -ceq 'PREVIEW' -and $preview.WouldChange -and
        $preview.ReadOnly -and (Get-V2Hash $f.Settings) -ceq $f.Baseline) `
        'V2 preview predicts change without writing'

    $null = Invoke-TypezeroOfflineTerminalCombinedTransactionV2 `
        -TestRoot $f.Root -Theme $theme @font -Execute -WhatIf
    $backupRoot = (Get-TypezeroOfflineTerminalTransactionPaths $f.Root).BackupRoot
    Assert-V2 ((Get-V2Hash $f.Settings) -ceq $f.Baseline -and
        -not [IO.Directory]::Exists($backupRoot)) 'V2 WhatIf creates no files'

    $first = Invoke-TypezeroOfflineTerminalCombinedTransactionV2 `
        -TestRoot $f.Root -Theme $theme @font -Execute -Confirm:$false
    $originalBackup = Join-Path $first.BackupDirectory 'settings-pre-replace.json'
    $receiptPath = Join-Path $first.BackupDirectory 'receipt.json'
    Assert-V2 ($first.Status -ceq 'VERIFIED' -and $first.Version -eq 2 -and
        (Get-V2Hash $f.Settings) -ceq $first.AfterSha256 -and
        (Get-V2Hash $originalBackup) -ceq $f.Baseline) `
        'V2 apply preserves original and installs candidate'
    $receipt = Read-TypezeroOfflineTerminalV2ApplyReceipt -Paths `
        (Get-TypezeroOfflineTerminalV2Paths $f.Root) -Folder $first.BackupDirectory
    Assert-V2 ($receipt.Version -eq 2 -and $receipt.Kind -ceq
        'TypezeroOfflineCombinedV2' -and $receipt.Operation -ceq 'APPLY' -and
        $receipt.BeforeSha256 -ceq $f.Baseline) 'V2 apply receipt validated'

    $diag = Get-TypezeroOfflineTerminalCombinedV2RecoveryDiagnostic `
        -TestRoot $f.Root -BackupDirectory $first.BackupDirectory
    Assert-V2 ($diag.State -ceq 'APPLIED_BYTES_PRESENT' -and $diag.ReadOnly -and
        -not $diag.RecoveryAllowed -and $diag.OperationPhase -ceq 'UNKNOWN') `
        'V2 applied diagnostic is read-only and phase-agnostic'

    $count = @(Get-ChildItem -LiteralPath $backupRoot -Directory).Count
    $noChange = Invoke-TypezeroOfflineTerminalCombinedTransactionV2 `
        -TestRoot $f.Root -Theme $theme @font -Execute -Confirm:$false
    Assert-V2 ($noChange.Status -ceq 'NO_CHANGE' -and
        @(Get-ChildItem -LiteralPath $backupRoot -Directory).Count -eq $count) `
        'V2 unchanged candidate creates no backup'

    $restorePreview = Restore-TypezeroOfflineTerminalCombinedTransactionV2 `
        -TestRoot $f.Root -BackupDirectory $first.BackupDirectory
    $null = Restore-TypezeroOfflineTerminalCombinedTransactionV2 `
        -TestRoot $f.Root -BackupDirectory $first.BackupDirectory -Execute -WhatIf
    Assert-V2 ($restorePreview.Status -ceq 'PREVIEW' -and
        $restorePreview.ReadOnly -and
        (Get-V2Hash $f.Settings) -ceq $first.AfterSha256 -and
        @(Get-ChildItem -LiteralPath $backupRoot -Directory).Count -eq $count) `
        'V2 restore preview and WhatIf preserve evidence'

    $restored = Restore-TypezeroOfflineTerminalCombinedTransactionV2 `
        -TestRoot $f.Root -BackupDirectory $first.BackupDirectory `
        -Execute -Confirm:$false
    Assert-V2 ($restored.Status -ceq 'RESTORED' -and
        (Get-V2Hash $f.Settings) -ceq $f.Baseline -and
        (Get-V2Hash $originalBackup) -ceq $f.Baseline -and
        (Get-V2Hash $restored.AppliedBackup) -ceq $first.AfterSha256) `
        'V2 restore exact original; preserve both backup states'
    $restoreReceipt = (Get-Content -LiteralPath (
        Join-Path $restored.RestoreBackupDirectory 'receipt.json') -Raw) |
        ConvertFrom-Json
    Assert-V2 ($restoreReceipt.Version -eq 2 -and
        $restoreReceipt.Operation -ceq 'RESTORE' -and
        $restoreReceipt.ParentTransactionFolderName -ceq
            [IO.Path]::GetFileName($first.BackupDirectory)) `
        'V2 restore receipt links to apply transaction name'
    $diag = Get-TypezeroOfflineTerminalCombinedV2RecoveryDiagnostic `
        -TestRoot $f.Root -BackupDirectory $first.BackupDirectory
    Assert-V2 ($diag.State -ceq 'ORIGINAL_BYTES_PRESENT' -and
        $diag.OperationPhase -ceq 'UNKNOWN') `
        'V2 restored diagnostic does not assert completed phase'

    # Detect modifications, V1 receipts, out-of-order restore, and corruption.
    $f2 = New-V2Fixture
    $second = Invoke-TypezeroOfflineTerminalCombinedTransactionV2 `
        -TestRoot $f2.Root -Theme $theme @font -Execute -Confirm:$false
    $secondBackup = Join-Path $second.BackupDirectory 'settings-pre-replace.json'
    $secondReceipt = Join-Path $second.BackupDirectory 'receipt.json'
    $appliedBytes = [IO.File]::ReadAllBytes($f2.Settings)
    [IO.File]::AppendAllText($f2.Settings, "`n", $utf8)
    Assert-V2Blocked {
        Restore-TypezeroOfflineTerminalCombinedTransactionV2 -TestRoot $f2.Root `
            -BackupDirectory $second.BackupDirectory -Execute -Confirm:$false
    } 'settings changed since transaction' 'External settings conflict rejected'
    [IO.File]::WriteAllBytes($f2.Settings, $appliedBytes)

    $backupBytes = [IO.File]::ReadAllBytes($secondBackup)
    [IO.File]::AppendAllText($secondBackup, "`n", $utf8)
    Assert-V2Blocked {
        Restore-TypezeroOfflineTerminalCombinedTransactionV2 -TestRoot $f2.Root `
            -BackupDirectory $second.BackupDirectory -Execute -Confirm:$false
    } 'backup checksum mismatch' 'Corrupted V2 original backup rejected'
    [IO.File]::WriteAllBytes($secondBackup, $backupBytes)

    $receiptBytes = [IO.File]::ReadAllBytes($secondReceipt)
    try {
        $tampered = [IO.File]::ReadAllText($secondReceipt).Replace(
            'TypezeroOfflineCombinedV2', 'TypezeroOfflineCombined'
        )
        [IO.File]::WriteAllText($secondReceipt, $tampered, $utf8)
        Assert-V2Blocked {
            Restore-TypezeroOfflineTerminalCombinedTransactionV2 -TestRoot $f2.Root `
                -BackupDirectory $second.BackupDirectory -Execute -Confirm:$false
        } 'receipt does not match' 'V1 identity rejected by V2 restore'

        $tampered = [IO.File]::ReadAllText($secondReceipt).Replace(
            '"Version": 2', '"Version": 1'
        )
        [IO.File]::WriteAllText($secondReceipt, $tampered, $utf8)
        Assert-V2Blocked {
            Restore-TypezeroOfflineTerminalCombinedTransactionV2 -TestRoot $f2.Root `
                -BackupDirectory $second.BackupDirectory -Execute -Confirm:$false
        } 'integer version 2' 'V1 version rejected by V2 restore'
    }
    finally { [IO.File]::WriteAllBytes($secondReceipt, $receiptBytes) }
    Assert-V2 ((Get-V2Hash $f2.Settings) -ceq $second.AfterSha256 -and
        (Get-V2Hash $secondBackup) -ceq $f2.Baseline -and
        (Get-V2Hash $secondReceipt) -ceq
            [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($receiptBytes))) `
        'Tampering tests restored fixture evidence'

    # A second V2 apply must block restoring an older transaction.
    $theme2 = $theme.Clone()
    $theme2.THEME_NAME = 'Gruvbox Dark'
    $theme2.BG = '#654321'
    $font2 = @{ FontFace = $font.FontFace; FontSize=13; FontWeight='normal' }
    $third = Invoke-TypezeroOfflineTerminalCombinedTransactionV2 `
        -TestRoot $f2.Root -Theme $theme2 @font2 -Execute -Confirm:$false
    Assert-V2 ($third.BeforeSha256 -ceq $second.AfterSha256) `
        'Second V2 apply retains previous bytes as baseline'
    Assert-V2Blocked {
        Restore-TypezeroOfflineTerminalCombinedTransactionV2 -TestRoot $f2.Root `
            -BackupDirectory $second.BackupDirectory -Execute -Confirm:$false
    } 'settings changed since transaction' 'Out-of-order V2 restore blocked'
    $thirdRestored = Restore-TypezeroOfflineTerminalCombinedTransactionV2 `
        -TestRoot $f2.Root -BackupDirectory $third.BackupDirectory `
        -Execute -Confirm:$false
    Assert-V2 ((Get-V2Hash $f2.Settings) -ceq $second.AfterSha256 -and
        $thirdRestored.Status -ceq 'RESTORED') 'Latest transaction restores intermediate bytes'

    Write-Output "PASS: $script:checks V2 lifecycle checks."
}
finally {
    if ($liveExists -ne [IO.File]::Exists($live) -or
        ($liveExists -and (Get-V2Hash $live) -cne $liveHash)) {
        throw 'REAL WINDOWS TERMINAL SETTINGS CHANGED!'
    }
    Write-Output 'PASS: Real Windows Terminal settings unchanged.'
    foreach ($path in $sourcePaths) {
        if ((Get-V2Hash $path) -cne $sourceHashes[$path]) {
            throw "SOURCE CHANGED: $path"
        }
    }
    Write-Output 'PASS: V1, V2, and replacement modules unchanged.'
    Write-Output "Retained disposable fixtures: $($fixtures.Count)"
    foreach ($root in $fixtures) { Write-Output "  $root" }
}

# === FONT MAPPING V2 ADAPTER REGRESSION ===

. (Join-Path $SourceDirectory 'FontMapping-WindowsTerminal.ps1')
. (Join-Path $SourceDirectory 'FontMappingV2TransactionAdapter-WindowsTerminal.ps1')

Write-Host "`n=== FONT MAPPING V2 ADAPTER ==="

$adapterFixture = New-V2Fixture
$adapterConfig = Join-Path $adapterFixture.Root 'font-v2.json'

$adapterMapping = [ordered]@{
    Version = 2
    Enabled = $false
    ManualOverride = $null
    Mappings = [ordered]@{
        gruvbox = [ordered]@{
            family = 'JetBrainsMono Nerd Font'
            size = 12
            weight = 'normal'
        }
    }
}

[IO.File]::WriteAllText(
    $adapterConfig,
    (($adapterMapping | ConvertTo-Json -Depth 10) + "`n"),
    $utf8
)

$adapterTheme = $theme.Clone()
$adapterTheme.THEME_NAME = 'Obsidian Silver'

$adapterBefore = Get-V2Hash $adapterFixture.Settings

$adapterPreview = Invoke-TypezeroOfflineFontMappingV2Transaction `
    -TestRoot $adapterFixture.Root `
    -ConfigPath $adapterConfig `
    -ThemeId gruvbox `
    -Theme $adapterTheme

Assert-V2 (
    $adapterPreview.Status -ceq 'PREVIEW' -and
    $adapterPreview.ReadOnly -and
    $adapterPreview.WouldChange -and
    (Get-V2Hash $adapterFixture.Settings) -ceq $adapterBefore
) 'Adapter preview is read-only'

Assert-V2Blocked {
    Invoke-TypezeroOfflineFontMappingV2Transaction `
        -TestRoot $adapterFixture.Root `
        -ConfigPath $adapterConfig `
        -ThemeId gruvbox `
        -Theme $adapterTheme `
        -Execute -Confirm:$false
} 'integration is disabled' 'Adapter rejects disabled execution'

$adapterMapping.Enabled = $true

[IO.File]::WriteAllText(
    $adapterConfig,
    (($adapterMapping | ConvertTo-Json -Depth 10) + "`n"),
    $utf8
)

$adapterApply = Invoke-TypezeroOfflineFontMappingV2Transaction `
    -TestRoot $adapterFixture.Root `
    -ConfigPath $adapterConfig `
    -ThemeId gruvbox `
    -Theme $adapterTheme `
    -Execute -Confirm:$false

$adapterBackup = Join-Path $adapterApply.BackupDirectory `
    'settings-pre-replace.json'

Assert-V2 (
    $adapterApply.Status -ceq 'VERIFIED' -and
    (Get-V2Hash $adapterBackup) -ceq $adapterBefore -and
    (Get-V2Hash $adapterFixture.Settings) -ceq $adapterApply.AfterSha256
) 'Adapter combined apply verified'

$adapterDiagnostic = Get-TypezeroOfflineTerminalCombinedV2RecoveryDiagnostic `
    -TestRoot $adapterFixture.Root `
    -BackupDirectory $adapterApply.BackupDirectory

Assert-V2 (
    $adapterDiagnostic.ReadOnly -and
    -not $adapterDiagnostic.RecoveryAllowed -and
    $adapterDiagnostic.State -ceq 'APPLIED_BYTES_PRESENT'
) 'Adapter applied diagnostic read-only'

$null = Restore-TypezeroOfflineTerminalCombinedTransactionV2 `
    -TestRoot $adapterFixture.Root `
    -BackupDirectory $adapterApply.BackupDirectory `
    -Execute -Confirm:$false

Assert-V2 (
    (Get-V2Hash $adapterFixture.Settings) -ceq $adapterBefore -and
    (Get-V2Hash $adapterBackup) -ceq $adapterBefore
) 'Adapter original settings restored'

$adapterFinal = Get-TypezeroOfflineTerminalCombinedV2RecoveryDiagnostic `
    -TestRoot $adapterFixture.Root `
    -BackupDirectory $adapterApply.BackupDirectory

Assert-V2 (
    $adapterFinal.ReadOnly -and
    $adapterFinal.State -ceq 'ORIGINAL_BYTES_PRESENT'
) 'Adapter restored diagnostic read-only'

Write-Host "`n=== ADAPTER REFUSAL TESTS ==="

$negativeHash = Get-V2Hash $adapterFixture.Settings
$originalMappingText = [IO.File]::ReadAllText($adapterConfig)

try {
    Assert-V2Blocked {
        Invoke-TypezeroOfflineFontMappingV2Transaction `
            -TestRoot $adapterFixture.Root -ConfigPath $adapterConfig `
            -ThemeId nonexistent -Theme $adapterTheme
    } 'No font mapping' 'Missing mapping rejected'

    $adapterMapping.Version = 1
    [IO.File]::WriteAllText(
        $adapterConfig,
        (($adapterMapping | ConvertTo-Json -Depth 10) + "`n"),
        $utf8
    )

    Assert-V2Blocked {
        Invoke-TypezeroOfflineFontMappingV2Transaction `
            -TestRoot $adapterFixture.Root -ConfigPath $adapterConfig `
            -ThemeId gruvbox -Theme $adapterTheme
    } '*' 'V1 mapping rejected'

    $adapterMapping.Version = 2
    $adapterMapping.Mappings.gruvbox.size = 99

    [IO.File]::WriteAllText(
        $adapterConfig,
        (($adapterMapping | ConvertTo-Json -Depth 10) + "`n"),
        $utf8
    )

    Assert-V2Blocked {
        Invoke-TypezeroOfflineFontMappingV2Transaction `
            -TestRoot $adapterFixture.Root -ConfigPath $adapterConfig `
            -ThemeId gruvbox -Theme $adapterTheme
    } '*' 'Invalid font size rejected'

    [IO.File]::WriteAllText($adapterConfig, $originalMappingText, $utf8)

    Assert-V2Blocked {
        Invoke-TypezeroOfflineFontMappingV2Transaction `
            -TestRoot $adapterFixture.Root `
            -ConfigPath (Join-Path $env:LOCALAPPDATA 'Typezero\ThemeEngine\font-windows-terminal.json') `
            -ThemeId gruvbox -Theme $adapterTheme
    } 'outside the fixture' 'External configuration rejected'

    Assert-V2Blocked {
        Invoke-TypezeroOfflineFontMappingV2Transaction `
            -TestRoot $env:LOCALAPPDATA `
            -ConfigPath $adapterConfig `
            -ThemeId gruvbox -Theme $adapterTheme
    } 'outside TEMP' 'Production root rejected'

    $hardlink = Join-Path $adapterFixture.Root 'font-v2-hardlink.json'

    New-Item -ItemType HardLink -Path $hardlink `
        -Target $adapterConfig -ErrorAction Stop | Out-Null

    try {
        Assert-V2Blocked {
            Invoke-TypezeroOfflineFontMappingV2Transaction `
                -TestRoot $adapterFixture.Root -ConfigPath $adapterConfig `
                -ThemeId gruvbox -Theme $adapterTheme
        } '*' 'Hardlinked configuration rejected'
    }
    finally {
        Remove-Item -LiteralPath $hardlink -Force
    }

    Assert-V2 (
        (Get-V2Hash $adapterFixture.Settings) -ceq $negativeHash
    ) 'Refusals preserve disposable settings'
}
finally {
    [IO.File]::WriteAllText($adapterConfig, $originalMappingText, $utf8)
}

Write-Host "`nPASS: Adapter refusal tests complete."
Write-Host "`nPASS: Adapter lifecycle checks complete."
