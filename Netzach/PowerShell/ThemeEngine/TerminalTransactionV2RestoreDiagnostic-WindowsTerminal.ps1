# Typezero ThemeEngine - Step 55F review (RECONSTRUCTED from Step 55E evidence).
# OFFLINE V2 RECEIPT OBSERVATION ONLY. This file is intentionally separate from
# BOTH transaction writers and the existing APPLY recovery diagnostic.
# Dot-source after the existing V2 module and its normal dependencies.
# No Execute/WhatIf/Confirm switches, file writes, cleanup, or phase inference.

function Read-TypezeroOfflineTerminalV2RestoreReceipt {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Paths,
        [Parameter(Mandatory)][string]$Folder
    )

    $folder = Assert-TypezeroOfflineTerminalV2Folder `
        -Paths $Paths -BackupDirectory $Folder
    $receiptPath = Join-Path $folder 'receipt.json'
    Assert-TypezeroOfflineReplacePlainPath -Path $receiptPath
    if (-not [IO.File]::Exists($receiptPath)) {
        throw 'V2 restore receipt is missing.'
    }
    Assert-TypezeroOfflineReplaceSingleLink -Path $receiptPath

    $bytes = [IO.File]::ReadAllBytes($receiptPath)
    if ($bytes.Length -gt 65536) { throw 'V2 restore receipt exceeds 64 KiB.' }
    $utf8 = [Text.UTF8Encoding]::new($false, $true)
    $json = $utf8.GetString($bytes)
    $doc = [Text.Json.JsonDocument]::Parse($json)
    try {
        $element = $doc.RootElement
        if ($element.ValueKind -ne [Text.Json.JsonValueKind]::Object) {
            throw 'V2 restore receipt must be an object.'
        }

        # Require exactly the fields emitted by the V2 RESTORE writer; reject
        # unknown, missing, duplicate and case-ambiguous property names.
        $expected = @(
            'Version', 'Kind', 'Operation', 'SettingsPath',
            'BeforeSha256', 'AfterSha256', 'StageFileName',
            'BackupFileName', 'ParentTransactionFolderName'
        )
        $allowed = [Collections.Generic.HashSet[string]]::new(
            [StringComparer]::Ordinal
        )
        foreach ($name in $expected) { [void]$allowed.Add($name) }
        $seen = [Collections.Generic.HashSet[string]]::new(
            [StringComparer]::OrdinalIgnoreCase
        )
        foreach ($property in $element.EnumerateObject()) {
            if (-not $seen.Add($property.Name)) {
                throw 'V2 restore receipt has duplicate or case-ambiguous fields.'
            }
            if (-not $allowed.Contains($property.Name)) {
                throw 'V2 restore receipt has an unknown or mis-cased field.'
            }
        }
        if ($seen.Count -ne $expected.Count) {
            throw 'V2 restore receipt is missing required fields.'
        }

        $version = $element.GetProperty('Version')
        if ($version.ValueKind -ne [Text.Json.JsonValueKind]::Number -or
            $version.GetInt32() -ne 2) {
            throw 'V2 restore receipt must have integer version 2.'
        }
        $data = [ordered]@{ Version = 2 }
        foreach ($name in $expected) {
            if ($name -ceq 'Version') { continue }
            $value = $element.GetProperty($name)
            if ($value.ValueKind -ne [Text.Json.JsonValueKind]::String) {
                throw "V2 restore receipt field must be a string: $name"
            }
            $data[$name] = $value.GetString()
        }

        if ($data.Kind -cne 'TypezeroOfflineCombinedV2' -or
            $data.Operation -cne 'RESTORE' -or
            -not [string]::Equals(
                $data.SettingsPath, $Paths.Settings,
                [StringComparison]::OrdinalIgnoreCase
            ) -or
            $data.StageFileName -cnotmatch
                '\A\.typezero-combined-restore-[a-f0-9]{32}\.tmp\z' -or
            $data.BackupFileName -cne 'settings-pre-replace.json' -or
            $data.ParentTransactionFolderName -cnotmatch
                '\A[0-9]{8}-[0-9]{6}-[0-9]{7}-[a-f0-9]{32}\z' -or
            $data.ParentTransactionFolderName -ceq [IO.Path]::GetFileName($folder)) {
            throw 'V2 restore receipt does not match an owned disposable transaction.'
        }
        foreach ($field in @('BeforeSha256', 'AfterSha256')) {
            if ($data[$field] -cnotmatch '\A[a-fA-F0-9]{64}\z') {
                throw "V2 restore receipt checksum invalid: $field"
            }
            $data[$field] = $data[$field].ToUpperInvariant()
        }
        if ($data.BeforeSha256 -ceq $data.AfterSha256) {
            throw 'V2 restore receipt checksums must be distinct.'
        }
        [pscustomobject]$data
    }
    finally { $doc.Dispose() }
}

function Get-TypezeroOfflineTerminalCombinedV2RestoreRecoveryDiagnostic {
    <#
      Read-only, offline, non-authorizing observation of a RESTORE receipt.
      Hash matches do NOT establish a durable phase, stage association,
      transaction authenticity or permission to recover anything.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$TestRoot,
        [Parameter(Mandatory)][string]$BackupDirectory
    )

    # These helpers enforce exact %TEMP% fixture roots and owned V2 folders.
    $paths = Get-TypezeroOfflineTerminalV2Paths -TestRoot $TestRoot
    $folder = Assert-TypezeroOfflineTerminalV2Folder `
        -Paths $paths -BackupDirectory $BackupDirectory
    $restoreReceiptPath = Join-Path $folder 'receipt.json'
    $restoreBackupPath = Join-Path $folder 'settings-pre-replace.json'

    # Path guard failures are intentionally exceptions, NOT recoverable states.
    foreach ($path in @($restoreReceiptPath, $restoreBackupPath, $paths.Settings)) {
        Assert-TypezeroOfflineReplacePlainPath -Path $path
        if ([IO.File]::Exists($path)) {
            Assert-TypezeroOfflineReplaceSingleLink -Path $path
        }
    }

    $report = [ordered]@{
        State = 'EVIDENCE_INCOMPLETE'
        ReadOnly = $true
        RecoveryAllowed = $false
        OperationPhase = 'UNKNOWN'
        ReceiptState = 'MISSING'
        ParentReceiptState = 'NOT_CHECKED'
        ParentBackupIntegrity = 'NOT_CHECKED'
        RestoreBackupIntegrity = 'NOT_CHECKED'
        SettingsState = 'NOT_CHECKED'
        StageFileState = 'NOT_CHECKED'
        StageAssociation = 'UNPROVEN'
        BeforeSha256 = $null
        AfterSha256 = $null
        ParentBackupDirectory = $null
        BackupDirectory = $folder
        TestRoot = $paths.Root
        Detail = 'RESTORE receipt missing; no recovery authorized.'
    }

    if (-not [IO.File]::Exists($restoreReceiptPath)) {
        return [pscustomobject]$report
    }
    try {
        $receipt = Read-TypezeroOfflineTerminalV2RestoreReceipt `
            -Paths $paths -Folder $folder
    }
    catch {
        $report.State = 'INVALID_RECEIPT'
        $report.ReceiptState = 'INVALID'
        $report.Detail = 'RESTORE receipt is malformed or unsupported; manual inspection required.'
        return [pscustomobject]$report
    }
    $report.ReceiptState = 'VALID'
    $report.BeforeSha256 = $receipt.BeforeSha256
    $report.AfterSha256 = $receipt.AfterSha256

    $parentFolder = Join-Path $paths.BackupRoot $receipt.ParentTransactionFolderName
    $parentFolder = Assert-TypezeroOfflineTerminalV2Folder `
        -Paths $paths -BackupDirectory $parentFolder
    $report.ParentBackupDirectory = $parentFolder
    $parentReceiptPath = Join-Path $parentFolder 'receipt.json'
    $parentBackupPath = Join-Path $parentFolder 'settings-pre-replace.json'
    foreach ($path in @($parentReceiptPath, $parentBackupPath)) {
        Assert-TypezeroOfflineReplacePlainPath -Path $path
        if ([IO.File]::Exists($path)) {
            Assert-TypezeroOfflineReplaceSingleLink -Path $path
        }
    }
    if (-not [IO.File]::Exists($parentReceiptPath)) {
        $report.State = 'PARENT_RECEIPT_MISSING'
        $report.ParentReceiptState = 'MISSING'
        $report.Detail = 'Referenced parent APPLY receipt is absent.'
        return [pscustomobject]$report
    }
    try {
        $parent = Read-TypezeroOfflineTerminalV2ApplyReceipt `
            -Paths $paths -Folder $parentFolder
    }
    catch {
        $report.State = 'INVALID_PARENT_RECEIPT'
        $report.ParentReceiptState = 'INVALID'
        $report.Detail = 'Referenced parent APPLY receipt is invalid.'
        return [pscustomobject]$report
    }
    $report.ParentReceiptState = 'VALID'
    if ($receipt.BeforeSha256 -cne $parent.AfterSha256 -or
        $receipt.AfterSha256 -cne $parent.BeforeSha256) {
        $report.State = 'PARENT_LINK_MISMATCH'
        $report.Detail = 'RESTORE hashes do not invert the parent APPLY receipt.'
        return [pscustomobject]$report
    }
    if (-not [IO.File]::Exists($parentBackupPath)) {
        $report.State = 'PARENT_BACKUP_MISSING'
        $report.ParentBackupIntegrity = 'MISSING'
        $report.Detail = 'Parent APPLY original backup is absent.'
        return [pscustomobject]$report
    }
    if ((Get-TypezeroOfflineTerminalV2Sha256 -Path $parentBackupPath) -cne
        $parent.BeforeSha256) {
        $report.State = 'PARENT_BACKUP_HASH_MISMATCH'
        $report.ParentBackupIntegrity = 'MISMATCH'
        $report.Detail = 'Parent APPLY original backup differs from receipt.'
        return [pscustomobject]$report
    }
    $report.ParentBackupIntegrity = 'MATCH'

    # Restore's own preserved pre-replace backup is the APPLIED byte image.
    if (-not [IO.File]::Exists($restoreBackupPath)) {
        $report.State = 'RESTORE_BACKUP_MISSING'
        $report.RestoreBackupIntegrity = 'MISSING'
        $report.Detail = 'RESTORE preserved pre-replace backup is absent.'
        return [pscustomobject]$report
    }
    if ((Get-TypezeroOfflineTerminalV2Sha256 -Path $restoreBackupPath) -cne
        $receipt.BeforeSha256) {
        $report.State = 'RESTORE_BACKUP_HASH_MISMATCH'
        $report.RestoreBackupIntegrity = 'MISMATCH'
        $report.Detail = 'RESTORE pre-replace backup differs from receipt.'
        return [pscustomobject]$report
    }
    $report.RestoreBackupIntegrity = 'MATCH'

    # Observation of a stage filename is never evidence of stage ownership.
    $stage = Join-Path (Split-Path -Parent $paths.Settings) $receipt.StageFileName
    Assert-TypezeroOfflineReplacePlainPath -Path $stage
    if ([IO.File]::Exists($stage)) {
        Assert-TypezeroOfflineReplaceSingleLink -Path $stage
        if ((Get-TypezeroOfflineTerminalV2Sha256 -Path $stage) -ceq
            $receipt.AfterSha256) {
            $report.StageFileState = 'HASH_MATCH_UNPROVEN'
        }
        else { $report.StageFileState = 'HASH_MISMATCH_UNPROVEN' }
    }
    else { $report.StageFileState = 'MISSING' }

    if (-not [IO.File]::Exists($paths.Settings)) {
        $report.State = 'SETTINGS_MISSING'
        $report.SettingsState = 'MISSING'
        $report.Detail = 'Disposable settings missing; operation phase unknown.'
        return [pscustomobject]$report
    }
    $current = Get-TypezeroOfflineTerminalV2Sha256 -Path $paths.Settings
    if ($current -ceq $receipt.AfterSha256) {
        $report.State = 'ORIGINAL_BYTES_PRESENT'
        $report.SettingsState = 'AFTER'
    }
    elseif ($current -ceq $receipt.BeforeSha256) {
        $report.State = 'APPLIED_BYTES_PRESENT'
        $report.SettingsState = 'BEFORE'
    }
    else {
        $report.State = 'SETTINGS_CONFLICT'
        $report.SettingsState = 'OTHER'
    }
    $report.Detail = 'Observed receipt/backup/settings hashes only; operation phase UNKNOWN.'
    [pscustomobject]$report
}
