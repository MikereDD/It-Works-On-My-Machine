# Typezero ThemeEngine — 57F.23.10.06.04
# TEMP-ONLY MOCK registry evidence. NO production registry, Windows theme,
# wallpaper, or live recovery access. DPAPI CurrentUser is same-user trust only.
# v4: Authenticated sidecar binds SHA-256 of every byte of the evidence.dpapi
# envelope, including header fields that DPAPI itself may ignore. The anchor
# sidecar is DPAPI protected, but its OWN envelope is not externally pinned.
Set-StrictMode -Version Latest

function Get-TypezeroProviderFixtureBlueprint {
    [CmdletBinding()]
    param()
    $rows = @(
        [ordered]@{ Name='registry-0.mock'; Before=[ordered]@{ Exists=$true; Type='DWord'; Value=1 }; After=[ordered]@{ Exists=$true; Type='DWord'; Value=0 } }
        [ordered]@{ Name='registry-1.mock'; Before=[ordered]@{ Exists=$true; Type='DWord'; Value=1 }; After=[ordered]@{ Exists=$true; Type='DWord'; Value=0 } }
        [ordered]@{ Name='registry-2.mock'; Before=[ordered]@{ Exists=$true; Type='DWord'; Value=0 }; After=[ordered]@{ Exists=$true; Type='DWord'; Value=1 } }
        [ordered]@{ Name='registry-3.mock'; Before=[ordered]@{ Exists=$false; Type=''; Value=$null }; After=[ordered]@{ Exists=$true; Type='DWord'; Value=0 } }
        [ordered]@{ Name='registry-4.mock'; Before=[ordered]@{ Exists=$true; Type='DWord'; Value=0 }; After=[ordered]@{ Exists=$true; Type='DWord'; Value=1 } }
    )
    return ,$rows
}

function Assert-TypezeroProviderFixturePlainFile {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path, [switch]$AllowMissing)
    if (-not (Test-Path -LiteralPath $Path)) {
        if ($AllowMissing) { return }
        throw "REFUSED: Missing fixture file $Path"
    }
    $item = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
    if ($item.PSIsContainer -or
        (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0)) {
        throw "REFUSED: Unsafe fixture file $Path"
    }
}

function Assert-TypezeroProviderFixtureRoot {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$TestRoot)
    if (-not $IsWindows) { throw 'REFUSED: Windows-only DPAPI fixture.' }
    if ([string]::IsNullOrWhiteSpace($env:TEMP)) { throw 'REFUSED: TEMP unavailable.' }
    $root = [IO.Path]::GetFullPath($TestRoot).TrimEnd([char[]]@('\','/'))
    $temp = [IO.Path]::GetFullPath($env:TEMP).TrimEnd([char[]]@('\','/'))
    $parent = [IO.Path]::GetDirectoryName($root)
    $leaf = [IO.Path]::GetFileName($root)
    if (-not [string]::Equals($parent, $temp, [StringComparison]::OrdinalIgnoreCase) -or
        $leaf -cnotmatch '\Atypezero-provider-sealed-[a-f0-9]{32}\z') {
        throw 'REFUSED: Only direct, named private TEMP fixture roots are permitted.'
    }
    $info = Get-Item -LiteralPath $root -Force -ErrorAction Stop
    if (-not $info.PSIsContainer -or
        (($info.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0)) {
        throw 'REFUSED: Fixture root is not a plain directory.'
    }
    $marker = Join-Path $root '.fixture'
    Assert-TypezeroProviderFixturePlainFile -Path $marker
    if ([IO.File]::ReadAllText($marker) -cne 'TYPEZERO_PROVIDER_SEALED_FIXTURE_V1') {
        throw 'REFUSED: Invalid private fixture marker.'
    }
    return $root
}

function Get-TypezeroProviderMockData {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Value)
    if (-not [bool]$Value.Exists) { return $null }
    if ([string]$Value.Type -cne 'DWord' -or
        [int]$Value.Value -notin @(0,1)) {
        throw 'REFUSED: Unsupported mock value shape.'
    }
    return ('DWORD:{0}' -f [int]$Value.Value)
}

function Read-TypezeroProviderFixtureSlot {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Root, [Parameter(Mandatory)][int]$Index)
    if ($Index -lt 0 -or $Index -gt 4) { throw 'REFUSED: Invalid mock slot.' }
    $path = Join-Path $Root ("registry-{0}.mock" -f $Index)
    Assert-TypezeroProviderFixturePlainFile -Path $path -AllowMissing
    if (-not [IO.File]::Exists($path)) { return $null }
    if ((Get-Item -LiteralPath $path -Force).Length -gt 64) {
        throw 'REFUSED: Oversize mock slot.'
    }
    return [IO.File]::ReadAllText($path, [Text.UTF8Encoding]::new($false, $true))
}

function Write-TypezeroProviderFixtureSlot {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][int]$Index,
        [AllowNull()][object]$NewData
    )
    if ($Index -lt 0 -or $Index -gt 4) { throw 'REFUSED: Invalid mock slot.' }
    $path = Join-Path $Root ("registry-{0}.mock" -f $Index)
    Assert-TypezeroProviderFixturePlainFile -Path $path -AllowMissing
    if ($null -eq $NewData) {
        if ([IO.File]::Exists($path)) { [IO.File]::Delete($path) }
    } else {
        if ([string]$NewData -cnotmatch '\ADWORD:[01]\z') {
            throw 'REFUSED: Unsupported new mock data.'
        }
        # Write a new inode and replace the directory entry, rather than
        # truncating an existing file (which could be an external hardlink).
        # This is NOT an atomic compare-and-swap or a power-loss guarantee.
        $pending = Join-Path $Root ('.pending-' + [guid]::NewGuid().ToString('N'))
        $bytes = [Text.UTF8Encoding]::new($false).GetBytes([string]$NewData)
        $stream = [IO.FileStream]::new($pending, [IO.FileMode]::CreateNew,
            [IO.FileAccess]::Write, [IO.FileShare]::None, 4096, [IO.FileOptions]::WriteThrough)
        try { $stream.Write($bytes, 0, $bytes.Length); $stream.Flush($true) }
        finally { $stream.Dispose() }
        [IO.File]::Move($pending, $path, $true)
    }
}

# Independently authenticated anchor: v3 checked DPAPI payload but Windows
# accepted a modified envelope header. Anchor records the exact SHA256 of
# evidence.dpapi inside a second, different-purpose DPAPI-protected document.
# This is NOT an external trust anchor: same-user code can rewrite both files.
function Get-TypezeroProviderFixtureSha256 {
    [CmdletBinding()]
    param([Parameter(Mandatory)][byte[]]$Bytes)
    return [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($Bytes))
}

function Get-TypezeroProviderFixtureAnchor {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][ValidatePattern('\A[a-f0-9]{32}\z')][string]$TransactionId,
        [Parameter(Mandatory)][byte[]]$EvidenceBytes
    )
    $anchorPath = Join-Path $Root 'envelope.anchor.dpapi'
    Assert-TypezeroProviderFixturePlainFile -Path $anchorPath
    $anchorBytes = [IO.File]::ReadAllBytes($anchorPath)
    if ($anchorBytes.Length -lt 16 -or $anchorBytes.Length -gt 8192) {
        throw 'REFUSED: Invalid anchor envelope size.'
    }
    $utf8 = [Text.UTF8Encoding]::new($false, $true)
    $entropy = $utf8.GetBytes('Typezero.ProviderFixtureEnvelopeAnchor.57F23100604')
    try {
        $plain = [Security.Cryptography.ProtectedData]::Unprotect(
            $anchorBytes, $entropy, [Security.Cryptography.DataProtectionScope]::CurrentUser)
    } catch { throw 'REFUSED: Anchor authentication failed.' }
    if ($plain.Length -lt 16 -or $plain.Length -gt 4096) {
        throw 'REFUSED: Invalid anchor document size.'
    }
    try {
        # Check duplicate JSON keys before ConvertFrom-Json overwrites them.
        $json = [Text.Json.JsonDocument]::Parse($utf8.GetString($plain))
        try {
            if ($json.RootElement.ValueKind -ne [Text.Json.JsonValueKind]::Object) {
                throw 'Anchor must be an object.'
            }
            $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
            foreach ($property in $json.RootElement.EnumerateObject()) {
                if (-not $seen.Add($property.Name)) {
                    throw 'Duplicate anchor property.'
                }
            }
        } finally { $json.Dispose() }
        $anchor = ConvertFrom-Json -InputObject $utf8.GetString($plain) -AsHashtable -ErrorAction Stop
    } catch { throw 'REFUSED: Malformed or ambiguous anchor JSON.' }
    if ($null -eq $anchor -or $anchor.Count -ne 8 -or
        $anchor.Version -ne 1 -or
        $anchor.Kind -cne 'TypezeroProviderFixtureEnvelopeAnchor' -or
        $anchor.FixtureOnly -ne $true -or
        $anchor.RecoveryAuthorized -ne $false -or
        $anchor.TransactionId -cne $TransactionId -or
        -not [string]::Equals([string]$anchor.Root, $Root, [StringComparison]::OrdinalIgnoreCase) -or
        [string]$anchor.Nonce -cnotmatch '\A[a-f0-9]{32}\z' -or
        [string]$anchor.EvidenceSHA256 -cnotmatch '\A[A-F0-9]{64}\z') {
        throw 'REFUSED: Anchor identity or policy mismatch.'
    }
    $observedHash = Get-TypezeroProviderFixtureSha256 -Bytes $EvidenceBytes
    $a = [Convert]::FromHexString([string]$anchor.EvidenceSHA256)
    $b = [Convert]::FromHexString($observedHash)
    if (-not [Security.Cryptography.CryptographicOperations]::FixedTimeEquals($a, $b)) {
        throw 'REFUSED: Exact evidence envelope hash mismatch.'
    }
    return $anchor
}

function Get-TypezeroProviderFixtureEvidence {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$TestRoot,
        [Parameter(Mandatory)][ValidatePattern('\A[a-f0-9]{32}\z')][string]$TransactionId
    )
    $root = Assert-TypezeroProviderFixtureRoot -TestRoot $TestRoot
    $path = Join-Path $root 'evidence.dpapi'
    Assert-TypezeroProviderFixturePlainFile -Path $path
    $cipher = [IO.File]::ReadAllBytes($path)
    if ($cipher.Length -lt 16 -or $cipher.Length -gt 32768) {
        throw 'REFUSED: Invalid sealed evidence size.'
    }
    $anchor = Get-TypezeroProviderFixtureAnchor -Root $root `
        -TransactionId $TransactionId -EvidenceBytes $cipher
    $utf8 = [Text.UTF8Encoding]::new($false, $true)
    $entropy = $utf8.GetBytes('Typezero.ProviderFixtureEvidence.57F23100603')
    try {
        $plain = [Security.Cryptography.ProtectedData]::Unprotect(
            $cipher, $entropy, [Security.Cryptography.DataProtectionScope]::CurrentUser)
    } catch { throw 'REFUSED: Sealed evidence authentication failed.' }
    if ($plain.Length -lt 16 -or $plain.Length -gt 8192) {
        throw 'REFUSED: Invalid evidence document size.'
    }
    try {
        $manifest = ConvertFrom-Json -InputObject $utf8.GetString($plain) -AsHashtable -ErrorAction Stop
    } catch { throw 'REFUSED: Malformed sealed evidence document.' }
    if ($null -eq $manifest -or $manifest.Count -ne 8 -or
        $manifest.Version -ne 1 -or
        $manifest.Kind -cne 'TypezeroProviderFixtureEvidence' -or
        $manifest.FixtureOnly -ne $true -or
        $manifest.RecoveryAuthorized -ne $false -or
        $manifest.TransactionId -cne $TransactionId -or
        -not [string]::Equals([string]$manifest.Root, $root, [StringComparison]::OrdinalIgnoreCase) -or
        [string]$manifest.Nonce -cnotmatch '\A[a-f0-9]{32}\z' -or
        $manifest.Nonce -cne $anchor.Nonce -or
        @($manifest.Slots).Count -ne 5) {
        throw 'REFUSED: Evidence identity or policy mismatch.'
    }
    $expected = Get-TypezeroProviderFixtureBlueprint
    for ($i=0; $i -lt 5; $i++) {
        $got = $manifest.Slots[$i]
        $want = $expected[$i]
        if ($null -eq $got -or $got.Count -ne 3 -or $got.Name -cne $want.Name) {
            throw "REFUSED: Invalid sealed slot at $i"
        }
        foreach ($side in @('Before','After')) {
            $a = $got[$side]
            $b = $want[$side]
            if ($null -eq $a -or $a.Count -ne 3 -or
                $a.Exists -ne $b.Exists -or
                $a.Type -cne $b.Type -or
                $a.Value -cne $b.Value) {
                throw "REFUSED: Invalid sealed $side state at $i"
            }
        }
    }
    return [pscustomobject]@{
        Root=$root; TransactionId=$TransactionId; Manifest=$manifest;
        SealedEvidenceVerified=$true; EnvelopeExactHashVerified=$true
        RestorationCertified=$false; ReceiptPresent=$false
        FixtureOnly=$true; RecoveryAuthorized=$false
    }
}

function New-TypezeroProviderFixtureEvidence {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$TestRoot,
        [Parameter(Mandatory)][ValidatePattern('\A[a-f0-9]{32}\z')][string]$TransactionId
    )
    $root = Assert-TypezeroProviderFixtureRoot -TestRoot $TestRoot
    $path = Join-Path $root 'evidence.dpapi'
    $anchorPath = Join-Path $root 'envelope.anchor.dpapi'
    if ((Test-Path -LiteralPath $path) -or (Test-Path -LiteralPath $anchorPath)) {
        throw 'REFUSED: Evidence or anchor already exists.'
    }
    $slots = Get-TypezeroProviderFixtureBlueprint
    for ($i=0; $i -lt 5; $i++) {
        $current = Read-TypezeroProviderFixtureSlot -Root $root -Index $i
        $before = Get-TypezeroProviderMockData -Value $slots[$i].Before
        if ($current -cne $before) {
            throw "REFUSED: Prepare found non-original mock value $i"
        }
    }
    $manifest = [ordered]@{
        Version=1; Kind='TypezeroProviderFixtureEvidence'; FixtureOnly=$true
        RecoveryAuthorized=$false; TransactionId=$TransactionId; Root=$root
        Nonce=([guid]::NewGuid().ToString('N')); Slots=$slots
    }
    $utf8 = [Text.UTF8Encoding]::new($false, $true)
    $plain = $utf8.GetBytes(($manifest | ConvertTo-Json -Depth 12 -Compress))
    if ($plain.Length -gt 8192) { throw 'REFUSED: Evidence exceeds policy limit.' }
    $entropy = $utf8.GetBytes('Typezero.ProviderFixtureEvidence.57F23100603')
    $cipher = [Security.Cryptography.ProtectedData]::Protect(
        $plain, $entropy, [Security.Cryptography.DataProtectionScope]::CurrentUser)
    $anchor = [ordered]@{
        Version=1; Kind='TypezeroProviderFixtureEnvelopeAnchor'; FixtureOnly=$true
        RecoveryAuthorized=$false; TransactionId=$TransactionId; Root=$root
        Nonce=$manifest.Nonce
        EvidenceSHA256=(Get-TypezeroProviderFixtureSha256 -Bytes $cipher)
    }
    $anchorPlain = $utf8.GetBytes(($anchor | ConvertTo-Json -Depth 5 -Compress))
    $anchorEntropy = $utf8.GetBytes('Typezero.ProviderFixtureEnvelopeAnchor.57F23100604')
    $anchorCipher = [Security.Cryptography.ProtectedData]::Protect(
        $anchorPlain, $anchorEntropy, [Security.Cryptography.DataProtectionScope]::CurrentUser)
    # Non-atomic pair publication: missing either file MUST fail closed. A
    # crash mid-preparation requires manual cleanup of this mock-only fixture.
    $stream = [IO.FileStream]::new($path, [IO.FileMode]::CreateNew,
        [IO.FileAccess]::Write, [IO.FileShare]::None, 4096, [IO.FileOptions]::WriteThrough)
    try { $stream.Write($cipher,0,$cipher.Length); $stream.Flush($true) }
    finally { $stream.Dispose() }
    $anchorStream = [IO.FileStream]::new($anchorPath, [IO.FileMode]::CreateNew,
        [IO.FileAccess]::Write, [IO.FileShare]::None, 4096, [IO.FileOptions]::WriteThrough)
    try { $anchorStream.Write($anchorCipher,0,$anchorCipher.Length); $anchorStream.Flush($true) }
    finally { $anchorStream.Dispose() }
    return (Get-TypezeroProviderFixtureEvidence -TestRoot $root -TransactionId $TransactionId)
}

function Get-TypezeroProviderFixtureObservedState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$TestRoot,
        [Parameter(Mandatory)][ValidatePattern('\A[a-f0-9]{32}\z')][string]$TransactionId
    )
    $e = Get-TypezeroProviderFixtureEvidence -TestRoot $TestRoot -TransactionId $TransactionId
    $beforeCount = 0; $afterCount = 0; $foreignCount = 0
    for ($i=0; $i -lt 5; $i++) {
        $slot = $e.Manifest.Slots[$i]
        $before = Get-TypezeroProviderMockData -Value $slot.Before
        $after = Get-TypezeroProviderMockData -Value $slot.After
        $current = Read-TypezeroProviderFixtureSlot -Root $e.Root -Index $i
        if ($current -ceq $before) { $beforeCount++ }
        elseif ($current -ceq $after) { $afterCount++ }
        else { $foreignCount++ }
    }
    $state = if ($foreignCount) { 'Conflicted' }
        elseif ($beforeCount -eq 5) { 'BeforeObservedNotCertified' }
        elseif ($afterCount -eq 5) { 'TargetObserved' }
        else { 'MixedObserved' }
    return [pscustomobject]@{
        Root=$e.Root; TransactionId=$TransactionId; State=$state
        Before=$beforeCount; After=$afterCount; Foreign=$foreignCount
        SealedEvidenceVerified=$true; EnvelopeExactHashVerified=$true
        RestorationCertified=$false; ReceiptPresent=$false
        FixtureOnly=$true; RecoveryAuthorized=$false
    }
}

function Invoke-TypezeroProviderFixtureApply {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$TestRoot,
        [Parameter(Mandatory)][ValidatePattern('\A[a-f0-9]{32}\z')][string]$TransactionId,
        [ValidateRange(0,5)][int]$SimulatedCrashAfter=0
    )
    $e = Get-TypezeroProviderFixtureEvidence -TestRoot $TestRoot -TransactionId $TransactionId
    $s = Get-TypezeroProviderFixtureObservedState -TestRoot $e.Root -TransactionId $TransactionId
    if ($s.State -cne 'BeforeObservedNotCertified') {
        throw 'CONFLICT: Apply requires all five original mock values.'
    }
    for ($i=0; $i -lt 5; $i++) {
        $slot=$e.Manifest.Slots[$i]
        $before=Get-TypezeroProviderMockData -Value $slot.Before
        $after=Get-TypezeroProviderMockData -Value $slot.After
        if ((Read-TypezeroProviderFixtureSlot -Root $e.Root -Index $i) -cne $before) {
            throw "CONFLICT: Mock value changed before apply at $i"
        }
        Write-TypezeroProviderFixtureSlot -Root $e.Root -Index $i -NewData $after
        if ($SimulatedCrashAfter -eq ($i+1)) { [Environment]::Exit(71) }
    }
    return (Get-TypezeroProviderFixtureObservedState -TestRoot $e.Root -TransactionId $TransactionId)
}

function Invoke-TypezeroProviderFixtureRecover {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$TestRoot,
        [Parameter(Mandatory)][ValidatePattern('\A[a-f0-9]{32}\z')][string]$TransactionId,
        [ValidateRange(0,5)][int]$SimulatedCrashAfter=0
    )
    $e = Get-TypezeroProviderFixtureEvidence -TestRoot $TestRoot -TransactionId $TransactionId
    $state = Get-TypezeroProviderFixtureObservedState -TestRoot $e.Root -TransactionId $TransactionId
    if ($state.State -ceq 'Conflicted') {
        throw 'CONFLICT: Foreign or malformed mock state; no recovery writes.'
    }
    $restored = 0
    for ($i=4; $i -ge 0; $i--) {
        $slot=$e.Manifest.Slots[$i]
        $before=Get-TypezeroProviderMockData -Value $slot.Before
        $after=Get-TypezeroProviderMockData -Value $slot.After
        $observed=Read-TypezeroProviderFixtureSlot -Root $e.Root -Index $i
        if ($observed -cne $before -and $observed -cne $after) {
            throw "CONFLICT: Mock value changed before recovery at $i"
        }
        if ($observed -ceq $after) {
            Write-TypezeroProviderFixtureSlot -Root $e.Root -Index $i -NewData $before
            $restored++
            if ($SimulatedCrashAfter -eq $restored) { [Environment]::Exit(72) }
        }
    }
    $final = Get-TypezeroProviderFixtureObservedState -TestRoot $e.Root -TransactionId $TransactionId
    if ($final.State -cne 'BeforeObservedNotCertified') {
        throw 'CONFLICT: Mock recovery did not verify original state.'
    }
    return [pscustomobject]@{
        State=$final.State; RestoredCount=$restored; FixtureOnly=$true
        SealedEvidenceVerified=$true; EnvelopeExactHashVerified=$true
        RestorationCertified=$false; ReceiptPresent=$false; RecoveryAuthorized=$false
    }
}

function Get-TypezeroProviderFixtureExternalDecision {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateSet('NotRequested','TargetVerified','AlreadySelected','Unknown','Foreign')][string]$WindowsTheme,
        [Parameter(Mandatory)][ValidateSet('NotRequested','TargetVerified','TimeoutTarget','Unknown','Foreign')][string]$Wallpaper,
        [Parameter(Mandatory)][bool]$ThemeCommitted
    )
    if ($WindowsTheme -in @('Unknown','Foreign') -or
        $Wallpaper -in @('Unknown','Foreign')) { return 'ManualIntervention' }
    if ($Wallpaper -eq 'TimeoutTarget') { return 'ManualVerification' }
    if (-not $ThemeCommitted -and
        ($WindowsTheme -eq 'TargetVerified' -or $Wallpaper -eq 'TargetVerified')) {
        return 'ManualIntervention'
    }
    return 'RecordedOnly'
}
