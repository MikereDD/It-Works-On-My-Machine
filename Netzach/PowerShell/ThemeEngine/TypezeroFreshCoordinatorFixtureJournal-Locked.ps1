function Write-TypezeroCoordinatorFixtureFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][AllowEmptyCollection()][byte[]]$Bytes
    )

    $full = [IO.Path]::GetFullPath($Path)
    Assert-TypezeroFontRecoveryPlainPath -Path $full

    $parent = [IO.Path]::GetDirectoryName($full)
    $leaf = [IO.Path]::GetFileName($full)

    $baseline = @(
        'vim-main.vim','vim-lightline.vim',
        'shell-current.ps1','appearance.mock',
        'history-previous.txt','history-current.txt'
    )

    $targets = @('settings.json') + $baseline

    if ($leaf -cin $baseline) {
        $root = Assert-TypezeroFontRecoveryRoot -TestRoot $parent
    }
    else {
        if ([IO.Path]::GetFileName($parent) -cnotmatch
            '\Acoordinator-[a-f0-9]{32}\z') {
            throw 'REFUSED: Coordinator writer path outside journal scope.'
        }

        $root = Assert-TypezeroFontRecoveryRoot -TestRoot (
            [IO.Path]::GetDirectoryName($parent)
        )

        Assert-TypezeroFontRecoveryPlainPath -Path $parent

        if (-not [IO.Directory]::Exists($parent)) {
            throw 'REFUSED: Coordinator journal folder missing.'
        }

        $allowed = @('coordinator.dpapi')
        foreach ($target in $targets) {
            $base = $target.Replace('.', '_')
            $allowed += ($base + '.before')
            $allowed += ($base + '.candidate')
        }

        if ($leaf -cnotin $allowed) {
            throw 'REFUSED: Coordinator writer filename not permitted.'
        }
    }

    if (-not [IO.Directory]::Exists($root)) {
        throw 'REFUSED: Coordinator fixture root missing.'
    }

    $max = if ($leaf -ceq 'coordinator.dpapi') {
        65536
    } else {
        8388608
    }

    if ($Bytes.Length -lt 1 -or $Bytes.Length -gt $max) {
        throw 'REFUSED: Coordinator writer payload length invalid.'
    }

    # CreateNew prevents overwriting existing evidence.
    $stream = [IO.FileStream]::new(
        $full, [IO.FileMode]::CreateNew,
        [IO.FileAccess]::Write, [IO.FileShare]::None,
        4096, [IO.FileOptions]::WriteThrough
    )

    try {
        $stream.Write($Bytes, 0, $Bytes.Length)
        $stream.Flush($true)
    }
    finally {
        $stream.Dispose()
    }
}
function New-TypezeroFreshCoordinatorFixtureJournal {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$PreflightRoot,
        [Parameter(Mandatory)][string]$RecoveryRoot,
        [Parameter(Mandatory)][System.Collections.IDictionary]$ExpectedHashes,
        [Parameter(Mandatory)][System.Collections.IDictionary]$Candidates,
        [ValidatePattern('\A[a-z0-9][a-z0-9-]{0,63}\z')]
        [string]$ThemeId = 'fixture-nord-dark'
    )

    $order = @(
        'settings.json',
        'vim-main.vim',
        'vim-lightline.vim',
        'shell-current.ps1',
        'appearance.mock',
        'history-previous.txt',
        'history-current.txt'
    )

    # Installed inspection entry, with all seven snapshot checks.
    $plan = Invoke-TypezeroGuardedFixtureEntry `
        -FixtureRoot $PreflightRoot `
        -ExpectedHashes $ExpectedHashes `
        -Operation Inspect

    if ($plan.ArtifactCount -ne 7 -or
        $plan.RecoveryAuthorized -ne $false -or
        $plan.LiveActivationAuthorized -ne $false -or
        $plan.TransactionPrepared -ne $false) {
        throw 'REFUSED: Unsafe preflight result.'
    }

    $root = Assert-TypezeroFontRecoveryRoot -TestRoot $RecoveryRoot

    $lock = Open-TypezeroFontRecoveryLock -TestRoot $root
    try {

    $items = @(Get-ChildItem -LiteralPath $root -Force)
    $expectedEntries = @($order) + @('.transaction.lock')

    if ($items.Count -ne 8 -or
        (@($items.Name | Sort-Object) -join '|') -cne
        (@($expectedEntries | Sort-Object) -join '|')) {
        throw 'REFUSED: Recovery fixture entries are not a clean baseline.'
    }

    foreach ($item in $items) {
        if ($item.PSIsContainer -or
            ($item.Attributes -band
             [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw 'REFUSED: Unsafe recovery fixture entry.'
        }
    }

    if ($Candidates.Count -ne 7) {
        throw 'REFUSED: Exactly seven candidates required.'
    }

    foreach ($key in $Candidates.Keys) {
        if ([string]$key -cnotin $order) {
            throw 'REFUSED: Unknown candidate target.'
        }
    }

    $snapshots = [ordered]@{}

    foreach ($name in $order) {
        if (-not $Candidates.Contains($name) -or
            $Candidates[$name] -isnot [byte[]]) {
            throw "REFUSED: Missing or invalid candidate: $name"
        }

        $before = Get-TypezeroFontRecoveryBytes -Path (
            Join-Path $root $name
        )

        $beforeHash = (
            Get-TypezeroFontRecoveryHash -Bytes $before
        ).ToUpperInvariant()

        if ($beforeHash -cne
            ([string]$ExpectedHashes[$name]).ToUpperInvariant()) {
            throw "REFUSED: Recovery baseline changed: $name"
        }

        $candidate = [byte[]]$Candidates[$name]

        if ($candidate.Length -lt 1 -or
            $candidate.Length -gt 8388608) {
            throw "REFUSED: Invalid candidate length: $name"
        }

        $afterHash = (
            Get-TypezeroFontRecoveryHash -Bytes $candidate
        ).ToUpperInvariant()

        if ($beforeHash -ceq $afterHash) {
            throw "REFUSED: Candidate unchanged: $name"
        }

        $snapshots[$name] = [pscustomobject]@{
            Before = $before
            Candidate = $candidate
            BeforeSHA256 = $beforeHash
            AfterSHA256 = $afterHash
        }
    }

    # Everything above is validation. Only now create a fresh journal.
    $id = [guid]::NewGuid().ToString('N')
    $folder = Join-Path $root ('coordinator-' + $id)

    Assert-TypezeroFontRecoveryPlainPath -Path $folder

    if ([IO.Directory]::Exists($folder) -or
        [IO.File]::Exists($folder)) {
        throw 'REFUSED: Journal identity already exists.'
    }

    [void][IO.Directory]::CreateDirectory($folder)

    $rows = @()

    foreach ($name in $order) {
        $record = $snapshots[$name]
        $safe = $name.Replace('.', '_')
        $backupName = $safe + '.before'
        $candidateName = $safe + '.candidate'

        Write-TypezeroCoordinatorFixtureFile `
            -Path (Join-Path $folder $backupName) `
            -Bytes $record.Before

        Write-TypezeroCoordinatorFixtureFile `
            -Path (Join-Path $folder $candidateName) `
            -Bytes $record.Candidate

        $rows += [ordered]@{
            Target = $name
            Backup = $backupName
            Candidate = $candidateName
            BeforeSha256 = $record.BeforeSHA256
            AfterSha256 = $record.AfterSHA256
            BeforeLength = $record.Before.Length
            AfterLength = $record.Candidate.Length
        }
    }

    $manifest = [ordered]@{
        Version = 1
        Kind = 'TypezeroCrossRendererFixturePlan'
        TransactionId = $id
        Root = $root
        ThemeId = $ThemeId
        State = 'Prepared'
        FixtureOnly = $true
        FontEnabled = $false
        Artifacts = $rows
    }

    $utf8 = [Text.UTF8Encoding]::new($false, $true)
    $json = $utf8.GetBytes(
        ($manifest | ConvertTo-Json -Depth 8 -Compress)
    )

    if ($json.Length -gt 16384) {
        throw 'REFUSED: Manifest exceeds allowed size.'
    }

    $sealed = [Security.Cryptography.ProtectedData]::Protect(
        $json,
        $null,
        [Security.Cryptography.DataProtectionScope]::CurrentUser
    )

    Write-TypezeroCoordinatorFixtureFile `
        -Path (Join-Path $folder 'coordinator.dpapi') `
        -Bytes $sealed

    # Independent validator must recognize the result.
    $verified = Read-TypezeroCoordinatorFixtureJournal `
        -TestRoot $root -TransactionId $id

    $state = Get-TypezeroCoordinatorFixtureRecoveryState `
        -TestRoot $root -TransactionId $id

    if ($verified.TransactionId -cne $id -or
        $verified.ThemeId -cne $ThemeId -or
        @($verified.Artifacts).Count -ne 7 -or
        $state.State -cne 'Prepared' -or
        @($state.Issues).Count -ne 0) {
        throw 'REFUSED: Coordinator did not recognize prepared journal.'
    }

    if ([IO.File]::Exists((Join-Path $folder 'receipt.dpapi')) -or
        [IO.File]::Exists((Join-Path $folder 'receipt.pending'))) {
        throw 'REFUSED: Unexpected recovery receipt.'
    }

    [pscustomobject]@{
        ContractVersion = 1
        Mode = 'PrivateFixtureJournalPreparation'
        Root = $root
        TransactionId = $id
        JournalDirectory = $folder
        ThemeId = $ThemeId
        ArtifactCount = 7
        CoordinatorState = $state.State
        JournalSHA256 = (
            Get-FileHash -LiteralPath (
                Join-Path $folder 'coordinator.dpapi'
            ) -Algorithm SHA256
        ).Hash
        TransactionPrepared = $true
        OriginalInputsAuthenticated = $false
        CrossRootEvidenceAuthenticated = $false
        ExternalProviderInvoked = $false
        RecoveryReceiptPresent = $false
        RecoveryAuthorized = $false
        LiveActivationAuthorized = $false
        GlobalRestorationCertified = $false
    }
    }
    finally {
        $lock.Dispose()
    }
}