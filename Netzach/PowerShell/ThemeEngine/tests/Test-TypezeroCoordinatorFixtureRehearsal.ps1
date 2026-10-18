#requires -Version 7.3
<#
57F.23.10.09.09.03 regression. All writes are to NEW private TEMP fixtures.
Loads function-only modules, never ThemeEngine.ps1 or a historical test runner.
Fixtures and intentionally damaged evidence remain on disk. No cleanup, evidence
overwrite outside a new test fixture, production writer, or live authorization.
Run in a fresh Windows PowerShell 7.3+ process on local NTFS as the current user.
#>
[CmdletBinding()]
param(
    [string]$SourceDirectory = (Split-Path -Parent $PSScriptRoot),
    [string]$ReportPath
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if (-not $IsWindows) { throw 'Rehearsal regression requires Windows PowerShell 7.3+ and local NTFS TEMP.' }
$source = [IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath($SourceDirectory))
$utf8 = [Text.UTF8Encoding]::new($false, $true)
$targets = @('settings.json','vim-main.vim','vim-lightline.vim','shell-current.ps1',
    'appearance.mock','history-previous.txt','history-current.txt')
$ownedRoots = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
$cases = [Collections.Generic.List[object]]::new()
$pairs = [Collections.Generic.List[object]]::new()
$sourceHashes = [ordered]@{}
$failure = $null
$failureStack = $null
$startedUtc = [DateTime]::UtcNow
$reportFull = $null
$modules = @('FontWriter-WindowsTerminal.ps1','TerminalCoordinatorRecovery-WindowsTerminal.ps1',
    'TerminalCoordinatorReceipt-WindowsTerminal.ps1','TypezeroIntegrationPreflight.ps1',
    'TypezeroGuardedIntegrationEntry.ps1','TypezeroFreshCoordinatorFixtureJournal-Locked.ps1',
    'TerminalCoordinatorLifecycle-WindowsTerminal.ps1','TerminalCoordinatorRehearsal-WindowsTerminal.ps1')

function Assert-Equal($Actual, $Expected, [string]$Reason) {
    if ($Actual -cne $Expected) { throw "${Reason}: expected [$Expected], got [$Actual]." }
}
function Assert-Bytes([byte[]]$Actual, [byte[]]$Expected, [string]$Reason) {
    if ($Actual.Length -ne $Expected.Length) {
        throw "${Reason}: byte length $($Actual.Length), expected $($Expected.Length)."
    }
    for ($i=0; $i -lt $Expected.Length; $i++) {
        if ($Actual[$i] -ne $Expected[$i]) { throw "${Reason}: differing byte at offset $i." }
    }
}
function Get-FileHashText([string]$Path) {
    (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
}
function Add-PassedCase([string]$Name, $Pair, $Details) {
    $cases.Add([pscustomobject]@{
        Name=$Name; Passed=$true; FixtureRoot=$(if ($Pair) { $Pair.Recovery } else { $null }); Details=$Details
    })
    Write-Host ('PASS [{0:d3}] {1}' -f $cases.Count,$Name)
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
function New-Pair([string]$Label) {
    $preflight = New-PrivatePreflightDirectory
    $originals = [ordered]@{}; $candidates = [ordered]@{}; $expected = [ordered]@{}
    $bom8 = [Text.UTF8Encoding]::new($true,$true)
    $le16 = [Text.UnicodeEncoding]::new($false,$true,$true)
    $be16 = [Text.UnicodeEncoding]::new($true,$true,$true)
    $le32 = [Text.UTF32Encoding]::new($false,$true,$true)
    $be32 = [Text.UTF32Encoding]::new($true,$true,$true)
    # Deliberately opaque synthetic payloads: no parser or text round-trip may
    # normalize BOMs, CRLF/LF mixtures, non-ASCII, NULs, or invalid UTF-8 bytes.
    $originals['settings.json'] = $utf8.GetBytes("{`r`n  `"synthetic`": `"$Label-before`"`n}`r`n")
    $candidates['settings.json'] = [byte[]]($bom8.GetPreamble() + $bom8.GetBytes("{`n`"synthetic`":`"$Label-after`"`r`n}`n"))
    $originals['vim-main.vim'] = [byte[]]($bom8.GetPreamble() + $bom8.GetBytes("`" synthetic $Label café`nset background=dark`r`n"))
    $candidates['vim-main.vim'] = $utf8.GetBytes("`" synthetic $Label naïve`r`nset background=light`n")
    $originals['vim-lightline.vim'] = [byte[]]($le16.GetPreamble() + $le16.GetBytes("SYNTHETIC $Label BEFORE Ω`r`n終`n"))
    $candidates['vim-lightline.vim'] = [byte[]]($be16.GetPreamble() + $be16.GetBytes("SYNTHETIC $Label AFTER λ`n終`r`n"))
    $originals['shell-current.ps1'] = $utf8.GetBytes("# SYNTHETIC $Label BEFORE`r`n# never executable`n")
    $candidates['shell-current.ps1'] = $utf8.GetBytes("# SYNTHETIC $Label AFTER`n# never executable`r`n")
    $originals['appearance.mock'] = [byte[]](@(0,255,254,239,187,191,0,13,10) + @(0..255))
    $candidates['appearance.mock'] = [byte[]](@(255,0,192,193,128,254,0,10,13) + @(255..0))
    $originals['history-previous.txt'] = [byte[]]@(0)
    $candidates['history-previous.txt'] = [byte[]]@(255)
    $originals['history-current.txt'] = [byte[]]($be32.GetPreamble() + $be32.GetBytes("SYNTHETIC $Label BEFORE 🧪`r`n`n"))
    $candidates['history-current.txt'] = [byte[]]($le32.GetPreamble() + $le32.GetBytes("SYNTHETIC $Label AFTER 🧪`n`r`n"))
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
    $journal = New-TypezeroFreshCoordinatorFixtureJournal -PreflightRoot $preflight `
        -RecoveryRoot $recovery -ExpectedHashes $expected -Candidates $candidates
    $pair = [pscustomobject]@{
        Label=$Label; Preflight=$preflight; Recovery=$recovery; Originals=$originals;
        Candidates=$candidates; Expected=$expected; Journal=$journal;
        TransactionId=$journal.TransactionId; Folder=$journal.JournalDirectory;
        JournalSHA256=$journal.JournalSHA256
    }
    $pairs.Add($pair)
    Assert-Equal $journal.CoordinatorState 'Prepared' 'Fresh locked journal state'
    Assert-Equal $journal.RecoveryAuthorized $false 'Preparation recovery authorization'
    Assert-Equal $journal.LiveActivationAuthorized $false 'Preparation activation authorization'
    $pair
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
            # Record the link itself; never traverse its destination.
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
function Assert-SafetyFlags($Report) {
    Assert-Equal $Report.FixtureOnly $true 'Rehearsal fixture-only contract'
    foreach ($name in @('RecoveryAuthorized','LiveActivationAuthorized','GlobalRestorationCertified','ExternalProviderInvoked')) {
        Assert-Equal $Report.$name $false "Rehearsal/$name"
    }
}
function Assert-PayloadSet($Pair, [ValidateSet('Before','After')][string]$Position, [int]$AppliedPrefix = -1) {
    for ($i=0; $i -lt $targets.Count; $i++) {
        $name = $targets[$i]
        $after = if ($AppliedPrefix -ge 0) { $i -lt $AppliedPrefix } else { $Position -ceq 'After' }
        $wanted = if ($after) { $Pair.Candidates[$name] } else { $Pair.Originals[$name] }
        Assert-Bytes ([IO.File]::ReadAllBytes((Join-Path $Pair.Recovery $name))) $wanted "$($Pair.Label)/$name exact target bytes"
        Assert-Bytes ([IO.File]::ReadAllBytes((Join-Path $Pair.Preflight $name))) $Pair.Originals[$name] "$($Pair.Label)/$name preflight remains original"
        $safe = $name.Replace('.','_')
        Assert-Bytes ([IO.File]::ReadAllBytes((Join-Path $Pair.Folder ($safe + '.before')))) $Pair.Originals[$name] "$($Pair.Label)/$name immutable before"
        Assert-Bytes ([IO.File]::ReadAllBytes((Join-Path $Pair.Folder ($safe + '.candidate')))) $Pair.Candidates[$name] "$($Pair.Label)/$name immutable candidate"
    }
    Assert-Equal (Get-FileHashText (Join-Path $Pair.Folder 'coordinator.dpapi')) $Pair.JournalSHA256 'Sealed manifest retained byte-for-byte'
}
function Assert-Proofs($Pair, [int]$ApplyCount, [int]$RestoreCount) {
    for ($i=0; $i -lt $targets.Count; $i++) {
        $name = $targets[$i]; $safe = $name.Replace('.','_')
        foreach ($kind in @('apply','restore')) {
            $path = Join-Path $Pair.Folder ('displaced-' + $kind + '-complete-' + $safe + '.bin')
            # Restore proceeds in reverse over the applied prefix.
            $wanted = if ($kind -ceq 'apply') { $i -lt $ApplyCount }
                else { $i -lt $ApplyCount -and $i -ge ($ApplyCount - $RestoreCount) }
            Assert-Equal ([IO.File]::Exists($path)) $wanted "$($Pair.Label)/$kind/$name evidence presence"
            if ($wanted) {
                $bytes = if ($kind -ceq 'apply') { $Pair.Originals[$name] } else { $Pair.Candidates[$name] }
                Assert-Bytes ([IO.File]::ReadAllBytes($path)) $bytes "$($Pair.Label)/$kind/$name exact displacement bytes"
            }
        }
    }
}
function Assert-FullRestore($Pair) {
    Assert-PayloadSet $Pair Before
    Assert-Proofs $Pair 7 7
    $receipt = Test-TypezeroCoordinatorFixtureReceipt -TestRoot $Pair.Recovery -TransactionId $Pair.TransactionId
    Assert-Equal $receipt.ReceiptValid $true 'Published receipt independently verifies'
    Assert-Equal $receipt.RecoveryAuthorized $false 'Receipt grants no recovery authorization'
    $assessment = Get-TypezeroCoordinatorFixtureLifecycleAssessment -TestRoot $Pair.Recovery -TransactionId $Pair.TransactionId
    Assert-Equal $assessment.ObservedState 'OriginalUnresolved' 'Lifecycle original state with displacement evidence'
    Assert-Equal $assessment.RecordedState 'Prepared' 'Manifest remains recorded Prepared'
    Assert-Equal $assessment.ReceiptStatus 'Valid' 'Lifecycle published receipt status'
    Assert-Equal $assessment.ArtifactConsistency 'Consistent' 'Lifecycle artifact consistency'
    Assert-Equal $assessment.PendingReceiptPresent $false 'No pending receipt remains'
    Assert-SafetyFlags $assessment
}
function Invoke-PairApply($Pair, [int]$InterruptAfterReplacement = -1) {
    Invoke-TypezeroCoordinatorFixtureApplyRehearsal -TestRoot $Pair.Recovery `
        -TransactionId $Pair.TransactionId -ExpectedJournalSha256 $Pair.JournalSHA256 `
        -Execute -InterruptAfterReplacement $InterruptAfterReplacement -Confirm:$false
}
function Invoke-PairRestore($Pair, [int]$InterruptAfterReplacement = -1) {
    Restore-TypezeroCoordinatorFixtureRehearsal -TestRoot $Pair.Recovery `
        -TransactionId $Pair.TransactionId -ExpectedJournalSha256 $Pair.JournalSHA256 `
        -Execute -InterruptAfterReplacement $InterruptAfterReplacement -Confirm:$false
}
function Assert-Refusal([string]$Name, $Pair, [scriptblock]$Probe, [string]$MessagePattern) {
    $before = Get-TreeSnapshot @($Pair.Preflight,$Pair.Recovery)
    $caught = $null
    try { & $Probe | Out-Null } catch { $caught = $_ }
    if ($null -eq $caught) { throw "$Name unexpectedly succeeded." }
    if ($MessagePattern -and $caught.Exception.Message -cnotlike $MessagePattern) {
        throw "$Name wrong refusal: $($caught.Exception.Message)"
    }
    Assert-Equal (Get-TreeSnapshot @($Pair.Preflight,$Pair.Recovery)) $before "$Name preserves full fixture trees"
    Add-PassedCase $Name $Pair @{ Refusal=$caught.Exception.Message; CompleteTreeUnchanged=$true }
}
function Assert-Injected([string]$Name, $Pair, [scriptblock]$Probe, [int]$Boundary) {
    $before = if ($Boundary -eq 0) { Get-TreeSnapshot @($Pair.Preflight,$Pair.Recovery) } else { $null }
    $caught = $null
    try { & $Probe | Out-Null } catch { $caught = $_ }
    if ($null -eq $caught) { throw "$Name did not reach deterministic injection boundary $Boundary; operation returned normally." }
    if ($caught.Exception.Message -cnotlike 'INJECTED:*') {
        throw "$Name did not reach deterministic injection boundary $Boundary; $($caught.Exception.Message)"
    }
    if ($Boundary -eq 0) {
        Assert-Equal (Get-TreeSnapshot @($Pair.Preflight,$Pair.Recovery)) $before "$Name changes no tree entry at boundary zero"
    }
    Add-PassedCase $Name $Pair @{ Boundary=$Boundary; Injection=$caught.Exception.Message }
}
function Assert-Preview([string]$Name, $Pair, [scriptblock]$Probe) {
    $before = Get-TreeSnapshot @($Pair.Preflight,$Pair.Recovery)
    $report = & $Probe
    Assert-Equal $report.Status 'PREVIEW' "$Name status"
    Assert-SafetyFlags $report
    Assert-Equal (Get-TreeSnapshot @($Pair.Preflight,$Pair.Recovery)) $before "$Name preserves full fixture trees"
    Add-PassedCase $Name $Pair @{ Status=$report.Status; CompleteTreeUnchanged=$true }
}

try {
    if ($ReportPath) {
        $reportCandidate = [IO.Path]::GetFullPath($ReportPath)
        if ([IO.File]::Exists($reportCandidate) -or [IO.Directory]::Exists($reportCandidate)) {
            throw 'ReportPath must be new; refusing to overwrite evidence.'
        }
        if ($reportCandidate.StartsWith($source + '\',[StringComparison]::OrdinalIgnoreCase)) {
            throw 'ReportPath must be outside the source directory.'
        }
        if (-not [IO.Directory]::Exists([IO.Path]::GetDirectoryName($reportCandidate))) {
            throw 'ReportPath parent must already exist.'
        }
        $reportFull = $reportCandidate
    }
    foreach ($file in Get-ChildItem -LiteralPath $source -Filter '*.ps1' -Recurse -File) {
        $sourceHashes[$file.FullName] = Get-FileHashText $file.FullName
    }
    foreach ($name in $modules) {
        $path = Join-Path $source $name
        Assert-FunctionOnlyModule $path
        . $path
    }
    Initialize-TypezeroFontRecoveryNative
    Assert-Equal (Get-FileHashText (Join-Path $source 'TypezeroIntegrationPreflight.ps1')) `
        '692B00314712FAF97DE941CAADFFECD923E3A55E0E453D4D879C08143AFE72AD' `
        'Guarded preflight byte contract (canonical LF checkout required)'

    $f = New-Pair 'default-and-whatif'
    Assert-Preview 'Apply defaults to preview' $f {
        Invoke-TypezeroCoordinatorFixtureApplyRehearsal -TestRoot $f.Recovery `
            -TransactionId $f.TransactionId -ExpectedJournalSha256 $f.JournalSHA256
    }
    Assert-Preview 'Explicit Execute false preserves fixture' $f {
        Invoke-TypezeroCoordinatorFixtureApplyRehearsal -TestRoot $f.Recovery `
            -TransactionId $f.TransactionId -ExpectedJournalSha256 $f.JournalSHA256 -Execute:$false
    }
    Assert-Preview 'Apply Execute WhatIf preserves fixture' $f {
        Invoke-TypezeroCoordinatorFixtureApplyRehearsal -TestRoot $f.Recovery `
            -TransactionId $f.TransactionId -ExpectedJournalSha256 $f.JournalSHA256 -Execute -WhatIf
    }
    $r = Invoke-PairApply $f
    Assert-Equal $r.Status 'APPLIED' 'Full apply status'
    Assert-Equal $r.ReplacementCount 7 'Full apply replacement count'
    Assert-SafetyFlags $r
    Assert-PayloadSet $f After
    Assert-Proofs $f 7 0
    Add-PassedCase 'Seven real replacements preserve exact varied candidate bytes and original displacements' $f @{
        ReplacementCount=7; ByteComparisons='All seven targets, immutable inputs, preflight files, apply displacements'
    }
    Assert-Preview 'Restore defaults to preview' $f {
        Restore-TypezeroCoordinatorFixtureRehearsal -TestRoot $f.Recovery `
            -TransactionId $f.TransactionId -ExpectedJournalSha256 $f.JournalSHA256
    }
    Assert-Preview 'Restore Execute WhatIf preserves fixture' $f {
        Restore-TypezeroCoordinatorFixtureRehearsal -TestRoot $f.Recovery `
            -TransactionId $f.TransactionId -ExpectedJournalSha256 $f.JournalSHA256 -Execute -WhatIf
    }
    $r = Invoke-PairRestore $f
    Assert-Equal $r.Status 'RESTORED' 'Full restore status'
    Assert-Equal $r.ReplacementCount 7 'Full restore replacement count'
    Assert-SafetyFlags $r
    Assert-FullRestore $f
    Add-PassedCase 'Seven exact original byte restorations and independently valid receipt/lifecycle' $f @{
        ReplacementCount=7; ReceiptValid=$true; Encodings='UTF8 BOM/no BOM; mixed CRLF/LF; UTF16 LE/BE; UTF32 LE/BE; NUL; binary; single-byte'
    }
    $before = Get-TreeSnapshot @($f.Preflight,$f.Recovery)
    $r = Invoke-PairRestore $f
    Assert-Equal $r.Status 'ALREADY_RESTORED' 'Repeat restore status'
    Assert-Equal $r.ReplacementCount 0 'Repeat restore count'
    Assert-SafetyFlags $r
    Assert-Equal (Get-TreeSnapshot @($f.Preflight,$f.Recovery)) $before 'Repeat restore preserves receipt and evidence'
    Add-PassedCase 'Restored transaction idempotence preserves all evidence' $f @{ CompleteTreeUnchanged=$true }
    Assert-Refusal 'Apply refuses a restored transaction' $f { Invoke-PairApply $f }

    $f = New-Pair 'direct-core-case-normalization'
    $r = Invoke-TypezeroCoordinatorFixtureRehearsalCore -Operation apply -TestRoot $f.Recovery `
        -TransactionId $f.TransactionId -ExpectedJournalSha256 $f.JournalSHA256 -Execute -Confirm:$false
    Assert-Equal $r.Operation 'Apply' 'Direct core lowercase apply canonicalizes operation'
    Assert-Equal $r.Status 'APPLIED' 'Direct core lowercase apply status'
    Assert-SafetyFlags $r
    Assert-PayloadSet $f After
    Assert-Proofs $f 7 0
    $r = Invoke-TypezeroCoordinatorFixtureRehearsalCore -Operation restore -TestRoot $f.Recovery `
        -TransactionId $f.TransactionId -ExpectedJournalSha256 $f.JournalSHA256 -Execute -Confirm:$false
    Assert-Equal $r.Operation 'Restore' 'Direct core lowercase restore canonicalizes operation'
    Assert-SafetyFlags $r
    Assert-FullRestore $f
    Add-PassedCase 'Direct core lowercase operations normalize and exactly restore seven targets' $f @{ ExactBytes=$true; ReceiptValid=$true }

    foreach ($boundary in 0..7) {
        $f = New-Pair "apply-interrupt-$boundary"
        Assert-Injected "Apply interruption after $boundary replacements" $f { Invoke-PairApply $f $boundary } $boundary
        Assert-PayloadSet $f Before -AppliedPrefix $boundary
        Assert-Proofs $f $boundary 0
        $r = Invoke-PairApply $f
        Assert-Equal $r.ReplacementCount (7-$boundary) 'Apply resume only writes remaining suffix'
        Assert-SafetyFlags $r
        Assert-PayloadSet $f After
        Assert-Proofs $f 7 0
        $r = Invoke-PairRestore $f
        Assert-SafetyFlags $r
        Assert-FullRestore $f
        Add-PassedCase "Apply boundary $boundary resumes and restores exact seven-file bytes" $f @{
            Boundary=$boundary; ResumedReplacementCount=(7-$boundary); ReceiptValid=$true; ExactBytes=$true
        }
    }
    foreach ($boundary in 0..7) {
        $f = New-Pair "restore-interrupt-$boundary"
        $null = Invoke-PairApply $f
        Assert-Injected "Restore interruption after $boundary replacements" $f { Invoke-PairRestore $f $boundary } $boundary
        Assert-PayloadSet $f Before -AppliedPrefix (7-$boundary)
        Assert-Proofs $f 7 $boundary
        $r = Invoke-PairRestore $f
        Assert-Equal $r.ReplacementCount (7-$boundary) 'Restore resume only writes remaining prefix'
        Assert-SafetyFlags $r
        Assert-FullRestore $f
        Add-PassedCase "Restore boundary $boundary resumes to exact original bytes and valid receipt" $f @{
            Boundary=$boundary; ResumedReplacementCount=(7-$boundary); ReceiptValid=$true; ExactBytes=$true
        }
    }
    $f = New-Pair 'receipt-publication-gap'
    $null = Invoke-PairApply $f
    Assert-Injected 'Interruption before receipt publication retains all real restoration proofs' $f {
        Restore-TypezeroCoordinatorFixtureRehearsal -TestRoot $f.Recovery -TransactionId $f.TransactionId `
            -ExpectedJournalSha256 $f.JournalSHA256 -Execute -InterruptBeforeReceiptPublication -Confirm:$false
    } 7
    Assert-PayloadSet $f Before
    Assert-Proofs $f 7 7
    Assert-Equal ([IO.File]::Exists((Join-Path $f.Folder 'receipt.dpapi'))) $false 'Receipt gap has no published receipt'
    Assert-Equal ([IO.File]::Exists((Join-Path $f.Folder 'receipt.pending'))) $false 'Receipt gap has no pending receipt'
    $r = Invoke-PairRestore $f
    Assert-Equal $r.ReplacementCount 0 'Receipt gap resume replaces no restored target'
    Assert-FullRestore $f
    Add-PassedCase 'Receipt gap resume publishes only after exact restoration verification' $f @{ ReceiptValid=$true; ReplacementCount=0 }

    foreach ($prefix in 1..6) {
        $f = New-Pair "partial-apply-restore-$prefix"
        Assert-Injected "Partial apply $prefix interruption" $f { Invoke-PairApply $f $prefix } $prefix
        $r = Invoke-PairRestore $f
        Assert-Equal $r.Status 'RESTORED' 'Partial apply restoration status'
        Assert-Equal $r.ReplacementCount $prefix 'Partial restoration replaces only applied files'
        Assert-SafetyFlags $r
        Assert-PayloadSet $f Before
        Assert-Proofs $f $prefix $prefix
        Assert-Equal ([IO.File]::Exists((Join-Path $f.Folder 'receipt.dpapi'))) $false 'Partial run cannot mint full recovery receipt'
        Add-PassedCase "Restore partially applied prefix $prefix without false complete receipt" $f @{ ExactBytes=$true; ReceiptPublished=$false }
    }

    foreach ($operation in @('Apply','Restore')) {
        foreach ($target in $targets) {
            $f = New-Pair ("foreign-$operation-" + $target.Replace('.','_'))
            if ($operation -ceq 'Restore') { $null = Invoke-PairApply $f }
            Write-TestBytes (Join-Path $f.Recovery $target) ($utf8.GetBytes("SYNTHETIC FOREIGN $operation $target")) -Replace
            if ($operation -ceq 'Apply') {
                Assert-Refusal "Apply refuses foreign edit in $target before any replacement" $f { Invoke-PairApply $f }
            } else {
                Assert-Refusal "Restore refuses foreign edit in $target before any replacement" $f { Invoke-PairRestore $f }
            }
        }
    }
    foreach ($kind in @('journal','before','candidate')) {
        foreach ($operation in @('Apply','Restore')) {
            $f = New-Pair "corrupt-$kind-$operation"
            if ($operation -ceq 'Restore') { $null = Invoke-PairApply $f }
            $leaf = switch ($kind) {
                'journal' { 'coordinator.dpapi' }
                'before' { 'history-current_txt.before' }
                'candidate' { 'history-current_txt.candidate' }
            }
            Write-TestBytes (Join-Path $f.Folder $leaf) ($utf8.GetBytes("SYNTHETIC CORRUPT $kind")) -Replace
            if ($operation -ceq 'Apply') {
                Assert-Refusal "Apply rejects corrupt $kind and preserves every tree entry" $f { Invoke-PairApply $f }
            } else {
                Assert-Refusal "Restore rejects corrupt $kind and preserves every tree entry" $f { Invoke-PairRestore $f }
            }
        }
    }
    $f = New-Pair 'corrupt-apply-displacement'
    Assert-Injected 'Apply proof corruption setup' $f { Invoke-PairApply $f 3 } 3
    Write-TestBytes (Join-Path $f.Folder 'displaced-apply-complete-vim-main_vim.bin') ($utf8.GetBytes('SYNTHETIC CORRUPT APPLY PROOF')) -Replace
    Assert-Refusal 'Apply resume rejects corrupt displacement before suffix writes' $f { Invoke-PairApply $f }
    Assert-Refusal 'Restore rejects corrupt apply displacement before target writes' $f { Invoke-PairRestore $f }
    $f = New-Pair 'corrupt-restore-displacement'
    $null = Invoke-PairApply $f
    Assert-Injected 'Restore proof corruption setup' $f { Invoke-PairRestore $f 3 } 3
    Write-TestBytes (Join-Path $f.Folder 'displaced-restore-complete-history-current_txt.bin') ($utf8.GetBytes('SYNTHETIC CORRUPT RESTORE PROOF')) -Replace
    Assert-Refusal 'Restore resume rejects corrupt displacement before remaining writes' $f { Invoke-PairRestore $f }
    $f = New-Pair 'corrupt-published-receipt'
    $null = Invoke-PairApply $f; $null = Invoke-PairRestore $f
    Write-TestBytes (Join-Path $f.Folder 'receipt.dpapi') ($utf8.GetBytes('SYNTHETIC CORRUPT RECEIPT')) -Replace
    Assert-Refusal 'Restore refuses corrupt published receipt without replacing evidence' $f { Invoke-PairRestore $f }
    $f = New-Pair 'pending-receipt'
    $null = Invoke-PairApply $f
    Write-TestBytes (Join-Path $f.Folder 'receipt.pending') ($utf8.GetBytes('SYNTHETIC UNVERIFIED PENDING'))
    Assert-Refusal 'Restore preserves unverified pending receipt without promotion' $f { Invoke-PairRestore $f }

    $f = New-Pair 'missing-target'
    Remove-TestFile (Join-Path $f.Recovery 'history-current.txt')
    Assert-Refusal 'Missing target refuses before any apply replacement' $f { Invoke-PairApply $f }
    $f = New-Pair 'missing-immutable'
    Remove-TestFile (Join-Path $f.Folder 'history-current_txt.before')
    Assert-Refusal 'Missing immutable backup refuses before apply replacement' $f { Invoke-PairApply $f }
    $f = New-Pair 'unknown-journal-entry'
    Write-TestBytes (Join-Path $f.Folder 'unrecognized-evidence.bin') ($utf8.GetBytes('SYNTHETIC UNKNOWN'))
    Assert-Refusal 'Unknown journal entry is retained and refuses apply' $f { Invoke-PairApply $f }
    $f = New-Pair 'unknown-root-stage'
    Write-TestBytes (Join-Path $f.Recovery 'stage-abandoned-synthetic.tmp') ($utf8.GetBytes('SYNTHETIC ABANDONED'))
    Assert-Refusal 'Unknown root/staging entry refuses apply without cleanup' $f { Invoke-PairApply $f }
    $f = New-Pair 'hardlinked-target'
    $link = Assert-OwnedPath (Join-Path $f.Recovery 'history-current.txt')
    Remove-TestFile $link
    New-Item -ItemType HardLink -Path $link -Target (Join-Path $f.Preflight 'history-current.txt') | Out-Null
    Assert-Refusal 'Hardlinked target refuses before any replacement' $f { Invoke-PairApply $f }
    $f = New-Pair 'hardlinked-journal-artifact'
    $link = Assert-OwnedPath (Join-Path $f.Folder 'history-current_txt.candidate')
    Remove-TestFile $link
    New-Item -ItemType HardLink -Path $link -Target (Join-Path $f.Preflight 'history-current.txt') | Out-Null
    Assert-Refusal 'Hardlinked immutable journal artifact refuses before replacement' $f { Invoke-PairApply $f }
    $f = New-Pair 'junction-target'
    $link = Assert-OwnedPath (Join-Path $f.Recovery 'history-current.txt')
    Remove-TestFile $link
    New-Item -ItemType Junction -Path $link -Target $f.Preflight | Out-Null
    Assert-Refusal 'Junction target refuses without traversing or writing destination' $f { Invoke-PairApply $f }
    $f = New-Pair 'junction-journal-entry'
    $link = Assert-OwnedPath (Join-Path $f.Folder 'unrecognized-directory')
    New-Item -ItemType Junction -Path $link -Target $f.Preflight | Out-Null
    Assert-Refusal 'Junction journal evidence refuses and retains link' $f { Invoke-PairApply $f }

    $f = New-Pair 'lock-contention'
    $before = Get-TreeSnapshot @($f.Preflight,$f.Recovery)
    $lock = Open-TypezeroFontRecoveryLock -TestRoot $f.Recovery
    $caught = $null
    try { try { Invoke-PairApply $f | Out-Null } catch { $caught = $_ } }
    finally { $lock.Dispose() }
    if ($null -eq $caught) { throw 'Contended transaction lock unexpectedly allowed apply.' }
    Assert-Equal (Get-TreeSnapshot @($f.Preflight,$f.Recovery)) $before 'Lock contention leaves complete trees unchanged'
    Add-PassedCase 'Contended transaction lock refuses without writes' $f @{ Refusal=$caught.Exception.Message; CompleteTreeUnchanged=$true }

    $f = New-Pair 'boundary-refusals'
    Assert-Refusal 'Nonfixture source root refuses before writes' $f {
        Invoke-TypezeroCoordinatorFixtureApplyRehearsal -TestRoot $source -TransactionId $f.TransactionId `
            -ExpectedJournalSha256 $f.JournalSHA256 -Execute -Confirm:$false
    }
    Assert-Refusal 'Preflight fixture is not a recovery-write boundary' $f {
        Invoke-TypezeroCoordinatorFixtureApplyRehearsal -TestRoot $f.Preflight -TransactionId $f.TransactionId `
            -ExpectedJournalSha256 $f.JournalSHA256 -Execute -Confirm:$false
    }
    Assert-Refusal 'Transaction traversal identifier refuses before writes' $f {
        Invoke-TypezeroCoordinatorFixtureApplyRehearsal -TestRoot $f.Recovery -TransactionId '../outside' `
            -ExpectedJournalSha256 $f.JournalSHA256 -Execute -Confirm:$false
    }
    Assert-Refusal 'Alternate data stream root refuses before writes' $f {
        Invoke-TypezeroCoordinatorFixtureApplyRehearsal -TestRoot ($f.Recovery + ':untrusted') -TransactionId $f.TransactionId `
            -ExpectedJournalSha256 $f.JournalSHA256 -Execute -Confirm:$false
    }
    Assert-Refusal 'Journal pin mismatch refuses before writes' $f {
        Invoke-TypezeroCoordinatorFixtureApplyRehearsal -TestRoot $f.Recovery -TransactionId $f.TransactionId `
            -ExpectedJournalSha256 ('0'*64) -Execute -Confirm:$false
    }
    Assert-Refusal 'Missing mandatory journal pin refuses without prompting' $f {
        $arguments = @{ TestRoot=$f.Recovery; TransactionId=$f.TransactionId; ExpectedJournalSha256=''; Execute=$true; Confirm=$false }
        Invoke-TypezeroCoordinatorFixtureApplyRehearsal @arguments
    }
    foreach ($operation in @('Apply','Recover','Activate')) {
        Assert-Refusal "Guarded live $operation remains refused" $f {
            Invoke-TypezeroGuardedFixtureEntry -FixtureRoot $f.Preflight -ExpectedHashes $f.Expected -Operation $operation
        } 'REFUSED: Guarded integration permits inspection only.'
    }
} catch {
    $failure = $_.Exception.Message
    $failureStack = $_.ScriptStackTrace
    throw
} finally {
    $sourceUnchanged = $sourceHashes.Count -gt 0
    foreach ($path in $sourceHashes.Keys) {
        try {
            if (-not [IO.File]::Exists($path) -or (Get-FileHashText $path) -cne $sourceHashes[$path]) {
                $sourceUnchanged = $false
            }
        } catch { $sourceUnchanged = $false }
    }
    if ($sourceHashes.Count -gt 0 -and
        @(Get-ChildItem -LiteralPath $source -Filter '*.ps1' -Recurse -File).Count -ne $sourceHashes.Count) {
        $sourceUnchanged = $false
    }
    $result = [pscustomobject]@{
        Milestone='57F.23.10.09.09.03'; StartedUtc=$startedUtc.ToString('o'); FinishedUtc=[DateTime]::UtcNow.ToString('o');
        ComputerName=$env:COMPUTERNAME; UserSID=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value;
        PowerShellVersion=$PSVersionTable.PSVersion.ToString(); OSVersion=[Environment]::OSVersion.VersionString;
        TempPath=[IO.Path]::GetTempPath(); SourceDirectory=$source;
        Passed=($null -eq $failure -and $sourceUnchanged); CaseCount=$cases.Count; Failure=$failure;
        FailureStack=$failureStack; SourceFilesUnchanged=$sourceUnchanged;
        RecoveryAuthorized=$false; LiveActivationAuthorized=$false; ProductionWrites=$false;
        FixtureEvidenceRetained=$true; FixturePairCount=$pairs.Count;
        SourceSHA256=$sourceHashes; Cases=@($cases.ToArray()); FixtureRoots=@($ownedRoots | Sort-Object)
    }
    if ($reportFull) {
        # CreateNew is intentional: concurrent creation also refuses to overwrite.
        $bytes = $utf8.GetBytes(($result | ConvertTo-Json -Depth 12))
        $stream = [IO.FileStream]::new($reportFull,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
        try { $stream.Write($bytes,0,$bytes.Length); $stream.Flush($true) }
        finally { $stream.Dispose() }
        Write-Host "Report: $reportFull"
    }
    Write-Host "Fixture evidence retained ($($ownedRoots.Count) roots):"
    foreach ($root in @($ownedRoots | Sort-Object)) { Write-Host $root }
    if (-not $sourceUnchanged) { throw 'Regression detected a source hash/inventory change, or source verification did not complete.' }
}
Write-Host "PASS: $($cases.Count) cases; exact fixture bytes verified; source hashes unchanged; RecoveryAuthorized=False; LiveActivationAuthorized=False."
