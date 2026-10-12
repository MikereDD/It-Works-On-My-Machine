# Typezero ThemeEngine
# OFFLINE TEST TRANSACTIONS ONLY.
# Requires FontPatch, TerminalColorPatch and TerminalCombinedPatch.
# Production Windows Terminal settings cannot be targeted.

function Assert-TypezeroOfflinePlainPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    # Inspect each existing path component, including ancestors.
    # Missing components are permitted for not-yet-created backups.
    $cursor = [IO.Path]::GetFullPath($Path)

    while ($true) {
        try {
            $attributes = [IO.File]::GetAttributes($cursor)

            if (($attributes -band
                [IO.FileAttributes]::ReparsePoint) -ne 0) {
                throw "Redirected filesystem path rejected: $cursor"
            }
        }
        catch [IO.FileNotFoundException] {
        }
        catch [IO.DirectoryNotFoundException] {
        }

        $parent = [IO.Path]::GetDirectoryName($cursor)

        if ([string]::IsNullOrEmpty($parent) -or
            [string]::Equals(
                $parent,
                $cursor,
                [StringComparison]::OrdinalIgnoreCase
            )) {
            break
        }

        $cursor = $parent
    }
}

function Get-TypezeroOfflineTerminalTransactionPaths {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$TestRoot
    )

    $root = [IO.Path]::GetFullPath($TestRoot).
        TrimEnd([IO.Path]::DirectorySeparatorChar)

    $tempRoot = [IO.Path]::GetFullPath(
        [IO.Path]::GetTempPath()
    ).TrimEnd([IO.Path]::DirectorySeparatorChar)

    $parent = [IO.Path]::GetDirectoryName($root)
    $name = [IO.Path]::GetFileName($root)

    if (-not [string]::Equals(
        $parent, $tempRoot,
        [StringComparison]::OrdinalIgnoreCase
    ) -or $name -cnotmatch '^typezero-terminal-txn-[a-f0-9]{32}$') {
        throw 'Only a direct, specially named temporary test directory is allowed.'
    }

    $item = Get-Item -LiteralPath $root -ErrorAction Stop

    if ($item -isnot [IO.DirectoryInfo] -or
        ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
        throw 'Test directory is invalid or redirected.'
    }

    $settings = Join-Path $root (
        'Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe' +
        '\LocalState\settings.json'
    )

    $backupRoot = Join-Path $root `
        'Typezero\ThemeEngine\backups\terminal-combined'

    $realLocal = [Environment]::GetFolderPath(
        [Environment+SpecialFolder]::LocalApplicationData
    )

    $realSettings = Join-Path $realLocal (
        'Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe' +
        '\LocalState\settings.json'
    )

    if ($settings -ieq $realSettings) {
        throw 'Production Windows Terminal settings are prohibited.'
    }

    # Reject redirection anywhere along settings or backup paths.
    Assert-TypezeroOfflinePlainPath -Path $settings
    Assert-TypezeroOfflinePlainPath -Path $backupRoot

    [pscustomobject]@{
        Root       = $root
        Settings   = $settings
        BackupRoot = $backupRoot
    }
}

function Invoke-TypezeroOfflineTerminalCombinedTransaction {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory)][string]$TestRoot,
        [Parameter(Mandatory)]
        [System.Collections.IDictionary]$Theme,
        [Parameter(Mandatory)][string]$FontFace,
        [Parameter(Mandatory)]
        [ValidateRange(6,36)][double]$FontSize,
        [Parameter(Mandatory)]
        [ValidateSet('normal','semi-bold')][string]$FontWeight,
        [switch]$Execute
    )

    $paths = Get-TypezeroOfflineTerminalTransactionPaths `
        -TestRoot $TestRoot

    if (-not (Test-Path -LiteralPath $paths.Settings -PathType Leaf)) {
        throw 'Disposable settings file is missing.'
    }

    $beforeHash = (
        Get-FileHash -LiteralPath $paths.Settings -Algorithm SHA256
    ).Hash

    $bytes = [IO.File]::ReadAllBytes($paths.Settings)

    if ($bytes.Length -ge 3 -and
        $bytes[0] -eq 239 -and
        $bytes[1] -eq 187 -and
        $bytes[2] -eq 191) {
        throw 'UTF-8 BOM requires separate handling.'
    }

    $utf8 = [Text.UTF8Encoding]::new($false, $true)
    $original = $utf8.GetString($bytes)

    $candidate = New-TypezeroTerminalCombinedJsonCandidate `
        -JsonText $original `
        -Theme $Theme `
        -FontFace $FontFace `
        -FontSize $FontSize `
        -FontWeight $FontWeight

    if ((Get-FileHash -LiteralPath $paths.Settings -Algorithm SHA256).Hash -ne
        $beforeHash) {
        throw 'Disposable settings changed during candidate preparation.'
    }

    if (-not $Execute) {
        return [pscustomobject]@{
            Status     = 'PREVIEW'
            WouldChange = -not [string]::Equals(
                $original, $candidate, [StringComparison]::Ordinal
            )
            Font       = $FontFace
            Size       = $FontSize
            Weight     = $FontWeight
            TestRoot   = $paths.Root
        }
    }

    if ([string]::Equals(
        $original, $candidate, [StringComparison]::Ordinal
    )) {
        return [pscustomobject]@{
            Status   = 'NO_CHANGE'
            TestRoot = $paths.Root
        }
    }

    if (-not $PSCmdlet.ShouldProcess(
        $paths.Settings, 'Apply offline combined Terminal transaction'
    )) {
        return
    }

    $folder = Join-Path $paths.BackupRoot (
        (Get-Date -Format 'yyyyMMdd-HHmmss-fffffff') +
        '-' + [guid]::NewGuid().ToString('N')
    )

    New-Item -ItemType Directory -Path $folder -Force `
        -ErrorAction Stop | Out-Null

    $backup = Join-Path $folder 'settings-original.json'
    $receiptPath = Join-Path $folder 'receipt.json'

    Copy-Item -LiteralPath $paths.Settings -Destination $backup `
        -ErrorAction Stop

    if ((Get-FileHash -LiteralPath $backup -Algorithm SHA256).Hash -ne
        $beforeHash) {
        throw 'Pre-transaction backup checksum mismatch.'
    }

    $stage = Join-Path (Split-Path -Parent $paths.Settings) (
        '.typezero-combined-' + [guid]::NewGuid().ToString('N') + '.tmp'
    )

    try {
        [IO.File]::WriteAllText($stage, $candidate, $utf8)

        $afterHash = (
            Get-FileHash -LiteralPath $stage -Algorithm SHA256
        ).Hash

        $receipt = [ordered]@{
            Version      = 1
            Kind         = 'TypezeroOfflineCombined'
            SettingsPath = $paths.Settings
            BeforeSha256 = $beforeHash
            AfterSha256  = $afterHash
            Font         = $FontFace
            Size         = $FontSize
            Weight       = $FontWeight
        }

        [IO.File]::WriteAllText(
            $receiptPath,
            ($receipt | ConvertTo-Json -Depth 10),
            $utf8
        )

        if ((Get-FileHash -LiteralPath $paths.Settings -Algorithm SHA256).Hash -ne
            $beforeHash) {
            throw 'Settings changed before transaction write.'
        }

        Move-Item -LiteralPath $stage -Destination $paths.Settings `
            -Force -ErrorAction Stop

        $verifiedHash = (
            Get-FileHash -LiteralPath $paths.Settings -Algorithm SHA256
        ).Hash

        if ($verifiedHash -ne $afterHash) {
            throw "Transaction verification failed. Backup: $folder"
        }

        [pscustomobject]@{
            Status          = 'VERIFIED'
            BeforeSha256    = $beforeHash
            AfterSha256     = $afterHash
            BackupDirectory = $folder
        }
    }
    finally {
        if (Test-Path -LiteralPath $stage) {
            Remove-Item -LiteralPath $stage -Force
        }
    }
}

function Restore-TypezeroOfflineTerminalCombinedTransaction {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory)][string]$TestRoot,
        [Parameter(Mandatory)][string]$BackupDirectory,
        [switch]$Execute
    )

    $paths = Get-TypezeroOfflineTerminalTransactionPaths `
        -TestRoot $TestRoot

    $folder = [IO.Path]::GetFullPath($BackupDirectory).
        TrimEnd([IO.Path]::DirectorySeparatorChar)

    $parent = [IO.Path]::GetDirectoryName($folder)

    if (-not [string]::Equals(
        $parent, $paths.BackupRoot,
        [StringComparison]::OrdinalIgnoreCase
    )) {
        throw 'Backup directory is outside this test transaction root.'
    }

    # Reject redirected backup folders and receipt files.
    Assert-TypezeroOfflinePlainPath -Path $folder
    Assert-TypezeroOfflinePlainPath -Path (
        Join-Path $folder 'receipt.json'
    )
    Assert-TypezeroOfflinePlainPath -Path (
        Join-Path $folder 'settings-original.json'
    )

    $receiptPath = Join-Path $folder 'receipt.json'
    $backup = Join-Path $folder 'settings-original.json'

    if (-not (Test-Path -LiteralPath $receiptPath -PathType Leaf) -or
        -not (Test-Path -LiteralPath $backup -PathType Leaf)) {
        throw 'Offline transaction backup is incomplete.'
    }

    $receipt = Get-Content -LiteralPath $receiptPath -Raw |
        ConvertFrom-Json -ErrorAction Stop

    if ($receipt.Version -ne 1 -or
        $receipt.Kind -cne 'TypezeroOfflineCombined' -or
        $receipt.SettingsPath -ine $paths.Settings) {
        throw 'Transaction receipt does not match this test fixture.'
    }

    $backupHash = (
        Get-FileHash -LiteralPath $backup -Algorithm SHA256
    ).Hash

    if ($backupHash -ne $receipt.BeforeSha256) {
        throw 'Original transaction backup checksum mismatch.'
    }

    $currentHash = (
        Get-FileHash -LiteralPath $paths.Settings -Algorithm SHA256
    ).Hash

    if ($currentHash -ne $receipt.AfterSha256) {
        throw 'Settings changed since transaction. Restore blocked.'
    }

    if (-not $Execute) {
        return [pscustomobject]@{
            Status          = 'PREVIEW'
            BackupDirectory = $folder
            OriginalHash    = $receipt.BeforeSha256
        }
    }

    if (-not $PSCmdlet.ShouldProcess(
        $paths.Settings, 'Restore offline transaction byte-for-byte'
    )) {
        return
    }

    $stage = Join-Path (Split-Path -Parent $paths.Settings) (
        '.typezero-combined-restore-' +
        [guid]::NewGuid().ToString('N') + '.tmp'
    )

    try {
        Copy-Item -LiteralPath $backup -Destination $stage `
            -ErrorAction Stop

        if ((Get-FileHash -LiteralPath $stage -Algorithm SHA256).Hash -ne
            $receipt.BeforeSha256) {
            throw 'Restoration staging checksum mismatch.'
        }

        if ((Get-FileHash -LiteralPath $paths.Settings -Algorithm SHA256).Hash -ne
            $receipt.AfterSha256) {
            throw 'Settings changed before restore write.'
        }

        Move-Item -LiteralPath $stage -Destination $paths.Settings `
            -Force -ErrorAction Stop

        $finalHash = (
            Get-FileHash -LiteralPath $paths.Settings -Algorithm SHA256
        ).Hash

        if ($finalHash -ne $receipt.BeforeSha256) {
            throw 'Transaction restoration verification failed.'
        }

        [pscustomobject]@{
            Status            = 'RESTORED'
            OriginalHashMatch = $true
            BackupDirectory   = $folder
        }
    }
    finally {
        if (Test-Path -LiteralPath $stage) {
            Remove-Item -LiteralPath $stage -Force
        }
    }
}


# Read one plain file while denying write/delete sharing. These snapshots are
# observations, not a filesystem lock spanning the whole diagnostic.
function Get-TypezeroOfflineRecoveryFileSnapshot {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [switch]$IncludeBytes
    )

    Assert-TypezeroOfflinePlainPath -Path $Path
    $ancestor = [IO.Path]::GetDirectoryName($Path)
    while (-not [string]::IsNullOrEmpty($ancestor)) {
        try {
            if (([IO.File]::GetAttributes($ancestor) -band
                [IO.FileAttributes]::Directory) -eq 0) {
                throw "Recovery path component must be a plain directory: $ancestor"
            }
        }
        catch [IO.FileNotFoundException] { }
        catch [IO.DirectoryNotFoundException] { }
        $ancestor = [IO.Path]::GetDirectoryName($ancestor)
    }
    try {
        $attributes = [IO.File]::GetAttributes($Path)
    }
    catch [IO.FileNotFoundException] {
        return [pscustomobject]@{ Exists = $false; Sha256 = $null; Bytes = $null }
    }
    catch [IO.DirectoryNotFoundException] {
        return [pscustomobject]@{ Exists = $false; Sha256 = $null; Bytes = $null }
    }

    if (($attributes -band [IO.FileAttributes]::Directory) -ne 0) {
        throw "Recovery evidence must be a plain file: $Path"
    }

    $stream = [IO.File]::Open(
        $Path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read
    )
    $buffer = [IO.MemoryStream]::new()
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        $bytes = $null
        if ($IncludeBytes) {
            # Version 1 receipts are small; reject oversized evidence explicitly.
            if ($stream.Length -gt 65536) {
                throw 'Recovery receipt exceeds the 64 KiB inspection limit.'
            }
            $stream.CopyTo($buffer)
            $bytes = $buffer.ToArray()
            $hashBytes = $sha.ComputeHash($bytes)
        }
        else { $hashBytes = $sha.ComputeHash($stream) }
        $hash = [BitConverter]::ToString($hashBytes).Replace('-', '')
        [pscustomobject]@{ Exists = $true; Sha256 = $hash; Bytes = $bytes }
    }
    finally {
        $sha.Dispose()
        $buffer.Dispose()
        $stream.Dispose()
    }
}

function Get-TypezeroOfflineTerminalCombinedRecoveryDiagnostic {
    <#
    .SYNOPSIS
    Observes one disposable transaction without changing any file.
    .DESCRIPTION
    Version 1 receipts have no durable phase or staging filename. Before bytes
    can mean never applied or already restored; after bytes can mean applied or
    restoration not completed. Stage files are never associated with a receipt,
    even when their checksums match. Checksums prove consistency, not authenticity.
    No result authorizes recovery. Unsafe paths, types, I/O failures or detected
    evidence changes throw. A stable reread cannot exclude every concurrent race.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$TestRoot,
        [Parameter(Mandatory)][string]$BackupDirectory
    )

    if ($PSVersionTable.PSVersion.Major -lt 7) {
        throw 'Recovery diagnostics require PowerShell 7 or later.'
    }
    $paths = Get-TypezeroOfflineTerminalTransactionPaths -TestRoot $TestRoot
    $folder = [IO.Path]::GetFullPath($BackupDirectory).
        TrimEnd([IO.Path]::DirectorySeparatorChar)
    if (-not [string]::Equals(
        [IO.Path]::GetDirectoryName($folder), $paths.BackupRoot,
        [StringComparison]::OrdinalIgnoreCase
    )) {
        throw 'Backup directory is outside this test transaction root.'
    }
    Assert-TypezeroOfflinePlainPath -Path $folder
    $folderExists = $true
    try {
        $attributes = [IO.File]::GetAttributes($folder)
        if (($attributes -band [IO.FileAttributes]::Directory) -eq 0) {
            throw 'Recovery backup path must be a plain directory.'
        }
    }
    catch [IO.FileNotFoundException] { $folderExists = $false }
    catch [IO.DirectoryNotFoundException] { $folderExists = $false }

    # All file paths are derived locally. Receipt path fields are never followed.
    $receiptPath = Join-Path $folder 'receipt.json'
    $backupPath = Join-Path $folder 'settings-original.json'
    $snapshots = [ordered]@{}
    foreach ($path in @($paths.Settings, $receiptPath, $backupPath)) {
        $snapshots[$path] = Get-TypezeroOfflineRecoveryFileSnapshot -Path $path `
            -IncludeBytes:($path -eq $receiptPath)
    }
    $settings = $snapshots[$paths.Settings]
    $receipt = $snapshots[$receiptPath]
    $backup = $snapshots[$backupPath]

    $stageParent = Split-Path -Parent $paths.Settings
    $stagePattern = '\A\.typezero-combined-(?:restore-)?[a-f0-9]{32}\.tmp\z'
    $stagePaths = @(
        if (Test-Path -LiteralPath $stageParent -PathType Container -ErrorAction Stop) {
            Get-ChildItem -LiteralPath $stageParent -Force -ErrorAction Stop |
                Where-Object { $_.Name -cmatch $stagePattern } |
                Sort-Object Name | ForEach-Object { $_.FullName }
        }
    )
    foreach ($path in $stagePaths) {
        $snapshots[$path] = Get-TypezeroOfflineRecoveryFileSnapshot -Path $path
        if (-not $snapshots[$path].Exists) {
            throw 'Recovery evidence changed during diagnosis. Retry read-only inspection.'
        }
    }

    $result = [ordered]@{
        State = 'EVIDENCE_INCOMPLETE'
        ReadOnly = $true
        RecoveryAllowed = $false
        TestRoot = $paths.Root
        SettingsPath = $paths.Settings
        BackupDirectory = $folder
        ReceiptState = $(if ($receipt.Exists) { 'INVALID' } else { 'MISSING' })
        BackupIntegrity = $(if ($backup.Exists) { 'UNVERIFIED' } else { 'MISSING' })
        SettingsState = $(if ($settings.Exists) { 'UNTRUSTED' } else { 'MISSING' })
        CurrentSha256 = $settings.Sha256
        BeforeSha256 = $null
        AfterSha256 = $null
        StageFiles = @()
        Detail = 'Receipt and original backup are both required; operation phase is unknown.'
    }
    if (-not $folderExists) {
        $result.State = 'TRANSACTION_MISSING'
        $result.Detail = 'Selected transaction directory is missing; operation phase is unknown.'
    }

    if ($receipt.Exists) {
        $doc = $null
        try {
            $utf8 = [Text.UTF8Encoding]::new($false, $true)
            $doc = [Text.Json.JsonDocument]::Parse($utf8.GetString($receipt.Bytes))
            $root = $doc.RootElement
            if ($root.ValueKind -ne [Text.Json.JsonValueKind]::Object) {
                throw 'Receipt must be one JSON object.'
            }
            $names = [Collections.Generic.HashSet[string]]::new(
                [StringComparer]::OrdinalIgnoreCase
            )
            foreach ($property in $root.EnumerateObject()) {
                if (-not $names.Add($property.Name)) {
                    throw 'Receipt contains duplicate or case-ambiguous fields.'
                }
            }
            $version = $root.GetProperty('Version')
            if ($version.ValueKind -ne [Text.Json.JsonValueKind]::Number -or
                $version.GetInt32() -ne 1) {
                throw 'Receipt version must be integer 1.'
            }
            foreach ($name in @('Kind', 'SettingsPath', 'BeforeSha256', 'AfterSha256')) {
                if ($root.GetProperty($name).ValueKind -ne [Text.Json.JsonValueKind]::String) {
                    throw "Receipt field must be a string: $name"
                }
            }
            if ($root.GetProperty('Kind').GetString() -cne 'TypezeroOfflineCombined' -or
                -not [string]::Equals(
                    $root.GetProperty('SettingsPath').GetString(), $paths.Settings,
                    [StringComparison]::OrdinalIgnoreCase
                )) {
                throw 'Transaction receipt does not match this test fixture.'
            }
            $before = $root.GetProperty('BeforeSha256').GetString()
            $after = $root.GetProperty('AfterSha256').GetString()
            if ($before -cnotmatch '\A[0-9a-fA-F]{64}\z' -or
                $after -cnotmatch '\A[0-9a-fA-F]{64}\z' -or
                [string]::Equals($before, $after, [StringComparison]::OrdinalIgnoreCase)) {
                throw 'Receipt must contain two distinct SHA256 checksums.'
            }
            $result.ReceiptState = 'VALID'
            $result.BeforeSha256 = $before.ToUpperInvariant()
            $result.AfterSha256 = $after.ToUpperInvariant()
        }
        catch {
            $result.State = 'INVALID_RECEIPT'
            $result.Detail = 'Invalid receipt: ' + $_.Exception.Message
        }
        finally {
            if ($null -ne $doc) { $doc.Dispose() }
        }
    }

    if ($result.ReceiptState -eq 'VALID' -and $backup.Exists) {
        if ($backup.Sha256 -ne $result.BeforeSha256) {
            $result.BackupIntegrity = 'MISMATCH'
            $result.State = 'BACKUP_HASH_MISMATCH'
            $result.Detail = 'Original backup differs from the receipt; inspect evidence manually.'
        }
        else {
            $result.BackupIntegrity = 'MATCH'
            if (-not $settings.Exists) {
                $result.State = 'SETTINGS_MISSING'
                $result.Detail = 'Settings are missing; no restore or stage promotion is authorized.'
            }
            elseif ($settings.Sha256 -eq $result.BeforeSha256) {
                $result.State = 'ORIGINAL_BYTES_PRESENT'
                $result.SettingsState = 'BEFORE'
                $result.Detail = 'Original bytes are present: never applied or already restored; phase unknown.'
            }
            elseif ($settings.Sha256 -eq $result.AfterSha256) {
                $result.State = 'APPLIED_BYTES_PRESENT'
                $result.SettingsState = 'AFTER'
                $result.Detail = 'Applied bytes are present; verification or restoration completion is unknown.'
            }
            else {
                $result.State = 'SETTINGS_CONFLICT'
                $result.SettingsState = 'OTHER'
                $result.Detail = 'Settings match neither receipt checksum; inspect evidence manually.'
            }
        }
    }

    $result.StageFiles = @(
        foreach ($path in $stagePaths) {
            $hash = $snapshots[$path].Sha256
            $match = 'UNVERIFIED'
            if ($result.ReceiptState -eq 'VALID') {
                $match = if ($hash -eq $result.BeforeSha256) { 'BEFORE' }
                    elseif ($hash -eq $result.AfterSha256) { 'AFTER' }
                    else { 'OTHER' }
            }
            [pscustomobject]@{
                Path = $path
                Kind = $(if ([IO.Path]::GetFileName($path).StartsWith(
                    '.typezero-combined-restore-', [StringComparison]::Ordinal
                )) { 'RESTORE' } else { 'APPLY' })
                Sha256 = $hash
                ContentMatch = $match
                Association = 'UNPROVEN'
            }
        }
    )

    # Detect evidence changing between observations; never repair a race.
    foreach ($path in $snapshots.Keys) {
        $again = Get-TypezeroOfflineRecoveryFileSnapshot -Path $path
        if ($again.Exists -ne $snapshots[$path].Exists -or
            $again.Sha256 -ne $snapshots[$path].Sha256) {
            throw 'Recovery evidence changed during diagnosis. Retry read-only inspection.'
        }
    }
    Assert-TypezeroOfflinePlainPath -Path $folder
    if ((Test-Path -LiteralPath $folder -PathType Container -ErrorAction Stop) -ne $folderExists) {
        throw 'Recovery evidence changed during diagnosis. Retry read-only inspection.'
    }
    $againStagePaths = @(
        if (Test-Path -LiteralPath $stageParent -PathType Container -ErrorAction Stop) {
            Get-ChildItem -LiteralPath $stageParent -Force -ErrorAction Stop |
                Where-Object { $_.Name -cmatch $stagePattern } |
                Sort-Object Name | ForEach-Object { $_.FullName }
        }
    )
    if ([string]::Join('\n', $stagePaths) -cne [string]::Join('\n', $againStagePaths)) {
        throw 'Recovery evidence changed during diagnosis. Retry read-only inspection.'
    }
    [pscustomobject]$result
}

function Get-TypezeroOfflineTerminalCombinedRecoveryPreview {
    <#
    .SYNOPSIS
    Explains diagnostic evidence without performing recovery or changing files.
    .DESCRIPTION
    Only calls the read-only diagnostic. Version 1 evidence cannot establish a
    completed transaction phase or prove that any remaining stage belongs to
    this transaction. Suggested actions are information for human review and
    never authorize replacement, promotion, cleanup, or a recovery operation.
    Diagnostic path validation, stable-evidence checks and failures are retained.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$TestRoot,
        [Parameter(Mandatory)][string]$BackupDirectory
    )

    $diagnostic = Get-TypezeroOfflineTerminalCombinedRecoveryDiagnostic `
        -TestRoot $TestRoot -BackupDirectory $BackupDirectory

    $blockers = [Collections.Generic.List[string]]::new()
    $blockers.Add('OperationPhaseUnknown')
    $suggestedAction = 'ManualInspection'
    $detail = 'Inspect the selected transaction evidence manually. No recovery action is authorized; operation phase is unknown.'

    # Stage checksum matches do not prove association. Never recommend stage
    # deletion, promotion or any writer operation from these observations.
    if (@($diagnostic.StageFiles).Count -gt 0) {
        $blockers.Add('StageAssociationUnproven')
    }
    if ($diagnostic.ReceiptState -cne 'VALID') {
        $blockers.Add('ReceiptNotValid')
    }
    if ($diagnostic.BackupIntegrity -cne 'MATCH') {
        $blockers.Add('BackupNotVerified')
    }
    if ($diagnostic.SettingsState -ceq 'MISSING') {
        $blockers.Add('SettingsMissing')
    }
    elseif ($diagnostic.SettingsState -cnotin @('BEFORE', 'AFTER')) {
        $blockers.Add('SettingsNotMatched')
    }

    $consistentEvidence = (
        $diagnostic.ReadOnly -is [bool] -and $diagnostic.ReadOnly -and
        $diagnostic.RecoveryAllowed -is [bool] -and -not $diagnostic.RecoveryAllowed -and
        $diagnostic.ReceiptState -ceq 'VALID' -and
        $diagnostic.BackupIntegrity -ceq 'MATCH' -and
        @($diagnostic.StageFiles).Count -eq 0
    )
    if ($consistentEvidence -and
        $diagnostic.State -ceq 'ORIGINAL_BYTES_PRESENT' -and
        $diagnostic.SettingsState -ceq 'BEFORE') {
        $suggestedAction = 'NoReplacementIndicated'
        $detail = 'Observed settings match the original backup. No replacement is indicated. Never applied and already restored remain indistinguishable; operation phase is unknown.'
    }
    elseif ($consistentEvidence -and
        $diagnostic.State -ceq 'APPLIED_BYTES_PRESENT' -and
        $diagnostic.SettingsState -ceq 'AFTER') {
        $suggestedAction = 'ReviewExistingOfflineRestore'
        $blockers.Add('FreshWriterChecksRequired')
        $blockers.Add('RecoveryExecutionAuthorizationRequired')
        $detail = 'Observed settings match the applied checksum and the original backup matches the receipt. Human review of the existing offline restore may be appropriate. Any recovery execution requires separate authorization and fresh checks by that writer. Verification and restoration completion remain unknown.'
    }
    else {
        $blockers.Add('NoRecoveryRecommendationFromEvidence')
        if (@($diagnostic.StageFiles).Count -gt 0) {
            $detail = 'Stage files have UNPROVEN association even when bytes match a receipt checksum. Inspect the evidence manually; no stage cleanup, promotion, settings replacement or recovery action is authorized. Operation phase is unknown.'
        }
    }

    [pscustomobject]@{
        Status = 'PREVIEW'
        ObservedState = $diagnostic.State
        SuggestedAction = $suggestedAction
        Blockers = @($blockers.ToArray())
        Detail = $detail
        OperationPhase = 'UNKNOWN'
        ReadOnly = $true
        RecoveryAllowed = $false
        TestRoot = $diagnostic.TestRoot
        BackupDirectory = $diagnostic.BackupDirectory
        Diagnostic = $diagnostic
    }
}
