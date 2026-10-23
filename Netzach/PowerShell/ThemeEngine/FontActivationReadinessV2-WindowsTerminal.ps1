# Read-only V2 activation readiness. A snapshot is never an execution grant.
# Load TerminalReplace-WindowsTerminal.ps1 and FontWriter-WindowsTerminal.ps1.
# Explicit paths avoid implicit provider lookup or application initialization.

function Assert-TypezeroActivationV2JsonObject {
    param([Parameter(Mandatory)][Text.Json.JsonElement]$Element,
          [string[]]$RequiredFields)

    if ($Element.ValueKind -ne [Text.Json.JsonValueKind]::Object) {
        throw 'V2 activation input must be a JSON object.'
    }
    $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($property in $Element.EnumerateObject()) {
        if (-not $seen.Add($property.Name)) {
            throw 'Duplicate or case-ambiguous JSON property.'
        }
        if ($RequiredFields -and $property.Name -cnotin $RequiredFields) {
            throw "Unexpected V2 activation field: $($property.Name)"
        }
    }
    foreach ($name in $RequiredFields) {
        if (-not $seen.Contains($name)) { throw "Missing V2 activation field: $name" }
        # GetProperty also enforces the exact spelling, not just case-insensitive presence.
        $null = $Element.GetProperty($name)
    }
}

function Assert-TypezeroActivationV2UnambiguousJson {
    param([Parameter(Mandatory)][Text.Json.JsonElement]$Element)
    if ($Element.ValueKind -eq [Text.Json.JsonValueKind]::Object) {
        Assert-TypezeroActivationV2JsonObject -Element $Element
        foreach ($property in $Element.EnumerateObject()) {
            Assert-TypezeroActivationV2UnambiguousJson -Element $property.Value
        }
    }
    elseif ($Element.ValueKind -eq [Text.Json.JsonValueKind]::Array) {
        foreach ($item in $Element.EnumerateArray()) {
            Assert-TypezeroActivationV2UnambiguousJson -Element $item
        }
    }
}

function Read-TypezeroActivationV2Snapshot {
    param([Parameter(Mandatory)][string]$Path,
          [Parameter(Mandatory)][int]$MaximumBytes)

    foreach ($command in @('Assert-TypezeroOfflineReplacePlainPath',
                           'Assert-TypezeroOfflineReplaceSingleLink')) {
        if (-not (Get-Command $command -CommandType Function -ErrorAction SilentlyContinue)) {
            throw "Readiness dependency not loaded: $command"
        }
    }
    $fullPath = [IO.Path]::GetFullPath($Path)
    Assert-TypezeroOfflineReplacePlainPath -Path $fullPath
    # No create mode. Deny content writes/deletion while snapshotting.
    $stream = [IO.FileStream]::new($fullPath, [IO.FileMode]::Open,
        [IO.FileAccess]::Read, [IO.FileShare]::Read)
    try {
        Assert-TypezeroOfflineReplacePlainPath -Path $fullPath
        Assert-TypezeroOfflineReplaceSingleLink -Path $fullPath
        if ($stream.Length -gt $MaximumBytes) { throw 'Activation input exceeds size limit.' }
        $memory = [IO.MemoryStream]::new()
        try {
            $stream.CopyTo($memory)
            [byte[]]$bytes = $memory.ToArray()
        }
        finally { $memory.Dispose() }
        if ($bytes.Length -gt $MaximumBytes) { throw 'Activation input exceeds size limit.' }
        Assert-TypezeroOfflineReplacePlainPath -Path $fullPath
        Assert-TypezeroOfflineReplaceSingleLink -Path $fullPath
        if ($bytes.Length -ge 3 -and $bytes[0] -eq 239 -and
            $bytes[1] -eq 187 -and $bytes[2] -eq 191) {
            throw 'UTF-8 BOM requires separate handling.'
        }
        [pscustomobject]@{
            Path = $fullPath
            Text = [Text.UTF8Encoding]::new($false, $true).GetString($bytes)
            Sha256 = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes))
        }
    }
    finally { $stream.Dispose() }
}

function Get-TypezeroTerminalFontActivationReadinessV2 {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidatePattern('\A[a-z0-9][a-z0-9-]*\z')][string]$ThemeId,
        [Parameter(Mandatory)][string]$ConfigPath,
        [Parameter(Mandatory)][string]$SettingsPath,
        [ValidatePattern('\A[A-Fa-f0-9]{64}\z')][string]$ExpectedConfigSha256,
        [ValidatePattern('\A[A-Fa-f0-9]{64}\z')][string]$ExpectedSettingsSha256
    )

    $config = Read-TypezeroActivationV2Snapshot -Path $ConfigPath -MaximumBytes 1048576
    if ($ExpectedConfigSha256 -and $config.Sha256 -cne $ExpectedConfigSha256.ToUpperInvariant()) {
        throw 'Selected V2 preference is stale: configuration hash changed.'
    }
    $doc = [Text.Json.JsonDocument]::Parse($config.Text)
    try {
        $root = $doc.RootElement
        Assert-TypezeroActivationV2JsonObject -Element $root `
            -RequiredFields @('Version','Enabled','ManualOverride','Mappings')
        if ($root.GetProperty('Version').GetRawText() -cne '2') {
            throw 'Activation readiness requires integer mapping version 2.'
        }
        $enabledValue = $root.GetProperty('Enabled')
        if ($enabledValue.ValueKind -notin @([Text.Json.JsonValueKind]::True,
                                           [Text.Json.JsonValueKind]::False)) {
            throw 'Integration Enabled must be a JSON Boolean.'
        }
        $enabled = $enabledValue.GetBoolean()
        if ($root.GetProperty('ManualOverride').ValueKind -ne [Text.Json.JsonValueKind]::Null) {
            throw 'Manual override is not supported for activation.'
        }
        $mappings = $root.GetProperty('Mappings')
        Assert-TypezeroActivationV2JsonObject -Element $mappings
        $selected = $null
        foreach ($property in $mappings.EnumerateObject()) {
            if ($property.Name -cnotmatch '\A[a-z0-9][a-z0-9-]*\z') {
                throw 'Invalid V2 theme ID.'
            }
            $entry = $property.Value
            Assert-TypezeroActivationV2JsonObject -Element $entry -RequiredFields @('family','size','weight')
            $familyValue = $entry.GetProperty('family')
            $sizeValue = $entry.GetProperty('size')
            $weightValue = $entry.GetProperty('weight')
            if ($familyValue.ValueKind -ne [Text.Json.JsonValueKind]::String -or
                $sizeValue.ValueKind -ne [Text.Json.JsonValueKind]::Number -or
                $weightValue.ValueKind -ne [Text.Json.JsonValueKind]::String) {
                throw 'Invalid V2 typography types.'
            }
            $family = $familyValue.GetString()
            $size = $sizeValue.GetDouble()
            $weight = $weightValue.GetString()
            if ([string]::IsNullOrWhiteSpace($family) -or $family -cne $family.Trim() -or
                $family -match '\p{C}' -or [double]::IsNaN($size) -or [double]::IsInfinity($size) -or
                $size -lt 6 -or $size -gt 36 -or $size -ne [math]::Round($size, 2) -or
                $weight -cnotin @('normal','semi-bold')) {
                throw 'Invalid V2 typography values.'
            }
            if ($property.Name -ceq $ThemeId) {
                $selected = [pscustomobject]@{ Family = $family; Size = $size; Weight = $weight }
            }
        }
        if ($null -eq $selected) { throw 'Selected theme has no saved V2 font preference.' }
    }
    finally { $doc.Dispose() }

    $settings = Read-TypezeroActivationV2Snapshot -Path $SettingsPath -MaximumBytes 33554432
    if ($ExpectedSettingsSha256 -and $settings.Sha256 -cne $ExpectedSettingsSha256.ToUpperInvariant()) {
        throw 'Terminal settings snapshot is stale.'
    }
    $options = [Text.Json.JsonDocumentOptions]::new()
    $options.AllowTrailingCommas = $true
    $options.CommentHandling = [Text.Json.JsonCommentHandling]::Skip
    $settingsDoc = [Text.Json.JsonDocument]::Parse($settings.Text, $options)
    try { Assert-TypezeroActivationV2UnambiguousJson -Element $settingsDoc.RootElement }
    finally { $settingsDoc.Dispose() }
    if (-not (Get-Command Get-TypezeroFontProfileTextSnapshot -CommandType Function -ErrorAction SilentlyContinue)) {
        throw 'Readiness dependency not loaded: Get-TypezeroFontProfileTextSnapshot'
    }
    $profile = Get-TypezeroFontProfileTextSnapshot -Text $settings.Text

    $blockers = [Collections.Generic.List[string]]::new()
    if (-not $enabled) { $blockers.Add('INTEGRATION_DISABLED') }
    if ($settings.Text.Contains('/* TYPEZERO_FONT_V2 */')) { $blockers.Add('V2_OWNERSHIP_REQUIRES_AUTHORIZED_RECOVERY') }
    if ($profile.HasFont) { $blockers.Add('EXISTING_PROFILE_FONT_REQUIRES_OWNERSHIP_REVIEW') }
    # These are implementation facts, never caller-supplied authorization flags.
    $blockers.Add('PRODUCTION_RECOVERY_AUTHORIZATION_NOT_IMPLEMENTED')
    $blockers.Add('PRODUCTION_DURABLE_REPLAY_PROTECTION_NOT_IMPLEMENTED')
    $blockers.Add('AUTHENTICATED_OPERATION_PHASE_NOT_ESTABLISHED')
    $blockers.Add('GUARDED_LIVE_TRANSACTION_NOT_IMPLEMENTED')
    [pscustomobject]@{
        Version = 2
        Status = 'BLOCKED'
        Theme = $ThemeId
        Preference = $selected
        IntegrationEnabled = $enabled
        ConfigPath = $config.Path
        ConfigSha256 = $config.Sha256
        SettingsPath = $settings.Path
        SettingsSha256 = $settings.Sha256
        Blockers = $blockers.ToArray()
        ReadOnly = $true
        SettingsChanged = $false
        FontActivated = $false
        RecoveryAllowed = $false
        RecoveryAuthorized = $false
        ReplayProtectionEstablished = $false
        LiveActivationAuthorized = $false
        OperationPhase = 'UNKNOWN'
    }
}
