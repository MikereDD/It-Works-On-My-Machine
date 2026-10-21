#requires -Version 7.3
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$WorkRoot,
    [string]$ReportPath,
    [string]$Python = 'python'
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
function Expect-Refusal([scriptblock]$Call,[string]$Name) {
    $refused = $false
    try { & $Call | Out-Null } catch { $refused = $true }
    Assert-Test $refused $Name
}
function New-Target([string]$Name) {
    $target = Join-Path $script:run $Name
    & git clone --quiet --no-hardlinks $script:source $target 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Fixture clone failed.' }
    $null = Git-Fixture $target @('remote','remove','origin')
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
    Write-Text (Join-Path $source '.gitattributes') "*.ps1 -text`n"
    Write-Text (Join-Path $source $a) "# baseline-a`n"
    Write-Text (Join-Path $source $b) "# baseline-b`n"
    $null = Git-Fixture $source @('init','--quiet')
    $null = Git-Fixture $source @('config','user.email','overlay-fixture@example.invalid')
    $null = Git-Fixture $source @('config','user.name','Disposable Overlay Fixture')
    $null = Git-Fixture $source @('add','.')
    $null = Git-Fixture $source @('commit','--quiet','-m','Disposable baseline')
    $base = Git-Fixture $source @('rev-parse','HEAD')
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
    $dry = Invoke-Installer $target
    Assert-Test ($dry.Mode -ceq 'DryRun' -and -not (Test-Path -LiteralPath (Join-Path $target $added)) -and
        -not (Test-Path -LiteralPath (Join-Path $target '.typezero-overlay-backups')) -and
        -not (Test-Path -LiteralPath (Join-Path $target '.typezero-overlay-install.lock'))) 'Default dry-run performs no target writes'
    $whatIf = Invoke-Installer $target @{Execute=$true;WhatIf=$true}
    Assert-Test ($whatIf.Mode -ceq 'DryRun' -and -not (Test-Path -LiteralPath (Join-Path $target $added))) 'ShouldProcess WhatIf prevents execution'
    $installed = Invoke-Installer $target @{Execute=$true;Confirm=$false}
    Assert-Test ($installed.Mode -ceq 'Executed' -and (Hash-File (Join-Path $target $a)) -ceq (Hash-File (Join-Path $source $a)) -and
        (Test-Path -LiteralPath (Join-Path $installed.BackupDirectory '0004-Completed.json'))) 'Explicit install writes verified payload and durable completion evidence'
    $rollbackDry = Invoke-Installer $target @{Action='Rollback';BackupDirectory=$installed.BackupDirectory}
    Assert-Test ($rollbackDry.Mode -ceq 'DryRun' -and (Test-Path -LiteralPath (Join-Path $target $added))) 'Rollback also defaults to dry-run'
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
    $json = [IO.File]::ReadAllText((Join-Path $duplicate 'overlay.json')).Replace('"SchemaVersion": 1,','"SchemaVersion": 1, "schemaVersion": 1,')
    Write-Text (Join-Path $duplicate 'overlay.json') $json
    Expect-Refusal { & (Join-Path $duplicate 'Install-Overlay.ps1') -TargetRoot $target -PackageRoot $duplicate } 'Installer rejects duplicate or case-colliding JSON names'
    $hardlink = New-Target 'hardlink-target'
    $linked = Join-Path $hardlink 'hardlink-evidence.ps1'
    $null = New-Item -ItemType HardLink -Path $linked -Target (Join-Path $hardlink $a)
    Expect-Refusal { Invoke-Installer $hardlink } 'Installer rejects hard-linked target files'
    $junction = New-Target 'junction-target'
    $moved = Join-Path $junction 'engine-evidence'
    Move-Item -LiteralPath (Join-Path $junction $engine) -Destination $moved
    $null = New-Item -ItemType Junction -Path (Join-Path $junction $engine) -Target $moved
    Expect-Refusal { Invoke-Installer $junction } 'Installer rejects junction/reparse ancestors'
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
    $report = [ordered]@{SchemaVersion=1;Status='Passed';Assertions=$results.Count;FixtureRoot=$run;
        Runtime=$PSVersionTable.PSVersion.ToString();Tests=@($results.ToArray());ProductionPathsAccessed=$false}
    if ($ReportPath) {
        $reportFile = [IO.Path]::GetFullPath($ReportPath)
        $stream = [IO.File]::Open($reportFile,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
        try { $bytes=$utf8.GetBytes(($report | ConvertTo-Json -Depth 8));$stream.Write($bytes);$stream.Flush($true) } finally { $stream.Dispose() }
    }
    [pscustomobject]$report
} catch {
    Write-Error "Overlay fixtures failed; retained evidence at $run. $($_.Exception.Message)"
    throw
}
