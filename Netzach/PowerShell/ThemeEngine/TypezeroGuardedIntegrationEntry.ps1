function Invoke-TypezeroGuardedFixtureEntry {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$FixtureRoot,
        [Parameter(Mandatory)]
        [System.Collections.IDictionary]$ExpectedHashes,
        [ValidateSet('Inspect','Apply','Recover','Activate')]
        [string]$Operation = 'Inspect'
    )

    if ($Operation -cne 'Inspect') {
        throw 'REFUSED: Guarded integration permits inspection only.'
    }

    $preflight = Join-Path $PSScriptRoot 'TypezeroIntegrationPreflight.ps1'
    $expectedHash = '692B00314712FAF97DE941CAADFFECD923E3A55E0E453D4D879C08143AFE72AD'

    $item = Get-Item -LiteralPath $preflight -Force

    if ($item.PSIsContainer -or
        ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw 'REFUSED: Installed preflight path is unsafe.'
    }

    if ((Get-FileHash -LiteralPath $preflight -Algorithm SHA256).Hash -cne
        $expectedHash) {
        throw 'REFUSED: Installed preflight hash mismatch.'
    }

    # Reuse the tested module; do not reproduce its path/hash checks.
    . $preflight

    $plan = Get-TypezeroIntegrationFixturePlan `
        -FixtureRoot $FixtureRoot `
        -ExpectedHashes $ExpectedHashes `
        -RequestedAction Inspect

    if ($null -eq $plan -or
        $plan.Mode -cne 'ReadOnlyFixturePreflight' -or
        $plan.ArtifactCount -ne 7 -or
        @($plan.Artifacts).Count -ne 7 -or
        $plan.ExternalProvider -cne 'RecordOnly' -or
        $plan.EvidenceAuthenticated -ne $false -or
        $plan.RecoveryAuthorized -ne $false -or
        $plan.LiveActivationAuthorized -ne $false -or
        $plan.GlobalRestorationCertified -ne $false) {
        throw 'REFUSED: Preflight authorization contract mismatch.'
    }

    return [pscustomobject]@{
        ContractVersion = 1
        Operation = 'Inspect'
        Mode = 'FixtureOnly'
        FixtureRoot = $plan.FixtureRoot
        ArtifactCount = $plan.ArtifactCount
        Artifacts = @($plan.Artifacts)
        FileCoordinator = 'NotInvoked'
        ExternalProvider = 'NotInspected'
        EvidenceAuthenticated = $false
        TransactionPrepared = $false
        RecoveryAuthorized = $false
        LiveActivationAuthorized = $false
        GlobalRestorationCertified = $false
    }
}