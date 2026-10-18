# Typezero ThemeEngine - Step 57F.23.09.04.06.03
# EXCLUSIVELY private TEMP fixtures. No live settings or recovery-write API.
# Requires dot-sourced corrected FontWriter and TerminalCoordinatorRecovery modules.
# DPAPI CurrentUser is not a defense against malicious code acting as the same user.

function Get-TypezeroCoordinatorFixtureReceiptEvidence {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$TestRoot,
        [Parameter(Mandatory)][ValidatePattern('\A[a-f0-9]{32}\z')][string]$TransactionId
    )
    $root = Assert-TypezeroFontRecoveryRoot -TestRoot $TestRoot
    $manifest = Read-TypezeroCoordinatorFixtureJournal -TestRoot $root -TransactionId $TransactionId
    $state = Get-TypezeroCoordinatorFixtureRecoveryState -TestRoot $root -TransactionId $TransactionId
    if ($state.State -cne 'OriginalUnresolved' -or @($state.Issues).Count -ne 0 -or
        $state.RecoveryAuthorized -ne $false) {
        throw 'Recovery receipt requires original fixture state with valid evidence and no authorization.'
    }
    $folder = $manifest.JournalDirectory
    Assert-TypezeroFontRecoveryPlainPath -Path $folder
    $order = @('settings.json','vim-main.vim','vim-lightline.vim','shell-current.ps1',
        'appearance.mock','history-previous.txt','history-current.txt')
    $byTarget = @{}
    foreach ($entry in $manifest.Artifacts) { $byTarget[$entry.Target] = $entry }
    $rows = @(
        foreach ($name in $order) {
            $entry = $byTarget[$name]
            if ($null -eq $entry) { throw "Missing fixture artifact: $name" }
            $safe = $name.Replace('.', '_')
            $paths = @{
                Apply = Join-Path $folder ('displaced-apply-complete-' + $safe + '.bin')
                Restore = Join-Path $folder ('displaced-restore-complete-' + $safe + '.bin')
                Target = Join-Path $root $name
            }
            $expected = @{
                Apply = @($entry.BeforeSha256, [long]$entry.BeforeLength)
                Restore = @($entry.AfterSha256, [long]$entry.AfterLength)
                Target = @($entry.BeforeSha256, [long]$entry.BeforeLength)
            }
            $actual = @{}
            foreach ($kind in @('Apply','Restore','Target')) {
                $bytes = Get-TypezeroFontRecoveryBytes -Path $paths[$kind]
                $hash = Get-TypezeroFontRecoveryHash -Bytes $bytes
                if ($bytes.Length -ne $expected[$kind][1] -or
                    $hash -cne $expected[$kind][0]) {
                    throw "Receipt evidence incomplete or changed: $name/$kind"
                }
                $actual[$kind] = $hash
            }
            [ordered]@{
                Target=$name; BeforeSha256=$entry.BeforeSha256
                AfterSha256=$entry.AfterSha256; ApplyProofSha256=$actual.Apply
                RestoreProofSha256=$actual.Restore; TargetSha256=$actual.Target
            }
        }
    )
    $manifestPath = Join-Path $folder 'coordinator.dpapi'
    $manifestCipher = Get-TypezeroFontRecoveryBytes -Path $manifestPath -Maximum 65536
    [pscustomobject]@{
        Root=$root; TransactionId=$TransactionId; JournalDirectory=$folder
        ThemeId=$manifest.ThemeId
        ManifestSha256=(Get-TypezeroFontRecoveryHash -Bytes $manifestCipher)
        Artifacts=$rows; RecoveryAuthorized=$false
    }
}

function New-TypezeroCoordinatorFixtureReceiptCipher {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$TestRoot,
        [Parameter(Mandatory)][ValidatePattern('\A[a-f0-9]{32}\z')][string]$TransactionId
    )
    $evidence = Get-TypezeroCoordinatorFixtureReceiptEvidence -TestRoot $TestRoot -TransactionId $TransactionId
    $data = [ordered]@{
        Version=1; Kind='TypezeroCrossRendererFixtureRecoveryReceipt'
        TransactionId=$evidence.TransactionId; Root=$evidence.Root
        ThemeId=$evidence.ThemeId; State='Recovered'; FixtureOnly=$true
        ManifestSha256=$evidence.ManifestSha256
        ReceiptNonce=([guid]::NewGuid().ToString('N'))
        Artifacts=$evidence.Artifacts
    }
    $utf8 = [Text.UTF8Encoding]::new($false, $true)
    $bytes = $utf8.GetBytes(($data | ConvertTo-Json -Depth 8 -Compress))
    if ($bytes.Length -gt 16384) { throw 'Receipt JSON exceeds policy limit.' }
    $entropy = $utf8.GetBytes('Typezero.CoordinatorFixtureReceipt.57F2309040602')
    return ,([Security.Cryptography.ProtectedData]::Protect(
        $bytes, $entropy, [Security.Cryptography.DataProtectionScope]::CurrentUser))
}

function Test-TypezeroCoordinatorFixtureReceiptCipher {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$TestRoot,
        [Parameter(Mandatory)][ValidatePattern('\A[a-f0-9]{32}\z')][string]$TransactionId,
        [Parameter(Mandatory)][byte[]]$Ciphertext,
        [string]$ExpectedRoot,
        [string]$ExpectedTransactionId
    )
    $root = Assert-TypezeroFontRecoveryRoot -TestRoot $TestRoot
    if (-not $ExpectedRoot) { $ExpectedRoot = $root }
    if (-not $ExpectedTransactionId) { $ExpectedTransactionId = $TransactionId }
    if ($Ciphertext.Length -lt 16 -or $Ciphertext.Length -gt 65536) {
        throw 'Invalid sealed receipt size.'
    }
    $utf8 = [Text.UTF8Encoding]::new($false, $true)
    $entropy = $utf8.GetBytes('Typezero.CoordinatorFixtureReceipt.57F2309040602')
    $plain = [Security.Cryptography.ProtectedData]::Unprotect(
        $Ciphertext, $entropy, [Security.Cryptography.DataProtectionScope]::CurrentUser)
    if ($plain.Length -lt 2 -or $plain.Length -gt 16384) { throw 'Invalid receipt plaintext size.' }
    $document = [Text.Json.JsonDocument]::Parse($utf8.GetString($plain))
    try {
        $top = $document.RootElement
        Assert-TypezeroCoordinatorExactObject -Element $top -Fields @(
            'Version','Kind','TransactionId','Root','ThemeId','State','FixtureOnly',
            'ManifestSha256','ReceiptNonce','Artifacts')
        if ($top.GetProperty('Version').GetRawText() -cne '1' -or
            (Get-TypezeroCoordinatorString -Element $top -Name 'Kind') -cne
                'TypezeroCrossRendererFixtureRecoveryReceipt' -or
            (Get-TypezeroCoordinatorString -Element $top -Name 'TransactionId') -cne $TransactionId -or
            (Get-TypezeroCoordinatorString -Element $top -Name 'TransactionId') -cne $ExpectedTransactionId -or
            (Get-TypezeroCoordinatorString -Element $top -Name 'Root') -ine $root -or
            (Get-TypezeroCoordinatorString -Element $top -Name 'Root') -ine $ExpectedRoot -or
            (Get-TypezeroCoordinatorString -Element $top -Name 'State') -cne 'Recovered' -or
            $top.GetProperty('FixtureOnly').ValueKind -ne [Text.Json.JsonValueKind]::True -or
            (Get-TypezeroCoordinatorString -Element $top -Name 'ReceiptNonce') -cnotmatch '\A[a-f0-9]{32}\z') {
            throw 'Receipt identity or policy mismatch.'
        }
        $evidence = Get-TypezeroCoordinatorFixtureReceiptEvidence -TestRoot $root -TransactionId $TransactionId
        if ((Get-TypezeroCoordinatorString -Element $top -Name 'ThemeId') -cne $evidence.ThemeId -or
            (Get-TypezeroCoordinatorString -Element $top -Name 'ManifestSha256') -cne $evidence.ManifestSha256) {
            throw 'Receipt not bound to the verified journal.'
        }
        $items = $top.GetProperty('Artifacts')
        if ($items.ValueKind -ne [Text.Json.JsonValueKind]::Array -or
            $items.GetArrayLength() -ne 7) { throw 'Receipt requires seven artifacts.' }
        $byName = @{}
        foreach ($item in $evidence.Artifacts) { $byName[$item.Target] = $item }
        $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
        foreach ($row in $items.EnumerateArray()) {
            Assert-TypezeroCoordinatorExactObject -Element $row -Fields @(
                'Target','BeforeSha256','AfterSha256','ApplyProofSha256',
                'RestoreProofSha256','TargetSha256')
            $name = Get-TypezeroCoordinatorString -Element $row -Name 'Target'
            if (-not $byName.ContainsKey($name) -or -not $seen.Add($name)) {
                throw 'Duplicate or unexpected receipt artifact.'
            }
            foreach ($field in @('BeforeSha256','AfterSha256','ApplyProofSha256',
                    'RestoreProofSha256','TargetSha256')) {
                $value = Get-TypezeroCoordinatorString -Element $row -Name $field
                if ($value -cnotmatch '\A[A-F0-9]{64}\z' -or
                    $value -cne $byName[$name][$field]) {
                    throw "Receipt evidence mismatch: $name/$field"
                }
            }
        }
        if ($seen.Count -ne 7) { throw 'Incomplete receipt artifact inventory.' }
    }
    finally { $document.Dispose() }
    [pscustomobject]@{
        State='RecoveredReceiptVerified'; ReceiptValid=$true; FixtureOnly=$true
        ReadOnly=$true; RecoveryAuthorized=$false
        TransactionId=$TransactionId; Root=$root
    }
}

function Test-TypezeroCoordinatorFixtureReceipt {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$TestRoot,
        [Parameter(Mandatory)][ValidatePattern('\A[a-f0-9]{32}\z')][string]$TransactionId
    )
    $root = Assert-TypezeroFontRecoveryRoot -TestRoot $TestRoot
    $folder = Join-Path $root ('coordinator-' + $TransactionId)
    Assert-TypezeroFontRecoveryPlainPath -Path $folder
    $published = Join-Path $folder 'receipt.dpapi'
    $ciphertext = Get-TypezeroFontRecoveryBytes -Path $published -Maximum 65536
    Test-TypezeroCoordinatorFixtureReceiptCipher -TestRoot $root `
        -TransactionId $TransactionId -Ciphertext $ciphertext
}

function Publish-TypezeroCoordinatorFixtureReceipt {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$TestRoot,
        [Parameter(Mandatory)][ValidatePattern('\A[a-f0-9]{32}\z')][string]$TransactionId
    )
    $root = Assert-TypezeroFontRecoveryRoot -TestRoot $TestRoot
    $lock = Open-TypezeroFontRecoveryLock -TestRoot $root
    try {
        $evidence = Get-TypezeroCoordinatorFixtureReceiptEvidence -TestRoot $root -TransactionId $TransactionId
        $folder = $evidence.JournalDirectory
        Assert-TypezeroFontRecoveryPlainPath -Path $folder
        $published = Join-Path $folder 'receipt.dpapi'
        $pending = Join-Path $folder 'receipt.pending'
        if ([IO.File]::Exists($published) -or [IO.File]::Exists($pending) -or
            [IO.Directory]::Exists($published) -or [IO.Directory]::Exists($pending)) {
            throw 'Receipt already published or pending; manual inspection required.'
        }
        $ciphertext = New-TypezeroCoordinatorFixtureReceiptCipher -TestRoot $root -TransactionId $TransactionId
        # Validate the exact bytes to be published before creating a receipt file.
        $null = Test-TypezeroCoordinatorFixtureReceiptCipher -TestRoot $root `
            -TransactionId $TransactionId -Ciphertext $ciphertext
        $stream = [IO.FileStream]::new($pending, [IO.FileMode]::CreateNew,
            [IO.FileAccess]::Write, [IO.FileShare]::None, 4096, [IO.FileOptions]::WriteThrough)
        try { $stream.Write($ciphertext, 0, $ciphertext.Length); $stream.Flush($true) }
        finally { $stream.Dispose() }
        # Re-read and validate evidence immediately before publishing. This isn't CAS or a power-loss proof.
        $null = Test-TypezeroCoordinatorFixtureReceiptCipher -TestRoot $root `
            -TransactionId $TransactionId -Ciphertext (Get-TypezeroFontRecoveryBytes -Path $pending -Maximum 65536)
        [IO.File]::Move($pending, $published) # Same-directory, no overwrite.
        Test-TypezeroCoordinatorFixtureReceipt -TestRoot $root -TransactionId $TransactionId
    }
    finally { $lock.Dispose() }
}
