# Typezero ThemeEngine - fixture-only V2 recovery grant reservation.
# This is cooperating-process replay protection, NOT recovery authorization.
# A deleted/rolled-back fixture ledger cannot be trusted as a production ledger.
# No recovery operation, caller callback, live path or key persistence is supported.

function Get-TypezeroOfflineTerminalV2ReplayContext {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$TestRoot,
        [switch]$AllowMissing
    )

    $paths = Get-TypezeroOfflineTerminalV2Paths -TestRoot $TestRoot
    $store = Join-Path $paths.Root '.typezero-terminal-v2-recovery-replay'
    $marker = Join-Path $store '.fixture'
    $expectedMarker = 'TYPEZERO-V2-RECOVERY-REPLAY-FIXTURE-1'
    Assert-TypezeroOfflineReplacePlainPath -Path $store

    if ([IO.File]::Exists($store)) {
        throw 'REFUSED: Replay store must be an ordinary directory.'
    }
    if (-not [IO.Directory]::Exists($store)) {
        if (-not $AllowMissing) {
            throw 'REFUSED: Explicitly initialize the fixture replay store first.'
        }
        return [pscustomobject]@{
            Paths = $paths; Store = $store; Marker = $marker
            MarkerText = $expectedMarker; Initialized = $false
        }
    }

    Assert-TypezeroOfflineReplacePlainPath -Path $marker
    if (-not [IO.File]::Exists($marker)) {
        throw 'REFUSED: Replay store is partial or its fixture marker is missing.'
    }
    Assert-TypezeroOfflineReplaceSingleLink -Path $marker
    if ([IO.FileInfo]::new($marker).Length -ne $expectedMarker.Length -or
        [IO.File]::ReadAllText($marker) -cne $expectedMarker) {
        throw 'REFUSED: Replay store fixture marker is invalid.'
    }

    foreach ($item in @(Get-ChildItem -LiteralPath $store -Force -ErrorAction Stop)) {
        Assert-TypezeroOfflineReplacePlainPath -Path $item.FullName
        if ($item.PSIsContainer -or
            ($item.Name -cne '.fixture' -and
             $item.Name -cnotmatch '\A[a-f0-9]{32}\.reserved\z')) {
            throw 'REFUSED: Unexpected replay-store entry.'
        }
        Assert-TypezeroOfflineReplaceSingleLink -Path $item.FullName
        # Existing reservation contents NEVER authorize re-use. Empty, partial,
        # or corrupt entries remain spent, and are deliberately not repaired.
    }

    [pscustomobject]@{
        Paths = $paths; Store = $store; Marker = $marker
        MarkerText = $expectedMarker; Initialized = $true
    }
}

function Open-TypezeroOfflineTerminalV2ReplayLock {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$TestRoot)

    $paths = Get-TypezeroOfflineTerminalV2Paths -TestRoot $TestRoot
    $lockPath = Join-Path $paths.Root '.typezero-terminal-v2.lock'
    Assert-TypezeroOfflineReplacePlainPath -Path $lockPath
    if ([IO.File]::Exists($lockPath)) {
        Assert-TypezeroOfflineReplaceSingleLink -Path $lockPath
    }
    try {
        # Same fixed lock as V2 transactions; never a caller-selected lock.
        return [IO.FileStream]::new(
            $lockPath, [IO.FileMode]::OpenOrCreate,
            [IO.FileAccess]::ReadWrite, [IO.FileShare]::None
        )
    }
    catch [IO.IOException] {
        throw 'REFUSED: Fixture V2 transaction lock is occupied or unsafe.'
    }
}

function Initialize-TypezeroOfflineTerminalV2ReplayStore {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory)][string]$TestRoot,
        [switch]$Execute
    )

    $context = Get-TypezeroOfflineTerminalV2ReplayContext `
        -TestRoot $TestRoot -AllowMissing
    if ($context.Initialized) {
        throw 'REFUSED: Replay store already exists; never reset or recycle it.'
    }
    if (-not $Execute) {
        return [pscustomobject]@{
            Status = 'PREVIEW'; WouldInitialize = $true; ReadOnly = $true
            FixtureOnly = $true; ReplayStore = $context.Store
            RecoveryAuthorized = $false; LiveActivationAuthorized = $false
        }
    }
    if (-not $PSCmdlet.ShouldProcess(
        $context.Store, 'Initialize disposable V2 recovery replay store'
    )) { return }

    $lock = Open-TypezeroOfflineTerminalV2ReplayLock -TestRoot $context.Paths.Root
    try {
        $context = Get-TypezeroOfflineTerminalV2ReplayContext `
            -TestRoot $context.Paths.Root -AllowMissing
        if ($context.Initialized -or [IO.Directory]::Exists($context.Store) -or
            [IO.File]::Exists($context.Store)) {
            throw 'REFUSED: Replay store already exists; initialization refused.'
        }
        New-Item -ItemType Directory -Path $context.Store -ErrorAction Stop |
            Out-Null
        # Preserve partial initialization on failure; never recycle it.
        Write-TypezeroOfflineTerminalV2NewFile -Path $context.Marker `
            -Bytes ([Text.Encoding]::ASCII.GetBytes($context.MarkerText))
        [pscustomobject]@{
            Status = 'INITIALIZED'; ReadOnly = $false; FixtureOnly = $true
            ReplayStore = $context.Store; RecoveryAuthorized = $false
            LiveActivationAuthorized = $false
        }
    }
    finally { $lock.Dispose() }
}

function Reserve-TypezeroOfflineTerminalV2RecoveryGrant {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory)][string]$TestRoot,
        [Parameter(Mandatory)][string]$BackupDirectory,
        [Parameter(Mandatory)][string]$GrantJson,
        [byte[]]$AuthorizationMac,
        [byte[]]$ApprovalKey,
        [byte[]]$EvidenceKey,
        [switch]$Execute
    )

    $context = Get-TypezeroOfflineTerminalV2ReplayContext -TestRoot $TestRoot
    $arguments = @{
        TestRoot = $context.Paths.Root; BackupDirectory = $BackupDirectory
        GrantJson = $GrantJson; AuthorizationMac = $AuthorizationMac
        ApprovalKey = $ApprovalKey; EvidenceKey = $EvidenceKey
    }
    $review = Get-TypezeroOfflineTerminalV2GrantReview @arguments
    $decision = $review.Decision
    $reason = $review.Reason
    $reserved = $false
    $reservationPath = $null
    $lock = $null

    try {
        if ($review.ValidForReview) {
            $reservationPath = Join-Path $context.Store ($review.GrantId + '.reserved')
            if ([IO.File]::Exists($reservationPath) -or
                [IO.Directory]::Exists($reservationPath)) {
                $decision = 'REPLAY_REFUSED'
                $reason = 'Grant ID is already occupied; partial/corrupt entries remain spent.'
            }
            elseif (-not $Execute) {
                $decision = 'PREVIEW'
                $reason = 'Valid fixture grant could be reserved; no replay state changed.'
            }
            elseif ($PSCmdlet.ShouldProcess(
                $reservationPath, 'Permanently reserve disposable V2 recovery grant ID'
            )) {
                $lock = Open-TypezeroOfflineTerminalV2ReplayLock `
                    -TestRoot $context.Paths.Root
                $context = Get-TypezeroOfflineTerminalV2ReplayContext `
                    -TestRoot $context.Paths.Root
                # Fresh grant/evidence/settings/time validation WHILE holding
                # the same lock as cooperating V2 apply/restore writers.
                $review = Get-TypezeroOfflineTerminalV2GrantReview @arguments
                $decision = $review.Decision
                $reason = $review.Reason
                if ($review.ValidForReview) {
                    $reservationPath = Join-Path $context.Store (
                        $review.GrantId + '.reserved'
                    )
                    Assert-TypezeroOfflineReplacePlainPath -Path $reservationPath
                    if ([IO.File]::Exists($reservationPath) -or
                        [IO.Directory]::Exists($reservationPath)) {
                        $decision = 'REPLAY_REFUSED'
                        $reason = 'Grant ID already occupied; reservation refused.'
                    }
                    else {
                        $utf8 = [Text.UTF8Encoding]::new($false, $true)
                        $tombstone = [ordered]@{
                            Version = 2; Kind = 'TypezeroFixtureRecoveryReservationV2'
                            GrantId = $review.GrantId; TestRoot = $context.Paths.Root
                            BackupDirectory = $review.BackupDirectory
                            GrantSha256 = [Convert]::ToHexString(
                                [Security.Cryptography.SHA256]::HashData(
                                    $utf8.GetBytes($GrantJson)
                                )
                            )
                        }
                        # CreateNew + Flush(true); any surviving partial write
                        # blocks this ID forever. No cleanup, retry, or recovery.
                        Write-TypezeroOfflineTerminalV2NewFile `
                            -Path $reservationPath `
                            -Bytes ($utf8.GetBytes(($tombstone | ConvertTo-Json -Compress)))
                        $reserved = $true
                        $decision = 'RESERVED_FIXTURE_ONLY'
                        $reason = 'Grant ID reserved for cooperating fixture processes; no recovery authorized.'
                    }
                }
            }
            else {
                $decision = 'NOT_EXECUTED'
                $reason = 'ShouldProcess did not authorize fixture reservation.'
            }
        }
    }
    finally { if ($null -ne $lock) { $lock.Dispose() } }

    [pscustomobject]@{
        Version = 2; Decision = $decision; Reason = $reason
        GrantId = $review.GrantId; GrantReserved = $reserved
        GrantConsumed = $false; ReservationPath = $reservationPath
        ReadOnly = (-not $reserved); FixtureOnly = $true
        ReplayProtectionEstablished = $reserved
        ReplayProtectionScope = 'CooperatingFixtureProcessesOnly'
        TrustedDurableProductionLedger = $false
        RecoveryAllowed = $false; RecoveryAuthorized = $false
        LiveActivationAuthorized = $false; OperationPhase = 'UNKNOWN'
        TestRoot = $context.Paths.Root; BackupDirectory = $review.BackupDirectory
    }
}
