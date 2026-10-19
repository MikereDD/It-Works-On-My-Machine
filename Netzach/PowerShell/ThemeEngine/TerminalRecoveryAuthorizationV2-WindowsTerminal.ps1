
# Typezero ThemeEngine
# V2 authenticated recovery assessment
# Read-only, fixture-only. No recovery execution or authorization.

Set-StrictMode -Version Latest

function Get-TypezeroOfflineTerminalV2RecoveryAssessment {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$TestRoot,

        [Parameter(Mandatory)]
        [string]$BackupDirectory,

        [byte[]]$IndependentKey
    )

    $dependencies = @(
        'Get-TypezeroOfflineTerminalV2Paths'
        'Get-TypezeroOfflineTerminalCombinedV2RecoveryDiagnostic'
        'Get-TypezeroOfflineTerminalV2SealResult'
    )

    foreach ($name in $dependencies) {
        if (-not (Get-Command $name -CommandType Function `
                -ErrorAction SilentlyContinue)) {
            throw "REFUSED: Recovery assessment dependency missing: $name"
        }
    }

    # Enforce the existing fixture-only path validation.
    # Invalid or redirected roots must fail rather than fall back
    # to a production settings location.
    $paths = Get-TypezeroOfflineTerminalV2Paths `
        -TestRoot $TestRoot

    $diagnostic = Get-TypezeroOfflineTerminalCombinedV2RecoveryDiagnostic `
        -TestRoot $paths.Root `
        -BackupDirectory $BackupDirectory

    $evidence = Get-TypezeroOfflineTerminalV2SealResult `
        -TestRoot $paths.Root `
        -BackupDirectory $BackupDirectory `
        -IndependentKey $IndependentKey

    $decision = 'RECOVERY_REFUSED'
    $reason = 'Recovery eligibility cannot be established.'

    if ($evidence.Status -ceq 'UNTRUSTED') {
        $decision = 'UNTRUSTED'
        $reason = 'Independent evidence authentication is required.'
    }
    elseif ($evidence.Status -cne 'AUTHENTICATED') {
        $decision = 'EVIDENCE_REFUSED'
        $reason = 'Evidence is incomplete or failed authentication.'
    }
    elseif ($diagnostic.State -ceq 'SETTINGS_CONFLICT') {
        $decision = 'SETTINGS_CONFLICT'
        $reason = 'Current settings differ from the authenticated transaction.'
    }
    elseif ($diagnostic.State -ceq 'ORIGINAL_BYTES_PRESENT') {
        $decision = 'NO_RECOVERY_NEEDED'
        $reason = 'Current settings already match the preserved original.'
    }
    elseif (
        $diagnostic.State -ceq 'APPLIED_BYTES_PRESENT' -and
        $diagnostic.ReceiptState -ceq 'VALID' -and
        $diagnostic.BackupIntegrity -ceq 'MATCH' -and
        $diagnostic.SettingsState -ceq 'AFTER'
    ) {
        $decision = 'ELIGIBLE_FOR_REVIEW'
        $reason = 'Authenticated evidence and current bytes are consistent; explicit authorization has not been granted.'
    }

    [pscustomobject]@{
        Version = 2
        Decision = $decision
        Reason = $reason

        EvidenceStatus = $evidence.Status
        DiagnosticState = $diagnostic.State

        BeforeSha256 = $diagnostic.BeforeSha256
        AfterSha256 = $diagnostic.AfterSha256

        ReceiptAuthenticated = $evidence.ReceiptAuthenticated

        ReadOnly = $true
        FixtureOnly = $true

        EligibleForAuthorizationReview = (
            $decision -ceq 'ELIGIBLE_FOR_REVIEW'
        )

        RecoveryAllowed = $false
        RecoveryAuthorized = $false
        LiveActivationAuthorized = $false
        OperationPhase = 'UNKNOWN'

        TestRoot = $paths.Root
        BackupDirectory = $evidence.BackupDirectory
    }
}
