
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

git -C $repo merge-base --is-ancestor '727d1c2' HEAD

Assert-Test (
    $LASTEXITCODE -eq 0
) 'Required recovery assessment baseline'

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
    'TerminalRecoveryGrantV2-WindowsTerminal.ps1'
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

$synthetic = [ordered]@{
    theme = 'Typezero ThemeEngine'
    schemes = @(
        @{
            name = 'Typezero Obsidian Silver'
            background = '#000000'
        }
    )
    themes = @(
        @{
            name = 'Typezero ThemeEngine'
            window = @{ applicationTheme = 'dark' }
            tab = @{ background = 'terminalBackground' }
            tabRow = @{ background = '#000000' }
        }
    )
    profiles = @{
        defaults = @{}
        list = @(
            @{
                guid = '{574e775e-4f2a-5b96-ac1e-a2962a402336}'
                name = 'PowerShell'
                colorScheme = 'Typezero Obsidian Silver'
            }
        )
    }
}

[IO.File]::WriteAllText(
    $paths.Settings,
    ($synthetic | ConvertTo-Json -Depth 20),
    $utf8
)

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

[byte[]]$evidenceKey = [byte[]]::new(32)
[byte[]]$approvalKey = [byte[]]::new(32)

[Security.Cryptography.RandomNumberGenerator]::Fill($evidenceKey)
[Security.Cryptography.RandomNumberGenerator]::Fill($approvalKey)

while ([Security.Cryptography.CryptographicOperations]::
    FixedTimeEquals($evidenceKey, $approvalKey)) {
    [Security.Cryptography.RandomNumberGenerator]::Fill($approvalKey)
}

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

function New-TestGrant {
    param([hashtable]$Overrides = @{})

    $fields = [ordered]@{}

    foreach ($name in $baseGrant.Keys) {
        $fields[$name] = $baseGrant[$name]
    }

    foreach ($name in $Overrides.Keys) {
        $fields[$name] = $Overrides[$name]
    }

    [byte[]]$payload = Get-TypezeroOfflineTerminalV2GrantPayload `
        -Fields $fields

    [byte[]]$mac = [Security.Cryptography.HMACSHA256]::
        HashData($approvalKey, $payload)

    [pscustomobject]@{
        Json = ($fields | ConvertTo-Json -Depth 10 -Compress)
        Mac = $mac
    }
}

function Assert-Grant {
    param(
        [string]$Label,
        [string]$ExpectedDecision,
        [string]$Json,
        [byte[]]$Mac,
        [byte[]]$VerificationApprovalKey = $approvalKey,
        [byte[]]$VerificationEvidenceKey = $evidenceKey
    )

    $before = Get-Snapshot

    $result = Get-TypezeroOfflineTerminalV2GrantReview `
        -TestRoot $root `
        -BackupDirectory $folder `
        -GrantJson $Json `
        -AuthorizationMac $Mac `
        -ApprovalKey $VerificationApprovalKey `
        -EvidenceKey $VerificationEvidenceKey

    $after = Get-Snapshot

    Assert-Test (
        $result.Decision -ceq $ExpectedDecision
    ) "$Label expected $ExpectedDecision; got $($result.Decision): $($result.Reason)"

    Assert-Test (
        $result.ReadOnly -eq $true -and
        $result.FixtureOnly -eq $true -and
        $result.GrantConsumed -eq $false -and
        $result.ReplayProtectionEstablished -eq $false -and
        $result.RecoveryAllowed -eq $false -and
        $result.RecoveryAuthorized -eq $false -and
        $result.LiveActivationAuthorized -eq $false -and
        $result.OperationPhase -ceq 'UNKNOWN'
    ) "$Label must remain unauthorized"

    Assert-Test (
        $result.ValidForReview -eq
        ($ExpectedDecision -ceq 'GRANT_VALID_FOR_REVIEW')
    ) "$Label validity flag mismatch"

    Assert-Test ($before -ceq $after) `
        "$Label modified fixture evidence"

    $script:checks++
    Write-Host "PASS [$script:checks] $Label"
}

try {
    Write-Host "`n=== CREATE AUTHENTICATED FIXTURE ==="

    $applied = Invoke-TypezeroOfflineTerminalV2Locked `
        -TestRoot $root `
        -Theme $theme `
        -FontFace 'JetBrainsMono Nerd Font' `
        -FontSize 13 `
        -FontWeight normal `
        -Execute -Confirm:$false

    Assert-Test ($applied.Status -ceq 'VERIFIED') `
        'Fixture transaction must verify'

    $folder = $applied.BackupDirectory

    $sealed = New-TypezeroOfflineTerminalV2EvidenceSeal `
        -TestRoot $root `
        -BackupDirectory $folder `
        -IndependentKey $evidenceKey `
        -Execute -Confirm:$false

    Assert-Test ($sealed.Status -ceq 'SEALED') `
        'Fixture evidence must seal'

    $context = Get-TypezeroOfflineTerminalV2SealContext `
        -TestRoot $root -BackupDirectory $folder

    $assessment = Get-TypezeroOfflineTerminalV2RecoveryAssessment `
        -TestRoot $root -BackupDirectory $folder `
        -IndependentKey $evidenceKey

    Assert-Test (
        $assessment.Decision -ceq 'ELIGIBLE_FOR_REVIEW' -and
        $assessment.EvidenceStatus -ceq 'AUTHENTICATED'
    ) 'Sealed fixture must be eligible for review'

    $issued = [datetime]::UtcNow.AddSeconds(-5)
    $expires = $issued.AddMinutes(10)

    $dateFormat = "yyyy-MM-ddTHH:mm:ss.fffffff'Z'"
    $culture = [Globalization.CultureInfo]::InvariantCulture

    $baseGrant = [ordered]@{
        Version = 2
        GrantId = [guid]::NewGuid().ToString('N')
        Operation = 'RESTORE'
        FixtureRoot = $paths.Root
        BackupDirectory = $folder
        ReceiptSha256 = (
            Get-FileHash $context.Receipt -Algorithm SHA256
        ).Hash
        BackupSha256 = (
            Get-FileHash $context.Backup -Algorithm SHA256
        ).Hash
        SealSha256 = (
            Get-FileHash $context.Seal -Algorithm SHA256
        ).Hash
        ExpectedSettingsSha256 = (
            Get-FileHash $paths.Settings -Algorithm SHA256
        ).Hash
        IssuedUtc = $issued.ToString($dateFormat, $culture)
        ExpiresUtc = $expires.ToString($dateFormat, $culture)
    }

    $valid = New-TestGrant

    Write-Host "`n=== SIGNED GRANT VALIDATION ==="

    Assert-Grant 'Valid grant eligible for review' `
        'GRANT_VALID_FOR_REVIEW' $valid.Json $valid.Mac

    [byte[]]$wrongApproval = [byte[]]::new(32)
    [Security.Cryptography.RandomNumberGenerator]::Fill($wrongApproval)

    Assert-Grant 'Incorrect approval key refused' `
        'GRANT_UNAUTHENTICATED' $valid.Json $valid.Mac `
        -VerificationApprovalKey $wrongApproval

    [array]::Clear($wrongApproval, 0, $wrongApproval.Length)

    [byte[]]$badMac = [byte[]]$valid.Mac.Clone()
    $badMac[0] = $badMac[0] -bxor 1

    Assert-Grant 'Modified approval MAC refused' `
        'GRANT_UNAUTHENTICATED' $valid.Json $badMac

    [array]::Clear($badMac, 0, $badMac.Length)

    [byte[]]$wrongEvidence = [byte[]]::new(32)
    [Security.Cryptography.RandomNumberGenerator]::Fill($wrongEvidence)

    Assert-Grant 'Incorrect evidence key refused' `
        'GRANT_STATE_CONFLICT' $valid.Json $valid.Mac `
        -VerificationEvidenceKey $wrongEvidence

    [array]::Clear($wrongEvidence, 0, $wrongEvidence.Length)

    Assert-Grant 'Identical approval and evidence keys refused' `
        'GRANT_REFUSED' $valid.Json $valid.Mac `
        -VerificationEvidenceKey $approvalKey

    Write-Host "`n=== TIME AND IDENTITY REFUSALS ==="

    $expired = New-TestGrant @{
        IssuedUtc = ([datetime]::UtcNow.AddMinutes(-20)).
            ToString($dateFormat, $culture)
        ExpiresUtc = ([datetime]::UtcNow.AddMinutes(-10)).
            ToString($dateFormat, $culture)
    }

    Assert-Grant 'Expired grant refused' `
        'GRANT_EXPIRED_OR_INVALID_TIME' $expired.Json $expired.Mac

    $future = New-TestGrant @{
        IssuedUtc = ([datetime]::UtcNow.AddMinutes(2)).
            ToString($dateFormat, $culture)
        ExpiresUtc = ([datetime]::UtcNow.AddMinutes(12)).
            ToString($dateFormat, $culture)
    }

    Assert-Grant 'Future-issued grant refused' `
        'GRANT_EXPIRED_OR_INVALID_TIME' $future.Json $future.Mac

    $wrongOperation = New-TestGrant @{ Operation = 'APPLY' }

    Assert-Grant 'Incorrect operation refused' `
        'GRANT_REFUSED' $wrongOperation.Json $wrongOperation.Mac

    $wrongFixture = New-TestGrant @{
        FixtureRoot = $paths.Root + '-different'
    }

    Assert-Grant 'Incorrect fixture identity refused' `
        'GRANT_REFUSED' $wrongFixture.Json $wrongFixture.Mac

    Write-Host "`n=== EVIDENCE AND JSON REFUSALS ==="

    [byte[]]$originalSettings = [IO.File]::ReadAllBytes(
        $paths.Settings
    )

    try {
        [IO.File]::WriteAllText(
            $paths.Settings, '{"externalChange":true}', $utf8
        )

        Assert-Grant 'Modified current settings refused' `
            'GRANT_STATE_CONFLICT' $valid.Json $valid.Mac
    }
    finally {
        [IO.File]::WriteAllBytes(
            $paths.Settings, $originalSettings
        )
    }

    [byte[]]$originalReceipt = [IO.File]::ReadAllBytes(
        $context.Receipt
    )

    try {
        [IO.File]::WriteAllText(
            $context.Receipt, '{"tampered":true}', $utf8
        )

        Assert-Grant 'Modified receipt refused' `
            'GRANT_STATE_CONFLICT' $valid.Json $valid.Mac
    }
    finally {
        [IO.File]::WriteAllBytes(
            $context.Receipt, $originalReceipt
        )
    }

    $duplicateJson = $valid.Json.Replace(
        '"GrantId":',
        '"GrantId":"00000000000000000000000000000000","GrantId":'
    )

    Assert-Test ($duplicateJson -cne $valid.Json) `
        'Duplicate-field fixture constructed'

    Assert-Grant 'Duplicate JSON property refused' `
        'GRANT_REFUSED' $duplicateJson $valid.Mac


    Write-Host "`n=== ADDITIONAL GRANT REFUSALS ==="

    # 13: Missing required field.
    $missingField = $valid.Json | ConvertFrom-Json
    $missingField.PSObject.Properties.Remove('GrantId')
    $missingJson = $missingField | ConvertTo-Json -Compress -Depth 10

    Assert-Grant 'Missing required field refused' `
        'GRANT_REFUSED' $missingJson $valid.Mac

    # 14: Malformed timestamp with a valid MAC for its payload.
    $badTime = New-TestGrant @{
        IssuedUtc = 'not-a-timestamp'
    }

    Assert-Grant 'Malformed timestamp refused' `
        'GRANT_REFUSED' $badTime.Json $badTime.Mac

    # 15: Modified original backup.
    [byte[]]$savedBackup = [IO.File]::ReadAllBytes($context.Backup)

    try {
        [IO.File]::WriteAllText(
            $context.Backup, '{"tampered":true}', $utf8
        )

        Assert-Grant 'Modified backup refused' `
            'GRANT_STATE_CONFLICT' $valid.Json $valid.Mac
    }
    finally {
        [IO.File]::WriteAllBytes($context.Backup, $savedBackup)
    }

    # 16: Modified evidence seal.
    [byte[]]$savedSeal = [IO.File]::ReadAllBytes($context.Seal)

    try {
        [byte[]]$tamperedSeal = [byte[]]$savedSeal.Clone()
        $tamperedSeal[0] = $tamperedSeal[0] -bxor 1
        [IO.File]::WriteAllBytes($context.Seal, $tamperedSeal)

        Assert-Grant 'Modified seal refused' `
            'GRANT_STATE_CONFLICT' $valid.Json $valid.Mac
    }
    finally {
        [IO.File]::WriteAllBytes($context.Seal, $savedSeal)
    }

    # 17: Invalid approval key length.
    [byte[]]$shortApproval = [byte[]]::new(16)

    Assert-Grant 'Malformed approval key refused' `
        'GRANT_REFUSED' $valid.Json $valid.Mac `
        -VerificationApprovalKey $shortApproval

    # 18: Invalid evidence key length.
    [byte[]]$shortEvidence = [byte[]]::new(16)

    Assert-Grant 'Malformed evidence key refused' `
        'GRANT_REFUSED' $valid.Json $valid.Mac `
        -VerificationEvidenceKey $shortEvidence


    Assert-Test ($checks -eq 18) 'Expected eighteen grant checks'

    Write-Host "`nPASS: 18/18 V2 recovery grant checks."
    Write-Host 'RecoveryAuthorized=False'
    Write-Host 'LiveActivationAuthorized=False'
    Write-Host 'ReplayProtectionEstablished=False'
    Write-Host "Fixture retained: $root"
}
finally {
    [array]::Clear($evidenceKey, 0, $evidenceKey.Length)
    [array]::Clear($approvalKey, 0, $approvalKey.Length)
}
