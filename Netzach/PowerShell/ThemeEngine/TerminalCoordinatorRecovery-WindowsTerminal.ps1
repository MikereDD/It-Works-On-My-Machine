# Typezero ThemeEngine — 57F.23.09.04.03
# READ-ONLY, FIXTURE-ONLY recovery-state inspector. No recovery/write API.
# Requires dot-sourced FontWriter-WindowsTerminal.ps1 (57F.23.07 SHA-256).
# Format v1 is the prepared coordinator prototype; it has NO signed recovery receipt.

function Read-TypezeroCoordinatorFixtureJournal {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$TestRoot,
        [Parameter(Mandatory)][ValidatePattern('\A[a-f0-9]{32}\z')][string]$TransactionId
    )
    $root = Assert-TypezeroFontRecoveryRoot -TestRoot $TestRoot
    $folder = Join-Path $root ('coordinator-' + $TransactionId)
    Assert-TypezeroFontRecoveryPlainPath -Path $folder
    if (-not [IO.Directory]::Exists($folder)) { throw 'Coordinator fixture journal missing.' }
    $sealed = Get-TypezeroFontRecoveryBytes -Path (Join-Path $folder 'coordinator.dpapi') -Maximum 65536
    $plain = [Security.Cryptography.ProtectedData]::Unprotect(
        $sealed, $null, [Security.Cryptography.DataProtectionScope]::CurrentUser)
    if ($plain.Length -lt 2 -or $plain.Length -gt 16384) { throw 'Invalid coordinator manifest length.' }
    $utf8 = [Text.UTF8Encoding]::new($false, $true)
    $json = $utf8.GetString($plain)
    ConvertFrom-TypezeroCoordinatorFixtureManifestJson -Json $json -TestRoot $root -TransactionId $TransactionId
}

function ConvertFrom-TypezeroCoordinatorFixtureManifestJson {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Json,
        [Parameter(Mandatory)][string]$TestRoot,
        [Parameter(Mandatory)][ValidatePattern('\A[a-f0-9]{32}\z')][string]$TransactionId
    )
    $root = Assert-TypezeroFontRecoveryRoot -TestRoot $TestRoot
    $folder = Join-Path $root ('coordinator-' + $TransactionId)
    $document = [Text.Json.JsonDocument]::Parse($Json)
    try {
        $object = $document.RootElement
        $topFields = @('Version','Kind','TransactionId','Root','ThemeId','State','FixtureOnly','FontEnabled','Artifacts')
        Assert-TypezeroCoordinatorExactObject -Element $object -Fields $topFields
        if ($object.GetProperty('Version').GetRawText() -cne '1' -or
            (Get-TypezeroCoordinatorString -Element $object -Name 'Kind') -cne 'TypezeroCrossRendererFixturePlan' -or
            (Get-TypezeroCoordinatorString -Element $object -Name 'TransactionId') -cne $TransactionId -or
            (Get-TypezeroCoordinatorString -Element $object -Name 'Root') -ine $root -or
            (Get-TypezeroCoordinatorString -Element $object -Name 'State') -cne 'Prepared' -or
            $object.GetProperty('FixtureOnly').ValueKind -ne [Text.Json.JsonValueKind]::True -or
            $object.GetProperty('FontEnabled').ValueKind -ne [Text.Json.JsonValueKind]::False) {
            throw 'Coordinator manifest contract violation.'
        }
        $themeId = Get-TypezeroCoordinatorString -Element $object -Name 'ThemeId'
        if ($themeId -cnotmatch '\A[a-z0-9][a-z0-9-]{0,63}\z') { throw 'Invalid fixture theme identifier.' }
        $array = $object.GetProperty('Artifacts')
        if ($array.ValueKind -ne [Text.Json.JsonValueKind]::Array -or
            $array.GetArrayLength() -ne 7) { throw 'Incorrect coordinator artifact count.' }
        $allowedTargets = @('settings.json','vim-main.vim','vim-lightline.vim',
            'shell-current.ps1','appearance.mock','history-previous.txt','history-current.txt')
        $fields = @('Target','Backup','Candidate','BeforeSha256','AfterSha256','BeforeLength','AfterLength')
        $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
        $rows = @(
            foreach ($entry in $array.EnumerateArray()) {
                Assert-TypezeroCoordinatorExactObject -Element $entry -Fields $fields
                $target = Get-TypezeroCoordinatorString -Element $entry -Name 'Target'
                if ($target -cnotin $allowedTargets -or -not $seen.Add($target)) { throw 'Unsupported or repeated artifact.' }
                $base = $target.Replace('.', '_')
                $backup = Get-TypezeroCoordinatorString -Element $entry -Name 'Backup'
                $candidate = Get-TypezeroCoordinatorString -Element $entry -Name 'Candidate'
                if ($backup -cne ($base + '.before') -or
                    $candidate -cne ($base + '.candidate')) { throw 'Invalid artifact path identifier.' }
                $beforeHash = Get-TypezeroCoordinatorString -Element $entry -Name 'BeforeSha256'
                $afterHash = Get-TypezeroCoordinatorString -Element $entry -Name 'AfterSha256'
                if ($beforeHash -cnotmatch '\A[A-F0-9]{64}\z' -or
                    $afterHash -cnotmatch '\A[A-F0-9]{64}\z' -or
                    $beforeHash -ceq $afterHash) { throw 'Invalid or ambiguous artifact SHA-256.' }
                $beforeLength = Get-TypezeroCoordinatorLength -Element $entry -Name 'BeforeLength'
                $afterLength = Get-TypezeroCoordinatorLength -Element $entry -Name 'AfterLength'
                [pscustomobject]@{
                    Target=$target; Backup=$backup; Candidate=$candidate
                    BeforeSha256=$beforeHash; AfterSha256=$afterHash
                    BeforeLength=$beforeLength; AfterLength=$afterLength
                }
            }
        )
        if ($seen.Count -ne 7) { throw 'Coordinator artifact inventory incomplete.' }
        [pscustomobject]@{
            Version=1; Kind='TypezeroCrossRendererFixturePlan'
            TestRoot=$root; JournalDirectory=$folder; TransactionId=$TransactionId
            ThemeId=$themeId; RecordedState='Prepared'; FixtureOnly=$true
            FontEnabled=$false; Artifacts=$rows
        }
    }
    finally { $document.Dispose() }
}

function Assert-TypezeroCoordinatorExactObject {
    param([Parameter(Mandatory)][Text.Json.JsonElement]$Element,
          [Parameter(Mandatory)][string[]]$Fields)
    if ($Element.ValueKind -ne [Text.Json.JsonValueKind]::Object) { throw 'Coordinator JSON object required.' }
    $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($property in $Element.EnumerateObject()) {
        if (-not $seen.Add($property.Name) -or $property.Name -cnotin $Fields) {
            throw 'Duplicate or unexpected coordinator property.'
        }
    }
    if ($seen.Count -ne $Fields.Count) { throw 'Missing coordinator property.' }
}

function Get-TypezeroCoordinatorString {
    param([Parameter(Mandatory)][Text.Json.JsonElement]$Element,
          [Parameter(Mandatory)][string]$Name)
    $value = $Element.GetProperty($Name)
    if ($value.ValueKind -ne [Text.Json.JsonValueKind]::String) { throw "Expected string property: $Name" }
    $value.GetString()
}

function Get-TypezeroCoordinatorLength {
    param([Parameter(Mandatory)][Text.Json.JsonElement]$Element,
          [Parameter(Mandatory)][string]$Name)
    $value = $Element.GetProperty($Name)
    if ($value.ValueKind -ne [Text.Json.JsonValueKind]::Number -or
        $value.GetRawText() -cnotmatch '\A[0-9]+\z') { throw "Invalid length property: $Name" }
    $length = $value.GetInt64()
    if ($length -lt 1 -or $length -gt 8388608) { throw "Out-of-range length: $Name" }
    $length
}

function Get-TypezeroCoordinatorFixtureRecoveryState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$TestRoot,
        [Parameter(Mandatory)][ValidatePattern('\A[a-f0-9]{32}\z')][string]$TransactionId
    )
    $manifest = Read-TypezeroCoordinatorFixtureJournal -TestRoot $TestRoot -TransactionId $TransactionId
    $root = $manifest.TestRoot
    $folder = $manifest.JournalDirectory
    $order = @('settings.json','vim-main.vim','vim-lightline.vim','shell-current.ps1',
        'appearance.mock','history-previous.txt','history-current.txt')
    $byName = @{}
    foreach ($e in $manifest.Artifacts) { $byName[$e.Target] = $e }
    $observations = @()
    $anyProof = $false
    $issues = [Collections.Generic.List[string]]::new()
    foreach ($name in $order) {
        $entry = $byName[$name]
        $backup = Join-Path $folder $entry.Backup
        $candidate = Join-Path $folder $entry.Candidate
        $target = Join-Path $root $entry.Target
        $before = Get-TypezeroFontRecoveryBytes -Path $backup
        $after = Get-TypezeroFontRecoveryBytes -Path $candidate
        if ($before.Length -ne $entry.BeforeLength -or
            (Get-TypezeroFontRecoveryHash -Bytes $before) -cne $entry.BeforeSha256 -or
            $after.Length -ne $entry.AfterLength -or
            (Get-TypezeroFontRecoveryHash -Bytes $after) -cne $entry.AfterSha256) {
            throw "Coordinator immutable journal artifact corrupt: $name"
        }
        # We treat unexpected targets as a conflict, not as a parse failure.
        $position = 'Unknown'
        try {
            $current = Get-TypezeroFontRecoveryBytes -Path $target
            $hash = Get-TypezeroFontRecoveryHash -Bytes $current
            if ($current.Length -eq $entry.BeforeLength -and $hash -ceq $entry.BeforeSha256) { $position = 'Before' }
            elseif ($current.Length -eq $entry.AfterLength -and $hash -ceq $entry.AfterSha256) { $position = 'After' }
        }
        catch { $issues.Add("Cannot read target: $name") }
        $safe = $name.Replace('.', '_')
        $applyProof = $false
        $restoreProof = $false
        foreach ($round in @('partial','complete')) {
            $applyPath = Join-Path $folder ('displaced-apply-' + $round + '-' + $safe + '.bin')
            $restorePath = Join-Path $folder ('displaced-restore-' + $round + '-' + $safe + '.bin')
            if ([IO.File]::Exists($applyPath)) {
                $proof = Get-TypezeroFontRecoveryBytes -Path $applyPath
                if ($proof.Length -ne $entry.BeforeLength -or
                    (Get-TypezeroFontRecoveryHash -Bytes $proof) -cne $entry.BeforeSha256) {
                    $issues.Add("Apply displacement evidence mismatch: $name")
                } else { $applyProof = $true }
                $anyProof = $true
            }
            if ([IO.File]::Exists($restorePath)) {
                $proof = Get-TypezeroFontRecoveryBytes -Path $restorePath
                if ($proof.Length -ne $entry.AfterLength -or
                    (Get-TypezeroFontRecoveryHash -Bytes $proof) -cne $entry.AfterSha256) {
                    $issues.Add("Restore displacement evidence mismatch: $name")
                } else { $restoreProof = $true }
                $anyProof = $true
            }
        }
        $observations += [pscustomobject]@{
            Target=$name; Position=$position
            ApplyEvidenceValid=$applyProof; RestoreEvidenceValid=$restoreProof
        }
    }
    # A names-only whitelist is enforced for evidence. Unknown displacement evidence is unsafe.
    foreach ($file in [IO.Directory]::EnumerateFiles($folder, 'displaced-*')) {
        $leaf = [IO.Path]::GetFileName($file)
        $recognized = $false
        foreach ($name in $order) {
            foreach ($round in @('partial','complete')) {
                $safe = $name.Replace('.', '_')
                if ($leaf -ceq ('displaced-apply-' + $round + '-' + $safe + '.bin') -or
                    $leaf -ceq ('displaced-restore-' + $round + '-' + $safe + '.bin')) {
                    $recognized = $true
                }
            }
        }
        if (-not $recognized) { $issues.Add('Unknown displacement evidence filename.') }
    }
    $state = Get-TypezeroCoordinatorObservedState -Observations $observations
    if ($issues.Count -gt 0) { $state = 'Conflicted' }
    if ($state -ceq 'Prepared' -and $anyProof) { $state = 'OriginalUnresolved' }
    [pscustomobject]@{
        State=$state; RecordedState=$manifest.RecordedState; ThemeId=$manifest.ThemeId
        FixtureOnly=$true; ReadOnly=$true; RecoveryAuthorized=$false
        TransactionId=$manifest.TransactionId; TestRoot=$root
        Issues=@($issues); Artifacts=@($observations)
        Note='No authenticated coordinator recovery receipt exists; classification never authorizes writes.'
    }
}

function Get-TypezeroCoordinatorObservedState {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object[]]$Observations)
    $order = @('settings.json','vim-main.vim','vim-lightline.vim','shell-current.ps1',
        'appearance.mock','history-previous.txt','history-current.txt')
    if ($Observations.Count -ne 7) { return 'Conflicted' }
    $positions = @{}
    foreach ($item in $Observations) {
        if ($null -eq $item.Target -or $item.Target -cnotin $order -or
            $positions.ContainsKey([string]$item.Target) -or
            $item.Position -cnotin @('Before','After')) { return 'Conflicted' }
        $positions[[string]$item.Target] = $item
    }
    if ($positions.Count -ne 7) { return 'Conflicted' }
    $applied = 0
    $seenBefore = $false
    foreach ($name in $order) {
        $entry = $positions[$name]
        if ($entry.Position -ceq 'After') {
            if ($seenBefore -or $entry.ApplyEvidenceValid -ne $true) { return 'Conflicted' }
            $applied++
        } else { $seenBefore = $true }
    }
    if ($applied -eq 0) {
        foreach ($name in $order) {
            if ($positions[$name].ApplyEvidenceValid -eq $true -or
                $positions[$name].RestoreEvidenceValid -eq $true) { return 'OriginalUnresolved' }
        }
        return 'Prepared'
    }
    if ($applied -eq 7) { return 'Applied' }
    'PartiallyApplied'
}
