# Typezero ThemeEngine -- V2 OFFLINE TRANSACTIONS ONLY.
# Deliberately separate from the untouched V1 transaction implementation.
# Requires dot-sourced FontPatch, TerminalColorPatch, TerminalCombinedPatch,
# TerminalTransaction (V1 path validator ONLY), and TerminalReplace modules.
# Do NOT deploy this file as a live writer. Every permitted destination lives
# under an exact, disposable %TEMP% fixture enforced by both dependencies.
# Intent receipts/hashes are NOT authentication or proof of a durable phase.

function Get-TypezeroOfflineTerminalV2Paths {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$TestRoot)

    foreach ($command in @(
        'Get-TypezeroOfflineTerminalTransactionPaths',
        'New-TypezeroTerminalCombinedJsonCandidate',
        'Invoke-TypezeroOfflineTerminalVerifiedReplace',
        'Assert-TypezeroOfflineReplacePlainPath',
        'Assert-TypezeroOfflineReplaceSingleLink'
    )) {
        if (-not (Get-Command $command -CommandType Function -ErrorAction SilentlyContinue)) {
            throw "V2 dependency not loaded: $command"
        }
    }
    $paths = Get-TypezeroOfflineTerminalTransactionPaths -TestRoot $TestRoot
    Assert-TypezeroOfflineReplacePlainPath -Path $paths.Settings
    Assert-TypezeroOfflineReplacePlainPath -Path $paths.BackupRoot
    $paths
}

function Assert-TypezeroOfflineTerminalV2Folder {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Paths,
          [Parameter(Mandatory)][string]$BackupDirectory)

    $folder = [IO.Path]::GetFullPath($BackupDirectory).TrimEnd('\', '/')
    if (-not [string]::Equals(
        [IO.Path]::GetDirectoryName($folder), $Paths.BackupRoot,
        [StringComparison]::OrdinalIgnoreCase
    ) -or [IO.Path]::GetFileName($folder) -cnotmatch
        '\A[0-9]{8}-[0-9]{6}-[0-9]{7}-[a-f0-9]{32}\z') {
        throw 'V2 backup directory is not an owned disposable transaction directory.'
    }
    Assert-TypezeroOfflineReplacePlainPath -Path $folder
    $folder
}

function New-TypezeroOfflineTerminalV2Folder {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Paths)

    Assert-TypezeroOfflineReplacePlainPath -Path $Paths.BackupRoot
    if (-not [IO.Directory]::Exists($Paths.BackupRoot)) {
        # Created only after outer -Execute / ShouldProcess authorization.
        New-Item -ItemType Directory -Path $Paths.BackupRoot -Force -ErrorAction Stop |
            Out-Null
    }
    $folder = Join-Path $Paths.BackupRoot (
        (Get-Date -Format 'yyyyMMdd-HHmmss-fffffff') + '-' +
        [guid]::NewGuid().ToString('N')
    )
    Assert-TypezeroOfflineReplacePlainPath -Path $folder
    New-Item -ItemType Directory -Path $folder -ErrorAction Stop | Out-Null
    $folder
}

function Write-TypezeroOfflineTerminalV2NewFile {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path,
          [Parameter(Mandatory)][byte[]]$Bytes)

    Assert-TypezeroOfflineReplacePlainPath -Path $Path
    # CreateNew never overwrites a preexisting stage, receipt, or backup.
    $stream = [IO.FileStream]::new(
        $Path, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write,
        [IO.FileShare]::None
    )
    try {
        $stream.Write($Bytes, 0, $Bytes.Length)
        $stream.Flush($true)
    }
    finally { $stream.Dispose() }
}

function Get-TypezeroOfflineTerminalV2Sha256 {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)
    (Get-FileHash -LiteralPath $Path -Algorithm SHA256 -ErrorAction Stop).Hash
}

function Read-TypezeroOfflineTerminalV2ApplyReceipt {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Paths,
          [Parameter(Mandatory)][string]$Folder)

    $folder = Assert-TypezeroOfflineTerminalV2Folder -Paths $Paths -BackupDirectory $Folder
    $receiptPath = Join-Path $folder 'receipt.json'
    Assert-TypezeroOfflineReplacePlainPath -Path $receiptPath
    if (-not [IO.File]::Exists($receiptPath)) {
        throw 'V2 apply receipt is missing.'
    }
    Assert-TypezeroOfflineReplaceSingleLink -Path $receiptPath
    $bytes = [IO.File]::ReadAllBytes($receiptPath)
    if ($bytes.Length -gt 65536) { throw 'V2 receipt exceeds 64 KiB.' }
    $utf8 = [Text.UTF8Encoding]::new($false, $true)
    $json = $utf8.GetString($bytes)
    $doc = [Text.Json.JsonDocument]::Parse($json)
    try {
        $element = $doc.RootElement
        if ($element.ValueKind -ne [Text.Json.JsonValueKind]::Object) {
            throw 'V2 receipt must be an object.'
        }
        $names = [Collections.Generic.HashSet[string]]::new(
            [StringComparer]::OrdinalIgnoreCase
        )
        foreach ($property in $element.EnumerateObject()) {
            if (-not $names.Add($property.Name)) {
                throw 'V2 receipt has duplicate or case-ambiguous fields.'
            }
        }
        $v = $element.GetProperty('Version')
        if ($v.ValueKind -ne [Text.Json.JsonValueKind]::Number -or
            $v.GetInt32() -ne 2) {
            throw 'V2 apply receipt must have integer version 2.'
        }
        $data = [ordered]@{ Version = 2 }
        foreach ($name in @(
            'Kind', 'Operation', 'SettingsPath', 'BeforeSha256',
            'AfterSha256', 'StageFileName', 'BackupFileName',
            'Font', 'Weight'
        )) {
            $value = $element.GetProperty($name)
            if ($value.ValueKind -ne [Text.Json.JsonValueKind]::String) {
                throw "V2 receipt field must be a string: $name"
            }
            $data[$name] = $value.GetString()
        }
        $size = $element.GetProperty('Size')
        if ($size.ValueKind -ne [Text.Json.JsonValueKind]::Number -or
            $size.GetDouble() -lt 6 -or $size.GetDouble() -gt 36) {
            throw 'V2 receipt font size invalid.'
        }
        $data['Size'] = $size.GetDouble()
        if ($data.Kind -cne 'TypezeroOfflineCombinedV2' -or
            $data.Operation -cne 'APPLY' -or
            -not [string]::Equals(
                $data.SettingsPath, $Paths.Settings,
                [StringComparison]::OrdinalIgnoreCase
            ) -or
            $data.BackupFileName -cne 'settings-pre-replace.json' -or
            $data.StageFileName -cnotmatch
                '\A\.typezero-combined-[a-f0-9]{32}\.tmp\z' -or
            $data.Weight -cnotin @('normal', 'semi-bold') -or
            [string]::IsNullOrWhiteSpace($data.Font)) {
            throw 'V2 apply receipt does not match the disposable transaction.'
        }
        foreach ($field in @('BeforeSha256', 'AfterSha256')) {
            if ($data[$field] -cnotmatch '\A[a-fA-F0-9]{64}\z') {
                throw "V2 receipt checksum invalid: $field"
            }
            $data[$field] = $data[$field].ToUpperInvariant()
        }
        if ($data.BeforeSha256 -ceq $data.AfterSha256) {
            throw 'V2 receipt checksums must be distinct.'
        }
        [pscustomobject]$data
    }
    finally { $doc.Dispose() }
}

function Invoke-TypezeroOfflineTerminalCombinedTransactionV2 {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory)][string]$TestRoot,
        [Parameter(Mandatory)][System.Collections.IDictionary]$Theme,
        [Parameter(Mandatory)][string]$FontFace,
        [Parameter(Mandatory)][ValidateRange(6,36)][double]$FontSize,
        [Parameter(Mandatory)][ValidateSet('normal','semi-bold')][string]$FontWeight,
        [switch]$Execute
    )

    $paths = Get-TypezeroOfflineTerminalV2Paths -TestRoot $TestRoot
    if (-not [IO.File]::Exists($paths.Settings)) {
        throw 'Disposable settings file is missing.'
    }
    Assert-TypezeroOfflineReplaceSingleLink -Path $paths.Settings
    $beforeHash = Get-TypezeroOfflineTerminalV2Sha256 -Path $paths.Settings
    $bytes = [IO.File]::ReadAllBytes($paths.Settings)
    if ($bytes.Length -ge 3 -and $bytes[0] -eq 239 -and
        $bytes[1] -eq 187 -and $bytes[2] -eq 191) {
        throw 'UTF-8 BOM requires separate handling.'
    }
    $utf8 = [Text.UTF8Encoding]::new($false, $true)
    $original = $utf8.GetString($bytes)
    $candidate = New-TypezeroTerminalCombinedJsonCandidate `
        -JsonText $original -Theme $Theme -FontFace $FontFace `
        -FontSize $FontSize -FontWeight $FontWeight

    if ((Get-TypezeroOfflineTerminalV2Sha256 -Path $paths.Settings) -ne $beforeHash) {
        throw 'Disposable settings changed during V2 candidate preparation.'
    }
    $changed = -not [string]::Equals(
        $original, $candidate, [StringComparison]::Ordinal
    )
    if (-not $Execute) {
        return [pscustomobject]@{
            Status = 'PREVIEW'; WouldChange = $changed; ReadOnly = $true
            TestRoot = $paths.Root; Font = $FontFace
            Size = $FontSize; Weight = $FontWeight
        }
    }
    if (-not $changed) {
        return [pscustomobject]@{ Status = 'NO_CHANGE'; TestRoot = $paths.Root }
    }
    if (-not $PSCmdlet.ShouldProcess(
        $paths.Settings, 'Apply V2 combined Terminal transaction to disposable fixture'
    )) { return }

    # From this point on retain ALL evidence on failure; never clean up stages.
    $folder = New-TypezeroOfflineTerminalV2Folder -Paths $paths
    $stage = Join-Path (Split-Path -Parent $paths.Settings) (
        '.typezero-combined-' + [guid]::NewGuid().ToString('N') + '.tmp'
    )
    $stageBytes = $utf8.GetBytes($candidate)
    Write-TypezeroOfflineTerminalV2NewFile -Path $stage -Bytes $stageBytes
    $afterHash = Get-TypezeroOfflineTerminalV2Sha256 -Path $stage
    $backup = Join-Path $folder 'settings-pre-replace.json'
    $receiptPath = Join-Path $folder 'receipt.json'
    $receipt = [ordered]@{
        Version = 2; Kind = 'TypezeroOfflineCombinedV2'; Operation = 'APPLY'
        SettingsPath = $paths.Settings; BeforeSha256 = $beforeHash
        AfterSha256 = $afterHash; StageFileName = [IO.Path]::GetFileName($stage)
        BackupFileName = 'settings-pre-replace.json'
        Font = $FontFace; Size = $FontSize; Weight = $FontWeight
    }
    Write-TypezeroOfflineTerminalV2NewFile -Path $receiptPath `
        -Bytes ($utf8.GetBytes(($receipt | ConvertTo-Json -Depth 8)))

    $replaced = Invoke-TypezeroOfflineTerminalVerifiedReplace `
        -TestRoot $paths.Root -StagePath $stage -BackupPath $backup `
        -ExpectedBeforeSha256 $beforeHash -ExpectedStageSha256 $afterHash `
        -Execute -Confirm:$false
    if ($replaced.Status -cne 'VERIFIED' -or -not $replaced.BackupVerified) {
        throw "V2 apply replacement could not be verified. Evidence: $folder"
    }
    [pscustomobject]@{
        Status = 'VERIFIED'; Version = 2; BeforeSha256 = $beforeHash
        AfterSha256 = $afterHash; BackupDirectory = $folder
        OriginalBackup = $backup; ReceiptPath = $receiptPath
    }
}

function Restore-TypezeroOfflineTerminalCombinedTransactionV2 {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory)][string]$TestRoot,
        [Parameter(Mandatory)][string]$BackupDirectory,
        [switch]$Execute
    )

    $paths = Get-TypezeroOfflineTerminalV2Paths -TestRoot $TestRoot
    $folder = Assert-TypezeroOfflineTerminalV2Folder `
        -Paths $paths -BackupDirectory $BackupDirectory
    $receipt = Read-TypezeroOfflineTerminalV2ApplyReceipt -Paths $paths -Folder $folder
    $backup = Join-Path $folder 'settings-pre-replace.json'
    Assert-TypezeroOfflineReplacePlainPath -Path $backup
    if (-not [IO.File]::Exists($backup)) {
        throw 'V2 original backup is missing.'
    }
    Assert-TypezeroOfflineReplaceSingleLink -Path $backup
    if ((Get-TypezeroOfflineTerminalV2Sha256 -Path $backup) -ne
        $receipt.BeforeSha256) {
        throw 'V2 original backup checksum mismatch.'
    }
    if (-not [IO.File]::Exists($paths.Settings)) {
        throw 'V2 disposable settings file is missing.'
    }
    Assert-TypezeroOfflineReplaceSingleLink -Path $paths.Settings
    if ((Get-TypezeroOfflineTerminalV2Sha256 -Path $paths.Settings) -ne
        $receipt.AfterSha256) {
        throw 'V2 settings changed since transaction. Restore blocked.'
    }
    if (-not $Execute) {
        return [pscustomobject]@{
            Status = 'PREVIEW'; ReadOnly = $true; BackupDirectory = $folder
            OriginalHash = $receipt.BeforeSha256
        }
    }
    if (-not $PSCmdlet.ShouldProcess(
        $paths.Settings, 'Restore V2 transaction in disposable fixture'
    )) { return }

    # A NEW backup directory for every restore attempt; preserve the V2 apply
    # receipt and its original backup intact. A failed restore leaves evidence.
    $restoreFolder = New-TypezeroOfflineTerminalV2Folder -Paths $paths
    $stage = Join-Path (Split-Path -Parent $paths.Settings) (
        '.typezero-combined-restore-' + [guid]::NewGuid().ToString('N') + '.tmp'
    )
    $backupBytes = [IO.File]::ReadAllBytes($backup)
    Write-TypezeroOfflineTerminalV2NewFile -Path $stage -Bytes $backupBytes
    $restoreReceipt = [ordered]@{
        Version = 2; Kind = 'TypezeroOfflineCombinedV2'; Operation = 'RESTORE'
        SettingsPath = $paths.Settings; BeforeSha256 = $receipt.AfterSha256
        AfterSha256 = $receipt.BeforeSha256
        StageFileName = [IO.Path]::GetFileName($stage)
        BackupFileName = 'settings-pre-replace.json'
        ParentTransactionFolderName = [IO.Path]::GetFileName($folder)
    }
    $utf8 = [Text.UTF8Encoding]::new($false, $true)
    Write-TypezeroOfflineTerminalV2NewFile `
        -Path (Join-Path $restoreFolder 'receipt.json') `
        -Bytes ($utf8.GetBytes(($restoreReceipt | ConvertTo-Json -Depth 8)))

    # Recheck source backup after stage creation; no stage cleanup on conflict.
    Assert-TypezeroOfflineReplaceSingleLink -Path $backup
    if ((Get-TypezeroOfflineTerminalV2Sha256 -Path $backup) -ne
        $receipt.BeforeSha256) {
        throw "V2 backup changed during restore preparation. Evidence: $restoreFolder"
    }
    $replaced = Invoke-TypezeroOfflineTerminalVerifiedReplace `
        -TestRoot $paths.Root -StagePath $stage `
        -BackupPath (Join-Path $restoreFolder 'settings-pre-replace.json') `
        -ExpectedBeforeSha256 $receipt.AfterSha256 `
        -ExpectedStageSha256 $receipt.BeforeSha256 `
        -Execute -Confirm:$false
    if ($replaced.Status -cne 'VERIFIED' -or -not $replaced.BackupVerified) {
        throw "V2 restore replacement could not be verified. Evidence: $restoreFolder"
    }
    [pscustomobject]@{
        Status = 'RESTORED'; Version = 2; OriginalHashMatch = $true
        BackupDirectory = $folder; RestoreBackupDirectory = $restoreFolder
        AppliedBackup = Join-Path $restoreFolder 'settings-pre-replace.json'
    }
}

function Get-TypezeroOfflineTerminalCombinedV2RecoveryDiagnostic {
    <# Read-only observations only. No cleanup, promotion, recovery authorization,
       nor trust in declared receipt phase or stage-file association. #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$TestRoot,
        [Parameter(Mandatory)][string]$BackupDirectory
    )

    $paths = Get-TypezeroOfflineTerminalV2Paths -TestRoot $TestRoot
    $folder = Assert-TypezeroOfflineTerminalV2Folder `
        -Paths $paths -BackupDirectory $BackupDirectory
    $receiptPath = Join-Path $folder 'receipt.json'
    $backupPath = Join-Path $folder 'settings-pre-replace.json'
    foreach ($path in @($receiptPath, $backupPath, $paths.Settings)) {
        Assert-TypezeroOfflineReplacePlainPath -Path $path
        if ([IO.File]::Exists($path)) {
            Assert-TypezeroOfflineReplaceSingleLink -Path $path
        }
    }
    $state = 'EVIDENCE_INCOMPLETE'
    $receiptState = 'MISSING'
    $backupState = 'MISSING'
    $settingsState = 'MISSING'
    $before = $null
    $after = $null
    $detail = 'Receipt and preserved original are required; phase unknown.'
    if ([IO.File]::Exists($receiptPath)) {
        try {
            $receipt = Read-TypezeroOfflineTerminalV2ApplyReceipt `
                -Paths $paths -Folder $folder
            $receiptState = 'VALID'
            $before = $receipt.BeforeSha256
            $after = $receipt.AfterSha256
        }
        catch {
            $receiptState = 'INVALID'
            $state = 'INVALID_RECEIPT'
            $detail = 'Invalid or unsupported V2 apply receipt; manual inspection required.'
        }
    }
    if ($receiptState -ceq 'VALID' -and [IO.File]::Exists($backupPath)) {
        if ((Get-TypezeroOfflineTerminalV2Sha256 $backupPath) -ne $before) {
            $state = 'BACKUP_HASH_MISMATCH'
            $backupState = 'MISMATCH'
            $detail = 'Backup disagrees with receipt; no recovery authorized.'
        }
        else {
            $backupState = 'MATCH'
            if ([IO.File]::Exists($paths.Settings)) {
                $current = Get-TypezeroOfflineTerminalV2Sha256 $paths.Settings
                if ($current -eq $before) {
                    $state = 'ORIGINAL_BYTES_PRESENT'; $settingsState = 'BEFORE'
                }
                elseif ($current -eq $after) {
                    $state = 'APPLIED_BYTES_PRESENT'; $settingsState = 'AFTER'
                }
                else { $state = 'SETTINGS_CONFLICT'; $settingsState = 'OTHER' }
                $detail = 'Observed hashes are consistent only; operation phase remains unknown.'
            }
            else {
                $state = 'SETTINGS_MISSING'; $detail = 'Settings absent; manual inspection.'
            }
        }
    }
    [pscustomobject]@{
        State = $state; ReadOnly = $true; RecoveryAllowed = $false
        OperationPhase = 'UNKNOWN'; ReceiptState = $receiptState
        BackupIntegrity = $backupState; SettingsState = $settingsState
        BeforeSha256 = $before; AfterSha256 = $after
        TestRoot = $paths.Root; BackupDirectory = $folder
        Detail = $detail
    }
}
