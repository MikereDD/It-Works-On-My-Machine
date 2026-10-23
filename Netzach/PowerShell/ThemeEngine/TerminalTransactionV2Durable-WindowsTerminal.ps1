# Typezero ThemeEngine: authenticated durable transactions in disposable fixtures.
# No production writer, key storage, automatic recovery, or grant issuer exists here.
# Only the three exported entry points can advance the private phase machine.
New-Module -Name TypezeroDurableFixtureV2 -ScriptBlock {
    Set-StrictMode -Version Latest
    $utf8 = [Text.UTF8Encoding]::new($false, $true)
    $phases = @('INTENT', 'PREPARED', 'REPLACED', 'COMPLETE')
    $recordNames = @('Version','Sequence','Phase','PreviousSha256','Kind',
        'FixtureRoot','BackupDirectory','Operation','ParentBackupDirectory',
        'GrantId','GrantSha256','AuthorizationMacSha256','ReservationSha256',
        'SourceChainSha256','SettingsPath','BeforeSha256','AfterSha256',
        'StageFileName','BackupFileName','ReceiptSha256','HmacSha256')
    $fileNames = @('000001.intent.json','000002.prepared.json',
        '000003.replaced.json','000004.complete.json')
    $zero = '0' * 64
    $markerText = 'TYPEZERO-V2-DURABLE-FIXTURE-1'
    # v1.1: writer and reader share inclusive encoded-byte limits.
    $settingsLimit = 16777216
    $receiptLimit = 65536
    $recordLimit = 32768
    $grantLimit = 16384
    $reservationLimit = 32768

    function Assert-Size([byte[]]$Bytes, [int]$Limit, [string]$Kind) {
        if ($null -eq $Bytes -or $Bytes.Length -gt $Limit) {
            throw ('REFUSED: Durable ' + $Kind + ' exceeds its byte size limit (' + $Limit + ').')
        }
    }
    function Encode-Bounded([string]$Text, [int]$Limit, [string]$Kind) {
        if ($utf8.GetByteCount($Text) -gt $Limit) {
            throw ('REFUSED: Durable ' + $Kind + ' exceeds its byte size limit (' + $Limit + ').')
        }
        return ,$utf8.GetBytes($Text)
    }

    function Assert-Key([byte[]]$Key) {
        if ($null -eq $Key -or $Key.Length -ne 32) {
            throw 'REFUSED: An independent 32-byte evidence key is required.'
        }
    }
    function Hash-Bytes([byte[]]$Bytes) {
        [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($Bytes))
    }
    function Read-Bytes([string]$Path, [int]$Limit = 16777216) {
        Assert-TypezeroOfflineReplacePlainPath -Path $Path
        if (-not [IO.File]::Exists($Path)) { throw 'Required durable evidence is missing.' }
        Assert-TypezeroOfflineReplaceSingleLink -Path $Path
        $stream = [IO.File]::Open($Path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
        try {
            if ($stream.Length -gt $Limit) { throw 'REFUSED: Durable evidence exceeds its byte size limit.' }
            $bytes = [byte[]]::new([int]$stream.Length)
            $offset=0
            while ($offset -lt $bytes.Length) {
                $read=$stream.Read($bytes,$offset,$bytes.Length-$offset)
                if ($read -eq 0) { throw 'Required durable evidence ended during its bounded read.' }
                $offset+=$read
            }
            return ,$bytes
        }
        finally { $stream.Dispose() }
    }
    function Read-Object([byte[]]$Bytes, [string[]]$Names, [string[]]$Integers) {
        $doc = [Text.Json.JsonDocument]::Parse($utf8.GetString($Bytes))
        try {
            $root = $doc.RootElement
            if ($root.ValueKind -ne [Text.Json.JsonValueKind]::Object) { throw 'Evidence must be an object.' }
            $properties = @($root.EnumerateObject())
            if ($properties.Count -ne $Names.Count) { throw 'Unexpected evidence field count.' }
            $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
            $values = @{}
            foreach ($p in $properties) {
                if (-not $seen.Add($p.Name) -or $p.Name -cnotin $Names) {
                    throw 'Unknown, duplicate, or case-ambiguous evidence field.'
                }
                if ($p.Name -cin $Integers) {
                    if ($p.Value.ValueKind -ne [Text.Json.JsonValueKind]::Number -or
                        $p.Value.GetRawText() -cnotmatch '\A[0-9]+\z') { throw 'Invalid evidence integer.' }
                    $values[$p.Name] = $p.Value.GetInt32()
                }
                else {
                    if ($p.Value.ValueKind -ne [Text.Json.JsonValueKind]::String) { throw 'Evidence fields must be strings.' }
                    $values[$p.Name] = $p.Value.GetString()
                }
            }
            $result = [ordered]@{}
            foreach ($name in $Names) {
                if (-not $seen.Contains($name)) { throw 'Required evidence field is missing.' }
                $result[$name] = $values[$name]
            }
            return ,$result
        }
        finally { $doc.Dispose() }
    }
    function Get-Mac($Record, [byte[]]$Key) {
        $stream = [IO.MemoryStream]::new()
        $writer = [IO.BinaryWriter]::new($stream, $utf8, $true)
        try {
            foreach ($value in @('TYPEZERO-V2-DURABLE-PHASE-1') + @(
                foreach ($name in $recordNames) {
                    if ($name -cne 'HmacSha256') { [string]$Record[$name] }
                }
            )) {
                $bytes = $utf8.GetBytes($value)
                $writer.Write([int]$bytes.Length); $writer.Write($bytes)
            }
            $writer.Flush()
            return ,[Security.Cryptography.HMACSHA256]::HashData($Key, $stream.ToArray())
        }
        finally { $writer.Dispose(); $stream.Dispose() }
    }
    function Get-Store($Paths, [switch]$Create) {
        $store = Join-Path $Paths.Root '.typezero-terminal-v2-durable'
        Assert-TypezeroOfflineReplacePlainPath -Path $store
        if ([IO.File]::Exists($store)) { throw 'REFUSED: Durable store is not a directory.' }
        if (-not [IO.Directory]::Exists($store)) {
            if (-not $Create) { return $store }
            [IO.Directory]::CreateDirectory($store) | Out-Null
            Write-TypezeroOfflineTerminalV2NewFile -Path (Join-Path $store '.fixture') -Bytes $utf8.GetBytes($markerText)
        }
        if ($utf8.GetString((Read-Bytes (Join-Path $store '.fixture') 128)) -cne $markerText) {
            throw 'REFUSED: Partial or invalid durable store marker.'
        }
        foreach ($item in @(Get-ChildItem -LiteralPath $store -Force -ErrorAction Stop)) {
            Assert-TypezeroOfflineReplacePlainPath -Path $item.FullName
            if ($item.Name -ceq '.fixture' -and -not $item.PSIsContainer) { continue }
            if (-not $item.PSIsContainer -or $item.Name -cnotmatch '\A[0-9]{8}-[0-9]{6}-[0-9]{7}-[a-f0-9]{32}\z') {
                throw 'REFUSED: Unexpected durable store evidence.'
            }
        }
        $store
    }
    function Read-Journal($Paths, [string]$Folder, [byte[]]$Key) {
        $folder = Assert-TypezeroOfflineTerminalV2Folder -Paths $Paths -BackupDirectory $Folder
        $store = Get-Store $Paths
        $journal = Join-Path $store ([IO.Path]::GetFileName($folder))
        Assert-TypezeroOfflineReplacePlainPath -Path $journal
        if (-not [IO.Directory]::Exists($journal)) { throw 'Authenticated durable journal is missing; legacy phase remains UNKNOWN.' }
        $entries = @(Get-ChildItem -LiteralPath $journal -Force -ErrorAction Stop)
        if ($entries.Count -lt 1 -or $entries.Count -gt 4) { throw 'Partial or extra durable journal evidence.' }
        foreach ($entry in $entries) {
            if ($entry.PSIsContainer -or $entry.Name -cnotin $fileNames) { throw 'Unexpected durable journal entry.' }
        }
        $previous = $zero; $first = $null; $last = $null
        for ($i = 0; $i -lt $entries.Count; $i++) {
            $bytes = Read-Bytes (Join-Path $journal $fileNames[$i]) $recordLimit
            $record = Read-Object $bytes $recordNames @('Version','Sequence')
            # The final record has no successor digest to protect its encoding.
            # Require the exact writer representation as well as its signed fields.
            $canonical = $utf8.GetBytes(($record | ConvertTo-Json -Compress))
            if (-not [Security.Cryptography.CryptographicOperations]::FixedTimeEquals($bytes, $canonical)) {
                throw 'Noncanonical durable journal bytes.'
            }
            if ($record.Version -ne 2 -or $record.Sequence -ne ($i + 1) -or
                $record.Phase -cne $phases[$i] -or $record.PreviousSha256 -cne $previous -or
                $record.Kind -cne 'TypezeroFixtureDurableTransactionV2' -or
                $record.FixtureRoot -cne $Paths.Root -or $record.BackupDirectory -cne $folder -or
                $record.SettingsPath -cne $Paths.Settings -or $record.Operation -cnotin @('APPLY','RESTORE') -or
                $record.BackupFileName -cne 'settings-pre-replace.json' -or
                $record.StageFileName -cnotmatch '\A\.typezero-combined-(?:restore-)?[a-f0-9]{32}\.tmp\z') {
                throw 'Durable phase or transaction identity mismatch.'
            }
            foreach ($name in @('BeforeSha256','AfterSha256','ReceiptSha256','HmacSha256')) {
                if ($record[$name] -cnotmatch '\A[A-F0-9]{64}\z') { throw 'Invalid durable evidence digest.' }
            }
            if ($record.BeforeSha256 -ceq $record.AfterSha256) { throw 'Durable transaction hashes must differ.' }
            if ($record.Operation -ceq 'APPLY') {
                if ($record.StageFileName -cmatch '-restore-') { throw 'Invalid apply stage identity.' }
                foreach ($name in @('ParentBackupDirectory','GrantId','GrantSha256','AuthorizationMacSha256','ReservationSha256','SourceChainSha256')) {
                    if ($record[$name] -cne '') { throw 'Apply must not contain recovery authority.' }
                }
            }
            else {
                if ($record.StageFileName -cnotmatch '-restore-' -or $record.GrantId -cnotmatch '\A[a-f0-9]{32}\z' -or
                    (Assert-TypezeroOfflineTerminalV2Folder -Paths $Paths -BackupDirectory $record.ParentBackupDirectory) -cne $record.ParentBackupDirectory -or
                    $record.ParentBackupDirectory -ceq $folder) { throw 'Invalid restore source identity.' }
                foreach ($name in @('GrantSha256','AuthorizationMacSha256','ReservationSha256','SourceChainSha256')) {
                    if ($record[$name] -cnotmatch '\A[A-F0-9]{64}\z') { throw 'Invalid restore authorization digest.' }
                }
            }
            if (-not [Security.Cryptography.CryptographicOperations]::FixedTimeEquals(
                [Convert]::FromHexString($record.HmacSha256), (Get-Mac $record $Key))) { throw 'Durable phase authentication failed.' }
            if ($null -eq $first) { $first = $record }
            else {
                foreach ($name in $recordNames) {
                    if ($name -cnotin @('Sequence','Phase','PreviousSha256','HmacSha256') -and
                        [string]$record[$name] -cne [string]$first[$name]) { throw 'Durable transaction metadata changed between phases.' }
                }
            }
            $previous = Hash-Bytes $bytes; $last = $record
        }
        [pscustomobject]@{ Record=$first; Last=$last; Digest=$previous; Count=$entries.Count; Complete=($entries.Count -eq 4); Journal=$journal }
    }
    function Assert-Snapshot($Paths, $State, [byte[]]$Key) {
        $r = $State.Record; $folder = $r.BackupDirectory
        $expected = @('receipt.json','settings-pre-replace.json','evidence.seal')
        if ($r.Operation -ceq 'RESTORE') { $expected += @('grant.json','authorization.mac') }
        $entries = @(Get-ChildItem -LiteralPath $folder -Force -ErrorAction Stop)
        if ($entries.Count -ne $expected.Count) { throw 'Partial or extra transaction evidence.' }
        foreach ($entry in $entries) {
            if ($entry.PSIsContainer -or $entry.Name -cnotin $expected) { throw 'Unexpected transaction evidence.' }
        }
        $receiptBytes = Read-Bytes (Join-Path $folder 'receipt.json') $receiptLimit
        $backupBytes = Read-Bytes (Join-Path $folder 'settings-pre-replace.json')
        $sealBytes = Read-Bytes (Join-Path $folder 'evidence.seal') 32
        if ((Hash-Bytes $receiptBytes) -cne $r.ReceiptSha256 -or (Hash-Bytes $backupBytes) -cne $r.BeforeSha256 -or
            -not [TypezeroEvidenceSealCryptoV2]::Equal($sealBytes, [TypezeroEvidenceSealCryptoV2]::Compute($Key,$receiptBytes,$backupBytes))) {
            throw 'Durable receipt, backup, or seal authentication failed.'
        }
        if ($r.Operation -ceq 'APPLY') {
            # Require exact legacy schema as well as the authenticated exact bytes.
            $doc = [Text.Json.JsonDocument]::Parse($utf8.GetString($receiptBytes))
            try {
                $names = @('Version','Kind','Operation','SettingsPath','BeforeSha256','AfterSha256','StageFileName','BackupFileName','Font','Size','Weight')
                $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
                $props = @($doc.RootElement.EnumerateObject())
                if ($props.Count -ne $names.Count) { throw 'Unknown apply receipt field.' }
                foreach ($p in $props) {
                    if (-not $seen.Add($p.Name) -or $p.Name -cnotin $names) { throw 'Ambiguous apply receipt field.' }
                }
            }
            finally { $doc.Dispose() }
            $receipt = Read-TypezeroOfflineTerminalV2ApplyReceipt -Paths $Paths -Folder $folder
        }
        else {
            $receipt = Read-Object $receiptBytes @('Version','Kind','Operation','SettingsPath','BeforeSha256','AfterSha256','StageFileName','BackupFileName','ParentTransactionFolderName') @('Version')
            if ($receipt.Version -ne 2 -or $receipt.Kind -cne 'TypezeroOfflineCombinedV2' -or
                $receipt.ParentTransactionFolderName -cne [IO.Path]::GetFileName($r.ParentBackupDirectory)) { throw 'Invalid restore receipt.' }
            $grantBytes = Read-Bytes (Join-Path $folder 'grant.json') $grantLimit
            $authBytes = Read-Bytes (Join-Path $folder 'authorization.mac') 32
            $replay = Get-TypezeroOfflineTerminalV2ReplayContext -TestRoot $Paths.Root
            $reservationBytes = Read-Bytes (Join-Path $replay.Store ($r.GrantId + '.reserved')) $reservationLimit
            if ((Hash-Bytes $grantBytes) -cne $r.GrantSha256 -or (Hash-Bytes $authBytes) -cne $r.AuthorizationMacSha256 -or
                $authBytes.Length -ne 32 -or (Hash-Bytes $reservationBytes) -cne $r.ReservationSha256) { throw 'Restore authority or reservation evidence changed.' }
            $reservation = Read-Object $reservationBytes @('Version','Kind','GrantId','TestRoot','BackupDirectory','GrantSha256') @('Version')
            if ($reservation.Version -ne 2 -or $reservation.Kind -cne 'TypezeroFixtureRecoveryReservationV2' -or
                $reservation.GrantId -cne $r.GrantId -or $reservation.TestRoot -cne $Paths.Root -or
                $reservation.BackupDirectory -cne $r.ParentBackupDirectory -or $reservation.GrantSha256 -cne $r.GrantSha256) { throw 'Restore reservation identity mismatch.' }
            $source = Read-Journal $Paths $r.ParentBackupDirectory $Key
            if (-not $source.Complete -or $source.Record.Operation -cne 'APPLY' -or $source.Digest -cne $r.SourceChainSha256 -or
                $source.Record.BeforeSha256 -cne $r.AfterSha256 -or $source.Record.AfterSha256 -cne $r.BeforeSha256) { throw 'Restore source chain mismatch.' }
            Assert-Snapshot $Paths $source $Key
        }
        foreach ($name in @('Operation','SettingsPath','BeforeSha256','AfterSha256','StageFileName','BackupFileName')) {
            if ([string]$receipt.$name -cne [string]$r[$name]) { throw 'Receipt differs from durable intent.' }
        }
        $stage = Join-Path ([IO.Path]::GetDirectoryName($Paths.Settings)) $r.StageFileName
        Assert-TypezeroOfflineReplacePlainPath -Path $stage
        if ([IO.File]::Exists($stage) -or [IO.Directory]::Exists($stage)) { throw 'Completed transaction retains unexpected stage evidence.' }
    }
    function Get-States($Paths, [byte[]]$Key) {
        $store = Get-Store $Paths
        if (-not [IO.Directory]::Exists($store)) { return @() }
        foreach ($entry in @(Get-ChildItem -LiteralPath $store -Directory -Force -ErrorAction Stop)) {
            $folder = Join-Path $Paths.BackupRoot $entry.Name
            $state = Read-Journal $Paths $folder $Key
            if (-not $state.Complete) { throw 'REFUSED: Interrupted durable transaction requires fresh independent review; all evidence is preserved.' }
            Assert-Snapshot $Paths $state $Key
            $state
        }
    }
    function Assert-Quiescent($Paths, [byte[]]$Key) {
        $states = @(Get-States $Paths $Key)
        $replay = Get-TypezeroOfflineTerminalV2ReplayContext -TestRoot $Paths.Root -AllowMissing
        if ($replay.Initialized) {
            foreach ($item in @(Get-ChildItem -LiteralPath $replay.Store -Filter '*.reserved' -Force -ErrorAction Stop)) {
                if (@($states | Where-Object { $_.Record.Operation -ceq 'RESTORE' -and ($_.Record.GrantId + '.reserved') -ceq $item.Name }).Count -ne 1) {
                    throw 'REFUSED: An orphan or uncertain grant reservation requires independent review.'
                }
            }
        }
        $stageDirectory = [IO.Path]::GetDirectoryName($Paths.Settings)
        if (@(Get-ChildItem -LiteralPath $stageDirectory -Filter '.typezero-combined-*.tmp' -Force -ErrorAction Stop).Count -gt 0) {
            throw 'REFUSED: Uncertain stage evidence requires independent review.'
        }
        return $states
    }
    function Prepare-Intent($Paths, [string]$Operation, [string]$Before, [string]$After, [string]$Stage, [byte[]]$Receipt,
        [byte[]]$Key, [string]$Parent='', [string]$GrantId='', [string]$GrantHash='', [string]$AuthHash='', [string]$ReservationHash='', [string]$SourceHash='') {
        Assert-Size $Receipt $receiptLimit 'receipt'
        $name = (Get-Date -Format 'yyyyMMdd-HHmmss-fffffff') + '-' + [guid]::NewGuid().ToString('N')
        $folder = Join-Path $Paths.BackupRoot $name
        $journal = Join-Path (Get-Store $Paths) $name
        foreach ($target in @($folder,$journal)) {
            Assert-TypezeroOfflineReplacePlainPath -Path $target
            if ([IO.File]::Exists($target) -or [IO.Directory]::Exists($target)) { throw 'REFUSED: Durable transaction identity collision.' }
        }
        $identity = [ordered]@{ Version=2; Sequence=1; Phase='INTENT'; PreviousSha256=$zero;
            Kind='TypezeroFixtureDurableTransactionV2'; FixtureRoot=$Paths.Root; BackupDirectory=$folder;
            Operation=$Operation; ParentBackupDirectory=$Parent; GrantId=$GrantId; GrantSha256=$GrantHash;
            AuthorizationMacSha256=$AuthHash; ReservationSha256=$ReservationHash; SourceChainSha256=$SourceHash;
            SettingsPath=$Paths.Settings; BeforeSha256=$Before; AfterSha256=$After; StageFileName=$Stage;
            BackupFileName='settings-pre-replace.json'; ReceiptSha256=(Hash-Bytes $Receipt); HmacSha256='' }
        $prepared = [Collections.Generic.List[object]]::new()
        $previous = $zero
        for ($i=0; $i -lt 4; $i++) {
            $r = [ordered]@{}
            foreach ($field in $recordNames) { $r[$field] = $identity[$field] }
            $r.Sequence=$i+1; $r.Phase=$phases[$i]; $r.PreviousSha256=$previous
            $r.HmacSha256=[Convert]::ToHexString((Get-Mac $r $Key))
            $bytes=Encode-Bounded ($r | ConvertTo-Json -Compress) $recordLimit 'phase record'
            $previous=Hash-Bytes $bytes
            $prepared.Add([pscustomobject]@{Record=$r;Bytes=$bytes;Digest=$previous})
        }
        # All four actual chained records exist in memory before any durable write.
        [pscustomobject]@{Record=$prepared[0].Record;Digest=$prepared[0].Digest;
            Journal=$journal;Folder=$folder;Prepared=$prepared.ToArray();Written=0}
    }
    function New-Intent($Paths, $State) {
        if ($State.Written -ne 0) { throw 'Invalid private intent transition.' }
        $null=Get-Store $Paths -Create
        Assert-TypezeroOfflineReplacePlainPath -Path $State.Journal
        if ([IO.File]::Exists($State.Journal) -or [IO.Directory]::Exists($State.Journal) -or
            [IO.File]::Exists($State.Folder) -or [IO.Directory]::Exists($State.Folder)) { throw 'REFUSED: Durable transaction identity collision.' }
        [IO.Directory]::CreateDirectory($State.Journal) | Out-Null
        Write-TypezeroOfflineTerminalV2NewFile -Path (Join-Path $State.Journal $fileNames[0]) -Bytes $State.Prepared[0].Bytes
        $State.Written=1
        $State
    }
    function Advance($State, [int]$Sequence, [byte[]]$Key) {
        # Private transitions persist only their preflighted exact canonical bytes.
        if ($Sequence -ne ($State.Written + 1) -or $Sequence -lt 2 -or $Sequence -gt 4) { throw 'Invalid private phase transition.' }
        $next=$State.Prepared[$Sequence-1]
        if ($next.Record.PreviousSha256 -cne $State.Digest -or
            -not [Security.Cryptography.CryptographicOperations]::FixedTimeEquals(
                [Convert]::FromHexString($next.Record.HmacSha256),(Get-Mac $next.Record $Key))) { throw 'Prepared phase authentication failed.' }
        Write-TypezeroOfflineTerminalV2NewFile -Path (Join-Path $State.Journal $fileNames[$Sequence-1]) -Bytes $next.Bytes
        $State.Record=$next.Record; $State.Digest=$next.Digest; $State.Written=$Sequence
    }
    # v1.1 private deadline-aware copy; the pinned legacy primitive is unchanged.
    function Invoke-DeadlineReplace {
        [CmdletBinding(
            SupportsShouldProcess = $true,
            ConfirmImpact = 'High'
        )]
        param(
            [Parameter(Mandatory)]
            [string]$TestRoot,

            [Parameter(Mandatory)]
            [string]$StagePath,

            [Parameter(Mandatory)]
            [string]$BackupPath,

            [Parameter(Mandatory)]
            [ValidatePattern('\A[a-fA-F0-9]{64}\z')]
            [string]$ExpectedBeforeSha256,

            [Parameter(Mandatory)]
            [ValidatePattern('\A[a-fA-F0-9]{64}\z')]
            [string]$ExpectedStageSha256,

            [Parameter(Mandatory)][datetime]$ExpiresUtc,

            [switch]$Execute
        )

        if ($ExpiresUtc.Kind -ne [DateTimeKind]::Utc) { throw 'REFUSED: A UTC grant deadline is required.' }

        # Offline-only: require a specially named direct child of TEMP.
        $root = [IO.Path]::GetFullPath($TestRoot).TrimEnd('\', '/')
        $temp = [IO.Path]::GetFullPath(
            [IO.Path]::GetTempPath()
        ).TrimEnd('\', '/')

        if (-not [string]::Equals(
            [IO.Path]::GetDirectoryName($root),
            $temp,
            [StringComparison]::OrdinalIgnoreCase
        ) -or
            [IO.Path]::GetFileName($root) -cnotmatch
            '\Atypezero-terminal-txn-[a-f0-9]{32}\z') {
            throw 'Replacement requires a direct disposable TEMP fixture.'
        }

        $settings = [IO.Path]::GetFullPath(
            (Join-Path $root (
                'Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe' +
                '\LocalState\settings.json'
            ))
        )

        $settingsDir = [IO.Path]::GetDirectoryName($settings)
        $stage = [IO.Path]::GetFullPath($StagePath)
        $backup = [IO.Path]::GetFullPath($BackupPath)

        # Stage must be an owned candidate in the settings directory.
        if (-not [string]::Equals(
            [IO.Path]::GetDirectoryName($stage),
            $settingsDir,
            [StringComparison]::OrdinalIgnoreCase
        ) -or
            [IO.Path]::GetFileName($stage) -cnotmatch
            '\A\.typezero-combined-(?:restore-)?[a-f0-9]{32}\.tmp\z') {
            throw 'Unexpected replacement staging path.'
        }

        # Backup must be in one exact transaction backup folder.
        $backupBase = [IO.Path]::GetFullPath(
            (Join-Path $root (
                'Typezero\ThemeEngine\backups\terminal-combined'
            ))
        )

        $backupDir = [IO.Path]::GetDirectoryName($backup)

        if ([IO.Path]::GetFileName($backup) -cne
            'settings-pre-replace.json' -or
            -not [string]::Equals(
                [IO.Path]::GetDirectoryName($backupDir),
                $backupBase,
                [StringComparison]::OrdinalIgnoreCase
            ) -or
            [IO.Path]::GetFileName($backupDir) -cnotmatch
            '\A[0-9]{8}-[0-9]{6}-[0-9]{7}-[a-f0-9]{32}\z') {
            throw 'Unexpected replacement backup path.'
        }

        foreach ($path in @(
            $root, $settings, $stage, $backupDir, $backup
        )) {
            Assert-TypezeroOfflineReplacePlainPath -Path $path
        }

        if (-not [IO.Directory]::Exists($backupDir)) {
            throw 'Transaction backup directory must already exist.'
        }

        if (-not [IO.File]::Exists($settings) -or
            -not [IO.File]::Exists($stage)) {
            throw 'Settings or stage file is missing.'
        }

        if ([IO.File]::Exists($backup) -or
            [IO.Directory]::Exists($backup)) {
            throw 'Replacement backup collision. Refusing overwrite.'
        }

        Assert-TypezeroOfflineReplaceSingleLink -Path $settings
        Assert-TypezeroOfflineReplaceSingleLink -Path $stage

        $beforeHash = (
            Get-FileHash -LiteralPath $settings -Algorithm SHA256
        ).Hash

        $stageHash = (
            Get-FileHash -LiteralPath $stage -Algorithm SHA256
        ).Hash

        if ($beforeHash -ine $ExpectedBeforeSha256) {
            throw 'Settings checksum differs from expected original.'
        }

        if ($stageHash -ine $ExpectedStageSha256) {
            throw 'Staging checksum differs from expected candidate.'
        }

        if (-not $Execute) {
            return [pscustomobject]@{
                Status             = 'PREVIEW'
                WouldReplace       = $true
                SettingsPath       = $settings
                StagePath          = $stage
                BackupPath         = $backup
                BeforeSha256       = $beforeHash
                CandidateSha256    = $stageHash
                ReadOnly           = $true
            }
        }

        if (-not $PSCmdlet.ShouldProcess(
            $settings,
            'Replace disposable Terminal settings with preserved backup'
        )) {
            return
        }

        # Repeat checks immediately before replacement.
        # These reduce exposure but are not an atomic compare-and-swap.
        foreach ($path in @($settings, $stage, $backup)) {
            Assert-TypezeroOfflineReplacePlainPath -Path $path
        }

        if ([IO.File]::Exists($backup) -or
            [IO.Directory]::Exists($backup)) {
            throw 'Backup collision immediately before replacement.'
        }

        Assert-TypezeroOfflineReplaceSingleLink -Path $settings
        Assert-TypezeroOfflineReplaceSingleLink -Path $stage

        if ((Get-FileHash -LiteralPath $settings -Algorithm SHA256).Hash -ine
            $ExpectedBeforeSha256) {
            throw 'Settings changed immediately before replacement.'
        }

        if ((Get-FileHash -LiteralPath $stage -Algorithm SHA256).Hash -ine
            $ExpectedStageSha256) {
            throw 'Stage changed immediately before replacement.'
        }

        # No automatic rollback or deletion on failure.
        # Preserve evidence for inspection.
        # DURABLE-CHECKPOINT: RESTORE_BEFORE_NATIVE_CALL
        if ([datetime]::UtcNow -ge $ExpiresUtc) { throw 'REFUSED: Grant expired at native replacement boundary; preserve all evidence.' }
        [IO.File]::Replace(
            $stage,
            $settings,
            $backup,
            $false
        )

        # DURABLE-CHECKPOINT: RESTORE_AFTER_NATIVE_UNVERIFIED
        $actualSettings = (
            Get-FileHash -LiteralPath $settings -Algorithm SHA256
        ).Hash

        $actualBackup = (
            Get-FileHash -LiteralPath $backup -Algorithm SHA256
        ).Hash

        if ($actualSettings -ine $ExpectedStageSha256 -or
            $actualBackup -ine $ExpectedBeforeSha256) {
            throw (
                'Replacement verification failed. Preserve files for ' +
                "manual inspection. Backup: $backup"
            )
        }

        [pscustomobject]@{
            Status          = 'VERIFIED'
            SettingsPath    = $settings
            BackupPath      = $backup
            BeforeSha256    = $actualBackup
            AfterSha256     = $actualSettings
            BackupVerified  = $true
            TestRoot        = $root
        }
    }
    function Prepare-Candidate($Paths, $Theme, [string]$Face, [double]$Size, [string]$Weight) {
        $beforeBytes = Read-Bytes $Paths.Settings
        if ($beforeBytes.Length -ge 3 -and $beforeBytes[0] -eq 239 -and $beforeBytes[1] -eq 187 -and $beforeBytes[2] -eq 191) { throw 'UTF-8 BOM requires separate handling.' }
        $original=$utf8.GetString($beforeBytes)
        $candidate=New-TypezeroTerminalCombinedJsonCandidate -JsonText $original -Theme $Theme -FontFace $Face -FontSize $Size -FontWeight $Weight
        $afterBytes=Encode-Bounded $candidate $settingsLimit 'candidate settings'
        $before=Hash-Bytes $beforeBytes; $after=Hash-Bytes $afterBytes
        if ((Get-TypezeroOfflineTerminalV2Sha256 -Path $Paths.Settings) -cne $before) { throw 'Fixture changed during candidate preparation.' }
        [pscustomobject]@{ Before=$before; After=$after; Bytes=$afterBytes; Changed=($before -cne $after) }
    }
    function Prepare-Apply($Paths, $Theme, [string]$Face, [double]$Size, [string]$Weight, [byte[]]$Key) {
        $candidate=Prepare-Candidate $Paths $Theme $Face $Size $Weight
        if (-not $candidate.Changed) { return [pscustomobject]@{Candidate=$candidate;State=$null;Receipt=$null} }
        $stageName='.typezero-combined-' + [guid]::NewGuid().ToString('N') + '.tmp'
        $receipt=[ordered]@{Version=2;Kind='TypezeroOfflineCombinedV2';Operation='APPLY';SettingsPath=$Paths.Settings;
            BeforeSha256=$candidate.Before;AfterSha256=$candidate.After;StageFileName=$stageName;BackupFileName='settings-pre-replace.json';
            Font=$Face;Size=$Size;Weight=$Weight}
        $receiptBytes=Encode-Bounded ($receipt | ConvertTo-Json -Depth 8) $receiptLimit 'receipt'
        $state=Prepare-Intent $Paths 'APPLY' $candidate.Before $candidate.After $stageName $receiptBytes $Key
        [pscustomobject]@{Candidate=$candidate;State=$state;Receipt=$receiptBytes}
    }
    function Prepare-Restore($Paths, [string]$Folder, $Source, $Review, [string]$GrantJson, [byte[]]$AuthorizationMac, [byte[]]$Key) {
        $grantBytes=Encode-Bounded $GrantJson $grantLimit 'grant'
        if ($null -eq $AuthorizationMac -or $AuthorizationMac.Length -ne 32) { throw 'REFUSED: A 32-byte authorization MAC is required.' }
        $null=Read-Bytes $Paths.Settings $settingsLimit
        $sourceBytes=Read-Bytes (Join-Path $Folder 'settings-pre-replace.json') $settingsLimit
        if ((Hash-Bytes $sourceBytes) -cne $Source.Record.BeforeSha256) { throw 'REFUSED: Restore source bytes changed during preflight.' }
        $reservation=[ordered]@{Version=2;Kind='TypezeroFixtureRecoveryReservationV2';GrantId=$Review.GrantId;
            TestRoot=$Paths.Root;BackupDirectory=$Folder;GrantSha256=(Hash-Bytes $grantBytes)}
        $reservationBytes=Encode-Bounded ($reservation | ConvertTo-Json -Compress) $reservationLimit 'reservation'
        $stageName='.typezero-combined-restore-' + [guid]::NewGuid().ToString('N') + '.tmp'
        $receipt=[ordered]@{Version=2;Kind='TypezeroOfflineCombinedV2';Operation='RESTORE';SettingsPath=$Paths.Settings;
            BeforeSha256=$Source.Record.AfterSha256;AfterSha256=$Source.Record.BeforeSha256;StageFileName=$stageName;
            BackupFileName='settings-pre-replace.json';ParentTransactionFolderName=[IO.Path]::GetFileName($Folder)}
        $receiptBytes=Encode-Bounded ($receipt | ConvertTo-Json -Depth 8) $receiptLimit 'receipt'
        $state=Prepare-Intent $Paths 'RESTORE' $Source.Record.AfterSha256 $Source.Record.BeforeSha256 $stageName $receiptBytes $Key $Folder $Review.GrantId (Hash-Bytes $grantBytes) (Hash-Bytes $AuthorizationMac) (Hash-Bytes $reservationBytes) $Source.Digest
        $grantDoc=[Text.Json.JsonDocument]::Parse($GrantJson)
        try { $expires=[datetime]::ParseExact($grantDoc.RootElement.GetProperty('ExpiresUtc').GetString(),"yyyy-MM-ddTHH:mm:ss.fffffff'Z'",[Globalization.CultureInfo]::InvariantCulture,([Globalization.DateTimeStyles]::AssumeUniversal -bor [Globalization.DateTimeStyles]::AdjustToUniversal)) }
        finally { $grantDoc.Dispose() }
        [pscustomobject]@{State=$state;Receipt=$receiptBytes;Grant=$grantBytes;Reservation=$reservationBytes;SourceBytes=$sourceBytes;ExpiresUtc=$expires}
    }
    function Get-TypezeroOfflineTerminalV2DurableAssessment {
        [CmdletBinding()]
        param([Parameter(Mandatory)][string]$TestRoot, [Parameter(Mandatory)][string]$BackupDirectory, [byte[]]$IndependentKey)
        $paths=Get-TypezeroOfflineTerminalV2Paths -TestRoot $TestRoot
        $folder=Assert-TypezeroOfflineTerminalV2Folder -Paths $paths -BackupDirectory $BackupDirectory
        $decision='INVALID_EVIDENCE'; $phase='UNKNOWN'; $authenticated=$false; $complete=$false; $settings='UNKNOWN'; $reason='Durable evidence cannot be established.'; $operation=$null; $digest=$null
        try {
            Assert-Key $IndependentKey
            $state=Read-Journal $paths $folder $IndependentKey
            $authenticated=$true; $phase=$state.Last.Phase; $operation=$state.Record.Operation; $digest=$state.Digest
            if (-not $state.Complete) { $decision='REVIEW_REQUIRED'; $reason='Interrupted durable transaction; never automatically replay or repair evidence.' }
            else {
                Assert-Snapshot $paths $state $IndependentKey
                $complete=$true
                if (-not [IO.File]::Exists($paths.Settings)) { $settings='MISSING' }
                else {
                    $current=Hash-Bytes (Read-Bytes $paths.Settings)
                    if ($current -ceq $state.Record.AfterSha256) { $settings='AFTER' }
                    elseif ($current -ceq $state.Record.BeforeSha256) { $settings='BEFORE' }
                    else { $settings='OTHER' }
                }
                $decision=if ($settings -ceq 'AFTER') { 'COMPLETE' } else { 'COMPLETE_HISTORICAL' }
                $reason='Complete chain and immutable evidence revalidated; current settings separately observed. No recovery is authorized.'
            }
        }
        catch { $reason=$_.Exception.Message }
        [pscustomobject]@{ Version=2; Decision=$decision; Reason=$reason; OperationPhase=$phase; Operation=$operation;
            ChainAuthenticated=$authenticated; EvidenceComplete=$complete; ChainSha256=$digest; SettingsState=$settings;
            ReadOnly=$true; FixtureOnly=$true; RecoveryAllowed=$false; RecoveryAuthorized=$false; LiveActivationAuthorized=$false;
            TrustedDurableProductionLedger=$false; TestRoot=$paths.Root; BackupDirectory=$folder }
    }
    function Invoke-TypezeroOfflineTerminalV2Durable {
        [CmdletBinding(SupportsShouldProcess=$true,ConfirmImpact='High')]
        param([Parameter(Mandatory)][string]$TestRoot, [Parameter(Mandatory)][System.Collections.IDictionary]$Theme,
            [Parameter(Mandatory)][string]$FontFace, [Parameter(Mandatory)][ValidateRange(6,36)][double]$FontSize,
            [Parameter(Mandatory)][ValidateSet('normal','semi-bold')][string]$FontWeight,
            [Parameter(Mandatory)][byte[]]$IndependentKey, [switch]$Execute)
        Assert-Key $IndependentKey
        $paths=Get-TypezeroOfflineTerminalV2Paths -TestRoot $TestRoot
        $null=Assert-Quiescent $paths $IndependentKey
        $plan=Prepare-Apply $paths $Theme $FontFace $FontSize $FontWeight $IndependentKey
        $candidate=$plan.Candidate
        if (-not $Execute) { return [pscustomobject]@{Status='PREVIEW';ReadOnly=$true;FixtureOnly=$true;WouldChange=$candidate.Changed;RecoveryAuthorized=$false;LiveActivationAuthorized=$false} }
        if (-not $candidate.Changed) { return [pscustomobject]@{Status='NO_CHANGE';ReadOnly=$true;FixtureOnly=$true} }
        if (-not $PSCmdlet.ShouldProcess($paths.Settings,'Apply authenticated durable transaction to disposable fixture')) { return }
        $lock=Open-TypezeroOfflineTerminalV2ReplayLock -TestRoot $paths.Root
        try {
            $paths=Get-TypezeroOfflineTerminalV2Paths -TestRoot $paths.Root
            $null=Assert-Quiescent $paths $IndependentKey
            $plan=Prepare-Apply $paths $Theme $FontFace $FontSize $FontWeight $IndependentKey
            $candidate=$plan.Candidate
            if (-not $candidate.Changed) { return [pscustomobject]@{Status='NO_CHANGE';ReadOnly=$true;FixtureOnly=$true} }
            $stageName=$plan.State.Record.StageFileName; $receiptBytes=$plan.Receipt
            # DURABLE-CHECKPOINT: APPLY_BEFORE_INTENT
            $state=New-Intent $paths $plan.State
            # DURABLE-CHECKPOINT: APPLY_AFTER_INTENT
            [IO.Directory]::CreateDirectory($state.Folder) | Out-Null
            $stage=Join-Path ([IO.Path]::GetDirectoryName($paths.Settings)) $stageName
            Write-TypezeroOfflineTerminalV2NewFile -Path $stage -Bytes $candidate.Bytes
            # DURABLE-CHECKPOINT: APPLY_AFTER_STAGE
            Write-TypezeroOfflineTerminalV2NewFile -Path (Join-Path $state.Folder 'receipt.json') -Bytes $receiptBytes
            Advance $state 2 $IndependentKey
            # DURABLE-CHECKPOINT: APPLY_AFTER_PREPARED
            $replace=Invoke-TypezeroOfflineTerminalVerifiedReplace -TestRoot $paths.Root -StagePath $stage -BackupPath (Join-Path $state.Folder 'settings-pre-replace.json') -ExpectedBeforeSha256 $candidate.Before -ExpectedStageSha256 $candidate.After -Execute -Confirm:$false
            # DURABLE-CHECKPOINT: APPLY_AFTER_REPLACE_VERIFICATION
            if ($replace.Status -cne 'VERIFIED' -or -not $replace.BackupVerified) { throw 'Durable fixture replacement could not be verified; preserve all evidence.' }
            Advance $state 3 $IndependentKey
            # DURABLE-CHECKPOINT: APPLY_AFTER_REPLACED
            $backupBytes=Read-Bytes (Join-Path $state.Folder 'settings-pre-replace.json')
            Write-TypezeroOfflineTerminalV2NewFile -Path (Join-Path $state.Folder 'evidence.seal') -Bytes ([TypezeroEvidenceSealCryptoV2]::Compute($IndependentKey,$receiptBytes,$backupBytes))
            # DURABLE-CHECKPOINT: APPLY_AFTER_SEAL
            $proof=Read-Journal $paths $state.Folder $IndependentKey
            Assert-Snapshot $paths $proof $IndependentKey
            if ((Get-TypezeroOfflineTerminalV2Sha256 -Path $paths.Settings) -cne $candidate.After) { throw 'Fixture changed before durable completion.' }
            Advance $state 4 $IndependentKey
            # DURABLE-CHECKPOINT: APPLY_AFTER_COMPLETE
            $assessment=Get-TypezeroOfflineTerminalV2DurableAssessment -TestRoot $paths.Root -BackupDirectory $state.Folder -IndependentKey $IndependentKey
            if ($assessment.Decision -cne 'COMPLETE') { throw 'Durable completion revalidation failed.' }
            [pscustomobject]@{Status='VERIFIED';Version=2;FixtureOnly=$true;BackupDirectory=$state.Folder;JournalDirectory=$state.Journal;
                BeforeSha256=$candidate.Before;AfterSha256=$candidate.After;OperationPhase='COMPLETE';ChainSha256=$state.Digest;RecoveryAuthorized=$false;LiveActivationAuthorized=$false}
        }
        finally { $lock.Dispose() }
    }
    function Restore-TypezeroOfflineTerminalV2Durable {
        [CmdletBinding(SupportsShouldProcess=$true,ConfirmImpact='High')]
        param([Parameter(Mandatory)][string]$TestRoot,[Parameter(Mandatory)][string]$BackupDirectory,
            [Parameter(Mandatory)][string]$GrantJson,[byte[]]$AuthorizationMac,[byte[]]$ApprovalKey,[byte[]]$EvidenceKey,[switch]$Execute)
        Assert-Key $EvidenceKey
        $null=Encode-Bounded $GrantJson $grantLimit 'grant'
        $paths=Get-TypezeroOfflineTerminalV2Paths -TestRoot $TestRoot
        $folder=Assert-TypezeroOfflineTerminalV2Folder -Paths $paths -BackupDirectory $BackupDirectory
        $states=@(Assert-Quiescent $paths $EvidenceKey)
        if (@($states | Where-Object {$_.Record.Operation -ceq 'RESTORE' -and $_.Record.ParentBackupDirectory -ceq $folder}).Count -gt 0) { throw 'REFUSED: This source already has a permanent durable restore claim.' }
        $source=Read-Journal $paths $folder $EvidenceKey
        if (-not $source.Complete -or $source.Record.Operation -cne 'APPLY') { throw 'REFUSED: Completed authenticated durable APPLY is required.' }
        $null=Read-Bytes $paths.Settings $settingsLimit
        $reviewArgs=@{TestRoot=$paths.Root;BackupDirectory=$folder;GrantJson=$GrantJson;AuthorizationMac=$AuthorizationMac;ApprovalKey=$ApprovalKey;EvidenceKey=$EvidenceKey}
        $review=Get-TypezeroOfflineTerminalV2GrantReview @reviewArgs
        if (-not $review.ValidForReview) { throw ('REFUSED: ' + $review.Decision + ': ' + $review.Reason) }
        $replay=Get-TypezeroOfflineTerminalV2ReplayContext -TestRoot $paths.Root
        $reservationPath=Join-Path $replay.Store ($review.GrantId + '.reserved')
        if ([IO.File]::Exists($reservationPath) -or [IO.Directory]::Exists($reservationPath)) { throw 'REFUSED: Recovery grant ID is already occupied.' }
        $plan=Prepare-Restore $paths $folder $source $review $GrantJson $AuthorizationMac $EvidenceKey
        if (-not $Execute) { return [pscustomobject]@{Status='PREVIEW';ReadOnly=$true;FixtureOnly=$true;GrantConsumed=$false;RecoveryAuthorized=$false;LiveActivationAuthorized=$false} }
        if (-not $PSCmdlet.ShouldProcess($paths.Settings,'Reserve grant and restore authenticated durable disposable fixture')) { return }
        $lock=Open-TypezeroOfflineTerminalV2ReplayLock -TestRoot $paths.Root
        try {
            $paths=Get-TypezeroOfflineTerminalV2Paths -TestRoot $paths.Root
            $states=@(Assert-Quiescent $paths $EvidenceKey)
            if (@($states | Where-Object {$_.Record.Operation -ceq 'RESTORE' -and $_.Record.ParentBackupDirectory -ceq $folder}).Count -gt 0) { throw 'REFUSED: Source already claimed for restore.' }
            $source=Read-Journal $paths $folder $EvidenceKey
            Assert-Snapshot $paths $source $EvidenceKey
            $review=Get-TypezeroOfflineTerminalV2GrantReview @reviewArgs
            if (-not $review.ValidForReview) { throw ('REFUSED: Locked grant review: ' + $review.Decision) }
            $replay=Get-TypezeroOfflineTerminalV2ReplayContext -TestRoot $paths.Root
            $reservationPath=Join-Path $replay.Store ($review.GrantId + '.reserved')
            Assert-TypezeroOfflineReplacePlainPath -Path $reservationPath
            if ([IO.File]::Exists($reservationPath) -or [IO.Directory]::Exists($reservationPath)) { throw 'REFUSED: Grant replay.' }
            $plan=Prepare-Restore $paths $folder $source $review $GrantJson $AuthorizationMac $EvidenceKey
            $grantBytes=$plan.Grant; $reservationBytes=$plan.Reservation; $receiptBytes=$plan.Receipt
            $stageName=$plan.State.Record.StageFileName; $expires=$plan.ExpiresUtc
            # DURABLE-CHECKPOINT: RESTORE_BEFORE_INTENT
            $state=New-Intent $paths $plan.State
            # DURABLE-CHECKPOINT: RESTORE_AFTER_SOURCE_CLAIM
            # Finish all serialization before the final reservation expiry check.
            # DURABLE-CHECKPOINT: RESTORE_BEFORE_RESERVATION
            if ([datetime]::UtcNow -ge $expires) { throw 'REFUSED: Grant expired before durable reservation; intent remains uncertain.' }
            $reservationStream=[IO.FileStream]::new($reservationPath,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
            try {
                # DURABLE-CHECKPOINT: RESTORE_RESERVATION_CREATED
                $reservationStream.Write($reservationBytes,0,$reservationBytes.Length)
                $reservationStream.Flush($true)
            }
            finally { $reservationStream.Dispose() }
            # DURABLE-CHECKPOINT: RESTORE_AFTER_RESERVATION
            [IO.Directory]::CreateDirectory($state.Folder) | Out-Null
            $stage=Join-Path ([IO.Path]::GetDirectoryName($paths.Settings)) $stageName
            Write-TypezeroOfflineTerminalV2NewFile -Path $stage -Bytes $plan.SourceBytes
            # DURABLE-CHECKPOINT: RESTORE_AFTER_STAGE
            Write-TypezeroOfflineTerminalV2NewFile -Path (Join-Path $state.Folder 'receipt.json') -Bytes $receiptBytes
            Write-TypezeroOfflineTerminalV2NewFile -Path (Join-Path $state.Folder 'grant.json') -Bytes $grantBytes
            Write-TypezeroOfflineTerminalV2NewFile -Path (Join-Path $state.Folder 'authorization.mac') -Bytes $AuthorizationMac
            Advance $state 2 $EvidenceKey
            # DURABLE-CHECKPOINT: RESTORE_AFTER_PREPARED
            Assert-Snapshot $paths $source $EvidenceKey
            if ([datetime]::UtcNow -ge $expires) { throw 'REFUSED: Grant expired before replacement; preserve reserved intent and evidence.' }
            $replace=Invoke-DeadlineReplace -TestRoot $paths.Root -StagePath $stage -BackupPath (Join-Path $state.Folder 'settings-pre-replace.json') -ExpectedBeforeSha256 $source.Record.AfterSha256 -ExpectedStageSha256 $source.Record.BeforeSha256 -ExpiresUtc $expires -Execute -Confirm:$false
            # DURABLE-CHECKPOINT: RESTORE_AFTER_REPLACE_VERIFICATION
            if ($replace.Status -cne 'VERIFIED' -or -not $replace.BackupVerified) { throw 'Restore replacement could not be verified; all evidence preserved.' }
            Advance $state 3 $EvidenceKey
            # DURABLE-CHECKPOINT: RESTORE_AFTER_REPLACED
            $backupBytes=Read-Bytes (Join-Path $state.Folder 'settings-pre-replace.json')
            Write-TypezeroOfflineTerminalV2NewFile -Path (Join-Path $state.Folder 'evidence.seal') -Bytes ([TypezeroEvidenceSealCryptoV2]::Compute($EvidenceKey,$receiptBytes,$backupBytes))
            # DURABLE-CHECKPOINT: RESTORE_AFTER_SEAL
            $proof=Read-Journal $paths $state.Folder $EvidenceKey
            Assert-Snapshot $paths $proof $EvidenceKey
            if ((Get-TypezeroOfflineTerminalV2Sha256 -Path $paths.Settings) -cne $source.Record.BeforeSha256) { throw 'Restore result changed before durable completion.' }
            Advance $state 4 $EvidenceKey
            # DURABLE-CHECKPOINT: RESTORE_AFTER_COMPLETE
            $assessment=Get-TypezeroOfflineTerminalV2DurableAssessment -TestRoot $paths.Root -BackupDirectory $state.Folder -IndependentKey $EvidenceKey
            if ($assessment.Decision -cne 'COMPLETE') { throw 'Restore completion revalidation failed.' }
            [pscustomobject]@{Status='RESTORED';Version=2;FixtureOnly=$true;BackupDirectory=$folder;RestoreBackupDirectory=$state.Folder;
                JournalDirectory=$state.Journal;GrantConsumed=$true;GrantId=$review.GrantId;OperationPhase='COMPLETE';ChainSha256=$state.Digest;
                OriginalHashMatch=$true;RecoveryAuthorized=$false;LiveActivationAuthorized=$false;TrustedDurableProductionLedger=$false}
        }
        finally { $lock.Dispose() }
    }
    Export-ModuleMember -Function Invoke-TypezeroOfflineTerminalV2Durable,Restore-TypezeroOfflineTerminalV2Durable,Get-TypezeroOfflineTerminalV2DurableAssessment
} | Import-Module -Global -Force
