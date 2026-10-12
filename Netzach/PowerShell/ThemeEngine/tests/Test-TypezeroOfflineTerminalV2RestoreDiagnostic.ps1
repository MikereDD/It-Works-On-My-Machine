# Step 55F review regression. Requires PowerShell 7 on NETZACH.
# WRITES ONLY NEW DISPOSABLE %TEMP% FIXTURES. NEVER CALLS AN APPLY/RESTORE WRITER.
param(
    [Parameter(Mandatory)][string]$SourceDirectory
)
$ErrorActionPreference = 'Stop'
$dir = [IO.Path]::GetFullPath($SourceDirectory)
$names = @(
    'FontPatch-WindowsTerminal.ps1',
    'TerminalColorPatch-WindowsTerminal.ps1',
    'TerminalCombinedPatch-WindowsTerminal.ps1',
    'TerminalTransaction-WindowsTerminal.ps1',
    'TerminalReplace-WindowsTerminal.ps1',
    'TerminalTransactionV2-WindowsTerminal.ps1',
    'TerminalTransactionV2RestoreDiagnostic-WindowsTerminal.ps1'
)
$hashes = @{}
foreach ($name in $names) {
    $p = Join-Path $dir $name
    if (-not [IO.File]::Exists($p)) { throw "Required module is absent: $p" }
    $hashes[$p] = (Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash
    . $p
}

$live = Join-Path ([Environment]::GetFolderPath(
    [Environment+SpecialFolder]::LocalApplicationData
)) 'Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json'
$liveExisted = [IO.File]::Exists($live)
$liveHash = if ($liveExisted) {
    (Get-FileHash -LiteralPath $live -Algorithm SHA256).Hash
} else { $null }
$utf8 = [Text.UTF8Encoding]::new($false, $true)
$script:fixtureRoots = [Collections.Generic.List[string]]::new()
$script:passed = 0

function Save-Json([string]$Path, $Value) {
    [IO.File]::WriteAllText($Path, ($Value | ConvertTo-Json -Depth 8), $utf8)
}
function Hash-Bytes([byte[]]$Bytes) {
    [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($Bytes))
}
function New-Fixture {
    $root = Join-Path ([IO.Path]::GetTempPath()) (
        'typezero-terminal-txn-' + [guid]::NewGuid().ToString('N')
    )
    New-Item -ItemType Directory -Path $root -ErrorAction Stop | Out-Null
    $script:fixtureRoots.Add($root)
    $paths = Get-TypezeroOfflineTerminalV2Paths -TestRoot $root
    foreach ($p in @((Split-Path -Parent $paths.Settings), $paths.BackupRoot)) {
        New-Item -ItemType Directory -Path $p -Force -ErrorAction Stop | Out-Null
    }
    $originalBytes = $utf8.GetBytes('{"demo":"original"}')
    $appliedBytes  = $utf8.GetBytes('{"demo":"applied"}')
    $originalHash = Hash-Bytes $originalBytes
    $appliedHash = Hash-Bytes $appliedBytes
    [IO.File]::WriteAllBytes($paths.Settings, $originalBytes)
    $parentName = (Get-Date -Format 'yyyyMMdd-HHmmss-fffffff') + '-' +
        [guid]::NewGuid().ToString('N')
    $restoreName = (Get-Date -Format 'yyyyMMdd-HHmmss-fffffff') + '-' +
        [guid]::NewGuid().ToString('N')
    $parentFolder = Join-Path $paths.BackupRoot $parentName
    $restoreFolder = Join-Path $paths.BackupRoot $restoreName
    foreach ($p in @($parentFolder, $restoreFolder)) {
        New-Item -ItemType Directory -Path $p -ErrorAction Stop | Out-Null
    }
    $parentBackup = Join-Path $parentFolder 'settings-pre-replace.json'
    $restoreBackup = Join-Path $restoreFolder 'settings-pre-replace.json'
    [IO.File]::WriteAllBytes($parentBackup, $originalBytes)
    [IO.File]::WriteAllBytes($restoreBackup, $appliedBytes)
    $applyReceipt = [ordered]@{
        Version=2; Kind='TypezeroOfflineCombinedV2'; Operation='APPLY'
        SettingsPath=$paths.Settings; BeforeSha256=$originalHash
        AfterSha256=$appliedHash
        StageFileName=('.typezero-combined-' + [guid]::NewGuid().ToString('N') + '.tmp')
        BackupFileName='settings-pre-replace.json'
        Font='JetBrainsMono Nerd Font'; Weight='semi-bold'; Size=12
    }
    $restoreReceipt = [ordered]@{
        Version=2; Kind='TypezeroOfflineCombinedV2'; Operation='RESTORE'
        SettingsPath=$paths.Settings; BeforeSha256=$appliedHash
        AfterSha256=$originalHash
        StageFileName=('.typezero-combined-restore-' + [guid]::NewGuid().ToString('N') + '.tmp')
        BackupFileName='settings-pre-replace.json'
        ParentTransactionFolderName=$parentName
    }
    $applyReceiptPath = Join-Path $parentFolder 'receipt.json'
    $restoreReceiptPath = Join-Path $restoreFolder 'receipt.json'
    Save-Json $applyReceiptPath $applyReceipt
    Save-Json $restoreReceiptPath $restoreReceipt
    [pscustomobject]@{
        Root=$root; Paths=$paths; ParentFolder=$parentFolder
        RestoreFolder=$restoreFolder; ParentBackup=$parentBackup
        RestoreBackup=$restoreBackup; ParentReceiptPath=$applyReceiptPath
        RestoreReceiptPath=$restoreReceiptPath
        ApplyReceipt=$applyReceipt; RestoreReceipt=$restoreReceipt
        OriginalBytes=$originalBytes; AppliedBytes=$appliedBytes
    }
}
function Snapshot-Bytes([string]$Root) {
    @(
        Get-ChildItem -LiteralPath $Root -Recurse -File -Force |
        Sort-Object -Property FullName |
        ForEach-Object {
            $_.FullName + '|' +
                (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash
        }
    ) -join "`n"
}
function Assert-Case([string]$Name, [string]$ExpectedState,
                     [scriptblock]$Mutate,
                     [string]$ExpectedStage = 'MISSING') {
    $fixture = New-Fixture
    if ($Mutate) { & $Mutate $fixture }
    $before = Snapshot-Bytes $fixture.Root
    $report = Get-TypezeroOfflineTerminalCombinedV2RestoreRecoveryDiagnostic `
        -TestRoot $fixture.Root -BackupDirectory $fixture.RestoreFolder
    $after = Snapshot-Bytes $fixture.Root
    if ($report.State -cne $ExpectedState) {
        throw "${Name}: expected $ExpectedState; got $($report.State)"
    }
    if ($report.ReadOnly -cne $true -or
        $report.RecoveryAllowed -cne $false -or
        $report.OperationPhase -cne 'UNKNOWN' -or
        $report.StageAssociation -cne 'UNPROVEN') {
        throw "${Name}: mandatory safety contract failed."
    }
    if ($before -cne $after) {
        throw "${Name}: diagnostic modified fixture bytes."
    }
    if ($ExpectedStage -and $report.StageFileState -cne $ExpectedStage -and
        $ExpectedState -cin @('ORIGINAL_BYTES_PRESENT','APPLIED_BYTES_PRESENT','SETTINGS_CONFLICT','SETTINGS_MISSING')) {
        throw "${Name}: unexpected stage observation $($report.StageFileState)"
    }
    $script:passed++
    Write-Host ("PASS [{0:d2}] {1}: {2}" -f $script:passed,$Name,$report.State)
}

try {
    Assert-Case 'Valid RESTORE with original bytes' 'ORIGINAL_BYTES_PRESENT' $null
    Assert-Case 'Valid RESTORE with applied bytes' 'APPLIED_BYTES_PRESENT' {
        param($f) [IO.File]::WriteAllBytes($f.Paths.Settings,$f.AppliedBytes)
    }
    Assert-Case 'Missing RESTORE receipt' 'EVIDENCE_INCOMPLETE' {
        param($f) [IO.File]::Delete($f.RestoreReceiptPath)
    }
    Assert-Case 'Unknown RESTORE field' 'INVALID_RECEIPT' {
        param($f)
        $f.RestoreReceipt.Add('Extra','not allowed')
        Save-Json $f.RestoreReceiptPath $f.RestoreReceipt
    }
    Assert-Case 'Case-ambiguous duplicate field' 'INVALID_RECEIPT' {
        param($f)
        $raw = [IO.File]::ReadAllText($f.RestoreReceiptPath)
        [IO.File]::WriteAllText(
            $f.RestoreReceiptPath, $raw.Replace('"Operation":', '"operation":"RESTORE","Operation":'), $utf8
        )
    }
    Assert-Case 'Invalid UTF8 in RESTORE receipt' 'INVALID_RECEIPT' {
        param($f) [IO.File]::WriteAllBytes($f.RestoreReceiptPath,[byte[]]@(0xff,0xfe,0x7b))
    }
    Assert-Case 'Oversize RESTORE receipt' 'INVALID_RECEIPT' {
        param($f) [IO.File]::WriteAllBytes($f.RestoreReceiptPath,[byte[]]::new(65537))
    }
    Assert-Case 'Mis-cased RESTORE field' 'INVALID_RECEIPT' {
        param($f)
        $raw = [IO.File]::ReadAllText($f.RestoreReceiptPath)
        [IO.File]::WriteAllText($f.RestoreReceiptPath,
            $raw.Replace('"Operation":', '"operation":'),$utf8)
    }
    Assert-Case 'Invalid stage basename' 'INVALID_RECEIPT' {
        param($f) $f.RestoreReceipt.StageFileName='../outside.tmp'
        Save-Json $f.RestoreReceiptPath $f.RestoreReceipt
    }
    Assert-Case 'Missing parent receipt' 'PARENT_RECEIPT_MISSING' {
        param($f) [IO.File]::Delete($f.ParentReceiptPath)
    }
    Assert-Case 'Invalid parent APPLY receipt' 'INVALID_PARENT_RECEIPT' {
        param($f) $f.ApplyReceipt.Operation='RESTORE'
        Save-Json $f.ParentReceiptPath $f.ApplyReceipt
    }
    Assert-Case 'Parent linkage mismatch' 'PARENT_LINK_MISMATCH' {
        param($f) $f.RestoreReceipt.BeforeSha256=('A'*64)
        Save-Json $f.RestoreReceiptPath $f.RestoreReceipt
    }
    Assert-Case 'Parent original backup missing' 'PARENT_BACKUP_MISSING' {
        param($f) [IO.File]::Delete($f.ParentBackup)
    }
    Assert-Case 'Parent original backup mismatch' 'PARENT_BACKUP_HASH_MISMATCH' {
        param($f) [IO.File]::WriteAllText($f.ParentBackup,'tampered',$utf8)
    }
    Assert-Case 'RESTORE backup missing' 'RESTORE_BACKUP_MISSING' {
        param($f) [IO.File]::Delete($f.RestoreBackup)
    }
    Assert-Case 'RESTORE backup mismatch' 'RESTORE_BACKUP_HASH_MISMATCH' {
        param($f) [IO.File]::WriteAllText($f.RestoreBackup,'tampered',$utf8)
    }
    Assert-Case 'Disposable settings missing' 'SETTINGS_MISSING' {
        param($f) [IO.File]::Delete($f.Paths.Settings)
    }
    Assert-Case 'Disposable settings conflict' 'SETTINGS_CONFLICT' {
        param($f) [IO.File]::WriteAllText($f.Paths.Settings,'unexpected',$utf8)
    }
    Assert-Case 'Stage hash match remains unproven' 'ORIGINAL_BYTES_PRESENT' {
        param($f)
        $stage = Join-Path (Split-Path -Parent $f.Paths.Settings) `
            $f.RestoreReceipt.StageFileName
        [IO.File]::WriteAllBytes($stage, $f.OriginalBytes)
    } 'HASH_MATCH_UNPROVEN'
    Assert-Case 'Stage hash mismatch remains unproven' 'ORIGINAL_BYTES_PRESENT' {
        param($f)
        $stage = Join-Path (Split-Path -Parent $f.Paths.Settings) `
            $f.RestoreReceipt.StageFileName
        [IO.File]::WriteAllText($stage,'unrelated',$utf8)
    } 'HASH_MISMATCH_UNPROVEN'

    Write-Host "PASS: $script:passed offline RESTORE diagnostic cases."
    Write-Host 'Fixtures retained for independent review:'
    $script:fixtureRoots | ForEach-Object { Write-Host $_ }
}
finally {
    foreach ($p in $hashes.Keys) {
        if ((Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash -cne $hashes[$p]) {
            throw "SOURCE MODIFIED: $p"
        }
    }
    if ([IO.File]::Exists($live) -ne $liveExisted) {
        throw 'LIVE WINDOWS TERMINAL FILE EXISTENCE CHANGED!'
    }
    if ($liveExisted -and
        (Get-FileHash -LiteralPath $live -Algorithm SHA256).Hash -cne $liveHash) {
        throw 'LIVE WINDOWS TERMINAL SETTINGS CHANGED!'
    }
    Write-Host 'PASS: all source files byte-for-byte unchanged.'
    Write-Host 'PASS: live Windows Terminal settings unchanged.'
}
