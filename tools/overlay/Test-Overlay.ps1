#requires -Version 7.3
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$WorkRoot,
    [string]$ReportPath,
    [string]$Python = 'python',
    # Qualified reporting only: default remains strict when native link fixtures cannot be created.
    [switch]$RecordUnavailableLinkTests
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if (-not $IsWindows) { throw 'Overlay installer fixtures require Windows.' }
$run = Join-Path ([IO.Path]::GetFullPath($WorkRoot)) ('overlay-fixtures-' + [guid]::NewGuid().ToString('N'))
$null = [IO.Directory]::CreateDirectory($run)
$results = [Collections.Generic.List[object]]::new()
$utf8 = [Text.UTF8Encoding]::new($false)
$engine = 'Netzach/PowerShell/ThemeEngine'
$a = "$engine/OverlayFixtureA.ps1"
$b = "$engine/OverlayFixtureB.ps1"
$added = "$engine/OverlayAdded.ps1"
$source = Join-Path $run 'source'
$null = [IO.Directory]::CreateDirectory((Join-Path $source $engine))
function Write-Text([string]$Path,[string]$Text) { [IO.File]::WriteAllText($Path,$Text,$script:utf8) }
function Assert-Test([bool]$Condition,[string]$Name) {
    if (-not $Condition) { throw "FAILED: $Name" }
    $script:results.Add([pscustomobject]@{Name=$Name;Passed=$true})
}
function Git-Fixture([string]$Root,[string[]]$Arguments) {
    $output = & git -C $Root @Arguments 2>&1
    if ($LASTEXITCODE -ne 0) { throw "Fixture git failed: $output" }
    return ($output -join "`n").Trim()
}
function Hash-File([string]$Path) { (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash }
function Get-GitMetadataSnapshot([string]$Target) {
    # A linked worktree has a .git pointer file, a private gitdir and a shared commondir.
    # Resolve both with optional locks disabled; include the pointer as evidence too.
    $gitRoot = Git-Fixture $Target @('rev-parse','--path-format=absolute','--git-dir')
    $commonRoot = Git-Fixture $Target @('rev-parse','--path-format=absolute','--git-common-dir')
    $roots = @($gitRoot,$commonRoot) | Select-Object -Unique
    $items = [Collections.Generic.Dictionary[string,object]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($metadataRoot in $roots) {
        foreach ($item in (@((Get-Item -Force -LiteralPath $metadataRoot)) + @(Get-ChildItem -Force -Recurse -LiteralPath $metadataRoot))) {
            $items[$item.FullName] = $item
        }
    }
    $pointer = Get-Item -Force -LiteralPath (Join-Path $Target '.git')
    if (-not $pointer.PSIsContainer) { $items[$pointer.FullName] = $pointer }
    $snapshot = foreach ($item in ($items.Values | Sort-Object FullName)) {
        [ordered]@{Path=$item.FullName;Directory=$item.PSIsContainer;
            Length=if($item.PSIsContainer){0}else{$item.Length};
            Sha256=if($item.PSIsContainer){$null}else{Hash-File $item.FullName};
            WriteTicks=$item.LastWriteTimeUtc.Ticks;CreationTicks=$item.CreationTimeUtc.Ticks;
            Attributes=[int]$item.Attributes}
    }
    return ConvertTo-Json -InputObject @($snapshot) -Depth 5 -Compress
}
function Expect-Refusal([scriptblock]$Call,[string]$Name) {
    $refused = $false
    try { & $Call | Out-Null } catch { $refused = $true }
    Assert-Test $refused $Name
}
function Record-UnavailableLinkCreation($Failure,[string]$Name) {
    $denied = $false
    $exception = $Failure.Exception
    while ($null -ne $exception) {
        if ($exception -is [UnauthorizedAccessException] -or $exception.HResult -eq -2147024891 -or
            ($exception -is [ComponentModel.Win32Exception] -and $exception.NativeErrorCode -eq 5)) { $denied = $true }
        $exception = $exception.InnerException
    }
    if (-not $script:RecordUnavailableLinkTests -or -not $denied) { throw $Failure }
    $script:results.Add([pscustomobject]@{Name=$Name;Passed=$false;Unavailable=$true;
        Reason='Windows denied native link fixture creation; installer link rejection was not executed.';
        Error=$Failure.Exception.Message})
}
function New-BaselineRepository([string]$Root) {
    $null = [IO.Directory]::CreateDirectory((Join-Path $Root $script:engine))
    Write-Text (Join-Path $Root '.gitattributes') "*.ps1 -text`n"
    Write-Text (Join-Path $Root $script:a) "# baseline-a`n"
    Write-Text (Join-Path $Root $script:b) "# baseline-b`n"
    $null = Git-Fixture $Root @('init','--quiet')
    $null = Git-Fixture $Root @('config','user.email','overlay-fixture@example.invalid')
    $null = Git-Fixture $Root @('config','user.name','Disposable Overlay Fixture')
    $null = Git-Fixture $Root @('config','commit.gpgsign','false')
    $null = Git-Fixture $Root @('add','.')
    $authorDate = [Environment]::GetEnvironmentVariable('GIT_AUTHOR_DATE','Process')
    $committerDate = [Environment]::GetEnvironmentVariable('GIT_COMMITTER_DATE','Process')
    try {
        [Environment]::SetEnvironmentVariable('GIT_AUTHOR_DATE','2020-01-01T00:00:00Z','Process')
        [Environment]::SetEnvironmentVariable('GIT_COMMITTER_DATE','2020-01-01T00:00:00Z','Process')
        $null = Git-Fixture $Root @('commit','--quiet','-m','Disposable baseline')
    } finally {
        [Environment]::SetEnvironmentVariable('GIT_AUTHOR_DATE',$authorDate,'Process')
        [Environment]::SetEnvironmentVariable('GIT_COMMITTER_DATE',$committerDate,'Process')
    }
}
function New-Target([string]$Name) {
    $target = Join-Path $script:run $Name
    # Build the same real baseline independently; no Git transport, live repository, or .git copy.
    New-BaselineRepository $target
    if ((Git-Fixture $target @('rev-parse','HEAD')) -cne $script:base) { throw 'Disposable fixture baseline SHA differs.' }
    Write-Text (Join-Path $target '.typezero-overlay-fixture') 'TypezeroOverlayDisposableFixtureV1'
    return $target
}
function New-Package([string]$Name) {
    $folder = Join-Path $script:run $Name
    Expand-Archive -LiteralPath $script:archive -DestinationPath $folder
    return $folder
}
function Invoke-Installer([string]$Target,[hashtable]$Options=@{}) {
    & $script:installer -TargetRoot $Target -PackageRoot $script:package @Options
}
try {
    # Compare the actual implementations against the same path corpus without executing an installer.
    $policyCases = @(
        @{Path="$engine/NewFixture.ps1";Allowed=$true},
        @{Path='tools/overlay/nested/Safe-File_1.2.py';Allowed=$true},
        @{Path="$engine/.fixture.md";Allowed=$true},
        @{Path="$engine/New Fixture.ps1";Allowed=$false},
        @{Path="$engine/NewFixture.PS1";Allowed=$false},
        @{Path="$engine/caf$([char]0xE9).ps1";Allowed=$false},
        @{Path='netzach/PowerShell/ThemeEngine/Case.ps1';Allowed=$false},
        @{Path="$engine//Double.ps1";Allowed=$false},
        @{Path="$engine/./Dot.ps1";Allowed=$false},
        @{Path="$engine/../Escape.ps1";Allowed=$false},
        @{Path="$engine/Trailing./File.ps1";Allowed=$false},
        @{Path="$engine/CON.ps1";Allowed=$false},
        @{Path="$engine/com0/Device.md";Allowed=$false},
        @{Path="$engine/File.ps1:stream";Allowed=$false},
        @{Path='tools\overlay\Backslash.ps1';Allowed=$false},
        @{Path='/tools/overlay/Absolute.ps1';Allowed=$false},
        @{Path="tools/overlay/Line`nBreak.md";Allowed=$false}
    )
    $caseFile = Join-Path $run 'path-policy.json'
    Write-Text $caseFile (ConvertTo-Json -InputObject @($policyCases.Path))
    $probe = Join-Path $run 'probe-policy.py'
    Write-Text $probe @'
import importlib.util
import json
import sys
sys.dont_write_bytecode = True
spec = importlib.util.spec_from_file_location("overlay_builder", sys.argv[1])
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
accepted = []
for value in json.loads(open(sys.argv[2], encoding="utf-8").read()):
    try:
        module.safe_path(value)
        accepted.append(True)
    except ValueError:
        accepted.append(False)
print(json.dumps(accepted))
'@
    $builderPolicy = & $Python $probe (Join-Path $PSScriptRoot 'build_overlay.py') $caseFile
    if ($LASTEXITCODE -ne 0) { throw 'Builder path policy probe failed.' }
    $builderAccepted = @($builderPolicy | ConvertFrom-Json)
    $tokens = $null; $parseErrors = $null
    $ast = [Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot 'Install-Overlay.ps1'),[ref]$tokens,[ref]$parseErrors)
    if ($parseErrors.Count) { throw 'Installer parse failed during path policy check.' }
    $pathFunction = $ast.Find({param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -ceq 'Assert-Relative'},$true)
    if ($null -eq $pathFunction) { throw 'Installer path policy missing.' }
    . ([scriptblock]::Create($pathFunction.Extent.Text))
    for ($i=0; $i -lt $policyCases.Count; $i++) {
        $installerAccepted = $true
        try { Assert-Relative $policyCases[$i].Path } catch { $installerAccepted = $false }
        Assert-Test ($builderAccepted[$i] -eq $policyCases[$i].Allowed -and $installerAccepted -eq $policyCases[$i].Allowed) "Builder and installer path policy agrees for case $i"
    }
    New-BaselineRepository $source
    $base = Git-Fixture $source @('rev-parse','HEAD')
    $limitProbe = Join-Path $run 'probe-build-limits.py'
    Write-Text $limitProbe @'
import importlib.util
from pathlib import Path
import sys
sys.dont_write_bytecode = True
spec = importlib.util.spec_from_file_location("overlay_limits", sys.argv[1])
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
root = Path(sys.argv[2])
output = root.parent / "refused-limits-output"
base = "1" * 40
prefix = "Netzach/PowerShell/ThemeEngine/"
def refused(call, message):
    try:
        call()
    except ValueError as error:
        assert message in str(error), str(error)
    else:
        raise AssertionError("Build limit accepted: " + message)
    assert not output.exists(), "Refused build created output evidence"
oversize = root / (prefix + "TooLarge.ps1")
with oversize.open("xb") as stream:
    stream.write(b"x" * (4194304 + 1))
refused(lambda: module.regular_bytes(root, prefix + "TooLarge.ps1"), "File too large")
module.git = lambda *args, **kwargs: base.encode()
module.baseline_bytes = lambda *args: None
module.regular_bytes = lambda *args: b"x" * 4194304
refused(lambda: module.safe_path(module.PROTECTED[0].replace("Typezero", "typezero")), "Pinned module")
refused(lambda: module.build(root, base, "limits", [prefix + "case.ps1", prefix + "Case.ps1"], output), "case-insensitively unique")
refused(lambda: module.build(root, base, "limits", [prefix + "case.ps1", prefix + "Case.ps1/Child.md"], output), "prefix collision")
refused(lambda: module.build(root, base, "limits", [prefix + str(i) + ".ps1" for i in range(1001)], output), "1-1000")
refused(lambda: module.build(root, base, "limits", [prefix + str(i) + ".ps1" for i in range(17)], output), "64 MiB")
module.regular_bytes = lambda *args: b"x"
refused(lambda: module.build(root, base, "limits", [prefix + "x" * 1048576 + ".ps1"], output), "1 MiB")
# Exercise baseline_bytes' own limit with Git-filter output, before any backup can be built.
spec.loader.exec_module(module)
module.git = lambda root, *args, **kwargs: b"100644 blob fixture" if args[0] == "ls-tree" else b"x" * 4194305
refused(lambda: module.baseline_bytes(root, base, prefix + "Baseline.ps1"), "Baseline file too large")
print("Passed")
'@
    $limitResult = & $Python $limitProbe (Join-Path $PSScriptRoot 'build_overlay.py') $source
    Assert-Test ($LASTEXITCODE -eq 0 -and $limitResult -ceq 'Passed') 'Builder refuses pinned aliases, case/prefix collisions, oversized files, baseline backups, counts, totals, and manifests before output creation'
    $baselineA = Hash-File (Join-Path $source $a)
    $baselineB = Hash-File (Join-Path $source $b)
    $null = [IO.Directory]::CreateDirectory((Join-Path $source 'tools/overlay'))
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'Install-Overlay.ps1') -Destination (Join-Path $source 'tools/overlay/Install-Overlay.ps1')
    Write-Text (Join-Path $source $a) "# candidate-a`n"
    Write-Text (Join-Path $source $b) "# candidate-b`n"
    Write-Text (Join-Path $source $added) "# added fixture only`n"
    $buildArgs = @((Join-Path $PSScriptRoot 'build_overlay.py'),'--repository',$source,'--base',$base,
        '--version','fixture-v1','--include',$a,'--include',$b,'--include',$added)
    $output1 = Join-Path $run 'build1'
    $output2 = Join-Path $run 'build2'
    $buildJson = & $Python @buildArgs --output-dir $output1
    if ($LASTEXITCODE -ne 0) { throw 'Initial fixture package build failed.' }
    $build = $buildJson | ConvertFrom-Json
    $archive = $build.Archive
    $again = & $Python @buildArgs --output-dir $output2
    if ($LASTEXITCODE -ne 0) { throw 'Repeat fixture package build failed.' }
    $second = $again | ConvertFrom-Json
    Assert-Test ((Hash-File $archive) -ceq (Hash-File $second.Archive)) 'Builder emits byte-identical ZIPs for identical input'
    & $Python @buildArgs --output-dir $output1 2>&1 | Out-Null
    Assert-Test ($LASTEXITCODE -ne 0) 'Builder refuses overwrite of a versioned deliverable'
    & $Python (Join-Path $PSScriptRoot 'build_overlay.py') --repository $source --base $base --version bad --include '../escape.ps1' --output-dir (Join-Path $run 'bad') 2>&1 | Out-Null
    Assert-Test ($LASTEXITCODE -ne 0) 'Builder rejects traversal paths'
    $package = New-Package 'package'
    $installer = Join-Path $package 'Install-Overlay.ps1'
    $target = New-Target 'normal-target'
    # A timestamp-only difference forces ordinary git status to refresh cached index metadata.
    [IO.File]::SetLastWriteTimeUtc((Join-Path $target $a),[DateTime]::UtcNow.AddDays(-2))
    # Materialize deferred NTFS directory metadata from fixture creation before the comparison.
    $null = Get-GitMetadataSnapshot $target
    $gitBefore = Get-GitMetadataSnapshot $target
    Write-Text (Join-Path $run 'git-metadata-before.json') $gitBefore
    $dry = Invoke-Installer $target
    Assert-Test ($dry.Mode -ceq 'DryRun' -and -not (Test-Path -LiteralPath (Join-Path $target $added)) -and
        -not (Test-Path -LiteralPath (Join-Path $target '.typezero-overlay-backups')) -and
        -not (Test-Path -LiteralPath (Join-Path $target '.typezero-overlay-install.lock'))) 'Default dry-run performs no target writes'
    $gitAfterDry = Get-GitMetadataSnapshot $target
    Write-Text (Join-Path $run 'git-metadata-after-dry-run.json') $gitAfterDry
    Assert-Test ($gitAfterDry -ceq $gitBefore) 'Default dry-run preserves every Git metadata file byte and timestamp'
    $whatIf = Invoke-Installer $target @{Execute=$true;WhatIf=$true}
    Assert-Test ($whatIf.Mode -ceq 'DryRun' -and -not (Test-Path -LiteralPath (Join-Path $target $added))) 'ShouldProcess WhatIf prevents execution'
    Assert-Test ((Get-GitMetadataSnapshot $target) -ceq $gitBefore) 'Execute WhatIf preserves every Git metadata file byte and timestamp'
    $installed = Invoke-Installer $target @{Execute=$true;Confirm=$false}
    Assert-Test ($installed.Mode -ceq 'Executed' -and (Hash-File (Join-Path $target $a)) -ceq (Hash-File (Join-Path $source $a)) -and
        (Test-Path -LiteralPath (Join-Path $installed.BackupDirectory '0004-Completed.json'))) 'Explicit install writes verified payload and durable completion evidence'
    $rollbackGitBefore = Get-GitMetadataSnapshot $target
    $rollbackDry = Invoke-Installer $target @{Action='Rollback';BackupDirectory=$installed.BackupDirectory}
    Assert-Test ($rollbackDry.Mode -ceq 'DryRun' -and (Test-Path -LiteralPath (Join-Path $target $added))) 'Rollback also defaults to dry-run'
    Assert-Test ((Get-GitMetadataSnapshot $target) -ceq $rollbackGitBefore) 'Rollback dry-run preserves all Git metadata'
    $rollbackWhatIf = Invoke-Installer $target @{Action='Rollback';BackupDirectory=$installed.BackupDirectory;Execute=$true;WhatIf=$true}
    Assert-Test ($rollbackWhatIf.Mode -ceq 'DryRun' -and (Get-GitMetadataSnapshot $target) -ceq $rollbackGitBefore) 'Rollback Execute WhatIf preserves all Git metadata'
    Write-Text (Join-Path $target $b) '# unrelated concurrent user edit'
    Expect-Refusal { Invoke-Installer $target @{Action='Rollback';BackupDirectory=$installed.BackupDirectory;Execute=$true;Confirm=$false} } 'Rollback refuses concurrent edits before reverting any file'
    Assert-Test ((Test-Path -LiteralPath (Join-Path $target $added)) -and
        (Hash-File (Join-Path $target $a)) -ceq (Hash-File (Join-Path $source $a))) 'Conflict refusal preserves the other installed files'
    [IO.File]::WriteAllBytes((Join-Path $target $b),[IO.File]::ReadAllBytes((Join-Path $source $b)))
    $null = Invoke-Installer $target @{Action='Rollback';BackupDirectory=$installed.BackupDirectory;Execute=$true;Confirm=$false}
    Assert-Test ((Hash-File (Join-Path $target $a)) -ceq $baselineA -and
        (Hash-File (Join-Path $target $b)) -ceq $baselineB -and -not (Test-Path -LiteralPath (Join-Path $target $added))) 'Rollback restores exact originals and removes only exact new overlay bytes'
    $null = Invoke-Installer $target @{Action='Rollback';BackupDirectory=$installed.BackupDirectory;Execute=$true;Confirm=$false}
    Assert-Test ((Hash-File (Join-Path $target $a)) -ceq $baselineA) 'Repeated rollback is idempotent'
    $collision = New-Target 'new-file-collision'
    Write-Text (Join-Path $collision $added) '# pre-existing untracked file'
    Expect-Refusal { Invoke-Installer $collision @{Execute=$true;Confirm=$false} } 'Install refuses pre-existing new-file collisions'
    $dirty = New-Target 'dirty-target'
    Write-Text (Join-Path $dirty $a) '# local user edit'
    Expect-Refusal { Invoke-Installer $dirty } 'Install refuses dirty tracked baseline'
    $other = New-Target 'different-head'
    $null = Git-Fixture $other @('config','user.email','overlay-fixture@example.invalid')
    $null = Git-Fixture $other @('config','user.name','Disposable Overlay Fixture')
    $null = Git-Fixture $other @('commit','--quiet','--allow-empty','-m','Different HEAD')
    Expect-Refusal { Invoke-Installer $other } 'Install refuses a different baseline commit'
    $badPackage = New-Package 'payload-tamper'
    Write-Text (Join-Path $badPackage "payload/$a") '# tampered payload'
    Expect-Refusal { & (Join-Path $badPackage 'Install-Overlay.ps1') -TargetRoot $target -PackageRoot $badPackage } 'Installer rejects payload tampering'
    $traversal = New-Package 'manifest-traversal'
    $json = [IO.File]::ReadAllText((Join-Path $traversal 'overlay.json')).Replace($a,'../escape.ps1')
    Write-Text (Join-Path $traversal 'overlay.json') $json
    Expect-Refusal { & (Join-Path $traversal 'Install-Overlay.ps1') -TargetRoot $target -PackageRoot $traversal } 'Installer rejects manifest traversal before writes'
    $duplicate = New-Package 'duplicate-json'
    $duplicateText = [IO.File]::ReadAllText((Join-Path $duplicate 'overlay.json'))
    $json = $duplicateText.Replace('"SchemaVersion": 2,','"SchemaVersion": 2, "schemaVersion": 2,')
    if ($json -ceq $duplicateText) { throw 'Duplicate-property test did not mutate the actual manifest.' }
    Write-Text (Join-Path $duplicate 'overlay.json') $json
    Expect-Refusal { & (Join-Path $duplicate 'Install-Overlay.ps1') -TargetRoot $target -PackageRoot $duplicate } 'Installer rejects duplicate or case-colliding JSON names'
    # Exercise actual JSON decoding and row construction, not just a hash-comparison helper.
    # The valid package above contains both existing-file string hashes and a new-file JSON null.
    $invalidRows = @(
        @{Name='array-before';Field='BeforeSha256';Value=@($baselineA);RowPath=$a},
        @{Name='empty-before';Field='BeforeSha256';Value='';RowPath=$a},
        @{Name='number-before';Field='BeforeSha256';Value=0;RowPath=$a},
        @{Name='boolean-before';Field='BeforeSha256';Value=$false;RowPath=$a},
        @{Name='null-existing';Field='BeforeSha256';Value=$null;RowPath=$a},
        @{Name='hash-added';Field='BeforeSha256';Value=$baselineA;RowPath=$added},
        @{Name='array-path';Field='Path';Value=@($a);RowPath=$a},
        @{Name='string-length';Field='Length';Value='14';RowPath=$a},
        @{Name='null-length';Field='Length';Value=$null;RowPath=$a},
        @{Name='array-after';Field='AfterSha256';Value=@(('A'*64));RowPath=$a}
    )
    foreach ($invalidRow in $invalidRows) {
        $badRows = New-Package ('row-contract-' + $invalidRow.Name)
        $badManifestPath = Join-Path $badRows 'overlay.json'
        $badManifest = [IO.File]::ReadAllText($badManifestPath) | ConvertFrom-Json -AsHashtable
        $badManifestRow = @($badManifest['Files'] | Where-Object { $_['Path'] -ceq $invalidRow.RowPath })[0]
        $badManifestRow[$invalidRow.Field] = $invalidRow.Value
        Write-Text $badManifestPath (ConvertTo-Json -InputObject $badManifest -Depth 24)
        Expect-Refusal { & (Join-Path $badRows 'Install-Overlay.ps1') -TargetRoot $target -PackageRoot $badRows } "Installer refuses malformed or mismatched row $($invalidRow.Name)"
        Assert-Test ((Hash-File (Join-Path $target $a)) -ceq $baselineA -and
            (Hash-File (Join-Path $target $b)) -ceq $baselineB -and -not (Test-Path -LiteralPath (Join-Path $target $added))) "Row refusal $($invalidRow.Name) preserves exact target baseline"
    }
    $hardlink = New-Target 'hardlink-target'
    $linked = Join-Path $hardlink 'hardlink-evidence.ps1'
    $hardlinkCreated = $false
    try { $null = New-Item -ItemType HardLink -Path $linked -Target (Join-Path $hardlink $a); $hardlinkCreated = $true }
    catch { Record-UnavailableLinkCreation $_ 'Installer rejects hard-linked target files' }
    if ($hardlinkCreated) { Expect-Refusal { Invoke-Installer $hardlink } 'Installer rejects hard-linked target files' }
    $junction = New-Target 'junction-target'
    $moved = Join-Path $junction 'engine-evidence'
    Move-Item -LiteralPath (Join-Path $junction $engine) -Destination $moved
    $junctionCreated = $false
    try { $null = New-Item -ItemType Junction -Path (Join-Path $junction $engine) -Target $moved; $junctionCreated = $true }
    catch { Record-UnavailableLinkCreation $_ 'Installer rejects junction/reparse ancestors' }
    if ($junctionCreated) { Expect-Refusal { Invoke-Installer $junction } 'Installer rejects junction/reparse ancestors' }
    $locked = New-Target 'concurrent-installer'
    $handle = [IO.File]::Open((Join-Path $locked '.typezero-overlay-install.lock'),[IO.FileMode]::CreateNew,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
    try { Expect-Refusal { Invoke-Installer $locked @{Execute=$true;Confirm=$false} } 'Concurrent installer lock refuses a second writer' }
    finally { $handle.Dispose() }
    $crashTarget = New-Target 'interrupted-target'
    $worker = Join-Path $run 'interrupt-worker.ps1'
    $quotedInstaller = $installer.Replace("'","''")
    $quotedTarget = $crashTarget.Replace("'","''")
    $quotedPackage = $package.Replace("'","''")
    Write-Text $worker "& '$quotedInstaller' -TargetRoot '$quotedTarget' -PackageRoot '$quotedPackage' -Execute -Confirm:`$false -FixturePauseAfterWrite 2`n"
    $proc = Start-Process -FilePath (Get-Process -Id $PID).Path -ArgumentList @('-NoLogo','-NoProfile','-File',('"' + $worker + '"')) -WindowStyle Hidden -PassThru
    try {
        $deadline = [DateTime]::UtcNow.AddSeconds(30)
        $paused = $null
        do {
            $paused = Get-ChildItem -LiteralPath (Join-Path $crashTarget '.typezero-overlay-backups') -Filter 'fixture-pause.ready' -File -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($paused) { break }
            if ($proc.HasExited) { throw 'Interruption worker exited before its durable pause barrier.' }
            Start-Sleep -Milliseconds 50
        } while ([DateTime]::UtcNow -lt $deadline)
        if (-not $paused) { throw 'Interruption worker timed out.' }
        Stop-Process -Id $proc.Id -Force
        $proc.WaitForExit()
        $interruptedBackup = $paused.Directory.FullName
        Assert-Test ((Test-Path -LiteralPath (Join-Path $interruptedBackup '0000-Prepared.json')) -and
            -not (Test-Path -LiteralPath (Join-Path $interruptedBackup '0004-Completed.json'))) 'Killed process retains durable plan/backups without false completion'
        $null = Invoke-Installer $crashTarget @{Action='Rollback';BackupDirectory=$interruptedBackup;Execute=$true;Confirm=$false}
        Assert-Test ((Hash-File (Join-Path $crashTarget $a)) -ceq $baselineA -and
            (Hash-File (Join-Path $crashTarget $b)) -ceq $baselineB -and -not (Test-Path -LiteralPath (Join-Path $crashTarget $added))) 'Fresh installer recovers a killed partial install from exact backup/payload hashes'
        $planPath = Join-Path $interruptedBackup 'plan.json'
        Write-Text $planPath ([IO.File]::ReadAllText($planPath).Replace($base,('0'*40)))
        Expect-Refusal { Invoke-Installer $crashTarget @{Action='Rollback';BackupDirectory=$interruptedBackup} } 'Rollback refuses tampered backup plan'
    } finally { if (-not $proc.HasExited) { Stop-Process -Id $proc.Id -Force }; $proc.Dispose() }
    $unavailable = @($results.ToArray() | Where-Object { $_.PSObject.Properties.Name -contains 'Unavailable' -and $_.Unavailable })
    $report = [ordered]@{SchemaVersion=1;Status=if($unavailable.Count){'PassedWithUnavailableChecks'}else{'Passed'};
        Completed=($unavailable.Count -eq 0);Assertions=(@($results.ToArray() | Where-Object Passed).Count);
        UnavailableChecks=@($unavailable);FixtureRoot=$run;
        Runtime=$PSVersionTable.PSVersion.ToString();Tests=@($results.ToArray());ProductionPathsAccessed=$false}
    if ($ReportPath) {
        $reportFile = [IO.Path]::GetFullPath($ReportPath)
        $stream = [IO.File]::Open($reportFile,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
        try { $bytes=$utf8.GetBytes(($report | ConvertTo-Json -Depth 8));$stream.Write($bytes);$stream.Flush($true) } finally { $stream.Dispose() }
    }
    [pscustomobject]$report
} catch {
    Write-Error "Overlay fixtures failed; retained evidence at $run. $($_.Exception.Message)" -ErrorAction Continue
    throw
}
