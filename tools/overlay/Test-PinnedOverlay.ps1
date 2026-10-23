#requires -Version 7.3
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Repository,
    [Parameter(Mandatory)][string]$Archive,
    [Parameter(Mandatory)][string]$WorkRoot,
    [string]$OriginalArchive,
    [string]$ReportPath
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if (-not $IsWindows) { throw 'Pinned overlay regression requires Windows.' }
$pinned = '88fd5525bdfe821d65b9a053d51ed1354f7fd1da'
$durablePath = 'Netzach/PowerShell/ThemeEngine/TerminalTransactionV2Durable-WindowsTerminal.ps1'
$pythonPath = 'tools/overlay/build_overlay.py'
$run = Join-Path ([IO.Path]::GetFullPath($WorkRoot)) ('pinned-overlay-' + [guid]::NewGuid().ToString('N'))
$null = [IO.Directory]::CreateDirectory($run)
$checks = [Collections.Generic.List[object]]::new()
$utf8 = [Text.UTF8Encoding]::new($false,$true)
$oldAttr = [Environment]::GetEnvironmentVariable('GIT_ATTR_NOSYSTEM','Process')
function Test-Check([bool]$Condition,[string]$Name) {
    if (-not $Condition) { throw "FAILED: $Name" }
    $script:checks.Add([pscustomobject]@{Name=$Name;Passed=$true})
}
function Test-Git([string]$Target,[string[]]$Arguments) {
    $lines = & git --no-optional-locks -C $Target @Arguments 2>&1
    if ($LASTEXITCODE -ne 0) { throw "Fixture Git failed: $lines" }
    return ($lines -join "`n").Trim()
}
function Test-Hash([string]$Path) {
    if ([IO.Directory]::Exists($Path)) { throw "Unexpected directory: $Path" }
    if ([IO.File]::Exists($Path)) { return [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([IO.File]::ReadAllBytes($Path))) }
    return $null
}
function Test-EqualHash($Expected,$Actual) {
    if ($null -eq $Expected) { return $null -eq $Actual }
    return $Actual -is [string] -and [StringComparer]::Ordinal.Equals($Expected,$Actual)
}
function Test-AuditRows([string]$Target,$Manifest) {
    $audit = foreach ($row in $Manifest['Files']) {
        $path = [IO.Path]::GetFullPath((Join-Path $Target $row['Path']))
        $actual = Test-Hash $path
        [ordered]@{Path=$row['Path'];ResolvedPath=$path;Expected=$row['BeforeSha256'];Actual=$actual;
            Equal=(Test-EqualHash $row['BeforeSha256'] $actual);
            ExpectedType=if($null -eq $row['BeforeSha256']){'null'}else{$row['BeforeSha256'].GetType().FullName};
            ActualType=if($null -eq $actual){'null'}else{$actual.GetType().FullName}}
    }
    return ,@($audit)
}
function Test-GitSnapshot([string]$Target) {
    $gitDir = Test-Git $Target @('rev-parse','--path-format=absolute','--git-dir')
    $commonDir = Test-Git $Target @('rev-parse','--path-format=absolute','--git-common-dir')
    $items = [Collections.Generic.Dictionary[string,object]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($folder in (@($gitDir,$commonDir) | Select-Object -Unique)) {
        foreach ($item in (@((Get-Item -Force -LiteralPath $folder)) + @(Get-ChildItem -Force -Recurse -LiteralPath $folder))) {
            $items[$item.FullName] = $item
        }
    }
    $pointer = Get-Item -Force -LiteralPath (Join-Path $Target '.git')
    $items[$pointer.FullName] = $pointer
    $data = foreach ($item in ($items.Values | Sort-Object FullName)) {
        [ordered]@{Path=$item.FullName;Directory=$item.PSIsContainer;
            Sha256=if($item.PSIsContainer){$null}else{Test-Hash $item.FullName};
            Length=if($item.PSIsContainer){0}else{$item.Length};
            CreationTicks=$item.CreationTimeUtc.Ticks;WriteTicks=$item.LastWriteTimeUtc.Ticks;
            Attributes=[int]$item.Attributes}
    }
    return ConvertTo-Json -InputObject @($data) -Depth 6 -Compress
}
function Test-Refusal([string]$Installer,[string]$Target,[string]$Package,[bool]$WhatIfMode) {
    try {
        if ($WhatIfMode) { & $Installer -TargetRoot $Target -PackageRoot $Package -Execute -WhatIf | Out-Null }
        else { & $Installer -TargetRoot $Target -PackageRoot $Package | Out-Null }
        return [ordered]@{Refused=$false;Message=$null;TargetRoot=$Target;WhatIf=$WhatIfMode}
    } catch {
        return [ordered]@{Refused=$true;Message=$_.Exception.Message;TargetRoot=$Target;WhatIf=$WhatIfMode;
            ScriptLine=$_.InvocationInfo.ScriptLineNumber;Runtime=$PSVersionTable.PSVersion.ToString()}
    }
}
function Test-NewWorktree([string]$Name) {
    $target = Join-Path $script:run $Name
    $null = Test-Git $script:privateRepository @('worktree','add','--quiet','--detach',$target,$script:pinned)
    Test-Check ((Test-Git $target @('rev-parse','HEAD')) -ceq $script:pinned) "$Name is a fresh exact pinned detached worktree"
    Test-Check (-not (Get-Item -Force -LiteralPath (Join-Path $target '.git')).PSIsContainer) "$Name uses a real linked worktree Git pointer"
    Test-Check ((Test-Git $target @('rev-parse','--abbrev-ref','HEAD')) -ceq 'HEAD') "$Name is detached"
    return $target
}
try {
    [Environment]::SetEnvironmentVariable('GIT_ATTR_NOSYSTEM','1','Process')
    $repositoryPath = [IO.Path]::GetFullPath($Repository)
    $archivePath = [IO.Path]::GetFullPath($Archive)
    $package = Join-Path $run 'package'
    Expand-Archive -LiteralPath $archivePath -DestinationPath $package
    $installer = Join-Path $package 'Install-Overlay.ps1'
    $manifest = [IO.File]::ReadAllText((Join-Path $package 'overlay.json')) | ConvertFrom-Json -AsHashtable
    Test-Check ($manifest['SchemaVersion'] -eq 2 -and $manifest['BaselineByteProfile'] -ceq 'TypezeroPinnedCheckoutLF-v1' -and
        $manifest['BaselineCommit'] -ceq $pinned) 'Release manifest declares schema 2, exact commit and explicit baseline byte profile'
    Test-Check ($manifest['Files'].Count -ge 9) 'Complete release payload includes at least all nine original manifest paths'
    Test-Check ((Test-Hash $installer) -ceq $manifest['InstallerSha256']) 'Top-level installer matches manifest SHA-256'
    foreach ($row in $manifest['Files']) {
        $payload = Join-Path (Join-Path $package 'payload') $row['Path']
        Test-Check ((Test-Hash $payload) -ceq $row['AfterSha256'] -and (Get-Item -LiteralPath $payload).Length -eq $row['Length']) "Payload independently verified: $($row['Path'])"
    }
    # A private repository with a read-only alternate object store creates its own metadata;
    # the supplied source repository and its existing worktrees are never changed.
    $privateRepository = Join-Path $run 'fixture-repository'
    $sourceCommon = Test-Git $repositoryPath @('rev-parse','--path-format=absolute','--git-common-dir')
    $initialized = & git --no-optional-locks -c core.hooksPath=NUL init --quiet $privateRepository 2>&1
    if ($LASTEXITCODE -ne 0) { throw "Private local fixture initialization failed: $initialized" }
    $alternates = Join-Path $privateRepository '.git/objects/info/alternates'
    $alternateBytes = $utf8.GetBytes(([IO.Path]::GetFullPath((Join-Path $sourceCommon 'objects')).Replace('\','/')) + "`n")
    $alternateStream = [IO.File]::Open($alternates,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
    try { $alternateStream.Write($alternateBytes);$alternateStream.Flush($true) } finally { $alternateStream.Dispose() }
    foreach ($setting in @(@('core.autocrlf','false'),@('core.eol','lf'),@('core.attributesfile','NUL'),@('core.hooksPath','NUL'))) {
        $null = Test-Git $privateRepository @('config','--local',$setting[0],$setting[1])
    }
    $null = Test-Git $privateRepository @('update-ref','refs/heads/typezero-pinned-fixture',$pinned)
    $target = Test-NewWorktree 'exact-review-target'
    $wrongTarget = Test-NewWorktree 'different-actual-target'
    $durableTargetPath = Join-Path $wrongTarget $durablePath
    $durableLf = $utf8.GetString([IO.File]::ReadAllBytes($durableTargetPath)).Replace("`r`n","`n")
    [IO.File]::WriteAllBytes($durableTargetPath,$utf8.GetBytes($durableLf))
    # Fixture setup refreshes the normalized index entry without changing its pinned blob.
    # This models a Git-clean LF checkout; the installer must still refuse its wrong bytes.
    $null = Test-Git $wrongTarget @('add','--',$durablePath)
    Test-Check (-not (Test-Git $wrongTarget @('diff','--cached','--name-only','HEAD'))) 'Different-target setup retains exactly the pinned index content'
    Test-Check (-not (Test-Git $wrongTarget @('status','--porcelain','--untracked-files=no'))) 'LF durable-module target remains Git-normalized clean but differs from required checkout bytes'
    $audit = Test-AuditRows $target $manifest
    Test-Check (@($audit | Where-Object { -not $_.Equal }).Count -eq 0) 'Every corrected manifest baseline state independently matches the fresh exact target'
    $wrongAudit = Test-AuditRows $wrongTarget $manifest
    Test-Check (@($wrongAudit | Where-Object { -not $_.Equal }).Count -eq 1 -and
        @($wrongAudit | Where-Object { -not $_.Equal })[0].Path -ceq $durablePath) 'Different actual target has exactly one strict durable-module byte mismatch'
    $original = $null
    if ($OriginalArchive) {
        $oldPackage = Join-Path $run 'original-package'
        Expand-Archive -LiteralPath ([IO.Path]::GetFullPath($OriginalArchive)) -DestinationPath $oldPackage
        $oldInstaller = Join-Path $oldPackage 'Install-Overlay.ps1'
        $oldManifest = [IO.File]::ReadAllText((Join-Path $oldPackage 'overlay.json')) | ConvertFrom-Json -AsHashtable
        $oldAudit = Test-AuditRows $target $oldManifest
        $oldWrongAudit = Test-AuditRows $wrongTarget $oldManifest
        $oldMismatches = @($oldAudit | Where-Object { -not $_.Equal })
        Test-Check ($oldMismatches.Count -eq 1 -and $oldMismatches[0].Path -ceq $pythonPath) 'Original ZIP on correct NETZACH byte profile differs only at Python baseline'
        $correctDry = Test-Refusal $oldInstaller $target $oldPackage $false
        $correctWhatIf = Test-Refusal $oldInstaller $target $oldPackage $true
        Test-Check ($correctDry.Refused -and $correctWhatIf.Refused -and $correctDry.Message.Contains($pythonPath) -and
            $correctWhatIf.Message.Contains($pythonPath)) 'Original dry-run and WhatIf reject the actual Python mismatch on the correct target'
        $wrongDry = Test-Refusal $oldInstaller $wrongTarget $oldPackage $false
        $wrongWhatIf = Test-Refusal $oldInstaller $wrongTarget $oldPackage $true
        Test-Check ($wrongDry.Refused -and $wrongWhatIf.Refused -and $wrongDry.Message.Contains($durablePath) -and
            $wrongWhatIf.Message.Contains($durablePath)) 'Original line-205 durable rejection reproduces when invocation targets different LF-module worktree'
        $original = [ordered]@{ArchiveSha256=(Test-Hash ([IO.Path]::GetFullPath($OriginalArchive)));CorrectTargetAudit=$oldAudit;
            DifferentTargetAudit=$oldWrongAudit;CorrectDryRun=$correctDry;CorrectWhatIf=$correctWhatIf;
            DifferentDryRun=$wrongDry;DifferentWhatIf=$wrongWhatIf}
    }
    $wrongRefusal = Test-Refusal $installer $wrongTarget $package $false
    Test-Check ($wrongRefusal.Refused -and $wrongRefusal.Message.Contains($durablePath)) 'Corrected installer preserves strict rejection of the different actual target'
    # Force an index stat-cache refresh opportunity; snapshots include private/common Git dirs and pointer.
    [IO.File]::SetLastWriteTimeUtc((Join-Path $target $durablePath),[DateTime]::UtcNow.AddDays(-2))
    $null = Test-GitSnapshot $target
    $before = Test-GitSnapshot $target
    $dry = & $installer -TargetRoot $target -PackageRoot $package
    Test-Check ($dry.Mode -ceq 'DryRun' -and (Test-GitSnapshot $target) -ceq $before) 'Full artifact default dry-run preserves all linked-worktree Git metadata bytes and timestamps'
    $whatIf = & $installer -TargetRoot $target -PackageRoot $package -Execute -WhatIf
    Test-Check ($whatIf.Mode -ceq 'DryRun' -and (Test-GitSnapshot $target) -ceq $before) 'Full artifact Execute WhatIf preserves all linked-worktree Git metadata bytes and timestamps'
    Test-Check (-not [IO.Directory]::Exists((Join-Path $target '.typezero-overlay-backups')) -and
        -not [IO.File]::Exists((Join-Path $target '.typezero-overlay-install.lock'))) 'Full artifact previews create no target backup or lock'
    $installed = & $installer -TargetRoot $target -PackageRoot $package -Execute -Confirm:$false
    Test-Check ($installed.Mode -ceq 'Executed') 'Full artifact installation executes against fresh exact baseline'
    foreach ($row in $manifest['Files']) {
        Test-Check ((Test-Hash (Join-Path $target $row['Path'])) -ceq $row['AfterSha256']) "Installed full artifact hash matches: $($row['Path'])"
    }
    $rollbackBefore = Test-GitSnapshot $target
    $rollbackDry = & $installer -TargetRoot $target -PackageRoot $package -Action Rollback -BackupDirectory $installed.BackupDirectory
    Test-Check ($rollbackDry.Mode -ceq 'DryRun' -and (Test-GitSnapshot $target) -ceq $rollbackBefore) 'Full artifact rollback dry-run preserves linked-worktree metadata'
    $rollbackWhatIf = & $installer -TargetRoot $target -PackageRoot $package -Action Rollback -BackupDirectory $installed.BackupDirectory -Execute -WhatIf
    Test-Check ($rollbackWhatIf.Mode -ceq 'DryRun' -and (Test-GitSnapshot $target) -ceq $rollbackBefore) 'Full artifact rollback WhatIf preserves linked-worktree metadata'
    $rolledBack = & $installer -TargetRoot $target -PackageRoot $package -Action Rollback -BackupDirectory $installed.BackupDirectory -Execute -Confirm:$false
    Test-Check ($rolledBack.Mode -ceq 'Executed') 'Full artifact rollback executes with bound exact backups'
    $rollbackAudit = Test-AuditRows $target $manifest
    Test-Check (@($rollbackAudit | Where-Object { -not $_.Equal }).Count -eq 0) 'Rollback restores every baseline hash and removes only added overlay files'
    Test-Check (-not (Test-Git $target @('diff','--name-only','HEAD'))) 'Rollback preserves exact pinned tracked content'
    $repeated = & $installer -TargetRoot $target -PackageRoot $package -Action Rollback -BackupDirectory $installed.BackupDirectory -Execute -Confirm:$false
    Test-Check ($repeated.Mode -ceq 'Executed' -and @((Test-AuditRows $target $manifest) | Where-Object { -not $_.Equal }).Count -eq 0) 'Full artifact repeated rollback is idempotent'
    $report = [ordered]@{SchemaVersion=1;Status='Passed';Assertions=$checks.Count;Runtime=$PSVersionTable.PSVersion.ToString();
        DotNet=[Environment]::Version.ToString();ArchiveSha256=(Test-Hash $archivePath);BaselineCommit=$pinned;
        BaselineByteProfile=$manifest['BaselineByteProfile'];Files=$manifest['Files'].Count;FixtureRoot=$run;
        ActualTarget=$target;DifferentTarget=$wrongTarget;BaselineAudit=$audit;DifferentTargetAudit=$wrongAudit;
        OriginalPackage=$original;DifferentTargetRefusal=$wrongRefusal;BackupDirectory=$installed.BackupDirectory;
        RollbackAudit=$rollbackAudit;Checks=$checks.ToArray();ProductionSettingsAccessed=$false;SourceRepositoryModified=$false}
    if ($ReportPath) {
        $stream = [IO.File]::Open([IO.Path]::GetFullPath($ReportPath),[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
        try { $bytes=$utf8.GetBytes((ConvertTo-Json -InputObject $report -Depth 20));$stream.Write($bytes);$stream.Flush($true) } finally { $stream.Dispose() }
    }
    [pscustomobject]$report
} catch {
    Write-Error "Pinned overlay fixtures failed; evidence preserved at $run. $($_.Exception.Message)" -ErrorAction Continue
    throw
} finally {
    [Environment]::SetEnvironmentVariable('GIT_ATTR_NOSYSTEM',$oldAttr,'Process')
}
