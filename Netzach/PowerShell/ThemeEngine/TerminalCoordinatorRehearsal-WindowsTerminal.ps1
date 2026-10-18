# Typezero ThemeEngine - 57F.23.10.09.09.03
# Explicit, disposable-fixture rehearsal only. Dot-sourcing defines functions only.
# Requires FontWriter, TerminalCoordinatorRecovery, TerminalCoordinatorReceipt,
# and TerminalCoordinatorLifecycle. The locked preparer creates the input journal.
# Reuses the durable transaction root, lock, byte reader, integrity assertions,
# coordinator classifier, lifecycle assessment, and receipt cipher/verifier.
# TerminalTransactionV2 and TerminalReplace retain their narrower, untouched scope.
# File.Replace is not compare-and-swap or proof against arbitrary same-user code,
# concurrent filesystem changes, process termination, or physical power loss.

function Get-TypezeroCoordinatorRehearsalContext {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$TestRoot,
        [Parameter(Mandatory)][ValidatePattern('\A[a-f0-9]{32}\z')][string]$TransactionId,
        [Parameter(Mandatory)][ValidatePattern('\A[a-fA-F0-9]{64}\z')][string]$ExpectedJournalSha256,
        [ValidatePattern('\A\.typezero-coordinator-stage-[a-f0-9]{32}\.tmp\z')][string]$ActiveStageName
    )

    foreach ($name in @('Assert-TypezeroFontRecoveryRoot','Open-TypezeroFontRecoveryLock',
        'Get-TypezeroFontRecoveryBytes','Get-TypezeroFontRecoveryHash',
        'Assert-TypezeroFontRecoveryContent','Read-TypezeroCoordinatorFixtureJournal',
        'Get-TypezeroCoordinatorFixtureRecoveryState','Get-TypezeroCoordinatorFixtureLifecycleAssessment',
        'New-TypezeroCoordinatorFixtureReceiptCipher','Test-TypezeroCoordinatorFixtureReceiptCipher',
        'Test-TypezeroCoordinatorFixtureReceipt')) {
        if (-not (Get-Command $name -CommandType Function -ErrorAction SilentlyContinue)) {
            throw "REFUSED: Rehearsal dependency not loaded: $name"
        }
    }
    $root = Assert-TypezeroFontRecoveryRoot -TestRoot $TestRoot
    $folder = Join-Path $root ('coordinator-' + $TransactionId)
    $manifestPath = Join-Path $folder 'coordinator.dpapi'
    $cipher = Get-TypezeroFontRecoveryBytes -Path $manifestPath -Maximum 65536
    $manifestHash = Get-TypezeroFontRecoveryHash -Bytes $cipher
    if ($manifestHash -cne $ExpectedJournalSha256.ToUpperInvariant()) {
        throw 'REFUSED: Exact prepared journal ciphertext hash changed.'
    }

    # Only a newly isolated seven-target fixture and its one journal are accepted.
    # A leftover stage is evidence of an unclassified failure; never delete/reuse it.
    $order = @('settings.json','vim-main.vim','vim-lightline.vim','shell-current.ps1',
        'appearance.mock','history-previous.txt','history-current.txt')
    $allowedRoot = $order + @('.transaction.lock', ('coordinator-' + $TransactionId))
    if ($ActiveStageName) { $allowedRoot += $ActiveStageName }
    $entries = @(Get-ChildItem -LiteralPath $root -Force -ErrorAction Stop)
    if ($entries.Count -ne $allowedRoot.Count) {
        throw 'REFUSED: Rehearsal root inventory changed; preserve all evidence.'
    }
    foreach ($entry in $entries) {
        if ($entry.Name -cnotin $allowedRoot -or
            ($entry.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or
            $entry.PSIsContainer -ne ($entry.Name -ceq ('coordinator-' + $TransactionId))) {
            throw 'REFUSED: Unexpected or unsafe rehearsal root entry.'
        }
        Assert-TypezeroFontRecoveryPlainPath -Path $entry.FullName
    }
    $manifest = Read-TypezeroCoordinatorFixtureJournal -TestRoot $root -TransactionId $TransactionId
    $state = Get-TypezeroCoordinatorFixtureRecoveryState -TestRoot $root -TransactionId $TransactionId
    $assessment = Get-TypezeroCoordinatorFixtureLifecycleAssessment -TestRoot $root -TransactionId $TransactionId
    if ($manifest.FixtureOnly -ne $true -or $manifest.FontEnabled -ne $false -or
        $state.RecoveryAuthorized -ne $false -or $state.State -ceq 'Conflicted' -or
        @($state.Issues).Count -ne 0 -or $assessment.JournalStatus -cne 'Valid' -or
        $assessment.JournalInventoryValid -ne $true -or
        $assessment.ArtifactConsistency -cne 'Consistent' -or
        $assessment.RecoveryAuthorized -ne $false -or
        $assessment.LiveActivationAuthorized -ne $false -or
        @($assessment.Issues).Count -ne 0) {
        throw 'REFUSED: Coordinator or lifecycle evidence is invalid or conflicted.'
    }
    if ($assessment.PendingReceiptPresent -eq $true) {
        throw 'REFUSED: Pending receipt evidence requires manual inspection; no promotion or overwrite.'
    }
    if ($assessment.PublishedReceiptPresent -eq $true -and $assessment.ReceiptValid -ne $true) {
        throw 'REFUSED: Published receipt failed independent verification.'
    }

    $byName = @{}; $positions = @{}
    foreach ($entry in $manifest.Artifacts) { $byName[$entry.Target] = $entry }
    foreach ($observation in $state.Artifacts) { $positions[$observation.Target] = $observation.Position }
    $rows = @(); $appliedCount = 0; $restoredCount = 0
    $seenRestored = $false; $seenUntouched = $false
    foreach ($targetName in $order) {
        $entry = $byName[$targetName]
        $safe = $targetName.Replace('.', '_')
        foreach ($kind in @('apply','restore')) {
            $partial = Join-Path $folder ('displaced-' + $kind + '-partial-' + $safe + '.bin')
            if ([IO.File]::Exists($partial) -or [IO.Directory]::Exists($partial)) {
                throw 'REFUSED: Partial-round evidence is outside this fresh rehearsal contract.'
            }
        }
        $applyPath = Join-Path $folder ('displaced-apply-complete-' + $safe + '.bin')
        $restorePath = Join-Path $folder ('displaced-restore-complete-' + $safe + '.bin')
        $applyPresent = [IO.File]::Exists($applyPath)
        $restorePresent = [IO.File]::Exists($restorePath)
        if ($applyPresent) {
            $null = Assert-TypezeroFontRecoveryContent -Path $applyPath -Sha256 $entry.BeforeSha256 -Length $entry.BeforeLength
            $appliedCount++
        }
        if ($restorePresent) {
            $null = Assert-TypezeroFontRecoveryContent -Path $restorePath -Sha256 $entry.AfterSha256 -Length $entry.AfterLength
            $restoredCount++
        }
        $phase = if ($positions[$targetName] -ceq 'After' -and $applyPresent -and -not $restorePresent) {
            'Applied'
        } elseif ($positions[$targetName] -ceq 'Before' -and $applyPresent -and $restorePresent) {
            'Restored'
        } elseif ($positions[$targetName] -ceq 'Before' -and -not $applyPresent -and -not $restorePresent) {
            'Untouched'
        } else {
            throw "REFUSED: Ambiguous target/displacement ownership: $targetName"
        }
        # The only accepted topology is Applied*, Restored*, Untouched*.
        # Reversing the restore order keeps the existing inspector's applied prefix.
        if ($phase -ceq 'Applied' -and ($seenRestored -or $seenUntouched)) {
            throw 'REFUSED: Non-prefix applied evidence.'
        }
        if ($phase -ceq 'Restored') {
            if ($seenUntouched) { throw 'REFUSED: Non-contiguous restored evidence.' }
            $seenRestored = $true
        }
        if ($phase -ceq 'Untouched') { $seenUntouched = $true }
        $rows += [pscustomobject]@{ Entry=$entry; Phase=$phase; ApplyProof=$applyPath; RestoreProof=$restorePath }
    }
    [pscustomobject]@{
        Root=$root; TransactionId=$TransactionId; Folder=$folder; JournalSha256=$manifestHash; JournalLength=$cipher.Length
        Manifest=$manifest; RecoveryState=$state; Lifecycle=$assessment; Rows=$rows
        AppliedArtifactCount=$appliedCount; RestoredArtifactCount=$restoredCount
        CompleteRoundRestored=($appliedCount -eq 7 -and $restoredCount -eq 7)
    }
}

function New-TypezeroCoordinatorRehearsalResult {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Context,
        [Parameter(Mandatory)][string]$Status,
        [Parameter(Mandatory)][ValidateSet('Apply','Restore')][string]$Operation,
        [int]$ReplacementCount = 0, [bool]$ReadOnly = $false)

    $originalsMatch = $true
    foreach ($row in $Context.Rows) {
        $original = Get-TypezeroFontRecoveryBytes -Path (Join-Path $Context.Folder $row.Entry.Backup)
        $actual = Get-TypezeroFontRecoveryBytes -Path (Join-Path $Context.Root $row.Entry.Target)
        if ($actual.Length -ne $original.Length -or
            [Convert]::ToBase64String($actual) -cne [Convert]::ToBase64String($original)) {
            $originalsMatch = $false
        }
    }
    [pscustomobject]@{
        ContractVersion=1; Milestone='57F.23.10.09.09.03'
        Mode='PrivateFixtureApplyRestoreRehearsal'; Operation=$Operation; Status=$Status
        TestRoot=$Context.Root; TransactionId=$Context.TransactionId; JournalDirectory=$Context.Folder
        JournalSHA256=$Context.JournalSha256; ArtifactCount=7; ReplacementCount=$ReplacementCount
        AppliedArtifactCount=$Context.AppliedArtifactCount; RestoredArtifactCount=$Context.RestoredArtifactCount
        CoordinatorState=$Context.RecoveryState.State; ExactOriginalBytesMatch=$originalsMatch
        CompleteRoundRestored=$Context.CompleteRoundRestored
        ReceiptStatus=$Context.Lifecycle.ReceiptStatus; ReceiptValid=$Context.Lifecycle.ReceiptValid
        ReceiptPublished=$Context.Lifecycle.PublishedReceiptPresent
        LifecycleAssessment=$Context.Lifecycle
        FixtureOnly=$true; ReadOnly=$ReadOnly; RecoveryAuthorized=$false; LiveActivationAuthorized=$false
        OriginalInputsAuthenticated=$false; CrossRootEvidenceAuthenticated=$false
        ExternalProviderInvoked=$false; GlobalRestorationCertified=$false
    }
}

function Invoke-TypezeroCoordinatorFixtureRehearsalCore {
    [CmdletBinding(SupportsShouldProcess=$true, ConfirmImpact='High')]
    param(
        [Parameter(Mandatory)][ValidateSet('Apply','Restore')][string]$Operation,
        [Parameter(Mandatory)][string]$TestRoot,
        [Parameter(Mandatory)][ValidatePattern('\A[a-f0-9]{32}\z')][string]$TransactionId,
        [Parameter(Mandatory)][ValidatePattern('\A[a-fA-F0-9]{64}\z')][string]$ExpectedJournalSha256,
        [switch]$Execute,
        [ValidateRange(-1,7)][int]$InterruptAfterReplacement = -1,
        [switch]$InterruptBeforeReceiptPublication
    )

    # ValidateSet accepts case-insensitive input, including direct calls to this
    # core function. Normalize before the ordinal phase/order comparisons below.
    $Operation = if ($Operation -ieq 'Apply') { 'Apply' } else { 'Restore' }
    $contextArgs = @{ TestRoot=$TestRoot; TransactionId=$TransactionId; ExpectedJournalSha256=$ExpectedJournalSha256 }
    $context = Get-TypezeroCoordinatorRehearsalContext @contextArgs
    if ($Operation -ceq 'Apply' -and ($context.RestoredArtifactCount -ne 0 -or
        $context.Lifecycle.PublishedReceiptPresent -eq $true)) {
        throw 'REFUSED: Apply cannot reuse a restoring or completed rehearsal journal.'
    }
    if ($Operation -ceq 'Apply' -and $InterruptBeforeReceiptPublication) {
        throw 'REFUSED: Receipt interruption applies only to fixture restore.'
    }
    if (-not $Execute -or -not $PSCmdlet.ShouldProcess($context.Root,
        "$Operation seven disposable fixture files using the exact prepared journal")) {
        return New-TypezeroCoordinatorRehearsalResult -Context $context -Status PREVIEW -Operation $Operation -ReadOnly $true
    }

    # Input validation above creates nothing. The preparer already created this lock.
    $lock = Open-TypezeroFontRecoveryLock -TestRoot $context.Root
    try {
        $context = Get-TypezeroCoordinatorRehearsalContext @contextArgs
        if ($Operation -ceq 'Apply' -and ($context.RestoredArtifactCount -ne 0 -or
            $context.Lifecycle.PublishedReceiptPresent -eq $true)) {
            throw 'REFUSED: Rehearsal phase changed before lock acquisition.'
        }
        $replacements = 0
        if ($InterruptAfterReplacement -eq 0) {
            throw "INJECTED: $Operation rehearsal after replacement 0; existing evidence retained."
        }
        $names = @($context.Rows.Entry.Target)
        if ($Operation -ceq 'Restore') { [array]::Reverse($names) }
        foreach ($name in $names) {
            $context = Get-TypezeroCoordinatorRehearsalContext @contextArgs
            $row = @($context.Rows | Where-Object { $_.Entry.Target -ceq $name })[0]
            $wantedPhase = if ($Operation -ceq 'Apply') { 'Untouched' } else { 'Applied' }
            if ($row.Phase -cne $wantedPhase) { continue }
            $entry = $row.Entry
            $source = if ($Operation -ceq 'Apply') { $entry.Candidate } else { $entry.Backup }
            $expectedCurrentHash = if ($Operation -ceq 'Apply') { $entry.BeforeSha256 } else { $entry.AfterSha256 }
            $expectedCurrentLength = if ($Operation -ceq 'Apply') { $entry.BeforeLength } else { $entry.AfterLength }
            $expectedNextHash = if ($Operation -ceq 'Apply') { $entry.AfterSha256 } else { $entry.BeforeSha256 }
            $expectedNextLength = if ($Operation -ceq 'Apply') { $entry.AfterLength } else { $entry.BeforeLength }
            $displaced = if ($Operation -ceq 'Apply') { $row.ApplyProof } else { $row.RestoreProof }
            $target = Join-Path $context.Root $entry.Target
            $bytes = Assert-TypezeroFontRecoveryContent -Path (Join-Path $context.Folder $source) `
                -Sha256 $expectedNextHash -Length $expectedNextLength
            Write-Debug "TZ57F2310090903:${Operation}:${name}:BeforeStage"
            # This path is derived here; callers cannot supply a stage/destination.
            $stage = Join-Path $context.Root ('.typezero-coordinator-stage-' + [guid]::NewGuid().ToString('N') + '.tmp')
            Assert-TypezeroFontRecoveryPlainPath -Path $stage
            $stream = [IO.FileStream]::new($stage, [IO.FileMode]::CreateNew,
                [IO.FileAccess]::Write, [IO.FileShare]::None, 4096, [IO.FileOptions]::WriteThrough)
            try { $stream.Write($bytes,0,$bytes.Length); $stream.Flush($true) }
            finally { $stream.Dispose() }
            Write-Debug "TZ57F2310090903:${Operation}:${name}:StageFlushed"

            # A fresh caller refuses an existing stage. Only this invocation can
            # validate the exact stage it just created alongside the full inventory.
            # Revalidate every journal/evidence/target immediately before replacing.
            $context = Get-TypezeroCoordinatorRehearsalContext @contextArgs -ActiveStageName ([IO.Path]::GetFileName($stage))
            $null = Assert-TypezeroFontRecoveryRoot -TestRoot $context.Root
            $null = Assert-TypezeroFontRecoveryContent -Path (Join-Path $context.Folder 'coordinator.dpapi') `
                -Sha256 $context.JournalSha256 -Length $context.JournalLength
            $null = Assert-TypezeroFontRecoveryContent -Path (Join-Path $context.Folder $source) `
                -Sha256 $expectedNextHash -Length $expectedNextLength
            $null = Assert-TypezeroFontRecoveryContent -Path $stage -Sha256 $expectedNextHash -Length $expectedNextLength
            $null = Assert-TypezeroFontRecoveryContent -Path $target -Sha256 $expectedCurrentHash -Length $expectedCurrentLength
            if ($Operation -ceq 'Restore') {
                $null = Assert-TypezeroFontRecoveryContent -Path $row.ApplyProof `
                    -Sha256 $entry.BeforeSha256 -Length $entry.BeforeLength
            }
            Assert-TypezeroFontRecoveryPlainPath -Path $displaced
            if ([IO.File]::Exists($displaced) -or [IO.Directory]::Exists($displaced)) {
                throw 'REFUSED: Displacement evidence collision; preserve all artifacts.'
            }
            # Preserve the ACTUAL displaced file, then verify it and the target.
            # Hash prechecks are not CAS; a failure never triggers automatic rollback.
            [IO.File]::Replace($stage,$target,$displaced,$false)
            Write-Debug "TZ57F2310090903:${Operation}:${name}:Replaced"
            $null = Assert-TypezeroFontRecoveryContent -Path $displaced `
                -Sha256 $expectedCurrentHash -Length $expectedCurrentLength
            $null = Assert-TypezeroFontRecoveryContent -Path $target `
                -Sha256 $expectedNextHash -Length $expectedNextLength
            $context = Get-TypezeroCoordinatorRehearsalContext @contextArgs
            Write-Debug "TZ57F2310090903:${Operation}:${name}:Verified"
            $replacements++
            if ($InterruptAfterReplacement -eq $replacements) {
                throw "INJECTED: $Operation rehearsal after replacement $replacements; existing evidence retained."
            }
        }

        $context = Get-TypezeroCoordinatorRehearsalContext @contextArgs
        $publishedNow = $false
        if ($Operation -ceq 'Restore' -and $context.CompleteRoundRestored -and
            -not $context.Lifecycle.PublishedReceiptPresent) {
            if ($InterruptBeforeReceiptPublication) {
                throw 'INJECTED: Restore rehearsal before receipt publication; original bytes and all proofs retained.'
            }
            # Existing cipher and independent verifier bind root/id/exact manifest
            # plus all seven real displacement proofs. Avoid nested root locking in
            # Publish-TypezeroCoordinatorFixtureReceipt; use the same publication
            # protocol under the lock already held here. Pending is never promoted.
            $ciphertext = New-TypezeroCoordinatorFixtureReceiptCipher -TestRoot $context.Root -TransactionId $TransactionId
            $null = Test-TypezeroCoordinatorFixtureReceiptCipher -TestRoot $context.Root `
                -TransactionId $TransactionId -Ciphertext $ciphertext
            $pending = Join-Path $context.Folder 'receipt.pending'
            $published = Join-Path $context.Folder 'receipt.dpapi'
            Assert-TypezeroFontRecoveryPlainPath -Path $pending
            Assert-TypezeroFontRecoveryPlainPath -Path $published
            if ([IO.File]::Exists($pending) -or [IO.Directory]::Exists($pending) -or
                [IO.File]::Exists($published) -or [IO.Directory]::Exists($published)) {
                throw 'REFUSED: Receipt evidence collision; preserve all artifacts.'
            }
            $stream = [IO.FileStream]::new($pending,[IO.FileMode]::CreateNew,
                [IO.FileAccess]::Write,[IO.FileShare]::None,4096,[IO.FileOptions]::WriteThrough)
            try { $stream.Write($ciphertext,0,$ciphertext.Length); $stream.Flush($true) }
            finally { $stream.Dispose() }
            Write-Debug 'TZ57F2310090903:Restore:receipt:PendingFlushed'
            $null = Test-TypezeroCoordinatorFixtureReceiptCipher -TestRoot $context.Root `
                -TransactionId $TransactionId -Ciphertext (Get-TypezeroFontRecoveryBytes -Path $pending -Maximum 65536)
            # Pin again immediately before same-directory no-overwrite publication.
            $currentCipher = Get-TypezeroFontRecoveryBytes -Path (Join-Path $context.Folder 'coordinator.dpapi') -Maximum 65536
            if ((Get-TypezeroFontRecoveryHash -Bytes $currentCipher) -cne $context.JournalSha256) {
                throw 'REFUSED: Prepared journal changed before receipt publication.'
            }
            Write-Debug 'TZ57F2310090903:Restore:receipt:BeforePublish'
            [IO.File]::Move($pending,$published)
            $null = Test-TypezeroCoordinatorFixtureReceipt -TestRoot $context.Root -TransactionId $TransactionId
            $publishedNow = $true
            $context = Get-TypezeroCoordinatorRehearsalContext @contextArgs
        }
        $status = if ($Operation -ceq 'Apply') { 'APPLIED' }
            elseif ($replacements -gt 0 -or $publishedNow) { 'RESTORED' } else { 'ALREADY_RESTORED' }
        $result = New-TypezeroCoordinatorRehearsalResult -Context $context -Status $status `
            -Operation $Operation -ReplacementCount $replacements
        if ($Operation -ceq 'Restore' -and -not $result.ExactOriginalBytesMatch) {
            throw 'REFUSED: Exact original fixture bytes could not be verified; evidence retained.'
        }
        $result
    }
    finally { $lock.Dispose() }
}

function Invoke-TypezeroCoordinatorFixtureApplyRehearsal {
    [CmdletBinding(SupportsShouldProcess=$true, ConfirmImpact='High')]
    param(
        [Parameter(Mandatory)][string]$TestRoot,
        [Parameter(Mandatory)][ValidatePattern('\A[a-f0-9]{32}\z')][string]$TransactionId,
        [Parameter(Mandatory)][ValidatePattern('\A[a-fA-F0-9]{64}\z')][string]$ExpectedJournalSha256,
        [switch]$Execute,
        [ValidateRange(-1,7)][int]$InterruptAfterReplacement = -1
    )
    Invoke-TypezeroCoordinatorFixtureRehearsalCore -Operation Apply @PSBoundParameters
}

function Restore-TypezeroCoordinatorFixtureRehearsal {
    [CmdletBinding(SupportsShouldProcess=$true, ConfirmImpact='High')]
    param(
        [Parameter(Mandatory)][string]$TestRoot,
        [Parameter(Mandatory)][ValidatePattern('\A[a-f0-9]{32}\z')][string]$TransactionId,
        [Parameter(Mandatory)][ValidatePattern('\A[a-fA-F0-9]{64}\z')][string]$ExpectedJournalSha256,
        [switch]$Execute,
        [ValidateRange(-1,7)][int]$InterruptAfterReplacement = -1,
        [switch]$InterruptBeforeReceiptPublication
    )
    Invoke-TypezeroCoordinatorFixtureRehearsalCore -Operation Restore @PSBoundParameters
}
