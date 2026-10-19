
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$engine = Split-Path -Parent $PSScriptRoot
$repo = (Resolve-Path (Join-Path $engine '..\..\..')).Path
$utf8 = [Text.UTF8Encoding]::new($false)

function Assert-Test {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "FAIL: $Message" }
}

Assert-Test (
    (git -C $repo branch --show-current).Trim() -ceq
    'feature/themeengine-font-management'
) 'Development branch required'

Assert-Test (
    (git -C $repo rev-parse HEAD).Trim() -ceq
    (git -C $repo rev-parse '5bc1736').Trim()
) 'Expected development checkpoint'

foreach ($name in @(
    'FontPatch-WindowsTerminal.ps1'
    'TerminalColorPatch-WindowsTerminal.ps1'
    'TerminalCombinedPatch-WindowsTerminal.ps1'
    'TerminalTransaction-WindowsTerminal.ps1'
    'TerminalReplace-WindowsTerminal.ps1'
    'TerminalTransactionV2-WindowsTerminal.ps1'
    'TerminalTransactionV2Lock-WindowsTerminal.ps1'
    'TerminalEvidenceSealV2-WindowsTerminal.ps1'
    'TerminalRecoveryAuthorizationV2-WindowsTerminal.ps1'
)) {
    . (Join-Path $engine $name)
}

$root = Join-Path ([IO.Path]::GetTempPath()) (
    'typezero-terminal-txn-' + [guid]::NewGuid().ToString('N')
)

[IO.Directory]::CreateDirectory($root) | Out-Null
$paths = Get-TypezeroOfflineTerminalV2Paths -TestRoot $root

[IO.Directory]::CreateDirectory(
    [IO.Path]::GetDirectoryName($paths.Settings)
) | Out-Null

$theme = @{
    THEME_NAME = 'Obsidian Silver'
    BG = '#123456'
    TEXT = '#eeeeee'
    CURSOR = '#ffffff'
    SELECTION = '#445566'
}

foreach ($name in @(
    'BLACK','RED','GREEN','YELLOW','BLUE','PURPLE','CYAN','WHITE',
    'BRIGHT_BLACK','BRIGHT_RED','BRIGHT_GREEN','BRIGHT_YELLOW',
    'BRIGHT_BLUE','BRIGHT_PURPLE','BRIGHT_CYAN','BRIGHT_WHITE'
)) {
    $theme["ANSI_$name"] = '#778899'
}

$synthetic = [ordered]@{
    theme = 'Typezero ThemeEngine'
    schemes = @(
        @{ name='Typezero Obsidian Silver'; background='#000000' }
    )
    themes = @(
        @{
            name='Typezero ThemeEngine'
            window=@{ applicationTheme='dark' }
            tab=@{ background='terminalBackground' }
            tabRow=@{ background='#000000' }
        }
    )
    profiles = @{
        defaults = @{}
        list = @(
            @{
                guid='{574e775e-4f2a-5b96-ac1e-a2962a402336}'
                name='PowerShell'
                colorScheme='Typezero Obsidian Silver'
            }
        )
    }
}

[IO.File]::WriteAllText(
    $paths.Settings,
    ($synthetic | ConvertTo-Json -Depth 20),
    $utf8
)

[byte[]]$key = [byte[]]::new(32)
[Security.Cryptography.RandomNumberGenerator]::Fill($key)

$checks = 0

function Get-Snapshot {
    $entries = @(
        Get-ChildItem -LiteralPath $root -Recurse -Force -File |
        Sort-Object FullName |
        ForEach-Object {
            $relative = $_.FullName.Substring($root.Length)
            $hash = (Get-FileHash -LiteralPath $_.FullName `
                -Algorithm SHA256).Hash

            "$relative|$hash|$($_.Length)"
        }
    )
    $entries -join "`n"
}

function Assert-Assessment {
    param(
        [string]$ExpectedDecision,
        [string]$ExpectedEvidence,
        [string]$Label,
        [byte[]]$VerificationKey = $key
    )

    $before = Get-Snapshot

    $result = Get-TypezeroOfflineTerminalV2RecoveryAssessment `
        -TestRoot $root `
        -BackupDirectory $folder `
        -IndependentKey $VerificationKey

    $after = Get-Snapshot

    Assert-Test (
        $result.Decision -ceq $ExpectedDecision
    ) "$Label expected decision $ExpectedDecision"

    Assert-Test (
        $result.EvidenceStatus -ceq $ExpectedEvidence
    ) "$Label expected evidence $ExpectedEvidence"

    Assert-Test (
        $result.ReadOnly -eq $true -and
        $result.FixtureOnly -eq $true -and
        $result.RecoveryAllowed -eq $false -and
        $result.RecoveryAuthorized -eq $false -and
        $result.LiveActivationAuthorized -eq $false -and
        $result.OperationPhase -ceq 'UNKNOWN'
    ) "$Label must remain unauthorized"

    Assert-Test (
        $result.EligibleForAuthorizationReview -eq
        ($ExpectedDecision -ceq 'ELIGIBLE_FOR_REVIEW')
    ) "$Label review eligibility"

    Assert-Test (
        $before -ceq $after
    ) "$Label assessment must not modify evidence"

    $script:checks++
    Write-Host "PASS [$script:checks] $Label"
}

try {
    $applied = Invoke-TypezeroOfflineTerminalV2Locked `
        -TestRoot $root -Theme $theme `
        -FontFace 'JetBrainsMono Nerd Font' `
        -FontSize 13 -FontWeight normal `
        -Execute -Confirm:$false

    Assert-Test (
        $applied.Status -ceq 'VERIFIED'
    ) 'Initial fixture transaction'

    $folder = $applied.BackupDirectory

    $receipt = Join-Path $folder 'receipt.json'
    $backup = Join-Path $folder 'settings-pre-replace.json'
    $seal = Join-Path $folder 'evidence.seal'

    $sealed = New-TypezeroOfflineTerminalV2EvidenceSeal `
        -TestRoot $root -BackupDirectory $folder `
        -IndependentKey $key -Execute -Confirm:$false

    Assert-Test (
        $sealed.Status -ceq 'SEALED'
    ) 'Fixture evidence sealed'

    [byte[]]$originalReceipt = [IO.File]::ReadAllBytes($receipt)
    [byte[]]$originalBackup = [IO.File]::ReadAllBytes($backup)
    [byte[]]$originalSeal = [IO.File]::ReadAllBytes($seal)
    [byte[]]$appliedSettings = [IO.File]::ReadAllBytes($paths.Settings)

    Write-Host "`n=== AUTHENTICATED RECOVERY ASSESSMENT ==="

    Assert-Assessment 'ELIGIBLE_FOR_REVIEW' 'AUTHENTICATED' `
        'Authenticated applied settings eligible for review'

    Assert-Assessment 'UNTRUSTED' 'UNTRUSTED' `
        'Missing independent key refused' -VerificationKey $null

    [byte[]]$wrongKey = [byte[]]::new(32)
    [Security.Cryptography.RandomNumberGenerator]::Fill($wrongKey)

    Assert-Assessment 'EVIDENCE_REFUSED' 'INVALID' `
        'Incorrect independent key refused' -VerificationKey $wrongKey

    [array]::Clear($wrongKey, 0, $wrongKey.Length)

    Write-Host "`n=== EVIDENCE TAMPERING ==="

    [IO.File]::Delete($seal)
    Assert-Assessment 'EVIDENCE_REFUSED' 'INCOMPLETE' `
        'Missing seal refused'
    [IO.File]::WriteAllBytes($seal, $originalSeal)

    try {
        [IO.File]::WriteAllText($receipt, '{"Version":999}', $utf8)
        Assert-Assessment 'EVIDENCE_REFUSED' 'INVALID' `
            'Modified receipt refused'
    }
    finally {
        [IO.File]::WriteAllBytes($receipt, $originalReceipt)
    }

    try {
        [IO.File]::WriteAllText($backup, '{"tampered":true}', $utf8)
        Assert-Assessment 'EVIDENCE_REFUSED' 'INVALID' `
            'Modified backup refused'
    }
    finally {
        [IO.File]::WriteAllBytes($backup, $originalBackup)
    }

    Write-Host "`n=== SETTINGS STATES ==="

    try {
        [IO.File]::WriteAllText(
            $paths.Settings,
            '{"externalChange":true}',
            $utf8
        )
        Assert-Assessment 'SETTINGS_CONFLICT' 'AUTHENTICATED' `
            'External settings conflict refused'

        [IO.File]::WriteAllBytes($paths.Settings, $originalBackup)

        Assert-Assessment 'NO_RECOVERY_NEEDED' 'AUTHENTICATED' `
            'Original settings already present'
    }
    finally {
        [IO.File]::WriteAllBytes($paths.Settings, $appliedSettings)
    }

    Assert-Assessment 'ELIGIBLE_FOR_REVIEW' 'AUTHENTICATED' `
        'Restored fixture evidence remains review eligible'


    Write-Host "`n=== ADDITIONAL REFUSAL TESTS ==="

    # Test 10: Malformed 16-byte authentication key.
    [byte[]]$shortKey = [byte[]]::new(16)
    [Security.Cryptography.RandomNumberGenerator]::Fill($shortKey)

    try {
        Assert-Assessment 'UNTRUSTED' 'UNTRUSTED' `
            'Malformed HMAC key length refused' `
            -VerificationKey $shortKey
    }
    finally {
        [array]::Clear($shortKey, 0, $shortKey.Length)
    }

    # Test 11: Missing transaction receipt.
    try {
        [IO.File]::Delete($receipt)

        Assert-Assessment 'EVIDENCE_REFUSED' 'INCOMPLETE' `
            'Incomplete transaction evidence refused'
    }
    finally {
        [IO.File]::WriteAllBytes($receipt, $originalReceipt)
    }

    # Test 12: Reject a root nested inside the disposable fixture.
    $invalidRoot = Join-Path $root 'not-an-approved-fixture'
    $snapshotBefore = Get-Snapshot
    $refused = $false

    try {
        $null = Get-TypezeroOfflineTerminalV2RecoveryAssessment `
            -TestRoot $invalidRoot `
            -BackupDirectory $folder `
            -IndependentKey $key
    }
    catch {
        $refused = $true
    }

    Assert-Test $refused 'Non-fixture root must be refused'
    Assert-Test (
        (Get-Snapshot) -ceq $snapshotBefore
    ) 'Invalid-root refusal preserves fixture evidence'

    $checks++
    Write-Host "PASS [$checks] Non-fixture root refused without changes"


    Assert-Test ($checks -eq 12) 'Expected twelve assessment checks'

    Write-Host "`nPASS: 12/12 V2 recovery assessment checks."
    Write-Host 'RecoveryAuthorized=False'
    Write-Host 'LiveActivationAuthorized=False'
    Write-Host "Fixture retained: $root"
}
finally {
    [array]::Clear($key, 0, $key.Length)
}
