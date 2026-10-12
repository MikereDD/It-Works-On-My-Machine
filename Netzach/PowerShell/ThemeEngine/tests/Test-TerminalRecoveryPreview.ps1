# Standalone read-only recovery preview tests. No Pester dependency.
# Loads offline function definitions, then guards both writer entry points.
# Every created fixture is NEW, directly beneath %TEMP%, and retained for review.
[CmdletBinding()]
param(
    [string]$SourceDirectory = (Split-Path -Parent $PSScriptRoot),
    [string]$PreviewPath = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$script:Passed = 0
$script:Failed = 0
$script:Roots = [Collections.Generic.List[string]]::new()
$script:Failures = [Collections.Generic.List[string]]::new()
$script:Utf8 = [Text.UTF8Encoding]::new($false, $true)
$script:WriterCalls = 0

. (Join-Path $SourceDirectory 'TerminalTransaction-WindowsTerminal.ps1')
if (-not [string]::IsNullOrEmpty($PreviewPath)) { . $PreviewPath }

function Invoke-TypezeroOfflineTerminalCombinedTransaction {
    $script:WriterCalls++
    throw 'TEST GUARD: preview attempted an apply writer.'
}
function Restore-TypezeroOfflineTerminalCombinedTransaction {
    $script:WriterCalls++
    throw 'TEST GUARD: preview attempted a restore writer.'
}

function Assert-Test {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}
function Assert-Equal {
    param($Actual, $Expected, [string]$Message)
    if ($Actual -cne $Expected) {
        throw ($Message + ': expected [' + $Expected + '], actual [' + $Actual + ']')
    }
}
function Invoke-Test {
    param([string]$Name, [scriptblock]$Body)
    try {
        & $Body
        $script:Passed++
        Write-Host ('PASS ' + $Name)
    }
    catch {
        $script:Failed++
        $detail = $Name + ': ' + $_.Exception.Message
        $script:Failures.Add($detail)
        Write-Host ('FAIL ' + $detail)
    }
}
function Get-TestByteHash {
    param([byte[]]$Bytes)
    $sha = [Security.Cryptography.SHA256]::Create()
    try { [BitConverter]::ToString($sha.ComputeHash($Bytes)).Replace('-', '') }
    finally { $sha.Dispose() }
}
function Write-FixtureBytes {
    param($Fixture, [string]$Path, [byte[]]$Bytes)
    $root = [IO.Path]::GetFullPath($Fixture.Root).TrimEnd('\')
    $pathFull = [IO.Path]::GetFullPath($Path)
    Assert-Test ($script:Roots.Contains($root)) 'Write requires a new fixture root'
    Assert-Test ($pathFull.StartsWith($root + '\', [StringComparison]::OrdinalIgnoreCase)) 'Fixture write would escape root'
    [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($pathFull)) | Out-Null
    [IO.File]::WriteAllBytes($pathFull, $Bytes)
}
function New-Fixture {
    param([switch]$NoReceipt, [switch]$NoBackup, [switch]$NoSettings, [switch]$NoTransaction, [switch]$Applied)
    $root = Join-Path ([IO.Path]::GetTempPath()) ('typezero-terminal-txn-' + [guid]::NewGuid().ToString('N'))
    $root = [IO.Path]::GetFullPath($root)
    Assert-Test (-not [IO.Directory]::Exists($root) -and -not [IO.File]::Exists($root)) 'Fixture already exists'
    [IO.Directory]::CreateDirectory($root) | Out-Null
    $script:Roots.Add($root)
    $settings = Join-Path $root 'Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json'
    $folder = Join-Path $root ('Typezero\ThemeEngine\backups\terminal-combined\20000101-000000-0000000-' + [guid]::NewGuid().ToString('N'))
    $before = $script:Utf8.GetBytes('{"fixture":"original"}' + "`r`n")
    $after = $script:Utf8.GetBytes('{"fixture":"applied"}' + "`n")
    $other = $script:Utf8.GetBytes('{"fixture":"unrelated edit"}')
    $fixture = [pscustomobject]@{
        Root = $root
        Settings = $settings
        BackupDirectory = $folder
        Backup = Join-Path $folder 'settings-original.json'
        Receipt = Join-Path $folder 'receipt.json'
        BeforeBytes = $before
        AfterBytes = $after
        OtherBytes = $other
        BeforeHash = Get-TestByteHash $before
        AfterHash = Get-TestByteHash $after
    }
    if (-not $NoSettings) {
        $bytes = if ($Applied) { $after } else { $before }
        Write-FixtureBytes $fixture $settings $bytes
    }
    if (-not $NoTransaction) {
        [IO.Directory]::CreateDirectory($folder) | Out-Null
        if (-not $NoBackup) { Write-FixtureBytes $fixture $fixture.Backup $before }
        if (-not $NoReceipt) {
            $receipt = [ordered]@{
                Version = 1
                Kind = 'TypezeroOfflineCombined'
                SettingsPath = $settings
                BeforeSha256 = $fixture.BeforeHash
                AfterSha256 = $fixture.AfterHash
                Font = 'Preview Fixture'
                Size = 12
                Weight = 'normal'
            }
            Write-FixtureBytes $fixture $fixture.Receipt $script:Utf8.GetBytes(($receipt | ConvertTo-Json))
        }
    }
    return $fixture
}
function Get-FixtureSnapshot {
    param([string[]]$Roots)
    $entries = [Collections.Generic.List[string]]::new()
    $pending = [Collections.Generic.Queue[string]]::new()
    foreach ($root in $Roots) { $pending.Enqueue($root) }
    while ($pending.Count -gt 0) {
        $path = $pending.Dequeue()
        $item = Get-Item -LiteralPath $path -Force -ErrorAction Stop
        $attributes = $item.Attributes
        $prefix = $item.FullName + '|' + [int]$attributes + '|' + $item.CreationTimeUtc.Ticks + '|' + $item.LastWriteTimeUtc.Ticks
        if (($attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            $entries.Add($prefix + '|REPARSE')
        }
        elseif (($attributes -band [IO.FileAttributes]::Directory) -ne 0) {
            $entries.Add($prefix + '|DIRECTORY')
            foreach ($child in [IO.Directory]::GetFileSystemEntries($path)) { $pending.Enqueue($child) }
        }
        else {
            $entries.Add($prefix + '|FILE|' + $item.Length + '|' + (Get-TestByteHash ([IO.File]::ReadAllBytes($path))))
        }
    }
    return [string]::Join("`n", @($entries | Sort-Object))
}
function Invoke-CheckedPreview {
    param($Fixture, [string]$State, [string]$Action, [string[]]$AdditionalRoots = @(), [hashtable]$Arguments = @{}, [switch]$MustThrow, [string]$ThrowPattern)
    $roots = @($Fixture.Root) + $AdditionalRoots
    $before = Get-FixtureSnapshot $roots
    $caught = $null
    $results = @()
    try {
        $parameters = @{ TestRoot = $Fixture.Root; BackupDirectory = $Fixture.BackupDirectory }
        foreach ($key in $Arguments.Keys) { $parameters[$key] = $Arguments[$key] }
        $results = @(Get-TypezeroOfflineTerminalCombinedRecoveryPreview @parameters)
    }
    catch { $caught = $_ }
    Assert-Equal (Get-FixtureSnapshot $roots) $before 'Preview changed fixture names, bytes, attributes or timestamps'
    Assert-Equal $script:WriterCalls 0 'Preview called a writer'
    if ($MustThrow) {
        Assert-Test ($null -ne $caught) 'Unsafe input unexpectedly returned preview'
        if ($ThrowPattern) { Assert-Test ($caught.Exception.Message -match $ThrowPattern) ('Unexpected failure: ' + $caught.Exception.Message) }
        return
    }
    if ($null -ne $caught) { throw $caught }
    Assert-Equal $results.Count 1 'Expected one result only'
    $result = $results[0]
    Assert-Equal $result.Status 'PREVIEW' 'Status'
    Assert-Equal $result.ObservedState $State 'Observed state'
    Assert-Equal $result.SuggestedAction $Action 'Suggested action'
    Assert-Test ($result.ReadOnly -is [bool] -and $result.ReadOnly) 'ReadOnly must be Boolean true'
    Assert-Test ($result.RecoveryAllowed -is [bool] -and -not $result.RecoveryAllowed) 'RecoveryAllowed must be Boolean false'
    Assert-Equal $result.OperationPhase 'UNKNOWN' 'Phase must remain unknown'
    Assert-Test (@($result.Blockers).Contains('OperationPhaseUnknown')) 'Phase ambiguity blocker missing'
    Assert-Equal $result.TestRoot $Fixture.Root 'Fixture root'
    Assert-Equal $result.BackupDirectory $Fixture.BackupDirectory 'Backup directory'
    Assert-Equal $result.Diagnostic.State $State 'Nested diagnostic state'
    foreach ($stage in $result.Diagnostic.StageFiles) { Assert-Equal $stage.Association 'UNPROVEN' 'Stage association' }
    return $result
}

Invoke-Test 'Preview exposes only required paths and no execution switches' {
    $command = Get-Command Get-TypezeroOfflineTerminalCombinedRecoveryPreview
    foreach ($name in @('Execute', 'WhatIf', 'Confirm')) {
        Assert-Test (-not $command.Parameters.ContainsKey($name)) ('Unexpected execution parameter: ' + $name)
    }
    foreach ($name in @('TestRoot', 'BackupDirectory')) {
        $mandatory = @($command.Parameters[$name].Attributes | Where-Object { $_ -is [Management.Automation.ParameterAttribute] -and $_.Mandatory })
        Assert-Equal $mandatory.Count 1 ('Required parameter ' + $name)
    }
    $calls = @($command.ScriptBlock.Ast.FindAll({ param($node) $node -is [Management.Automation.Language.CommandAst] }, $true))
    Assert-Equal $calls.Count 1 'Preview must have exactly one command invocation'
    Assert-Equal $calls[0].GetCommandName() 'Get-TypezeroOfflineTerminalCombinedRecoveryDiagnostic' 'Only permitted command'
}

Invoke-Test 'Original bytes indicate no replacement without proving completion' {
    $f = New-Fixture
    $p = Invoke-CheckedPreview $f 'ORIGINAL_BYTES_PRESENT' 'NoReplacementIndicated'
    Assert-Test ($p.Detail -match 'Never applied and already restored') 'Original ambiguity omitted'
}
Invoke-Test 'Applied bytes suggest separately authorized review only' {
    $f = New-Fixture -Applied
    $p = Invoke-CheckedPreview $f 'APPLIED_BYTES_PRESENT' 'ReviewExistingOfflineRestore'
    foreach ($blocker in @('FreshWriterChecksRequired', 'RecoveryExecutionAuthorizationRequired')) {
        Assert-Test (@($p.Blockers).Contains($blocker)) ('Missing blocker: ' + $blocker)
    }
    Assert-Test ($p.Detail -match 'Verification and restoration completion remain unknown') 'Applied ambiguity omitted'
    Assert-Test (-not ($p.PSObject.Properties.Name -match 'Command|Script|Execute')) 'Executable recommendation field returned'
}
foreach ($case in @(
    @{Name='Missing transaction'; Args=@{NoTransaction=$true}; State='TRANSACTION_MISSING'},
    @{Name='Empty transaction'; Args=@{NoReceipt=$true;NoBackup=$true}; State='EVIDENCE_INCOMPLETE'},
    @{Name='Backup without receipt'; Args=@{NoReceipt=$true}; State='EVIDENCE_INCOMPLETE'},
    @{Name='Receipt without backup'; Args=@{NoBackup=$true}; State='EVIDENCE_INCOMPLETE'},
    @{Name='Missing settings'; Args=@{NoSettings=$true}; State='SETTINGS_MISSING'}
)) {
    Invoke-Test ($case.Name + ' blocks recovery') {
        $fixtureArgs = $case.Args
        $f = New-Fixture @fixtureArgs
        $p = Invoke-CheckedPreview $f $case.State 'ManualInspection'
        Assert-Test (@($p.Blockers).Contains('NoRecoveryRecommendationFromEvidence')) 'Manual blocker missing'
    }
}
Invoke-Test 'Mismatched original backup blocks recovery' {
    $f = New-Fixture
    Write-FixtureBytes $f $f.Backup $f.OtherBytes
    $p = Invoke-CheckedPreview $f 'BACKUP_HASH_MISMATCH' 'ManualInspection'
    Assert-Test (@($p.Blockers).Contains('BackupNotVerified')) 'Backup blocker missing'
}
Invoke-Test 'Conflicting settings block recovery' {
    $f = New-Fixture
    Write-FixtureBytes $f $f.Settings $f.OtherBytes
    $p = Invoke-CheckedPreview $f 'SETTINGS_CONFLICT' 'ManualInspection'
    Assert-Test (@($p.Blockers).Contains('SettingsNotMatched')) 'Settings blocker missing'
}
foreach ($badReceipt in @('{', '{}', '{"Version":1,"version":1}', 'null')) {
    Invoke-Test ('Invalid receipt [' + $badReceipt + '] blocks recovery') {
        $f = New-Fixture
        Write-FixtureBytes $f $f.Receipt $script:Utf8.GetBytes($badReceipt)
        $p = Invoke-CheckedPreview $f 'INVALID_RECEIPT' 'ManualInspection'
        Assert-Test (@($p.Blockers).Contains('ReceiptNotValid')) 'Receipt blocker missing'
    }
}
Invoke-Test 'Invalid UTF8 receipt blocks recovery' {
    $f = New-Fixture
    Write-FixtureBytes $f $f.Receipt ([byte[]]@(255, 254, 255))
    $null = Invoke-CheckedPreview $f 'INVALID_RECEIPT' 'ManualInspection'
}
foreach ($applied in @($false, $true)) {
    foreach ($stageKind in @('APPLY', 'RESTORE')) {
        foreach ($match in @('BEFORE', 'AFTER', 'OTHER')) {
            Invoke-Test ("Stage $stageKind/$match with applied=$applied remains unproven") {
                $f = New-Fixture -Applied:$applied
                $name = '.typezero-combined-' + $(if ($stageKind -eq 'RESTORE') {'restore-'}) + [guid]::NewGuid().ToString('N') + '.tmp'
                $stagePath = Join-Path ([IO.Path]::GetDirectoryName($f.Settings)) $name
                $bytes = switch ($match) { 'BEFORE' {$f.BeforeBytes} 'AFTER' {$f.AfterBytes} 'OTHER' {$f.OtherBytes} }
                Write-FixtureBytes $f $stagePath $bytes
                $state = if ($applied) { 'APPLIED_BYTES_PRESENT' } else { 'ORIGINAL_BYTES_PRESENT' }
                $p = Invoke-CheckedPreview $f $state 'ManualInspection'
                Assert-Test (@($p.Blockers).Contains('StageAssociationUnproven')) 'Stage blocker missing'
                Assert-Equal @($p.Diagnostic.StageFiles).Count 1 'Stage evidence missing'
                Assert-Equal $p.Diagnostic.StageFiles[0].ContentMatch $match 'Stage bytes match'
                Assert-Equal $p.Diagnostic.StageFiles[0].Kind $stageKind 'Stage kind'
            }
        }
    }
}
Invoke-Test 'Multiple stages cannot justify cleanup or restore' {
    $f = New-Fixture -Applied
    foreach ($prefix in @('.typezero-combined-', '.typezero-combined-restore-')) {
        $stagePath = Join-Path ([IO.Path]::GetDirectoryName($f.Settings)) ($prefix + [guid]::NewGuid().ToString('N') + '.tmp')
        Write-FixtureBytes $f $stagePath $f.BeforeBytes
    }
    $p = Invoke-CheckedPreview $f 'APPLIED_BYTES_PRESENT' 'ManualInspection'
    Assert-Equal @($p.Diagnostic.StageFiles).Count 2 'All stage evidence must be retained'
}
Invoke-Test 'Missing receipt plus stage remains blocked' {
    $f = New-Fixture -NoReceipt
    $stage = Join-Path ([IO.Path]::GetDirectoryName($f.Settings)) ('.typezero-combined-' + [guid]::NewGuid().ToString('N') + '.tmp')
    Write-FixtureBytes $f $stage $f.AfterBytes
    $p = Invoke-CheckedPreview $f 'EVIDENCE_INCOMPLETE' 'ManualInspection'
    Assert-Test (@($p.Blockers).Contains('StageAssociationUnproven')) 'Unverified stage blocker missing'
}
Invoke-Test 'Execute is rejected before any diagnostic or writer action' {
    $f = New-Fixture
    Invoke-CheckedPreview $f '' '' -Arguments @{Execute=$true} -MustThrow -ThrowPattern 'parameter.*Execute'
}
Invoke-Test 'Nested test root is rejected without changing evidence' {
    $f = New-Fixture
    $nestedRoot = Join-Path $f.Root ('typezero-terminal-txn-' + [guid]::NewGuid().ToString('N'))
    [IO.Directory]::CreateDirectory($nestedRoot) | Out-Null
    Invoke-CheckedPreview $f '' '' -Arguments @{TestRoot=$nestedRoot} -MustThrow -ThrowPattern 'direct, specially named'
}
Invoke-Test 'Backup from another fixture is rejected without following it' {
    $f = New-Fixture
    $other = New-Fixture -Applied
    Invoke-CheckedPreview $f '' '' -AdditionalRoots @($other.Root) -Arguments @{BackupDirectory=$other.BackupDirectory} -MustThrow -ThrowPattern 'outside this test'
}
Invoke-Test 'Settings directory in place of file throws without changing evidence' {
    $f = New-Fixture -NoSettings
    [IO.Directory]::CreateDirectory($f.Settings) | Out-Null
    Invoke-CheckedPreview $f '' '' -MustThrow -ThrowPattern 'plain file'
}
Invoke-Test 'Diagnostic exception propagates unchanged' {
    $command = Get-Command Get-TypezeroOfflineTerminalCombinedRecoveryDiagnostic
    $savedDiagnostic = $command.ScriptBlock
    $script:ExpectedDiagnosticFailure = [IO.IOException]::new('Synthetic evidence-change failure')
    try {
        function Get-TypezeroOfflineTerminalCombinedRecoveryDiagnostic {
            param($TestRoot, $BackupDirectory)
            throw $script:ExpectedDiagnosticFailure
        }
        $caught = $null
        try { $null = Get-TypezeroOfflineTerminalCombinedRecoveryPreview -TestRoot 'unused' -BackupDirectory 'unused' }
        catch { $caught = $_ }
        Assert-Test ($null -ne $caught) 'Diagnostic failure was swallowed'
        Assert-Test ([object]::ReferenceEquals($caught.Exception, $script:ExpectedDiagnosticFailure)) 'Diagnostic exception was replaced'
    }
    finally { Set-Item -Path Function:Get-TypezeroOfflineTerminalCombinedRecoveryDiagnostic -Value $savedDiagnostic }
}

Write-Host ('SUMMARY preview: passed=' + $script:Passed + ' failed=' + $script:Failed + ' writerCalls=' + $script:WriterCalls)
[pscustomobject]@{
    Suite = 'RecoveryPreview'
    Passed = $script:Passed
    Failed = $script:Failed
    WriterCalls = $script:WriterCalls
    FixtureRoots = @($script:Roots.ToArray())
    Failures = @($script:Failures.ToArray())
} | ConvertTo-Json -Depth 8
if ($script:Failed -gt 0) { exit 1 }
