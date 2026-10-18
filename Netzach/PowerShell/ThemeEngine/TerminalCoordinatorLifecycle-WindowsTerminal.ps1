# Typezero ThemeEngine - 57F.23.10.09.09.02
# Read-only assessment of ONE existing private coordinator fixture journal.
# Dot-source FontWriter, TerminalCoordinatorRecovery and TerminalCoordinatorReceipt first.
# No lock creation, preparation, receipt publication, recovery, or live entry points.

function Get-TypezeroCoordinatorFixtureLifecycleAssessment {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$TestRoot,
        [Parameter(Mandatory)]
        [ValidatePattern('\A[a-f0-9]{32}\z')][string]$TransactionId
    )

    # Invalid fixture boundaries are refused, never converted into a successful report.
    $root = Assert-TypezeroFontRecoveryRoot -TestRoot $TestRoot
    $folder = Join-Path $root ('coordinator-' + $TransactionId)
    $issues = [Collections.Generic.List[object]]::new()
    $blockers = [Collections.Generic.List[string]]::new()
    $blockers.Add('RecoveryNotAuthorized')
    $blockers.Add('LiveActivationNotAuthorized')
    $journalStatus = 'Invalid'
    $recordedState = $null
    $observedState = 'Unavailable'
    $themeId = $null
    $artifacts = @()
    $artifactConsistency = 'Unverified'
    $inventoryValid = $false
    $publishedPresent = $false
    $pendingPresent = $false
    $receiptStatus = 'NotVerified'
    $receiptValid = $false
    $unsafeReceipt = $false
    $folderReadable = $false

    $order = @('settings.json','vim-main.vim','vim-lightline.vim','shell-current.ps1',
        'appearance.mock','history-previous.txt','history-current.txt')
    $allowed = @('coordinator.dpapi','receipt.dpapi','receipt.pending')
    foreach ($name in $order) {
        $safe = $name.Replace('.', '_')
        $allowed += @(($safe + '.before'), ($safe + '.candidate'))
        foreach ($round in @('partial','complete')) {
            $allowed += 'displaced-apply-' + $round + '-' + $safe + '.bin'
            $allowed += 'displaced-restore-' + $round + '-' + $safe + '.bin'
        }
    }

    try {
        Assert-TypezeroFontRecoveryPlainPath -Path $folder
        try { $attributes = [IO.File]::GetAttributes($folder) }
        catch [IO.FileNotFoundException] { $journalStatus = 'Missing'; throw }
        catch [IO.DirectoryNotFoundException] { $journalStatus = 'Missing'; throw }
        if (($attributes -band [IO.FileAttributes]::Directory) -eq 0) {
            throw 'Coordinator journal path is not a directory.'
        }
        $entries = @(Get-ChildItem -LiteralPath $folder -Force -ErrorAction Stop)
        $folderReadable = $true
        $inventoryValid = $true
        foreach ($entry in $entries) {
            # Presence is independent of validity, including wrong-case/unsafe entries.
            if ($entry.Name -ieq 'receipt.dpapi') { $publishedPresent = $true }
            if ($entry.Name -ieq 'receipt.pending') { $pendingPresent = $true }
            try {
                if ($entry.Name -cnotin $allowed -or $entry.PSIsContainer -or
                    ($entry.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                    throw 'Unexpected filename, directory, or redirected journal entry.'
                }
                # Check every known entry, including pending evidence, without decrypting
                # or promoting it. The shared reader enforces single-link handles/limits.
                $maximum = if ($entry.Name -cin @('coordinator.dpapi','receipt.dpapi','receipt.pending')) {
                    65536
                } else { 8388608 }
                $null = Get-TypezeroFontRecoveryBytes -Path $entry.FullName -Maximum $maximum
            }
            catch {
                $inventoryValid = $false
                if ($entry.Name -ieq 'receipt.dpapi') { $unsafeReceipt = $true }
                $issues.Add([pscustomobject]@{
                    Code='JournalInventoryInvalid'; Artifact=$entry.Name
                    Message=$_.Exception.Message
                })
            }
        }
    }
    catch {
        $issues.Add([pscustomobject]@{
            Code='JournalUnavailable'; Artifact='coordinator-' + $TransactionId
            Message=$_.Exception.Message
        })
    }

    if ($folderReadable) {
        # These existing contracts, rather than inferred target positions or receipt
        # filenames, decide whether the manifest and recovery evidence are valid.
        $manifestPath = Join-Path $folder 'coordinator.dpapi'
        if (-not [IO.File]::Exists($manifestPath) -and
            -not [IO.Directory]::Exists($manifestPath) -and
            @($entries | Where-Object { $_.Name -ieq 'coordinator.dpapi' }).Count -eq 0) {
            $journalStatus = 'Missing'
        }
        else {
            try {
                $manifest = Read-TypezeroCoordinatorFixtureJournal -TestRoot $root -TransactionId $TransactionId
                $journalStatus = 'Valid'
                $recordedState = $manifest.RecordedState
                $themeId = $manifest.ThemeId
            }
            catch {
                $issues.Add([pscustomobject]@{
                    Code='JournalInvalid'; Artifact='coordinator.dpapi'; Message=$_.Exception.Message
                })
            }
        }

        if ($journalStatus -ceq 'Valid') {
            try {
                $state = Get-TypezeroCoordinatorFixtureRecoveryState -TestRoot $root -TransactionId $TransactionId
                $observedState = $state.State
                $artifacts = @($state.Artifacts)
                $artifactConsistency = if ($state.State -ceq 'Conflicted' -or -not $inventoryValid) {
                    'Conflicted'
                } else { 'Consistent' }
                foreach ($message in $state.Issues) {
                    $issues.Add([pscustomobject]@{ Code='ArtifactConflict'; Artifact=$null; Message=$message })
                }
                if ($state.State -ceq 'Conflicted') { $blockers.Add('ArtifactConflict') }
            }
            catch {
                $blockers.Add('ArtifactInspectionFailed')
                $issues.Add([pscustomobject]@{
                    Code='ArtifactInspectionFailed'; Artifact=$null; Message=$_.Exception.Message
                })
            }
        }

        if ($publishedPresent) {
            if ($unsafeReceipt) { $receiptStatus = 'Invalid' }
            elseif ($journalStatus -ceq 'Valid') {
                try {
                    $receipt = Test-TypezeroCoordinatorFixtureReceipt -TestRoot $root -TransactionId $TransactionId
                    if ($receipt.ReceiptValid -ne $true -or
                        $receipt.State -cne 'RecoveredReceiptVerified' -or
                        $receipt.RecoveryAuthorized -ne $false -or
                        $receipt.FixtureOnly -ne $true -or $receipt.ReadOnly -ne $true) {
                        throw 'Receipt verifier contract mismatch.'
                    }
                    $receiptValid = $true
                    $receiptStatus = 'Valid'
                }
                catch {
                    $receiptStatus = 'Invalid'
                    $issues.Add([pscustomobject]@{
                        Code='ReceiptInvalid'; Artifact='receipt.dpapi'; Message=$_.Exception.Message
                    })
                }
            }
        }
        else {
            $receiptStatus = if ($pendingPresent) { 'Pending' } else { 'Missing' }
        }
    }

    if ($journalStatus -ceq 'Missing') { $blockers.Add('JournalMissing') }
    elseif ($journalStatus -cne 'Valid') { $blockers.Add('JournalInvalid') }
    if (-not $inventoryValid) { $blockers.Add('JournalInventoryInvalid') }
    if ($pendingPresent) { $blockers.Add('PendingReceipt') }
    if ($receiptStatus -ceq 'Invalid') { $blockers.Add('ReceiptInvalid') }
    elseif (-not $publishedPresent -and $folderReadable) { $blockers.Add('ReceiptMissing') }
    elseif (-not $receiptValid) { $blockers.Add('ReceiptNotVerified') }

    [pscustomobject]@{
        ContractVersion=1; Milestone='57F.23.10.09.09.02'
        Mode='ReadOnlyFixtureLifecycleAssessment'
        TestRoot=$root; TransactionId=$TransactionId; JournalDirectory=$folder; ThemeId=$themeId
        JournalStatus=$journalStatus; RecordedState=$recordedState; ObservedState=$observedState
        JournalInventoryValid=$inventoryValid
        ArtifactConsistency=$artifactConsistency; Artifacts=@($artifacts)
        ReceiptStatus=$receiptStatus; ReceiptValid=$receiptValid
        PublishedReceiptPresent=$publishedPresent; PendingReceiptPresent=$pendingPresent
        Blockers=@($blockers); Issues=@($issues)
        FixtureOnly=$true; ReadOnly=$true; AtomicSnapshot=$false
        OriginalInputsAuthenticated=$false; CrossRootEvidenceAuthenticated=$false
        ExternalProviderInvoked=$false; GlobalRestorationCertified=$false
        RecoveryAuthorized=$false; LiveActivationAuthorized=$false
        Note='Observed fixture evidence only. RecordedState remains Prepared; a valid published receipt is separate evidence. No action is authorized, and concurrent changes are not excluded.'
    }
}
