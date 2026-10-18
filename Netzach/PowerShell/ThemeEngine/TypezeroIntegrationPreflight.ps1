function Get-TypezeroIntegrationFixturePlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$FixtureRoot,
        [Parameter(Mandatory)]
        [System.Collections.IDictionary]$ExpectedHashes,
        [ValidateSet('Inspect','Live')]
        [string]$RequestedAction = 'Inspect'
    )

    if ($RequestedAction -cne 'Inspect') {
        throw 'REFUSED: Live integration is prohibited.'
    }

    $names = @(
        'settings.json',
        'vim-main.vim',
        'vim-lightline.vim',
        'shell-current.ps1',
        'appearance.mock',
        'history-previous.txt',
        'history-current.txt'
    )

    if ($ExpectedHashes.Count -ne 7) {
        throw 'REFUSED: Exactly seven artifact hashes required.'
    }

    foreach ($key in $ExpectedHashes.Keys) {
        if ([string]$key -cnotin $names) {
            throw 'REFUSED: Unknown expected artifact.'
        }
    }

    $root = [IO.Path]::GetFullPath($FixtureRoot).TrimEnd('\')
    $temp = [IO.Path]::GetFullPath($env:TEMP).TrimEnd('\')
    $parent = [IO.Path]::GetDirectoryName($root)
    $leaf = [IO.Path]::GetFileName($root)

    if (-not [string]::Equals(
        $parent, $temp,
        [StringComparison]::OrdinalIgnoreCase
    ) -or
        $leaf -cnotmatch '\Atypezero-integration-preflight-[0-9a-f]{32}\z') {
        throw 'REFUSED: Root is outside the private fixture scope.'
    }

    if (-not (Test-Path -LiteralPath $root -PathType Container)) {
        throw 'REFUSED: Fixture does not exist.'
    }

    $rootItem = Get-Item -LiteralPath $root -Force
    if (($rootItem.Attributes -band
        [IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw 'REFUSED: Reparse-point fixture root.'
    }

    $items = @(Get-ChildItem -LiteralPath $root -Force)
    $expectedNames = @('.fixture') + $names

    if ($items.Count -ne 8 -or
        (@($items.Name | Sort-Object) -join '|') -cne
        (@($expectedNames | Sort-Object) -join '|')) {
        throw 'REFUSED: Unexpected fixture entries.'
    }

    foreach ($item in $items) {
        if ($item.PSIsContainer -or
            ($item.Attributes -band
             [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw 'REFUSED: Unsafe fixture entry.'
        }
    }

    $marker = [IO.File]::ReadAllText(
        (Join-Path $root '.fixture')
    )

    if ($marker -cne 'TYPEZERO_INTEGRATION_PREFLIGHT_V2') {
        throw 'REFUSED: Invalid fixture marker.'
    }

    $manifest = @(
        foreach ($name in $names) {
            if (-not $ExpectedHashes.Contains($name)) {
                throw "REFUSED: Missing expected hash: $name"
            }

            $wanted = [string]$ExpectedHashes[$name]
            if ($wanted -cnotmatch '\A[A-Fa-f0-9]{64}\z') {
                throw "REFUSED: Invalid hash: $name"
            }

            $actual = (Get-FileHash -LiteralPath `
                (Join-Path $root $name) -Algorithm SHA256).Hash

            if ($actual -cne $wanted.ToUpperInvariant()) {
                throw "REFUSED: Artifact changed: $name"
            }

            [pscustomobject]@{
                Name = $name
                SHA256 = $actual
            }
        }
    )

    [pscustomobject]@{
        Mode = 'ReadOnlyFixturePreflight'
        FixtureRoot = $root
        ArtifactCount = 7
        Artifacts = $manifest
        ExternalProvider = 'RecordOnly'
        EvidenceAuthenticated = $false
        RecoveryAuthorized = $false
        LiveActivationAuthorized = $false
        GlobalRestorationCertified = $false
    }
}