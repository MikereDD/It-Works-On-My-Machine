#requires -Version 7.3
<#
57F.23.10.09.09.02 regression. Uses only NEW private TEMP fixtures.
Never loads ThemeEngine.ps1, calls an Apply/Recover/Activate writer or the receipt
publication API, or removes historical evidence. Synthetic byte/proof injections belong
to this test. Run in a fresh PowerShell process on local NTFS.
#>
[CmdletBinding()]
param(
    [string]$SourceDirectory = (Split-Path -Parent $PSScriptRoot),
    [string]$ReportPath
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if (-not $IsWindows) { throw 'Lifecycle regression requires Windows PowerShell 7.3+ and local NTFS TEMP.' }
$source = [IO.Path]::GetFullPath($SourceDirectory)
$utf8 = [Text.UTF8Encoding]::new($false, $true)
$targets = @('settings.json','vim-main.vim','vim-lightline.vim','shell-current.ps1',
    'appearance.mock','history-previous.txt','history-current.txt')
$ownedRoots = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
$cases = [Collections.Generic.List[object]]::new()
$pairs = [Collections.Generic.List[object]]::new()
$sourceHashes = [ordered]@{}
$failure = $null
$modules = @('FontWriter-WindowsTerminal.ps1','TerminalCoordinatorRecovery-WindowsTerminal.ps1',
    'TerminalCoordinatorReceipt-WindowsTerminal.ps1','TypezeroIntegrationPreflight.ps1',
    'TypezeroGuardedIntegrationEntry.ps1','TypezeroFreshCoordinatorFixtureJournal-Locked.ps1',
    'TerminalCoordinatorLifecycle-WindowsTerminal.ps1')

function Assert-Equal($Actual, $Expected, [string]$Reason) {
    if ($Actual -cne $Expected) { throw "${Reason}: expected [$Expected], got [$Actual]." }
}
function Get-FileHashText([string]$Path) {
    (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
}
function Assert-FunctionOnlyModule([string]$Path) {
    $tokens = $null; $parseErrors = $null
    $ast = [Management.Automation.Language.Parser]::ParseFile($Path,[ref]$tokens,[ref]$parseErrors)
    if (@($parseErrors).Count -ne 0 -or $null -ne $ast.BeginBlock -or
        $null -ne $ast.ProcessBlock -or $null -ne $ast.CleanBlock -or
        @($ast.EndBlock.Statements | Where-Object {
            $_ -isnot [Management.Automation.Language.FunctionDefinitionAst]
        }).Count -ne 0) { throw "Module must contain function definitions only: $Path" }
}
function Assert-OwnedPath([string]$Path) {
    $full = [IO.Path]::GetFullPath($Path)
    $found = $false
    foreach ($root in $ownedRoots) {
        if ($full.StartsWith($root + '\', [StringComparison]::OrdinalIgnoreCase)) {
            $found = $true; break
        }
    }
    if (-not $found) { throw "Test mutation requires a descendant of a newly owned fixture: $full" }
    Assert-TypezeroFontRecoveryPlainPath -Path $full
    $full
}
function Write-TestBytes([string]$Path, [byte[]]$Bytes, [switch]$Replace) {
    $full = Assert-OwnedPath $Path
    $mode = if ($Replace) { [IO.FileMode]::Truncate } else { [IO.FileMode]::CreateNew }
    $stream = [IO.FileStream]::new($full,$mode,[IO.FileAccess]::Write,[IO.FileShare]::None,
        4096,[IO.FileOptions]::WriteThrough)
    try {
        [TypezeroFontRecoveryNative57F17]::AssertSinglePlain($stream.SafeFileHandle)
        $stream.Write($Bytes,0,$Bytes.Length); $stream.Flush($true)
    } finally { $stream.Dispose() }
}
function Remove-TestFile([string]$Path) {
    $full = Assert-OwnedPath $Path
    if (-not [IO.File]::Exists($full)) { throw "Missing synthetic file: $full" }
    [IO.File]::Delete($full)
}
function New-PrivatePreflightDirectory {
    $path = Join-Path ([IO.Path]::GetTempPath()) ('typezero-integration-preflight-' + [guid]::NewGuid().ToString('N'))
    Assert-TypezeroFontRecoveryPlainPath -Path $path
    if (Test-Path -LiteralPath $path) { throw 'New synthetic directory already exists.' }
    $sid = [Security.Principal.WindowsIdentity]::GetCurrent().User
    $acl = [Security.AccessControl.DirectorySecurity]::new()
    $acl.SetOwner($sid); $acl.SetAccessRuleProtection($true,$false)
    foreach ($identity in @($sid,[Security.Principal.SecurityIdentifier]::new('S-1-5-18'))) {
        $acl.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new($identity,
            [Security.AccessControl.FileSystemRights]::FullControl,
            [Security.AccessControl.InheritanceFlags]'ContainerInherit,ObjectInherit',
            [Security.AccessControl.PropagationFlags]::None,[Security.AccessControl.AccessControlType]::Allow))
    }
    [IO.FileSystemAclExtensions]::Create([IO.DirectoryInfo]::new($path),$acl) | Out-Null
    [void]$ownedRoots.Add($path)
    $path
}
function New-Pair([string]$Label, [switch]$Unprepared) {
    $preflight = New-PrivatePreflightDirectory
    $originals = [ordered]@{}; $candidates = [ordered]@{}; $expected = [ordered]@{}
    foreach ($name in $targets) {
        $originals[$name] = $utf8.GetBytes("SYNTHETIC-ORIGINAL:${name}:$Label")
        $candidates[$name] = $utf8.GetBytes("SYNTHETIC-CANDIDATE:${name}:$Label")
    }
    $recovery = New-TypezeroFontRecoveryFixture -Bytes $originals['settings.json']
    [void]$ownedRoots.Add($recovery)
    Write-TestBytes (Join-Path $preflight '.fixture') ($utf8.GetBytes('TYPEZERO_INTEGRATION_PREFLIGHT_V2'))
    foreach ($name in $targets) {
        Write-TestBytes (Join-Path $preflight $name) $originals[$name]
        if ($name -cne 'settings.json') {
            Write-TypezeroCoordinatorFixtureFile -Path (Join-Path $recovery $name) -Bytes $originals[$name]
        }
        $expected[$name] = Get-TypezeroFontRecoveryHash -Bytes $originals[$name]
    }
    $pair = [pscustomobject]@{ Label=$Label; Preflight=$preflight; Recovery=$recovery;
        Originals=$originals; Candidates=$candidates; Expected=$expected; Journal=$null;
        TransactionId=([guid]::NewGuid().ToString('N')); Folder=$null }
    $pairs.Add($pair)
    if (-not $Unprepared) {
        $pair.Journal = New-TypezeroFreshCoordinatorFixtureJournal -PreflightRoot $preflight `
            -RecoveryRoot $recovery -ExpectedHashes $expected -Candidates $candidates
        $pair.TransactionId = $pair.Journal.TransactionId
        $pair.Folder = $pair.Journal.JournalDirectory
        Assert-Equal $pair.Journal.CoordinatorState 'Prepared' 'Locked preparation state'
        Assert-Equal $pair.Journal.RecoveryAuthorized $false 'Locked preparation recovery authorization'
        Assert-Equal $pair.Journal.LiveActivationAuthorized $false 'Locked preparation activation authorization'
    }
    $pair
}
function Write-Proof($Pair, [string]$Target, [ValidateSet('apply','restore')][string]$Kind,
    [ValidateSet('partial','complete')][string]$Round = 'complete', [switch]$Bad) {
    $bytes = if ($Bad) { $utf8.GetBytes('SYNTHETIC-BAD-PROOF') }
        elseif ($Kind -ceq 'apply') { $Pair.Originals[$Target] }
        else { $Pair.Candidates[$Target] }
    $leaf = 'displaced-' + $Kind + '-' + $Round + '-' + $Target.Replace('.','_') + '.bin'
    Write-TestBytes (Join-Path $Pair.Folder $leaf) $bytes
}
function Set-AppliedPrefix($Pair, [int]$Count) {
    for ($i=0; $i -lt $Count; $i++) {
        $name = $targets[$i]
        Write-TestBytes (Join-Path $Pair.Recovery $name) $Pair.Candidates[$name] -Replace
        Write-Proof $Pair $name apply
    }
}
function Set-CompleteRecoveryEvidence($Pair) {
    foreach ($name in $targets) { Write-Proof $Pair $name apply; Write-Proof $Pair $name restore }
}
function Write-PublishedReceipt($Pair) {
    $cipher = New-TypezeroCoordinatorFixtureReceiptCipher -TestRoot $Pair.Recovery -TransactionId $Pair.TransactionId
    Write-TestBytes (Join-Path $Pair.Folder 'receipt.dpapi') $cipher
}
function Get-TreeSnapshot([string[]]$Roots) {
    $records = [Collections.Generic.List[string]]::new()
    $pending = [Collections.Generic.Queue[string]]::new()
    foreach ($root in $Roots) { $pending.Enqueue($root) }
    while ($pending.Count -gt 0) {
        $path = $pending.Dequeue()
        $item = Get-Item -LiteralPath $path -Force
        $prefix = $item.FullName + '|' + [long]$item.Attributes + '|' + $item.LastWriteTimeUtc.Ticks
        if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            # Record the link itself; never walk into its destination.
            $records.Add('L|' + $prefix + '|' + (@($item.LinkTarget) -join ','))
        } elseif ($item.PSIsContainer) {
            $records.Add('D|' + $prefix)
            foreach ($child in Get-ChildItem -LiteralPath $path -Force) { $pending.Enqueue($child.FullName) }
        } else {
            $records.Add('F|' + $prefix + '|' + $item.Length + '|' + (Get-FileHashText $path))
        }
    }
    @($records | Sort-Object) -join "`n"
}
function Assert-SafetyContract($Report) {
    Assert-Equal $Report.ContractVersion 1 'Assessment contract'
    Assert-Equal $Report.Mode 'ReadOnlyFixtureLifecycleAssessment' 'Assessment mode'
    foreach ($name in @('FixtureOnly','ReadOnly')) { Assert-Equal $Report.$name $true $name }
    foreach ($name in @('RecoveryAuthorized','LiveActivationAuthorized','GlobalRestorationCertified','ExternalProviderInvoked')) {
        Assert-Equal $Report.$name $false $name
    }
    foreach ($code in @('RecoveryNotAuthorized','LiveActivationNotAuthorized')) {
        if ($code -cnotin @($Report.Blockers)) { throw "Missing permanent blocker: $code" }
    }
    foreach ($issue in @($Report.Issues)) {
        if ([string]::IsNullOrWhiteSpace([string]$issue.Code) -or
            [string]::IsNullOrWhiteSpace([string]$issue.Message)) { throw 'Issue lacks a code or message.' }
    }
}
function Assert-Assessment([string]$Name, $Pair, [hashtable]$Expected, [string[]]$Blockers = @(),
    [string[]]$AbsentBlockers = @()) {
    $before = Get-TreeSnapshot @($Pair.Preflight,$Pair.Recovery)
    $report = Get-TypezeroCoordinatorFixtureLifecycleAssessment -TestRoot $Pair.Recovery -TransactionId $Pair.TransactionId
    $after = Get-TreeSnapshot @($Pair.Preflight,$Pair.Recovery)
    Assert-Equal $after $before "$Name preserves tree inventory, bytes, attributes and LastWriteTime"
    Assert-SafetyContract $report
    foreach ($key in $Expected.Keys) { Assert-Equal $report.$key $Expected[$key] "$Name/$key" }
    foreach ($code in $Blockers) {
        if ($code -cnotin @($report.Blockers)) { throw "$Name missing blocker: $code" }
    }
    foreach ($code in $AbsentBlockers) {
        if ($code -cin @($report.Blockers)) { throw "$Name unexpected blocker: $code" }
    }
    $cases.Add([pscustomobject]@{ Name=$Name; Passed=$true; ObservedState=$report.ObservedState;
        ReceiptStatus=$report.ReceiptStatus; Blockers=@($report.Blockers); FixtureRoot=$Pair.Recovery })
    Write-Host ('PASS [{0:d2}] {1}: {2}/{3}' -f $cases.Count,$Name,$report.ObservedState,$report.ReceiptStatus)
    $report
}
function Assert-Refusal([string]$Name, [scriptblock]$Probe, [string]$Message) {
    $caught = $null
    try { & $Probe | Out-Null } catch { $caught = $_ }
    if ($null -eq $caught) { throw "$Name unexpectedly succeeded." }
    if ($Message) { Assert-Equal $caught.Exception.Message $Message "$Name refusal" }
    $cases.Add([pscustomobject]@{ Name=$Name; Passed=$true; Refusal=$caught.Exception.Message })
    Write-Host ('PASS [{0:d2}] {1}: refused' -f $cases.Count,$Name)
}

try {
    # Hash every source file including the unchanged historical test harness.
    foreach ($file in Get-ChildItem -LiteralPath $source -Filter '*.ps1' -Recurse -File) {
        $sourceHashes[$file.FullName] = Get-FileHashText $file.FullName
    }
    foreach ($name in $modules) {
        $path = Join-Path $source $name
        Assert-FunctionOnlyModule $path
        . $path
    }
    Initialize-TypezeroFontRecoveryNative
    $guardedPreflightHash = '692B00314712FAF97DE941CAADFFECD923E3A55E0E453D4D879C08143AFE72AD'
    Assert-Equal (Get-FileHashText (Join-Path $source 'TypezeroIntegrationPreflight.ps1')) `
        $guardedPreflightHash 'Guarded preflight byte contract (canonical LF checkout required)'

    $f = New-Pair 'prepared'
    $r = Assert-Assessment 'Prepared, no receipt' $f @{
        JournalStatus='Valid'; RecordedState='Prepared'; ObservedState='Prepared'; ReceiptStatus='Missing';
        ReceiptValid=$false; PublishedReceiptPresent=$false; PendingReceiptPresent=$false;
        ArtifactConsistency='Consistent'; JournalInventoryValid=$true
    } @('ReceiptMissing') @('JournalInvalid','ArtifactConflict')
    Assert-Equal @($r.Artifacts).Count 7 'Prepared canonical observations'

    $f = New-Pair 'partial'; Set-AppliedPrefix $f 3
    $null = Assert-Assessment 'Synthetic applied prefix' $f @{ObservedState='PartiallyApplied';ArtifactConsistency='Consistent'}
    $f = New-Pair 'applied'; Set-AppliedPrefix $f 7
    $null = Assert-Assessment 'Synthetic fully applied' $f @{ObservedState='Applied';ArtifactConsistency='Consistent'}
    $f = New-Pair 'original-unresolved'; Write-Proof $f 'settings.json' apply partial
    $null = Assert-Assessment 'Original with displacement evidence' $f @{ObservedState='OriginalUnresolved';ReceiptStatus='Missing'} @('ReceiptMissing')
    $f = New-Pair 'foreign'; Write-TestBytes (Join-Path $f.Recovery 'settings.json') ($utf8.GetBytes('SYNTHETIC-FOREIGN')) -Replace
    $null = Assert-Assessment 'Foreign target bytes' $f @{ObservedState='Conflicted';ArtifactConsistency='Conflicted'} @('ArtifactConflict')
    $f = New-Pair 'missing-target'; Remove-TestFile (Join-Path $f.Recovery 'vim-main.vim')
    $null = Assert-Assessment 'Missing target' $f @{ObservedState='Conflicted';ArtifactConsistency='Conflicted'} @('ArtifactConflict')
    $f = New-Pair 'non-prefix'; Write-TestBytes (Join-Path $f.Recovery 'vim-main.vim') $f.Candidates['vim-main.vim'] -Replace
    Write-Proof $f 'vim-main.vim' apply
    $null = Assert-Assessment 'Non-prefix applied position' $f @{ObservedState='Conflicted'} @('ArtifactConflict')
    $f = New-Pair 'after-no-proof'; Write-TestBytes (Join-Path $f.Recovery 'settings.json') $f.Candidates['settings.json'] -Replace
    $null = Assert-Assessment 'After bytes without displacement proof' $f @{ObservedState='Conflicted'} @('ArtifactConflict')
    $f = New-Pair 'bad-proof'; Write-Proof $f 'settings.json' apply complete -Bad
    $null = Assert-Assessment 'Corrupt displacement proof' $f @{ObservedState='Conflicted'} @('ArtifactConflict')
    $f = New-Pair 'missing-journal' -Unprepared
    $null = Assert-Assessment 'Absent journal directory' $f @{JournalStatus='Missing';ObservedState='Unavailable';ReceiptValid=$false} @('JournalMissing')
    $f = New-Pair 'missing-manifest'; Remove-TestFile (Join-Path $f.Folder 'coordinator.dpapi')
    $null = Assert-Assessment 'Absent journal manifest' $f @{JournalStatus='Missing';ObservedState='Unavailable'} @('JournalMissing')
    $f = New-Pair 'corrupt-manifest'; Write-TestBytes (Join-Path $f.Folder 'coordinator.dpapi') ($utf8.GetBytes('SYNTHETIC-INVALID-DPAPI')) -Replace
    $null = Assert-Assessment 'Corrupt sealed journal' $f @{JournalStatus='Invalid';ObservedState='Unavailable';ReceiptValid=$false} @('JournalInvalid')
    $f = New-Pair 'missing-immutable'; Remove-TestFile (Join-Path $f.Folder 'vim-main_vim.before')
    $r = Assert-Assessment 'Missing immutable artifact' $f @{JournalStatus='Valid';ObservedState='Unavailable';ArtifactConsistency='Unverified'} @('ArtifactInspectionFailed')
    Assert-Equal @($r.Artifacts).Count 0 'Unavailable inspection has no partial canonical observations'
    $f = New-Pair 'corrupt-immutable'; Write-TestBytes (Join-Path $f.Folder 'history-current_txt.candidate') ($utf8.GetBytes('SYNTHETIC-BAD-IMMUTABLE')) -Replace
    $null = Assert-Assessment 'Corrupt immutable artifact' $f @{JournalStatus='Valid';ObservedState='Unavailable';ArtifactConsistency='Unverified'} @('ArtifactInspectionFailed')
    $f = New-Pair 'pending'; Write-TestBytes (Join-Path $f.Folder 'receipt.pending') ($utf8.GetBytes('SYNTHETIC-PENDING'))
    $null = Assert-Assessment 'Pending receipt is unverified' $f @{ReceiptStatus='Pending';ReceiptValid=$false;PendingReceiptPresent=$true;PublishedReceiptPresent=$false} @('PendingReceipt')
    $f = New-Pair 'receipt'; Set-CompleteRecoveryEvidence $f; Write-PublishedReceipt $f
    $null = Assert-Assessment 'Complete evidence and valid published receipt' $f @{
        ObservedState='OriginalUnresolved';ReceiptStatus='Valid';ReceiptValid=$true;
        PublishedReceiptPresent=$true;PendingReceiptPresent=$false;JournalInventoryValid=$true
    } @() @('ReceiptMissing','ReceiptInvalid','PendingReceipt')
    $f = New-Pair 'receipt-and-pending'; Set-CompleteRecoveryEvidence $f; Write-PublishedReceipt $f
    Write-TestBytes (Join-Path $f.Folder 'receipt.pending') ($utf8.GetBytes('SYNTHETIC-PENDING'))
    $null = Assert-Assessment 'Published valid receipt plus pending evidence' $f @{
        ReceiptStatus='Valid';ReceiptValid=$true;PendingReceiptPresent=$true;JournalInventoryValid=$true
    } @('PendingReceipt') @('ReceiptInvalid','ReceiptMissing')
    $f = New-Pair 'bad-receipt'; Set-CompleteRecoveryEvidence $f
    Write-TestBytes (Join-Path $f.Folder 'receipt.dpapi') ($utf8.GetBytes('SYNTHETIC-CORRUPT-RECEIPT'))
    $null = Assert-Assessment 'Invalid published receipt bytes' $f @{ReceiptStatus='Invalid';ReceiptValid=$false} @('ReceiptInvalid')
    $f = New-Pair 'receipt-binding'; Set-CompleteRecoveryEvidence $f
    $other = New-Pair 'receipt-binding-other'; Set-CompleteRecoveryEvidence $other
    $foreignCipher = New-TypezeroCoordinatorFixtureReceiptCipher -TestRoot $other.Recovery -TransactionId $other.TransactionId
    Write-TestBytes (Join-Path $f.Folder 'receipt.dpapi') $foreignCipher
    $null = Assert-Assessment 'Receipt bound to another root and transaction' $f @{ReceiptStatus='Invalid';ReceiptValid=$false} @('ReceiptInvalid')
    $f = New-Pair 'receipt-manifest-binding'; Set-CompleteRecoveryEvidence $f; Write-PublishedReceipt $f
    $manifest = Read-TypezeroCoordinatorFixtureJournal -TestRoot $f.Recovery -TransactionId $f.TransactionId
    $oldCipher = Get-TypezeroFontRecoveryBytes -Path (Join-Path $f.Folder 'coordinator.dpapi') -Maximum 65536
    $plain = [Security.Cryptography.ProtectedData]::Unprotect($oldCipher,$null,[Security.Cryptography.DataProtectionScope]::CurrentUser)
    # Re-sealing identical valid manifest content changes its cipher digest only.
    $newCipher = [Security.Cryptography.ProtectedData]::Protect($plain,$null,[Security.Cryptography.DataProtectionScope]::CurrentUser)
    Write-TestBytes (Join-Path $f.Folder 'coordinator.dpapi') $newCipher -Replace
    $null = Assert-Assessment 'Receipt bound to exact journal cipher' $f @{JournalStatus='Valid';ObservedState='OriginalUnresolved';ReceiptStatus='Invalid';ReceiptValid=$false} @('ReceiptInvalid')
    $f = New-Pair 'receipt-proof-missing'; Set-CompleteRecoveryEvidence $f; Write-PublishedReceipt $f
    Remove-TestFile (Join-Path $f.Folder 'displaced-restore-complete-settings_json.bin')
    $null = Assert-Assessment 'Published receipt with missing complete proof' $f @{ReceiptStatus='Invalid';ReceiptValid=$false} @('ReceiptInvalid')
    $f = New-Pair 'unexpected-file'; Write-TestBytes (Join-Path $f.Folder 'unexpected.txt') ($utf8.GetBytes('SYNTHETIC-UNKNOWN'))
    $null = Assert-Assessment 'Unknown journal filename' $f @{JournalInventoryValid=$false} @('JournalInventoryInvalid')
    $f = New-Pair 'unknown-displacement'; Write-TestBytes (Join-Path $f.Folder 'displaced-unknown.bin') ($utf8.GetBytes('SYNTHETIC-UNKNOWN'))
    $null = Assert-Assessment 'Unknown displacement filename' $f @{ObservedState='Conflicted';JournalInventoryValid=$false} @('ArtifactConflict','JournalInventoryInvalid')
    $f = New-Pair 'evidence-directory'
    [void][IO.Directory]::CreateDirectory((Assert-OwnedPath (Join-Path $f.Folder 'displaced-apply-complete-settings_json.bin')))
    $null = Assert-Assessment 'Evidence-named directory' $f @{JournalInventoryValid=$false} @('JournalInventoryInvalid')
    $f = New-Pair 'receipt-directory'
    [void][IO.Directory]::CreateDirectory((Assert-OwnedPath (Join-Path $f.Folder 'receipt.dpapi')))
    $null = Assert-Assessment 'Published receipt name is a directory' $f @{ReceiptValid=$false;JournalInventoryValid=$false} @('JournalInventoryInvalid')
    $f = New-Pair 'hardlink'
    $link = Assert-OwnedPath (Join-Path $f.Folder 'displaced-apply-complete-settings_json.bin')
    New-Item -ItemType HardLink -Path $link -Target (Join-Path $f.Folder 'settings_json.before') | Out-Null
    $null = Assert-Assessment 'Hardlinked journal evidence rejected' $f @{ReceiptValid=$false;JournalInventoryValid=$false} @('JournalInventoryInvalid')
    $f = New-Pair 'junction'
    $link = Assert-OwnedPath (Join-Path $f.Folder 'displaced-apply-complete-settings_json.bin')
    New-Item -ItemType Junction -Path $link -Target $f.Preflight | Out-Null
    $null = Assert-Assessment 'Journal evidence junction rejected' $f @{ReceiptValid=$false;JournalInventoryValid=$false} @('JournalInventoryInvalid')
    $f = New-Pair 'no-lock'; Remove-TestFile (Join-Path $f.Recovery '.transaction.lock')
    $null = Assert-Assessment 'Assessment does not create a missing lock' $f @{ObservedState='Prepared';ReceiptStatus='Missing'}
    Assert-Equal ([IO.File]::Exists((Join-Path $f.Recovery '.transaction.lock'))) $false 'No lock created'

    $before = Get-TreeSnapshot @($f.Preflight,$f.Recovery)
    foreach ($operation in @('Apply','Recover','Activate')) {
        Assert-Refusal "Guarded $operation remains refused" {
            Invoke-TypezeroGuardedFixtureEntry -FixtureRoot $f.Preflight -ExpectedHashes $f.Expected -Operation $operation
        } 'REFUSED: Guarded integration permits inspection only.'
    }
    Assert-Refusal 'Nonfixture root rejected before reporting' {
        Get-TypezeroCoordinatorFixtureLifecycleAssessment -TestRoot $source -TransactionId $f.TransactionId
    }
    Assert-Refusal 'Invalid transaction path rejected before reporting' {
        Get-TypezeroCoordinatorFixtureLifecycleAssessment -TestRoot $f.Recovery -TransactionId '../outside'
    }
    Assert-Equal (Get-TreeSnapshot @($f.Preflight,$f.Recovery)) $before 'Refusals preserve all fixture evidence'
} catch {
    $failure = $_.Exception.Message
    throw
} finally {
    $sourceUnchanged = $true
    foreach ($path in $sourceHashes.Keys) {
        if (-not [IO.File]::Exists($path) -or (Get-FileHashText $path) -cne $sourceHashes[$path]) {
            $sourceUnchanged = $false
        }
    }
    $result = [pscustomobject]@{
        Milestone='57F.23.10.09.09.02'; ComputerName=$env:COMPUTERNAME;
        PowerShellVersion=$PSVersionTable.PSVersion.ToString(); Passed=($null -eq $failure -and $sourceUnchanged);
        CaseCount=$cases.Count; Failure=$failure; SourceFilesUnchanged=$sourceUnchanged;
        RecoveryAuthorized=$false; LiveActivationAuthorized=$false; FixtureEvidencePreserved=($null -eq $failure);
        SourceSHA256=$sourceHashes; Cases=@($cases.ToArray()); FixtureRoots=@($ownedRoots | Sort-Object)
    }
    if ($ReportPath) {
        $reportFull = [IO.Path]::GetFullPath($ReportPath)
        if ([IO.File]::Exists($reportFull) -or [IO.Directory]::Exists($reportFull)) {
            throw 'ReportPath must be new; refusing to overwrite evidence.'
        }
        [IO.File]::WriteAllText($reportFull,($result | ConvertTo-Json -Depth 12),$utf8)
        Write-Host "Report: $reportFull"
    }
    Write-Host "Fixture evidence retained ($($ownedRoots.Count) roots):"
    foreach ($root in @($ownedRoots | Sort-Object)) { Write-Host $root }
    if (-not $sourceUnchanged) { throw 'Regression detected a source hash change.' }
}
Write-Host "PASS: $($cases.Count) cases; source hashes unchanged; RecoveryAuthorized=False; LiveActivationAuthorized=False."
