#requires -Version 7.3
[CmdletBinding()]
param([ValidateSet('All','ForeignEdit','JournalTamper')][string]$Suite = 'All')

# NETZACH only. Writes fresh TEMP evidence and synthetic fixtures. No cleanup,
# recovery, provider invocation, repository edits, or live ThemeEngine execution.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if (-not $IsWindows -or $env:COMPUTERNAME -cne 'NETZACH') {
    throw 'This checkpoint is restricted to NETZACH running PowerShell 7.3+ on Windows.'
}
$repo = 'G:\Forgejo\It-Works-On-My-Machine'
$relative = 'Netzach/PowerShell/ThemeEngine'
$moduleDir = Join-Path $repo $relative
$tempRoot = [IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetTempPath())
if ($tempRoot -ine 'C:\Users\miker\AppData\Local\Temp' -or
    [IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath($env:TEMP)) -ine $tempRoot) {
    throw 'Run outside the sandbox with the original NETZACH TEMP scope.'
}
$preparer = Join-Path $tempRoot 'typezero-coordinator-locked-4dcb263251d2443b97bf9129f5c9d98b\TypezeroFreshCoordinatorFixtureJournal-Locked.ps1'
$preparerHash = 'F582F8F09296B6E0419050F9A716BD87D748B5B780B4575BDA177C1634467178'
$sourceHashes = [ordered]@{
    'ThemeEngine.ps1' = '7B11DF6840389933F0FD4C6BC7D085BB5275B1E3C84003E1AE54B3CB69B50525'
    'FontWriter-WindowsTerminal.ps1' = 'DEA6EDEB661AE7E064723785C0635DC29816B85B1D34AF40E38F9681145D54C7'
    'FontMapping-WindowsTerminal.ps1' = 'C3A7A009E2153EE8292B1EB4DAE014B1A012E37313E7EC320182CFD002BA6C15'
    'FontProvider-WindowsTerminal.ps1' = '62FCFA11213B9D16D15A17C54944FE6A326614B4DA6AAC6B8BB7054748C95B29'
    'TerminalColorCompat-WindowsTerminal.ps1' = 'A18EC504E65BD451547B21DDAD7FBA1599051E1BF8139A3FD6FA3CC5B37367D5'
    'TerminalUnified-WindowsTerminal.ps1' = '8E143BFE889368EE12F568B2E293D3B3F95F4C1E9580D51DE5F40560FBA29DA4'
    'TerminalThemeBridge-WindowsTerminal.ps1' = 'A4EAAA697CE097B660E046BEE4093CC5FFA2541A70C312F2C3EB7CA4E4E0141F'
    'TerminalThemeFixture-WindowsTerminal.ps1' = '80DB9B24172B6AE2B8CB7F5D09B996F85596ECA4304E7B8AB6674DFF19068857'
    'TerminalCoordinatorRecovery-WindowsTerminal.ps1' = '1C20DDEC98B760A0A301DAD1DC4623E3FA08F49AE59C819802323EEE0C60902F'
    'TerminalCoordinatorReceipt-WindowsTerminal.ps1' = 'DF1FE6B9A40CE5E8ADD3A29962155220BFAD8794CEB4125EEF88A8159A4FB6AF'
    'TypezeroProviderFixtureEvidence.ps1' = 'FFC433A40BCECD707ED0C57AC56D88801CD008D5F8CB982EE8491A39BDBCE237'
    'TypezeroIntegrationPreflight.ps1' = '692B00314712FAF97DE941CAADFFECD923E3A55E0E453D4D879C08143AFE72AD'
    'TypezeroGuardedIntegrationEntry.ps1' = 'F71097A2CFFF032896A9399691BE1636D98161982290677553FDDFF0117248A4'
}
$untracked = @('FontWriter-WindowsTerminal.ps1','TerminalColorCompat-WindowsTerminal.ps1',
    'TerminalCoordinatorReceipt-WindowsTerminal.ps1','TerminalCoordinatorRecovery-WindowsTerminal.ps1',
    'TerminalThemeBridge-WindowsTerminal.ps1','TerminalThemeFixture-WindowsTerminal.ps1',
    'TerminalUnified-WindowsTerminal.ps1','TypezeroGuardedIntegrationEntry.ps1',
    'TypezeroIntegrationPreflight.ps1','TypezeroProviderFixtureEvidence.ps1')
$expectedStatus = @(" M $relative/ThemeEngine.ps1") + @($untracked | ForEach-Object { "?? $relative/$_" })
$names = @('settings.json','vim-main.vim','vim-lightline.vim','shell-current.ps1',
    'appearance.mock','history-previous.txt','history-current.txt')
$utf8 = [Text.UTF8Encoding]::new($false, $true)
$freshRoots = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
$mutationPaths = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
$cases = [Collections.Generic.List[object]]::new()

function Hash-File([string]$Path) { (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash }
function Assert-Equal($Actual, $Expected, [string]$Reason) {
    if ($Actual -cne $Expected) { throw "BLOCKER: $Reason; expected [$Expected], got [$Actual]." }
}
function Assert-Checkpoint {
    $branch = & git --no-optional-locks -C $repo branch --show-current
    if ($LASTEXITCODE -ne 0) { throw 'Cannot inspect branch.' }
    Assert-Equal $branch 'feature/themeengine-font-management' 'Branch'
    $head = & git --no-optional-locks -C $repo rev-parse HEAD
    if ($LASTEXITCODE -ne 0) { throw 'Cannot inspect HEAD.' }
    Assert-Equal $head '637354b66c757827830dd164e2a62115e11ce04c' 'HEAD'
    $status = @(& git --no-optional-locks -C $repo status --porcelain=v1 --untracked-files=all)
    if ($LASTEXITCODE -ne 0) { throw 'Cannot inspect worktree.' }
    Assert-Equal (@($status | Sort-Object) -join "`n") (@($expectedStatus | Sort-Object) -join "`n") 'Eleven-change checkpoint'
    & git --no-optional-locks -C $repo diff --cached --quiet
    if ($LASTEXITCODE -ne 0) { throw 'Index is not empty.' }
    foreach ($name in $sourceHashes.Keys) {
        Assert-Equal (Hash-File (Join-Path $moduleDir $name)) $sourceHashes[$name] "Source SHA256: $name"
    }
    Assert-Equal (Hash-File $preparer) $preparerHash 'Locked preparer SHA256'
    $font = Get-Content -LiteralPath 'C:\Users\miker\AppData\Local\Typezero\ThemeEngine\font-windows-terminal.json' -Raw | ConvertFrom-Json
    Assert-Equal $font.Enabled $false 'Fonts disabled'
}
function Assert-FunctionModule([string]$Path) {
    $tokens = $null; $parseErrors = $null
    $ast = [Management.Automation.Language.Parser]::ParseFile($Path,[ref]$tokens,[ref]$parseErrors)
    if (@($parseErrors).Count -ne 0 -or $null -ne $ast.BeginBlock -or
        $null -ne $ast.ProcessBlock -or $null -ne $ast.CleanBlock -or
        @($ast.EndBlock.Statements | Where-Object {
            $_ -isnot [Management.Automation.Language.FunctionDefinitionAst]
        }).Count -ne 0) { throw "Unsafe fixture module structure: $Path" }
}
function Get-TreeSnapshot([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { throw "Protected path missing: $Path" }
    $baseItem = Get-Item -LiteralPath $Path -Force
    $all = @($baseItem)
    if ($baseItem.PSIsContainer) { $all += @(Get-ChildItem -LiteralPath $Path -Recurse -Force) }
    @($all | Sort-Object FullName | ForEach-Object {
        if (($_.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "Protected snapshot rejects redirected path: $($_.FullName)"
        }
        if ($_.PSIsContainer) { 'D|' + $_.FullName }
        else { 'F|' + $_.FullName + '|' + $_.Length + '|' + (Hash-File $_.FullName) }
    }) -join "`n"
}
function Write-NewBytes([string]$Path,[byte[]]$Bytes) {
    Assert-TypezeroFontRecoveryPlainPath -Path $Path
    $parent = [IO.Path]::GetDirectoryName([IO.Path]::GetFullPath($Path))
    if (-not $freshRoots.Contains($parent)) { throw 'Writer requires a newly registered root.' }
    $stream = [IO.FileStream]::new($Path,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,
        [IO.FileShare]::None,4096,[IO.FileOptions]::WriteThrough)
    try { $stream.Write($Bytes,0,$Bytes.Length); $stream.Flush($true) }
    finally { $stream.Dispose() }
}
function New-PrivateDirectory([string]$Prefix) {
    $path = Join-Path $tempRoot ($Prefix + [guid]::NewGuid().ToString('N'))
    Assert-TypezeroFontRecoveryPlainPath -Path $path
    if (Test-Path -LiteralPath $path) { throw 'New fixture path already exists.' }
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
    [void]$freshRoots.Add($path)
    $path
}
function New-Pair([string]$Label) {
    $preflight = New-PrivateDirectory 'typezero-integration-preflight-'
    $settings = $utf8.GetBytes('{"syntheticFixtureOnly":true,"label":"' + $Label + '"}')
    $recovery = New-TypezeroFontRecoveryFixture -Bytes $settings
    [void]$freshRoots.Add($recovery)
    Write-NewBytes (Join-Path $preflight '.fixture') ($utf8.GetBytes('TYPEZERO_INTEGRATION_PREFLIGHT_V2'))
    $expected = [ordered]@{}; $candidates = [ordered]@{}
    foreach ($name in $names) {
        $bytes = if ($name -ceq 'settings.json') { $settings } else { $utf8.GetBytes("ORIGINAL:${name}:$Label") }
        Write-NewBytes (Join-Path $preflight $name) $bytes
        if ($name -cne 'settings.json') {
            Write-TypezeroCoordinatorFixtureFile -Path (Join-Path $recovery $name) -Bytes $bytes
        }
        $expected[$name] = Hash-File (Join-Path $preflight $name)
        $candidates[$name] = $utf8.GetBytes("CANDIDATE:${name}:$Label")
    }
    # Establish the lock before taking inventories so a later refusal cannot hide
    # even the creation of an otherwise harmless lock file.
    $handle = Open-TypezeroFontRecoveryLock -TestRoot $recovery; $handle.Dispose()
    [pscustomobject]@{ Label=$Label; Preflight=$preflight; Recovery=$recovery;
        Expected=$expected; Candidates=$candidates; Journal=$null }
}
function Prepare-Pair($Pair) {
    $Pair.Journal = New-TypezeroFreshCoordinatorFixtureJournal -PreflightRoot $Pair.Preflight `
        -RecoveryRoot $Pair.Recovery -ExpectedHashes $Pair.Expected -Candidates $Pair.Candidates
    Assert-Equal $Pair.Journal.CoordinatorState 'Prepared' 'Positive preparation control'
    Assert-Equal $Pair.Journal.RecoveryAuthorized $false 'Preparation recovery authorization'
    Assert-Equal $Pair.Journal.LiveActivationAuthorized $false 'Preparation activation authorization'
    Assert-Equal @(Get-ChildItem -LiteralPath $Pair.Journal.JournalDirectory -Force).Count 15 'Positive journal inventory'
    Assert-Targets $Pair ''
}
function Assert-Targets($Pair,[string]$Except) {
    foreach ($name in $names) {
        Assert-Equal (Hash-File (Join-Path $Pair.Preflight $name)) $Pair.Expected[$name] "Preflight preserved: $name"
        if ($name -cne $Except) {
            Assert-Equal (Hash-File (Join-Path $Pair.Recovery $name)) $Pair.Expected[$name] "Recovery target preserved: $name"
        }
    }
}
function Flip-FreshByte($Pair,[string]$Path) {
    $pathFull = [IO.Path]::GetFullPath($Path)
    $parent = [IO.Path]::GetDirectoryName($pathFull)
    $allowed = @((Join-Path $Pair.Preflight 'settings.json')) + @($names | ForEach-Object { Join-Path $Pair.Recovery $_ })
    if ($null -ne $Pair.Journal) {
        $allowed += @('vim-main_vim.before','history-current_txt.candidate','coordinator.dpapi' | ForEach-Object {
            Join-Path $Pair.Journal.JournalDirectory $_
        })
    }
    if (-not $freshRoots.Contains($Pair.Preflight) -or -not $freshRoots.Contains($Pair.Recovery) -or
        $pathFull -cnotin $allowed -or -not $mutationPaths.Add($pathFull)) {
        throw 'Mutation refused: requires a fresh pair and a single allowlisted injection.'
    }
    Assert-TypezeroFontRecoveryPlainPath -Path $pathFull
    $before = Hash-File $pathFull
    $stream = [IO.FileStream]::new($pathFull,[IO.FileMode]::Open,[IO.FileAccess]::ReadWrite,
        [IO.FileShare]::None,4096,[IO.FileOptions]::WriteThrough)
    try {
        [TypezeroFontRecoveryNative57F17]::AssertSinglePlain($stream.SafeFileHandle)
        $length = $stream.Length
        if ($length -lt 1) { throw 'Injection requires nonempty bytes.' }
        $stream.Position = $length - 1; $last = $stream.ReadByte()
        $stream.Position = $length - 1; $stream.WriteByte([byte]($last -bxor 1)); $stream.Flush($true)
        Assert-Equal $stream.Length $length 'Injection preserves length'
    } finally { $stream.Dispose() }
    $after = Hash-File $pathFull
    if ($before -ceq $after) { throw 'Injection did not change bytes.' }
    [pscustomobject]@{ Path=$pathFull; BeforeSHA256=$before; AfterSHA256=$after; Length=$length }
}
function Expect-Refusal([scriptblock]$Probe,[string]$Message,[switch]$Cryptographic) {
    $caught = $null
    try { & $Probe | Out-Null } catch { $caught = $_ }
    if ($null -eq $caught) { throw 'BLOCKER: Probe unexpectedly accepted corrupted input.' }
    if ($Cryptographic) {
        $cursor = $caught.Exception; $found = $false
        while ($null -ne $cursor) {
            if ($cursor -is [Security.Cryptography.CryptographicException]) { $found = $true }
            $cursor = $cursor.InnerException
        }
        if (-not $found) { throw "Unrelated exception cannot pass DPAPI corruption test: $caught" }
    } else { Assert-Equal $caught.Exception.Message $Message 'Specific refusal' }
    $caught.Exception.Message
}
function Assert-NoProof($Pair) {
    $proof = @(Get-ChildItem -LiteralPath $Pair.Recovery -Recurse -Force -File | Where-Object {
        $_.Name -match '^(receipt|displaced-|restore-|apply-)' })
    Assert-Equal $proof.Count 0 'No receipt, displacement or recovery proof'
}
function Assert-ReplayPreserved($Pair) {
    $before = Get-TreeSnapshot $Pair.Recovery
    $null = Expect-Refusal {
        New-TypezeroFreshCoordinatorFixtureJournal -PreflightRoot $Pair.Preflight -RecoveryRoot $Pair.Recovery `
            -ExpectedHashes $Pair.Expected -Candidates $Pair.Candidates
    } 'REFUSED: Recovery fixture entries are not a clean baseline.'
    $handle = Open-TypezeroFontRecoveryLock -TestRoot $Pair.Recovery; $handle.Dispose()
    Assert-Equal (Get-TreeSnapshot $Pair.Recovery) $before 'Replay refusal and released lock preserve bytes'
}
function Record-Case($Pair,$Mutation,[string]$Outcome,$Details) {
    Assert-NoProof $Pair
    $cases.Add([pscustomobject]@{ Name=$Pair.Label; PreflightRoot=$Pair.Preflight; RecoveryRoot=$Pair.Recovery;
        Journal=$Pair.Journal; Mutation=$Mutation; Outcome=$Outcome; Details=$Details;
        RecoveryAuthorized=$false; LiveActivationAuthorized=$false; Passed=$true })
    Write-Host "PASS: $($Pair.Label): $Outcome"
}

Assert-Checkpoint
$loadPaths = @('FontWriter-WindowsTerminal.ps1','TerminalCoordinatorRecovery-WindowsTerminal.ps1',
    'TypezeroIntegrationPreflight.ps1','TypezeroGuardedIntegrationEntry.ps1' | ForEach-Object { Join-Path $moduleDir $_ }) + @($preparer)
foreach ($path in $loadPaths) { Assert-FunctionModule $path }
. (Join-Path $moduleDir 'FontWriter-WindowsTerminal.ps1')
. (Join-Path $moduleDir 'TerminalCoordinatorRecovery-WindowsTerminal.ps1')
. (Join-Path $moduleDir 'TypezeroGuardedIntegrationEntry.ps1')
. $preparer

# Protect all existing coordinator roots and preflight fixtures, including earlier
# successful journals and the incomplete pre-seal diagnostic root. No old fixture
# is registered in freshRoots or eligible for test mutation.
$protectedPaths = [Collections.Generic.List[string]]::new()
foreach ($path in @($moduleDir,'C:\Users\miker\PS\ThemeEngine',
    'C:\Users\miker\AppData\Local\Typezero\ThemeEngine', (Join-Path $repo '.git\index'),
    $preparer,
    (Join-Path $tempRoot 'typezero-coordinator-preparer-v2-d3d86a9f767941eeba5d3893b53f0042'),
    (Join-Path $tempRoot 'typezero-interrupted-preparation-fa3267bbbdce4ab7b730e347e9c2c33a'))) {
    $protectedPaths.Add($path)
}
foreach ($directory in Get-ChildItem -LiteralPath $tempRoot -Directory -Filter 'typezero-*') {
    if ($directory.Name -cmatch '^typezero-integration-preflight-[a-f0-9]{32}$' -or
        ($directory.Name -cmatch '^typezero-font-recovery-test-[a-f0-9]{32}$' -and
        @(Get-ChildItem -LiteralPath $directory.FullName -Directory -Filter 'coordinator-*').Count -gt 0)) {
        $protectedPaths.Add($directory.FullName)
    }
}
foreach ($path in @('C:\Users\miker\AppData\Local\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json',
    'C:\Users\miker\AppData\Local\Packages\Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe\LocalState\settings.json',
    'C:\Users\miker\AppData\Local\Microsoft\Windows Terminal\settings.json')) {
    if (Test-Path -LiteralPath $path) { $protectedPaths.Add($path) }
}
$protectedBefore = [ordered]@{}
foreach ($path in $protectedPaths) { $protectedBefore[$path] = Get-TreeSnapshot $path }
$knownJournals = @(
    @('typezero-font-recovery-test-56874ee849c64aaa85ac3390f8cb61e5','31037baecbf946b3a34a0740a659bbdf','BF8748D166E7563F537ECB3D57235B14A5F2991686178745F52BE7788BF3E3BA'),
    @('typezero-font-recovery-test-42309d53678d4ee195204b8937d37f40','d254556af6124e2489c38fde0f1b136e','D4742CE5DF39EF307B136BD044B34E9817A83CF010BDC1C058EFE6864D307271'))
function Assert-KnownJournals {
    foreach ($known in $knownJournals) {
        $root = Join-Path $tempRoot $known[0]
        Assert-Equal (Hash-File (Join-Path $root ('coordinator-' + $known[1] + '\coordinator.dpapi'))) $known[2] 'Historical sealed journal'
        $state = Get-TypezeroCoordinatorFixtureRecoveryState -TestRoot $root -TransactionId $known[1]
        Assert-Equal $state.State 'Prepared' 'Historical prepared state'
        Assert-Equal $state.RecoveryAuthorized $false 'Historical recovery authorization'
        Assert-Equal @($state.Issues).Count 0 'Historical journal issues'
    }
    $partial = Join-Path $tempRoot 'typezero-font-recovery-test-c540fe87074a4e81bcb685c77990ba34\coordinator-9221847d65154b0399992f1eda3ac179'
    Assert-Equal @(Get-ChildItem -LiteralPath $partial -Force).Count 14 'Partial journal retained'
    Assert-Equal (Test-Path -LiteralPath (Join-Path $partial 'coordinator.dpapi')) $false 'Partial remains unsealed'
}
Assert-KnownJournals
$evidence = New-PrivateDirectory 'typezero-fixture-safety-'
Write-NewBytes (Join-Path $evidence 'Test-TypezeroFixtureSafety.ps1') ([IO.File]::ReadAllBytes($PSCommandPath))
Write-NewBytes (Join-Path $evidence 'protected-before.json') ($utf8.GetBytes(($protectedBefore | ConvertTo-Json -Depth 5)))
$failure = $null; $integrityFailure = $null
Write-Host "Evidence workspace: $evidence"
Write-Host 'PASS: Eleven-change checkpoint, thirteen historical SHA256 pins, fonts disabled, known journals preserved.'
try {
    if ($Suite -cin @('All','ForeignEdit')) {
        Write-Host '=== 57F.23.10.09.06.04 FOREIGN EDIT ==='
        foreach ($role in @('Preflight','Recovery')) {
            $pair = New-Pair ("before-prepare-" + $role.ToLowerInvariant())
            $target = if ($role -ceq 'Preflight') { Join-Path $pair.Preflight 'settings.json' } else { Join-Path $pair.Recovery 'settings.json' }
            $mutation = Flip-FreshByte $pair $target
            $beforePreflight = Get-TreeSnapshot $pair.Preflight; $beforeRecovery = Get-TreeSnapshot $pair.Recovery
            $message = if ($role -ceq 'Preflight') { 'REFUSED: Artifact changed: settings.json' } else { 'REFUSED: Recovery baseline changed: settings.json' }
            $detail = Expect-Refusal { New-TypezeroFreshCoordinatorFixtureJournal -PreflightRoot $pair.Preflight `
                -RecoveryRoot $pair.Recovery -ExpectedHashes $pair.Expected -Candidates $pair.Candidates } $message
            $handle = Open-TypezeroFontRecoveryLock -TestRoot $pair.Recovery; $handle.Dispose()
            Assert-Equal @(Get-ChildItem -LiteralPath $pair.Recovery -Directory).Count 0 'No journal on stale input'
            Assert-Equal (Get-TreeSnapshot $pair.Preflight) $beforePreflight 'Preflight refusal preserves edit'
            Assert-Equal (Get-TreeSnapshot $pair.Recovery) $beforeRecovery 'Recovery refusal preserves bytes'
            Record-Case $pair $mutation 'Specific stale-input refusal; no journal; lock released' $detail
        }
        foreach ($name in $names) {
            $pair = New-Pair ('foreign-' + $name.Replace('.','-')); Prepare-Pair $pair
            $preflightBefore = Get-TreeSnapshot $pair.Preflight
            $mutation = Flip-FreshByte $pair (Join-Path $pair.Recovery $name)
            $afterInjection = Get-TreeSnapshot $pair.Recovery
            $manifest = Read-TypezeroCoordinatorFixtureJournal -TestRoot $pair.Recovery -TransactionId $pair.Journal.TransactionId
            Assert-Equal $manifest.RecordedState 'Prepared' 'Manifest intent remains readable'
            $state = Get-TypezeroCoordinatorFixtureRecoveryState -TestRoot $pair.Recovery -TransactionId $pair.Journal.TransactionId
            Assert-Equal $state.State 'Conflicted' 'Foreign edit classification'
            Assert-Equal $state.ReadOnly $true 'Inspector is read-only'
            Assert-Equal $state.RecoveryAuthorized $false 'Foreign edit cannot authorize recovery'
            Assert-Equal @($state.Artifacts).Count 7 'Seven target observations'
            foreach ($row in $state.Artifacts) {
                $expectedPosition = if ($row.Target -ceq $name) { 'Unknown' } else { 'Before' }
                Assert-Equal $row.Position $expectedPosition "Position of $($row.Target)"
                Assert-Equal $row.ApplyEvidenceValid $false 'No apply proof'
                Assert-Equal $row.RestoreEvidenceValid $false 'No restore proof'
            }
            Assert-Targets $pair $name
            Assert-ReplayPreserved $pair
            Assert-Equal (Get-TreeSnapshot $pair.Preflight) $preflightBefore 'Preflight untouched'
            Assert-Equal (Get-TreeSnapshot $pair.Recovery) $afterInjection 'Inspection preserves foreign bytes and journal'
            Record-Case $pair $mutation 'Conflicted; edited target Unknown; six targets Before; replay refused' $state
        }
        Write-Host 'STEP 57F.23.10.09.06.04: FOREIGN EDIT REGRESSION COMPLETE'
    }
    if ($Suite -cin @('All','JournalTamper')) {
        Write-Host '=== 57F.23.10.09.06.05 JOURNAL TAMPER ==='
        foreach ($kind in @('Backup','Candidate','SealedManifest')) {
            $pair = New-Pair ('tamper-' + $kind.ToLowerInvariant()); Prepare-Pair $pair
            $preflightBefore = Get-TreeSnapshot $pair.Preflight
            $leaf = switch ($kind) { 'Backup' { 'vim-main_vim.before' } 'Candidate' { 'history-current_txt.candidate' } 'SealedManifest' { 'coordinator.dpapi' } }
            $mutation = Flip-FreshByte $pair (Join-Path $pair.Journal.JournalDirectory $leaf)
            $afterInjection = Get-TreeSnapshot $pair.Recovery
            if ($kind -ceq 'SealedManifest') {
                $readerDetail = Expect-Refusal { Read-TypezeroCoordinatorFixtureJournal -TestRoot $pair.Recovery `
                    -TransactionId $pair.Journal.TransactionId } '' -Cryptographic
                $stateDetail = Expect-Refusal { Get-TypezeroCoordinatorFixtureRecoveryState -TestRoot $pair.Recovery `
                    -TransactionId $pair.Journal.TransactionId } '' -Cryptographic
            } else {
                $manifest = Read-TypezeroCoordinatorFixtureJournal -TestRoot $pair.Recovery -TransactionId $pair.Journal.TransactionId
                Assert-Equal $manifest.RecordedState 'Prepared' 'Valid sealed intent still decodes'
                $readerDetail = 'Reader accepts unchanged sealed manifest; state validates artifact bytes.'
                $badTarget = if ($kind -ceq 'Backup') { 'vim-main.vim' } else { 'history-current.txt' }
                $stateDetail = Expect-Refusal { Get-TypezeroCoordinatorFixtureRecoveryState -TestRoot $pair.Recovery `
                    -TransactionId $pair.Journal.TransactionId } ("Coordinator immutable journal artifact corrupt: $badTarget")
            }
            Assert-Targets $pair ''
            Assert-ReplayPreserved $pair
            Assert-Equal (Get-TreeSnapshot $pair.Preflight) $preflightBefore 'Tamper preflight preserved'
            Assert-Equal (Get-TreeSnapshot $pair.Recovery) $afterInjection 'Refusals preserve injected journal bytes'
            Record-Case $pair $mutation 'Specific corruption refusal; all fourteen original targets preserved; replay refused' @($readerDetail,$stateDetail)
        }
        Write-Host 'STEP 57F.23.10.09.06.05: JOURNAL TAMPER REGRESSION COMPLETE'
    }
    $expectedCaseCount = switch ($Suite) { 'All' { 12 } 'ForeignEdit' { 9 } 'JournalTamper' { 3 } }
    Assert-Equal $cases.Count $expectedCaseCount 'Required independent case count'
} catch { $failure = $_.ToString() }
finally {
    try {
        Assert-Checkpoint; Assert-KnownJournals
        foreach ($path in $protectedBefore.Keys) {
            Assert-Equal (Get-TreeSnapshot $path) $protectedBefore[$path] "Protected inventory: $path"
        }
        Write-Host 'PASS: Final branch/index, thirteen source SHA256 checks, installed files, fonts, all prior journals and partial evidence unchanged.'
    } catch { $integrityFailure = $_.ToString() }
    $report = [ordered]@{
        Suite=$Suite; Computer=$env:COMPUTERNAME; PowerShell=$PSVersionTable.PSVersion.ToString();
        CompletedUtc=[DateTime]::UtcNow.ToString('o'); EvidenceRoot=$evidence;
        HarnessSHA256=(Hash-File $PSCommandPath); SourceSHA256=$sourceHashes;
        Branch='feature/themeengine-font-management'; HEAD='637354b66c757827830dd164e2a62115e11ce04c';
        ExpectedGitStatus=$expectedStatus; ProtectedPathCount=$protectedBefore.Count;
        ProtectedPaths=@($protectedBefore.Keys); Cases=@($cases.ToArray());
        RecoveryAuthorized=$false; LiveActivationAuthorized=$false; ExternalProviderInvoked=$false;
        Failure=$failure; IntegrityFailure=$integrityFailure;
        Passed=($null -eq $failure -and $null -eq $integrityFailure)
    }
    Write-NewBytes (Join-Path $evidence 'report.json') ($utf8.GetBytes(($report | ConvertTo-Json -Depth 15)))
    Write-Host "Report: $(Join-Path $evidence 'report.json')"
}
if ($null -ne $integrityFailure) { throw "PROTECTED INTEGRITY FAILURE: $integrityFailure" }
if ($null -ne $failure) { throw $failure }
Write-Host "PASS: $($cases.Count) independent disposable cases. RecoveryAuthorized=False; LiveActivationAuthorized=False."
Write-Output (Join-Path $evidence 'report.json')
