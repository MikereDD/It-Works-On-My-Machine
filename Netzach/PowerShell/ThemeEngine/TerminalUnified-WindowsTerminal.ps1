# Typezero ThemeEngine / Step 57F.20
# Fixture-only unified font + color transaction.
# Depends on FontWriter-WindowsTerminal.ps1 and TerminalColorCompat-WindowsTerminal.ps1.
# Deliberately no production destination, no live-write switch, no CLI registration.
# Uses 57F.17 prepared DPAPI metadata and recovery of original bytes.

function Get-TypezeroUnifiedOwnedEntry {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Text,
        [Parameter(Mandatory)][ValidateSet('schemes','themes')][string]$Collection,
        [Parameter(Mandatory)][string]$Name
    )
    $options = [Text.Json.JsonDocumentOptions]::new()
    $options.AllowTrailingCommas = $true
    $options.CommentHandling = [Text.Json.JsonCommentHandling]::Skip
    $document = [Text.Json.JsonDocument]::Parse($Text, $options)
    try {
        $results = @(
            foreach ($entry in $document.RootElement.GetProperty($Collection).EnumerateArray()) {
                if ($entry.GetProperty('name').GetString() -ceq $Name) {
                    $entry.GetRawText()
                }
            }
        )
        if ($results.Count -ne 1) { throw "Missing or duplicate managed entry: $Collection / $Name" }
        return [string]$results[0]
    }
    finally { $document.Dispose() }
}

function New-TypezeroUnifiedApplyText {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Text,
        [Parameter(Mandatory)]
        [ValidatePattern('\ATypezero [A-Za-z0-9][A-Za-z0-9 ._\x27-]*\z')]
        [string]$SchemeName,
        [Parameter(Mandatory)]
        [ValidatePattern('\A[A-Za-z0-9][A-Za-z0-9 ._+-]{0,99}\z')]
        [string]$Family,
        [ValidateRange(6,36)][double]$Size = 12,
        [ValidateSet('normal','semi-bold')][string]$Weight = 'normal'
    )
    $initialScheme = (Get-TypezeroTerminalColorSchemeTextSpan -Text $Text).Value
    if ($initialScheme -cnotmatch '\ATypezero ') {
        throw 'Current PowerShell scheme is not Typezero-managed.'
    }
    if ($initialScheme -ceq $SchemeName) {
        throw 'Unified rehearsal requires a different target scheme.'
    }
    $schemeRaw = Get-TypezeroUnifiedOwnedEntry -Text $Text -Collection schemes -Name $SchemeName
    $scheme = ConvertFrom-Json -InputObject $schemeRaw -Depth 100
    if ([string]$scheme.background -cnotmatch '\A#[0-9A-Fa-f]{6}\z') {
        throw 'Target palette has an invalid background.'
    }
    $themeName = 'Typezero ThemeEngine'
    $themeRaw = Get-TypezeroUnifiedOwnedEntry -Text $Text -Collection themes -Name $themeName
    $theme = ConvertFrom-Json -InputObject $themeRaw -Depth 100
    if ($null -eq $theme.tabRow.background -or
        $null -eq $theme.tabRow.unfocusedBackground -or
        $null -eq $theme.tab.unfocusedBackground) {
        throw 'Unsupported managed application theme layout.'
    }
    $theme.tabRow.background = $scheme.background
    $theme.tabRow.unfocusedBackground = $scheme.background
    $theme.tab.unfocusedBackground = $scheme.background
    $newThemeRaw = ConvertTo-Json -InputObject $theme -Depth 100 -Compress
    if ($themeRaw -ceq $newThemeRaw) { throw 'Application theme replacement is unchanged.' }

    $withFont = New-TypezeroMappedFontOverrideText -Text $Text `
        -Family $Family -Size $Size -Weight $Weight
    $withScheme = Set-TypezeroTerminalProfileColorSchemeText `
        -Text $withFont -SchemeName $SchemeName
    $combined = Set-TypezeroTerminalOwnedElementText `
        -Text $withScheme -Collection themes -Name $themeName -Replacement $newThemeRaw

    $font = Get-TypezeroFontProfileTextSnapshot -Text $combined
    if (-not $font.HasFont -or $font.Face -cne $Family -or
        $font.Size -ne $Size -or $font.Weight -cne $Weight -or
        -not $combined.Contains('/* TYPEZERO_FONT_V2 */') -or
        (Get-TypezeroTerminalColorSchemeTextSpan -Text $combined).Value -cne $SchemeName -or
        (Get-TypezeroUnifiedOwnedEntry -Text $combined -Collection schemes -Name $SchemeName) -cne $schemeRaw -or
        (Get-TypezeroUnifiedOwnedEntry -Text $combined -Collection themes -Name $themeName) -cne $newThemeRaw) {
        throw 'Unified font/color verification failed.'
    }
    return $combined
}

function Invoke-TypezeroUnifiedFixtureChange {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateSet('Apply','Restore')][string]$Mode,
        [Parameter(Mandatory)][string]$TestRoot,
        [Parameter(Mandatory)]
        [ValidatePattern('\A[A-Fa-f0-9]{64}\z')][string]$ExpectedSha256,
        [ValidatePattern('\ATypezero [A-Za-z0-9][A-Za-z0-9 ._\x27-]*\z')]
        [string]$SchemeName,
        [ValidatePattern('\A[A-Za-z0-9][A-Za-z0-9 ._+-]{0,99}\z')]
        [string]$Family,
        [ValidateRange(6,36)][double]$Size = 12,
        [ValidateSet('normal','semi-bold')][string]$Weight = 'normal',
        [ValidatePattern('\A[a-f0-9]{32}\z')]
        [string]$ApplyTransactionId,
        [switch]$ForcePostReplaceFailure
    )
    $modeName = if ($Mode -ieq 'Apply') { 'Apply' } else { 'Restore' }
    if ($modeName -ceq 'Apply') {
        if (-not $SchemeName -or -not $Family -or $ApplyTransactionId) {
            throw 'Apply requires scheme and family, without prior transaction ID.'
        }
    }
    elseif (-not $ApplyTransactionId -or $SchemeName -or $Family) {
        throw 'Restore requires only the original Apply transaction ID.'
    }

    # This root validation is the non-negotiable safety boundary: direct child
    # of TEMP, private current-user ACL, local NTFS, no redirects/hardlinks.
    $root = Assert-TypezeroFontRecoveryRoot -TestRoot $TestRoot
    $lock = Open-TypezeroFontRecoveryLock -TestRoot $root
    try {
        $target = Join-Path $root 'settings.json'
        $beforeBytes = Get-TypezeroFontRecoveryBytes -Path $target
        $beforeHash = Get-TypezeroFontRecoveryHash -Bytes $beforeBytes
        if ($beforeHash -ine $ExpectedSha256) {
            throw 'Settings changed since the expected snapshot.'
        }
        $utf8 = [Text.UTF8Encoding]::new($false, $true)
        $hasBom = ($beforeBytes.Length -ge 3 -and $beforeBytes[0] -eq 239 -and
            $beforeBytes[1] -eq 187 -and $beforeBytes[2] -eq 191)
        $offset = if ($hasBom) { 3 } else { 0 }
        $text = $utf8.GetString($beforeBytes, $offset, $beforeBytes.Length - $offset)

        if ($modeName -ceq 'Apply') {
            $candidateText = New-TypezeroUnifiedApplyText -Text $text `
                -SchemeName $SchemeName -Family $Family -Size $Size -Weight $Weight
            $candidateBytes = $utf8.GetBytes($candidateText)
            if ($hasBom) { $candidateBytes = [byte[]](@(239,187,191) + $candidateBytes) }
        }
        else {
            $originalManifest = Read-TypezeroFontRecoveryManifest `
                -TestRoot $root -TransactionId $ApplyTransactionId
            if ($originalManifest.Mode -cne 'Apply' -or
                $originalManifest.AfterSha256 -cne $beforeHash -or
                $originalManifest.BeforeSha256 -ceq $beforeHash) {
                throw 'Apply transaction does not match current settings.'
            }
            $font = Get-TypezeroFontProfileTextSnapshot -Text $text
            if (-not $font.HasFont -or -not $text.Contains('/* TYPEZERO_FONT_V2 */')) {
                throw 'Managed font is missing from the expected applied state.'
            }
            $originalBackup = Join-Path (Join-Path $root ('txn-' + $ApplyTransactionId)) 'original.bin'
            $candidateBytes = Assert-TypezeroFontRecoveryContent -Path $originalBackup `
                -Sha256 $originalManifest.BeforeSha256 -Length $originalManifest.BeforeLength
            $originalOffset = if ($candidateBytes.Length -ge 3 -and
                $candidateBytes[0] -eq 239 -and $candidateBytes[1] -eq 187 -and
                $candidateBytes[2] -eq 191) { 3 } else { 0 }
            $plainOriginal = $utf8.GetString($candidateBytes, $originalOffset,
                $candidateBytes.Length - $originalOffset)
            if ((Get-TypezeroFontProfileTextSnapshot -Text $plainOriginal).HasFont -or
                $plainOriginal.Contains('/* TYPEZERO_FONT_V2 */')) {
                throw 'Original recovery evidence already contains an override.'
            }
        }

        if ($candidateBytes.Length -eq 0 -or $candidateBytes.Length -gt 8388608) {
            throw 'Invalid unified candidate size.'
        }
        $afterHash = Get-TypezeroFontRecoveryHash -Bytes $candidateBytes
        if ($beforeHash -ceq $afterHash) { throw 'Unified candidate is unchanged.' }

        $id = [guid]::NewGuid().ToString('N')
        $folder = Join-Path $root ('txn-' + $id)
        if (Test-Path -LiteralPath $folder) { throw 'Transaction ID collision.' }
        $null = [IO.Directory]::CreateDirectory($folder)
        $backup = Join-Path $folder 'original.bin'
        $stage = Join-Path $folder 'candidate.bin'
        Write-TypezeroFontRecoveryNewFile -Path $backup -Bytes $beforeBytes
        $null = Assert-TypezeroFontRecoveryContent -Path $backup -Sha256 $beforeHash -Length $beforeBytes.Length
        Write-TypezeroFontRecoveryNewFile -Path $stage -Bytes $candidateBytes
        $null = Assert-TypezeroFontRecoveryContent -Path $stage -Sha256 $afterHash -Length $candidateBytes.Length

        # Metadata matches the established 57F.17 schema so its tested Repair
        # function can recover either a combined Apply or combined Restore.
        $manifest = [ordered]@{
            Version=1; Kind='TypezeroFontRecoveryFixture'; Root=$root
            TransactionId=$id; Mode=$modeName
            BeforeSha256=$beforeHash; AfterSha256=$afterHash
            BeforeLength=$beforeBytes.Length; AfterLength=$candidateBytes.Length
            BackupName='original.bin'; TargetName='settings.json'
        }
        $pending = Join-Path $folder 'manifest.pending'
        Write-TypezeroFontRecoveryNewFile -Path $pending `
            -Bytes (Protect-TypezeroFontRecoveryManifest -Data $manifest)
        [IO.File]::Move($pending, (Join-Path $folder 'manifest.dpapi'))
        $null = Read-TypezeroFontRecoveryManifest -TestRoot $root -TransactionId $id

        $null = Assert-TypezeroFontRecoveryRoot -TestRoot $root
        $null = Assert-TypezeroFontRecoveryContent -Path $backup -Sha256 $beforeHash -Length $beforeBytes.Length
        $null = Assert-TypezeroFontRecoveryContent -Path $stage -Sha256 $afterHash -Length $candidateBytes.Length
        $null = Assert-TypezeroFontRecoveryContent -Path $target -Sha256 $beforeHash -Length $beforeBytes.Length
        $displaced = Join-Path $folder 'displaced-apply.bin'
        if (Test-Path -LiteralPath $displaced) { throw 'Displacement evidence already exists.' }
        [IO.File]::Replace($stage, $target, $displaced, $false)

        if ($ForcePostReplaceFailure) {
            throw 'INJECTED: combined transaction interrupted after File.Replace.'
        }
        $null = Assert-TypezeroFontRecoveryContent -Path $displaced -Sha256 $beforeHash -Length $beforeBytes.Length
        $null = Assert-TypezeroFontRecoveryContent -Path $target -Sha256 $afterHash -Length $candidateBytes.Length
        [pscustomobject]@{
            Mode=$modeName; TransactionId=$id; FixtureRoot=$root
            BeforeHash=$beforeHash; AfterHash=$afterHash
            BackupPath=$backup; Verified=$true; FixtureOnly=$true
        }
    }
    finally { $lock.Dispose() }
}
