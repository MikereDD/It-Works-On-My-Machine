
# Typezero ThemeEngine - Recovery Grant V2
# Read-only, fixture-only authorization review.
# A valid grant never authorizes or executes restoration.

Set-StrictMode -Version Latest

function Get-TypezeroOfflineTerminalV2GrantPayload {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Collections.IDictionary]$Fields
    )

    # Fixed field order and domain-separated, length-prefixed encoding.
    # The same encoding must be used by a future independent grant issuer.
    $names = @(
        'GrantId', 'Operation', 'FixtureRoot',
        'BackupDirectory', 'ReceiptSha256',
        'BackupSha256', 'SealSha256',
        'ExpectedSettingsSha256', 'IssuedUtc', 'ExpiresUtc'
    )

    $utf8 = [Text.UTF8Encoding]::new($false, $true)
    $stream = [IO.MemoryStream]::new()
    $writer = [IO.BinaryWriter]::new($stream, $utf8, $true)

    try {
        $values = @('TYPEZERO-V2-RECOVERY-GRANT-1', '2')

        foreach ($name in $names) {
            $values += [string]$Fields[$name]
        }

        foreach ($value in $values) {

            [byte[]]$bytes = $utf8.GetBytes([string]$value)

            # BinaryWriter writes little-endian Int32 length prefixes.
            $writer.Write([int]$bytes.Length)
            $writer.Write($bytes)
        }

        $writer.Flush()
        return ,$stream.ToArray()
    }
    finally {
        $writer.Dispose()
        $stream.Dispose()
    }
}

function Get-TypezeroOfflineTerminalV2GrantReview {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$TestRoot,
        [Parameter(Mandatory)][string]$BackupDirectory,
        [Parameter(Mandatory)][string]$GrantJson,
        [byte[]]$AuthorizationMac,
        [byte[]]$ApprovalKey,
        [byte[]]$EvidenceKey
    )

    foreach ($name in @(
        'Get-TypezeroOfflineTerminalV2Paths',
        'Assert-TypezeroOfflineTerminalV2Folder',
        'Get-TypezeroOfflineTerminalV2RecoveryAssessment',
        'Get-TypezeroOfflineTerminalV2SealContext'
    )) {
        if (-not (Get-Command $name -CommandType Function `
            -ErrorAction SilentlyContinue)) {
            throw "REFUSED: Missing dependency: $name"
        }
    }

    # Validate the fixture before evaluating any grant.
    # Invalid paths must throw, not fall back to live settings.
    $paths = Get-TypezeroOfflineTerminalV2Paths -TestRoot $TestRoot
    $folder = Assert-TypezeroOfflineTerminalV2Folder `
        -Paths $paths -BackupDirectory $BackupDirectory

    $decision = 'GRANT_REFUSED'
    $reason = 'Grant could not be validated.'
    $assessmentDecision = 'NOT_EVALUATED'
    $grantId = $null

    $required = @(
        'GrantId', 'Operation', 'FixtureRoot',
        'BackupDirectory', 'ReceiptSha256',
        'BackupSha256', 'SealSha256',
        'ExpectedSettingsSha256', 'IssuedUtc', 'ExpiresUtc'
    )

    $doc = $null

    try {
        if ($GrantJson.Length -gt 16384) {
            throw 'Grant exceeds size limit.'
        }

        if ($null -eq $ApprovalKey -or $ApprovalKey.Length -ne 32 -or
            $null -eq $EvidenceKey -or $EvidenceKey.Length -ne 32 -or
            $null -eq $AuthorizationMac -or
            $AuthorizationMac.Length -ne 32) {
            throw 'Independent keys and a 32-byte MAC are required.'
        }

        if ([Security.Cryptography.CryptographicOperations]::
            FixedTimeEquals($ApprovalKey, $EvidenceKey)) {
            throw 'Approval and evidence keys must be distinct.'
        }

        $doc = [Text.Json.JsonDocument]::Parse($GrantJson)
        $element = $doc.RootElement

        if ($element.ValueKind -ne [Text.Json.JsonValueKind]::Object) {
            throw 'Grant must be a JSON object.'
        }

        $fields = [ordered]@{ Version = 2 }
        $seen = [Collections.Generic.HashSet[string]]::new(
            [StringComparer]::OrdinalIgnoreCase
        )

        $properties = @($element.EnumerateObject())

        if ($properties.Count -ne 11) {
            throw 'Grant contains an unexpected number of fields.'
        }

        foreach ($property in $properties) {
            if (-not $seen.Add($property.Name)) {
                throw 'Duplicate or ambiguous grant field.'
            }

            if ($property.Name -cne 'Version' -and
                $property.Name -cnotin $required) {
                throw 'Unknown grant field.'
            }

            if ($property.Name -ceq 'Version') {
                if ($property.Value.ValueKind -ne
                    [Text.Json.JsonValueKind]::Number -or
                    $property.Value.GetRawText() -cne '2') {
                    throw 'Unsupported grant version.'
                }
            }
            else {
                if ($property.Value.ValueKind -ne
                    [Text.Json.JsonValueKind]::String) {
                    throw 'Grant fields must be strings.'
                }

                $fields[$property.Name] = $property.Value.GetString()
            }
        }

        foreach ($name in $required) {
            if (-not $seen.Contains($name)) {
                throw "Missing grant field: $name"
            }
        }

        $grantId = $fields['GrantId']

        if ($grantId -cnotmatch '\A[a-f0-9]{32}\z' -or
            $fields['Operation'] -cne 'RESTORE' -or
            $fields['FixtureRoot'] -cne $paths.Root -or
            $fields['BackupDirectory'] -cne $folder) {
            throw 'Grant identity or operation mismatch.'
        }

        foreach ($name in @(
            'ReceiptSha256', 'BackupSha256',
            'SealSha256', 'ExpectedSettingsSha256'
        )) {
            if ($fields[$name] -cnotmatch '\A[A-F0-9]{64}\z') {
                throw "Invalid SHA-256 field: $name"
            }
        }

        $dateFormat = "yyyy-MM-ddTHH:mm:ss.fffffff'Z'"
        $styles = [Globalization.DateTimeStyles]::AssumeUniversal -bor
                  [Globalization.DateTimeStyles]::AdjustToUniversal
        $culture = [Globalization.CultureInfo]::InvariantCulture

        $issued = [datetime]::ParseExact(
            $fields['IssuedUtc'], $dateFormat, $culture, $styles
        )
        $expires = [datetime]::ParseExact(
            $fields['ExpiresUtc'], $dateFormat, $culture, $styles
        )

        $now = [datetime]::UtcNow

        if ($expires -le $issued -or
            ($expires - $issued).TotalMinutes -gt 15 -or
            $now -ge $expires -or
            $issued -gt $now -or
            $issued -lt $now.AddMinutes(-15)) {
            $decision = 'GRANT_EXPIRED_OR_INVALID_TIME'
            throw 'Grant outside permitted validity window.'
        }

        [byte[]]$payload = Get-TypezeroOfflineTerminalV2GrantPayload `
            -Fields $fields

        [byte[]]$expectedMac = [Security.Cryptography.HMACSHA256]::
            HashData($ApprovalKey, $payload)

        if (-not [Security.Cryptography.CryptographicOperations]::
            FixedTimeEquals($AuthorizationMac, $expectedMac)) {
            $decision = 'GRANT_UNAUTHENTICATED'
            throw 'Approval MAC verification failed.'
        }

        $context = Get-TypezeroOfflineTerminalV2SealContext `
            -TestRoot $paths.Root -BackupDirectory $folder

        $files = [ordered]@{
            ReceiptSha256 = $context.Receipt
            BackupSha256 = $context.Backup
            SealSha256 = $context.Seal
            ExpectedSettingsSha256 = $paths.Settings
        }

        foreach ($name in $files.Keys) {
            if (-not [IO.File]::Exists($files[$name])) {
                throw 'Bound evidence file is missing.'
            }

            $hash = (
                Get-FileHash -LiteralPath $files[$name] `
                    -Algorithm SHA256 -ErrorAction Stop
            ).Hash

            if ($hash -cne $fields[$name]) {
                $decision = 'GRANT_STATE_CONFLICT'
                throw "Grant-bound file mismatch: $name"
            }
        }

        $assessment = Get-TypezeroOfflineTerminalV2RecoveryAssessment `
            -TestRoot $paths.Root `
            -BackupDirectory $folder `
            -IndependentKey $EvidenceKey

        $assessmentDecision = $assessment.Decision

        if ($assessment.Decision -cne 'ELIGIBLE_FOR_REVIEW' -or
            $assessment.EvidenceStatus -cne 'AUTHENTICATED') {
            $decision = 'GRANT_STATE_CONFLICT'
            throw 'Authenticated recovery assessment is not eligible.'
        }

        if ($fields['ExpectedSettingsSha256'] -cne
            $assessment.AfterSha256) {
            $decision = 'GRANT_STATE_CONFLICT'
            throw 'Grant settings hash differs from authenticated transaction.'
        }

        $decision = 'GRANT_VALID_FOR_REVIEW'
        $reason = 'Grant and current evidence match; no recovery authorized.'
    }
    catch {
        $reason = $_.Exception.Message
    }
    finally {
        if ($null -ne $doc) {
            $doc.Dispose()
        }
    }

    [pscustomobject]@{
        Version = 2
        Decision = $decision
        Reason = $reason
        GrantId = $grantId
        AssessmentDecision = $assessmentDecision
        ReadOnly = $true
        FixtureOnly = $true
        ValidForReview = ($decision -ceq 'GRANT_VALID_FOR_REVIEW')
        GrantConsumed = $false
        ReplayProtectionEstablished = $false
        RecoveryAllowed = $false
        RecoveryAuthorized = $false
        LiveActivationAuthorized = $false
        OperationPhase = 'UNKNOWN'
        TestRoot = $paths.Root
        BackupDirectory = $folder
    }
}
