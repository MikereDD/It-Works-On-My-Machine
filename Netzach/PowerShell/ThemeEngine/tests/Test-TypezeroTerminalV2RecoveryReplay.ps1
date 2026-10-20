param(
    [ValidateSet('Parent','ChildReserve','ChildCrash')][string]$Mode = 'Parent',
    [string]$TestRoot = '',
    [string]$BackupDirectory = ''
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$engine = Split-Path -Parent $PSScriptRoot
$utf8 = [Text.UTF8Encoding]::new($false, $true)

foreach ($name in @(
    'FontPatch-WindowsTerminal.ps1', 'TerminalColorPatch-WindowsTerminal.ps1',
    'TerminalCombinedPatch-WindowsTerminal.ps1', 'TerminalTransaction-WindowsTerminal.ps1',
    'TerminalReplace-WindowsTerminal.ps1', 'TerminalTransactionV2-WindowsTerminal.ps1',
    'TerminalTransactionV2Lock-WindowsTerminal.ps1', 'TerminalEvidenceSealV2-WindowsTerminal.ps1',
    'TerminalRecoveryAuthorizationV2-WindowsTerminal.ps1', 'TerminalRecoveryGrantV2-WindowsTerminal.ps1',
    'TerminalRecoveryReplayV2-WindowsTerminal.ps1'
)) { . (Join-Path $engine $name) }

function Assert-Test {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "FAIL: $Message" }
}

if ($Mode -cne 'Parent') {
    $inputData = [Console]::In.ReadLine() | ConvertFrom-Json
    [byte[]]$approvalKey = [Convert]::FromBase64String($inputData.ApprovalKey)
    [byte[]]$evidenceKey = [Convert]::FromBase64String($inputData.EvidenceKey)
    [byte[]]$mac = [Convert]::FromBase64String($inputData.AuthorizationMac)
    try {
        if ($Mode -ceq 'ChildCrash') {
            $script:CrashRoot = (Get-TypezeroOfflineTerminalV2Paths -TestRoot $TestRoot).Root
            function Invoke-ReplayTestCheckpoint {
                param([string]$Path)
                if ($Path -cnotlike '*.reserved') { return }
                # The real CreateNew handle is held, but its write has not begun.
                $signal = Join-Path $script:CrashRoot 'replay-crash-signal.json'
                $process = [Diagnostics.Process]::GetCurrentProcess()
                [IO.File]::WriteAllText($signal, ([ordered]@{
                    ProcessId = $PID
                    StartTicks = $process.StartTime.ToUniversalTime().Ticks
                    ReservationPath = $Path
                } | ConvertTo-Json -Compress), $utf8)
                while ($true) { Start-Sleep -Milliseconds 50 }
            }
            $body = (Get-Command Write-TypezeroOfflineTerminalV2NewFile).ScriptBlock.ToString()
            $anchor = '$stream.Write($Bytes, 0, $Bytes.Length)'
            Assert-Test ($body.Split($anchor).Count -eq 2) 'Unique CreateNew write checkpoint'
            $instrumented = $body.Replace($anchor, ('Invoke-ReplayTestCheckpoint -Path $Path' + "`n        " + $anchor))
            Assert-Test ($instrumented.Replace(('Invoke-ReplayTestCheckpoint -Path $Path' + "`n        " + $anchor), $anchor) -ceq $body) 'Reversible checkpoint'
            Set-Item -Path Function:\Write-TypezeroOfflineTerminalV2NewFile `
                -Value ([scriptblock]::Create($instrumented))
        }
        $result = Reserve-TypezeroOfflineTerminalV2RecoveryGrant `
            -TestRoot $TestRoot -BackupDirectory $BackupDirectory `
            -GrantJson $inputData.GrantJson -AuthorizationMac $mac `
            -ApprovalKey $approvalKey -EvidenceKey $evidenceKey `
            -Execute -Confirm:$false
        $result | ConvertTo-Json -Compress
    }
    finally {
        [array]::Clear($approvalKey, 0, $approvalKey.Length)
        [array]::Clear($evidenceKey, 0, $evidenceKey.Length)
    }
    return
}

$root = Join-Path ([IO.Path]::GetTempPath()) (
    'typezero-terminal-txn-' + [guid]::NewGuid().ToString('N')
)
[IO.Directory]::CreateDirectory($root) | Out-Null
$paths = Get-TypezeroOfflineTerminalV2Paths -TestRoot $root
[IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($paths.Settings)) | Out-Null
$synthetic = [ordered]@{
    theme = 'Typezero ThemeEngine'
    schemes = @(@{ name = 'Typezero Obsidian Silver'; background = '#000000' })
    themes = @(@{
        name = 'Typezero ThemeEngine'
        window = @{ applicationTheme = 'dark' }
        tab = @{ background = 'terminalBackground' }
        tabRow = @{ background = '#000000' }
    })
    profiles = @{
        defaults = @{}
        list = @(@{
            guid = '{574e775e-4f2a-5b96-ac1e-a2962a402336}'
            name = 'PowerShell'; colorScheme = 'Typezero Obsidian Silver'
        })
    }
}
[IO.File]::WriteAllText($paths.Settings, ($synthetic | ConvertTo-Json -Depth 20), $utf8)
$theme = @{
    THEME_NAME = 'Obsidian Silver'; BG = '#123456'; TEXT = '#eeeeee'
    CURSOR = '#ffffff'; SELECTION = '#445566'
}
foreach ($name in @(
    'BLACK','RED','GREEN','YELLOW','BLUE','PURPLE','CYAN','WHITE',
    'BRIGHT_BLACK','BRIGHT_RED','BRIGHT_GREEN','BRIGHT_YELLOW',
    'BRIGHT_BLUE','BRIGHT_PURPLE','BRIGHT_CYAN','BRIGHT_WHITE'
)) { $theme["ANSI_$name"] = '#778899' }
[byte[]]$evidenceKey = [byte[]]::new(32)
[byte[]]$approvalKey = [byte[]]::new(32)
[Security.Cryptography.RandomNumberGenerator]::Fill($evidenceKey)
[Security.Cryptography.RandomNumberGenerator]::Fill($approvalKey)
while ([Security.Cryptography.CryptographicOperations]::FixedTimeEquals($evidenceKey, $approvalKey)) {
    [Security.Cryptography.RandomNumberGenerator]::Fill($approvalKey)
}
$checks = 0

function Pass {
    param([string]$Label)
    $script:checks++
    Write-Host "PASS [$script:checks] $Label"
}
function Get-Snapshot {
    (@(Get-ChildItem -LiteralPath $root -Recurse -Force -File |
        Sort-Object FullName | ForEach-Object {
            $_.FullName.Substring($root.Length) + '|' +
            (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash
        })) -join "`n"
}
function Assert-Unauthorized {
    param($Result)
    Assert-Test (
        $Result.FixtureOnly -eq $true -and
        $Result.GrantConsumed -eq $false -and
        $Result.TrustedDurableProductionLedger -eq $false -and
        $Result.RecoveryAllowed -eq $false -and
        $Result.RecoveryAuthorized -eq $false -and
        $Result.LiveActivationAuthorized -eq $false -and
        $Result.OperationPhase -ceq 'UNKNOWN'
    ) 'Reservation must never authorize recovery or live activation'
}
function New-TestGrant {
    param([hashtable]$Overrides = @{})
    $fields = [ordered]@{}
    foreach ($name in $baseGrant.Keys) { $fields[$name] = $baseGrant[$name] }
    $fields['GrantId'] = [guid]::NewGuid().ToString('N')
    foreach ($name in $Overrides.Keys) { $fields[$name] = $Overrides[$name] }
    [byte[]]$payload = Get-TypezeroOfflineTerminalV2GrantPayload -Fields $fields
    [pscustomobject]@{
        Id = $fields['GrantId']
        Json = ($fields | ConvertTo-Json -Compress)
        Mac = [Security.Cryptography.HMACSHA256]::HashData($approvalKey, $payload)
    }
}
function Reserve-Grant {
    param($Grant, [switch]$Execute)
    Reserve-TypezeroOfflineTerminalV2RecoveryGrant `
        -TestRoot $root -BackupDirectory $folder -GrantJson $Grant.Json `
        -AuthorizationMac $Grant.Mac -ApprovalKey $approvalKey `
        -EvidenceKey $evidenceKey -Execute:$Execute -Confirm:$false
}
function Assert-Refused {
    param([scriptblock]$Action, [string]$Label)
    $threw = $false
    try { & $Action | Out-Null } catch { $threw = $true }
    Assert-Test $threw $Label
    Pass $Label
}
function Start-ReplayChild {
    param($Grant, [string]$ChildMode = 'ChildReserve')
    $psi = [Diagnostics.ProcessStartInfo]::new()
    $psi.FileName = (Get-Command pwsh -ErrorAction Stop).Source
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.RedirectStandardInput = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    foreach ($argument in @(
        '-NoProfile','-NonInteractive','-File',$PSCommandPath,
        '-Mode',$ChildMode,'-TestRoot',$root,'-BackupDirectory',$folder
    )) { $psi.ArgumentList.Add($argument) }
    $process = [Diagnostics.Process]::new()
    $process.StartInfo = $psi
    Assert-Test ($process.Start()) 'Replay child starts'
    $data = [ordered]@{
        GrantJson = $Grant.Json
        AuthorizationMac = [Convert]::ToBase64String($Grant.Mac)
        ApprovalKey = [Convert]::ToBase64String($approvalKey)
        EvidenceKey = [Convert]::ToBase64String($evidenceKey)
    }
    $process.StandardInput.WriteLine(($data | ConvertTo-Json -Compress))
    $process.StandardInput.Close()
    $process
}
function Complete-ReplayChild {
    param($Process)
    Assert-Test ($Process.WaitForExit(15000)) 'Replay child completes'
    $outputText = $Process.StandardOutput.ReadToEnd()
    $errorText = $Process.StandardError.ReadToEnd()
    Assert-Test ($Process.ExitCode -eq 0) "Replay child succeeds: $errorText"
    $outputText | ConvertFrom-Json
}
function Close-ReplayChild {
    param($Process)
    if (-not $Process.HasExited) {
        $Process.Kill()
        $null = $Process.WaitForExit(5000)
    }
    $Process.Dispose()
}

try {
    $previewRoot = Join-Path ([IO.Path]::GetTempPath()) ('typezero-terminal-txn-' + [guid]::NewGuid().ToString('N'))
    [IO.Directory]::CreateDirectory($previewRoot) | Out-Null
    $null = Initialize-TypezeroOfflineTerminalV2ReplayStore -TestRoot $previewRoot
    Initialize-TypezeroOfflineTerminalV2ReplayStore -TestRoot $previewRoot -Execute -WhatIf | Out-Null
    Assert-Test (@(Get-ChildItem -LiteralPath $previewRoot -Force).Count -eq 0) 'Fresh preview creates no lock, directories, or files'
    Pass 'Fresh initialization preview and WhatIf leave an empty fixture empty'
    $applied = Invoke-TypezeroOfflineTerminalV2Locked -TestRoot $root `
        -Theme $theme -FontFace 'JetBrainsMono Nerd Font' -FontSize 13 `
        -FontWeight normal -Execute -Confirm:$false
    $folder = $applied.BackupDirectory
    $null = New-TypezeroOfflineTerminalV2EvidenceSeal -TestRoot $root `
        -BackupDirectory $folder -IndependentKey $evidenceKey -Execute -Confirm:$false
    $context = Get-TypezeroOfflineTerminalV2SealContext -TestRoot $root -BackupDirectory $folder
    $issued = [datetime]::UtcNow.AddSeconds(-2)
    $dateFormat = "yyyy-MM-ddTHH:mm:ss.fffffff'Z'"
    $culture = [Globalization.CultureInfo]::InvariantCulture
    $baseGrant = [ordered]@{
        Version = 2; GrantId = ''; Operation = 'RESTORE'; FixtureRoot = $paths.Root
        BackupDirectory = $folder
        ReceiptSha256 = (Get-FileHash -LiteralPath $context.Receipt -Algorithm SHA256).Hash
        BackupSha256 = (Get-FileHash -LiteralPath $context.Backup -Algorithm SHA256).Hash
        SealSha256 = (Get-FileHash -LiteralPath $context.Seal -Algorithm SHA256).Hash
        ExpectedSettingsSha256 = (Get-FileHash -LiteralPath $paths.Settings -Algorithm SHA256).Hash
        IssuedUtc = $issued.ToString($dateFormat, $culture)
        ExpiresUtc = $issued.AddMinutes(10).ToString($dateFormat, $culture)
    }

    $before = Get-Snapshot
    $preview = Initialize-TypezeroOfflineTerminalV2ReplayStore -TestRoot $root
    Initialize-TypezeroOfflineTerminalV2ReplayStore -TestRoot $root -Execute -WhatIf | Out-Null
    Assert-Test ($preview.ReadOnly -and (Get-Snapshot) -ceq $before) 'Initialization preview and WhatIf unchanged'
    Pass 'Initialization preview and WhatIf create no store or files'
    $null = Initialize-TypezeroOfflineTerminalV2ReplayStore -TestRoot $root -Execute -Confirm:$false
    $replay = Get-TypezeroOfflineTerminalV2ReplayContext -TestRoot $root
    Assert-Refused { Initialize-TypezeroOfflineTerminalV2ReplayStore -TestRoot $root -Execute -Confirm:$false } 'Existing store cannot be reset'

    $grant = New-TestGrant
    $before = Get-Snapshot
    $preview = Reserve-Grant $grant
    Reserve-TypezeroOfflineTerminalV2RecoveryGrant -TestRoot $root `
        -BackupDirectory $folder -GrantJson $grant.Json -AuthorizationMac $grant.Mac `
        -ApprovalKey $approvalKey -EvidenceKey $evidenceKey -Execute -WhatIf | Out-Null
    Assert-Unauthorized $preview
    Assert-Test ($preview.Decision -ceq 'PREVIEW' -and (Get-Snapshot) -ceq $before) 'Reservation preview unchanged'
    Pass 'Reservation preview and WhatIf preserve the entire fixture'
    $reserved = Reserve-Grant $grant -Execute
    Assert-Unauthorized $reserved
    Assert-Test ($reserved.Decision -ceq 'RESERVED_FIXTURE_ONLY' -and $reserved.GrantReserved) 'First reservation succeeds'
    $before = Get-Snapshot
    $again = Reserve-Grant $grant -Execute
    Assert-Unauthorized $again
    Assert-Test ($again.Decision -ceq 'REPLAY_REFUSED' -and (Get-Snapshot) -ceq $before) 'Repeated reservation refused unchanged'
    Pass 'One reservation succeeds; repeat refuses without authorizing recovery'
    $child = Start-ReplayChild $grant
    try {
        $cross = Complete-ReplayChild $child
        Assert-Unauthorized $cross
        Assert-Test ($cross.Decision -ceq 'REPLAY_REFUSED') 'Cross-process replay refused'
    } finally { Close-ReplayChild $child }
    Pass 'Independent process refuses the reserved grant ID'

    $raceGrant = New-TestGrant
    $child1 = Start-ReplayChild $raceGrant
    $child2 = Start-ReplayChild $raceGrant
    try {
        # A contender can either see the tombstone or be refused by the fixed
        # transaction lock. Both outcomes must produce exactly one tombstone.
        Assert-Test ($child1.WaitForExit(15000) -and $child2.WaitForExit(15000)) 'Race workers complete'
        $successes = 0
        foreach ($child in @($child1,$child2)) {
            $outText = $child.StandardOutput.ReadToEnd()
            $errText = $child.StandardError.ReadToEnd()
            if ($child.ExitCode -eq 0) {
                $result = $outText | ConvertFrom-Json
                Assert-Unauthorized $result
                if ($result.GrantReserved) { $successes++ }
                else { Assert-Test ($result.Decision -ceq 'REPLAY_REFUSED') 'Race loser replay refusal' }
            }
            else { Assert-Test ($errText -match 'lock|being used') 'Race loser lock refusal' }
        }
        Assert-Test ($successes -eq 1) 'Exactly one concurrent grant reservation'
    } finally { Close-ReplayChild $child1; Close-ReplayChild $child2 }
    Pass 'Competing processes reserve one grant at most once'

    $lockGrant = New-TestGrant
    $held = [IO.FileStream]::new((Join-Path $root '.typezero-terminal-v2.lock'),
        [IO.FileMode]::Open, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
    try { Assert-Refused { Reserve-Grant $lockGrant -Execute } 'Occupied shared V2 lock refuses reservation' }
    finally { $held.Dispose() }
    Assert-Test (-not [IO.File]::Exists((Join-Path $replay.Store ($lockGrant.Id + '.reserved')))) 'Contended grant remains unused'

    foreach ($case in @('WrongKey','WrongEvidenceKey','BadMac','Expired','WrongOperation','StaleSettings','Malformed')) {
        $testGrant = switch ($case) {
            'Expired' { New-TestGrant @{
                IssuedUtc = ([datetime]::UtcNow.AddMinutes(-20)).ToString($dateFormat, $culture)
                ExpiresUtc = ([datetime]::UtcNow.AddMinutes(-10)).ToString($dateFormat, $culture)
            } }
            'WrongOperation' { New-TestGrant @{ Operation = 'APPLY' } }
            default { New-TestGrant }
        }
        [byte[]]$settingsBytes = [IO.File]::ReadAllBytes($paths.Settings)
        [byte[]]$verificationKey = $approvalKey
        [byte[]]$verificationEvidenceKey = $evidenceKey
        if ($case -ceq 'WrongKey') {
            $verificationKey = [byte[]]::new(32)
            [Security.Cryptography.RandomNumberGenerator]::Fill($verificationKey)
        }
        if ($case -ceq 'WrongEvidenceKey') {
            $verificationEvidenceKey = [byte[]]::new(32)
            [Security.Cryptography.RandomNumberGenerator]::Fill($verificationEvidenceKey)
        }
        if ($case -ceq 'BadMac') { $testGrant.Mac[0] = $testGrant.Mac[0] -bxor 1 }
        if ($case -ceq 'StaleSettings') { [IO.File]::WriteAllText($paths.Settings, '{"external":true}', $utf8) }
        if ($case -ceq 'Malformed') { $testGrant.Json = '{"Version":2}' }
        try {
            $before = Get-Snapshot
            $result = Reserve-TypezeroOfflineTerminalV2RecoveryGrant `
                -TestRoot $root -BackupDirectory $folder -GrantJson $testGrant.Json `
                -AuthorizationMac $testGrant.Mac -ApprovalKey $verificationKey `
                -EvidenceKey $verificationEvidenceKey -Execute -Confirm:$false
            Assert-Unauthorized $result
            Assert-Test (-not $result.GrantReserved -and (Get-Snapshot) -ceq $before) "$case does not reserve or mutate"
            Pass "$case refuses without consuming the grant"
        }
        finally { [IO.File]::WriteAllBytes($paths.Settings, $settingsBytes) }
    }

    # Test-only interposition changes settings AFTER initial validation and
    # BEFORE acquiring the fixed lock. The real locked second review must refuse.
    $freshGrant = New-TestGrant
    [byte[]]$settingsBytes = [IO.File]::ReadAllBytes($paths.Settings)
    $script:OriginalReplayLock = (Get-Command Open-TypezeroOfflineTerminalV2ReplayLock).ScriptBlock
    $script:StaleReplaySettings = $paths.Settings
    function Open-TypezeroOfflineTerminalV2ReplayLock {
        param([string]$TestRoot)
        [IO.File]::WriteAllText($script:StaleReplaySettings, '{"changedBeforeLock":true}', $utf8)
        & $script:OriginalReplayLock -TestRoot $TestRoot
    }
    try {
        $result = Reserve-Grant $freshGrant -Execute
        Assert-Test ($result.Decision -ceq 'GRANT_STATE_CONFLICT' -and -not $result.GrantReserved) 'Fresh locked review rejects post-preview state change'
        Assert-Test (-not [IO.File]::Exists((Join-Path $replay.Store ($freshGrant.Id + '.reserved')))) 'Stale grant ID remains unreserved'
        Pass 'Grant and evidence are reviewed freshly under the shared V2 lock'
    }
    finally {
        Set-Item -Path Function:\Open-TypezeroOfflineTerminalV2ReplayLock -Value $script:OriginalReplayLock
        [IO.File]::WriteAllBytes($paths.Settings, $settingsBytes)
    }

    foreach ($bytes in @([byte[]]::new(0), $utf8.GetBytes('{broken'))) {
        $partial = New-TestGrant
        [IO.File]::WriteAllBytes((Join-Path $replay.Store ($partial.Id + '.reserved')), $bytes)
        $before = Get-Snapshot
        $result = Reserve-Grant $partial -Execute
        Assert-Test ($result.Decision -ceq 'REPLAY_REFUSED' -and (Get-Snapshot) -ceq $before) 'Partial/corrupt reservation remains spent'
    }
    Pass 'Empty and corrupt tombstones are permanent refusals'

    $crashGrant = New-TestGrant
    $child = Start-ReplayChild $crashGrant 'ChildCrash'
    try {
        $started = $child.StartTime.ToUniversalTime().Ticks
        $signal = Join-Path $root 'replay-crash-signal.json'
        $deadline = [datetime]::UtcNow.AddSeconds(15)
        while (-not [IO.File]::Exists($signal) -and -not $child.HasExited -and [datetime]::UtcNow -lt $deadline) {
            Start-Sleep -Milliseconds 50
        }
        if (-not [IO.File]::Exists($signal)) {
            if (-not $child.HasExited) { $child.Kill(); $null = $child.WaitForExit(5000) }
            throw ('Crash worker missed checkpoint: ' + $child.StandardError.ReadToEnd())
        }
        $paused = [IO.File]::ReadAllText($signal) | ConvertFrom-Json
        Assert-Test ($paused.ProcessId -eq $child.Id -and $paused.StartTicks -eq $started -and
            $paused.ReservationPath -ceq (Join-Path $replay.Store ($crashGrant.Id + '.reserved'))) 'Crash worker and reserved path identity'
        $child.Kill()
        Assert-Test ($child.WaitForExit(5000)) 'Parent-owned crash worker terminates'
        $result = Reserve-Grant $crashGrant -Execute
        Assert-Test ($result.Decision -ceq 'REPLAY_REFUSED' -and
            (Get-Item -LiteralPath $paused.ReservationPath).Length -eq 0) 'Crash survivor is spent'
    }
    finally {
        if (-not $child.HasExited) { $child.Kill(); $null = $child.WaitForExit(5000) }
        $child.Dispose()
    }
    Pass 'Hard process termination after CreateNew preserves an unusable tombstone'

    Assert-Refused { Get-TypezeroOfflineTerminalV2ReplayContext -TestRoot (Join-Path $root 'nested') } 'Malformed fixture path refuses'
    $partialRoot = Join-Path ([IO.Path]::GetTempPath()) ('typezero-terminal-txn-' + [guid]::NewGuid().ToString('N'))
    $partialStore = Join-Path $partialRoot '.typezero-terminal-v2-recovery-replay'
    [IO.Directory]::CreateDirectory($partialStore) | Out-Null
    Assert-Refused { Initialize-TypezeroOfflineTerminalV2ReplayStore -TestRoot $partialRoot -Execute -Confirm:$false } 'Partial store initialization cannot be recycled'
    $lockRoot = Join-Path ([IO.Path]::GetTempPath()) ('typezero-terminal-txn-' + [guid]::NewGuid().ToString('N'))
    [IO.Directory]::CreateDirectory($lockRoot) | Out-Null
    $lockSource = Join-Path $lockRoot 'lock-source.fixture'
    [IO.File]::WriteAllText($lockSource, 'synthetic hardlink target', $utf8)
    $null = New-Item -ItemType HardLink -Path (Join-Path $lockRoot '.typezero-terminal-v2.lock') -Target $lockSource -ErrorAction Stop
    Assert-Refused { Initialize-TypezeroOfflineTerminalV2ReplayStore -TestRoot $lockRoot -Execute -Confirm:$false } 'Hard-linked fixed transaction lock refuses'
    $markerBytes = [IO.File]::ReadAllBytes($replay.Marker)
    [IO.File]::WriteAllText($replay.Marker, 'corrupt', $utf8)
    try { Assert-Refused { Reserve-Grant (New-TestGrant) -Execute } 'Corrupt replay marker refuses' }
    finally { [IO.File]::WriteAllBytes($replay.Marker, $markerBytes) }

    $hardlink = Join-Path $replay.Store ([guid]::NewGuid().ToString('N') + '.reserved')
    $null = New-Item -ItemType HardLink -Path $hardlink -Target $context.Receipt -ErrorAction Stop
    Assert-Refused { Reserve-Grant (New-TestGrant) -Execute } 'Hard-linked replay entry refuses'
    # Keep unsafe fixture evidence intact, and use a fresh fixture for junction
    # refusal so no existing replay entry or evidence needs removal.
    $linkRoot = Join-Path ([IO.Path]::GetTempPath()) ('typezero-terminal-txn-' + [guid]::NewGuid().ToString('N'))
    [IO.Directory]::CreateDirectory($linkRoot) | Out-Null
    $linkStore = Join-Path $linkRoot '.typezero-terminal-v2-recovery-replay'
    $null = New-Item -ItemType Junction -Path $linkStore -Target $replay.Store -ErrorAction Stop
    Assert-Refused { Get-TypezeroOfflineTerminalV2ReplayContext -TestRoot $linkRoot } 'Redirected replay directory refuses'

    Write-Host "`nPASS: $checks V2 fixture replay checks."
    Write-Host 'RecoveryAuthorized=False; LiveActivationAuthorized=False'
    Write-Host 'ReplayProtectionScope=CooperatingFixtureProcessesOnly'
    Write-Host 'TrustedDurableProductionLedger=False'
    Write-Host "Fixture retained: $root"
    Write-Host "Preview fixture retained: $previewRoot"
    Write-Host "Partial fixture retained: $partialRoot"
    Write-Host "Lock fixture retained: $lockRoot"
    Write-Host "Redirect fixture retained: $linkRoot"
}
finally {
    [array]::Clear($approvalKey, 0, $approvalKey.Length)
    [array]::Clear($evidenceKey, 0, $evidenceKey.Length)
}
