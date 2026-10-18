# Typezero ThemeEngine — Step 57F.22.03
# Fixture-only theme-switch transaction using the validated semantic bridge.
# Not a production writer. No CLI entry point, no live destination, no history update.
# Prerequisites: dot-source FontWriter, TerminalColorCompat, TerminalUnified,
# and TerminalThemeBridge before invoking these functions.

function Invoke-TypezeroFixtureThemeSwitch {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$TestRoot,
        [Parameter(Mandatory)]
        [ValidatePattern('\A[A-Fa-f0-9]{64}\z')][string]$ExpectedSha256,
        [Parameter(Mandatory)][System.Collections.IDictionary]$Theme,
        [Parameter(Mandatory)][psobject]$FontConfig,
        [ValidateRange(6,36)][double]$InheritedSize = 12,
        [ValidateSet('normal','semi-bold')][string]$InheritedWeight = 'normal',
        [switch]$PreviewMappedFont,
        [switch]$InjectPostReplaceFailure
    )

    # Even a deliberately malicious caller cannot route this through a live path.
    $root = Assert-TypezeroFontRecoveryRoot -TestRoot $TestRoot
    $lock = Open-TypezeroFontRecoveryLock -TestRoot $root
    try {
        $target = Join-Path $root 'settings.json'
        $beforeBytes = Get-TypezeroFontRecoveryBytes -Path $target
        $beforeHash = Get-TypezeroFontRecoveryHash -Bytes $beforeBytes
        if ($beforeHash -ine $ExpectedSha256) {
            throw 'Fixture changed since its expected snapshot.'
        }
        $utf8 = [Text.UTF8Encoding]::new($false, $true)
        $bom = ($beforeBytes.Length -ge 3 -and $beforeBytes[0] -eq 239 -and
            $beforeBytes[1] -eq 187 -and $beforeBytes[2] -eq 191)
        $offset = if ($bom) { 3 } else { 0 }
        $beforeText = $utf8.GetString($beforeBytes, $offset,
            $beforeBytes.Length - $offset)

        # This is the exact semantic bridge used for the 11-theme compatibility gate.
        $candidateText = New-TypezeroTerminalThemeBridgeText `
            -Text $beforeText -Theme $Theme -FontConfig $FontConfig `
            -InheritedSize $InheritedSize -InheritedWeight $InheritedWeight `
            -PreviewMappedFont:$PreviewMappedFont
        $candidateBytes = $utf8.GetBytes($candidateText)
        if ($bom) { $candidateBytes = [byte[]](@(239,187,191) + $candidateBytes) }
        if ($candidateBytes.Length -lt 1 -or $candidateBytes.Length -gt 8388608) {
            throw 'Invalid fixture candidate length.'
        }
        $afterHash = Get-TypezeroFontRecoveryHash -Bytes $candidateBytes
        if ($afterHash -ceq $beforeHash) { throw 'No change to rehearse.' }

        $id = [guid]::NewGuid().ToString('N')
        $folder = Join-Path $root ('txn-' + $id)
        if (Test-Path -LiteralPath $folder) { throw 'Transaction ID collision.' }
        $null = [IO.Directory]::CreateDirectory($folder)
        $backup = Join-Path $folder 'original.bin'
        $stage = Join-Path $folder 'candidate.bin'
        Write-TypezeroFontRecoveryNewFile -Path $backup -Bytes $beforeBytes
        $null = Assert-TypezeroFontRecoveryContent -Path $backup `
            -Sha256 $beforeHash -Length $beforeBytes.Length
        Write-TypezeroFontRecoveryNewFile -Path $stage -Bytes $candidateBytes
        $null = Assert-TypezeroFontRecoveryContent -Path $stage `
            -Sha256 $afterHash -Length $candidateBytes.Length

        # Exact 57F.17 DPAPI manifest schema, so existing recovery can be reused.
        $intent = [ordered]@{
            Version=1; Kind='TypezeroFontRecoveryFixture'; Root=$root
            TransactionId=$id; Mode='Apply'
            BeforeSha256=$beforeHash; AfterSha256=$afterHash
            BeforeLength=$beforeBytes.Length; AfterLength=$candidateBytes.Length
            BackupName='original.bin'; TargetName='settings.json'
        }
        $pending = Join-Path $folder 'manifest.pending'
        Write-TypezeroFontRecoveryNewFile -Path $pending `
            -Bytes (Protect-TypezeroFontRecoveryManifest -Data $intent)
        [IO.File]::Move($pending, (Join-Path $folder 'manifest.dpapi'))
        $manifest = Read-TypezeroFontRecoveryManifest -TestRoot $root -TransactionId $id
        if ($manifest.BeforeSha256 -cne $beforeHash -or
            $manifest.AfterSha256 -cne $afterHash -or $manifest.Mode -cne 'Apply') {
            throw 'Prepared transaction metadata does not match candidate.'
        }
        $null = Assert-TypezeroFontRecoveryRoot -TestRoot $root
        $null = Assert-TypezeroFontRecoveryContent -Path $backup `
            -Sha256 $beforeHash -Length $beforeBytes.Length
        $null = Assert-TypezeroFontRecoveryContent -Path $stage `
            -Sha256 $afterHash -Length $candidateBytes.Length
        $null = Assert-TypezeroFontRecoveryContent -Path $target `
            -Sha256 $beforeHash -Length $beforeBytes.Length
        $displaced = Join-Path $folder 'displaced-apply.bin'
        if ([IO.File]::Exists($displaced)) { throw 'Unexpected displaced evidence.' }

        # Not atomic compare-and-swap. Retain displaced evidence and reject
        # unexpected file contents during verification or later recovery.
        [IO.File]::Replace($stage, $target, $displaced, $false)
        if ($InjectPostReplaceFailure) {
            throw 'INJECTED: Theme rehearsal interrupted after File.Replace.'
        }
        $null = Assert-TypezeroFontRecoveryContent -Path $displaced `
            -Sha256 $beforeHash -Length $beforeBytes.Length
        $null = Assert-TypezeroFontRecoveryContent -Path $target `
            -Sha256 $afterHash -Length $candidateBytes.Length
        [pscustomobject]@{
            ThemeId=[string]$Theme['THEME_ID']
            TransactionId=$id; FixtureRoot=$root
            BeforeHash=$beforeHash; AfterHash=$afterHash
            Verified=$true; FixtureOnly=$true
        }
    }
    finally { $lock.Dispose() }
}
